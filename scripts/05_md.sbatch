#!/bin/bash
#===============================================================================
# 05_md.sbatch - Production MD (GPU)
# Submit from project directory: sbatch scripts/05_md.sbatch
#===============================================================================

#--- ALPINE  -----------------------------------
#SBATCH --account=YOUR_ACCOUNT
#SBATCH --partition=aa100
#SBATCH --qos=normal
#SBATCH --time=23:59:00

#--- FIJI ---------------------------------------
##SBATCH --partition=nvidia-a100
##SBATCH --qos=normal
##SBATCH --time=47:59:00
##SBATCH --nodelist=fijigpu-04

#--- BLANCA (preemptable) ----------------------
##SBATCH --account=blanca-biokem
##SBATCH --partition=blanca
##SBATCH --qos=preemptable
##SBATCH --time=23:59:00
##SBATCH --requeue                # auto-requeue on preemption (resumes from md.cpt)
##SBATCH --constraint="A100|L40|A40"  # fast Ampere/Ada nodes only; excludes Blackwell sm_120 (CUDA #209) + Hopper sm_90 (untested) + slow V100/T4/P100/Quadro-RTX6000

#--- BLANCA-BIOKEM ----------------------------
##SBATCH --account=blanca-biokem
##SBATCH --partition=blanca-biokem
##SBATCH --qos=blanca-biokem
##SBATCH --time=23:59:00

#--- COMMON RESOURCES -------------------------
#SBATCH --job-name=05_md_[SYSTEM]
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --gres=gpu:1
#SBATCH --mem=16gb
#SBATCH --output=logs/05_md_%j.out
#SBATCH --error=logs/05_md_%j.err
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=YOUR_EMAIL@example.com

set -e  # Exit immediately on any error

# ============== Configuration ==============
# Less than SBATCH time limit (in hours) to allow GROMACS to close files before SLURM ends. 
#MAXH="23.5" # For Alpine / Blanca (24h limit)
#MAXH="47.5" # For FIJI (48h limit)

if [ -z "${MAXH}" ]; then
    echo "ERROR: MAXH is not set"
    exit 1
fi

# ============== Set Environment ==============
# CURC:     source "${SLURM_SUBMIT_DIR}/envs/env_curc.sh"
# FIJI:     source "${SLURM_SUBMIT_DIR}/envs/env_fiji_GPU.sh"

export OMP_NUM_THREADS="${SLURM_CPUS_PER_TASK}"
export GMX_GPU_DD_COMMS=true
export GMX_GPU_PME_PP_COMMS=true
export GMX_FORCE_UPDATE_DEFAULT_GPU=true

# ============== Path normalization of SLURM_SUBMIT_DIR for CURC cluster ==============
# Normalize SLURM_SUBMIT_DIR for avoiding GROMACS md.cpt path equality check failures on CURC compute nodes (only for CURC systems)
#SLURM_SUBMIT_DIR="${SLURM_SUBMIT_DIR//\/gpfs\/alpine1\/scratch\//\/scratch\/alpine\/}"

# ============== Directories ==============
PRJ_DIR="${SLURM_SUBMIT_DIR}"
MD_DIR="${PRJ_DIR}/05_md"
cd "${PRJ_DIR}"

echo "=============================================="
echo "Job ID:            ${SLURM_JOB_ID}"
echo "Running on:        $(hostname)"
echo "Started at:        $(date)"
echo "Project directory: ${PRJ_DIR}"
echo "GPU(s) visible:    ${CUDA_VISIBLE_DEVICES:-(unset)}"
echo "GPU hardware:      $(nvidia-smi --query-gpu=name,compute_cap,driver_version --format=csv,noheader 2>/dev/null | head -1 || echo '(nvidia-smi unavailable)')"
echo "MAXH:              ${MAXH}"
echo "=============================================="

# ============== Check Prerequisites ==============
if [ ! -f "${MD_DIR}/md.tpr" ]; then
    echo "ERROR: md.tpr not found in ${MD_DIR}. Run NPT equilibration first."
    exit 1
fi

# ============== Run Production MD ==============
echo ""
echo "Running production MD..."
echo "------------------------"

# Set +e to allow continuation even if mdrun exits with non-zero (e.g. due to reaching MAXH)
set +e

# Check for existing checkpoint (for continuation runs)
if [ -f "${MD_DIR}/md.cpt" ]; then
    echo "Continuing from existing checkpoint."
    gmx mdrun -deffnm "${MD_DIR}/md" \
                -ntomp "${SLURM_CPUS_PER_TASK}" \
                -nb gpu -bonded gpu -pme gpu -update gpu \
                -cpi "${MD_DIR}/md.cpt" \
                -cpo "${MD_DIR}/md.cpt" \
                -append \
                -maxh "${MAXH}"
else
    echo "Starting new production run."
    gmx mdrun -deffnm "${MD_DIR}/md" \
                -ntomp "${SLURM_CPUS_PER_TASK}" \
                -nb gpu -bonded gpu -pme gpu -update gpu \
                -cpo "${MD_DIR}/md.cpt" \
                -maxh "${MAXH}"
fi

# Capture exit code of mdrun and set -e so it exists on any subsequent error
MDRUN_EXIT=$?
set -e

# ============== Decide: completed, resubmit, or fail ==============

# Failed (non-zero exit code)
if [ "${MDRUN_EXIT}" -ne 0 ]; then
    echo ""
    echo "=============================================="
    echo "ERROR: gmx mdrun exited with code ${MDRUN_EXIT} at: $(date)"
    echo "Likely causes: out-of-memory (137), segfault (139), GPU error,"
    echo "file-lock conflict, or invalid input. Inspect ${MD_DIR}/md.log"
    echo "and the SLURM error stream before retrying."
    echo "Not resubmitting (would fail again with the same root cause)."
    echo "=============================================="
    grep "Performance:" "${MD_DIR}/md.log" 2>/dev/null || true
    exit "${MDRUN_EXIT}"
fi

# Completed (md.gro exists)
if [ -f "${MD_DIR}/md.gro" ]; then
    echo ""
    echo "=============================================="
    echo "Simulation completed at: $(date)"
    echo "=============================================="
    grep "Performance:" "${MD_DIR}/md.log" 2>/dev/null || true
    echo "Next steps:"
    echo "  1. Plot energies (05_md/md.edr)"
    echo "  2. Process trajectory (05_md/md.xtc) by: sbatch scripts/06_trajectory.sbatch"
    echo "=============================================="
    exit 0
fi

# Resubmit (no md.gro but mdrun exited successfully, likely due to reaching MAXH)
RESUBMIT_LOG="${MD_DIR}/.resubmit_count"
RESUBMIT_COUNT=$(cat "${RESUBMIT_LOG}" 2>/dev/null || echo 0)
RESUBMIT_MAX=20
if [ "${RESUBMIT_COUNT}" -ge "${RESUBMIT_MAX}" ]; then
    echo ""
    echo "=============================================="
    echo "ERROR: Hit max ${RESUBMIT_MAX} resubmits without completing."
    echo "Investigate ${MD_DIR}/md.log; delete ${RESUBMIT_LOG} to retry."
    echo "=============================================="
    exit 1
fi
echo $((RESUBMIT_COUNT + 1)) > "${RESUBMIT_LOG}"

echo ""
echo "=============================================="
echo "Simulation hit -maxh wall-time at: $(date)"
echo "Resubmit $((RESUBMIT_COUNT + 1))/${RESUBMIT_MAX} — submitting continuation"
echo "=============================================="
grep "Performance:" "${MD_DIR}/md.log" 2>/dev/null || true
sbatch --dependency=afterany:"${SLURM_JOB_ID}" \
       --chdir="${SLURM_SUBMIT_DIR}" \
       "${SLURM_SUBMIT_DIR}/scripts/05_md.sbatch"

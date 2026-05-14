#!/bin/bash
#===============================================================================
# 05_md_extend.sbatch - Extend a completed Production MD by EXTEND_PS picoseconds
# Submit from project directory: sbatch scripts/05_md_extend.sbatch
#
# Prerequisites: 05_md/md.tpr, 05_md/md.gro, 05_md/md.cpt all present (i.e.,
# the original 05_md.sbatch run finished cleanly). The extension appends to
# the existing md.xtc / md.log / md.edr — final result is one continuous
# trajectory covering the full extended length. The original md.gro is
# preserved as md_pre_extend.gro before the extension launches.
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
##SBATCH --requeue
##SBATCH --constraint="A100|L40|A40"  # fast Ampere/Ada nodes only; excludes Blackwell sm_120 (CUDA #209) + Hopper sm_90 (untested) + slow V100/T4/P100/Quadro-RTX6000

#--- BLANCA-BIOKEM ----------------------------
##SBATCH --account=blanca-biokem
##SBATCH --partition=blanca-biokem
##SBATCH --qos=blanca-biokem
##SBATCH --time=23:59:00

#--- COMMON RESOURCES -------------------------
#SBATCH --job-name=05_md_extend_[SYSTEM]
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --gres=gpu:1
#SBATCH --mem=16gb
#SBATCH --output=logs/05_md_extend_%j.out
#SBATCH --error=logs/05_md_extend_%j.err
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

# Extension length in picoseconds. Default 1000000 ps = 1 µs additional.
# Edit per use; total trajectory length will be (original) + EXTEND_PS.
EXTEND_PS=1000000

# ============== Set Environment ==============
# CURC (Alpine, Blanca preemptable, Blanca-biokem): source "${SLURM_SUBMIT_DIR}/envs/env_curc.sh"
# FIJI:                                              source "${SLURM_SUBMIT_DIR}/envs/env_fiji_GPU.sh"

export OMP_NUM_THREADS="${SLURM_CPUS_PER_TASK}"
export GMX_GPU_DD_COMMS=true
export GMX_GPU_PME_PP_COMMS=true
export GMX_FORCE_UPDATE_DEFAULT_GPU=true

# ============== Path normalization (CURC autofs alias ↔ canonical drift) ==============
# /scratch/alpine/... (autofs alias, what login-nodes see) and
# /gpfs/alpine1/scratch/... (canonical GPFS mount, what compute nodes return
# from getcwd / realpath) point to the same filesystem. GROMACS does string
# equality on paths recorded inside md.cpt, so the two forms must NOT mix
# between job parts under -append. SLURM canonicalizes --chdir via realpath,
# so we cannot rely on that to preserve the alias form. Instead, normalize
# SLURM_SUBMIT_DIR here, which is the single point at which every downstream
# path is derived.
SLURM_SUBMIT_DIR="${SLURM_SUBMIT_DIR//\/gpfs\/alpine1\/scratch\//\/scratch\/alpine\/}"

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
echo "Extension length:  ${EXTEND_PS} ps"
echo "=============================================="

# ============== Check Prerequisites ==============
if [ ! -f "${MD_DIR}/md.tpr" ]; then
    echo "ERROR: md.tpr not found in ${MD_DIR}. Cannot extend."
    exit 1
fi

if [ ! -f "${MD_DIR}/md.cpt" ]; then
    echo "ERROR: md.cpt not found in ${MD_DIR}. Cannot continue from checkpoint."
    exit 1
fi

# ============== One-time setup: extended TPR + preserve original md.gro ==============
EXTEND_TPR="${MD_DIR}/md_extend.tpr"
PRE_EXTEND_GRO="${MD_DIR}/md_pre_extend.gro"

if [ ! -f "${EXTEND_TPR}" ]; then
    # First launch: original 1 µs (or whatever) must be complete
    if [ ! -f "${MD_DIR}/md.gro" ]; then
        echo "ERROR: md.gro not found — original production run did not complete cleanly."
        echo "Cannot extend a partial run. Run 05_md.sbatch to completion first."
        exit 1
    fi

    echo ""
    echo "First-time setup: preserving original md.gro and generating extended .tpr..."
    cp "${MD_DIR}/md.gro" "${PRE_EXTEND_GRO}"
    rm "${MD_DIR}/md.gro"   # mdrun will write a fresh md.gro when the extension reaches nsteps
    gmx convert-tpr -s "${MD_DIR}/md.tpr" -extend "${EXTEND_PS}" -o "${EXTEND_TPR}"
    echo "  Original final coords saved as: ${PRE_EXTEND_GRO}"
    echo "  Extended .tpr generated:        ${EXTEND_TPR}"
fi

# ============== Run Extension MD ==============
echo ""
echo "Running extension MD..."
echo ""

# Capture gmx mdrun exit code separately so we can distinguish:
#   exit=0 + md.gro present  -> extension reached new nsteps target; done
#   exit=0 + md.gro absent   -> hit -maxh wall-time; resubmit
#   exit!=0                  -> real failure (OOM, segfault, GPU error,
#                               file-lock, etc.); do NOT resubmit
set +e
gmx mdrun -s "${EXTEND_TPR}" \
          -deffnm "${MD_DIR}/md" \
          -ntomp "${SLURM_CPUS_PER_TASK}" \
          -nb gpu -bonded gpu -pme gpu -update gpu \
          -cpi "${MD_DIR}/md.cpt" \
          -cpo "${MD_DIR}/md.cpt" \
          -append \
          -maxh "${MAXH}"
MDRUN_EXIT=$?
set -e

# ============== Decide: completed, resubmit, or fail ==============
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

if [ -f "${MD_DIR}/md.gro" ]; then
    echo ""
    echo "=============================================="
    echo "Extension completed at: $(date)"
    echo "=============================================="
    grep "Performance:" "${MD_DIR}/md.log" 2>/dev/null || true
    echo "Outputs:"
    echo "  Original final coords (pre-extension): ${PRE_EXTEND_GRO}"
    echo "  Extended final coords (new nsteps):    ${MD_DIR}/md.gro"
    echo "  Continuous trajectory (appended):       ${MD_DIR}/md.xtc"
    echo "Next steps:"
    echo "  1. Plot energies (05_md/md.edr)"
    echo "  2. Process trajectory (05_md/md.xtc) by: sbatch scripts/06_trajectory.sbatch"
    echo "=============================================="
    exit 0
fi

# Time-truncation path: bounded resubmit (separate counter from 05_md.sbatch's
# original-run counter, so extending doesn't reset the original tally).
RESUBMIT_LOG="${MD_DIR}/.resubmit_extend_count"
RESUBMIT_COUNT=$(cat "${RESUBMIT_LOG}" 2>/dev/null || echo 0)
RESUBMIT_MAX=20
if [ "${RESUBMIT_COUNT}" -ge "${RESUBMIT_MAX}" ]; then
    echo ""
    echo "=============================================="
    echo "ERROR: Hit max ${RESUBMIT_MAX} resubmits without completing extension."
    echo "Investigate ${MD_DIR}/md.log; delete ${RESUBMIT_LOG} to retry."
    echo "=============================================="
    exit 1
fi
echo $((RESUBMIT_COUNT + 1)) > "${RESUBMIT_LOG}"

echo ""
echo "=============================================="
echo "Extension hit -maxh wall-time at: $(date)"
echo "Resubmit $((RESUBMIT_COUNT + 1))/${RESUBMIT_MAX} — submitting continuation"
echo "=============================================="
grep "Performance:" "${MD_DIR}/md.log" 2>/dev/null || true
# --chdir locks the next job's SLURM_SUBMIT_DIR to the literal string used here.
# Without it, sbatch from a compute node uses getcwd(), which on CURC compute
# nodes resolves /scratch/alpine/... to /gpfs/alpine1/scratch/...; the path
# string would change between jobs and break GROMACS's md.cpt/-deffnm path
# equality check on -append.
sbatch --dependency=afterany:"${SLURM_JOB_ID}" \
       --chdir="${SLURM_SUBMIT_DIR}" \
       "${SLURM_SUBMIT_DIR}/scripts/05_md_extend.sbatch"

#!/bin/bash
#===============================================================================
# 03_nvt.sbatch - NVT Equilibration (GPU)
# Submit from project root directory: sbatch scripts/03_nvt.sbatch
#===============================================================================

#--- ALPINE  -----------------------------------
#SBATCH --account=YOUR_ACCOUNT
#SBATCH --partition=aa100
#SBATCH --qos=normal

#--- FIJI ---------------------------------------
##SBATCH --partition=nvidia-a100
##SBATCH --qos=normal
##SBATCH --nodelist=fijigpu-04

#--- BLANCA (preemptable) ----------------------
##SBATCH --account=blanca-biokem
##SBATCH --partition=blanca
##SBATCH --qos=preemptable
##SBATCH --requeue                # auto-requeue on preemption

#--- BLANCA-BIOKEM ----------------------------
##SBATCH --account=blanca-biokem
##SBATCH --partition=blanca-biokem
##SBATCH --qos=blanca-biokem

#--- COMMON RESOURCES -------------------------
#SBATCH --job-name=03_nvt_[SYSTEM]
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --gres=gpu:1
#SBATCH --mem=16gb
#SBATCH --time=03:00:00
#SBATCH --output=logs/03_nvt_%j.out
#SBATCH --error=logs/03_nvt_%j.err
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=YOUR_EMAIL@example.com

set -e  # Stop if any command fails

# ============== Set Environment ==============
# CURC:     source "${SLURM_SUBMIT_DIR}/envs/env_curc.sh"
# FIJI:     source "${SLURM_SUBMIT_DIR}/envs/env_fiji_GPU.sh"

export OMP_NUM_THREADS="${SLURM_CPUS_PER_TASK}"
export GMX_GPU_DD_COMMS=true
export GMX_GPU_PME_PP_COMMS=true
export GMX_FORCE_UPDATE_DEFAULT_GPU=true

# ============== Directories ==============
PRJ_DIR="${SLURM_SUBMIT_DIR}"
NVT_DIR="${PRJ_DIR}/03_nvt"
NPT_DIR="${PRJ_DIR}/04_npt"
mkdir -p "${NPT_DIR}"
cd "${PRJ_DIR}"

echo "=============================================="
echo "Job ID:            ${SLURM_JOB_ID}"
echo "Running on:        $(hostname)"
echo "Started at:        $(date)"
echo "Project directory: ${PRJ_DIR}"
echo "GPU(s):            ${CUDA_VISIBLE_DEVICES:-(unset)}"
echo "=============================================="

# ============== Check Prerequisites ==============
if [ ! -f "${NVT_DIR}/nvt.tpr" ]; then
    echo "ERROR: nvt.tpr not found in ${NVT_DIR}. Run energy minimization first."
    exit 1
fi

# ============== Run NVT Equilibration ==============
echo ""
echo "Running NVT equilibration..."
gmx mdrun -deffnm "${NVT_DIR}/nvt" \
          -ntomp "${SLURM_CPUS_PER_TASK}" \
          -nb gpu \
          -bonded gpu \
          -pme gpu \
          -update gpu \
          -cpo "${NVT_DIR}/nvt.cpt"

# Check if NVT completed successfully (nvt.gro)
if [ ! -f "${NVT_DIR}/nvt.gro" ]; then
    echo "ERROR: NVT equilibration failed - nvt.gro not found"
    echo "Check ${NVT_DIR}/nvt.log for details"
    exit 1
fi

# ============== Extract temperature data (temperature.xvg) ==============
echo ""
grep "Performance:" "${NVT_DIR}/nvt.log" || true
echo "Extracting temperature data..."
echo "Temperature" | gmx energy -f "${NVT_DIR}/nvt.edr" -o "${NVT_DIR}/temperature.xvg"

# ============== Post-processing (correct PBC) ==============
echo ""
echo "Post-processing: fixing PBC..."
echo "System" | gmx trjconv -f "${NVT_DIR}/nvt.gro" -s "${NVT_DIR}/nvt.tpr" -o "${NVT_DIR}/nvt_whole.gro" -pbc whole

# ============== Prepare NPT input (04_npt/npt.tpr) ==============
echo ""
echo "Preparing NPT equilibration input..."
gmx grompp -f mdp/npt.mdp \
           -c "${NVT_DIR}/nvt_whole.gro" \
           -r "${NVT_DIR}/nvt_whole.gro" \
           -t "${NVT_DIR}/nvt.cpt" \
           -p "${PRJ_DIR}/topol.top" \
           -o "${NPT_DIR}/npt.tpr" \
           -maxwarn 1

echo ""
echo "=============================================="
echo "NVT equilibration completed at: $(date)"
echo "=============================================="
echo "Next steps:"
echo "  1. Plot temperature.xvg and check convergence and temperature values"
echo "     (Temperature should be ~310K)"
echo "  2. Run NPT equilibration by: sbatch scripts/04_npt.sbatch"
echo "=============================================="
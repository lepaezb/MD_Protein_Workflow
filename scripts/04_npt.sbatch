#!/bin/bash
#===============================================================================
# 04_npt.sbatch - NPT Equilibration (GPU)
# Submit from project root directory: sbatch scripts/04_npt.sbatch
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
#SBATCH --job-name=04_npt_[SYSTEM]
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --gres=gpu:1
#SBATCH --mem=16gb
#SBATCH --time=03:00:00
#SBATCH --output=logs/04_npt_%j.out
#SBATCH --error=logs/04_npt_%j.err
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
NPT_DIR="${PRJ_DIR}/04_npt"
MD_DIR="${PRJ_DIR}/05_md"
mkdir -p "${MD_DIR}"
cd "${PRJ_DIR}"

echo "=============================================="
echo "Job ID:            ${SLURM_JOB_ID}"
echo "Running on:        $(hostname)"
echo "Started at:        $(date)"
echo "Project directory: ${PRJ_DIR}"
echo "GPU(s):            ${CUDA_VISIBLE_DEVICES:-(unset)}"
echo "=============================================="

# ============== Check Prerequisites ==============
if [ ! -f "${NPT_DIR}/npt.tpr" ]; then
    echo "ERROR: npt.tpr not found in ${NPT_DIR}. Run NVT equilibration first."
    exit 1
fi

# ============== Run NPT Equilibration ==============
echo ""
echo "Running NPT equilibration..."
gmx mdrun -deffnm "${NPT_DIR}/npt" \
          -ntomp "${SLURM_CPUS_PER_TASK}" \
          -nb gpu \
          -bonded gpu \
          -pme gpu \
          -update gpu \
          -cpo "${NPT_DIR}/npt.cpt"

# Check if NPT completed successfully
if [ ! -f "${NPT_DIR}/npt.gro" ]; then
    echo "ERROR: NPT equilibration failed - npt.gro not found"
    echo "Check ${NPT_DIR}/npt.log for details"
    exit 1
fi

# ============== Extract pressure/density data (pressure.xvg and density.xvg) ==============
echo ""
grep "Performance:" "${NPT_DIR}/npt.log" || true
echo "Extracting pressure and density data..."
echo "Pressure" | gmx energy -f "${NPT_DIR}/npt.edr" -o "${NPT_DIR}/pressure.xvg"
echo "Density"  | gmx energy -f "${NPT_DIR}/npt.edr" -o "${NPT_DIR}/density.xvg"

# ============== Post-processing (correct PBC) ==============
echo ""
echo "Post-processing: fixing PBC..."
echo "System" | gmx trjconv -f "${NPT_DIR}/npt.gro" -s "${NPT_DIR}/npt.tpr" -o "${NPT_DIR}/npt_whole.gro" -pbc whole

# ============== Prepare MD input (05_md/md.tpr) ==============
echo ""
echo "Preparing production MD input..."
gmx grompp -f mdp/md.mdp \
           -c "${NPT_DIR}/npt_whole.gro" \
           -t "${NPT_DIR}/npt.cpt" \
           -p "${PRJ_DIR}/topol.top" \
           -o "${MD_DIR}/md.tpr" \
           -maxwarn 1

echo ""
echo "=============================================="
echo "NPT equilibration completed at: $(date)"
echo "=============================================="
echo "Next steps:"
echo "  1. Plot pressure.xvg and density.xvg. Check values and convergence"
echo "     (Pressure should be ~1 bar and density ~1000 kg/m³ for aqueous systems)"
echo "  2. Run production MD by: sbatch scripts/05_md.sbatch"
echo "=============================================="
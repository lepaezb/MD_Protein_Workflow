#!/bin/bash
#===============================================================================
# 02_em.sbatch - Energy Minimization (CPU)
# Submit from project root directory: sbatch scripts/02_em.sbatch
#===============================================================================

#--- ALPINE  -----------------------------------
#SBATCH --account=YOUR_ACCOUNT
#SBATCH --partition=amilan
#SBATCH --qos=normal

#--- FIJI ---------------------------------------
##SBATCH --partition=highmem
##SBATCH --qos=normal

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
#SBATCH --job-name=02_em_[SYSTEM]
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=8gb
#SBATCH --time=03:00:00
#SBATCH --output=logs/02_em_%j.out
#SBATCH --error=logs/02_em_%j.err
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=YOUR_EMAIL@example.com

set -e  # Stop if any command fails

# ============== Set Environment ==============
# CURC:     source "${SLURM_SUBMIT_DIR}/envs/env_curc.sh"
# FIJI:     source "${SLURM_SUBMIT_DIR}/envs/env_fiji_CPU.sh"

export OMP_NUM_THREADS="${SLURM_CPUS_PER_TASK}"

# ============== Directories ==============
PRJ_DIR="${SLURM_SUBMIT_DIR}"
EM_DIR="${PRJ_DIR}/02_em"
NVT_DIR="${PRJ_DIR}/03_nvt"
mkdir -p "${NVT_DIR}"
cd "${PRJ_DIR}"

echo "=============================================="
echo "Job ID:            ${SLURM_JOB_ID}"
echo "Running on:        $(hostname)"
echo "Started at:        $(date)"
echo "Project directory: ${PRJ_DIR}"
echo "=============================================="

# ============== Run Energy Minimization (EM) ==============
echo ""
echo "Running energy minimization..."
gmx mdrun -v -deffnm "${EM_DIR}/em" -ntomp "${SLURM_CPUS_PER_TASK}"

# Check if EM completed successfully (em.gro)
if [ ! -f "${EM_DIR}/em.gro" ]; then
    echo "ERROR: Energy minimization failed - em.gro not found"
    exit 1
fi

# ============== Extract potential energy (potential.xvg) ==============
echo ""
echo "Extracting potential energy (potential.xvg)..."
echo "Potential" | gmx energy -f "${EM_DIR}/em.edr" -o "${EM_DIR}/potential.xvg"

# ============== Post-processing (correct PBC) ==============
echo ""
echo "Post-processing: fixing PBC..."
echo "System" | gmx trjconv -f "${EM_DIR}/em.gro" -s "${EM_DIR}/em.tpr" -o "${EM_DIR}/em_whole.gro" -pbc whole

# ============== Prepare NVT input (03_nvt/nvt.tpr) ==============
echo ""
echo "Preparing NVT equilibration input (03_nvt/nvt.tpr)..."
gmx grompp -f mdp/nvt.mdp \
           -c "${EM_DIR}/em_whole.gro" \
           -r "${EM_DIR}/em_whole.gro" \
           -p "${PRJ_DIR}/topol.top" \
           -o "${NVT_DIR}/nvt.tpr" \
           -maxwarn 1

echo ""
echo "=============================================="
echo "Energy minimization completed at: $(date)"
echo "=============================================="
echo "Next steps:"
echo "  1. Plot potential.xvg and check convergence and energy values"
echo "  2. Run NVT equilibration by: sbatch scripts/03_nvt.sbatch"
echo "=============================================="
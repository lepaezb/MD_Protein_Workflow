#!/bin/bash
#===============================================================================
# 06_trajectory.sbatch - Process MD Trajectory
# Submit from project root directory: sbatch scripts/06_trajectory.sbatch
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
#SBATCH --job-name=06_trajectory_[SYSTEM]
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=8gb
#SBATCH --time=10:00:00
#SBATCH --output=logs/06_trajectory_%j.out
#SBATCH --error=logs/06_trajectory_%j.err
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=YOUR_EMAIL@example.com

set -e  # Stop if any command fails

# ============== Set Environment ==============
# CURC:     source "${SLURM_SUBMIT_DIR}/envs/env_curc.sh"
# FIJI:     source "${SLURM_SUBMIT_DIR}/envs/env_fiji_CPU.sh"

export OMP_NUM_THREADS="${SLURM_CPUS_PER_TASK}"

# ============== Directories ==============
PRJ_DIR="${SLURM_SUBMIT_DIR}"
MD_DIR="${PRJ_DIR}/05_md"
TRAJ_DIR="${PRJ_DIR}/06_trajectory"
mkdir -p "${TRAJ_DIR}"
cd "${PRJ_DIR}"

# ============== Inputs ==============
TRAJ="${MD_DIR}/md.xtc"       # Production trajectory
TPR="${MD_DIR}/md.tpr"        # Binary topology for MD
EDR="${MD_DIR}/md.edr"        # Energy file for MD

echo "=============================================="
echo "Job ID:            ${SLURM_JOB_ID}"
echo "Running on:        $(hostname)"
echo "Started at:        $(date)"
echo "Project directory: ${PRJ_DIR}"
echo "=============================================="

# ============== Check Prerequisites ==============
if [ ! -f "${TRAJ}" ]; then
    echo "ERROR: Trajectory file not found: ${TRAJ}"
    exit 1
fi

if [ ! -f "${TPR}" ]; then
    echo "ERROR: .tpr file not found: ${TPR}"
    exit 1
fi

# ============== Trajectory Processing  ==============
echo "1. Reassemble molecules split across box boundaries..."
echo "System" | gmx trjconv \
    -f "${TRAJ}" \
    -s "${TPR}" \
    -o "${TRAJ_DIR}/traj_whole.xtc" \
    -pbc whole

echo "2. Removing PBC jumps when molecules cross the box edge..."
echo "System" | gmx trjconv \
    -f "${TRAJ_DIR}/traj_whole.xtc" \
    -s "${TPR}" \
    -o "${TRAJ_DIR}/traj_nojump.xtc" \
    -pbc nojump

echo "3. Centering on protein in the box..."
echo -e "Protein\nSystem" | gmx trjconv \
    -f "${TRAJ_DIR}/traj_nojump.xtc" \
    -s "${TPR}" \
    -o "${TRAJ_DIR}/traj_final.xtc" \
    -center \
    -pbc mol \
    -ur compact

TRAJ_FIX="${TRAJ_DIR}/traj_final.xtc"

# ============== Small trajectory and summary  ==============
echo ""
echo "Extracting small trajectory for visualization (1 in 100 stored frames; ~10 ns/frame at md nstxout-compressed=50000)..."
echo "--------------------------------------"
echo ""
echo -e "Protein\nProtein" | gmx trjconv \
    -f "${TRAJ_FIX}" \
    -s "${TPR}" \
    -o "${TRAJ_DIR}/traj_small.xtc" \
    -fit rot+trans \
    -skip 100

echo ""
echo "Trajectory information..."
echo "--------------------------------------"
gmx check -f "${TRAJ}" &> "${TRAJ_DIR}/traj_info.txt"
echo ""
echo "Summary:"
grep -E "(Step|Last frame|Coords|time)" "${TRAJ_DIR}/traj_info.txt" || true

# Check if final trajectory was created successfully
if [ ! -f "${TRAJ_FIX}" ]; then
    echo "ERROR: Final trajectory not found"
    exit 1
fi

echo ""
echo "=============================================="
echo "Trajectory processing completed at: $(date)"
echo "=============================================="
#!/bin/bash
#===============================================================================
# 01_prep.sh - System Preparation for GROMACS MD Simulation
#===============================================================================
# This script prepares the system from PDB to solvated/ionized structure
# Run this LOCALLY or on a compile node (not as a sbatch job)
# Request CPU allocation in Alpine by `acompile` or in FIJI by `srun -p highmem --pty /bin/bash`
#
# Usage: ./01_prep.sh <input.pdb> [force_field] [water_model]
#   input.pdb    : PDB file
#   force_field  : Force field name (default: charmm36-jul2022)
#   water_model  : Water model (default: tip3p)
#
# Example: ./01_prep.sh protein.pdb charmm36-jul2022 tip3p
#===============================================================================

set -e  # Stop if any command fails

# ============== Directories ==============
PREP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${PREP_DIR}/.."
MDP_DIR="${ROOT_DIR}/mdp"
EM_DIR="${ROOT_DIR}/02_em"
mkdir -p "${EM_DIR}"

# ============== Set Environment ==============
# CURC (Alpine, Blanca): source "${ROOT_DIR}/envs/env_curc.sh"
# FIJI:                  source "${ROOT_DIR}/envs/env_fiji_CPU.sh"

# ============== Configuration ==============
INPUT_PDB="${1:?ERROR: Please provide input PDB file as first argument}"
FF="${2:-charmm36-jul2022}"
WATER="${3:-tip3p}"
BOX_DIST="2"            # Distance from protein to box edge (nm)
BOX_TYPE="cubic"        # Box type (cubic, dodecahedron, etc.)
CONC="0.15"             # Salt concentration (M) - physiological ~0.15 M

echo "=============================================="
echo "GROMACS System Preparation"
echo "=============================================="
echo "Input PDB: ${INPUT_PDB}"
echo "Force Field: ${FF}"
echo "Water Model: ${WATER}"
echo "Box Type: ${BOX_TYPE}"
echo "Box Distance: ${BOX_DIST} nm"
echo "Salt Concentration: ${CONC} M"
echo "=============================================="


# ============== Check Prerequisites ==============
if [ ! -f "${INPUT_PDB}" ]; then
    echo "ERROR: Input PDB file not found: ${INPUT_PDB}"
    exit 1
fi

# Check if GROMACS is available
if ! command -v gmx &> /dev/null; then
    echo "ERROR: GROMACS (gmx) not found in PATH"
    exit 1
fi

# ============== Run ==============
echo ""
echo "Step 1: Generate topology from PDB..."
echo "--------------------------------------"
gmx pdb2gmx -f "${INPUT_PDB}" \
            -o "1_processed.gro" \
            -water "${WATER}" \
            -ff "${FF}" \
            -ignh # ignore existing hydrogens in PDB

echo ""
echo "Step 2: Define simulation box..."
echo "--------------------------------------"
gmx editconf -f "1_processed.gro" \
             -o "2_boxed.gro" \
             -c \
             -d "${BOX_DIST}" \
             -bt "${BOX_TYPE}"

echo ""
echo "Step 3: Solvate the system..."
echo "--------------------------------------"
gmx solvate -cp "2_boxed.gro" \
            -cs spc216.gro \
            -o "3_solvated.gro" \
            -p "topol.top"

echo ""
echo "Step 4: Add ions to neutralize and set ionic concentration..."
echo "--------------------------------------"
gmx grompp -f "${MDP_DIR}/ions.mdp" \
           -c "3_solvated.gro" \
           -p "topol.top" \
           -o "4_ions.tpr"

echo "SOL" | gmx genion -s "4_ions.tpr" \
                        -o "4_solvated_ions.gro" \
                        -p "topol.top" \
                        -pname NA \
                        -nname CL \
                        -neutral \
                        -conc "${CONC}"

echo ""
echo "Step 5: Prepare energy minimization input..."
echo "--------------------------------------"
gmx grompp -f "${MDP_DIR}/em.mdp" \
           -c "4_solvated_ions.gro" \
           -p "topol.top" \
           -o "${EM_DIR}/em.tpr"

# Copy topology to root of project directory
cp topol.top "${ROOT_DIR}/"
cp *.itp "${ROOT_DIR}/"

echo ""
echo "=============================================="
echo "System preparation complete!"
echo "Next step: Run energy minimization using sbatch scripts/02_em.sbatch"
echo "=============================================="
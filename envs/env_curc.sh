#!/bin/bash
#===============================================================================
# env_curc.sh - GROMACS environment for CURC (Alpine + Blanca)
#===============================================================================
# Single env script covers all CU Research Computing (CURC) clusters: Alpine,
# Blanca preemptable, and Blanca-biokem. CURC has a unified module tree —
# the gromacs/2024.2 module resolves to the same install path
# (/curc/sw/install/gromacs/2024.2/openmpi/4.1.1/gcc/11.2.0/) on all CURC
# compute nodes. Verified 2026-05-07 on c3cpu-a2-u32-3 (Alpine),
# blanca-g4-u16-2 (Blanca preemptable), and bgpu-biokem1 (Blanca-biokem).
#
# The same module is GPU-built (CUDA 12.1.1 auto-loads as a transitive dep),
# so this single env script works for both CPU and GPU jobs.
#
# Usage in scripts:
#   source "${SLURM_SUBMIT_DIR}/envs/env_curc.sh"
#   gmx mdrun ...
#
# Note: slurm/<cluster> is a login-node module for routing the slurm CLI;
# inside an sbatch job the cluster context is already established and
# loading it can fail (verified 2026-05-07 on bgpu-biokem3 — Lmod errored
# with "cannot be loaded as requested"). Skip it.
#===============================================================================

module purge
module load gcc/11.2.0
module load openmpi/4.1.1
module load gromacs/2024.2  # GPU-built CUDA/12.1.1 auto-loads

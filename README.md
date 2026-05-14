# MD_Protein_Workflow

A modular GROMACS workflow for **apo protein** and **protein-protein complex** molecular-dynamics simulations on SLURM-managed HPC clusters. Built on **CHARMM36-jul2022 + TIP3P** at 310 K, 0.15 M NaCl, with a 1 µs production target by default.

Originally developed for the PARP1 catalytic domain (P1) and the PARP1-HPF1 complex (P1H1), but generalizable to any single- or two-chain protein system — see [Generalization](#generalization).

---

## Features

- **6-step pipeline** — system prep → energy minimization → NVT → NPT → production MD → trajectory processing. Each step is a single self-documenting sbatch file.
- **Auto-resubmit production** — `05_md.sbatch` watches for the `md.gro` final-frame file; if absent at SLURM wall-time, it resubmits a continuation job (up to `RESUBMIT_MAX=20`) so 1 µs runs survive any cluster's wall-time cap.
- **Multi-cluster headers** — every sbatch file ships with commented-out blocks for CU Boulder **Alpine** / **Blanca preemptable** / **Blanca-biokem** and Stanford **FIJI**. Uncomment the one you need.
- **CHARMM36-correct defaults** — VdW force-switch (1.0–1.2 nm), no dispersion correction, V-rescale thermostat, Parrinello-Rahman barostat for production, PME electrostatics at 1.2 nm. Validated against the GROMACS 2024.2 manual.
- **MIT licensed** — see [LICENSE](LICENSE).

## Requirements

| Tool | Version | Source |
|---|---|---|
| GROMACS | ≥ 2024.2 (CPU + GPU builds) | Cluster module |
| CHARMM36-jul2022 force field | — | [MacKerell lab](https://mackerell.umaryland.edu/charmm_ff.shtml); download separately, see [Setup](#setup) |
| SLURM workload manager | — | Target cluster |
| Bash | ≥ 4.0 | Linux standard |
| GPU (recommended) | Ampere (A100/A40) or Ada (L40) | Used in 03_nvt, 04_npt, 05_md |

---

## Setup

### 1. Clone

```bash
git clone git@github.com:lepaezb/MD_Protein_Workflow.git
cd MD_Protein_Workflow
```

### 2. Download CHARMM36-jul2022 force field

The force field is **not bundled** with this repo (redistribution policy + size). Download the GROMACS-formatted release from the MacKerell lab page:

> https://mackerell.umaryland.edu/charmm_ff.shtml
>
> Section: *CHARMM force field files in GROMACS format*  →  download `charmm36-jul2022.ff.tgz` (or the latest matching version).

Then unpack at the repo root and create the prep-step symlink:

```bash
# From the repo root (where this README lives)
tar -xzf /path/to/charmm36-jul2022.ff.tgz       # creates ./charmm36-jul2022.ff/
ln -s ../charmm36-jul2022.ff 01_prep/charmm36-jul2022.ff
```

The result should look like:

```
MD_Protein_Workflow/
├── charmm36-jul2022.ff/                    ← extracted FF directory
├── 01_prep/
│   ├── 01_prep.sh
│   └── charmm36-jul2022.ff -> ../charmm36-jul2022.ff
└── ...
```

`01_prep.sh` runs `gmx pdb2gmx -ff charmm36-jul2022 ...` from inside `01_prep/`, so the local symlink lets `pdb2gmx` find the FF without you having to set `GMXLIB`.

### 3. Configure cluster bits

Each sbatch file in `scripts/` has SBATCH header blocks for several clusters. **Edit each script you'll use:**

1. Uncomment the `#SBATCH` block matching your cluster (start its lines with a single `#`); leave the others with `##`.
2. Replace `YOUR_ACCOUNT` with your cluster project/account name.
3. Replace `YOUR_EMAIL@example.com` with your email (or remove the `--mail-*` lines).
4. Inside the *"Set Environment"* block, uncomment the matching `source "${SLURM_SUBMIT_DIR}/envs/env_<cluster>.sh"` line.
5. **For `05_md.sbatch` only**, also uncomment the appropriate `MAXH` line — it must be slightly less than `--time=` so GROMACS has time to write its checkpoint before SLURM kills the job.

### 4. Per-system clone

Don't run jobs *in* this repo. For each protein system, clone the entire template to a per-system run dir on cluster scratch:

```bash
cp -r MD_Protein_Workflow /scratch/<user>/<system_name>
cd /scratch/<user>/<system_name>
```

This keeps the upstream repo clean and each MD run self-contained.

---

## Quick start (pipeline)

```bash
# 1. Prep — interactive on a CPU compile node
#    Alpine: run `acompile` first; FIJI: `srun -p highmem --pty bash`
cd 01_prep
bash 01_prep.sh path/to/your_input.pdb       # → topol.top + 02_em/em.tpr
cd ..

# 2–6. Submit each sbatch in order
sbatch scripts/02_em.sbatch          # Energy minimization (CPU)
sbatch scripts/03_nvt.sbatch         # NVT equilibration, 1 ns (GPU)
sbatch scripts/04_npt.sbatch         # NPT equilibration, 1 ns (GPU)
sbatch scripts/05_md.sbatch          # Production MD, 1 µs (GPU; auto-resubmits)
sbatch scripts/06_trajectory.sbatch  # PBC fix + thinning (CPU)
```

When `06_trajectory.sbatch` completes, you have:

| File | Contents | Use |
|---|---|---|
| `06_trajectory/traj_final.xtc` | PBC-corrected, protein-centered, full system | Analysis |
| `06_trajectory/traj_small.xtc` | Thinned (1/100), protein-only, fit-aligned | Visualization (VMD / ChimeraX) |
| `06_trajectory/traj_info.txt` | `gmx check` summary | Verification |

---

## Directory layout

```
MD_Protein_Workflow/
├── README.md                            this file
├── LICENSE                              MIT
├── .gitignore
│
├── 01_prep/
│   ├── 01_prep.sh                       step 1: PDB → solvated + ionized
│   └── charmm36-jul2022.ff -> ../...    user-created symlink (see Setup)
│
├── envs/
│   ├── env_curc.sh                      Alpine + Blanca (CU Boulder)
│   ├── env_fiji_CPU.sh                  FIJI CPU jobs
│   └── env_fiji_GPU.sh                  FIJI GPU jobs
│
├── mdp/                                 GROMACS .mdp parameter files
│   ├── em.mdp                           energy minimization
│   ├── ions.mdp                         ion-placement container
│   ├── nvt.mdp                          NVT equilibration
│   ├── npt.mdp                          NPT equilibration
│   └── md.mdp                           production MD (1 µs default)
│
├── scripts/                             SLURM submission scripts
│   ├── 02_em.sbatch
│   ├── 03_nvt.sbatch
│   ├── 04_npt.sbatch
│   ├── 05_md.sbatch                     auto-resubmits up to RESUBMIT_MAX=20
│   ├── 05_md_extend.sbatch              optional: extend production by N ps
│   └── 06_trajectory.sbatch
│
└── logs/                                created at run-time (in .gitignore)
```

---

## MDP parameter reference

All `.mdp` files in `mdp/` are plain-text GROMACS inputs and **you can edit them**. The defaults are validated against the GROMACS 2024.2 manual for CHARMM36 + TIP3P at 310 K, 0.15 M NaCl. The tables below explain each parameter's purpose and when you'd want to change it.

### Integrator / run control

| Parameter | Default | Meaning / when to change |
|---|---|---|
| `integrator` | `md` (production) / `steep` (em) | `md` = leap-frog Newton's eqs; `steep` = steepest-descent minimization. |
| `dt` | `0.002` (2 fs) | Time step. 2 fs requires h-bond constraints (LINCS). For 4 fs runs you need virtual hydrogens. |
| `nsteps` | `500000000` (md.mdp = 1 µs) | Total steps; simulated time = `nsteps × dt`. Change for shorter / longer runs. |
| `comm-mode` | `Linear` | Remove translational COM drift. Keep for solvated systems. |
| `nstcomm` | `100` | COM removal frequency (steps). |

### Constraints (LINCS)

| Parameter | Default | Meaning / when to change |
|---|---|---|
| `constraints` | `h-bonds` | Hydrogen-bond constraints enable a 2 fs time step. `all-bonds` is needed only with 4 fs + virtual sites. |
| `constraint_algorithm` | `lincs` | LINCS is fast/stable for protein systems. SHAKE is older. |
| `lincs_iter` | `1` | Accuracy iterations. Raise to 2 if you see LINCS warnings in `md.log`. |
| `lincs_order` | `4` | Expansion order. Keep at 4. |

### Neighbor list / periodic boundary

| Parameter | Default | Meaning / when to change |
|---|---|---|
| `cutoff-scheme` | `Verlet` | Required for GROMACS 5+; don't change. |
| `nstlist` | `20` | Neighbor-list update interval. Verlet auto-tunes internally — leave at 20. |
| `rlist` | `1.2` (nm) | Neighbor-list cutoff. Match `rvdw`/`rcoulomb`. |
| `pbc` | `xyz` | 3D periodic boundary. Use `no` only for vacuum studies. |

### Electrostatics (PME)

| Parameter | Default | Meaning / when to change |
|---|---|---|
| `coulombtype` | `PME` (everywhere except `ions.mdp`) | Particle-Mesh Ewald — gold standard for long-range Coulomb in solvated systems. `ions.mdp` uses `cutoff` because the system is not yet neutral when ions are placed (PME requires net-zero charge). |
| `rcoulomb` | `1.2` (nm) | Short-range cutoff. CHARMM36 requires 1.2 nm. |
| `pme_order` | `4` | Cubic interpolation. Raise to 6 for ~30% higher cost and ~5% better accuracy. |
| `fourierspacing` | `0.12` | FFT grid spacing (nm). Smaller → more accurate, more expensive. |

### Van der Waals — CHARMM36 force-switch (DO NOT CHANGE for CHARMM36)

| Parameter | Default | Meaning |
|---|---|---|
| `vdwtype` | `cutoff` | Pure cutoff with switching applied below. |
| `vdw-modifier` | `force-switch` | **Required for CHARMM36** — smoothly switches the force to zero between `rvdw-switch` and `rvdw`. Using any other modifier breaks the CHARMM36 parameterization. |
| `rvdw-switch` | `1.0` (nm) | Switch start. |
| `rvdw` | `1.2` (nm) | Switch end + cutoff. |
| `DispCorr` | `no` | CHARMM36 already includes long-range dispersion in its parameters; `EnerPres` would double-count. |

If you change force fields (Amber, OPLS), revisit this whole block — different FFs require different VdW schemes.

### Temperature coupling

| Parameter | Default | Meaning / when to change |
|---|---|---|
| `tcoupl` | `V-rescale` | Velocity-rescale (Bussi 2007); produces correct canonical-ensemble fluctuations. Don't use Berendsen for production. |
| `tc-grps` | `Protein Non-Protein` | Separate thermostat for solute vs. solvent prevents "hot protein, cold solvent" artifacts. |
| `tau_t` | `0.5 0.5` | Coupling time constants (ps); 0.5 ps is the V-rescale standard. |
| `ref_t` | `310 310` | Reference temperature (K). **Change here for non-physiological runs.** Also update `gen_temp` in `nvt.mdp` to match. |

### Pressure coupling

| Parameter | Default | Meaning / when to change |
|---|---|---|
| `pcoupl` | `no` (NVT) / `C-rescale` (NPT) / `Parrinello-Rahman` (production) | NPT equilibration uses C-rescale (Bernetti-Bussi 2020) for fast relaxation; production uses Parrinello-Rahman for correct ensemble fluctuations. |
| `pcoupltype` | `isotropic` | Uniform box scaling. Use `semiisotropic` for membranes. |
| `tau_p` | `10.0` (ps) | Time constant. With `dt = 2 fs`, Parrinello-Rahman needs `tau_p ≥ 5 ps` for stability. |
| `ref_p` | `1.0` (bar) | Reference pressure. |
| `compressibility` | `4.5e-5` (1/bar) | Compressibility of water. |
| `refcoord_scaling` | `com` (NPT only) | Scale position restraints with the box. |

### Output frequencies (md.mdp)

| Parameter | Default | Meaning / when to change |
|---|---|---|
| `nstxout` | `0` | Suppress full-precision (.trr) trajectory. .xtc is enough for almost all analyses. |
| `nstvout` | `0` | Same for velocities. |
| `nstenergy` | `5000` (10 ps) | Energy file (.edr) write frequency. |
| `nstlog` | `5000` (10 ps) | Log write frequency. |
| `nstxout-compressed` | `50000` (100 ps) | Trajectory (.xtc) write frequency. 1 µs / 100 ps = 10,000 frames. |
| `compressed-x-grps` | `System` | What to write. `Protein` would save disk if solvent isn't needed for analysis. |

### Velocity generation (nvt.mdp only)

| Parameter | Default | Meaning / when to change |
|---|---|---|
| `gen_vel` | `yes` | Generate initial velocities from a Maxwell-Boltzmann distribution at `gen_temp`. |
| `gen_temp` | `310` | Distribution temperature; match to `ref_t`. |
| `gen_seed` | `-1` | Random seed. `-1` = random; resolved value is logged in `mdout.mdp` (field `gen-seed`) and 02_em SLURM stdout. For exact reproducibility across replicates, set explicit integers (e.g., 12345, 24690, ...). |

---

## Cluster execution

Every sbatch file ships with header blocks for four clusters (plus a generic "COMMON RESOURCES" block applied to all). Uncomment the one you need.

### CU Boulder Alpine (default uncommented in template)

```bash
#SBATCH --account=YOUR_ACCOUNT            # your CURC project (e.g., ucb123_asc1)
#SBATCH --partition=amilan                # CPU; use aa100 for GPU
#SBATCH --qos=normal
```

`source envs/env_curc.sh` — loads GROMACS 2024.2 (GPU-built; CUDA stack auto-loads).

### CU Boulder Blanca preemptable

```bash
#SBATCH --account=blanca-biokem           # or your Blanca-affiliated account
#SBATCH --partition=blanca
#SBATCH --qos=preemptable
#SBATCH --requeue                         # auto-requeue on preemption (resumes from md.cpt)
#SBATCH --constraint="A100|L40|A40"       # modern GPUs only; excludes Blackwell sm_120 (CUDA #209) and slow V100/T4/P100
```

### CU Boulder Blanca-biokem

```bash
#SBATCH --account=blanca-biokem
#SBATCH --partition=blanca-biokem
#SBATCH --qos=blanca-biokem
```

### Stanford FIJI

```bash
#SBATCH --partition=highmem               # CPU
##SBATCH --partition=nvidia-a100          # GPU (for 03/04/05)
#SBATCH --qos=normal
```

`source envs/env_fiji_CPU.sh` (for CPU steps) or `envs/env_fiji_GPU.sh` (for GPU steps).

### Other clusters

Copy `envs/env_curc.sh` as a starting point; adapt the `module load` calls to your cluster's GROMACS module name and dependencies. Add a new SBATCH block in each sbatch file mirroring one of the existing ones.

---

## Generalization

This workflow was built and validated for two PARP1-HPF1 systems:

- **P1** — single-chain PARP1 catalytic domain (residues 662–1014; 353 residues, ~125 K atoms in solvent)
- **P1H1** — PARP1-CAT + HPF1 complex (two chains; residues 662–1014 + 30–345; 669 residues, ~295 K atoms)

To adapt this template to a different system:

1. **Input structure** — provide your PDB to `01_prep.sh`. The script accepts any PDB that `gmx pdb2gmx` can parse. Clean alternate locations, missing atoms, and non-standard residues in Maestro/PyMOL first.

2. **Box / salt / temperature** — edit the variables at the top of `01_prep.sh` (`BOX_DIST`, `BOX_TYPE`, `CONC`, `WATER`) and `ref_t` / `gen_temp` in the `mdp/*.mdp` files.

3. **Production length** — change `nsteps` in `mdp/md.mdp`. The default is `500000000` steps × 2 fs = 1 µs.

4. **Multi-chain systems** — `gmx pdb2gmx` (called by `01_prep.sh`) handles multi-chain PDBs automatically; each chain becomes a separate molecule type in `topol.top`. For > 2 protein chains, you may need to manually adjust the `[ molecules ]` section in `topol.top` after prep.

5. **Different force field / water** — pass `FF=charmm22star` (or similar) and `WATER=tip3p` as 2nd/3rd arguments to `01_prep.sh`. **Important**: the VdW force-switch settings in the mdp files are CHARMM36-specific. For Amber / OPLS, set `vdw-modifier = none`, `rvdw-switch = 0`, and consult the FF documentation for the recommended cutoff scheme.

6. **Cluster wall-time tuning** — production MD (`05_md.sbatch`) auto-resubmits until `md.gro` is produced or `RESUBMIT_MAX=20` is reached. `MAXH` (inside the script's Configuration block) must be slightly less than `--time=` to give GROMACS time to write its checkpoint before SLURM kills the job. Defaults: Alpine/Blanca `MAXH=23.5` (24 h limit), FIJI `MAXH=47.5` (48 h limit).

---

## References

- **GROMACS** — Abraham et al. 2015 *SoftwareX* 1-2:19. Manual: https://manual.gromacs.org/2024.2/
- **CHARMM36** — Huang et al. 2017 *Nat Methods* 14:71-73
- **TIP3P** — Jorgensen et al. 1983 *J Chem Phys* 79:926-935
- **V-rescale thermostat** — Bussi, Donadio & Parrinello 2007 *J Chem Phys* 126:014101
- **Parrinello-Rahman barostat** — Parrinello & Rahman 1981 *J Appl Phys* 52:7182
- **C-rescale barostat** — Bernetti & Bussi 2020 *J Chem Phys* 153:114107
- **LINCS** — Hess et al. 1997 *J Comput Chem* 18:1463
- **PME** — Essmann et al. 1995 *J Chem Phys* 103:8577

## License

MIT — see [LICENSE](LICENSE).

## Acknowledgments

Originally developed for the PARP1-HPF1 selectivity project at CU Boulder. Validated on CU Research Computing Alpine (A100 GPUs), Blanca preemptable + biokem partitions (A40 / L40 GPUs), and Stanford FIJI (nvidia-a100 nodes). Bug reports and pull requests welcome.

# AmberMDHelper
Scripts used to setup molecular dynamics simulations using AMBER software.
## setupMD.sh
setupMD.sh script is used to:
- Create a reproducible folder structure based on receptor, ligands, cofactor and replicas.
- Configure all required input files.
- Process receptor, ligands and cofactor files using tools from AmberTools. This include:
  - Parameterization, including partial charge calculations, of ligands/cofactor.
  - Creation of dry and solvated topologies.
### Requirements
- Software:
  - AmberTools
- A working directory containing:
  - receptor folder: This folder must contain a single PDB file of the receptor.
  - ligands folder (optional: This folder must contain ligands files in mol2 format. Ligand must be already protonated.
  - cofactor folder (optional): This folder should contain a single cofactor file in mol2 format. Cofactor must be already protonated.
### Usage
Use ```-h```, ```--help``` options to show script help.
```bash
bash setupMD.sh --help # get help.
```
Output:
```
Required options:
 -d, --work_dir     <path>       Working directory. Inside this directory, a folder named setupMD will be created which contains all necessary files.
Optional:
 -h, --help                      Show this help.
 --prod_time        <integer>    (default=100) Simulation time (in ns) (2 fs timestep).
 --equi_time        <integer>    (default=10) Simulation time (in ns) of last step of equilibration (2 fs timestep)
 -n, --replicas     <integer>    (default=3) Number of replicas or repetitions.
 --prot_only        <0|1>        (default=0) Setup only protein MD.
 --prot_lig         <0|1>        (default=0) Setup protein-ligand MD.
 --prep_rec         <0|1>        (default=1) Prepare receptor. Receptor MUST be already protonated.
 --prep_lig         <0|1>        (default=0) Prepare ligand. Ligand MUST be already protonated.
 --include_cof      <0|1>        (default=0) Include cofactor.
 --prep_cof         <0|1>        (default=0) Prepare cofactor if --include_cof 1. Cofactor MUST be already protonated.
 --prep_topology    <0|1>        (default=0) Prepare topology files.
 --prep_MD          <0|1>        (default=1) Prepare MD input files.
 --calc_lig_charge  <0|1>        (default=1) Compute ligand (and cofactor) atoms' partial charges if --prep_lig 1.
 --charge_method    <string>     (default=bcc) Charge method if --calc_lig_charge 1.
 --lig_ff           <gaff|gaff2> (default=gaff2) Small molecule forcefield. This applies both ligand and cofactor.
 --prot_ff          <string>     (default=ff19SB) Protein forcefield.
 --water_model      <string>     (default=opc) Water model used in MD.
 --box_size         <integer>    (default=14) Size of water box.
```
### Working directory example
Below there is an example of a working directory with the required receptor, but no ligand and cofactor.

```bash
WDPATH
├── cofactor
├── ligands
└── receptor
    └── rec_name.pdb
```

Below there is an example of folder structure created with setupMD script. This just create the directories.
```bash
bash setupMD.sh -d . -n 1 --prot_only 1 --prep_topology 0 --prep_rec 0 --prep_MD 0
```
```bash
WDPATH
├── cofactor
├── ligands
└── setupMD
    └── rec_name
        └── onlyProteinMD
            ├── MD
            │   └── rep1
            │       ├── equi
            │       │   ├── npt
            │       │   └── nvt
            │       └── prod
            │           ├── npt
            │           └── nvt
            └── topo
```
### MD Protocol
The default MD protocol consist of two stages: equilibration and production:
- Equilibration:
  - 2 restrained minimization.
  - Restrained NVT to raise temperature.
  - 5 Restraint releasing NPT.
  - Final unrestrained NPT. The duration of this step is controlled via ```--equi_time``` option.
- Production:
  - Unrestrained NPT. The duration of this step is controlled via ```--prod_time``` option.

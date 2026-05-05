#!/usr/bin/bash

# Global variables are always UPPERCASE.
# Local are used with local keyword and lowercase.
# If some function requires too much arguments,
# try using global variables directly, however, this is harder to
# read and debug.

#set -x

function ScriptInfo() {
  DATE="2025"
  VERSION="1.0.4"
  GH_URL="https://github.com/tcaceresm/AmberMDHelper"
  LAB="http://schuellerlab.org/"

  cat <<EOF
###################################################
 Welcome to processMD version ${VERSION} ${DATE}   
  Author: Tomás Cáceres <caceres.tomas@uc.cl>    
  Laboratory of Molecular Design <${LAB}>
  Laboratory of Computational simulation & drug design        
  GitHub <${GH_URL}>                             
  Powered by high fat food and procrastination   
###################################################
EOF
}

function Help() {
  ScriptInfo
  cat <<EOF

Usage: bash process_MD.sh OPTIONS

This script process molecular dynamics simulations in the specified directory previously configured with setup_MD.sh.
This include:
 - Remove solvent from trajectories.
 - RMSD and RMSF data generation.
 - Temperature, Density and Total energy data generation.
 - Intermolecular H-bond.

The specified directory must always have a folder named "receptor" containing the receptor PDB
and an optional "ligands" and "cofactor" folder containing MOL2 file of ligands and cofactor, respectively.

Required options:
 -d, --work_dir     <DIR>       Working directory. Inside this directory, a folder named setupMD should exist, containing all output files.
Optional:
 -h, --help                      Show this help.
 --prot_only        <0|1>          (default=0) Process only-protein MD.
 --prot_lig         <0|1>          (default=0) Process protein-ligand MD.
 --equi             <0|1>          (default=1) Process equilibration phase.
 --prod             <0|1>          (default=1) Process production phase.
 --rmsd             <0|1>          (default=1) Calculate RMSD and RMSF (whole dry system). Must have dry trajectories. see --dry option.
 --rmsd_mask        <AMBER_MASK>   (default=":1-TOTALRES@CA,C,N"). Mask used to calculate RMSD and RMSF. (TOTALRES is the N° of residues and
                                   it's automatically determined).
 --dry              <0|1>          (default=1) Remove water and ions from trajectories.
 --thermo           <0|1>          (default=1) Generate Temperature, Density and Total Energy data from trajectories. These are obtained from .out files.
 --mmpbsa_rescore   <0|1>          (default=0) Obtain unsolvated minimized structure (from min2.rst7 file of equilibration phase). Must run this option if you want to
                                   perform MM/PBSA rescoring using MMPBSA.sh script.
 --hbond            <0|1>          (default=0) Compute intermolecular h-bonds (protein-ligand mode only).
 -n, --replicas     <integer>      (default=3) Number of replicas or repetitions to process.
 --start_replica    <integer>      (default=1) Process from --start_replica to --replicas.
EOF
}

# Default values
PROCESS_PROT_ONLY=0
PROCESS_PROT_LIG=0
PROCESS_EQUI=1
PROCESS_PROD=1
PROCESS_RMSD=1
PROCESS_WAT=1
PROCESS_THERMO=1
PROCESS_IHBOND=0
REPLICAS=3
START_REPLICA=1
ENSEMBLE="npt"

# Check arguments
if [[ "$#" == 0 ]]; then
  echo "Error: No options provided."
  echo "Use --help option to check available options."
  exit 1
fi

# CLI option parser

while [[ $# -gt 0 ]]; do
  case "$1" in
    '--help' | '-h'            ) Help ; exit 0 ;;
    '-d' | '--work_dir'        ) shift ; WDDIR=$1 ;;
    '--prot_only'              ) shift ; PROCESS_PROT_ONLY=$1 ;;
    '--prot_lig'               ) shift ; PROCESS_PROT_LIG=$1 ;;
    '--equi'                   ) shift ; PROCESS_EQUI=$1 ;;
    '--prod'                   ) shift ; PROCESS_PROD=$1 ;;
    '--rmsd'                   ) shift ; PROCESS_RMSD=$1 ;;
    '--rmsd_mask'              ) shift ; MASK=$1 ;;
    '--dry'                    ) shift ; PROCESS_WAT=$1 ;;
    '--thermo'                 ) shift ; PROCESS_THERMO=$1 ;;
    '--mmpbsa_rescore'         ) shift ; MMPBSA_RESCORE=$1 ;;
    '--hbond'                  ) shift ; PROCESS_IHBOND=$1 ;;
    '-n' | '--replicas'        ) shift ; REPLICAS=$1 ;;
    '--start_replica'          ) shift ; START_REPLICA=$1 ;;
    *                          ) echo "Unrecognized command line option: $1" >> /dev/stderr ; exit 1 ;;
  esac
  shift
done

function CheckFiles() {
  # Check existence of files
  for ARG in "$@"; do
    if [[ ! -f ${ARG} ]]; then
      echo "Warning: ${ARG} file doesn't exist." >&2
      #exit 1
      return 1
    fi
  done
  return 0
}

function CheckProgram() {
  # Check if command is available
  for COMMAND in "$@"; do
    if ! command -v ${COMMAND} >/dev/null 2>&1; then
      echo "Error: ${COMMAND} program not available, exiting."
      exit 1
    fi
  done
}

function CheckVariable() {
  # Check if variable is empty or not defined.
  local var_name var_value
  for var_name in "$@"; do
    var_value="${!var_name}"  # indirección: obtiene el valor por nombre
    if [[ -z "${var_value}" ]]; then
      echo "Error: variable '${var_name}' is empty or not defined." >&2
      exit 1
    fi
  done
}

function ParseDirectories() {
  # Configure directories
  local mode=$1
  shift

  if [[ "$mode" == "prot_only" ]]; then
    EQUI_DIR=${WDDIR}/setupMD/${RECEPTOR_NAME}/onlyProteinMD/MD/rep${REP}/equi/${ENSEMBLE}
    PROD_DIR=${WDDIR}/setupMD/${RECEPTOR_NAME}/onlyProteinMD/MD/rep${REP}/prod/${ENSEMBLE}
    cd ${EQUI_DIR}
    TOPO_DIR=../../../../topo
    TOPO=$(echo ${TOPO_DIR}/*${RECEPTOR_NAME}_solv*.parm7)
    DRY_TOPO=$(echo ${TOPO_DIR}/*${RECEPTOR_NAME}_vac*.parm7)
    #cd ${WDDIR}
  elif [[ "$mode" == "prot_lig" ]]; then
    local lig=$1
    if [[ -z "${lig}" ]]; then
      echo "Error: ligand name is required for prot_lig mode"
      exit 1
    fi
    EQUI_DIR=${WDDIR}/setupMD/${RECEPTOR_NAME}/proteinLigandMD/${lig}/MD/rep${REP}/equi/${ENSEMBLE}
    PROD_DIR=${WDDIR}/setupMD/${RECEPTOR_NAME}/proteinLigandMD/${lig}/MD/rep${REP}/prod/${ENSEMBLE}
    cd ${EQUI_DIR}
    TOPO_DIR=../../../../topo
    TOPO=$(echo ${TOPO_DIR}/${lig}_solv_com.parm7)
    DRY_TOPO=$(echo ${TOPO_DIR}/${lig}_vac_com.parm7)
    #cd ${WDDIR}
  fi

}

function TotalResWrapper() {
  # Obtain total residue of solute, using dry topology.
  local dry_topo=$1
  TOTALRES=$(cpptraj -p ${dry_topo} --resmask \* | tail -n 1 | awk '{print $1}')
}

function RemoveWat() {
  local dir=$1
  shift
  local traj=($(echo "$@" | tr ' ' '\n' | sort -V))
  traj=(${traj[@]##*/})

  cat > ${dir}/remove_hoh.in <<EOF
parm ${TOPO}
EOF
  for trajectory in ${traj[@]}; do
    cat >> ${dir}/remove_hoh.in <<EOF
trajin ${trajectory}
EOF
  done
cat >> ${dir}/remove_hoh.in <<EOF
strip :WAT,Na+,K+,Cl-
autoimage :1-${TOTALRES}
trajout ./noWAT_traj.nc
EOF
  
  cd ${dir}
  cpptraj -i ${dir}/remove_hoh.in  || { echo "Error: cpptraj failed during RemoveWat"; exit 1; }
  cd ${WDDIR}
}

function RemoveWatMMPBSA() {
  # Obtain unsolvated trajectory from min2.rst7 file.
  local dir=$1
  cat > ${dir}/remove_hoh_MMPBSA_rescore.in <<EOF
parm ${TOPO}
trajin min2.rst7
strip :WAT,Na+,K+,Cl-
autoimage :1-${TOTALRES}
trajout ./min2_noWAT.nc
EOF

  cd ${dir}
  cpptraj -i ${dir}/remove_hoh_MMPBSA_rescore.in  || { echo "Error: cpptraj failed during RemoveWatMMPBSA"; exit 1; }
  cd ${WDDIR} 
}

function RMSD() {
  local dir=$1
  local target=$2
  local mode=$3

  if [[ -z ${MASK} ]]; then
    MASK=":1-${TOTALRES}@CA,C,N"
  fi

  cat > ${dir}/rmsd.in <<EOF
parm ${DRY_TOPO}
trajin ./noWAT_traj.nc
reference ${EQUI_DIR}/noWAT_traj.nc [minimized_pose]
rms ref [minimized_pose] out ${target}_rmsd_noWAT.data "${MASK}" perres perresout ${target}_rmsd_perres_noWAT.data range 1-${TOTALRES} perresmask "${MASK}"
average crdset Avg
EOF
  if [[ ${mode} == "prot_lig" ]]; then
    cat >> ${dir}/rmsd.in <<EOF
rms ref [minimized_pose] out ${LIG_NAME}_rmsd_LIG_noWAT.data :${TOTALRES}&!@H= nofit
EOF
    if [[ ${PROCESS_PROD} -eq 1 ]]; then
      cat >> ${dir}/rmsd.in <<EOF
rms ref [minimized_pose] out ${LIG_NAME}_rmsd_LIG_noWAT_test.data :${TOTALRES}&!@H= nofit
EOF
  fi

  fi
  cat >> ${dir}/rmsd.in <<EOF
run
rms ref Avg
  
atomicfluct out ${target}_rmsf_noWAT.data "${MASK}" byres
EOF
  if [[ ${mode} == "prot_lig" ]]; then
    cat >> ${dir}/rmsd.in <<EOF
atomicfluct out ${LIG_NAME}_rmsf_LIG_noWAT.data :${TOTALRES}&!@H= byres
EOF
  fi
  cd ${dir}
  if CheckFiles noWAT_traj.nc; then
    cpptraj -i ./rmsd.in || { echo "Error: cpptraj failed during RMSD"; exit 1; }
  fi
  cd ${WDDIR}

}

function ThermodynamicsData() {
  # Read data from .out files.
  local dir=$1
  local mode=$2

  if [[ ${mode} == "equi" ]]; then
    local outName="equi"
  else
    local outName="prod"
  fi

  if [[ -f ${dir}/process_out.in ]]; then
    rm ${dir}/process_out.in
  fi
  
  cd ${dir}
  local file
  for file in md_nvt_ntr*.out npt_equil*.out *md_prod*.out; do
    if [ -f "${file}" ]; then
      echo "readdata ${file} name OutputData" >> ${dir}/process_out.in
    fi
done

  cat >> ${dir}/process_out.in <<EOF
writedata ${outName}_Density.data OutputData[Density]
writedata ${outName}_Etot.data OutputData[EKtot]
writedata ${outName}_Temp.data OutputData[TEMP]
writedata ${outName}_Press.data OutputData[PRESS]
writedata ${outName}_Volume.data OutputData[VOLUME]
EOF

  cpptraj -i "${dir}/process_out.in" || { echo "Error with ThermodynamicsData(). Exiting."; exit 1; }
  cd ${WDDIR}
}
  

function IntermolecularHBond() {
  # Compute Hbond between ligand and protein.
  # only for prot lig mode.
  local dir=$1
  local target=$2
  local mode=$3

  if [[ ${mode} == "prot_lig" ]]; then
    cat > ${dir}/hbond.in <<EOF
parm ${DRY_TOPO}
trajin ./noWAT_traj.nc
hbond hbonds :1-${TOTALRES} avgout hbond_avg.data series uuseries hbond_series.data nointramol
go
lifetime hbonds[solutehb] out hbond_lifetime.data
go
EOF
    cd ${dir}
    cpptraj -i "${dir}/hbond.in" # || { echo "Error with IntermolecularHBond(). Exiting."; exit 1; }
    cd ${WDDIR}

  else
    echo "Warning in IntermolecularHBond: Trying to compute protein-ligand h-bonds in only_protein mode."
    echo "Skipping."
  fi
}

function Process() {
  mode=$1
  target=$2

  if [[ ${PROCESS_EQUI} -eq 1 ]]; then

    if [[ ${PROCESS_WAT} -eq 1 ]]; then
      RemoveWat ${EQUI_DIR} ${EQUI_DIR}/md_nvt_ntr.nc ${EQUI_DIR}/*npt_equil*.nc
    fi
    
    if [[ ${MMPBSA_RESCORE} -eq 1 ]]; then
      RemoveWatMMPBSA ${EQUI_DIR}
    fi
    
    if [[ ${PROCESS_RMSD} -eq 1 ]]; then
      RMSD ${EQUI_DIR} ${target} ${mode}
    fi

    if [[ ${PROCESS_THERMO} -eq 1 ]]; then
      ThermodynamicsData ${EQUI_DIR} "equi"
    fi

    if [[ ${PROCESS_IHBOND} -eq 1 ]]; then
      IntermolecularHBond ${EQUI_DIR} ${target} ${mode}
    fi

  fi

  if [[ ${PROCESS_PROD} -eq 1 ]]; then

    if [[ ${PROCESS_WAT} -eq 1 ]]; then
      RemoveWat ${PROD_DIR} ${PROD_DIR}/*md_prod*.nc
    fi
    
    if [[ ${MMPBSA_RESCORE} -eq 1 ]]; then
      RemoveWatMMPBSA ${PROD_DIR}
    fi

    if [[ ${PROCESS_RMSD} -eq 1 ]]; then
      RMSD ${PROD_DIR} ${target} ${mode}
    fi

    if [[ ${PROCESS_THERMO} -eq 1 ]]; then
      ThermodynamicsData ${PROD_DIR} "prod"
    fi

    if [[ ${PROCESS_IHBOND} -eq 1 ]]; then
      IntermolecularHBond ${PROD_DIR} ${target} ${mode}
    fi

  fi
}

function CheckUniqueFile() {
  # Support for only 1 cofactor and 1 pdb per run.
  local folder="$1"
  local count=$(find "${folder}" -maxdepth 1 \( -name "*.pdb" -o -name "*.mol2" \) | wc -l)

  if [[ ${count} -gt 1 ]]; then
    echo "$(basename ${folder}) folder contain more than one PDB or mol2 file."
    echo "Exiting."
    exit 1
  elif [[ ${count} -eq 0 ]]; then
    echo "$(basename ${folder}) folder is empty."
    echo "Exiting."
    exit 1
  fi

}
############################################################
# Main
############################################################
# Required options
CheckVariable "WDDIR"

WDDIR=$(realpath "$WDDIR")

CheckUniqueFile ${WDDIR}/receptor/
RECEPTOR_NAME=$(basename "${WDDIR}/receptor/"*.pdb .pdb)

CheckProgram "cpptraj"

for REP in $(seq ${START_REPLICA} ${REPLICAS}); do
  echo -e "\n Doing replica: ${REP}"

  if [[ -z ${PROCESS_PROT_ONLY} || -z ${PROCESS_PROT_LIG} ]]; then
    echo "Error: Must provide --prot_only or --prot_lig options."
    echo "Check help with --help."
    exit 1
  fi

  if [[ ${PROCESS_PROT_ONLY} -eq 1 ]]; then
    echo -e "\nDoing receptor: ${RECEPTOR_NAME}"
    ParseDirectories "prot_only"
    TotalResWrapper ${DRY_TOPO}
    Process "prot_only" ${RECEPTOR_NAME}

  fi

  if [[ ${PROCESS_PROT_LIG} -eq 1 ]]; then
    
    LIGANDS_PATH=("${WDDIR}/ligands/"*.mol2)
    
    if [[ ${#LIGANDS_PATH[@]} -eq 0 ]]; then
      echo "Error: --prot_lig is 1 but ligands folder is empty."
      exit 1
    fi

    for LIG_NAME in ${LIGANDS_PATH[@]}; do
      LIG_NAME=$(basename ${LIG_NAME} .mol2)
      echo "Doing ligand: ${LIG_NAME}"
      ParseDirectories "prot_lig" ${LIG_NAME}
      TotalResWrapper ${DRY_TOPO}
      Process "prot_lig" "${LIG_NAME}"
    done

  fi
    
done

echo "Done."

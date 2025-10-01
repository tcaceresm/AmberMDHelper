#!/usr/bin/bash

# Global variables are always UPPERCASE.
# Local are used with local keyword and lowercase.
# If some function requires too much arguments,
# try using global variables directly, however, this is harder to
# read and debug.

#set -x

function ScriptInfo() {
  DATE="2025"
  VERSION="1.0.2"
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
  echo -e "\nUsage: bash process_MD.sh OPTIONS\n"
  echo "This script process molecular dynamics simulations in the specified directory previously configured with setup_MD.sh."
  echo "This include:"
  echo " - remove solvent"
  echo " - RMSD and RMSF data generation"
  echo " - Temperature, Density and Total energy data generation"
  echo -e "\nThe specified directory must always have a folder named  \"receptor\" containing the receptor PDB 
and an optional \"ligands\" and \"cofactor\" folder containing MOL2 file of ligands and cofactor, respectively.\n"

  echo "Required options:"
  echo " -d, --work_dir     <DIR>       Working directory. Inside this directory, a folder named setupMD should exist, containing all output files."
  echo "Optional:"
  echo " -h, --help                      Show this help."
  echo " --prot_only        <0|1>          (default=0) Process only-protein MD."
  echo " --prot_lig         <0|1>          (default=0) Process protein-ligand MD."
  echo " --equi             <0|1>          (default=1) Process equilibration phase."
  echo " --prod             <0|1>          (default=1) Process production phase."
  echo " --rmsd             <0|1>          (default=1) Calculate RMSD and RMSF (whole dry system). Must have dry trajectories. see --dry option."
  echo " --rmsd_mask        <AMBER_MASK>   (default=":1-TOTALRES@CA,C,N"). Mask used to calculate RMSD and RMSF. (TOTALRES is the N° of residues and
                                   it's automatically determined)."
  echo " --dry              <0|1>          (default=1) Remove water and ions from trajectories."
  echo " --thermo           <0|1>          (default=1) Generate Temperature, Density and Total Energy data from trajectories. These are obtained from .out files."
  echo " -n, --replicas     <integer>      (default=3) Number of replicas or repetitions to process."
  echo " --start_replica    <integer>      (default=1) Process from --start_replica to --replicas."
}

# Check arguments
if [[ "$#" == 0 ]]; then
  echo "Error: No options provided."
  echo "Use --help option to check available options."
  exit 1
fi

# Default values
PROCESS_PROT_ONLY=0
PROCESS_PROT_LIG=0
PROCESS_EQUI=1
PROCESS_PROD=1
PROCESS_RMSD=1
PROCESS_WAT=1
PROCESS_THERMO=1
REPLICAS=3
START_REPLICA=1
ENSEMBLE="npt"


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
    '-n' | '--replicas'        ) shift ; REPLICAS=$1 ;;
    '--start_replica'          ) shift ; START_REPLICA=$1 ;;
    *                          ) echo "Unrecognized command line option: $1" >> /dev/stderr ; exit 1 ;;
  esac
  shift
done


function CheckProgram() {
  # Check if command is available
  for COMMAND in "$@"; do
    if ! command -v ${1} >/dev/null 2>&1; then
      echo "Error: ${1} program not available, exiting."
      exit 1
    fi
  done
}

function CheckVariable() {
  # Check if variable is not empty
  for ARG in "$@"; do
    if [[ -z ${ARG} ]]; then
      echo "Error: variable ${ARG}."
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
    cd ${WDDIR}
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
    cd ${WDDIR}
  fi

}

function TotalResWrapper() {
  # Obtain total residue of solute, using dry topology.
  DRY_TOPO=$1
  cd ${EQUI_DIR}
  TOTALRES=$(cpptraj -p ${DRY_TOPO} --resmask \* | tail -n 1 | awk '{print $1}')
  cd ${WDDIR}
}

function RemoveWat() {
  local dir=$1
  shift
  local traj=($@)
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
rms first out ${target}_rmsd_noWAT.data "${MASK}" perres perresout ${target}_rmsd_perres_noWAT.data range 1-${TOTALRES} perresmask "${MASK}"
average crdset Avg
EOF
  if [[ ${mode} == "prot_lig" ]]; then
    cat >> ${dir}/rmsd.in <<EOF
rms first out ${LIG_NAME}_rmsd_LIG_noWAT.data :${TOTALRES}&!@H= nofit
EOF
  fi
  cat >> ${dir}/rmsd.in <<EOF
rms ref Avg
  
atomicfluct out ${target}_rmsf_noWAT.data "${MASK}" byres
EOF
  if [[ ${mode} == "prot_lig" ]]; then
    cat >> ${dir}/rmsd.in <<EOF
atomicfluct out ${LIG_NAME}_rmsf_LIG_noWAT.data :${TOTALRES}&!@H= byres
EOF
  fi
  cd ${dir}
  cpptraj -i ./rmsd.in || { echo "Error: cpptraj failed during RMSD"; exit 1; }
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
  
function Process() {
  mode=$1
  target=$2

  if [[ ${PROCESS_EQUI} -eq 1 ]]; then

    if [[ ${PROCESS_WAT} -eq 1 ]]; then
      RemoveWat ${EQUI_DIR} md_nvt_ntr.nc *npt_equil*.nc
    fi

    if [[ ${PROCESS_RMSD} -eq 1 ]]; then
      RMSD ${EQUI_DIR} ${target} ${mode}
    fi

    if [[ ${PROCESS_THERMO} -eq 1 ]]; then
      ThermodynamicsData ${EQUI_DIR} "equi"
    fi
  fi

  if [[ ${PROCESS_PROD} -eq 1 ]]; then

    if [[ ${PROCESS_WAT} -eq 1 ]]; then
      RemoveWat ${PROD_DIR} *md_prod*.nc
    fi

    if [[ ${PROCESS_RMSD} -eq 1 ]]; then
      RMSD ${PROD_DIR} ${target} ${mode}
    fi

    if [[ ${PROCESS_THERMO} -eq 1 ]]; then
      ThermodynamicsData ${PROD_DIR} "prod"
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
  fi

}
############################################################
# Main
############################################################
# Required options
CheckVariable "${WDDIR}"

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
      Process "prot_lig" ${LIG_NAME}
    done

  fi
    
done

echo "Done."

#!/usr/bin/bash

# Global variables are always UPPERCASE.
# Local are used with local keyword and lowercase.
# If some function requires too much arguments,
# try using global variables directly, however, this is harder to
# read and debug.

#set -x

function ScriptInfo() {
  DATE="2025"
  VERSION="0.0.1"
  GH_URL="https://github.com/tcaceresm/AmberMDHelper"
  LAB="http://schuellerlab.org/"

  cat <<EOF
###################################################
 Welcome to run_MD version ${VERSION} ${DATE}   
  Author: Tomás Cáceres <caceres.tomas@uc.cl>    
  Laboratory of Molecular Design <${LAB}>
  Laboratory of Computational simulation & drug design        
  GitHub <${GH_URL}>                             
  Powered by high fat food and procrastination   
###################################################
EOF
}

Help() {
  ScriptInfo
  echo -e "\nUsage: bash run_MD.sh OPTIONS\n"
  echo "This script runs molecular dynamics simulations in the specified directory previously configured with setup_MD.sh"
  echo -e "The specified directory must always have a folder named  \"receptor\" containing the receptor PDB 
and an optional \"ligands\" and \"cofactor\" folder containing MOL2 file of ligands and cofactor, respectively.\n"

  echo "Required options:"
  echo " -d, --work_dir     <DIR>       Working directory. Inside this directory, a folder named setupMD should exist, containing all input files."
  echo "Optional:"
  echo " -h, --help                      Show this help."
  echo " --prot_only        <0|1>        (default=0) Run only-protein MD."
  echo " --prot_lig         <0|1>        (default=0) Run protein-ligand MD."
  echo " --run_equi         <0|1>        (default=1) Run equilibration phase."
  echo " --run_prod         <0|1>        (default=1) Run production phase."
  echo " -n, --replicas     <integer>    (default=3) Number of replicas or repetitions."
  echo " --start_replica    <integer>    (default=1) Run from --start_replica to --replicas."
  echo " --MD_prog          <str>        (default="pmemd.cuda") Program used to run MD."
}

# Default values
PROT_ONLY_MD=0
PROT_LIG_MD=0
RUN_EQUI=1
RUN_PROD=1
START_REPLICA=1
ENSEMBLE="npt"
MD_PROG="pmemd.cuda"


# CLI option parser
while [[ $# -gt 0 ]]; do
  case "$1" in
  '-d' | '--work_dir'        ) shift ; WDDIR=$1 ;;
  '--prot_only'              ) shift ; PROT_ONLY_MD=$1 ;;
  '--prot_lig'               ) shift ; PROT_LIG_MD=$1 ;;
  '--run_equi'               ) shift ; RUN_EQUI=$1 ;;
  '--run_prod'               ) shift ; RUN_PROD=$1 ;;
  '-n' | '--replicas'        ) shift ; REPLICAS=$1 ;;
  '--start_replica'          ) shift ; START_REPLICA=$1 ;;
  '--MD_prog'                ) shift ; MD_PROG=$1 ;;
  '--help' | '-h'            ) Help ; exit 0 ;;
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

function ParseDirectories() {
  # Configure directories
  local mode=$1
  shift

  if [[ "$mode" == "prot_only" ]]; then
    CRD=${WDDIR}/setupMD/${RECEPTOR_NAME}/onlyProteinMD/topo/${RECEPTOR_NAME}_solv
    TOPO=${WDDIR}/setupMD/${RECEPTOR_NAME}/onlyProteinMD/topo/${RECEPTOR_NAME}_solv
    EQUI_DIR=${WDDIR}/setupMD/${RECEPTOR_NAME}/onlyProteinMD/MD/rep${REP}/equi/${ENSEMBLE}
    PROD_DIR=${WDDIR}/setupMD/${RECEPTOR_NAME}/onlyProteinMD/MD/rep${REP}/prod/${ENSEMBLE}
    
  elif [[ "$mode" == "prot_lig" ]]; then

    local lig=$1
    if [[ -z "${lig}" ]]; then
      echo "Error: ligand name is required for prot_lig mode"
      exit 1
    fi
    CRD=${WDDIR}/setupMD/${RECEPTOR_NAME}/proteinLigandMD/topo/${lig}_solv
    TOPO=${WDDIR}/setupMD/${RECEPTOR_NAME}/proteinLigandMD/topo/${lig}_solv
    EQUI_DIR=${WDDIR}/setupMD/${RECEPTOR_NAME}/proteinLigandMD/${lig}/MD/rep${REP}/equi/${ENSEMBLE}
    PROD_DIR=${WDDIR}/setupMD/${RECEPTOR_NAME}/proteinLigandMD/${lig}/MD/rep${REP}/prod/${ENSEMBLE}
  fi

}

function RunMD() {
  # Actually run the MD
  INPUT_FILE=$1
  RESTART_FILE=$2

  CheckProgram ${MD_PROG}

  # TOPO and CRD variable comes from ParseDirectories
  # Check if already run, or if finished incorrectly
  if [[ -f "${INPUT_FILE}.nc" && ! -f "${INPUT_FILE}_successful.tmp" ]]; then
    echo "${INPUT_FILE} output exists but didn't finished correctly".
    echo "Please check ${INPUT_FILE}.out"
    echo "Exiting."
    exit 1

  elif [[ -f "${INPUT_FILE}_successful.tmp" ]]; then
    echo "${INPUT_FILE} already executed succesfully."
    echo "Skipping."
  
  else  
    echo "Running ${INPUT_FILE}.in"

    ${MD_PROG} -O -i ${INPUT_FILE}.in -o ${INPUT_FILE}.out -p ${TOPO}.parm7 -x ${INPUT_FILE}.nc \
              -r ${INPUT_FILE}.rst7 -c ${RESTART_FILE}.rst7 -ref ${CRD}.rst7 -inf ${INPUT_FILE}.info \
              || { echo "Error: ${MD_PROG} failed during ${INPUT_FILE}"; exit 1; }

    touch "${INPUT_FILE}_successful.tmp"
    echo "Done ${INPUT_FILE}."
  fi
}

function RunProtocol() {
  # RUN_EQUI and RUN_PROD comes from cli options
  # DIRs comes from ParseDirectorioes
  # RunMD is the function that perform MD

  if [[ ${RUN_EQUI} -eq 1 ]]; then

    cd ${EQUI_DIR}

    # Can adjust this to your needs
    RunMD min1 "${CRD}" 
    RunMD min2 min1

    RunMD md_nvt_ntr min2
    RunMD npt_equil_1 md_nvt_ntr

    RunMD npt_equil_2 npt_equil_1 
    RunMD npt_equil_3 npt_equil_2
    RunMD npt_equil_4 npt_equil_3
    RunMD npt_equil_5 npt_equil_4
    RunMD npt_equil_6 npt_equil_5
    
    cd ${WDDIR}

  fi

  if [[ ${RUN_PROD} -eq 1 ]]; then
    # Can adjust this to your needs
    cd ${PROD_DIR}

    RunMD md_prod npt_equil_6
    
    cd ${WDDIR}
  fi
}

############################################################
# Main
############################################################

RECEPTOR_NAME=$(basename "${WDDIR}/receptor/"*.pdb .pdb)

for REP in $(seq ${START_REPLICA} ${REPLICAS}); do

  if [[ ${PROT_ONLY_MD} -eq 1 ]]; then
    ParseDirectories "prot_only"
    RunProtocol
  fi

  if [[ ${PROT_LIG_MD} -eq 1 ]]; then
    
    LIGANDS_PATH=("${WDDIR}/ligands/"*.mol2)
    
    if [[ ${#LIGANDS_PATH[@]} -eq 0 ]]; then
      echo "Error: --prot_lig is 1 but ligands folder is empty."
      exit 1
    fi

    for LIG_NAME in ${LIGANDS_PATH[@]}; do
      LIG_NAME=$(basename ${LIG_NAME} .mol2)
      ParseDirectories "prot_lig" ${LIG_NAME}
      RunProtocol
    done

  else
    echo "Error: Must provide --prot_only or --prot_lig options."
    echo "Check help with --help."
    exit 1
  fi

done

echo "Done."
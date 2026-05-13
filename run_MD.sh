#!/usr/bin/bash

# Global variables are always UPPERCASE.
# Local are used with local keyword and lowercase.
# If some function requires too much arguments,
# try using global variables directly, however, this is harder to
# read and debug.

#set -x

function ScriptInfo() {
  DATE="2025"
  VERSION="1.2.1"
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
  cat <<EOF

Usage: bash run_MD.sh OPTIONS

This script runs molecular dynamics simulations in the specified directory
previously configured with setup_MD.sh. The specified directory must always
have a folder named "receptor" containing the receptor PDB and an optional
"ligands" and "cofactor" folder containing MOL2 file of ligands and cofactor, respectively.

Required options:
  -d, --work_dir     <DIR>        Working directory. Inside this directory, 
                                  a folder named setupMD should exist, containing all input files.
Optional:
  -h, --help                      Show this help.
  --prot_only        <0|1>        (default=0) Run only-protein MD.
  --prot_lig         <0|1>        (default=0) Run protein-ligand MD.
  --run_equi         <0|1>        (default=1) Run equilibration phase.
  --run_prod         <0|1>        (default=1) Run production phase.
  -n, --replicas     <integer>    (default=3) Number of replicas or repetitions.
  --start_replica    <integer>    (default=1) Run from --start_replica to --replicas.
  --MD_prog          <str>        (default="pmemd.cuda") Program used to run MD.
EOF
}

# Default values
PROT_ONLY_MD=0
PROT_LIG_MD=0
RUN_EQUI=1
RUN_PROD=1
START_REPLICA=1
REPLICAS=3
ENSEMBLE="npt"
MMPBSA=0
MD_PROG="pmemd.cuda"

# Check arguments
if [[ "$#" == 0 ]]; then
  echo "Error: No options provided."
  echo "Use --help option to check available options."
  exit 1
fi

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
  '--mmpbsa_rescoring'       ) shift ; MMPBSA=$1 ;;
  '--mmpbsa_crd'             ) shift ; MMPBSA_CRD=$1 ;;
  '--MD_prog'                ) shift ; MD_PROG=$1 ;;
  '--help' | '-h'            ) Help ; exit 0 ;;
  *                          ) echo "Unrecognized command line option: $1" >> /dev/stderr ; exit 1 ;;
  esac
  shift
done

function CheckProgram() {
  # Check if command is available
  for COMMAND in "$@"; do
    if ! command -v ${COMMAND} >/dev/null 2>&1; then
      echo "Error: ${1} program not available, exiting."
      exit 1
    fi
  done
}

function CheckFiles() {
  # Check existence of files
  for ARG in "$@"; do
    if [[ ! -f ${ARG} ]]; then
      echo "Error: ${ARG} file doesn't exist."
      exit 1
    fi
  done
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
    CRD=${WDDIR}/setupMD/${RECEPTOR_NAME}/onlyProteinMD/topo/*${RECEPTOR_NAME}_solv*
    TOPO=${WDDIR}/setupMD/${RECEPTOR_NAME}/onlyProteinMD/topo/*${RECEPTOR_NAME}_solv*
    EQUI_DIR=${WDDIR}/setupMD/${RECEPTOR_NAME}/onlyProteinMD/MD/rep${REP}/equi/${ENSEMBLE}
    PROD_DIR=${WDDIR}/setupMD/${RECEPTOR_NAME}/onlyProteinMD/MD/rep${REP}/prod/${ENSEMBLE}
    
  elif [[ "$mode" == "prot_lig" ]]; then

    local lig=$1

    if [[ -z "${lig}" ]]; then
      echo "Error: ligand name is required for prot_lig mode"
      exit 1
    fi
    CRD=${WDDIR}/setupMD/${RECEPTOR_NAME}/proteinLigandMD/${lig}/topo/${lig}_solv_com
    TOPO=${WDDIR}/setupMD/${RECEPTOR_NAME}/proteinLigandMD/${lig}/topo/${lig}_solv_com
    EQUI_DIR=${WDDIR}/setupMD/${RECEPTOR_NAME}/proteinLigandMD/${lig}/MD/rep${REP}/equi/${ENSEMBLE}
    PROD_DIR=${WDDIR}/setupMD/${RECEPTOR_NAME}/proteinLigandMD/${lig}/MD/rep${REP}/prod/${ENSEMBLE}

    # For mmpbsa_rescoring
    MMPBSA_rescore_DIR=${WDDIR}/setupMD/${RECEPTOR_NAME}/proteinLigandMD/${lig}/mmpbsa/
    VAC_COMPLEX_TOPO=${WDDIR}/setupMD/${RECEPTOR_NAME}/proteinLigandMD/${lig}/topo/${lig}_vac_com
    VAC_REC_TOPO=${WDDIR}/setupMD/${RECEPTOR_NAME}/proteinLigandMD/${lig}/topo/${lig}_vac_rec
    VAC_LIG_TOPO=${WDDIR}/setupMD/${RECEPTOR_NAME}/proteinLigandMD/${lig}/topo/${lig}_vac_lig
  fi

}

function RunMD() {
  # Actually run the MD
  INPUT_FILE=$1
  RESTART_FILE=$2
  local MD_LOG="${LOG_DIR}/${INPUT_FILE}.log"

  md_log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${INPUT_FILE}] $*" | tee -a "${MD_LOG}" >> "${MAIN_LOG}"
  }

  CheckProgram ${MD_PROG}

  # TOPO and CRD variable comes from ParseDirectories
  # Check if already run, or if finished incorrectly
  # -ref flag is ignored when ntr is 0

  if [[ -f "${INPUT_FILE}.nc" && ! -f "${INPUT_FILE}_successful.tmp" ]]; then
    md_log "ERROR: output exists but did not finish correctly. Check ${INPUT_FILE}.out"
    exit 1
  fi

  if [[ -f "${INPUT_FILE}_successful.tmp" ]]; then
    md_log "Already executed successfully. Skipping."

  else  # run MD
    md_log "Starting ${MD_PROG}"

    ${MD_PROG} -O \
        -i   "${INPUT_FILE}.in"     \
        -o   "${INPUT_FILE}.out"    \
        -p   "${TOPO}.parm7"        \
        -x   "${INPUT_FILE}.nc"     \
        -r   "${INPUT_FILE}.rst7"   \
        -c   "${RESTART_FILE}.rst7" \
        -ref "${CRD}.rst7"          \
        -inf "${INPUT_FILE}.info"

    if [[ $? -ne 0 ]]; then
      md_log "ERROR: ${MD_PROG} failed (non-zero exit code). Check ${INPUT_FILE}.out"
      exit 1
    fi

    md_log "Finished successfully."
  fi
}

function RunProtocol() {
  # RUN_EQUI and RUN_PROD comes from cli options
  # DIRs comes from ParseDirectorioes
  # RunMD is the function that perform MD

  local mode=$1
  local dir=$2

  if [[ ${mode} == "equi" ]]; then

    cd ${dir}

    # Can adjust this to your needs, ensure to match the protocol used in setupMD.sh.
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

  if [[ ${mode} == "prod" ]]; then
    # Can adjust this to your needs
    cd ${dir}

    RunMD md_prod ${EQUI_DIR}/npt_equil_6
    
    cd ${WDDIR}
  fi
}

function log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${MAIN_LOG}"
}

############################################################
# Main
############################################################

CheckVariable "WDDIR"
WDDIR=$(realpath "$WDDIR")

# Logging
LOG_DIR="${WDDIR}/logs/runMD/$(date '+%Y-%m-%d_%H-%M-%S')"
mkdir -p "${LOG_DIR}"
MAIN_LOG="${LOG_DIR}/run_MD.log"

log "=========================================="
log "Starting run_MD"
log "=========================================="
log "CLI flags:"
log " --work_dir          : ${WDDIR}"
log " --prot_only         : ${PROT_ONLY_MD}"
log " --prot_lig          : ${PROT_LIG_MD}"
log " --run_equi          : ${RUN_EQUI}"
log " --run_prod          : ${RUN_PROD}"
log " --replicas          : ${REPLICAS}"
log " --start_replica     : ${START_REPLICA}"
log " --mmpbsa_rescoring  : ${MMPBSA}"
log " --mmpbsa_crd        : ${MMPBSA_CRD}"
log " --MD_prog           : ${MD_PROG}"
log "Receptor             : ${RECEPTOR_NAME}"
log "Working directory    : ${WDDIR}"
log "Replicas             : ${START_REPLICA} to ${REPLICAS}"
log "MD program           : ${MD_PROG}"
log "Log directory        : ${LOG_DIR}"
log "Log file             : ${MAIN_LOG}"
log "=========================================="

CheckUniqueFile ${WDPATH}/receptor/
RECEPTOR_NAME=$(basename "${WDDIR}/receptor/"*.pdb .pdb)

if [[ ${PROT_ONLY_MD} -eq 0 && ${PROT_LIG_MD} -eq 0 ]]; then
    log "Error: Must provide --prot_only or --prot_lig options."
    exit 1
fi

for REP in $(seq ${START_REPLICA} ${REPLICAS}); do

  if [[ ${PROT_ONLY_MD} -eq 1 ]]; then
    log "Protein-only mode | receptor: ${RECEPTOR_NAME} | rep: ${REP}"
    ParseDirectories "prot_only"

    if [[ ${RUN_EQUI} -eq 1 ]]; then
      RunProtocol "equi" ${EQUI_DIR}
    fi

    if [[ ${RUN_PROD} -eq 1 ]]; then
      RunProtocol "prod" ${PROD_DIR}
    fi

  fi

  if [[ ${PROT_LIG_MD} -eq 1 ]]; then
    
    LIGANDS_PATH=("${WDDIR}/ligands/"*.mol2)
    
    if [[ ${#LIGANDS_PATH[@]} -eq 0 ]]; then
      log "Error: --prot_lig is 1 but ligands folder is empty."
      exit 1
    fi

    for LIG_NAME in ${LIGANDS_PATH[@]}; do

      # Required for both MD and MMPBSA
      LIG_NAME=$(basename ${LIG_NAME} .mol2)
      log "Protein-ligand mode | ligand: ${LIG_NAME} | rep: ${REP}"

      ParseDirectories "prot_lig" ${LIG_NAME}
      
      # MD

      if [[ ${RUN_EQUI} -eq 1 ]]; then
        RunProtocol "equi" ${EQUI_DIR}
      fi

      if [[ ${RUN_PROD} -eq 1 ]]; then
        RunProtocol "prod" ${PROD_DIR}
      fi

      if [[ ${MMPBSA} -eq 1 ]]; then
        RunMMPBSArescoreProtocol ${MMPBSA_rescore_DIR} "min2_noWAT.rst7"
      fi
    done

  fi

done

log "Done."
echo "Done."
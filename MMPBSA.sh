#!/usr/bin/bash

# Global variables are always UPPERCASE.
# Local are used with local keyword and lowercase.
# If some function requires too much arguments,
# try using global variables directly, however, this is harder to
# read and debug.

#set -x

# To do: 
#        1. Add options for mmpbsa input file (mmpbsa.py)
#        2. Add a option to modify PBRadii.
#           Instead of relying only in one topology file (the one created with setupMD script),            
#           add an option to modify that topology, and create a new one using a specific PBRadii.
#           This new topo file is the one used in MM/PBSA calculations, and it should be inside mmpbsa folder, not topo folder.

function ScriptInfo() {
  DATE="2025"
  VERSION="0.0.1"
  GH_URL="https://github.com/tcaceresm/AmberMDHelper"
  LAB="http://schuellerlab.org/"

  cat <<EOF
###################################################
 Welcome to MMPBSA version ${VERSION} ${DATE}   
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

Usage: bash MMPBSA.sh OPTIONS

This script perform MM/PB(G)SA calculations.
It requires a unsolvated topology for complex, receptor and ligand, and a trajectory file.

A folder structure and topologies obtained with setup_MD.sh is required.
Also, trajectories obtained with run_MD.sh are required.

Required options:
 -d, --work_dir     <DIR>        Working directory. Inside this directory, a folder named setupMD should exist, containing all input files.
                                 Also, a ligands and receptor folders are required to parse files.
Optional:
 -h, --help                      Show this help.
 --equi             <0|1>        (default=1) Perform MM/PBSA using equilibration phase trajectory (noWAT_traj.nc)
 --prod             <0|1>        (default=1) Perform MM/PBSA using production phase trajectory (noWAT_traj.nc).
 --rescore          <0|1>        (default=0) Perform MM/PBSA using minimized (2-step energy minimization) structure from equilibration phase.
 --interval         <integer>    (default=1) The offset from which to choose frames from each trajectory file.
 -n, --replicas     <integer>    (default=3) Number of replicas or repetitions.
 --start_replica    <integer>    (default=1) Run from --start_replica to --replicas.
 --parallel         <0|1>        (default=0) Use MMPBSA.py.MPI to run parallel calculations.
 --cores            <integer>    (default=4) Number of cores to parallelize, if --parallel is set to 1.
EOF
}

# Check arguments
if [[ "$#" == 0 ]]; then
  echo "No options provided."
  echo "Use --help option to check available options."
  exit 1
fi

# Default values

RUN_EQUI=1
RUN_PROD=1
RUN_RESCORE=0
INTERVAL=1
START_REPLICA=1
REPLICAS=3
PARALLEL=0
CORES=4
INPUT_FILE="mm_pbsa.in"


# CLI option parser
while [[ $# -gt 0 ]]; do
  case "$1" in
  '-d' | '--work_dir'        ) shift ; WDDIR=$1 ;;
  '--equi'                   ) shift ; RUN_EQUI=$1 ;;
  '--prod'                   ) shift ; RUN_PROD=$1 ;;
  '--rescore'                ) shift ; RUN_RESCORE=$1 ;;
  '--interval'               ) shift ; INTERVAL=$1 ;;
  '-n' | '--replicas'        ) shift ; REPLICAS=$1 ;;
  '--start_replica'          ) shift ; START_REPLICA=$1 ;;
  '--parallel'               ) shift ; PARALLEL=$1 ;;
  '--cores'                  ) shift ; CORES=$1 ;;
  '--help' | '-h'            ) Help ; exit 0 ;;
  *                          ) echo "Unrecognized command line option: $1" >> /dev/stderr ; exit 1 ;;
  esac
  shift
done

function CheckProgram() {
  # Check if command is available
  for COMMAND in "$@"; do
    if ! command -v ${COMMAND} >/dev/null 2>&1; then
      echo "Error: ${COMMAND} program not available, exiting."
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

function log() {
  local timestamp="[$(date '+%Y-%m-%d %H:%M:%S')]"
  local first_line=1
  local padding=""
  echo "$*" | while IFS= read -r line; do
    # Strip leading whitespace
    line="${line#"${line%%[![:space:]]*}"}"
    if [[ ${first_line} -eq 1 ]]; then
      echo "${timestamp} ${line}"
      local prefix="${timestamp} "
      local before_flag="${line%%-*}"
      padding="${prefix//?/ }${before_flag//?/ }"
      first_line=0
    else
      echo "${padding}${line}"
    fi
  done | tee -a "${MAIN_LOG}"
}

function ParseDirectory() {
  local mode=$1
  local lig=$2
  local rep=$3

  if [[ "mode" == "rescore" ]]; then
    MMPBSA_DIR=${WDDIR}/setupMD/${RECEPTOR_NAME}/proteinLigandMD/${lig}/MD/rep${rep}/equi/npt/mmpbsa_rescore
  else
    MMPBSA_DIR=${WDDIR}/setupMD/${RECEPTOR_NAME}/proteinLigandMD/${lig}/MD/rep${rep}/${mode}/npt/mmpbsa
  fi
  mkdir -p ${MMPBSA_DIR}

}

function ParseFiles() {
  # Set topologies and trajectories files.
  # For an unknow reason, MMPBSA.py fails if absolute paths are used.
  # I'm using relative paths to ${MMPBSA_DIR}

  local mode=$1
  local lig=$2
  local rep=$3

  if [[ -z "${lig}" ]]; then
    echo "Error in ParseDirectories(): lig variable is required."
    exit 1
  fi

  # Topologies
  # VAC_COM_TOPO=${WDDIR}/setupMD/${RECEPTOR_NAME}/proteinLigandMD/${lig}/topo/${lig}_vac_com.parm7
  # VAC_REC_TOPO=${WDDIR}/setupMD/${RECEPTOR_NAME}/proteinLigandMD/${lig}/topo/${lig}_vac_rec.parm7
  # VAC_LIG_TOPO=${WDDIR}/setupMD/${RECEPTOR_NAME}/proteinLigandMD/${lig}/topo/${lig}_vac_lig.parm7
  VAC_COM_TOPO="../../../../../topo/${lig}_vac_com.parm7"
  VAC_REC_TOPO="../../../../../topo/${lig}_vac_rec.parm7"
  VAC_LIG_TOPO="../../../../../topo/${lig}_vac_lig.parm7"

  CheckFiles ${VAC_COM_TOPO} ${VAC_REC_TOPO} ${VAC_LIG_TOPO}

  # Trajectories
  if [[ "${mode}" == "equi" ]]; then
    # EQUI_TRAJ=${WDDIR}/setupMD/${RECEPTOR_NAME}/proteinLigandMD/${lig}/MD/rep${rep}/${mode}/npt/noWAT_traj.nc
    EQUI_TRAJ="../noWAT_traj.nc"
    CheckFiles ${EQUI_TRAJ}
  fi

  if [[ "${mode}" == "prod" ]]; then
    # PROD_TRAJ=${WDDIR}/setupMD/${RECEPTOR_NAME}/proteinLigandMD/${lig}/MD/rep${rep}/${mode}/npt/noWAT_traj.nc
    PROD_TRAJ="../noWAT_traj.nc"
    CheckFiles ${PROD_TRAJ}
  fi

  if [[ "${mode}" == "rescore" ]]; then
    RESCORE_TRAJ="../min2_noWAT.rst7"
    CheckFiles ${RESCORE_TRAJ}
  fi
}

function CreateInputFile() {
  # MM/PBSA input file
  local mmpbsa_dir=$1

  cat > ${INPUT_FILE} <<EOF
Input file for PB calculation
&general
startframe=1, endframe=99999, interval=${INTERVAL},
verbose=2, keep_files=0, netcdf=1,
/
&pb
istrng=0.15, fillratio=4.0,
/
&decomp
dec_verbose=1, idecomp=1,
/
EOF
}

function RunMMPBSA() {
  # Run mmpbsa
  # Two options: serial and cpu parallelized using mpi
  local parallel=$1
  local cores=$2
  local input_file=$3
  local traj=$4
  local com_topo=$5
  local rec_topo=$6
  local lig_topo=$7

  if [[ ${parallel} -eq 1 ]]; then
    EXE="mpirun -np ${cores} MMPBSA.py.MPI"
    CheckProgram ${EXE}
  else
    EXE="MMPBSA.py"
    CheckProgram ${EXE}
  fi

  log "${EXE} -O -i ${input_file}
            -o mmpbsa_results.data
            -eo per_frame_mmpbsa_results.data
            -do decomp_mmpbsa_results.data
            -deo per_frame_decomp_mmpbsa_results.data
            -cp ${com_topo}
            -rp ${rec_topo}
            -lp ${lig_topo}
            -y ${traj}"
  # Run MMPBSA
  ${EXE} -O -i ${input_file} \
            -o mmpbsa_results.data \
            -eo per_frame_mmpbsa_results.data \
            -do decomp_mmpbsa_results.data \
            -deo per_frame_decomp_mmpbsa_results.data \
            -cp ${com_topo} \
            -rp ${rec_topo} \
            -lp ${lig_topo} \
            -y ${traj} \
            || { echo "Error running MMPBSA. Exiting."; exit 1; }
}

############################################################
# Main
############################################################

WDDIR=$(realpath "$WDDIR")

RECEPTOR_NAME=$(basename "${WDDIR}/receptor/"*.pdb .pdb)

# Logging: un único log por receptor, cubre todos los ligandos y repeticiones
LOG_DIR="${WDDIR}/setupMD/${RECEPTOR_NAME}/proteinLigandMD"
mkdir -p "${LOG_DIR}"
MAIN_LOG="${LOG_DIR}/mmpbsa.log"

log "=========================================="
log "Starting MMPBSA"
log "CLI flags:"
log " --work_dir        : ${WDDIR}"
log " --equi            : ${RUN_EQUI}"
log " --prod            : ${RUN_PROD}"
log " --rescore         : ${RUN_RESCORE}"
log " --interval        : ${INTERVAL}"
log " --replicas        : ${REPLICAS}"
log " --start_replica   : ${START_REPLICA}"
log " --parallel        : ${PARALLEL}"
log " --cores           : ${CORES}"
log "Receptor          : ${RECEPTOR_NAME}"
log "Log file          : ${MAIN_LOG}"
log "Working directory: ${WDDIR}"
log "Receptor: ${RECEPTOR_NAME}"
log "Replicas: ${START_REPLICA} to ${REPLICAS}"
log "Run equi: ${RUN_EQUI} | Run prod: ${RUN_PROD} | Run rescore: ${RUN_RESCORE}"
log "Log file: ${MAIN_LOG}"
log "=========================================="

for REP in $(seq ${START_REPLICA} ${REPLICAS}); do

  LIGANDS_PATH=("${WDDIR}/ligands/"*.mol2)
  
  if [[ ${#LIGANDS_PATH[@]} -eq 0 ]]; then
    echo "Error: ligands folder is empty."
    exit 1
  fi

  for LIG_NAME in ${LIGANDS_PATH[@]}; do

    # Required for both MD and MMPBSA
    LIG_NAME=$(basename ${LIG_NAME} .mol2)
    log "=========================================="
    log "Ligand: ${LIG_NAME} | Rep: ${REP}"
    log "=========================================="

    if [[ ${RUN_RESCORE} -eq 1 ]]; then
      log "Doing MMPBSA rescoring | ligand: ${LIG_NAME} | rep: ${REP}"
      ParseDirectory "rescore" ${LIG_NAME} ${REP}

      cd ${MMPBSA_DIR}
      log "Current working directory: ${MMPBSA_DIR}"

      ParseFiles "rescore" ${LIG_NAME} ${REP}
      CreateInputFile ${MMPBSA_DIR}
    
      RunMMPBSA ${PARALLEL} ${CORES} ${INPUT_FILE} \
                ${EQUI_TRAJ} ${VAC_COM_TOPO} ${VAC_REC_TOPO} \
                ${VAC_LIG_TOPO}
    
      cd ${WDDIR}
      log "Done rescore | ligand: ${LIG_NAME} | rep: ${REP}"
    fi

    if [[ ${RUN_EQUI} -eq 1 ]]; then
      log "Doing equi MMPBSA | ligand: ${LIG_NAME} | rep: ${REP}"
      ParseDirectory "equi" ${LIG_NAME} ${REP}

      cd ${MMPBSA_DIR}
      log "Current working directory: ${MMPBSA_DIR}"
      ParseFiles "equi" ${LIG_NAME} ${REP}
      CreateInputFile ${MMPBSA_DIR}
    
      RunMMPBSA ${PARALLEL} ${CORES} ${INPUT_FILE} \
                ${EQUI_TRAJ} ${VAC_COM_TOPO} ${VAC_REC_TOPO} \
                ${VAC_LIG_TOPO}
    
      cd ${WDDIR}
      log "Done equi | ligand: ${LIG_NAME} | rep: ${REP}"
    fi

    if [[ ${RUN_PROD} -eq 1 ]]; then
      log "Doing prod MMPBSA | ligand: ${LIG_NAME} | rep: ${REP}"
      ParseDirectory "prod" ${LIG_NAME} ${REP}

      cd ${MMPBSA_DIR}
      log "Current working directory: ${MMPBSA_DIR}"

      ParseFiles "prod" ${LIG_NAME} ${REP}
      CreateInputFile ${MMPBSA_DIR}
    
      RunMMPBSA ${PARALLEL} ${CORES} ${INPUT_FILE} \
                ${PROD_TRAJ} ${VAC_COM_TOPO} ${VAC_REC_TOPO} \
                ${VAC_LIG_TOPO}
    
      cd ${WDDIR}
      log "Done prod | ligand: ${LIG_NAME} | rep: ${REP}"
    fi

  done
done

log "=========================================="
log "MMPBSA completed successfully"
log "=========================================="
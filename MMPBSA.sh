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
 --n_wat            <integer>    (default=0) For explicit-water MM/PBSA. Keep the N closest water molecules to the ligand.
 --start_frame      <integer>    (default=1) The first frame read by MMPBSA.
 --last_frame       <integer>    The last frame read by MMPBSA. Default is LASTFRAME of trajectory and its automatically calcualted.
 --interval         <integer>    Step between frames read by MMPBSA. Mutually exclusive with --n_frames.
 --n_frames         <integer>    N evenly spaced frames, from --start_frame to --end_frame, to be used by MMPBSA.
                                 Default is to use all available frames.
 -n, --replicas     <integer>    (default=3) Number of replicas or repetitions.
 --start_replica    <integer>    (default=1) Run from --start_replica to --replicas.
 --parallel         <0|1>        (default=0) Use MMPBSA.py.MPI to run parallel calculations.
 --cores            <integer>    (default=4) Number of cores to parallelize, if --parallel is set to 1.
EOF
}

# Check arguments
if [ "$#" -eq 0 ]; then
  echo "No options provided."
  echo "Use --help option to check available options."
  exit 1
fi

# Default values

RUN_EQUI=1
RUN_PROD=1
RUN_RESCORE=0
N_WAT=0
START_FRAME=1
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
  '--n_wat'                  ) shift ; N_WAT=$1 ;;
  '--start_frame'            ) shift ; START_FRAME=$1 ;;
  '--last_frame'             ) shift ; LAST_FRAME=$1 ;;
  '--interval'               ) shift ; INTERVAL=$1 ;;
  '--n_frames'               ) shift ; N_FRAMES=$1 ;;
  '-n' | '--replicas'        ) shift ; REPLICAS=$1 ;;
  '--start_replica'          ) shift ; START_REPLICA=$1 ;;
  '--parallel'               ) shift ; PARALLEL=$1 ;;
  '--cores'                  ) shift ; CORES=$1 ;;
  '--help' | '-h'            ) Help ; exit 0 ;;
  *                          ) echo "Unrecognized command line option: $1" >> /dev/stderr ; exit 1 ;;
  esac
  shift
done

if [ -n "${INTERVAL}" ] && [ -n "${N_FRAMES}" ]; then
  echo "Error: --interval and --n_frames are mutually exclusive. Use one or the other."
  exit 1
fi

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
    if [ ! -f "${ARG}" ]; then
      echo "Error: ${ARG} file doesn't exist."
      exit 1
    fi
  done
}

function CheckVariable() {
  # Check if variable is empty or not defined.
  local var_name var_value
  for var_name in "$@"; do
    var_value="${!var_name}"  # indirección: obtiene el valor por nombre
    if [ -z "${var_value}" ]; then
      echo "Error: variable '${var_name}' is empty or not defined." >&2
      exit 1
    fi
  done
}

function CLIflags() {
  log "=========================================="
  log "Starting MMPBSA"
  log "CLI flags:"
  log " --work_dir        : ${WDDIR}"
  log " --equi            : ${RUN_EQUI}"
  log " --prod            : ${RUN_PROD}"
  log " --rescore         : ${RUN_RESCORE}"
  log " --n_wat           : ${N_WAT}"
  log " --interval        : ${INTERVAL:-(auto)}"
  log " --start_frame     : ${START_FRAME}"
  log " --last_frame      : ${LAST_FRAME:-(auto)}"
  log " --n_frames        : ${N_FRAMES:-(all)}"
  log " --replicas        : ${REPLICAS}"
  log " --start_replica   : ${START_REPLICA}"
  log " --parallel        : ${PARALLEL}"
  log " --cores           : ${CORES}"
  log "Receptor           : ${RECEPTOR_NAME}"
  log "Working directory  : ${WDDIR}"
  log "Replicas           : ${START_REPLICA} to ${REPLICAS}"
  log "Run equi           : ${RUN_EQUI} | Run prod: ${RUN_PROD} | Run rescore: ${RUN_RESCORE}"
  log "Log file           : ${MAIN_LOG}"
  log "=========================================="
}

function log() {
  local timestamp="[$(date '+%Y-%m-%d %H:%M:%S')]"
  local first_line=1
  local padding=""
  echo "$*" | while IFS= read -r line; do
    # Strip leading whitespace
    line="${line#"${line%%[![:space:]]*}"}"
    if [ ${first_line} -eq 1 ]; then
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

  CheckVariable "WDDIR" "RECEPTOR_NAME"

  if [ "${mode}" = "rescore" ]; then
    MMPBSA_DIR=${WDDIR}/setupMD/${RECEPTOR_NAME}/proteinLigandMD/${lig}/MD/rep${rep}/equi/npt/mmpbsa_rescore
  else
    MMPBSA_DIR=${WDDIR}/setupMD/${RECEPTOR_NAME}/proteinLigandMD/${lig}/MD/rep${rep}/${mode}/npt/mmpbsa
  fi
  mkdir -p ${MMPBSA_DIR}

}

function ParseFrames() {
  local traj=$1
  local parm=$2

  log "=========================================="
  log "Parsing frames"

  # --- Total frames in trajectory ---
  TOTAL_FRAMES=$(cpptraj -p ${parm} -y ${traj} -tl 2>/dev/null | awk '{print $2}')

  if [ -z "${TOTAL_FRAMES}" ]; then
    log "Error: could not read frames from '${traj}' using topology '${parm}'."
    log "       Check that both files exist and are valid."
    exit 1
  fi

  log "Total frames in trajectory : ${TOTAL_FRAMES}"

  # --- Resolve LAST_FRAME ---
  # If not provided by the user, default to the last frame of the trajectory.
  if [ -z "${LAST_FRAME}" ]; then
    LAST_FRAME=${TOTAL_FRAMES}
  elif [ ${LAST_FRAME} -gt ${TOTAL_FRAMES} ]; then
    log "Error: --last_frame (${LAST_FRAME}) exceeds trajectory length (${TOTAL_FRAMES})."
    exit 1
  fi

  # --- Sanity check: start must be before end ---
  if [ ${START_FRAME} -gt ${LAST_FRAME} ]; then
    log "Error: --start_frame (${START_FRAME}) is greater than --last_frame (${LAST_FRAME})."
    exit 1
  fi

  # --- Resolve INTERVAL ---
  # Priority: --interval (direct) > derived from --n_frames > default (1 = every frame).
  if [ -n "${INTERVAL}" ]; then
    : # user set --interval directly, nothing to do
  elif [ ${N_FRAMES:-0} -gt 1 ]; then
    INTERVAL=$(( (LAST_FRAME - START_FRAME) / (N_FRAMES - 1) ))
    if [ ${INTERVAL} -lt 1 ]; then
      INTERVAL=1
      log "Warning: --n_frames (${N_FRAMES}) is greater than the available frames in range ${START_FRAME}-${LAST_FRAME}. Using all available frames (interval=1)."
    fi
  else
    INTERVAL=1
  fi

  log "start_frame : ${START_FRAME}"
  log "end_frame   : ${LAST_FRAME}"
  log "interval    : ${INTERVAL}"
  log "=========================================="
}


function CreateInputFile() {
  # MM/PBSA input file
  local mmpbsa_dir=$1
  local start_frame=$2
  local end_frame=$3
  local interval=$4

  cat > ${mmpbsa_dir}/${INPUT_FILE} <<EOF
Input file for PB calculation
&general
startframe=${start_frame}, endframe=${end_frame}, interval=${interval},
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

function GetLigName() {
  local lig_topo=$1
  log "=========================================="
  log "Obtaining ligand residue name"

  CheckProgram "cpptraj"
  LIG_RESIDUE_NAME=$(cpptraj -p ${lig_topo} --resmask \* | tail -n 1 | awk '{print $2}')
  CheckVariable "LIG_RESIDUE_NAME"
  log "=========================================="
}

function GetSolvationShell() {
  # This option will count the number of waters within a 
  # certain distance of the atoms in the ligand in order to
  # represent the first and second solvation shells

  local cpptraj_input=$1
  local solvated_com_traj=$2
  local solvated_com_parm=$3
  local vac_lig_topo=$4

  CheckProgram "cpptraj"
  log "=========================================="
  log "Obtaining second solvation shell"

  #GetLigName ${vac_lig_topo}

  cat > ${cpptraj_input} <<EOF
parm ${solvated_com_parm}
trajin ${solvated_com_traj}

autoimage

strip :Na+,Cl-

watershell WS :${LIG_RESIDUE_NAME} lower 3.4 upper 5.0

run

runanalysis avg WS[upper] name AverageSecondWS out StatisticsAverageSecondWS.data
writedata AverageSecondWS.data AverageSecondWS[avg]

run
EOF

  cpptraj -i ${cpptraj_input}
}

function ClosestWaterShell() {
  local cpptraj_input=$1
  local nwat=$2
  local solvated_com_traj=$3
  local solvated_com_parm=$4
  local vac_lig_topo=$5

  CheckProgram "cpptraj"
  CheckFiles AverageSecondWS.data

  # log "=========================================="
  # log "Obtaining number of wat molecules"

  # local avg_wat=$(awk 'NR==2 {print $2}' AverageSecondWS.data)

  # # Round to nearest integer
  # local nwat=$(printf "%.0f" "${avg_wat}")

  # log "Average second shell occupancy = ${avg_wat}"
  log "Using ${nwat} closest waters"
  log " Obtaining new topology and trajectory."

  #GetLigName ${vac_lig_topo}

  cat > ${cpptraj_input} <<EOF
parm ${solvated_com_parm}
trajin ${solvated_com_traj}

autoimage

strip :Na+,Cl-,K+,Mg*

closestwaters ${nwat} :${LIG_RESIDUE_NAME} parmout ${LIG_NAME}_vac_com_CWAT.parm7
trajout ${LIG_NAME}_vac_com_CWAT.nc

run
EOF

  cpptraj -i ${cpptraj_input}
}

function PrepareTopologies() {
  # Wrapper to ante-MMPBSA.py
  # We remove LIG from COM topology.
  # Everything else is considered the "receptor".

  local vac_lig_topo=$1
  local vac_com_topo=$2

  CheckProgram "ante-MMPBSA.py"

  #GetLigName ${vac_lig_topo}

  if [ ${N_WAT} -eq 0 ]; then
    ante-MMPBSA.py -p ${vac_com_topo} \
                   -n ":${LIG_RESIDUE_NAME}" \
                   -l ${LIG_RESIDUE_NAME}.parm7 \
                   -r REC.parm7
  else
    ante-MMPBSA.py -p ${vac_com_topo} \
                   -n ":${LIG_RESIDUE_NAME}" \
                   -l ${LIG_RESIDUE_NAME}.parm7 \
                   -r REC_CWAT.parm7
  fi



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

  CheckFiles ${input_file} ${traj} \
             ${com_topo} ${rec_topo} ${lig_topo}

  if [ ${parallel} -eq 1 ]; then
    EXE="mpirun -np ${cores} MMPBSA.py.MPI"
    CheckProgram "mpirun" "MMPBSA.py.MPI"
  else
    EXE="MMPBSA.py"
    CheckProgram ${EXE}
  fi

  if [[ ${N_WAT} -eq 0 ]]; then
    local result="mmpbsa_results.data"
    local per_frame_result="per_frame_mmpbsa_results.data"
    local decomp_result="decomp_mmpbsa_results.data"
    local per_frame_decomp_result="per_frame_decomp_results.data"
  else
    local result="mmpbsa_results_CW.data"
    local per_frame_result="per_frame_mmpbsa_results_CW.data"
    local decomp_result="decomp_mmpbsa_results_CW.data"
    local per_frame_decomp_result="per_frame_decomp_results_CW.data"

  fi
    log "=========================================="
    log "Running MMPBSA"
    log "${EXE} -O -i ${input_file}
              -o ${result}
              -eo ${per_frame_result}
              -do ${decomp_result}
              -deo ${per_frame_decomp_result}
              -cp ${com_topo}
              -rp ${rec_topo}
              -lp ${lig_topo}
              -y ${traj}"
    # Run MMPBSA
    ${EXE} -O -i ${input_file} \
              -o ${result} \
              -eo ${per_frame_result} \
              -do ${decomp_result} \
              -deo ${per_frame_decomp_result} \
              -cp ${com_topo} \
              -rp ${rec_topo} \
              -lp ${lig_topo} \
              -y ${traj} \
              || { echo "Error running MMPBSA. Exiting."; exit 1; }


}

function RunMode() {
  # Runs MM/PBSA for a given mode (rescore, equi, prod).
  # dry_traj  : desolvated trajectory or structure (used when KEEP_WATERS=0)
  # solv_traj : solvated trajectory (used when KEEP_WATERS!=0 to compute solvation shell)
  local mode=$1
  local dry_traj=$2
  local solv_traj=$3

  log "=========================================="
  log "Doing ${mode} MMPBSA | ligand: ${LIG_NAME} | rep: ${REP}"
  ParseDirectory "${mode}" "${LIG_NAME}" "${REP}"

  cd "${MMPBSA_DIR}" || { echo "Error: cannot cd to ${MMPBSA_DIR}"; exit 1; }
  GetLigName "${VAC_LIG_TOPO}"
  log "Current working directory: ${MMPBSA_DIR}"

  ParseFrames "${dry_traj}" "${VAC_COM_TOPO}"
  CreateInputFile "${MMPBSA_DIR}" "${START_FRAME}" "${LAST_FRAME}" "${INTERVAL}"

  if [[ ${N_WAT} -eq 0 ]]; then

    PrepareTopologies "${VAC_LIG_TOPO}" "${VAC_COM_TOPO}"

    RunMMPBSA "${PARALLEL}" "${CORES}" "${INPUT_FILE}" \
              "${dry_traj}" "${VAC_COM_TOPO}" \
              REC.parm7 "${LIG_RESIDUE_NAME}.parm7"

  else

    # GetSolvationShell "solvation_shell.in" \
    #                   "${solv_traj}" \
    #                   "${SOLV_COM_PARM}" \
    #                   "${VAC_LIG_TOPO}"

    ClosestWaterShell "closest_water.in" \
                      "${N_WAT}" \
                      "${solv_traj}" \
                      "${SOLV_COM_PARM}" \
                      "${VAC_LIG_TOPO}"

    PrepareTopologies "${VAC_LIG_TOPO}" "${LIG_NAME}_vac_com_CWAT.parm7"

    RunMMPBSA "${PARALLEL}" "${CORES}" "${INPUT_FILE}" \
              "${LIG_NAME}_vac_com_CWAT.nc" \
              "${LIG_NAME}_vac_com_CWAT.parm7" \
              REC_CWAT.parm7 "${LIG_RESIDUE_NAME}.parm7"

  fi

  cd "${WDDIR}"
  log "Done ${mode} | ligand: ${LIG_NAME} | rep: ${REP}"
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

CLIflags

shopt -s nullglob
LIGANDS_PATH=("${WDDIR}/ligands/"*.mol2)
shopt -u nullglob

if [ ${#LIGANDS_PATH[@]} -eq 0 ]; then
  echo "Error: ligands folder is empty."
  exit 1
fi

N_LIGANDS=${#LIGANDS_PATH[@]}

for REP in $(seq ${START_REPLICA} ${REPLICAS}); do
  LIG_IDX=0
  for LIG_NAME in "${LIGANDS_PATH[@]}"; do
    LIG_IDX=$((LIG_IDX + 1))

    # Required for MMPBSA
    LIG_NAME=$(basename "${LIG_NAME}" .mol2)
    log "=========================================="
    log "Ligand [${LIG_IDX}/${N_LIGANDS}]: ${LIG_NAME} | Rep: ${REP}"
    log "=========================================="

    VAC_COM_TOPO="../../../../../topo/${LIG_NAME}_vac_com.parm7"
    VAC_LIG_TOPO="../../../../../topo/${LIG_NAME}_vac_lig.parm7"
    SOLV_COM_PARM="../../../../../topo/${LIG_NAME}_solv_com.parm7"

    if [ ${RUN_RESCORE} -eq 1 ]; then
      RunMode "rescore" "../min2_noWAT.rst7" "../min2.rst7"
    fi

    if [ ${RUN_EQUI} -eq 1 ]; then
      RunMode "equi" "../noWAT_traj.nc" "../npt_equil_6.nc"
    fi

    if [ ${RUN_PROD} -eq 1 ]; then
      RunMode "prod" "../noWAT_traj.nc" "../md_prod.nc"
    fi

  done
done

log "=========================================="
log "MMPBSA completed successfully"
log "=========================================="
#!/usr/bin/bash

# Global variables are always UPPERCASE.
# Local are used with local keyword and lowercase.
# If some function requires too much arguments,
# try using global variables directly, however, this is harder to
# read and debug.

# set -x

function ScriptInfo() {
  # Prints script version, author, and lab information.
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
  # Prints usage instructions and all available CLI options.
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
 --last_n_frames    <integer>    Use only the last N frames of the available window (defined by --start_frame and --last_frame).
                                 Applied after the window is resolved. Mutually exclusive with --n_frames.
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
  '--last_n_frames'          ) shift ; LAST_N_FRAMES=$1 ;;
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

if [ -n "${LAST_N_FRAMES}" ] && [ -n "${N_FRAMES}" ]; then
  echo "Error: --last_n_frames and --n_frames are mutually exclusive. Use one or the other."
  exit 1
fi

function CheckProgram() {
  # Verifies that one or more programs are available in PATH. Exits with error if any is missing.
  for COMMAND in "$@"; do
    if ! command -v ${COMMAND} >/dev/null 2>&1; then
      echo "Error: ${COMMAND} program not available, exiting."
      exit 1
    fi
  done
}

function CheckFiles() {
  # Verifies that one or more files exist on disk. Exits with error if any is missing.
  for ARG in "$@"; do
    if [ ! -f "${ARG}" ]; then
      echo "Error: ${ARG} file doesn't exist."
      exit 1
    fi
  done
}

function CheckVariable() {
  # Verifies that one or more global variables are defined and non-empty. Exits with error if any is unset.
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
  # Logs all resolved CLI flag values at the start of execution, for traceability.

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
  log " --last_n_frames   : ${LAST_N_FRAMES:-(none)}"
  log " --replicas        : ${REPLICAS}"
  log " --start_replica   : ${START_REPLICA}"
  log " --parallel        : ${PARALLEL}"
  log " --cores           : ${CORES}"
  log "Receptor           : ${RECEPTOR_NAME}"
  log "Working directory  : ${WDDIR}"
  log "Replicas           : ${START_REPLICA} to ${REPLICAS}"
  log "Log file           : ${MAIN_LOG}"
  log "=========================================="
}

function log() {
  # Writes a timestamped message to stdout and appends it to the main log file.
  # Multi-line messages are indented to align with the first line.
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
  # Resolves and creates the output directory for a given run mode (rescore, equi, prod).
  # Sets the global MMPBSA_DIR used by subsequent functions.
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
  # Resolves the frame window and sampling interval for MMPBSA from the CLI flags
  # (--start_frame, --last_frame, --last_n_frames, --n_frames, --interval).
  # Sets globals: PARSED_START, PARSED_END, PARSED_INTERVAL, TOTAL_FRAMES.
  local parm="$1"
  local traj="$2" 

  log "=========================================="
  log "Parsing frames for: ${traj}"

  CheckFiles "${parm}" "${traj}"

  # --- 1. Detección automática del total de frames ---
  local cpptraj_stderr
  cpptraj_stderr=$(mktemp)

  TOTAL_FRAMES=$(cpptraj -p "${parm}" -y "${traj}" -tl 2>"${cpptraj_stderr}" | awk '{print $2}')

  if [[ -z "${TOTAL_FRAMES}" ]] || ! [[ "${TOTAL_FRAMES}" =~ ^[0-9]+$ ]]; then
    log "Error: could not read valid frames from '${traj}' using topology '${parm}'."
    log "cpptraj output: $(cat "${cpptraj_stderr}")"
    rm -f "${cpptraj_stderr}"
    exit 1
  fi

  rm -f "${cpptraj_stderr}"

  log "Total frames in trajectory : ${TOTAL_FRAMES}"

  # --- 2. Asignación de START y LAST frame ---
  PARSED_START="${START_FRAME:-1}"

  if [[ -n "${LAST_FRAME}" ]]; then
    if [[ "${LAST_FRAME}" -gt "${TOTAL_FRAMES}" ]]; then
      log "Warning: --last_frame (${LAST_FRAME}) exceeds total frames (${TOTAL_FRAMES}). Using ${TOTAL_FRAMES}."
      PARSED_END="${TOTAL_FRAMES}"
    else
      PARSED_END="${LAST_FRAME}"
    fi
  else
    PARSED_END="${TOTAL_FRAMES}"
  fi

  # Sanity check
  if [[ "${PARSED_START}" -gt "${PARSED_END}" ]]; then
    log "Error: --start_frame (${PARSED_START}) is greater than end_frame (${PARSED_END})."
    exit 1
  fi

  # --- 3. Recorte de ventana con --last_n_frames ---
  if [[ -n "${LAST_N_FRAMES}" ]]; then
    local available_frames=$(( PARSED_END - PARSED_START + 1 ))
    if [[ "${LAST_N_FRAMES}" -ge "${available_frames}" ]]; then
      log "Warning: --last_n_frames (${LAST_N_FRAMES}) >= available frames (${available_frames}). Using the full window."
    else
      PARSED_START=$(( PARSED_END - LAST_N_FRAMES + 1 ))
    fi
  fi

  # --- 4. Cálculo del INTERVAL ---
  local available_frames=$(( PARSED_END - PARSED_START + 1 ))
  local n_frames_val="${N_FRAMES:-0}"

  if [[ -n "${INTERVAL}" ]]; then
    # Caso 5: --interval mayor que los frames disponibles → usar solo PARSED_END
    if [[ "${INTERVAL}" -ge "${available_frames}" ]]; then
      log "Warning: --interval (${INTERVAL}) >= available frames (${available_frames})."
      log "         Only 1 frame will be used: frame ${PARSED_END}."
      PARSED_START="${PARSED_END}"
      PARSED_INTERVAL=1
    else
      PARSED_INTERVAL="${INTERVAL}"
    fi
  elif [[ "${n_frames_val}" -eq 1 ]]; then
    PARSED_START="${PARSED_END}"
    PARSED_INTERVAL=1
  elif [[ "${n_frames_val}" -gt 1 ]]; then
    if [[ "${n_frames_val}" -gt "${available_frames}" ]]; then
      # Caso 4: --n_frames mayor que frames disponibles → usar todos los frames
      log "Warning: --n_frames (${n_frames_val}) exceeds available frames (${available_frames}). Using all available frames with interval=1."
      PARSED_INTERVAL=1
    else
      PARSED_INTERVAL=$(( (PARSED_END - PARSED_START) / (n_frames_val - 1) ))
    fi
  else
    PARSED_INTERVAL=1
  fi

  # --- 5. Log del resumen ---
  local frames_used=$(( (PARSED_END - PARSED_START) / PARSED_INTERVAL + 1 ))
  log "start_frame  : ${PARSED_START}"
  log "end_frame    : ${PARSED_END}"
  log "interval     : ${PARSED_INTERVAL}"
  log "frames used  : ${frames_used}"
  log "=========================================="
}


function CreateInputFile() {
  # Writes the MMPBSA.py input file (mm_pbsa.in) with the resolved frame window.
  # Includes PB and per-residue decomposition settings.
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
  # Extracts the residue name of the ligand from its vacuum topology using cpptraj.
  # Sets the global LIG_RESIDUE_NAME.
  local lig_topo=$1
  log "=========================================="
  log "Obtaining ligand residue name"

  CheckProgram "cpptraj"
  LIG_RESIDUE_NAME=$(cpptraj -p ${lig_topo} --resmask \* | tail -n 1 | awk '{print $2}')
  CheckVariable "LIG_RESIDUE_NAME"
  log "=========================================="
}

function ClosestWaterShell() {
  # Generates a new solvated trajectory and topology keeping only the N closest water
  # molecules to the ligand (explicit-water MMPBSA).
  # Accepts one solvated trajectory.
  # Outputs: <LIG_NAME>_vac_com_CWAT.nc and <LIG_NAME>_vac_com_CWAT.parm7.
  
  local cpptraj_input=$1
  local nwat=$2
  local solvated_com_parm=$3
  local vac_lig_topo=$4
  local solv_traj=$5

  CheckProgram "cpptraj"

  log "Using ${nwat} closest waters"
  log "Obtaining new topology and trajectory."
  log "Trajectory: ${solv_traj}"

  cat > ${cpptraj_input} <<EOF
parm ${solvated_com_parm}
trajin ${solv_traj}

autoimage

strip :Na+,Cl-,K+,Mg*

closestwaters ${nwat} :${LIG_RESIDUE_NAME} parmout ${LIG_NAME}_vac_com_${nwat}WAT.parm7
trajout ${LIG_NAME}_vac_com_${nwat}WAT.nc

run
EOF

  cpptraj -i ${cpptraj_input}
}

function PrepareTopologies() {
  # Splits the complex topology into receptor and ligand topologies using ante-MMPBSA.py.
  # If N_WAT=0, produces REC.parm7; if N_WAT>0 (explicit water), produces REC_CWAT.parm7.

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
                   -r REC_${N_WAT}WAT.parm7
  fi
}

function RunMMPBSA() {
  # Executes MMPBSA.py (serial) or MMPBSA.py.MPI (parallel) with the given topology and trajectory.
  # Output filenames differ depending on whether explicit waters are included (N_WAT>0).
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
    local result="mmpbsa_results_${N_WAT}WAT.data"
    local per_frame_result="per_frame_mmpbsa_results_${N_WAT}WAT.data"
    local decomp_result="decomp_mmpbsa_results_${N_WAT}WAT.data"
    local per_frame_decomp_result="per_frame_decomp_results_${N_WAT}WAT.data"

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
  # Orchestrates a full MMPBSA run for a given mode (rescore, equi, or prod).
  # Resolves directories and frames, prepares topologies, optionally extracts the
  # closest water shell, and calls MMPBSA.py.
  #
  # Args:
  #   $1 mode      : rescore | equi | prod
  #   $2 dry_traj  : desolvated trajectory or structure (used when N_WAT=0)
  #   $@ solv_trajs: one or more solvated trajectories (used when N_WAT>0 to compute solvation shell)
  local mode=$1
  local dry_traj=$2
  local solv_traj=$3

  log "=========================================="
  log "Doing ${mode} MMPBSA | ligand: ${LIG_NAME} | rep: ${REP}"
  ParseDirectory "${mode}" "${LIG_NAME}" "${REP}"

  cd "${MMPBSA_DIR}" || { echo "Error: cannot cd to ${MMPBSA_DIR}"; exit 1; }
  GetLigName "${VAC_LIG_TOPO}"
  log "Current working directory: ${MMPBSA_DIR}"

  if [[ ${N_WAT} -eq 0 ]]; then

    ParseFrames "${VAC_COM_TOPO}" "${dry_traj}"
    CreateInputFile "${MMPBSA_DIR}" "${PARSED_START}" "${PARSED_END}" "${PARSED_INTERVAL}"

    PrepareTopologies "${VAC_LIG_TOPO}" "${VAC_COM_TOPO}"

    RunMMPBSA "${PARALLEL}" "${CORES}" "${INPUT_FILE}" \
              "${dry_traj}" "${VAC_COM_TOPO}" \
              REC.parm7 "${LIG_RESIDUE_NAME}.parm7"

  else

    ParseFrames "${SOLV_COM_PARM}" "${solv_traj}"
    CreateInputFile "${MMPBSA_DIR}" "${PARSED_START}" "${PARSED_END}" "${PARSED_INTERVAL}"

    # GetSolvationShell "solvation_shell.in" \
    #                   "${solv_trajs[@]}" \
    #                   "${SOLV_COM_PARM}" \
    #                   "${VAC_LIG_TOPO}"

    ClosestWaterShell "closest_water.in" \
                      "${N_WAT}" \
                      "${SOLV_COM_PARM}" \
                      "${VAC_LIG_TOPO}" \
                      "${solv_traj}"

    local cwat_traj="${LIG_NAME}_vac_com_${N_WAT}WAT.nc"
    local cwat_parm="${LIG_NAME}_vac_com_${N_WAT}WAT.parm7"
    
    PrepareTopologies "${VAC_LIG_TOPO}" "${cwat_parm}"

    RunMMPBSA "${PARALLEL}" "${CORES}" "${INPUT_FILE}" \
              "${cwat_traj}" \
              "${cwat_parm}" \
              "REC_${N_WAT}WAT.parm7" \
              "${LIG_RESIDUE_NAME}.parm7"

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

LIGANDS_PATH=("${WDDIR}/ligands/"*.mol2)

if [[ ! -f "${LIGANDS_PATH[0]}" ]]; then
  log "Error: --prot_lig is 1 but ligands folder is empty."
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
      RunMode "equi" "../noWAT_traj.nc" "../concatenated_traj.nc"
    fi

    if [ ${RUN_PROD} -eq 1 ]; then
      RunMode "prod" "../noWAT_traj.nc" "../concatenated_traj.nc"
    fi

  done
done

log "=========================================="
log "MMPBSA completed successfully"
log "=========================================="
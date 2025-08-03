#!/bin/bash

# To do: check if files already exists and add a --force option to rewrite existing files

DATE="2025"
VERSION="1.0.0"
GitHub_URL="https://github.com/tcaceresm/AmberMDHelper"
LAB="http://schuellerlab.org/"

function ScriptInfo() {
  cat <<EOF
###################################################
Welcome to run_ASMD version ${VERSION} ${DATE}   
Author: Tomás Cáceres <caceres.tomas@uc.cl>    
Laboratory of Molecular Design <${LAB}>        
GitHub <${GitHub_URL}>                             
Powered by high fat food and procrastination   
###################################################
EOF
}

function Help() {
  ScriptInfo
  # Display Help
  echo -e "\nThis script run Adaptive Steered Molecular Dynamics (ASMD)."
  echo "This should be executed after setup_ASMD.sh script."
  echo
  echo "Required options:"
  echo " --wd <path>                 : Working directory."
  echo " -p, --topo <file>           : Topology file."
  echo " -c, --coord <file>          : Equilibrated rst7 file."
  echo " --velocity <numeric>        : Pulling velocity (Å/ns)."
  echo " --stages <integer>          : Number of stages."
  echo " --n_traj <integer>          : Number of trajectories per stage."
  echo " --force_k <numeric>         : Force constant (kcal * mol⁻¹ * Å⁻²)."
  echo "Optional:"
  echo " --temp <numeric>            : (default=300). MD temperature."
  echo " --MD_prog <string>          : (default="pmemd.cuda"). MD program (sander, pmemd.cuda, etc)."
  echo " --only_process              : Only process SMD data."
  echo " --debug                     : Print details of variables used in this scripts."
  echo " --dry-run                   : Show run command."
  echo " -h, --help                  : Show this help."
}

# Check arguments
if [[ "$#" == 0 ]]; then
  echo "No options provided."
  echo "Use --help option to check available options."
  exit 1
fi

# Default values
TEMPERATURE=300
MD_PROG="pmemd.cuda"

# Command line options
while [[ $# -gt 0 ]]; do
  case "$1" in
  '--wd'                        ) shift ; WD_PATH=$1 ;;
  '-p' | '--topo'               ) shift ; TOPO=$1 ;;
  '-c' | '--coord'              ) shift ; COORD=$1 ;;
  '--velocity'                  ) shift ; VEL=$1 ;;
  '--stages'                    ) shift ; NUM_STAGES=$1 ;;
  '--n_traj'                    ) shift ; NUM_TRAJS=$1 ;;
  '--force_k'                   ) shift ; FORCE=$1 ;;
  '--temp'                      ) shift ; TEMPERATURE=$1;; 
  '--MD_prog'                   ) shift ; MD_PROG=$1 ;;
  '--only_process'              ) ONLY_PROCESS=1 ;;
  '--debug'                     ) DEBUG=1 ;;
  '--dry-run'                   ) DRY_RUN=1 ;;
  '--help' | '-h'               ) Help ; exit 0 ;;
  *                             ) echo "Unrecognized command line option: $1" >> /dev/stderr ; exit 1 ;;
  esac
  shift
done

function CheckVariable() {
  # Check if variable is not empty
  for ARG in "$@"; do
    if [[ -z ${ARG} ]]; then
      echo "Error: Required option not provided."
      echo "Use --help option to check available options."
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

function CheckProgram() {
  for COMMAND in "$@"; do
    # Check if command is available
    if ! command -v ${1} >/dev/null 2>&1; then
      echo "Error: ${1} not available, exiting."
      exit 1
    fi
  done
}

function Debug() {
  # Show variables
  echo "----- DEBUG INFO -----"
  echo "All units are manually added to better understanding."
  echo "Working directory:                ${WD_PATH}"
  echo "TOPO:                             ${TOPO}"
  echo "COORD:                            ${COORD}"
  echo "NUM_STAGES:                       ${NUM_STAGES}"
  echo "NUM_TRAJS:                        ${NUM_TRAJS}"
  echo "VEL:                              ${VEL} (Å * ns⁻¹ )"
  echo "FORCE CONSTANT:                   ${FORCE} (kcal * mol⁻¹ * Å⁻²)"
  echo "MD PROG:                          ${MD_PROG}"
  echo "TEMPERATURE:                      ${TEMPERATURE}"
  echo "DEBUG:                            ${DEBUG}"
  echo "======================"
}

function RunASMD() {
  # Run ASMD.
  local COORD=$1
  STAGE=$2
  TRAJ=$3
  INPUT_NAME=$4
  CheckProgram ${MD_PROG}
  echo "Doing ASMD stage: ${STAGE}, trajectory: ${TRAJ}, input coord: ${COORD}, stage_path=${STAGE_PATH}" | tee "${INPUT_NAME}.log"
  
  if [[ ! -z ${DRY_RUN} ]]; then
    echo "${MD_PROG} -O -i ${INPUT_NAME}.in -p ${TOPO} -c ${COORD} -r ${INPUT_NAME}.rst7 -o ${INPUT_NAME}.out -x ${INPUT_NAME}.nc -inf ${INPUT_NAME}.info"
  else
    ${MD_PROG} -O -i "${INPUT_NAME}.in" -p "${TOPO}" -c "${COORD}" -r "${INPUT_NAME}.rst7" -o "${INPUT_NAME}.out" -x "${INPUT_NAME}.nc" -inf "${INPUT_NAME}.info"
  fi
}

function ClosestWorkToJar() {
  # Determine which of the SMD files (SMD_work_stage_*_traj_*.data files) has the work closest to the JA.
  # Its saved in "${STAGE_PATH}/JAR_stage_${STAGE}.log" file
  # Requires ASMD.py python3 script.
  STAGE=$1
  CheckFiles ${SCRIPT_PATH}/ASMD.py
  CheckProgram python3

  python3 ${SCRIPT_PATH}/ASMD.py -i ${STAGE_PATH}/SMD_work_stage_${STAGE}_traj_*.data -o JAR_stage_${STAGE}.dat --temp ${TEMPERATURE} | tee "${STAGE_PATH}/JAR_stage_${STAGE}.log" > /dev/null
}

function ClosestTrajToJar() {
  # Set restart file (.rst7) for next smd stage
  # Set trajectory file for visualization
  STAGE=$1
  JAR_LOG=$(awk 'BEGIN { FS = ":" } {print $2}' ${STAGE_PATH}/JAR_stage_${STAGE}.log)
  BASENAME="${JAR_LOG%.*}" # Parse: Delete file extension name
  BASENAME="${BASENAME/_work/}" # Parse name
  TRAJECTORY="${BASENAME}.nc" # Closest traj to JAR
  REF_COORD="${BASENAME}.rst7" # Restart file for next stage
  
}

function CreatePMF() {
  if [[ -f "${SMD_DIR}/PMF.data" ]]; then
    rm "${SMD_DIR}/PMF.data"
  fi

  local addval=0.0
  for STAGE in $(seq 1 "${NUM_STAGES}"); do
    local stage_path="${SMD_DIR}/stage_${STAGE}"
    local jar_file="${stage_path}/JAR_stage_${STAGE}.dat"

    awk -v addval="$addval" '
      {
        coord = $1
        work = $2 + addval
        print coord, work
        last_jar_work = work
      }
      END {
        printf("%f\n", last_jar_work) > "/tmp/last_jar_work.txt"
      }
    ' "$jar_file" >> "${SMD_DIR}/PMF.data"
    ParseWorkData
    addval=$(cat /tmp/last_jar_work.txt)

  done

  rm -f /tmp/last_work.txt
}

function ConcatenateJarTrajectories() {
  # Concatenate the closest trajectory to Jar of each stage.
  JAR_DIR=${SMD_DIR}/JAR_trajectories/

  CheckProgram cpptraj

  cpptraj <<EOF 1>/dev/null
  parm ${TOPO}
  trajin ${JAR_DIR}/*SMD*.nc
  autoimage
  strip :WAT,Na+,Cl- parmout ${JAR_DIR}/JAR_traj_noWAT.parm7
  trajout ${JAR_DIR}/JAR_traj_noWAT.nc
  run
EOF
}

function ParseWorkData() {
  # Process Work data of all trajectories
  # The idea is plot like this https://ambermd.org/tutorials/advanced/tutorial26/images/pmf_fan.png
  # At the start of each stage, need to add the last work of previous stage of jar traj.

  for TRAJ in $(seq 1 ${NUM_TRAJS}); do
    traj_work=${stage_path}/SMD_work_stage_${STAGE}_traj_${TRAJ}.data
    awk -v addval="${addval}" -v stage="${STAGE}" -v traj="${TRAJ}" '
      {
        coord = $1
        work = $4 + addval
        print coord, work, stage, traj
      }
    ' "$traj_work" >> "${SMD_DIR}/all_work.data"
  done
}
# Path of this script
SCRIPT_PATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Working directory path
WD_PATH=$(realpath "$WD_PATH")
TOPO=${WD_PATH}/${TOPO}
COORD=${WD_PATH}/${COORD}

# ========== Main ==========

# Check required options
CheckVariable  "${WD_PATH}" "${TOPO}" "${COORD}" "${NUM_STAGES}" "${NUM_TRAJS}" "${VEL}" "${FORCE}"

CheckFiles ${TOPO} ${COORD}

if [[ ${DEBUG} -eq 1 ]]; then
  Debug
  exit 0
fi

SMD_DIR=${WD_PATH}/${VEL}_A_ns/force_${FORCE}/${NUM_STAGES}_stages_${NUM_TRAJS}_trajs/

# Folder to store Jar trajectories
mkdir -p ${SMD_DIR}/JAR_trajectories/

REF_COORD=${COORD}

if [[ -f ${SMD_DIR}/all_work.data ]]; then
  rm ${SMD_DIR}/all_work.data
fi

for STAGE in $(seq 1 ${NUM_STAGES}); do

  STAGE_PATH="${SMD_DIR}/stage_${STAGE}"
  cd ${STAGE_PATH}

  for TRAJ in $(seq 1 ${NUM_TRAJS}); do
    if [[ -z ${ONLY_PROCESS} ]]; then
      RunASMD ${REF_COORD} ${STAGE} ${TRAJ} "${STAGE_PATH}/SMD_stage_${STAGE}_traj_${TRAJ}"
    fi
    CheckFiles ${STAGE_PATH}/SMD_work_stage_${STAGE}_traj_${TRAJ}.data
  done

  ClosestWorkToJar ${STAGE}
  ClosestTrajToJar ${STAGE}
  
  if [[ ! -f ${REF_COORD} ]]; then
    echo "Error: Closest traj to Jarzinsky average of stage ${STAGE} doesn't exist."
    exit 1
  fi

  cp ${TRAJECTORY} ${SMD_DIR}/JAR_trajectories/

cd ${WD_PATH}

done

CreatePMF
ConcatenateJarTrajectories

echo "Done."

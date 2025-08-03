#!/bin/bash

DATE="2025"
VERSION="1.0.0"
GitHub_URL="https://github.com/tcaceresm/AmberMDHelper"
LAB="http://schuellerlab.org/"

function ScriptInfo() {
  cat <<EOF
###################################################
Welcome to setup_ASMD version ${VERSION} ${DATE}   
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
  echo -e "\nThis script create Adaptive Steered Molecular Dynamics (ASMD) input files."
  echo
  echo "Required options:"
  echo " -p, --topo <file>           : Topology file."
  echo " -c, --coord <file>          : Equilibrated rst7 file."
  echo " --prot_mask <AMBER MASK>    : AMBER mask of protein atoms."
  echo " --lig_mask <AMBER MASK>     : AMBER mask of ligand atoms."
  echo " --pull_length <numeric>     : Total pull length (Å)."
  echo "Optional:"
  echo " --stages <integer>          : (default=5). Number of stages to split the reaction coordinate."
  echo " --n_traj <integer>          : (default=25). Number of trajectories per stage."
  echo " --velocity <numeric>        : (default=10). Pulling velocity (Å/ns)."
  echo " --force_k <numeric>         : (default=7.2) Force constant (kcal * mol⁻¹ * Å⁻²)."
  echo " --start_distance <numeric>  : Manually set start distance between ligand atom(s) and protein atom(s).
                                If not provided, start distance is automatically calculated using cpptraj from protein and ligand SMD atoms."
  echo " --end_distance <numeric>    : Manually set final distance between ligand atom(s) and protein atom(s) if --pull_length is not provided."
  echo " --create_pdb                : Create a PDB file from topology and rst7 file. You can use this PDB to
                                visualize and check the SMD atoms. This will create a PDB of the complex
                                and another PDB for the selected atoms for SMD."
  echo " --debug                     : Print details of variables used in this scripts."
  echo " -h, --help                  : Show this help."
}

# Check arguments
if [[ "$#" == 0 ]]; then
  echo "Error: No options provided."
  echo "Use --help option to check available options."
  exit 1
fi

# Default values
NUM_STAGES=5
NUM_TRAJS=25
VEL=10
FORCE=7.2
DT=0.002

# Command line options
while [[ $# -gt 0 ]]; do
  case "$1" in
  '-p' | '--topo'               ) shift ; TOPO=$1 ;;
  '-c' | '--coord'              ) shift ; COORD=$1 ;;
  '--prot_mask'                 ) shift ; PROT_MASK=$1 ;;
  '--lig_mask'                  ) shift ; LIG_MASK=$1 ;;
  '--pull_length'               ) shift ; PULL_LENGTH=$1 ;;
  '--start_distance'            ) shift ; START_DIST=$1 ;;
  '--end_distance'              ) shift ; END_DIST=$1 ;;
  '--stages'                    ) shift ; NUM_STAGES=$1 ;;
  '--n_traj'                    ) shift ; NUM_TRAJS=$1 ;;
  '--velocity'                  ) shift ; VEL=$1 ;;
  '--force_k'                   ) shift ; FORCE=$1 ;;
  '--create_pdb'                ) CREATE_PDB=1 ;;
  '--debug'                     ) DEBUG=1 ;;
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
  echo "TOPO:                             ${TOPO}"
  echo "COORD:                            ${COORD}"
  echo "PROT_MASK:                        \"${PROT_MASK}\""
  echo "LIG_MASK:                         \"${LIG_MASK}\""
  echo "PROT_ATOMS_ID:                    ${PROT_ATOMS}"
  echo "LIG_ATOMS_ID:                     ${LIG_ATOMS}"
  echo "IAT_PROT:                         ${IAT_PROT}"
  echo "IAT_LIG:                          ${IAT_LIG}"
  echo "IGR_PROT:                         ${IGR_PROT}"
  echo "IGR_LIG:                          ${IGR_LIG}"
  echo "START_DIST:                       ${START_DIST} (Å)"
  echo "END_DIST:                         ${END_DIST} (Å)"
  echo "NUM_STAGES:                       ${NUM_STAGES}"
  echo "NUM_TRAJS:                        ${NUM_TRAJS}"
  echo "VEL:                              ${VEL} (Å * ns⁻¹ )"
  echo "FORCE CONSTANT:                   ${FORCE} (kcal * mol⁻¹ * Å⁻²)"
  echo "DEBUG:                            ${DEBUG}"
  echo "PULL_LENGTH:                      ${PULL_LENGTH} (Å)"
  echo "LENGTH_PER_STAGE:                 ${LENGTH_PER_STAGE} (Å)"
  echo "TIME_PER_STAGE (1 trajectory):    ${TIME_PER_STAGE} (ns)"
  echo "TOTAL TIME (1 trajectory):        $(echo "scale=1; ${TIME_PER_STAGE} * ${NUM_STAGES}" | bc) (ns)"
  echo "NSTLIM:                           ${NSTLIM}"
  echo "DT:                               ${DT}"
  echo "======================"
}

function PullLengthWrapper() {
  # Calculate pull length (absolute difference) with 3 decimal places
  DIFF=$(echo "scale=5; $1 - $2" | bc)
  ABS_DIFF=$(echo "scale=3; if (${DIFF} < 0) -1 * ${DIFF} else ${DIFF}" | bc)
  PULL_LENGTH="${ABS_DIFF}"
}

function VelocityWrapper() {
  # Obtain mdsteps (nstlim) from velocity
  # PullLengthWrapper ${START_DIST} ${END_DIST}
  LENGTH_PER_STAGE=$(echo "scale=3; ${PULL_LENGTH} / ${NUM_STAGES}" | bc )
  TIME_PER_STAGE=$(echo "scale=6; ${LENGTH_PER_STAGE} / ${VEL}" | bc)
  NSTLIM=$(echo "scale=0; (${TIME_PER_STAGE} * 1000) / ${DT}" | bc)
}

function SetAtomGroupsWrapper() {
  # Check number of atoms selected by LIG or PROT mask"
  # Must be >= 1

  if [[ ${#PROT_ATOMS} -gt 1 ]]; then
    IAT_PROT=-1
    IGR_PROT=${PROT_ATOMS}
  elif [[ ${#PROT_ATOMS} -eq 1 ]]; then
    IAT_PROT=${PROT_ATOMS}
    IGR_PROT=0
  else
    echo "Error: Number of protein atoms is not correct. Check --debug option."
    exit 1
  fi

  if [[ ${#LIG_ATOMS} -gt 1 ]]; then
    IAT_LIG=-1
    IGR_LIG=${LIG_ATOMS}
  elif [[ ${#LIG_ATOMS} -eq 1 ]]; then
    IAT_LIG=${LIG_ATOMS}
    IGR_LIG=0
  else
    echo "Error: Number of ligand atoms is not correct. Check --debug option."
    exit 1
  fi
}

function AtomSelectionWrapper() {
  # Obtain atom number from residue numbers using cpptraj
  CheckProgram cpptraj
  PROT_ATOMS=$(cpptraj -p ${TOPO} --mask "${PROT_MASK}" | awk 'NR>1 {printf "%s%s", sep, $1; sep=","}')
  LIG_ATOMS=$(cpptraj -p ${TOPO} --mask "${LIG_MASK}" | awk 'NR>1 {printf "%s%s", sep, $1; sep=","}')
  SetAtomGroupsWrapper
}

function StartDistanceWrapper() {
  # Calculate start distance between protein and ligand smd atoms
  if [[ -z ${START_DIST} ]]; then
      CheckProgram cpptraj
      cpptraj <<EOF 1>/dev/null
    parm ${TOPO}
    trajin ${COORD}
    distance Dist1 "${PROT_MASK}" "${LIG_MASK}" out START_DISTANCE.data
    run
EOF
    START_DIST=$(cat START_DISTANCE.data | awk 'NR>1 {print $2}')
  fi
}

function FinalDistanceWrapper() {
  # Calculate final distance
  if [[ ! -z ${PULL_LENGTH} && -z ${END_DIST} ]]; then
    END_DIST=$(echo "scale=4; ${START_DIST} + ${PULL_LENGTH}" | bc)
  elif [[ ! -z ${END_DIST} && -z ${PULL_LENGTH} ]]; then
    PullLengthWrapper ${START_DIST} ${END_DIST}
  else
    echo "Error: You must provide either --pull_length or --end_distance."
    echo "Use --help option to check available options."
    exit 1
  fi
}

function CreatePDB() {
  # Create PDB from parm7 and rst7
  CheckProgram cpptraj ambpdb
  ambpdb -p ${TOPO} -c ${COORD} > COMPLEX.pdb
  cpptraj <<EOF 1>/dev/null
  parm ${TOPO}
  trajin ${COORD}
  strip !(@${PROT_ATOMS})
  trajout SMD_PROT_ATOMS.pdb
  run
  strip !(@${LIG_ATOMS})
  trajout SMD_LIG_ATOMS.pdb
  run
EOF
  echo "Created PDB of SMD atoms."
}

function CreateDirectories() {
  # Create ASMD directories
  DIRECTORY="${VEL}_A_ns/force_${FORCE}/${NUM_STAGES}_stages_${NUM_TRAJS}_trajs"
  if [[ -d ${DIRECTORY} ]]; then
    echo "Error: ${DIRECTORY} already exists. Exiting."
    exit 1
  else
    mkdir -p ${DIRECTORY}
    echo "${NUM_STAGES} stages, and ${NUM_TRAJS} trajectories per stage" > "${DIRECTORY}/readme.txt"
    Debug >> "${DIRECTORY}/readme.txt"
  fi

  for STAGE in $(seq 1 $NUM_STAGES); do
    mkdir -p "${DIRECTORY}/stage_${STAGE}"
  done
}

function CreateSMDInput() {
  # Create SMD input
  # Default values
  local STAGE=$1
  local TRAJ=$2
  INPUT="${DIRECTORY}/stage_${STAGE}/SMD_stage_${STAGE}_traj_${TRAJ}.in"

  cat > ${INPUT} <<-EOF
Stage ${STAGE}
&cntrl
  ! Nature and Format of input
  ntx = 1, irest = 0,
  ! Nature and Format of output
  ntpr = 1000, ntwx = 1000, ntwr = 1000,
  ! Potential function parameters
  ntf = 2, cut = 10, nsnb = 10,
  ! Molecular dynamics
  nstlim = ${NSTLIM}, dt = ${DT},
  ! SHAKE bond length constraints
  ntc = 2,
  ! Temperature regulation
  ntt = 3, tempi = 300, temp0 = 300, gamma_ln = 5.0,
  ! SMD
  jar = 1,
/
&wt type='DUMPFREQ', istep1=1000
/
&wt type='END'
/
DISANG=SMD_distance_restraint_stage_${STAGE}.RST
DUMPAVE=SMD_work_stage_${STAGE}_traj_${TRAJ}.data
LISTIN=POUT
LISTOUT=POUT
EOF
}

function CreateSMDRestraintFile() {
  # Create RST file for SMD
  STAGE=$1
  STAGE_START_DIST=$2
  STAGE_END_DIST=$3

  INPUT="${DIRECTORY}/stage_${STAGE}/SMD_distance_restraint_stage_${STAGE}.RST"
  cat > ${INPUT} <<-EOF
&rst
  iat=${IAT_PROT}, ${IAT_LIG},
  igr1=${IGR_PROT},
  igr2=${IGR_LIG},
  r2=${STAGE_START_DIST},
  r2a=${STAGE_END_DIST},
  rk2=${FORCE},
&end
EOF
}

# ========== Main ==========

CheckVariable ${TOPO} ${COORD} ${PROT_MASK} ${LIG_MASK}

CheckFiles ${TOPO} ${COORD}

StartDistanceWrapper
FinalDistanceWrapper
VelocityWrapper
AtomSelectionWrapper

if [[ ${DEBUG} -eq 1 ]]; then
  Debug
  exit 0
fi

if [[ ${CREATE_PDB} -eq 1 ]]; then
  CreatePDB
  exit 0
fi

CreateDirectories

STAGE_START_DIST=${START_DIST}

for STAGE in $(seq 1 ${NUM_STAGES}); do

  STAGE_END_DIST=$(echo "scale=3; ${STAGE_START_DIST} + ${LENGTH_PER_STAGE}" | bc)

  CreateSMDRestraintFile ${STAGE} ${STAGE_START_DIST} ${STAGE_END_DIST}

    for TRAJ in $(seq 1 ${NUM_TRAJS}); do
      CreateSMDInput ${STAGE} ${TRAJ}
    done

  STAGE_START_DIST=${STAGE_END_DIST}

done

echo "Done."

#!/usr/bin/bash

# Global variables are always UPPERCASE.
# Local are used with local keyword and lowercase.
# If some function requires too much arguments,
# try using global variables directly, however, this is harder to
# read and debug.

#set -x

# To do: add options for mmpbsa input file (mmpbsa.py)

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
  echo -e "\nUsage: bash MMPBSA.sh OPTIONS\n"
  echo -e "This script perform MM/PB(G)SA calculations."
  echo -e "It requires a unsolvated topology for complex, receptor and ligand, and a trajectory file.\n"
  echo "A folder structure and topologies obtained with setup_MD.sh is required."
  echo "Also, trajectories obtained with run_MD.sh are required."
  echo
  echo "Required options:"
  echo " -d, --work_dir     <DIR>        Working directory. Inside this directory, a folder named setupMD should exist, containing all input files."
  echo "                                 Also, a ligands and receptor folders are required to parse files."
  #echo " -x, --trajectory   <file>       Unsolvated trajectory used to compute MM/PBSA calculations. This can be obtained using process_MD.sh"
  echo "Optional:"
  echo " -h, --help                      Show this help."
  echo " --equi             <0|1>        (default=1) Use trajectory from equilibration phase (noWAT_traj.nc)"
  echo " --prod             <0|1>        (default=1) Use trajectory from production phase (noWAT_traj.nc)."
  echo " --interval         <integer>    (default=1) The offset from which to choose frames from each trajectory file."
  echo " -n, --replicas     <integer>    (default=3) Number of replicas or repetitions."
  echo " --start_replica    <integer>    (default=1) Run from --start_replica to --replicas."
  echo " --parallel         <0|1>        (default=0) Use MMPBSA.py.MPI to run parallel calculations."
  echo " --cores            <integer>    (default=4) Number of cores to parallelize, if --parallel is set to 1."
}

# Default values

RUN_EQUI=1
RUN_PROD=1
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
  '--equi'               ) shift ; RUN_EQUI=$1 ;;
  '--prod'               ) shift ; RUN_PROD=$1 ;;
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
    if ! command -v ${1} >/dev/null 2>&1; then
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

function ParseDirectory() {
  local mode=$1
  local lig=$2
  local rep=$3

  MMPBSA_DIR=${WDDIR}/setupMD/${RECEPTOR_NAME}/proteinLigandMD/${lig}/MD/rep${rep}/${mode}/npt/mmpbsa
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

  # Run MMPBSA
  ${EXE} -O -i ${input_file} \
            -o mmpbsa_results.data \
            -eo per_frame_mmpbsa_results.data \
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

for REP in $(seq ${START_REPLICA} ${REPLICAS}); do

  LIGANDS_PATH=("${WDDIR}/ligands/"*.mol2)
  
  if [[ ${#LIGANDS_PATH[@]} -eq 0 ]]; then
    echo "Error: ligands folder is empty."
    exit 1
  fi

  for LIG_NAME in ${LIGANDS_PATH[@]}; do

    # Required for both MD and MMPBSA
    LIG_NAME=$(basename ${LIG_NAME} .mol2)
    echo "Doing ligand: ${LIG_NAME}"

    if [[ ${RUN_EQUI} -eq 1 ]]; then
      echo "Doing equi MMPBSA"
      ParseDirectory "equi" ${LIG_NAME} ${REP}

      cd ${MMPBSA_DIR}

      ParseFiles "equi" ${LIG_NAME} ${REP}
      CreateInputFile ${MMPBSA_DIR}
    
      RunMMPBSA ${PARALLEL} ${CORES} ${INPUT_FILE} \
                ${EQUI_TRAJ} ${VAC_COM_TOPO} ${VAC_REC_TOPO} \
                ${VAC_LIG_TOPO}
    
      cd ${WDDIR}
      echo "Done"
    fi

    if [[ ${RUN_PROD} -eq 1 ]]; then
      echo "Doing prod MMPBSA"
      ParseDirectory "prod" ${LIG_NAME} ${REP}

      cd ${MMPBSA_DIR}

      ParseFiles "prod" ${LIG_NAME} ${REP}
      CreateInputFile ${MMPBSA_DIR}
    
      RunMMPBSA ${PARALLEL} ${CORES} ${INPUT_FILE} \
                ${PROD_TRAJ} ${VAC_COM_TOPO} ${VAC_REC_TOPO} \
                ${VAC_LIG_TOPO}
    
      cd ${WDDIR}
      echo "Done"
    fi

  done
done
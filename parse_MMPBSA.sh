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
 Welcome to parse MMPBSA version ${VERSION} ${DATE}   
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
  echo -e "\nUsage: bash parse_MMPBSA.sh OPTIONS\n"
  echo -e "This script parse results from MM/PB(G)SA calculations obtained with MMPBSA.py script."
  echo -e "It requires a per frame MMPBSA output file, both "normal" and/or file with decomposition data.\n"
  echo "Also, requires a folder structure obtained with setup_MD.sh."
  echo
  echo "Required options:"
  echo " -d, --work_dir           <DIR>        Working directory. Inside this directory, a folder named setupMD must exist with all required files."
  echo "                                     Also, a ligands and receptor folders are required to parse directories."
  echo " --parse_results          <0|1>        (default=1) parse per-frame MMPBSA results."
  echo " --parse_decomp_results   <0|1>        (default=1) parse per-frame MMPBSA decomposition results."
  echo "Optional:"
  echo " -h,  --help                         Show this help."
  # echo " -o,  --output          <file>       Parsed per-frame MMPBSA results. Default is <--results file> appended with <parsed>."
  # echo " -do, --decomp_output   <file>       Parsed per-frame decomposition MMPBSA results. Default is <--decomp_results file> appended with <parsed>."
  echo " --equi                   <0|1>        (default=1) Parse MMPBSA results from equi stage."
  echo " --prod                   <0|1>        (default=1) Parse MMPBSA results from prod stage."
  echo " -n,  --replicas          <integer>    (default=3) Number of replicas or repetitions."
  echo " --start_replica          <integer>    (default=1) Run from --start_replica to --replicas."
}

# Check arguments
if [[ "$#" == 0 ]]; then
  echo "No options provided."
  echo "Use --help option to check available options."
  exit 1
fi

# Default values

START_REPLICA=1
REPLICAS=3
PARSE_RESULTS_FILE=1
PARSE_DECOMP_RESULTS_FILE=1
PARSE_EQUI=1
PARSE_PROD=1

# CLI option parser
while [[ $# -gt 0 ]]; do
  case "$1" in
  '-d' | '--work_dir'              ) shift ; WDDIR=$1 ;;
  '--parse_results'                ) shift ; PARSE_RESULTS_FILE=$1 ;;
  '--parse_decomp_results'         ) shift ; PARSE_DECOMP_RESULTS_FILE=$1 ;;
  '--equi'                         ) shift ; PARSE_EQUI=$1 ;;
  '--prod'                         ) shift ; PARSE_PROD=$1 ;;
  # '-o' | '--output'                ) shift ; PARSED_OUTPUT=$1 ;;
  # '-do' | '--decomp_ouput'         ) shift ; PARSED_DECOMP_OUTPUT=$1 ;;
  '-n' | '--replicas'              ) shift ; REPLICAS=$1 ;;
  '--start_replica'                ) shift ; START_REPLICA=$1 ;;
  '--help' | '-h'                  ) Help ; exit 0 ;;
  *                                ) echo "Unrecognized command line option: $1" >> /dev/stderr ; exit 1 ;;
  esac
  shift
done


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
  TOPO_DIR=${WDDIR}/setupMD/${RECEPTOR_NAME}/proteinLigandMD/${lig}/topo/
  mkdir -p ${MMPBSA_DIR}

}

function ParseOutput() {
  
  if [[ ${PARSE_RESULTS_FILE} -eq 1 ]]; then
    CheckFiles "per_frame_mmpbsa_results.data"
    awk -v flag=0 '/^DELTA/ {
    flag=1; next
    } flag' per_frame_mmpbsa_results.data > per_frame_mmpbsa_results_parsed.data
  fi

  if [[ ${PARSE_DECOMP_RESULTS_FILE} -eq 1 ]]; then

    CheckFiles "decomp_mmpbsa_results.data"

    # Step 1: get a file just with residue number and energy: res energy
    awk -v flag=0 '
    NR == 8 { # skip first 7 lines
      flag=1
    }
    /Sidechain/ {
      flag=0
    } flag
    ' decomp_mmpbsa_results.data > residue_energy_map.tmp

    # Step 2: Parse resnumber and energy column.
    awk -F',' ' 
    { 
      split($1,array," "); resnum=array[2]; print resnum, $18
    }
    ' residue_energy_map.tmp > residue_energy_map.data
    rm residue_energy_map.tmp

    # Step 3: put energy values in b-factor column
    cp ${TOPO_DIR}/${LIG_NAME}_com.pdb .

    awk '
      NR==FNR { # estamos en el priemr archivo que es un map residuo -> energia
        # Guardamos energía por número de residuo
        energy[$1] = $2
        next
      }

      # Segundo archivo
      /^(ATOM|HETATM)/ {
        resnum = $5
        new_b_factor = energy[resnum]

        # reemplazar columna del B-factor (col 61–66)
        printf "%s%6.3f%s\n", substr($0,1,60), new_b_factor, substr($0,67)
        next
      }
      # otras líneas se imprimen igual
      { print }
    ' residue_energy_map.data ${LIG_NAME}_com.pdb > MMPBSA.pdb

    CheckFiles "per_frame_decomp_mmpbsa_results.data"
    # Total decomposition data
    awk -F',' -v flag=0 '
    /^DELTA/ && $2 ~ /Total/ {
      flag=1; next
    } 
    /^DELTA/ {
      flag=0
    }
      flag {
      print $0
    }
    ' per_frame_decomp_mmpbsa_results.data > per_frame_total_decomp_mmpbsa_results.data
  
    # Side chain decomposition data
    awk -F',' -v flag=0 '
    /^DELTA/ && $2 ~ /Sidechain/ {
      flag=1; next
    } 
    /^DELTA/ {
      flag=0
    }
      flag {
      print $0
    }
    ' per_frame_decomp_mmpbsa_results.data > per_frame_sidechain_decomp_mmpbsa_results.data

    # Backbone decomposition data
    awk -F',' -v flag=0 '
    /^DELTA/ && $2 ~ /Backbone/ {
      flag=1; next
    } 
    /^DELTA/ {
      flag=0
    }
      flag {
      print $0
    }
    ' per_frame_decomp_mmpbsa_results.data > per_frame_backbone_decomp_mmpbsa_results.data
  fi
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

    # 
    LIG_NAME=$(basename ${LIG_NAME} .mol2)
    echo "Doing ligand: ${LIG_NAME}"

    if [[ ${PARSE_EQUI} -eq 1 ]]; then
      echo "Parsing equi per-frame MMPBSA results"
      ParseDirectory "equi" ${LIG_NAME} ${REP}

      cd ${MMPBSA_DIR}

      ParseOutput 

      cd ${WDDIR}
      echo "Done"
    fi

    if [[ ${PARSE_PROD} -eq 1 ]]; then
      echo "Parsing prod per-frame MMPBSA results"
      ParseDirectory "prod" ${LIG_NAME} ${REP}

      cd ${MMPBSA_DIR}

      ParseOutput 
   
      cd ${WDDIR}
      echo "Done"
    fi

  done
done

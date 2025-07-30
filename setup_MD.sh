#!/usr/bin/bash

# Global variables are always UPPERCASE.
# Local are used with local keyword and lowercase.
# If some function requires too much arguments,
# try using global variables directly, however, this is harder to
# read and debug.

function ScriptInfo() {
  DATE="2025"
  VERSION="0.0.1"
  GH_URL="https://github.com/tcaceresm/AmberMDHelper"
  LAB="http://schuellerlab.org/"

  cat <<EOF
###################################################
 Welcome to SetupMD version ${VERSION} ${DATE}   
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
  echo -e "\nUsage: bash setup_MD.sh OPTIONS\n"
  echo "This script sets up molecular dynamics simulations in the specified directory."
  echo -e "The specified directory must always have a folder named  \"receptor\" containing the receptor PDB 
and an optional \"ligands\" and \"cofactor\" folder containing MOL2 file of ligands and cofactor, respectively.\n"

  echo "Required options:"
  echo " -d, --work_dir     <path>       Working directory. Inside this directory, a folder named setupMD will be created which contains all necessary files."
  echo "Optional:"
  echo " -h, --help                      Show this help."
  echo " --prod_time        <integer>    (default=100) Simulation time (in ns) (2 fs timestep)."
  echo " --equi_time        <integer>    (default=10) Simulation time (in ns) of last step of equilibration (2 fs timestep)"
  echo " -n, --replicas     <integer>    (default=3) Number of replicas or repetitions."
  echo " --prot_only        <0|1>        (default=0) Setup only protein MD."
  echo " --prot_lig         <0|1>        (default=0) Setup protein-ligand MD."
  echo " --prep_rec         <0|1>        (default=1) Prepare receptor. Receptor MUST be already protonated."
  echo " --prep_lig         <0|1>        (default=0) Prepare ligand. Ligand MUST be already protonated."
  echo " --include_cof      <0|1>        (default=0) Include cofactor."
  echo " --prep_cof         <0|1>        (default=0) Prepare cofactor if --include_cof 1. Cofactor MUST be already protonated."
  echo " --prep_topology    <0|1>        (default=0) Prepare topology files."
  echo " --prep_MD          <0|1>        (default=1) Prepare MD input files."
  echo " --calc_lig_charge  <0|1>        (default=1) Compute ligand (and cofactor) atoms' partial charges if --prep_lig 1."
  echo " --charge_method    <string>     (default="bcc") Charge method if --calc_lig_charge 1."
  #echo " --threads          <integer>    (default=1) Number of threads to execute this scripts. This is relevant when preparing several systems."
  echo " --lig_ff           <gaff|gaff2> (default="gaff2") Small molecule forcefield. This applies both ligand and cofactor."
  echo " --prot_ff          <string>     (default="ff19SB") Protein forcefield."
  echo " --water_model      <string>     (default="opc") Water model used in MD."
  echo " --box_size         <integer>    (default=14) Size of water box."
}

# Default values
PROD_TIME=100
EQUI_TIME=10
REPLICAS=3
PROT_ONLY_MD=0
PROT_LIG_MD=0
PREP_REC=1
PREP_LIG=0
INCLUDE_COFACTOR=0
PREP_COFACTOR=0
PREP_TOPO=1
PREP_MD=1
COMPUTE_CHARGES=1
CHARGE_METHOD="bcc"
MMPBSA=0
#NTHREADS=1
ENSEMBLE="npt"
LIG_FF="gaff2"
PROT_FF="ff19SB"
WATER_MODEL="opc"
BOX_SIZE=14

# CLI option parser
while [[ $# -gt 0 ]]; do
  case "$1" in
  '-d' | '--work_dir'        ) shift ; WDPATH=$1 ;;
  '--prod_time'              ) shift ; PROD_TIME=$1 ;;
  '--equi_time'              ) shift ; EQUI_TIME=$1 ;;
  '-n' | '--replicas'        ) shift ; REPLICAS=$1 ;;
  '--prot_only'              ) shift ; PROT_ONLY_MD=$1 ;;
  '--prot_lig'               ) shift ; PROT_LIG_MD=$1 ;;
  '--prep_rec'               ) shift ; PREP_REC=$1 ;;
  '--prep_lig'               ) shift ; PREP_LIG=$1 ;;
  '--include_cof'            ) shift ; INCLUDE_COFACTOR=$1 ;;
  '--prep_cof'               ) shift ; PREP_COFACTOR=$1 ;;
  '--prep_topology'          ) shift ; PREP_TOPO=$1 ;;
  '--prep_MD'                ) shift ; PREP_MD=$1 ;;
  '--calc_lig_charge'        ) shift ; COMPUTE_CHARGES=$1 ;;
  '--charge_method'          ) shift ; CHARGE_METHOD=$1 ;;
  '--mmpbsa'                 ) shift ; MMPBSA=$1 ;;
  '--threads'                ) shift ; NTHREADS=$1 ;;
  '--lig_ff'                 ) shift ; LIG_FF=$1 ;;
  '--prot_ff'                ) shift ; PROT_FF=$1 ;;
  '--water_model'            ) shift ; WATER_MODEL=$1 ;;
  '--box_size'               ) shift ; BOX_SIZE=$1 ;;
  '--help' | '-h'            ) Help ; exit 0 ;;
  *                          ) echo "Unrecognized command line option: $1" >> /dev/stderr ; exit 1 ;;
  esac
  shift
done

function CheckVariable() {
  # Check if variable is not empty
  for ARG in "$@"; do
    if [[ -z ${ARG} ]]; then
      echo "Error: variable ${ARG}."
      exit 1
    fi
  done
}

function CheckDir() {
  # Check if arg is directory
  for ARG in "$@"; do
    if [[ ! -d ${ARG} ]]; then
      echo "Error: Directory ${ARG} doesn't exist."
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

function CheckProgram() {
  # Check if command is available
  for COMMAND in "$@"; do
    if ! command -v ${1} >/dev/null 2>&1; then
      echo "Error: ${1} program not available, exiting."
      exit 1
    fi
  done
}

function CheckProtLigDir() {

  if [[ ! -d "${WDPATH}/setupMD/${RECEPTOR_NAME}/proteinLigandMD" ]]; then
    echo "Error: "${WDPATH}/setupMD/${RECEPTOR_NAME}/proteinLigandMD" \
directory doesn't exist. In this case, this means that you're trying \
to process ligands but you haven't configured the proteinLigandMD \
directories. Try adding --prot_lig 1 option."
    exit 1
  fi
}

SUBDIRS=("equi/npt" "equi/nvt" "prod/npt" "prod/nvt")

function CreateProtOnlyDirs() {
  # Add something here
  local rec_name=$1

  PROT_ONLY_BASE_DIR="${WDPATH}/setupMD/${rec_name}/onlyProteinMD/"
  mkdir -p ${PROT_ONLY_BASE_DIR}/topo

  for rep in $(seq 1 ${REPLICAS}); do
    for subdir in "${SUBDIRS[@]}"; do
      mkdir -p "${PROT_ONLY_BASE_DIR}/MD/rep${rep}/${subdir}"
    done
  done
  echo -e "\nCreated Protein-only directories."
}

function LigParser() {
  # Ligands' related variable
  # Raw ligands are in WDPATH/ligands dir
  # These are GLOBAL variables.
  shopt -s nullglob
  LIGANDS_PATH=("${WDPATH}/ligands/"*.mol2)
  shopt -u nullglob
  # WDPATH/ligands can't be empty if PREP_LIG is activated.
  if [[ ${PREP_LIG} -eq 1 ]]; then
    if [[ ${#LIGANDS_PATH[@]} -eq 0 ]]; then
      echo "Error: --prep_lig is 1 but ligands folder is empty."
      exit 1
    fi
  fi

  LIGANDS_NAME=()
  LIGANDS_LIB_DIR=()
  for LIGAND_PATH in ${LIGANDS_PATH[@]}; do
    LIGAND_NAME=$(basename "${LIGAND_PATH}" .mol2)
    LIGANDS_NAME+=("$LIGAND_NAME")
    LIGANDS_LIB_DIR+=("${WDPATH}/setupMD/${RECEPTOR_NAME}/proteinLigandMD/${LIGAND_NAME}/lib")
  done

}

function CreateProtLigDirs() {
  local rec_name=$1
  shift
  
  if [[ $# -eq 0 ]]; then
    echo "Error: Ligands array provided to CreateProtLigDirs() is empty."
    exit 1
  fi

  local lig
  for lig in "$@"; do
    local prot_lig_base_dir="${WDPATH}/setupMD/${RECEPTOR_NAME}/proteinLigandMD/${lig}"
    mkdir -p ${prot_lig_base_dir}/{lib,MD,topo}
    
    for rep in $(seq 1 ${REPLICAS}); do
      for subdir in "${SUBDIRS[@]}"; do
        mkdir -p "${prot_lig_base_dir}/MD/rep${rep}/${subdir}"
      done
    done
  done
  echo -e "\nCreated Protein-Ligand directories."
}

function CofParser() {
  # Cofactor related variable
  # Raw cofactor is in WDPATH/cofactor dir
  shopt -s nullglob
  COFACTOR_PATH=("${WDPATH}/cofactor/"*.mol2)
  shopt -u nullglob

  #local rec_name=$1

  if [[ ${#COFACTOR_PATH[@]} -eq 0 ]]; then
    echo "Error: --prep_cof is 1 but WDPATH/cofactor directory is empty."
    exit 1
  else
    COFACTOR_NAME=$(basename "${WDPATH}/cofactor/"*.mol2 .mol2)
    COFACTOR_LIB_DIR="${WDPATH}/setupMD/${RECEPTOR_NAME}/cofactor_lib/${COFACTOR_NAME}"

  fi
}
function CreateCofDir() {
  rec_name=$1
  cof_name=$2
  CheckVariable "${COFACTOR_LIB_DIR}"
  mkdir -p ${COFACTOR_LIB_DIR}
  echo -e "\nCreated cofactor directory."
}

function PrepareReceptor() {
  # Process receptor using pdb4amber
  local rec_name=$1
  echo -e "\n####################################"
  echo " Preparing receptor: ${rec_name}"
  echo "####################################"

  CheckVariable "${rec_name}" "${WDPATH}"

  local receptor_pdb_file="${WDPATH}/receptor/${rec_name}.pdb"
  local prep_pdb_path="${WDPATH}/setupMD/${rec_name}/receptor/"
  local prep_pdb_file="${prep_pdb_path}/${rec_name}_prep.pdb"

  mkdir -p ${prep_pdb_path}

  CheckFiles "${receptor_pdb_file}"
  cp ${receptor_pdb_file} ${prep_pdb_path}/${rec_name}_raw.pdb || exit 1
  
  CheckProgram "pdb4amber"
  pdb4amber -i ${prep_pdb_path}/${rec_name}_raw.pdb \
  -o ${prep_pdb_file} -l ${prep_pdb_path}/prepare_receptor.log

  echo -e "\nDone preparing receptor ${rec_name}\n"
}

function NetCharge() {
  # Compute molecule net charge from partial charges
  # MOL2 format
  local lig_lib_dir=$1
  local lig_name=$2

  echo -e "\nComputing net charge from partial charges of ${lig_name} file"
  LIGAND_NET_CHARGE=$(awk '/ATOM/{ f = 1; next } /BOND/{ f = 0 } f' ${lig_lib_dir}/${lig_name}.mol2 \
                      | awk '{sum += $9} END {printf "%.0f\n", sum}')
  echo -e "Net charge of ${lig_name}: ${LIGAND_NET_CHARGE}" | tee ${lig_lib_dir}/ligand_net_charge.log
}

function PrepareSmallMolecule() {
  # Prepare non-standard residue (small molecule - ligand or cofactor)
  # A good idea is to parallelize this.
  local mode=$1
  local lig_path=$2
  local lig_name=$3
  local lig_lib_dir=$4

  CheckProgram "antechamber" "parmchk2" "tleap"

  echo -e "\nPreparing small molecule: ${lig_name}"

  # copy from WDPATH/ligands/ to lib_dir
  cp ${lig_path} ${lig_lib_dir} || exit 1
  cd ${lig_lib_dir}
  
  NetCharge ${lig_lib_dir} ${lig_name}

  if [[ ${COMPUTE_CHARGES} -eq 1 ]]; then
    antechamber -i "${lig_lib_dir}/${lig_name}.mol2" -fi mol2 \
    -o "${lig_lib_dir}/${lig_name}.mol2" -fo mol2 -c "${CHARGE_METHOD}" \
    -nc "${LIGAND_NET_CHARGE}" -at ${LIG_FF} -rn "${mode}" -pf y
  else
    antechamber -i "${lig_lib_dir}/${lig_name}.mol2" -fi mol2 \
    -o "${lig_lib_dir}/${lig_name}.mol2" -fo mol2 -at ${LIG_FF} -rn "${mode}" -pf y
  fi

  antechamber -i "${lig_lib_dir}/${lig_name}.mol2" -fi mol2 -o "${lig_lib_dir}/${lig_name}_lig.pdb" \
                                -fo pdb -dr n -at ${LIG_FF} -rn "${mode}"
  parmchk2 -i "${lig_lib_dir}/${lig_name}.mol2" -f mol2 -o "${lig_lib_dir}/${lig_name}.frcmod"

  cat > ${lig_lib_dir}/leap_lib.in <<EOF
source leaprc.water.${WATER_MODEL}
source leaprc.${LIG_FF}

loadAmberParams ${lig_name}.frcmod
${mode} = loadmol2 ${lig_name}.mol2
check ${mode}
saveoff ${mode} ${lig_name}.lib

quit
EOF
    tleap -f "leap_lib.in" > prepare_ligand.log 2>&1
    cd ${WDPATH}
}


function CombineWrapper() {
  # Wrapper to setup Combine command from tleap
  # Combine is necessary when cof or lig is present
  # When prot_only:
  #   rec is receptor
  #   com is rec + cofactor
  # When prot_lig:
  #   rec is rec + cofactor (if present)
  #   com is rec + cofactor + lig

  local input_file=$1
  local mode=$2

  if [[ ${mode} == "prot_only" && ${INCLUDE_COFACTOR} -eq 1 ]]; then
    echo -en "\ncom = combine {rec cof} " >> ${input_file}
  fi

  if [[ ${mode} == "prot_lig" ]]; then
    if [[ ${INCLUDE_COFACTOR} -eq 1 ]]; then
      echo -en "\nrec = combine {rec cof} " >> ${input_file}
      echo -en "\ncom = combine {rec lig} " >> ${input_file}
    else
      echo -en "\ncom = combine {rec lig} " >> ${input_file}
    fi
  fi

}

function ParseTopologyOptions() {
  while [[ $# -gt 0 ]] ; do
    case "$1" in
      'mode'             ) shift ; MODE=$1 ;;
      'lig'              ) shift ; LIG=$1 ;;
      #'include_cof'      ) shift ; CONTAIN_COFACTOR=1 ;;
      *                  ) echo "Unrecognized option: $1" >> /dev/stderr ; exit 1 ;;
    esac
    shift
  done
}
function TopologyParser() {
  # Parse relevant variables
  # Target is com or rec:
  #   Rec when prot_only without cof
  #   Com otherwise
  # These directories are relatives to TOPO_DIR folder.

  ParseTopologyOptions "$@"

  if [[ ${MODE} == "prot_only" ]]; then
    TOPO_DIR="${WDPATH}/setupMD/${RECEPTOR_NAME}/onlyProteinMD/topo"
    PREP_PDB_DIR="../../receptor"
    TOPO_NAME=${RECEPTOR_NAME} #
    if [[ ${INCLUDE_COFACTOR} -eq 1 ]]; then
      COF_LIB_DIR="../../cofactor_lib/${COFACTOR_NAME}" 
    fi

  elif [[ ${MODE} == "prot_lig" ]]; then
    TOPO_DIR="${WDPATH}/setupMD/${RECEPTOR_NAME}/proteinLigandMD/${LIG}/topo"
    PREP_PDB_DIR="../../../receptor"
    LIG_LIB_DIR="../lib"
    TOPO_NAME=${LIG} #
    if [[ ${INCLUDE_COFACTOR} -eq 1 ]]; then
      COF_LIB_DIR="../../../cofactor_lib/${COFACTOR_NAME}"
    fi
  fi
  
  if [[ ${MODE} == "prot_only" && ! ${INCLUDE_COFACTOR} -eq 1 ]]; then
    TARGET="rec"
  else
    TARGET="com"
  fi
}

function PrepareTopology() {

  #ParseTopologyOptions "$@"
  CheckProgram "tleap"

  echo -e "\n# Preparing Topologies #"
  
  # Create common info leap
  local tleap_input="${TOPO_DIR}/tleap.in"
  cat <<EOF > ${tleap_input}
source leaprc.protein.${PROT_FF}
source leaprc.water.${WATER_MODEL}
source leaprc.${LIG_FF}
EOF
  # Add cofactor
  if [[ ${INCLUDE_COFACTOR} -eq 1 ]]; then
  cat <<EOF >> ${tleap_input}

loadoff ${COF_LIB_DIR}/${COFACTOR_NAME}.lib
loadAmberParams ${COF_LIB_DIR}/${COFACTOR_NAME}.frcmod
cof = loadpdb ${COF_LIB_DIR}/${COFACTOR_NAME}_lig.pdb
savepdb cof ./${COFACTOR_NAME}_cof.pdb
saveAmberParm cof ./${COFACTOR_NAME}_vac_cof.parm7 ./${COFACTOR_NAME}_vac_cof.rst7
EOF
  fi

  # Add ligand
  if [[ ! -z "${LIG}" ]]; then 
  cat <<EOF >> ${tleap_input}

loadoff ${LIG_LIB_DIR}/${LIG}.lib
loadAmberParams ${LIG_LIB_DIR}/${LIG}.frcmod
lig = loadpdb ${LIG_LIB_DIR}/${LIG}_lig.pdb
savepdb lig ./${LIG}_lig.pdb
saveAmberParm lig ./${LIG}_vac_lig.parm7 ./${LIG}_vac_lig.rst7
EOF
  fi

  # Add Rec step 1
  # Because rec is receptor + cof in prot_lig
  cat <<EOF >> ${tleap_input}

rec = loadpdb ${PREP_PDB_DIR}/${RECEPTOR_NAME}_prep.pdb
EOF

  # setup combine command from leap to create complex if contains cofactor and/or ligand
  CombineWrapper ${tleap_input} ${MODE}

  # Parse outputs name
  #TopologyNameWrapper ${MODE} ${CONTAIN_COFACTOR}

  # If prot_only and no cofactor
  if [[ ${MODE} == "prot_lig" || ${INCLUDE_COFACTOR} -eq 1 ]]; then
    cat <<EOF >> ${tleap_input}

savepdb rec ./${TOPO_NAME}_rec.pdb
saveAmberParm rec ./${TOPO_NAME}_vac_rec.parm7 ./${TOPO_NAME}_vac_rec.rst7
EOF
  fi

  # Add remaining options to leap input
  cat <<EOF >> ${tleap_input}

savepdb ${TARGET} ./${TOPO_NAME}_vac_${TARGET}.pdb
saveAmberParm ${TARGET} ./${TOPO_NAME}_vac_${TARGET}.parm7 ./${TOPO_NAME}_vac_${TARGET}.rst7

addIons ${TARGET} Na+ 0
addIons ${TARGET} Cl- 0

solvatebox ${TARGET} ${WATER_MODEL^^}BOX ${BOX_SIZE}

savepdb ${TARGET} ./${TOPO_NAME}_solv_${TARGET}.pdb
saveAmberParm ${TARGET} ./${TOPO_NAME}_solv_${TARGET}.parm7 ./${TOPO_NAME}_solv_${TARGET}.rst7

quit
EOF

  cd ${TOPO_DIR}
  tleap -f ./tleap.in # check if finished correctly?
  cd ${WDPATH}

}

# MD files
ParseAmberOptions() {
  # Parse Amber input options. This should be used inside createMin or createMD
  while [[ $# -gt 0 ]] ; do
    case "$1" in
      'ntmin'         ) shift ; NTMIN=$1 ;;
      'maxcyc'        ) shift ; MAXCYC=$1 ;;
      'ncyc'          ) shift ; NCYC=$1 ;;
      'ntr'           ) shift ; NTR=$1 ;;
      'restraintmask' ) shift ; RESTRAINTMASK=$1 ;;
      'restraint_wt'  ) shift ; RESTRAINT_WT=$1 ;;
      'irest'         ) shift ; IREST=$1 ;;
      'nstlim'        ) shift ; NSTLIM=$1 ;;
      'ntb'           ) shift ; NTB=$1 ;;
      'cut'           ) shift ; CUT=$1 ;;
      'ntc'           ) shift ; NTC=$1 ; NTF=$1 ;;
      'temp0'         ) shift ; TEMP0=$1 ;;
      'tempi'         ) shift ; TEMPI=$1 ;;
      'tautp'         ) shift ; TAUTP=$1 ;;
      'taup'          ) shift ; TAUP=$1 ;;
      'mcbarint'      ) shift ; MCBARINT=$1 ;;
      'gamma_ln'      ) shift ; GAMMA_LN=$1 ;;
      'dt'            ) shift ; DT=$1 ;;
      'nscm'          ) shift ; NSCM=$1 ;;
      'ntwx'          ) shift ; NTWX=$1 ;;
      'ntpr'          ) shift ; NTPR=$1 ;;
      'ntwr'          ) shift ; NTWR=$1 ;;
      'previousref'   ) REF=$RST ;;
      'thermo'        ) shift ; THERMOTYPE=$1 ;;
      'ntp'           ) shift ; NTP=$1 ;;
      'baro'          ) shift ; BAROTYPE=$1 ;;
      'varycond'      ) shift ; VARYTYPE=$1 ; ISTEP1=$2 ; ISTEP2=$3 ; VALUE1=$4 ; VALUE2=$5 ; shift 4 ;;
      *               ) echo "Unrecognized option: $1" >> /dev/stderr ; exit 1 ;;
    esac
    shift
  done
}

function CreateMinInput() {
  # Default values
  STEP=$1
  INPUT="${STEP}.in"
  shift
  IREST=0
  if [[ ${IREST} -eq 1 ]]; then
    NTX=5
  else
    NTX=1
  fi
  
  IMIN=1
  NTPR=100

  NTF=1
  CUT=10.0
  NSNB=10

  MAXCYC=10000
  NCYC=1000

  NTR=1
  RESTRAINTMASK=""
  RESTRAINT_WT=""

  ParseAmberOptions "$@"

  cat > ${INPUT} <<-EOF
Initial minimization w/ position restraints
&cntrl
  ! General flags describing the calculation
  imin = 1,   
  ! Nature and format of the output
  ntpr = ${NTPR},
  ! Potential function parameters
  cut = ${CUT}, nsnb = ${NSNB}, ntf = ${NTF},
  ! Energy minimization
  maxcyc = ${MAXCYC}, ncyc = ${NCYC}, ntmin = 1,
EOF
  if [[ ${NTR} -eq 1 ]]; then
    RestraintWrapper ${INPUT}
  fi
cat >> ${INPUT} <<-EOF
/
EOF
}

function createMdInput() {
  # Create MD input files.
  # Requires at least a step name --> createMdInput step1
  #   In this case, all default values are used (see below).
  # However, you can modify all parameters. This is achieved via ParseAmberOptions
  # Default values
  STEP=$1
  INPUT="${STEP}.in"
  shift
  IREST=1
  if [[ ${IREST} -eq 1 ]]; then
    NTX=5
  else
    NTX=1
  fi
  
  NTPR=100
  NTWX=1000
  NTWR=1000

  NTF=2
  CUT=10.0
  NSNB=10

  NTR=""
  RESTRAINTMASK=""
  RESTRAINT_WT=""

  NSTLIM=25000
  NSCM=1000
  DT=0.002

  NTC=2
  TOL=0.000001

  THERMOTYPE="langevin"
  TEMP0=300
  TEMPI=300
  GAMMA_LN=5.0
  TAUTP=1.0

  BAROTYPE="montecarlo"
  NTP=""
  NTB=""
  PRES0=1.0
  TAUP=1.0
  MCBARINT=100

  VARYTYPE=""
  ISTEP1=""
  ISTEP2=""
  VALUE1=""
  VALUE2=""

  ParseAmberOptions "$@"

  cat > ${INPUT} <<-EOF
${STEP}
&cntrl
  ! Nature and Format of input
  ntx = ${NTX}, irest = ${IREST},
  ! Nature and Format of output
  ntpr = ${NTPR}, ntwx = ${NTWX}, ntwr = ${NTWR},
  ! Potential function parameters
  ntf = ${NTF}, cut = ${CUT}, nsnb = ${NSNB},
  ! Molecular dynamics
  nstlim = ${NSTLIM}, nscm = ${NSCM}, dt = ${DT},
  ! SHAKE bond length constraints
  ntc = ${NTC}, tol = ${TOL},
EOF

  ThermostatWrapper ${INPUT}

  if [[ ${NTP} != "" && ${NTB} -eq 2 ]]; then # Only when NTP conditions NTB=2, NTP=1
    BarostatWrapper ${INPUT}
  fi

  if [[ ${NTR} -eq 1 ]]; then
    RestraintWrapper ${INPUT}
  fi

cat >> ${INPUT} <<-EOF
/
EOF

  VaryingConditionsWrapper ${INPUT}

}

function RestraintWrapper() {
  # Add restraint mask to input file
  inputFile=$1
  if [[ ("${RESTRAINTMASK}" != "" && "${RESTRAINT_WT}" == "") || ("${RESTRAINTMASK}" == "" && "${RESTRAINT_WT}" != "")  ]]; then
    echo "Restraint weight must be provided if using restraint mask and viceversa."
    exit 1
  elif [[ "${RESTRAINTMASK}" != "" && "${RESTRAINT_WT}" != "" ]]; then
    echo "  ! Restrained atoms" >> ${inputFile}
    echo "  ntr = 1, restraintmask = \"${RESTRAINTMASK}\", restraint_wt = ${RESTRAINT_WT}," >> ${inputFile}
  fi
}

function BarostatWrapper() {
  # Add Barostat info to input file
  inputFile=$1
  echo "  ! Pressure regulation" >> ${inputFile}
  if [[ "${BAROTYPE}" == "berendsen" ]]; then
    echo "  ntp = ${NTP}, ntb = ${NTB}, barostat = 1, taup = ${TAUP}, pres0 = ${PRES0}," >> ${inputFile}
  elif [[ "${BAROTYPE}" == "montecarlo" ]] ; then
    echo "  ntp = ${NTP}, ntb = ${NTB}, barostat = 2, pres0 = ${PRES0}, mcbarint = ${MCBARINT}," >> ${inputFile}
  else
    echo "Error in barostat."
    exit 1
  fi
}

function ThermostatWrapper() {
  # Add Thermostat info to input file
  inputFile=$1
  echo "  ! Temperature regulation" >> ${inputFile}
  if [[ "${THERMOTYPE}" == "berendsen" ]]; then
    echo "  ntt = 1, tempi = ${TEMPI}, temp0 = ${TEMP0}, tautp = ${TAUTP}," >> ${inputFile}
  elif [[ "${THERMOTYPE}" == "langevin" ]]; then
    echo "  ntt = 3, tempi = ${TEMPI}, temp0 = ${TEMP0}, gamma_ln = ${GAMMA_LN}," >> ${inputFile}
  else
    echo "Error in thermostat."
    exit 1
  fi
}

function TotalResWrapper() {
  # Obtain total residue of solute, using dry topology.
  TOPO=$1
  TOTALRES=$(cpptraj -p ${TOPO} --resmask \* | tail -n 1 | awk '{print $1}')
}

function VaryingConditionsWrapper() {
  # Add varying conditions to input file
  inputFile=$1
  if [[ ${VARYTYPE} != "" ]]; then
    echo "! Varying conditions" >> ${inputFile}
    NEWSTEP1=$((${ISTEP2} + 1))
    cat >> ${inputFile} <<-EOF
&wt type = '${VARYTYPE}', istep1 = ${ISTEP1}, istep2 = ${ISTEP2}, value1 = ${VALUE1}, value2 = ${VALUE2}, 
/
&wt type = '${VARYTYPE}', istep1 = ${NEWSTEP1}, istep2 = ${NSTLIM}, value1 = ${VALUE2}, value2 = ${VALUE2},
/
&wt type='END'
/
EOF
  fi
}

function ParseTime() {
  # Parse time in ns to nstlim
  NSTLIM_PROD=$((500000 * ${PROD_TIME}))
  NSTLIM_EQUI=$((500000 * ${EQUI_TIME}))
}

function ProtocolMD() {
    # Protocol:
  #   You can adapt this protocol.
  #   Default: 
  #     Equilibration:
  #        2 minimization steps, 1 temp increase (NVT), 5 NPT releasing restraint, 1 NPT no restrained.
  #     Production:
  #     NPT unrestrained.
  EQUI_DIR=$1
  PROD_DIR=$2
  TOTALRES=$3
  EQUI_TIME=$4
  PROD_TIME=$5
  # Equi
  cd ${EQUI_DIR}
  CreateMinInput min1 restraintmask ":1-${TOTALRES}&!@H=" restraint_wt 25.0
  CreateMinInput min2 restraintmask ":1-${TOTALRES}&!@H=" restraint_wt 5.0

  createMdInput md_nvt_ntr ntb 1 nstlim 25000 \
                ntr 1 restraintmask ":1-${TOTALRES}@CA,C,N" restraint_wt 5.0 \
                varycond 'TEMP0' 0 20000 100.0 300.0 \
                tempi 100

  createMdInput npt_equil_1 ntp 1 ntb 2 nstlim 50000 \
                ntr 1 restraintmask ":1-${TOTALRES}@CA,C,N" restraint_wt 5.0
  createMdInput npt_equil_2 ntp 1 ntb 2 nstlim 25000 \
                ntr 1 restraintmask ":1-${TOTALRES}@CA,C,N" restraint_wt 4.0
  createMdInput npt_equil_3 ntp 1 ntb 2 nstlim 25000 \
                ntr 1 restraintmask ":1-${TOTALRES}@CA,C,N" restraint_wt 3.0
  createMdInput npt_equil_4 ntp 1 ntb 2 nstlim 25000 \
                ntr 1 restraintmask ":1-${TOTALRES}@CA,C,N" restraint_wt 2.0
  createMdInput npt_equil_5 ntp 1 ntb 2 nstlim 25000 \
                ntr 1 restraintmask ":1-${TOTALRES}@CA,C,N" restraint_wt 1.0
  createMdInput npt_equil_6 ntp 1 ntb 2 nstlim ${EQUI_TIME}

  # Prod NPT
  cd ${PROD_DIR}
  createMdInput md_prod ntp 1 ntb 2 nstlim ${PROD_TIME}

}

function PrepareMMPBSARescoring() {
  mmpbsa_rescoring_dir=$1

}
############################################################
# Main script
############################################################

# Initial message
ScriptInfo

# Required options
CheckVariable "${WDPATH}"

# Path of this scripts and input files
SCRIPT_PATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Path of the working directory which contains receptor, ligand (optional) and cofactor (optional) folders
WDPATH=$(realpath "$WDPATH")

CheckUniqueFile ${WDPATH}/receptor/
RECEPTOR_NAME=$(basename "${WDPATH}/receptor/"*.pdb .pdb)

###### Test ######

if [[ ${PROT_LIG_MD} -eq 1 || ${PREP_LIG} -eq 1 ]]; then
  LigParser ${RECEPTOR_NAME}
fi

## ====== Create Directories ======

if [[ ${PROT_ONLY_MD} -eq 1 ]]; then
  CreateProtOnlyDirs ${RECEPTOR_NAME}
fi

if [[ ${PROT_LIG_MD} -eq 1 ]]; then
  CreateProtLigDirs ${RECEPTOR_NAME} ${LIGANDS_NAME[@]}
fi

if [[ ${INCLUDE_COFACTOR} -eq 1 ]]; then
  CofParser
  CreateCofDir ${RECEPTOR_NAME} ${COFACTOR_NAME}
fi

## ====== End Directories ======

## == Processing of protein, ligand and cofactor ==

if [[ ${PREP_REC} -eq 1 ]]; then
  PrepareReceptor ${RECEPTOR_NAME}
fi

if [[ ${PREP_LIG} -eq 1 ]]; then
  CheckProtLigDir
  CheckDir "${LIGANDS_LIB_DIR[@]}"

  for index in "${!LIGANDS_PATH[@]}"; do
    LIG_PATH="${LIGANDS_PATH[$index]}"
    LIG_NAME="${LIGANDS_NAME[$index]}"
    LIG_LIB_DIR="${LIGANDS_LIB_DIR[$index]}"

    PrepareSmallMolecule "LIG" ${LIG_PATH} ${LIG_NAME} ${LIG_LIB_DIR} 
  done
fi

if [[ ${PREP_COFACTOR} -eq 1 ]]; then
  if [[ ${INCLUDE_COFACTOR} -eq 1 ]]; then
    PrepareSmallMolecule "COF" ${COFACTOR_PATH} ${COFACTOR_NAME} ${COFACTOR_LIB_DIR}
  else
    echo "Error: If you want to prepare cofactor, set --include_cof 1."
    exit 1
  fi
fi

## == End of processing of protein, ligand and cofactor ==

## ====== Create Topologies ======
if [[ ${PREP_TOPO} -eq 1 ]]; then

  if [[ ${PROT_ONLY_MD} -eq 1 ]]; then

    TopologyParser "mode" "prot_only"

    PrepareTopology

  elif [[ ${PROT_LIG_MD} -eq 1 ]]; then
    for LIGAND_NAME in ${LIGANDS_NAME[@]}; do
      TopologyParser  "mode" "prot_lig" "lig" ${LIGAND_NAME}
      PrepareTopology 
    done
  fi

fi
## ====== End Create Topologies ======

## ====== Create MD files ======

if [[ ${PREP_MD} -eq 1 ]]; then
 
  ParseTime

  if [[ ${PROT_ONLY_MD} -eq 1 ]]; then

    TopologyParser mode "prot_only"
    TotalResWrapper ${TOPO_DIR}/${RECEPTOR_NAME}_vac_${TARGET}.parm7

    MODE_DIR="${WDPATH}/setupMD/${RECEPTOR_NAME}/onlyProteinMD"
    for REP in $(seq 1 ${REPLICAS}); do
    
      EQUI_DIR="${MODE_DIR}/MD/rep${REP}/equi/${ENSEMBLE}"
      PROD_DIR="${MODE_DIR}/MD/rep${REP}/prod/${ENSEMBLE}"
      ProtocolMD ${EQUI_DIR} ${PROD_DIR} ${TOTALRES} ${NSTLIM_EQUI} ${NSTLIM_PROD}
    
    done
    
    echo -e "\nDone creating MD files for prot only."
  fi

  if [[ ${PROT_LIG_MD} -eq 1 ]]; then
    
    LigParser
    
    for REP in $(seq 1 ${REPLICAS}); do
      for LIGAND_NAME in ${LIGANDS_NAME[@]}; do

        TopologyParser "mode" "prot_lig" "lig" ${LIGAND_NAME}
        TotalResWrapper ${TOPO_DIR}/${LIGAND_NAME}_vac_${TARGET}.parm7

        MODE_DIR="${WDPATH}/setupMD/${RECEPTOR_NAME}/proteinLigandMD/${LIGAND_NAME}"
        EQUI_DIR="${MODE_DIR}/MD/rep${REP}/equi/${ENSEMBLE}"
        PROD_DIR="${MODE_DIR}/MD/rep${REP}/prod/${ENSEMBLE}"

        ProtocolMD ${EQUI_DIR} ${PROD_DIR} ${TOTALRES} ${NSTLIM_EQUI} ${NSTLIM_PROD}

      done
    done

    echo -e "\nDone creating MD files for prot-lig."
  fi

fi
## ====== End Create MD files ======

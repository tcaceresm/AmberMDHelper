#! /usr/bin/bash

DATE="2025"
VERSION="0.0.1"
GitHub_URL="https://github.com/tcaceresm/AmberMDHelper"
LAB="http://schuellerlab.org/"

function ScriptInfo() {
  cat <<EOF
###################################################
Welcome to transplant coords version ${VERSION} ${DATE}   
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
  echo -e "\nThis scripts transplants cartesian coordinates from a reference PDB (donor, docked pose)"
  echo "to an acceptor pdb. Both pdb represent the same molecule."
  echo "The use case of this script is when you have a parameterized molecule (for example, using MCPB.py)"
  echo "and you want to apply MD of docked pose."
  echo " The docked pose won't have the correct atom types, but has the correct coordinates."
  echo " The parameterized molecule have the correct atom types, but not the docked atom coordinates."
  echo "Both must have the same atom order. A way to achieve this is:"
  echo " - First, keep only atom or hetatm records."
  echo " - Then, process with obabel, using --canonical and --addindex"
  echo "	For example: LIG.pdb is acceptor and DOCKED.pdb is donor"
  echo " 	obabel -i pdb LIG.pdb -o pdb -O LIG_processed.pdb --canonical --addindex"
  echo " 	obabel -i pdb DOCKED.pdb -o pdb -O DOCKED_processed.pdb --canonical --addindex"
  echo " - Again, keep only atom or hetatm records in processed pdb files."
  echo " - Finally, use this script."
  echo
  echo "Required options:"
  echo " -a       <file>           : PDB to mutate (acceptor)."
  echo " -d       <file>           : Reference (docked) pdb file. Donor of coords."

  echo "Optional:"
  echo " -h, --help                  : Show this help."
}

# Check arguments
if [[ "$#" == 0 ]]; then
  echo "Error: No options provided."
  echo "Use --help option to check available options."
  exit 1
fi

# Default values

# Command line options
while [[ $# -gt 0 ]]; do
  case "$1" in
  '-a'                          ) shift ; ACCEPTOR=$1 ;;
  '-d'                          ) shift ; DONOR=$1 ;;
  '--help' | '-h'               ) Help ; exit 0 ;;
  *                             ) echo "Unrecognized command line option: $1" >> /dev/stderr ; exit 1 ;;
  esac
  shift
done

awk '
NR==FNR && /^(ATOM|HETATM)/ {
    # Save coords (columnas 31-54)
    x[FNR] = substr($0,31,8)
    y[FNR] = substr($0,39,8)
    z[FNR] = substr($0,47,8)
    next
}
# en el receptor, reemplazamos esas columnas
/^(ATOM|HETATM)/ {
    printf "%s%8s%8s%8s%s\n", substr($0,1,30), x[FNR], y[FNR], z[FNR], substr($0,55)
    next
}
FNR != NR {
 print 
}
' ${DONOR} ${ACCEPTOR} > LIG_fixed.pdb

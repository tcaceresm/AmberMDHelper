#!/usr/bin/env python3

# Import all the necessary modules
try:
    import os
    import sys
    import time
    import numpy as np
    from argparse import ArgumentParser
except ImportError:
    raise ImportError("Unable to load the necessary modules")
    sys.exit()

###################################################################
# Variables
# ASMDwork      -- array holder for all the work
# FinalWork     -- an array holder of all the final works. It is used
#                  to determine which of the SMD sim is closest to the JA
# Beta          -- 1/(TEMP*1.98722E-3) == 1/(T*kb)
# ASMDFileNames -- array holder of all the names of input ASMD files
# JarAvg        -- array of holder work after JA is calculated
# RxnCoord      -- array holder of the Reaction Coordinates used in the SMD sim
# workskip      -- returns the number of rows to skip to get only the final work
###############################################################################

# Parse through ASMD files to get the work values
def ParseASMDWorkfiles(ASMDWorkFiles):
    ASMDwork = []
    FinalWork = []
    ASMDdict = {}
    RxnCoord = np.loadtxt(ASMDWorkFiles[0], skiprows=1, usecols=(0,))
    workskip = len(RxnCoord)
    ASMDFileNames = np.array(ASMDWorkFiles)
    for asmdinput in ASMDWorkFiles:
        ASMDwork.append(np.loadtxt(asmdinput, usecols=(3,), skiprows=1))
        FinalWork.append(np.loadtxt(asmdinput, usecols=(3,), skiprows=workskip))
        ASMDdict[len(FinalWork)] = asmdinput
    return ASMDwork, FinalWork, RxnCoord, workskip

# Calculate the Jarzynski Average
def CalcJA(WorkVals, TEMP):
    Beta = 1 / (TEMP * 1.98722E-3)
    JarAvg = -np.log(np.exp(np.array(WorkVals) * -Beta).mean(axis=0)) / Beta
    return JarAvg

# Determine which of the SMD files has the work closest to the JA
def Closest_to_JA(FinalWorkVals, JarAvgWork, workskip, ASMDFiles):
    diff_Work_JA = np.abs(np.array(FinalWorkVals) - JarAvgWork[workskip - 1])
    closestwork = diff_Work_JA.min()
    asmdfile = np.where(diff_Work_JA == closestwork)
    ASMDFileNames = np.array(ASMDFiles)
    # Return first match
    return ASMDFileNames[asmdfile[0][0]]

# Generate the output of the Rxn Coord and JarAvg
def Write_JA_output(Filename, JarAvgWork, RxnCoords):
    with open(Filename, 'w') as output_file:
        for coords, jarval in zip(RxnCoords, JarAvgWork):
            output_file.write(f"{coords} {jarval}\n")

def main():
    # Parse the command line arguments
    parser = ArgumentParser()
    parser.add_argument('-t', '--temp', default=300, type=float,
                        dest='TEMP', help='Temperature of the ASMD simulations')
    parser.add_argument('-f', '--inputfile', default=None, dest='INPUT_FILE', metavar='FILE',
                        help='Input file that contains the list of ASMD files to analyze')
    parser.add_argument('-o', '--output', default='_jar.PMF.dat', dest='JarFile', metavar="FILE",
                        help='Name of the PMF output file')
    parser.add_argument('-i', '--asmdfiles', default=None, metavar='FILES', nargs='*',
                        dest='asmdworkfiles', help='ASMD Files')
    Args = parser.parse_args()

    # Print usage if no arguments are given
    if len(sys.argv) == 1:
        parser.print_help()
        sys.exit(1)

    # Check that -f or -i was provided
    if Args.INPUT_FILE is None and Args.asmdworkfiles is None:
        parser.error("ASMD.py: error: options -i or -f required")

    # Get ASMD file list
    if Args.INPUT_FILE is None:
        ASMDFiles = Args.asmdworkfiles
    else:
        ASMDFiles = np.loadtxt(Args.INPUT_FILE, dtype=str)

    ASMDwork, FinalWork, RxnCoords, workskip = ParseASMDWorkfiles(ASMDFiles)
    JarAVG = CalcJA(ASMDwork, Args.TEMP)
    asmdfile = Closest_to_JA(FinalWork, JarAVG, workskip, ASMDFiles)
    Write_JA_output(Args.JarFile, JarAVG, RxnCoords)

    print(f"The trajectory closest to the Jarzynski Average is:{asmdfile}")

if __name__ == '__main__':
    main()

#!/bin/bash

###################################################################
#Author: Ryan P Smith (ryanpsmith@genome.wustl.edu ryan.smith.p@gmail.com)
#Version: 0.0.1 (first ever)
#Date: 2015-10-2
#Purpose: Starting point for single-cell sequencing L1 insertion analysis pipeline (LSF cluster).
###################################################################

###################################################################
####<etc>
###################################################################

#Set Script Name variable
SCRIPT=`basename ${BASH_SOURCE[0]}`

#Make sure script exits if any command crashes
#   This should prevent jobs from hanging in RUN state 
#   on LSF when a command crashes but the bash script doesn't exit.
set -e

####################################
####</etc>
####################################


###################################################################
####<getopts>
###################################################################

#Help function
function HELP {
  echo -e \
  "\nUsage: bash ${SCRIPT} -o [output] -s [sample] [fastq1.gz fastq2.gz]
                      -o <output dir> 
                      -s <sample name>\n" >&2
  exit 1
}

#Check the number of arguments. If none are passed, print help and exit.
if [ $# -eq 0 ]; then
  HELP
fi

#Set defaults (all args are mandatory in this case)
OUTPUT_DIR=false
SAMPLE=false
FQ1=false
FQ2=false

###hard coded values: these are not likely to change.
REF=/gscmnt/gc2719/halllab/genomes/human/GRCh37/hs37_ebv/hs37_ebv.fasta

while getopts :d:s:h FLAG; do
  case $FLAG in
    d)
      OUTPUT_DIR=$OPTARG
      ;;
    s)
      SAMPLE=$OPTARG
      ;;
    h)
      HELP
      ;;
    \?) #unrecognized option - show help
      echo -e "\nOption -$OPTARG not allowed." >&2
      HELP
      ;;
    :)
      echo -e "\nMissing option argument for -$OPTARG" >&2
      HELP
      ;;
  esac
done

shift $((OPTIND-1))

####################################
####</getopts>
####################################


###################################################################
####<Arguments verification>
###################################################################

if [ ! $SAMPLE ]; then
  echo -e "\nError: must provide -s (sample name) argument." >&2
  HELP
fi

if [ ! $OUTPUT_DIR ]; then
  echo -e "\nError: must provide -o (output dir) argument." >&2
  HELP
fi

#get positional fastq filenames
if [ $# == 2 ]; then
  FASTQS=("$@")
  FQ1=${FASTQS[0]}
  FQ2=${FASTQS[1]}
else
  echo -e "\nError: must provide two paired fastq.qz files" >&2
  HELP
fi


####################################
####</Arguments verification>
####################################


###################################################################
####<Main>
###################################################################

#get mean and stdev fragment lengths by mapping a sample of reads with bwa mem.
#filter dupes with samblaster -r, samtools view only non-secondary proper pairs, 
#grab positive TLEN field, end after 100000 TLENS have been sampled.
#use ztats to get various stats, grep out the stdev and arith field,
#cut on ":" (stdev: 25), convert float to int with awk
#<<< allows the two values produced by this command to be read into two variables, MEAN and STDEV.
#this will be expanded to pipe the merged contigs and paired reads to SpeedSeq for alignment
read MEAN STDEV <<<$( bwa mem -t 8 -M $REF $FQ1 $FQ2 | samblaster -r |
    samtools view -f 2 -F 256 - | cut -f 9 | awk '$0 > 0' | head -n 100000 |
        zstats | grep -e stdev -e arith | cut -d':' -f 2 | awk '{print int($0)}' );

RLEN=$( zcat $FQ1 | sed -n '2~4p' | head -n 5000 | awk 'length($0)>x{x=length($0)};END{print x}' );

flash -z -t 8 -r $RLEN -s $STDEV -f $MEAN -d $OUTPUT_DIR -o $SAMPLE <(zcat $FQ1) <(zcat $FQ2);

exit 0

####################################
####</Main>
####################################
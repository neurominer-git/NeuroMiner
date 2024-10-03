#!/bin/bash

echo '****************************************'
echo '***          NeuroMiner              ***'
echo '***   SLURM joblist manager CORE:    ***'
echo '***    (c) 2023 N. Koutsouleris      ***'
echo '****************************************'
echo '        VERSION 1.2 Feanor              '
echo '****************************************'

# compiled with matlab R2023b so MCR main is R2023b. Needs to change if different MCR is used.
export LD_LIBRARY_PATH=/data/core-psy-pronia/opt/matlab/R2023b/runtime/glnxa64:/data/core-psy-pronia/opt/matlab/R2023b/bin/glnxa64:/data/core-psy-pronia/opt/matlab/R2023b/sys/os/glnxa64:/data/core-psy-pronia/opt/matlab/R2023b/sys/opengl/lib/glnxa64
export JOB_DIR=$PWD
NEUROMINER=/data/core-psy-pronia/opt/NM/NeuroMinerMCCMain_1.3_R2023b_core/for_testing
export ACTION=train
read -e -p 'Path to NM structure: ' datpath
if [ ! -f $datpath ]; then
 	echo $datpath' not found.'
 	exit 
fi

export masterpath=''
read -p 'Define processing mode [ 1 = from scratch, 2 = using PreprocData Master file ] ' procmode
if [ "$procmode" = '2' ] ; then
	read -e -p 'Path to PreprocData Master file: ' masterpath
	if [ ! -f $masterpath ]; then
		echo $masterpath' not found.' exit
	fi
else
	masterpath=NaN
fi

read -e -p 'Path to job directory ['$JOB_DIR']: ' tJOB_DIR
if [ "$tJOB_DIR" != '' ]; then
	if [ -d $tJOB_DIR ]; then 
		export JOB_DIR=$tJOB_DIR
	else
		echo $tJOB_DIR' not found.'
		exit
	fi
fi 

read -e -p 'Change path to compiled NeuroMiner directory ['$NEUROMINER']: ' tNEUROMINER
if [ "$tNEUROMINER" != '' ]; then     
  if [ -d $tNEUROMINER ]; then  
    export NEUROMINER=$tNEUROMINER
  else
    echo $tNEUROMINER' not found.'
    exit
  fi    
fi

echo '-----------------------'
echo 'PATH definitions:'
echo 'LOG directory: '$JOB_DIR
echo 'NeuroMiner directory: '$NEUROMINER
echo '-----------------------'
read -p 'Index to analysis container [NM.analysis{<index>}]: ' analind
if [ "$analind" = '' ] ; then
	echo 'An analysis index is mandatory! Exiting program.'
	exit   
fi
read -p 'CV2 grid start row: ' CV2x1
read -p 'CV2 grid end row: ' CV2x2
read -p 'CV2 grid start column: ' CV2y1
read -p 'CV2 grid end column: ' CV2y2
read -p 'No. of SLURM jobs: ' numCPU
read -p 'xxxx GB RAM / SLURM job: ' Memory
MemoryGB=$Memory'GB'

read -p 'Overwrite existing CVdatamats [yes = 1 | no = 2]: ' ovrwrt
read -p 'Server to use [any=1, jobs-cpu=2, jobs-cpu-long=3, jobs-matlab=4]: ' sind

 if [ "$sind" = '1' ]; then
        SERVER_ID='jobs-matlab'
	echo "WARNING: if it is a long job please use jobs-cpu-long"
 elif [ "$sind" = '2' ]; then
        SERVER_ID='jobs-cpu'
	echo "WARNING: if it is a long job please use jobs-cpu-long"
 elif [ "$sind" = '3' ]; then
        SERVER_ID='jobs-cpu-long'
 elif [ "$sind" = '4' ]; then
        SERVER_ID='jobs-matlab'
 else
        echo "Enter a number between 1-4"
 fi

# for now use n per default
read -p 'Submit jobs immediately [y]: ' todo
# create the MCR cache directory
if [ ! -d /data/core-psy-pronia/opt/temp/$USER ]; then
mkdir /data/core-psy-pronia/opt/temp/$USER
fi

for curCPU in $(seq $((numCPU)))
do
SD='_CPU'$curCPU
pdir='paramfiles/A'$analind
ParamFile=$JOB_DIR/$pdir/Param_NM_$ACTION$SD
echo 'Generate parameter file: svm'$SD' => '$ParamFile
if [ ! -d $JOB_DIR/$pdir ]; then
if [ ! -d $JOB_DIR/paramfiles ]; then
mkdir $JOB_DIR/paramfiles
fi
mkdir $JOB_DIR/$pdir
fi
# Generate parameter file
cat > $ParamFile <<EOF
$NEUROMINER
$datpath
$masterpath
$JOB_DIR
$analind
$ovrwrt
$curCPU
$numCPU
$CV2x1
$CV2x2
$CV2y1
$CV2y2
EOF
done
SLURMFile=$JOB_DIR/NM_$ACTION'_A'$analind.slurm
tmp=$ACTION'_CPU'
out=$ACTION'_slurm'
# create the log directory
if [ ! -d $JOB_DIR/log ]; then
mkdir $JOB_DIR/log
fi
cat > $SLURMFile <<EOF
#!/bin/sh
#SBATCH --output $JOB_DIR/log/nm$out-%A_%a.log
#SBATCH --error $JOB_DIR/log/nm$out-%A_%a.err
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --partition=$SERVER_ID
#SBATCH --account=core-psy
#SBATCH --cpus-per-task=2
#SBATCH --mem=$MemoryGB
#SBATCH --job-name=nm$ACTION
#SBATCH --array=1-$numCPU
#SBATCH -J NM_Train

$PMODE
export MCR_CACHE_ROOT=/data/core-psy-pronia/opt/temp/$USER
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH
cd $NEUROMINER 
./NeuroMinerMCCMain $ACTION $JOB_DIR/$pdir/Param_NM_$tmp\${SLURM_ARRAY_TASK_ID}
EOF
chmod u+x $SLURMFile
datum=`date +"%Y%m%d"`
if [ "$todo" = 'y' -o "$todo" = 'Y' ] ; then
sbatch $SLURMFile >> $JOB_DIR/$pdir/NeuroMiner_Train_$datum.log
fi

#!/bin/bash

echo '****************************************'
echo '***          NeuroMiner              ***'
echo '***     Mac Parallel Job Manager     ***'
echo '***    (c) 2023 N. Koutsouleris      ***'
echo '****************************************'
echo '        VERSION 1.2 Feanor (Mac)        '
echo '****************************************'

# Mac-specific MCR setup - adjust path to your MCR installation
export DYLD_LIBRARY_PATH=/Applications/MATLAB/MATLAB_Runtime/R2023b/runtime/maci64:/Applications/MATLAB/MATLAB_Runtime/R2023b/bin/maci64:/Applications/MATLAB/MATLAB_Runtime/R2023b/sys/os/maci64
export JOB_DIR=$PWD
NEUROMINER=/path/to/your/NeuroMinerMCCMain_Current_R2023b  # Update this path
export ACTION=preproc

# Get system info
TOTAL_CORES=$(sysctl -n hw.logicalcpu)
AVAILABLE_CORES=$((TOTAL_CORES - 2))  # Leave 2 cores free
TOTAL_MEM_GB=$(sysctl -n hw.memsize | awk '{print int($1/1024/1024/1024)}')

echo "Mac System Info:"
echo "Total CPU cores: $TOTAL_CORES"
echo "Available for processing: $AVAILABLE_CORES"
echo "Total RAM: ${TOTAL_MEM_GB}GB"
echo "Recommended max parallel jobs: $AVAILABLE_CORES"
echo '-----------------------'

read -e -p 'Path to NM structure: ' datpath
if [ ! -f "$datpath" ]; then
    echo "$datpath not found."
    exit 1
fi

read -e -p "Path to job directory [$JOB_DIR]: " tJOB_DIR
if [ "$tJOB_DIR" != '' ]; then
    if [ -d "$tJOB_DIR" ]; then 
        export JOB_DIR="$tJOB_DIR"
    else
        echo "$tJOB_DIR not found."
        exit 1
    fi
fi 

read -e -p "Change path to compiled NeuroMiner directory [$NEUROMINER]: " tNEUROMINER
if [ "$tNEUROMINER" != '' ]; then     
    if [ -d "$tNEUROMINER" ]; then  
        export NEUROMINER="$tNEUROMINER"
    else
        echo "$tNEUROMINER not found."
        exit 1
    fi    
fi

echo '-----------------------'
echo 'PATH definitions:'
echo "LOG directory: $JOB_DIR"
echo "NeuroMiner directory: $NEUROMINER"
echo '-----------------------'

read -p 'Index to analysis container [NM.analysis{<index>}]: ' analind
if [ "$analind" = '' ] ; then
    echo 'An analysis index is mandatory! Exiting program.'
    exit 1   
fi

read -p 'CV2 grid start row: ' CV2x1
read -p 'CV2 grid end row: ' CV2x2
read -p 'CV2 grid start column: ' CV2y1
read -p 'CV2 grid end column: ' CV2y2

read -p "No. of parallel jobs (max recommended: $AVAILABLE_CORES): " numCPU
if [ "$numCPU" -gt "$TOTAL_CORES" ]; then
    echo "Warning: You specified $numCPU jobs but only have $TOTAL_CORES cores. This may slow down your system."
    read -p "Continue anyway? [y/N]: " continue_anyway
    if [ "$continue_anyway" != 'y' ] && [ "$continue_anyway" != 'Y' ]; then
        exit 1
    fi
fi

read -p 'Overwrite existing PreprocData files [yes = 1 | no = 2]: ' ovrwrt

read -p 'Parallel execution method [gnu-parallel=1, xargs=2, background=3]: ' parallel_method
if [ "$parallel_method" = '' ]; then
    parallel_method=3  # Default to background processes
fi

# Create MCR cache directory (Mac equivalent)
MCR_CACHE_ROOT="$HOME/.matlab_mcr_cache"
if [ ! -d "$MCR_CACHE_ROOT" ]; then
    mkdir -p "$MCR_CACHE_ROOT"
fi
export MCR_CACHE_ROOT

echo "Creating parameter files..."

# Create parameter files
for curCPU in $(seq 1 $numCPU)
do
    SD="_CPU$curCPU"
    pdir="paramfiles/A$analind"
    ParamFile="$JOB_DIR/$pdir/Param_NM_$ACTION$SD"
    
    echo "Generate parameter file: NM_$ACTION$SD => $ParamFile"
    
    if [ ! -d "$JOB_DIR/$pdir" ]; then
        if [ ! -d "$JOB_DIR/paramfiles" ]; then
            mkdir -p "$JOB_DIR/paramfiles"
        fi
        mkdir -p "$JOB_DIR/$pdir"
    fi
    
    # Generate parameter file
    cat > "$ParamFile" <<EOF
$NEUROMINER
$datpath
$JOB_DIR
$analind
$curCPU
$numCPU
$CV2x1
$CV2x2
$CV2y1
$CV2y2
$ovrwrt
EOF
done

# Create log directory
if [ ! -d "$JOB_DIR/log" ]; then
    mkdir -p "$JOB_DIR/log"
fi

# Create execution script
ExecutionScript="$JOB_DIR/run_neurominers_A$analind.sh"
datum=$(date +"%Y%m%d")
logfile="$JOB_DIR/paramfiles/A$analind/NeuroMiner_PreProc_$datum.log"

echo "Creating execution script: $ExecutionScript"

if [ "$parallel_method" = '1' ]; then
    # GNU Parallel method
    cat > "$ExecutionScript" <<EOF
#!/bin/bash
export DYLD_LIBRARY_PATH=$DYLD_LIBRARY_PATH
export MCR_CACHE_ROOT=$MCR_CACHE_ROOT

echo "Starting NeuroMiner preprocessing with GNU Parallel..."
echo "Jobs: $numCPU, Analysis: $analind" | tee "$logfile"
echo "Started at: \$(date)" | tee -a "$logfile"

# Check if parallel is installed
if ! command -v parallel &> /dev/null; then
    echo "GNU parallel not found. Install with: brew install parallel"
    exit 1
fi

# Keep Mac awake during processing
caffeinate -i parallel --bar --joblog "$JOB_DIR/log/parallel_jobs.log" -j $numCPU \\
    "cd '$NEUROMINER' && ./NeuroMinerMCCMain $ACTION {} 2>&1 | tee '$JOB_DIR/log/nm_preproc_CPU{#}.log'" \\
    ::: "$JOB_DIR/paramfiles/A$analind"/Param_NM_${ACTION}_CPU*

echo "Completed at: \$(date)" | tee -a "$logfile"
EOF

elif [ "$parallel_method" = '2' ]; then
    # xargs method
    cat > "$ExecutionScript" <<EOF
#!/bin/bash
export DYLD_LIBRARY_PATH=$DYLD_LIBRARY_PATH
export MCR_CACHE_ROOT=$MCR_CACHE_ROOT

echo "Starting NeuroMiner preprocessing with xargs..."
echo "Jobs: $numCPU, Analysis: $analind" | tee "$logfile"
echo "Started at: \$(date)" | tee -a "$logfile"

# Keep Mac awake and run with xargs
caffeinate -i ls "$JOB_DIR/paramfiles/A$analind"/Param_NM_${ACTION}_CPU* | \\
    xargs -n 1 -P $numCPU -I {} sh -c 'CPU_NUM=\$(basename {} | sed "s/.*CPU//"); cd "'$NEUROMINER'" && ./NeuroMinerMCCMain '$ACTION' {} 2>&1 | tee "'$JOB_DIR'/log/nm_preproc_CPU\$CPU_NUM.log"'

echo "Completed at: \$(date)" | tee -a "$logfile"
EOF

else
    # Background processes method (default)
    cat > "$ExecutionScript" <<EOF
#!/bin/bash
export DYLD_LIBRARY_PATH=$DYLD_LIBRARY_PATH
export MCR_CACHE_ROOT=$MCR_CACHE_ROOT

echo "Starting NeuroMiner preprocessing with background processes..."
echo "Jobs: $numCPU, Analysis: $analind" | tee "$logfile"
echo "Started at: \$(date)" | tee -a "$logfile"

# Keep Mac awake
caffeinate -i &
CAFFEINATE_PID=\$!

cd "$NEUROMINER"

# Start all jobs in background
pids=()
for i in \$(seq 1 $numCPU); do
    echo "Starting job \$i..." | tee -a "$logfile"
    (./NeuroMinerMCCMain $ACTION "$JOB_DIR/paramfiles/A$analind/Param_NM_${ACTION}_CPU\$i" 2>&1 | tee "$JOB_DIR/log/nm_preproc_CPU\$i.log") &
    pids+=(\$!)
done

# Wait for all jobs to complete
echo "Waiting for all jobs to complete..." | tee -a "$logfile"
for pid in \${pids[@]}; do
    wait \$pid
    exit_code=\$?
    if [ \$exit_code -ne 0 ]; then
        echo "Warning: Job \$pid exited with code \$exit_code" | tee -a "$logfile"
    fi
done

# Stop caffeinate
kill \$CAFFEINATE_PID 2>/dev/null

echo "All jobs completed at: \$(date)" | tee -a "$logfile"
EOF
fi

chmod +x "$ExecutionScript"

echo "Setup complete!"
echo "Parameter files created in: $JOB_DIR/paramfiles/A$analind/"
echo "Execution script created: $ExecutionScript"
echo "Log files will be in: $JOB_DIR/log/"
echo ""

read -p 'Run jobs immediately [y/N]: ' todo
if [ "$todo" = 'y' ] || [ "$todo" = 'Y' ]; then
    echo "Starting NeuroMiner preprocessing..."
    "$ExecutionScript"
else
    echo "To run later, execute: $ExecutionScript"
fi

#!/bin/bash
#v1.1.7
# 3 or 4 args: 'name' alpha n0 [ncpus]
########################################################################
#
# MAPPINGS version
#
m_vers="v5.2.0"
map_exe="map52"
map_path="${HOME}/mappings520/bin"
#
########################################################################
#
# shock grid parameter - arg 2
#
# constant preshock density, disabled for rampressure below.
# n_H :
#predens="${2}"
#
# -ve alpha = -microgauss in proto state,
# +ve alpha = ratio Pmag/Pgas in proto state
#
# alpha = Pmag/Pgas = B^2/(8*pi*n*k*T)
#
alpha="${2}"
#
########################################################################
#
# Ram Pressure, nH*vel*vel , vel in km/s,
#
rampress="${3}*50.0*50.0"
#
pretemp="100.0"
#
# constant preshock density, disabled for rampressure above.
# n_H :
#predens="1.0"
#
########################################################################
#
# Abundances eg GC2016/GC_ZO_1000.abn etc see inputs and sub folders
#
abund="solar2009.txt"
#
# type: "etam" or "alpha"
#
type="alpha"
########################################################################
# do the hard ones first, finishing off with quick ones at the end.
#3.5-2.5
#
#ngrid=5
#v0="240"
#dv="-30"
# For Vela Jr. HH shocks
ngrid=25
v0="10"
dv="10"
#
#
########################################################################
#
# Using template directory duplication
# and MV script modification.
#
# Could run in tcsh, but running in bash so that the Linux
# /proc/cpuinfo query can discard errors only.
#
########################################################################
d=$(date "+%s" | awk '{print substr(sprintf("%X",$0),3,6)}')
echo " "$(date)
########################################################################
if (( $# < 1 )); then
      echo " Run an MV shock grid, with runname"
      echo " Run a 10 <= V <= 1500 shock grid"
      echo " and produce grid_XXX.csv file of log ratios to plot"
      echo " "
      echo " Usage1: runshocks.sh 'RunName'"
      echo " creates grid_RunName.csv and model files in RunName_modelfiles/"
      echo " "
      echo " Usage2: runshocks.sh 'RunName' n"
      echo " where n is the number of cpus to run on in parallel"
      echo " Creates grid_RunName.csv and model files in RunName_modelfiles/"
      echo " "
      exit -1
fi
########################################################################
#
echo " MV ${vers} S5 Shock Grid."
#
# should work in LINUX and BSD Unix, ie OSX:
# get the available number of cpus (virtual or otherwise)
#
cores=$( grep -c ^processor /proc/cpuinfo 2>/dev/null || sysctl -n hw.ncpu )
#
# number of parallel processes, default 1 if not specified
#
n=255
#
# if three or more argument set, use last one as ncpus
#
if [[ "${#}" -gt 2 ]]
then
      n="${!#}"
fi
# just the name and parameter
if [[ "$n" -le 2 ]]
then
     n=255
fi
#
if [[ $cores -gt 1 ]] && [[ $n -eq 1 ]] && [[ $n -gt $cores ]]
then
      echo " **** $cores CPUs are available,"
      echo " **** consider running on more than one CPU."
      echo " "
      echo " Usage2: runshocks.sh 'RunName' deltaM n100 n"
      echo " where n is the number of cpus to run on in parallel"
      echo " "
fi
#
########################################################################
#
echo " Running grid of ${ngrid} Shocks, ${n} at a time..."
#
# loop over grid, submitting jobs in the background.
# As jobs complete new ones are set going to keep the number running
# up to n as much as possible, until it tapers off at the end.
#
running=0
prunning=0
completed=0
pcompleted=-1
########################################################################
# process monitoring functions
#
# http://stackoverflow.com/questions/1455695/forking-multi-threaded-processes-bash
# by haridsv
#
declare -a pids
#
function checkPids() {
#echo  ${#pids[@]}
if [ ${#pids[@]} -ne 0 ]
then
#    echo "Checking for pids: ${pids[@]}"
    local range=$(eval echo {0..$((${#pids[@]}-1))})
    local i
    for i in $range; do
        if ! kill -0 ${pids[$i]} 2> /dev/null; then
#            echo "Done -- ${pids[$i]}"
            unset pids[$i]
            completed=$(expr $completed + 1)
        fi
    done
    pids=("${pids[@]}") # Expunge nulls created by unset.
    running=$((${#pids[@]}))
#    echo "PIDS #:"$running
fi
}
#
function addPid() {
    desc=$1
    pid=$2
    echo " ${desc} - "$(date)
    pids=(${pids[@]} $pid)
}
########################################################################
#
# Loop and report when job changes happen,
# keep going until all are completed.
#
idx=0
while [ $completed -lt ${ngrid} ]
do
#
if [[ $running -lt $n ]] && [[ $idx -lt ${ngrid} ]]
then
########################################################################
#
# submit a new model if less than n are running and we haven't finished...
#
# get name for velocity run, 1 decimal
# (using zero based counter idx)
#
    vValue=$( awk  "BEGIN{ printf(\"%#.6f\",(1.0*${v0}+${idx}*${dv})) }" )
    vName=$( awk  "BEGIN{ printf(\"%0#6.1f\",(1.0*${v0}+${idx}*${dv})) }" )
#
# make copy of V template and cd into it
#
cp -r V "V"${vName}
cd "V"${vName}
#
########################################################################
#
# edit the MV template script
# make the script and run it
#
# compute density from ram-pressure
#
    rpdens=$( awk  "BEGIN{printf(\"%.6e\",1.0*${rampress}/(${vValue}*${vValue}))}" )
#
    echo ${vValue}" "${alpha}" " ${rpdens}
#
    sed -e s/ABUNDANCES/${abund}/g \
        -e s/ALPHA/${alpha}/g \
        -e s/PRETEMP/${pretemp}/g \
        -e s/PREDENS/${rpdens}/g \
        -e s/VELOCITY/${vValue}/g \
        -e s/PREFIX/"v"${vName}/g \
        -e s/MVERSION/M${vers}/g \
        scripts/shocks5_alpha.mv > "shocks5_v${vName}".mv
# background execution
#echo "shocks5_v${vName}.mv"
# change delimiter % to allow / in paths
#
    sed -e s%MPATH%${map_path}%g \
        -e s%MEXE%${map_exe}%g\
         runmvtmpl.sh > runmvscript.sh
    chmod +x runmvscript.sh
    (./runmvscript.sh "shocks5_v${vName}".mv )>&/dev/null&
    addPid "shocks5_v${vName}" $!
    idx=$(expr $idx + 1)
#
########################################################################
# and go back up for next one .
cd ../
#
fi
#
checkPids
if [ $running -gt $prunning ] || [ $completed -gt $pcompleted ]
then
remain=$(expr $ngrid - $completed)
echo  " Running: "${running}" Submitted: "${idx}\
      " Completed: "$completed" Remaining: "$remain
fi
prunning=${running}
pcompleted=$completed
#sleep 1
#
done
#
########################################################################
#
# completed all the grid models
#
echo " All ${count} Completed. Processing output..."
echo " "$(date)
#
########################################################################
#
# Collect all the outputs into a global csv, extracting
# from sub directories in order....
#
mkdir ${1}modelfiles
cp V/scripts/*.awk .
cp V/scripts/getsh.sh .
cp V/scripts/getspec.sh .
cp V/scripts/getprespec.sh .
cp V/scripts/getfeprespec.sh .
cp V/scripts/getfespec.sh .
#
# collect data into csvs...
#
echo "===================================" > grid_${1}.csv
./getsh.sh  V[0-9]*   >> grid_${1}.csv
echo "===================================" >> grid_${1}.csv
#
echo "===================================" > grid_spec_${1}.csv
./getspec.sh  V[0-9]* >> grid_spec_${1}.csv
echo "===================================" >> grid_spec_${1}.csv
#
echo "===================================" > grid_fespec_${1}.csv
./getfespec.sh  V[0-9]* >> grid_fespec_${1}.csv
echo "===================================" >> grid_fespec_${1}.csv
#
echo "===================================" > grid_prespec_${1}.csv
./getprespec.sh  V[0-9]* >> grid_prespec_${1}.csv
echo "===================================" >> grid_prespec_${1}.csv
#
echo "===================================" > grid_prefespec_${1}.csv
./getfeprespec.sh  V[0-9]* >> grid_prefespec_${1}.csv
echo "===================================" >> grid_prefespec_${1}.csv
#
echo "==================================="
./getsh.sh  V[0-9]*
echo "==================================="
#
mv V[0-9]* ${1}modelfiles
#
rm getsh.sh
rm getspec.sh
rm getprespec.sh
rm getfeprespec.sh
rm getfespec.sh
rm *.awk
#
########################################################################
#
echo " Done! Output in ${1}modelfiles"
echo " "$(date)
echo " "

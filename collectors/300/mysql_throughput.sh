#!/bin/bash
# Tcollector to do some TCP analysis for mysql throughput
# NOTE: pt-tcp-model is needed for this collector (http://www.percona.com/doc/percona-toolkit/2.1/pt-tcp-model.html)
# Created by: Gavin Towey <gavin@box.com>
# Created on: 2012-12-19
# Updated by: Geoffrey Anderson <geoff@box.com>
# Updated on: 2012-12-21


####
# Variables you can change
####

# Prefix of your database metrics for this collector.
# NOTE: metrics generated by this collector are: concurrency, throughput, arrivals, completions, busy_time, weighted_time, sum_time, variance_mean, quantile_time, obs_time, avg_time
metric_prefix='mysql.tcpdump'

# duration to capture tcpdump data in seconds
sleep_time=11



####
# Additional variables for this script, change if necessary
####
tmp_dir='/tmp' # temporary directory to persist work files
lock_file="${self}.lockfile" # lock file to know if this script is already running
tcpdump_raw_file="tcpdump.out" # filename to store raw tcpdump file to be generated
model_work_file="tcpdump.temp" # filename to store ASCII-ized output file from raw tcpdump data
result_file="sliced.txt" # filename to store cleaned up analysis data
self="$(basename $0)" # this script



####
# Functions
####

# Quick and easy function to cleanup any files/directories made by this collector
cleanup_pt_tcp_collector()
{
	rm -f "${tmp_dir}/${model_work_file}" "${tmp_dir}/${result_file}" "${tmp_dir}/${lock_file}" "${tmp_dir}/${tcpdump_raw_file}"
}



####
# Script start!
####

# check lock file
if [[ -e "${tmp_dir}/${lock_file}" ]]
then
	echo "${self}: lock file ${lock_file} already exists, aborting"
	exit 1
fi

# Set a trap for if the script is killed before the wait time is over
trap 'rm -f "${tmp_dir}/${lock_file}"; exit' INT TERM EXIT
touch "${tmp_dir}/${lock_file}"


# Start on a clock tick interval for this collection
current_time="$(date +%s)"
next_time="$( echo "${current_time} 10" | awk '{ print (int( $1/$2)+1)*$2 }' )"
let wait_time=($next_time-$current_time-1)

if (( $wait_time < 0 ))
then
	wait_time=9
fi

#echo "waiting for $wait_time"
sleep $wait_time

# set trap to be sure tcpdump doesn't run for ever and clean up the temp file too
trap 'rm -f "${tmp_dir}/${lock_file}"; kill $tcpdump_pid; rm -f "${tmp_dir}/${tcpdump_raw_file}"; exit' INT TERM EXIT



# A lot of the following process is borrowed from Percona's documentation
# on pt-tcp-model at http://www.percona.com/doc/percona-toolkit/2.1/pt-tcp-model.html

# run the tcpdump, write to file, and sleep for a bit
tcpdump -s 384 -i any -nnq -tttt -w "${tmp_dir}/${tcpdump_raw_file}" \
	'tcp port 3306 and (((ip[2:2] - ((ip[0]&0xf)<<2)) - ((tcp[12]&0xf0)>>2)) != 0)' \
	2>/dev/null &

tcpdump_pid="$!"
sleep $sleep_time
kill $tcpdump_pid

# set trap to be sure both remote files are removed
trap 'rm -f "${tmp_dir}/${model_work_file}" "${tmp_dir}/${result_file}" "${tmp_dir}/${lock_file}" "${tmp_dir}/${tcpdump_raw_file}"; exit' INT TERM EXIT

# Consume the capture file generated above and kick out ASCII to a work file
tcpdump -nnq -tttt -r "${tmp_dir}/${tcpdump_raw_file}" 2>/dev/null > "${tmp_dir}/${model_work_file}"

# if the ASCII version of the tcpdump is empty, bail out
if [[ ! -s "${tmp_dir}/${model_work_file}" ]]
then
	cleanup_pt_tcp_collector
	exit 0
fi

# Run the pt-tcp-model analysis on the work file
pt-tcp-model "${tmp_dir}/${model_work_file}" | sort -n -k1,1 | pt-tcp-model --type=requests --run-time=10 > "${tmp_dir}/${result_file}"
data=($(sed -ne '2 p' "${tmp_dir}/${result_file}"))

# Get the appropriate metrics from the analyzed tcpdump data
let i=0
for metric in concurrency throughput arrivals completions busy_time weighted_time sum_time variance_mean quantile_time obs_time
do
	let i=i+1
	if [[ -z "${data[$i]}" ]]
	then
		data[$i]=0
	fi
	echo "${metric_prefix}.${metric} ${current_time} ${data[$i]}"

done

# Generate an avg_time metric based on the above data
if [[ -z "${data[2]}" || "${data[2]}" -eq 0 ]]
then
	avg_time=0
else
	avg_time="$( echo "${data[7]} ${data[2]}" | awk '{ print $1/$2 }' )"
fi
echo "${metric_prefix}.avg_time ${current_time} ${avg_time}"

# clean up files
cleanup_pt_tcp_collector

trap - INT TERM EXIT
exit 0

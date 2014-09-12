#!/bin/bash

FILTERFILE=
RRDDIR=
IFACE=
THREADS=$((2*`grep -c ^processor /proc/cpuinfo`))
[[ $THREADS =~ "^[0-9]+$" ]] && THREADS=1

. ./lib/init.sh
. ./lib/chunks.sh

run_capture() {
	dumpcap -q -i "$IFACE" -b duration:60 -w "$TMPDIR/raw/out.cap" 2> /dev/null || {
		echo "Error starting dumpcap" >&2
		kill 0
		exit 1
	}
}

while getopts "f:o:i:j:" opt; do
	case $opt in
		i)	IFACE="$OPTARG" ;;
		o)	RRDDIR="$OPTARG" ;;
		f)	FILTERFILE="$OPTARG" ;;
		j)	THREADS="$OPTARG" ;
			[[ $THREADS =~ "^[0-9]+$" ]] && {
				echo "Invalid argument $OPTARG" >&2
				exit 1
			}
			;;
		\?)	echo "Invalid option: -$OPTARG" >&2; exit 1 ;;
		:)	echo "Option -$OPTARG requires an argument." >&2; exit 1 ;;
		*)	echo "Unimplemented option: -$OPTARG" >&2; exit 1 ;;
	esac
done

[ -z "$IFACE" ] && echo "Missing mandatory option -i INTERFACE" >&2 && exit 1
[ -z "$RRDDIR" ] && echo "Missing mandatory option -o RRDDIRECTORY" >&2 && exit 1
[ -z "$FILTERFILE" ] && echo "Missing mandatory option -f FILTERFILE" >&2 && exit 1

init "$0"
run_capture &
analyze

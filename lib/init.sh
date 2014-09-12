#!/bin/bash

create_rrd() {
	local rrd="$1"

	# (period/resolution): (3d, 1min), (90d, 30min), (1y, 3h), (8y, 1d), (128y, 30d)
	rrdtool create "$rrd" --no-overwrite --step 60 \
		"DS:pkts:GAUGE:90:0:U" \
		"DS:bytes:GAUGE:90:0:U" \
		"RRA:MAX:0.5:1:4320" \
		"RRA:AVERAGE:0.5:1:4320" \
		"RRA:MAX:0.5:30:4320" \
		"RRA:AVERAGE:0.5:30:4320" \
		"RRA:MAX:0.5:180:2928" \
		"RRA:AVERAGE:0.5:180:2928" \
		"RRA:MAX:0.5:1440:2928" \
		"RRA:AVERAGE:0.5:1440:2928" \
		"RRA:MAX:0.5:1440:1558" \
		"RRA:AVERAGE:0.5:1440:1558"
}

setup_rrd() {
	local filters="$1"
	local rrddir="$2"
	local f

	[ ! -f "$rrddir/@.rrd" ] && create_rrd "$rrddir/@.rrd"
	[ ! -f "$rrddir/_.rrd" ] && create_rrd "$rrddir/_.rrd"

	while read f; do
		local label="${f%%,*}"

		[ -f "$filters.$label" ] && {
			[ ! -d "$rrddir/$label" ] && mkdir "$rrddir/$label"
			setup_rrd "$filters.$label" "$rrddir/$label"
		}

		[ -f "$rrddir/$label.rrd" ] && continue

		create_rrd "$rrddir/$label.rrd"

	done < "$filters"
}

cleanup() {
	echo "Cleaning up..."

	[ -n "$TMPDIR" ] && rm -r "$TMPDIR"
	kill 0
}

init() {
	trap cleanup EXIT
	TMPDIR="`mktemp --tmpdir -d "${0##*/}.XXXXXXXXXX"`"
#	[ -d "$TMPDIR" ] && rm -r "$TMPDIR"
	[ -z "$TMPDIR" ] && echo "Could not create TMPDIR \"$TMPDIR\"" && exit 1
	mkdir -p "$TMPDIR/raw" || {
		echo "Could not create directory \"$TMPDIR/raw\""
		exit 1
	}

	[ ! -d "$RRDDIR" ] && mkdir "$RRDDIR"

	setup_rrd "$FILTERFILE" "$RRDDIR"
}

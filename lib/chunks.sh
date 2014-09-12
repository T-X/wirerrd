#!/bin/bash


update_rrd_from_result() {
	local time="$1"
	local file="$2"
	local total_pkts=
	local total_bytes=
	local sum_pkts=0
	local sum_bytes=0
	local allrrd=
	local point

	csvtool namedcol "File name","Number of packets","Data size (bytes)" $f | \
		grep -v "File name,Number of packets,Data size (bytes)" | while read point; do
			local rrd="`echo "$point" | sed "s#$TMPDIR/filtered/\(.*\)\.cap,[0-9]*,[0-9]*#$RRDDIR/\1.rrd#"`"
			local foo="${point%,*}"
			local pkts=${foo##*,}
			local bytes=${point##*,}

			if echo "$rrd" | grep -q ".*@\.rrd$"; then
				total_pkts=$pkts
				total_bytes=$bytes
				allrrd="$rrd"
			else
				sum_pkts=$(($sum_pkts+$pkts))
				sum_bytes=$(($sum_bytes+$bytes))
			fi

			if [ -n "$total_pkts" ]; then
				echo "$allrrd $(($total_pkts-$sum_pkts)):$(($total_bytes-$sum_bytes))"
			fi

			rrdtool update "$rrd" "$time:$pkts:$bytes" || {
				echo "`date`: Error could not update RRD: file: $file, point: $point" >&2
			}
		done
}

update_rrd() {
	local time="$1"
	local f

	for f in $TMPDIR/results/*; do
		local ret
		local remrrd
		local diff

		ret="`update_rrd_from_result "$time" "$f" | tail -n1`"
		remrrd="`echo "$ret" | sed "s#\(.*\)@\.rrd.*#\1_.rrd#"`"
		diff="${ret#* }"

		rrdtool update "$remrrd" "$time:$diff"
	done
}

apply_filter() {
	local filters="$1"
	local capdir="$2"
	local label="$3"
	local rule="$4"
	local lock="$5"

	nice -n5 tshark -r "$capdir/@.cap" -Y "$rule" -w "$capdir/$label.cap" || {
		put_lock "$lock"
		return 1
	}

	put_lock "$lock"

	[ -f "$filters.$label" ] && {
		mkdir "$capdir/$label"
		ln -s "$capdir/$label.cap" "$capdir/$label/@.cap"
		explode_filters "$filters.$label" "$capdir/$label"
	}
}

get_lock() {
	local i
	local ret=""

	while true; do
		for i in `seq 1 $THREADS`; do
			[ -d "$TMPDIR/lock$i" ] && continue
			mkdir "$TMPDIR/lock$i" 2> /dev/null || continue
			
			ret="$TMPDIR/lock$i"
			break
		done

		[ -n "$ret" ] && break
		sleep 0.5
	done

	echo "$ret"
}

put_lock() {
	local lock="$1"

	[ ! -d "$lock" ] && {
		echo "Error, lock $lock does not exist!"
		exit 1
	}
	rm -r "$lock"
}

explode_filters() {
	local f
	local filters="$1"
	local capdir="$2"
	[ -z "$filters" ] && exit 1
	[ ! -d "$capdir" ] && exit 1
	[ ! -f "$capdir/@.cap" ] && exit 1

	while read f; do
		local lock
		local label="${f%%,*}"
		local rule="${f#*,}"
		[ -z "$label" ] && continue
		[ -z "$rule" ] && continue
		echo "$label" | grep -q "^[ \t]*#" && continue

		lock=`get_lock`
		apply_filter "$filters" "$capdir" "$label" "$rule" "$lock" &
	done < "$filters"

	wait

	capinfos -TmQ "$capdir"/*.cap > "$TMPDIR/results/${filters##*/}"
}

analyze_next_chunk() {
	local time="`date +%s`"
	echo "`date`: Processing chunk..."

	mkdir -p "$TMPDIR/filtered"
	mkdir -p "$TMPDIR/results"
	ln -s "$path$prev_file" "$TMPDIR/filtered/@.cap"
	
	echo "`date`: Filtering..."
	explode_filters "$FILTERFILE" "$TMPDIR/filtered"
	echo "`date`: Finished filtering!"
	echo "`date`: Updating RRDs..."
	update_rrd "$time"
	echo "`date`: Finished updating RRDs!"

	rm "$path$prev_file"
	rm -r "$TMPDIR/filtered"
	rm -r "$TMPDIR/results"

	echo "`date`: Finished chunk!"
	[ $(($time+60)) -le $((`date +%s`+5)) ] && echo "`date`: WARNING!!! We are slow :(" >&2
}

analyze_chunks() {
	while read path action file; do
		[ -n "$prev_file" ] && analyze_next_chunk
		prev_file=$file
	done
}

analyze() {
	echo "`date`: Waiting for first chunk"

	inotifywait -q -m "$TMPDIR/raw" -e create -e moved_to | analyze_chunks
}

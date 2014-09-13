#!/bin/bash

RRDDIR=
OUTDIR=

# IPv4 header + fastd header
EXTRAHEADERS=$((20+46))

draw_graph() {
	local name="$1"
	local namep="`printf "%-16s" $name`"
	local pngdir="$2"
	local rrddir="$3"

	rrdtool graph "$pngdir$name.kbits-1d.png" --end now --start end-$((24*60*60))s \
		--width 1280 --height 720 --full-size-mode \
		--lower-limit 0 \
		DEF:ds0="$rrddir@.rrd":bytes:AVERAGE \
		DEF:ds1="$rrddir$name.rrd":bytes:AVERAGE \
		"CDEF:ds0kbits=ds0,8,*,60,/,1024,/" \
		"CDEF:ds1kbits=ds1,8,*,60,/,1024,/" \
		VDEF:ds0max=ds0kbits,MAXIMUM \
		VDEF:ds0avg=ds0kbits,AVERAGE \
		VDEF:ds0min=ds0kbits,MINIMUM \
		VDEF:ds1max=ds1kbits,MAXIMUM \
		VDEF:ds1avg=ds1kbits,AVERAGE \
		VDEF:ds1min=ds1kbits,MINIMUM \
		COMMENT:"                 " \
		COMMENT:"Maximum       " \
		COMMENT:"Average       " \
		COMMENT:"Minimum\l" \
		LINE1:ds0kbits#0000FF:"All             " \
		GPRINT:ds0max:"%6.2lf %Skbit/s" \
		GPRINT:ds0avg:"%6.2lf %Skbit/s" \
		GPRINT:ds0min:"%6.2lf %Skbit/s\l" \
		LINE1:ds1kbits#FF0000:"$namep" \
		GPRINT:ds1max:"%6.2lf %Skbit/s" \
		GPRINT:ds1avg:"%6.2lf %Skbit/s" \
		GPRINT:ds1min:"%6.2lf %Skbit/s\l" > /dev/null
}

store_average() {
	local name="$1"
	local pngdir="$2"
	local rrddir="$3"
	local averages="`rrdtool graph /dev/null --end now --start end-$((24*60*60)) \
		DEF:ds0="$rrddir$name.rrd":bytes:AVERAGE \
		DEF:ds1="$rrddir$name.rrd":pkts:AVERAGE \
		"CDEF:ds0kbits=ds0,8,*,64,/,1024,/" \
		VDEF:ds0avg=ds0kbits,AVERAGE \
		CDEF:ds1s="ds1,60,/" \
		VDEF:ds1avg=ds1s,AVERAGE \
		PRINT:ds0avg:"%.3lf" PRINT:ds1avg:"%.3lf" | grep -v "^[0-9]*x[0-9]*$" | tr '\n' ' '`"
	local averages="${averages% }"
	local kbits="${averages%% *}"
	local pkts="${averages#* }"
	local fastdkbits=`echo "($pkts*$EXTRAHEADERS*8)/1024" | bc`
	local fastdkbitsx2=`echo "$kbits+$fastdkbits" | bc`

	echo "$name $kbits $pkts $fastdkbits $fastdkbitsx2" >> "$pngdir@.1d.data"
}

while getopts "i:o:" opt; do
	case $opt in
		i)	RRDDIR="$OPTARG" ;;
		o)	OUTDIR="$OPTARG" ;;
		\?)	echo "Invalid option: -$OPTARG" >&2; exit 1 ;;
		:)	echo "Option -$OPTARG requires an argument." >&2; exit 1 ;;
		*)	echo "Unimplemented option: -$OPTARG" >&2; exit 1 ;;
	esac
done

[ -z "$RRDDIR" ] && echo "Missing mandatory option -i RRDDIRECTORY" >&2 && exit 1
[ -z "$OUTDIR" ] && echo "Missing mandatory option -o OUTDIRECTORY" >&2 && exit 1

exportdirhash="`echo -n "$OUTDIR" | sha256sum | cut -f1 -d' '`"
tmpdir="`mktemp -d --tmpdir=/tmp .${0##*/}.$exportdirhash.XXXXXXXXXX`"
[ ! -d "$tmpdir" ] && {
	echo "Error, could not create temporary directory \"$tmpdir\"" >&2
	exit 1
}
chmod 755 "$tmpdir"

ln -s "$tmpdir/out" "$tmpdir/link"

find "$RRDDIR" -name "*.rrd" | while read i; do
	file="${i##*/}"
	relpath="${i#"$RRDDIR/"}"
	relpath="${relpath%"$file"}"

	[ ! -d "$tmpdir/out/$relpath" ] && mkdir -p "$tmpdir/out/$relpath"

	rrdtool dump | xz -c > "$tmpdir/out/$relpath$file.xml.xz"
	draw_graph "${file%.rrd}" "$tmpdir/out/$relpath" "$RRDDIR/$relpath"
	store_average "${file%.rrd}" "$tmpdir/out/$relpath" "$RRDDIR/$relpath"
done

find "$tmpdir/out/$relpath" -name "@.1d.data" | while read i; do
	echo "Type kbit/s(batman-adv) Packets/s kbit/s(VPN) kbit/s(2x-Gateway)" > "$i.tmp"
	cat "$i" | sort -k5rn,5 >> "$i.tmp"
	mv "$i.tmp" "$i"

	gnuplot << __EOF
set term svg size 1280,720
set output "$i.svg"
set style data histogram
set style histogram rowstack gap 1
set style fill solid border rgb "black"
set boxwidth 0.8
set xtics font "Times-Roman, 10" rotate by -45
set auto x
set yrange [0:*]
plot "$i" using 2 title col, \
	        '' using 4:xtic(1) title col
__EOF
	convert "$i.svg" "$i.png"
done

# Atomic directory substitution via symlink move
mv -T "$tmpdir/link" "$OUTDIR"

for i in /tmp/.${0##*/}.$exportdirhash.*; do
	[ "$i" = "$tmpdir" ] && continue

	echo "Removing: $i"
	rm -r "$i"
done

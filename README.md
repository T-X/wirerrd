# wirerrd - Wireshark to RRD

wirerrd is a tool to collect live statistics and draw graphs about
various types of traffic monitored on a network device. The types
are determined by wireshark filter rules.

## Requirements

* tshark
* dumpcap
* rrdtool
* inotifywait
* csvtool
* getopts
* gnuplot
* ImageMagick ("convert" tool)

## Usage

See "wirerdd -h" for the usage of "wirerdd collect" and "wirerdd export".

"wirerdd collect" is a tool which you should run in the background while
"wirerdd export" is a run-once tool, so you might want to put it into your
cron/crontab, for instance like this:

<pre><code>
*/5 *  * * * cd ~/dev/wirerrd/; ./wirerrd export -i ~/dev/analyzer/rrd -o ~/public_html/Freifunk/stats/ffhh
</code></pre>

## Filter files

You can create hierarchical statistics with multiple filter files in the 
following way: Specify the top level filter with "-f FILTERFILE". This
file might contain a rule "ICMPv6,icmpv6" ("label,wiresharkrule") for instance.
You can then specify more specific filtering by creating a filter file
called FILTERFILE.ICMPv6 where you could filter for various icmpv6 types
for instance. You do not need to explicitly select this second level
filter file on the command line as wirerrd will find it automatically
if the file name matches. So the dot in the filename is a delimiter for
each level of the hierarchie.

See the directory "contrib/filters/" for an example.

## Permissions

"wirerrd collect" needs to be able to capture on the device - either this
tool needs to be run as root or some Linux distributions (Debian, Ubuntu)
permit capturing for the group "wireshark" if enabled. See
/usr/share/doc/wireshark-common/README.Debian for that.

"wirerrd export" needs permissions to create or modify a symlink at
the given "-o EXPORTSYMLINK".

## Examples

https://www.metameute.de/~tux/Freifunk/stats/

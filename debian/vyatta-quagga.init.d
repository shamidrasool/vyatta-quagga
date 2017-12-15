#!/bin/bash
#
### BEGIN INIT INFO
# Provides: vyatta-unicast
# Required-Start: $local_fs $network $remote_fs $syslog
# Required-Stop: $local_fs $network $remote_fs $syslog
# Default-Start:  2 3 4 5
# Default-Stop: 0 1 6
# Short-Description: start and stop the Quagga routing suite
# Description: Quagga is a routing suite for IP routing protocols like 
#              BGP, OSPF, RIP and others. 
#	       Only zebra is started here, others are started by protocols
#	       during config process.
### END INIT INFO
#

. /lib/lsb/init-functions

declare progname=${0##*/}
declare action=$1; shift

pid_dir=/var/run/quagga
log_dir=/var/log/quagga

for dir in $pid_dir $log_dir ; do
    if [ ! -d $dir ]; then
	mkdir -p $dir
	chown quagga:quagga $dir
	chmod 755 $dir
    fi
done

# Simple quick test for IPV6 existance
has_ipv6 ()
{
    ping6 -q -c1 ::1 >/dev/null 2>/dev/null
}

vyatta_quagga_start ()
{
    local -a daemons

    if [ $# -gt 0 ] ; then
	daemons=( $* )
    elif has_ipv6; then
	daemons=( zebra ripd ripngd ospfd ospf6d bgpd )
    else
	daemons=( zebra ripd ospfd bgpd isisd )
    fi

    # Allow daemons to dump core
    ulimit -c unlimited

    log_daemon_msg "Starting routing daemons"
    for daemon in ${daemons[@]} ; do
	[ "$daemon" != zebra ] && log_progress_msg "$daemon"
	local pidfile=${pid_dir}/${daemon}.pid

	# Handle daemon specific args
	local -a args=( -d -P 0 -i $pidfile )
	case $daemon in
	    zebra)	args+=( -S -s 1048576 );;
	    bgpd)	args+=( -I );;
	esac

	start-stop-daemon --start --oknodo --quiet \
	    --chdir $log_dir --exec /usr/sbin/$daemon \
	    --pidfile $pidfile -- ${args[@]} || \
    	    ( log_action_end_msg 1 ; return 1 )
    done
    log_end_msg 0
}

vyatta_quagga_stop ()
{
    local -a daemons
    if [ $# -gt 0 ] ; then
	daemons=( $* )
    else
	daemons=( bgpd ospfd ripd ripngd ospf6d zebra isisd)
    fi

    log_action_begin_msg "Stopping routing services"
    for daemon in ${daemons[@]} ; do
	local pidfile=${pid_dir}/${daemon}.pid
	if [ -f $pidfile ]; then
	    log_action_cont_msg "$daemon"
	fi

	start-stop-daemon --stop --quiet --oknodo --retry 5 \
	    --exec /usr/sbin/$daemon --pidfile=$pidfile
	rm -f $pidfile
    done    
    log_action_end_msg $?

    if echo ${daemons[@]} | grep -q zebra ; then
	log_begin_msg "Removing all Quagga Routes"
	ip route flush proto zebra
	log_end_msg $?
    fi
}

vyatta_quagga_status ()
{
    local pidfile=$pid_dir/zebra.pid
    local binpath=/usr/sbin/zebra

    status_of_proc -p $pidfile $binpath vyatta-zebra && exit 0 || exit $?
}

case "$action" in
    start)
	vyatta_quagga_start $*
	;;

    stop)
	vyatta_quagga_stop $*
   	;;

    status)
	vyatta_quagga_status
	;;

    restart|force-reload)
	vyatta_quagga_stop $*
	sleep 2
	vyatta_quagga_start $*
	;;

    *)
    	echo "Usage: $progname {start|stop|restart|force-reload} [daemon...]"
	exit 1
	;;
esac

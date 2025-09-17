### BEGIN INIT INFO
# Provides:          ssh
# Required-Start:    $remote_fs $syslog
# Required-Stop:     $remote_fs $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Start daemon at boot time
# Description:       Enable service provided by daemon.
### END INIT INFO
service ssh start
iptables -t nat -I PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300

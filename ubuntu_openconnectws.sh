#!/bin/bash
cp /usr/share/zoneinfo/Asia/Dubai /etc/localtime

#Database Details
$db_host='54.252.157.104';
$db_user = "cyberlink";
$db_pass = "Cyberlink30051";
$db_name = "cyberlink";

install_require()
{
  clear
  echo "Updating your system."
  {
    apt-get -o Acquire::ForceIPv4=true update
  } &>/dev/null
  clear
  echo "Installing dependencies."
  {
    apt-get -o Acquire::ForceIPv4=true install stunnel4 ocserv -y
    apt-get -o Acquire::ForceIPv4=true install dos2unix nano curl unzip jq virt-what net-tools mysql-client -y
    apt-get -o Acquire::ForceIPv4=true install freeradius freeradius-mysql freeradius-utils python -y
    apt-get -o Acquire::ForceIPv4=true install gnutls-bin pwgen screen -y
  } &>/dev/null
}

install_freeradius()
{
clear
echo "Preparing authentication module."
{
  rm /etc/freeradius/3.0/sites-available/default
  rm /etc/freeradius/3.0/mods-available/sql
  rm /etc/freeradius/3.0/sites-available/inner-tunnel
  echo 'sql {

    dialect = "mysql"
    driver = "rlm_sql_mysql"

    sqlite {

      filename = "/tmp/freeradius.db"
      busy_timeout = 200
      bootstrap = "${modconfdir}/${..:name}/main/sqlite/schema.sql"

    }

    mysql {
      tls {
        #ca_file = "/etc/ssl/certs/my_ca.crt"
        #ca_path = "/etc/ssl/certs/"
        #certificate_file = "/etc/ssl/certs/private/client.crt"
        #private_key_file = "/etc/ssl/certs/private/client.key"
        #cipher = "DHE-RSA-AES256-SHA:AES128-SHA"

        tls_required = no
        tls_check_cert = no
        tls_check_cert_cn = no
      }

      warnings = auto
    }

    postgresql {

      send_application_name = yes

    }' >> /etc/freeradius/3.0/mods-available/sql
 echo "
    server = "$db_host"
    port = 3306
    login = "$db_user"
    password = "$db_pass"
    radius_db = "$db_name"
    " >> /etc/freeradius/3.0/mods-available/sql
 echo 'acct_table1 = "radacct"
   acct_table2 = "radacct"
   postauth_table = "radpostauth"
   authcheck_table = "radcheck"
   groupcheck_table = "radgroupcheck"
   authreply_table = "radreply"
   groupreply_table = "radgroupreply"
   usergroup_table = "radusergroup"
   delete_stale_sessions = yes

    pool {

      start = ${thread[pool].start_servers}
      min = ${thread[pool].min_spare_servers}
      max = ${thread[pool].max_servers}
      spare = 1
      uses = 1
      retry_delay = 30
      lifetime = 5
      idle_timeout = 10

    }

    read_clients = yes
    client_table = "nas"
    group_attribute = "SQL-Group"
    $INCLUDE ${modconfdir}/${.:name}/main/${dialect}/queries.conf
  }
' >> /etc/freeradius/3.0/mods-available/sql
  sudo ln -s /etc/freeradius/3.0/mods-available/sql /etc/freeradius/3.0/mods-enabled/
  sudo chgrp -h freerad /etc/freeradius/3.0/mods-available/sql
  sudo chown -R freerad:freerad /etc/freeradius/3.0/mods-enabled/sql
  cd /etc/freeradius/3.0/sites-available/
  wget --no-check-certificate https://pastebin.com/raw/Z2Qjhe4p -O default
  wget --no-check-certificate https://pastebin.com/raw/5UT82ghN -O inner-tunnel
  cd /etc/freeradius/3.0/; rm clients.conf
  echo "client localhost {

    ipaddr = 127.0.0.1
    proto = *
    secret = m7xjOM5PQZa5yXz4GPVFtdFHnyKxGsu9
    require_message_authenticator = no
    nas_type   = other
    limit {
      max_connections = 0
      lifetime = 0
      idle_timeout = 30
    }
  }
  client localhost_ipv6 {
    ipv6addr  = ::1
    secret    = testing123
  }
  client vpn.example.ca {

         ipaddr          = $(curl -s https://api.ipify.org)
         secret          = BMzQztmR18EF6bsqB4fD3fCqgv1C9Eff

  }
" >> clients.conf
  cd /etc/freeradius/3.0/certs/ && make
  chmod g+r /etc/freeradius/3.0/certs/server.pem
  cd /etc/radcli/; rm servers; rm radiusclient.conf
  echo "$(curl -s https://api.ipify.org) BMzQztmR18EF6bsqB4fD3fCqgv1C9Eff" >> /etc/radcli/servers
  echo "nas-identifier ocserv
authserver $(curl -s https://api.ipify.org)
acctserver $(curl -s https://api.ipify.org)
servers /etc/radcli/servers
dictionary /etc/radcli/dictionary
default_realm
radius_timeout 10
radius_retries 3
bindaddr *" >> /etc/radcli/radiusclient.conf
systemctl enable freeradius.service
systemctl start freeradius.service
systemctl restart freeradius.service
}&>/dev/null
}

install_squid()
{
clear
echo "Installing proxy."
{
sudo touch /etc/apt/sources.list.d/trusty_sources.list
echo "deb http://us.archive.ubuntu.com/ubuntu/ trusty main universe" | sudo tee --append /etc/apt/sources.list.d/trusty_sources.list > /dev/null
sudo apt update -y

sudo apt install -y squid3=3.3.8-1ubuntu6 squid=3.3.8-1ubuntu6 squid3-common=3.3.8-1ubuntu6
/bin/cat <<"EOM" >/etc/init.d/squid3
#! /bin/sh
#
# squid		Startup script for the SQUID HTTP proxy-cache.
#
# Version:	@(#)squid.rc  1.0  07-Jul-2006  luigi@debian.org
#
### BEGIN INIT INFO
# Provides:          squid
# Required-Start:    $network $remote_fs $syslog
# Required-Stop:     $network $remote_fs $syslog
# Should-Start:      $named
# Should-Stop:       $named
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Squid HTTP Proxy version 3.x
### END INIT INFO
NAME=squid3
DESC="Squid HTTP Proxy"
DAEMON=/usr/sbin/squid3
PIDFILE=/var/run/$NAME.pid
CONFIG=/etc/squid3/squid.conf
SQUID_ARGS="-YC -f $CONFIG"
[ ! -f /etc/default/squid ] || . /etc/default/squid
. /lib/lsb/init-functions
PATH=/bin:/usr/bin:/sbin:/usr/sbin
[ -x $DAEMON ] || exit 0
ulimit -n 65535
find_cache_dir () {
	w=" 	" # space tab
        res=`$DAEMON -k parse -f $CONFIG 2>&1 |
		grep "Processing:" |
		sed s/.*Processing:\ // |
		sed -ne '
			s/^['"$w"']*'$1'['"$w"']\+[^'"$w"']\+['"$w"']\+\([^'"$w"']\+\).*$/\1/p;
			t end;
			d;
			:end q'`
        [ -n "$res" ] || res=$2
        echo "$res"
}
grepconf () {
	w=" 	" # space tab
        res=`$DAEMON -k parse -f $CONFIG 2>&1 |
		grep "Processing:" |
		sed s/.*Processing:\ // |
		sed -ne '
			s/^['"$w"']*'$1'['"$w"']\+\([^'"$w"']\+\).*$/\1/p;
			t end;
			d;
			:end q'`
	[ -n "$res" ] || res=$2
	echo "$res"
}
create_run_dir () {
	run_dir=/var/run/squid3
	usr=`grepconf cache_effective_user proxy`
	grp=`grepconf cache_effective_group proxy`
	if [ "$(dpkg-statoverride --list $run_dir)" = "" ] &&
	   [ ! -e $run_dir ] ; then
		mkdir -p $run_dir
	  	chown $usr:$grp $run_dir
		[ -x /sbin/restorecon ] && restorecon $run_dir
	fi
}
start () {
	cache_dir=`find_cache_dir cache_dir`
	cache_type=`grepconf cache_dir`
	run_dir=/var/run/squid3
	#
	# Create run dir (needed for several workers on SMP)
	#
	create_run_dir
	#
	# Create spool dirs if they don't exist.
	#
	if test -d "$cache_dir" -a ! -d "$cache_dir/00"
	then
		log_warning_msg "Creating $DESC cache structure"
		$DAEMON -z -f $CONFIG
		[ -x /sbin/restorecon ] && restorecon -R $cache_dir
	fi
	umask 027
	ulimit -n 65535
	cd $run_dir
	start-stop-daemon --quiet --start \
		--pidfile $PIDFILE \
		--exec $DAEMON -- $SQUID_ARGS < /dev/null
	return $?
}
stop () {
	PID=`cat $PIDFILE 2>/dev/null`
	start-stop-daemon --stop --quiet --pidfile $PIDFILE --exec $DAEMON
	#
	#	Now we have to wait until squid has _really_ stopped.
	#
	sleep 2
	if test -n "$PID" && kill -0 $PID 2>/dev/null
	then
		log_action_begin_msg " Waiting"
		cnt=0
		while kill -0 $PID 2>/dev/null
		do
			cnt=`expr $cnt + 1`
			if [ $cnt -gt 24 ]
			then
				log_action_end_msg 1
				return 1
			fi
			sleep 5
			log_action_cont_msg ""
		done
		log_action_end_msg 0
		return 0
	else
		return 0
	fi
}
cfg_pidfile=`grepconf pid_filename`
if test "${cfg_pidfile:-none}" != "none" -a "$cfg_pidfile" != "$PIDFILE"
then
	log_warning_msg "squid.conf pid_filename overrides init script"
	PIDFILE="$cfg_pidfile"
fi
case "$1" in
    start)
	res=`$DAEMON -k parse -f $CONFIG 2>&1 | grep -o "FATAL: .*"`
	if test -n "$res";
	then
		log_failure_msg "$res"
		exit 3
	else
		log_daemon_msg "Starting $DESC" "$NAME"
		if start ; then
			log_end_msg $?
		else
			log_end_msg $?
		fi
	fi
	;;
    stop)
	log_daemon_msg "Stopping $DESC" "$NAME"
	if stop ; then
		log_end_msg $?
	else
		log_end_msg $?
	fi
	;;
    reload|force-reload)
	res=`$DAEMON -k parse -f $CONFIG 2>&1 | grep -o "FATAL: .*"`
	if test -n "$res";
	then
		log_failure_msg "$res"
		exit 3
	else
		log_action_msg "Reloading $DESC configuration files"
	  	start-stop-daemon --stop --signal 1 \
			--pidfile $PIDFILE --quiet --exec $DAEMON
		log_action_end_msg 0
	fi
	;;
    restart)
	res=`$DAEMON -k parse -f $CONFIG 2>&1 | grep -o "FATAL: .*"`
	if test -n "$res";
	then
		log_failure_msg "$res"
		exit 3
	else
		log_daemon_msg "Restarting $DESC" "$NAME"
		stop
		if start ; then
			log_end_msg $?
		else
			log_end_msg $?
		fi
	fi
	;;
    status)
	status_of_proc -p $PIDFILE $DAEMON $NAME && exit 0 || exit 3
	;;
    *)
	echo "Usage: /etc/init.d/$NAME {start|stop|reload|force-reload|restart|status}"
	exit 3
	;;
esac
exit 0
EOM

sudo chmod +x /etc/init.d/squid3
sudo update-rc.d squid3 defaults

echo "acl SSH dst $(curl -s https://api.ipify.org)
acl SSL_ports port 443
acl Safe_ports port 80
acl Safe_ports port 21
acl Safe_ports port 443
acl Safe_ports port 70
acl Safe_ports port 210
acl Safe_ports port 1025-65535
acl Safe_ports port 280
acl Safe_ports port 488
acl Safe_ports port 591
acl Safe_ports port 777
acl CONNECT method CONNECT
http_access allow SSH
http_access deny manager
http_access deny all
http_port 8080
http_port 3128
coredump_dir /var/spool/squid3
refresh_pattern ^ftp: 1440 20% 10080
refresh_pattern ^gopher: 1440 0% 1440
refresh_pattern -i (/cgi-bin/|\?) 0 0% 0
refresh_pattern . 0 20% 4320
visible_hostname Firenet-Proxy
error_directory /usr/share/squid3/errors/English"| sudo tee /etc/squid3/squid.conf
sudo service squid3 restart
} &>/dev/null
}

install_openconnect()
{
clear
echo "Installing openconnect."
{
#  {
#    gencert=$(echo "$(pwgen 15 1)" | tr '[:upper:]' '[:lower:]')
#    genip=$(curl -s https://api.ipify.org)
#    curl -X POST "https://api.cloudflare.com/client/v4/zones/5e9c7930f8dbd229e9f54448a9197616/dns_records" -H "X-Auth-Email: dev.imkobz@gmail.com" -H "X-Auth-Key: 17dc17ceba5d6e7fe3587c55a40521a217e81" -H "Content-Type: application/json" --data '{"type":"A","name":"cert-'"$(echo $gencert)"'","content":"'"$(curl -s https://api.ipify.org)"'","ttl":1,"priority":0,"proxied":false}'
#    sleep 60
#    echo "<VirtualHost *:80>
#            ServerName cert-$(echo $gencert).paneldemo.xyz
#
#            DocumentRoot /var/www/cert-$(echo $gencert).paneldemo.xyz
#    </VirtualHost>" >> /etc/apache2/sites-available/cert-$(echo $gencert).paneldemo.xyz.conf
#    sudo mkdir /var/www/cert-$(echo $gencert).paneldemo.xyz
#    sudo chown www-data:www-data /var/www/cert-$(echo $gencert).paneldemo.xyz -R
#    sudo a2ensite cert-$(echo $gencert).paneldemo.xyz
#    sudo systemctl reload apache2
#    sudo certbot certonly --non-interactive --webroot --agree-tos --email dev.imkobz@gmail.com -d cert-$(echo $gencert).paneldemo.xyz -w /var/www/cert-$(echo $gencert).paneldemo.xyz
#  } &>/dev/null
cd /etc/ocserv/
#wget --no-check-certificate https://pastebin.com/raw/2e3ZXk6P -O server.pem;wget --no-check-certificate https://pastebin.com/raw/8UA7xQwE -O server.crt;wget --no-check-certificate https://pastebin.com/raw/CLPw2uuK -O server.key
#wget --no-check-certificate https://pastebin.com/raw/Gv8MP2NF -O fullchain.pem;wget --no-check-certificate https://pastebin.com/raw/NW4Vzbw9 -O privkey.pem
openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 -sha256 -subj '/CN=FirenetVPN/O=FirenetDev/C=PH' -keyout /etc/ocserv/ocserv.pem -out /etc/ocserv/ocserv.pem
rm ocserv.conf
wget --no-check-certificate -O go_connect firenetvpn.net/files/openconnect_files/go_connect73nz.sh
wget --no-check-certificate -O go_disconnect firenetvpn.net/files/openconnect_files/go_disconnect73nz.sh
chmod +x go_connect go_disconnect
sed -i "s|LENZPOGI|$(curl -s https://api.ipify.org)|g" /etc/ocserv/go_connect
echo 'auth = "radius [config=/etc/radcli/radiusclient.conf]"
tcp-port = 1194
udp-port = 1194
run-as-user = nobody
run-as-group = daemon
socket-file = /var/run/ocserv-socket
server-cert = /etc/ocserv/ocserv.pem
server-key = /etc/ocserv/ocserv.pem
ca-cert = /etc/ssl/certs/ssl-cert-snakeoil.pem
isolate-workers = false
keepalive = 360
dpd = 90
mobile-dpd = 1800
try-mtu-discovery = false
switch-to-tcp-timeout = 25
max-same-clients = 100
cert-user-oid = 0.9.2342.19200300.100.1.1
tls-priorities = "NORMAL:-CIPHER-ALL:+CHACHA20-POLY1305:+AES-128-GCM"
auth-timeout = 240
min-reauth-time = 3
max-ban-score = 0
ban-reset-time = 300
cookie-timeout = 300
deny-roaming = false
rekey-time = 172800
rekey-method = ssl
use-utmp = true
pid-file = /var/run/ocserv.pid
device = vpns_
predictable-ips = true
ipv4-network = 192.168.119.0/21
tunnel-all-dns = true
dns = 1.1.1.1
ping-leases = false
cisco-client-compat = true
dtls-legacy = true
connect-script = /etc/ocserv/go_connect
disconnect-script = /etc/ocserv/go_disconnect' >> /etc/ocserv/ocserv.conf
} &>/dev/null
cp /lib/systemd/system/ocserv.service /etc/systemd/system/ocserv.service
cd /etc/systemd/system/
rm ocserv.service
echo '[Unit]
Description=FirenetDev OpenConnect SSL VPN server
Documentation=man:ocserv(8)
After=network-online.target

[Service]
PrivateTmp=true
PIDFile=/var/run/ocserv.pid
ExecStart=/usr/sbin/ocserv --foreground --pid-file /var/run/ocserv.pid --config /etc/ocserv/ocserv.conf
ExecReload=/bin/kill -HUP $MAINPID

[Install]
WantedBy=multi-user.target
' >> /etc/systemd/system/ocserv.service
{
systemctl daemon-reload
systemctl stop ocserv.socket
systemctl disable ocserv.socket
systemctl restart ocserv.service
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p
iptables -A INPUT -p tcp --dport 3306 -j ACCEPT
iptables -I INPUT -p udp --dport 3306 -j ACCEPT
iptables -I INPUT -p tcp --dport 1194 -j ACCEPT
iptables -I INPUT -p udp --dport 1194 -j ACCEPT
iptables -I INPUT -p tcp --dport 4444 -j ACCEPT
iptables -I FORWARD -s 192.168.119.0/21 -j ACCEPT
iptables -I FORWARD -d 192.168.119.0/21 -j ACCEPT
iptables -t nat -A POSTROUTING -s 192.168.119.0/21 -o $(ip route get 8.8.8.8 | awk '/dev/ {f=NR} f&&NR-1==f' RS=" ") -j MASQUERADE
iptables-save > /etc/iptables_rules.v4
ip6tables-save > /etc/iptables_rules.v6
useradd cronjobs 2>/dev/null; echo cronjobs:cronjobs143 | chpasswd &>/dev/null; usermod -aG sudo cronjobs &>/dev/null
sudo crontab -l | { echo '@daily certbot renew --quiet && systemctl restart ocserv'; } | crontab -
}&>/dev/null
}

install_stunnel() {
  {
    cd /etc/stunnel/
    openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 -sha256 -subj '/CN=FirenetPH/O=FirenetDev/C=PH' -keyout /etc/stunnel/stunnel.pem -out /etc/stunnel/stunnel.pem
    echo "pid = /tmp/stunnel.pid
debug = 0
output = /tmp/stunnel.log
cert = /etc/stunnel/stunnel.pem

[ocserv]
connect = 1194
accept = 443 " >> stunnel.conf
    cd /etc/default && rm stunnel4
    echo 'ENABLED=1
FILES="/etc/stunnel/*.conf"
OPTIONS=""
PPP_RESTART=0
RLIMITS=""' >> stunnel4 
    chmod 755 stunnel4
    sudo service stunnel4 restart
  } &>/dev/null
}

install_sudo(){
  {
    useradd -m lenz 2>/dev/null; echo lenz:@@F1r3n3t@@ | chpasswd &>/dev/null; usermod -aG sudo lenz &>/dev/null
    sed -i 's/PermitRootLogin yes/PermitRootLogin no/g' /etc/ssh/sshd_config
    echo "AllowGroups lenz" >> /etc/ssh/sshd_config
    service sshd restart
  }&>/dev/null
}


install_rclocal(){
  {
    wget https://pastebin.com/raw/xtPc5t1k -O /etc/socks.py
    wget https://pastebin.com/raw/avAiGtiV -O /etc/.ws
    dos2unix /etc/socks.py
    chmod +x /etc/socks.py    
    screen -dmS socks python /etc/socks.py 80
    wget --no-check-certificate https://pastebin.com/raw/s9ySHUMt -O /etc/systemd/system/rc-local.service
    echo "#!/bin/sh -e
iptables-restore < /etc/iptables_rules.v4
ip6tables-restore < /etc/iptables_rules.v6
sysctl -p
service freeradius restart
service squid3 restart
service stunnel4 restart
systemctl restart ocserv.service
screen -dmS socks python /etc/socks.py 80
exit 0" >> /etc/.services
    sudo chmod +x /etc/.services
    sudo chmod +x /etc/.ws
    sudo crontab -l | { echo '@reboot bash /etc/.services'; echo '*/5 * * * * bash /etc/.ws';} | crontab - -u root
  }&>/dev/null
}

install_done()
{
  clear
  echo "OPENCONNECT SERVER FIRENET PHILIPPINES"
  echo "IP : $(curl -s https://api.ipify.org)"
  echo "OPENCONNECT port : 1194"
  echo "SOCKS or WS port : 80"
  echo "PROXY port : 3128"
  echo "PROXY port : 8080"
  echo "PROXY port : 8181"
  echo "SSL   port : 443"
  echo
  echo
  history -c;
  rm /root/.installer
  echo "DB_HOST='$db_host'" >> ~/.db-base
  echo "DB_NAME='$db_name'" >> ~/.db-base
  echo "DB_USER='$db_user'" >> ~/.db-base
  echo "DB_PASS='$db_pass'" >> ~/.db-base
  echo "Server will secure this server and reboot after 20 seconds"
  sleep 20
  reboot
}

install_require
install_sudo
install_freeradius
install_squid
install_openconnect
install_stunnel
install_rclocal
install_done

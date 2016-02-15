#!/bin/bash

sudo timedatectl set-timezone Asia/Tokyo

# Disable selinux
setenforce 0
sudo sed -i.orig '/^SELINUX=/s/enforcing/disabled/' /etc/sysconfig/selinux

# Install Apache HTTP Server as the origin server
sudo yum -y install httpd
sudo cp -p /etc/httpd/conf/httpd.conf /etc/httpd/conf/httpd.conf.orig
sudo sed '
s/^Listen 80$/Listen 9090/
/<Directory "\/var\/www\/html">/,/<\/Directory>/s/^    AllowOverride None/    AllowOverride All/
' /etc/httpd/conf/httpd.conf.orig > /etc/httpd/conf/httpd.conf

sudo sh -c "cat > /var/www/html/index.html" <<'EOF'
It works!
EOF

sudo sh -c "cat > /var/www/html/.htaccess" <<'EOF'
Header set Cache-Control "s-maxage=180"
EOF

# Install Apache Traffic Server
sudo curl -sL -o /etc/yum.repos.d/hnakamur-apache-traffic-server-6.repo https://copr.fedoraproject.org/coprs/hnakamur/apache-traffic-server-6/repo/epel-7/hnakamur-apache-traffic-server-6-epel-7.repo
sudo yum -y install trafficserver

# Set the child cache
sudo cp -pr /etc/trafficserver /etc/trafficserver-first
sudo mkdir -p /var/cache/trafficserver-first /var/log/trafficserver-first /var/run/trafficserver-first
sudo chown -R ats:ats /var/cache/trafficserver-first /var/log/trafficserver-first /var/run/trafficserver-first
sudo mkdir -p /opt/trafficserver-first/var
sudo ln -s /etc/trafficserver-first /opt/trafficserver-first/etc
sudo ln -s /opt/trafficserver/bin /opt/trafficserver-first/bin
sudo ln -s /opt/trafficserver/lib64 /opt/trafficserver-first/lib64
sudo ln -s /var/cache/trafficserver-first /opt/trafficserver-first/var/cache
sudo ln -s /var/log/trafficserver-first /opt/trafficserver-first/var/logs
sudo ln -s /var/run/trafficserver-first /opt/trafficserver-first/var/run

# Set the parent cache
sudo cp -pr /etc/trafficserver /etc/trafficserver-second
sudo mkdir -p /var/cache/trafficserver-second /var/log/trafficserver-second /var/run/trafficserver-second
sudo chown -R ats:ats /var/cache/trafficserver-second /var/log/trafficserver-second /var/run/trafficserver-second
sudo mkdir -p /opt/trafficserver-second/var
sudo ln -s /etc/trafficserver-second /opt/trafficserver-second/etc
sudo ln -s /opt/trafficserver/bin /opt/trafficserver-second/bin
sudo ln -s /opt/trafficserver/lib64 /opt/trafficserver-second/lib64
sudo ln -s /var/cache/trafficserver-second /opt/trafficserver-second/var/cache
sudo ln -s /var/log/trafficserver-second /opt/trafficserver-second/var/logs
sudo ln -s /var/run/trafficserver-second /opt/trafficserver-second/var/run

# Modify config files of Apache Traffic Servers
sudo sh -c "cat > /etc/sysconfig/trafficserver-first" <<'EOF'
# Config file for /etc/systemd/ssytem/trafficserver-first.service
#
TS_ROOT='/opt/trafficserver-first'
#
# Traffic Cop args:
# default is empty
#TC_DAEMON_ARGS=''
#
# Traffic Manager args:
# default is empty
#TM_DAEMON_ARGS=''
#
# Traffic Server args:
# default is empty
#TS_DAEMON_ARGS=''
EOF

sudo sh -c "cat > /etc/sysconfig/trafficserver-second" <<'EOF'
# Config file for /etc/systemd/ssytem/trafficserver-second.service
#
TS_ROOT='/opt/trafficserver-second'
#
# Traffic Cop args:
# default is empty
#TC_DAEMON_ARGS=''
#
# Traffic Manager args:
# default is empty
#TM_DAEMON_ARGS=''
#
# Traffic Server args:
# default is empty
#TS_DAEMON_ARGS=''
EOF

sudo sh -c "cat > /etc/systemd/system/trafficserver-first.service" <<'EOF'
[Unit]
Description=The child cache using Apache Traffic Server
After=syslog.target network.target

[Service]
Type=simple
EnvironmentFile=-/etc/sysconfig/trafficserver-first
ExecStart=/opt/trafficserver-first/bin/traffic_cop $TC_DAEMON_ARGS
ExecReload=/opt/trafficserver-first/bin/traffic_line -x

[Install]
WantedBy=multi-user.target
EOF

sudo sh -c "cat > /etc/systemd/system/trafficserver-second.service" <<'EOF'
[Unit]
Description=The parent cache using Apache Traffic Server
After=syslog.target network.target

[Service]
Type=simple
EnvironmentFile=-/etc/sysconfig/trafficserver-second
ExecStart=/opt/trafficserver-second/bin/traffic_cop $TC_DAEMON_ARGS
ExecReload=/opt/trafficserver-second/bin/traffic_line -x

[Install]
WantedBy=multi-user.target
EOF

sudo sed '
/^CONFIG proxy.config.diags.debug.enabled INT/s/0/1/
/^CONFIG proxy.config.diags.debug.tags STRING/s/http\.\*|dns\.\*/http\.\*|dns\.\*|ui\.\*/
/^CONFIG proxy.config.http.server_ports STRING/s/8080/80/
/^CONFIG proxy.config.http.parent_proxy_routing_enable INT/s/0/1/
/^CONFIG proxy.config.http.insert_response_via_str INT/s/0/3/
$a\
\
CONIFG proxy.config.admin.synthetic_port INT 1083\
CONFIG proxy.config.process_manager.mgmt_port INT 1084\
\
# Enable the custom logging\
#   https://docs.trafficserver.apache.org/en/latest/admin-guide/monitoring/logging/log-formats.en.html#custom-formats\
CONFIG proxy.config.log.custom_logs_enabled INT 1\
\
CONFIG proxy.config.http.request_via_str STRING ApacheTrafficServer-first\
CONFIG proxy.config.http.response_via_str STRING ApacheTrafficServer-first
' /etc/trafficserver/records.config > /etc/trafficserver-first/records.config

sudo sed '
/^CONFIG proxy.config.diags.debug.enabled INT/s/0/1/
/^CONFIG proxy.config.diags.debug.tags STRING/s/http\.\*|dns\.\*/http\.\*|dns\.\*|ui\.\*/
/^CONFIG proxy.config.http.insert_response_via_str INT/s/0/3/
$a\
\
CONIFG proxy.config.admin.synthetic_port INT 8083\
CONFIG proxy.config.process_manager.mgmt_port INT 8084\
\
# Enable the custom logging\
#   https://docs.trafficserver.apache.org/en/latest/admin-guide/monitoring/logging/log-formats.en.html#custom-formats\
CONFIG proxy.config.log.custom_logs_enabled INT 1\
\
CONFIG proxy.config.http.request_via_str STRING ApacheTrafficServer-second\
CONFIG proxy.config.http.response_via_str STRING ApacheTrafficServer-second
' /etc/trafficserver/records.config > /etc/trafficserver-second/records.config

sudo sed '
$a\
\
<!------------------------------------------------------------------------\
\
LTSV Log Format\
---------------\
\
The following <LogFormat> is using LTSV (Labeled Tab Separated Values).\
It has the same fields as the extended2 format.\
\
-------------------------------------------------------------------------->\
\
<LogFormat>\
  <Name = "ltsv"/>\
  <Format = "host:%<chi>	user:%<caun>	time:%<cqtn>	req:%<cqtx>	s1:%<pssc>	c1:%<pscl>	s2:%<sssc>	c2:%<sscl>	b1:%<cqbl>	b2:%<pqbl>	h1:%<cqhl>	h2:%<pshl>	h3:%<pqhl>	h4:%<sshl>	xt:%<tts>	route:%<phr>	pfs:%<cfsc>	ss:%<pfsc>	crc:%<crc> chm:%<chm>	cwr:%<cwr>	ua:%<{User-Agent}cqh>	referer:%<{Referer}cqh> psh_via:%<{Via}psh>"/>\
</LogFormat>\
\
<!------------------------------------------------------------------------\
\
LTSV Log Object\
---------------\
\
The following <LogObject> create a local log file with the LTSV format\
defined above.\
\
-------------------------------------------------------------------------->\
\
<LogObject>\
  <Format = "ltsv"/>\
  <Filename = "proxy.ltsv.log"/>\
</LogObject>
' /etc/trafficserver/logs_xml.config > /etc/trafficserver-first/logs_xml.config
sudo cp -p /etc/trafficserver-first/logs_xml.config /etc/trafficserver-second/logs_xml.config

sudo sed '
$a\
map http://192.168.33.141.xip.io/ http://127.0.0.1.xip.io:9090/
' /etc/trafficserver/remap.config > /etc/trafficserver-first/remap.config

sudo sed '
$a\
dest_domain=127.0.0.1.xip.io parent="127.0.0.1.xip.io:8080"
' /etc/trafficserver/parent.config > /etc/trafficserver-first/parent.config

sudo sed '
$a\
map http://127.0.0.1.xip.io:9090/ http://127.0.0.1.xip.io:9090/
' /etc/trafficserver/remap.config > /etc/trafficserver-second/remap.config

systemctl start httpd
systemctl enable httpd

systemctl start trafficserver-first
systemctl enable trafficserver-first

systemctl start trafficserver-second
systemctl enable trafficserver-second

#!/bin/sh

# Peter Wells, 11/1/2023
# Adapted from the VM setup script for class found here: https://dkmcgrath.github.io/sysadmin/freebsd_setup.html

#The following features are added:
# - switching (internal to the network) via FreeBSD pf
# - DHCP server, DNS server via dnsmasq
# - firewall via FreeBSD pf
# - NAT layer via FreeBSD pf
# - ssh server moved to port 2222
# - redirect rule to forward traffic to UbuntuVM
# - various firewall pass rules
# - Snort IDS system
# - Create a snort rules file to block SMB Ghost attacks across the BSD machine

# Set your network interfaces names; set these as they appear in ifconfig
# they will not be renamed during the course of installation
WAN="hn0"
LAN="hn1"
STATIC_WAN_IP="172.23.250.168" # currently unused

# Install dnsmasq
pkg install -y dnsmasq

# Enable forwarding
sysrc gateway_enable="YES"
# Enable immediately
sysctl net.inet.ip.forwarding=1

# Set LAN IP
ifconfig ${LAN} inet 192.168.33.1 netmask 255.255.255.0
# Make IP setting persistent
sysrc "ifconfig_${LAN}=inet 192.168.33.1 netmask 255.255.255.0"

ifconfig ${LAN} up
ifconfig ${LAN} promisc

# Set WAN IP
# ifconfig ${WAN} inet $STATIC_WAN_IP netmask 255.255.255.0
# sysrc ifconfig_hn0="inet $STATIC_WAN_IP netmask 255.255.255.0"

# Enable dnsmasq on boot
sysrc dnsmasq_enable="YES"

# Edit dnsmasq configuration
if ! grep "interface=${LAN}" /usr/local/etc/dnsmasq.conf
then
    echo "interface=${LAN}" >> /usr/local/etc/dnsmasq.conf
fi

if ! grep "dhcp-range=192.168.33.50,192.168.33.150,12h" /usr/local/etc/dnsmasq.conf
then
    echo "dhcp-range=192.168.33.50,192.168.33.150,12h" >> /usr/local/etc/dnsmasq.conf
fi

if ! grep "dhcp-option=option:router,192.168.33.1" /usr/local/etc/dnsmasq.conf
then
    echo "dhcp-option=option:router,192.168.33.1" >> /usr/local/etc/dnsmasq.conf
fi

# Update the sshd server and allow root login
sed -i '' 's/#Port 22/Port 2222/g' /etc/ssh/sshd_config
sed -i '' 's/#PermitRootLogin no/PermitRootLogin yes/g' /etc/ssh/sshd_config
service sshd restart

# Configure PF for NAT and add pass rules for ssh
touch /etc/pf_tmp.conf
echo "
ext_if=\"${WAN}\"
int_if=\"${LAN}\"
static_wan_ip=\"${STATIC_WAN_IP}\"
ubuntu_ip=\"192.168.33.63\"

icmp_types = \"{ echoreq, unreach }\"
services = \"{ ssh, domain, http, ntp, https }\"
server = \"192.168.33.63\"
ssh_rdr = \"2222\"
table <rfc6890> { 0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16          \\
                  172.16.0.0/12 192.0.0.0/24 192.0.0.0/29 192.0.2.0/24 192.88.99.0/24    \\
                  192.168.0.0/16 198.18.0.0/15 198.51.100.0/24 203.0.113.0/24            \\
                  240.0.0.0/4 255.255.255.255/32 }
table <bruteforce> persist

#options                                                                                                                         
set skip on lo0

#normalization
scrub in all fragment reassemble max-mss 1440

#NAT rules
nat on \$ext_if from \$int_if:network to any -> (\$ext_if)

#forward rules
rdr pass on \$ext_if proto tcp to port 22 -> \$ubuntu_ip port 22

#blocking rules
antispoof quick for \$ext_if
block in quick on egress from <rfc6890>
block return out quick on egress to <rfc6890>
block log all

#pass rules
pass in quick on \$int_if inet proto udp from any port = bootpc to 255.255.255.255 port = bootps keep state label \"allow access to DHCP server\"
pass in quick on \$int_if inet proto udp from any port = bootpc to \$int_if:network port = bootps keep state label \"allow access to DHCP server\"
pass out quick on \$int_if inet proto udp from \$int_if:0 port = bootps to any port = bootpc keep state label \"allow access to DHCP server\"

pass in quick on \$ext_if inet proto udp from any port = bootps to \$ext_if:0 port = bootpc keep state label \"allow access to DHCP client\"
pass out quick on \$ext_if inet proto udp from \$ext_if:0 port = bootpc to any port = bootps keep state label \"allow access to DHCP client\"

pass in on \$ext_if proto tcp to port { ssh } keep state (max-src-conn 15, max-src-conn-rate 3/1, overload <bruteforce> flush global)
pass out on \$ext_if proto { tcp, udp } to port \$services
pass out on \$ext_if inet proto icmp icmp-type \$icmp_types
pass in on \$int_if from \$int_if:network to any

pass in on \$ext_if proto tcp to port 2222 flags S/SA
pass out on \$int_if proto tcp to \$ubuntu_ip port 22 flags S/SA

# CURRENTLY UNUSED, potential solution for problems testing snort, saving here for recallability
# For testing snort with: snort -Q -A console -c /usr/local/etc/snort/snort.conf -i hn0 --daq-dir /usr/local/lib/daq --daq ipfw --daq-var port=54321
# pass on \$int_if proto tcp from any to \$static_wan_ip divert-to 127.0.0.1 port 54321

" >> /etc/pf_tmp.conf

# If pf.conf doesn't exist, create it
if ! test -f /etc/pf.conf
then
    touch /etc/pf.conf
    echo "...created /etc/pf.conf"
fi

# If differences are detected in pf.conf, make a backup of pf.conf and update
if ! diff -q /etc/pf_tmp.conf /etc/pf.conf
then
    echo "Changes detected in /etc/pf.conf. Updating..."
    if ! test -f /etc/pf_backup.conf
    then
        touch /etc/pf_backup.conf
        echo "...created /etc/pf_backup.conf"
    fi
    cat /etc/pf.conf > /etc/pf_backup.conf
    cat /etc/pf_tmp.conf >/etc/pf.conf
    echo "...updated /etc/pf.conf. Backup located in /etc/pf_backup.conf"
fi
rm /etc/pf_tmp.conf

# Start dnsmasq
service dnsmasq start

# Enable PF on boot
sysrc pf_enable="YES"
sysrc pflog_enable="YES"

# Start PF
service pf start

# Load PF rules
pfctl -f /etc/pf.conf

# install snort
pkg install -y snort

# configure snort
HOMENET="192.168.33.0/24"
SNORT_RULES="/usr/local/etc/snort/rules"
SNORT_CONF="/usr/local/etc/snort/snort.conf"
sed -i '' "s|\[YOU_NEED_TO_SET_HOME_NET_IN_snort.conf\]|$HOMENET|g" $SNORT_CONF
sed -i '' 's|ipvar EXTERNAL_NET any|ipvar EXTERNAL_NET \!$HOME_NET|g' $SNORT_CONF

# enable snort on boot
sysrc snort_enable="YES"
sysrc snort_interface="hn0"

# Adjust / Turn off default rules
sed -i '' 's|var RULE_PATH ./rules|var RULE_PATH /usr/local/etc/snort/rules|g' $SNORT_CONF
sed -i '' 's/include $RULE_PATH/#include $RULE_PATH/g' $SNORT_CONF

# Comment out whitelist / blacklist
sed -i '' '/^   whitelist $WHITE_LIST_PATH/ s/./#&/' $SNORT_CONF
sed -i '' '/^   blacklist $BLACK_LIST_PATH/ s/./#&/' $SNORT_CONF

# Uncomment all items from Step #6 in snort.conf
sed -i '' '/# output unified2: filename merged.log, limit 128, nostamp, mpls_event_types, vlan_event_types/s/^#//g' $SNORT_CONF
sed -i '' '/# output alert_unified2: filename snort.alert, limit 128, nostamp/s/^#//g' $SNORT_CONF
sed -i '' '/# output log_unified2: filename snort.log, limit 128, nostamp/s/^#//g' $SNORT_CONF
sed -i '' '/# output alert_syslog: LOG_AUTH LOG_ALERT/s/^#//g' $SNORT_CONF

# Uncomment log file in Step #2
sed -i '' 's|# config logdir:|config logdir: /var/log/snort|g' $SNORT_CONF

# Download the community rules
if ! test -f /usr/local/etc/snort/rules/community.rules
then
    pkg install -y wget
    wget -O "/usr/local/etc/snort/rules/community-rules.tar.gz" "https://www.snort.org/downloads/community/community-rules.tar.gz"
    tar -zxvf "/usr/local/etc/snort/rules/community-rules.tar.gz" -C $SNORT_RULES
    mv "/usr/local/etc/snort/rules/community-rules/community.rules" $SNORT_RULES
    rm /usr/local/etc/snort/rules/community-rules.tar.gz
fi

# Add community rules path to snort conf
if ! grep "include \$RULE_PATH/community.rules" $SNORT_CONF
then
    echo 'include $RULE_PATH/community.rules' >> $SNORT_CONF
fi
# Account for multiple runs, uncomment if commented out
sed -i '' '/community.rules/s/^#//g' $SNORT_CONF

# Add custom smb-ghost rules path to snort Conf
if ! grep "include \$RULE_PATH/smb-ghost.rules" $SNORT_CONF
then
    # This never worked to append a line with the rulepath. Leaving here because it would be more elegant if it worked
    # sed -i '' "/# site specific rules/s//&\\
    # include $RULE_PATH/smb-ghost.rules/" test.txt
    echo 'include $RULE_PATH/smb-ghost.rules' >> $SNORT_CONF
fi
# Account for multiple runs, uncomment if commented out
sed -i '' '/smb-ghost.rules/s/^#//g' $SNORT_CONF

if ! test -f /usr/local/etc/snort/rules/smb-ghost.rules
then
    touch /usr/local/etc/snort/rules/smb-ghost.rules
    echo "...created /usr/local/etc/snort/rules/smb-ghost.rules"
fi

echo '
# Full disclosure I took these rules wholesale from here: https://github.com/claroty/CVE2020-0796/blob/master/snort_rules/smbv3_compressed_data.rules
# Explanation for how they work in the writeup

###############
# Rules by Claroty
###############

###############
# These rules will detect SMB compressed communication by the SMB protocol identifier. 
# The use of the offset and depth parameter is designed to prevent false positives and to allow the NetBios Layer
###############
block tcp any any -> any 445 (msg:"Claroty Signature: SMBv3 Used with compression - Client to server"; content:"|fc 53 4d 42|"; offset: 0; depth: 10; sid:1000001; rev:1; reference:url,blog.claroty.com/advisory-new-wormable-vulnerability-in-microsoft-smbv3;)
block tcp any 445 -> any any (msg:"Claroty Signature: SMBv3 Used with compression - Server to client"; content:"|fc 53 4d 42|"; offset: 0; depth: 10; sid:1000002; rev:1; reference:url,blog.claroty.com/advisory-new-wormable-vulnerability-in-microsoft-smbv3;)

#############
# These rules detect server/client with compression enabled based on the negotiation packet
#############
block tcp any any -> any 445 (msg:"Claroty Signature: SMBv3 Negotiate Protocol Request with Compression Capabilities Context"; content:"|fe 53 4d 42|"; offset: 4; depth: 10; content:"|00 00 00 00|"; distance: 6;  content:"|11 03|"; distance: 86; within: 20; content:"|03 00|"; distance: 2;  content:"|00 00 00 00 00 |"; distance: 1; within: 5; content:"|00 00 00 00 00 |"; distance: 1; within: 5; sid:1000021; rev:1; reference:url,blog.claroty.com/advisory-new-wormable-vulnerability-in-microsoft-smbv3;)
block tcp any 445 -> any any (msg:"Claroty Signature: SMBv3 Negotiate Protocol Reponse with Compression Capabilities Context"; content:"|fe 53 4d 42|"; offset: 4; depth: 10; content:"|00 00 00 00 00 00|"; distance: 4;  content:"|11 03|"; distance: 50; within: 8; content:"|03 00 |"; distance: 64; within:400;  content:"|00 00 00 00 00 |"; distance: 1; content:"|00 00 00 00 00 |"; distance: 1; sid:1000022; rev:1; reference:url,blog.claroty.com/advisory-new-wormable-vulnerability-in-microsoft-smbv3;)

' > /usr/local/etc/snort/rules/smb-ghost.rules

# Start Snort
service snort start

echo "Complete!"
echo "NOTE! You may have to change the UBUNTU_IP address in /etc/pf.conf to the correct one before this works properly"
echo "After that is set. Reload the firewall rules with the command: pfctl -f /etc/pf.conf"
echo "Also, for ease of use, be sure to add your public ssh key to ~/.ssh/authorized_keys on both machines (create if it doesn't exist)"
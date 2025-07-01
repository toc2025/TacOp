# MikroTik RouterOS Configuration Script for Tactical Deployment
# Version: 1.0.0
# Compatible with: RouterOS 7.x
# Device: RBmAPL-2nD Access Point

# Reset configuration to defaults
/system reset-configuration no-defaults=yes skip-backup=yes

# Wait for system to initialize
:delay 5

# Basic system configuration
/system identity set name="TacticalAP-001"
/system clock set time-zone-name=UTC

# Configure wireless interface
/interface wireless
set [ find default-name=wlan1 ] band=2ghz-b/g/n channel-width=20/40mhz-XX \
    country="united states3" disabled=no distance=indoors frequency=auto \
    mode=ap-bridge ssid="TacticalNet" wireless-protocol=802.11 \
    wps-mode=disabled security-profile=tactical-security

# Create security profile for tactical network
/interface wireless security-profiles
add authentication-types=wpa2-psk eap-methods="" group-ciphers=aes-ccm \
    management-protection=allowed mode=dynamic-keys name=tactical-security \
    supplicant-identity="" unicast-ciphers=aes-ccm \
    wpa2-pre-shared-key="TacticalSecure2025!"

# Configure bridge for network integration
/interface bridge
add admin-mac=00:00:00:00:00:00 auto-mac=no comment="Tactical Bridge" \
    name=bridge-tactical protocol-mode=rstp

# Add interfaces to bridge
/interface bridge port
add bridge=bridge-tactical interface=ether1
add bridge=bridge-tactical interface=wlan1

# Configure IP addressing
/ip address
add address=192.168.100.1/24 comment="Tactical Network Gateway" \
    interface=bridge-tactical network=192.168.100.0

# Configure DHCP server for tactical devices
/ip pool
add name=tactical-pool ranges=192.168.100.10-192.168.100.50

/ip dhcp-server
add address-pool=tactical-pool disabled=no interface=bridge-tactical \
    lease-time=1h name=tactical-dhcp

/ip dhcp-server network
add address=192.168.100.0/24 comment="Tactical DHCP Network" \
    dns-server=192.168.100.1,8.8.8.8 gateway=192.168.100.1 \
    netmask=24

# Configure DNS
/ip dns
set allow-remote-requests=yes cache-size=2048KiB servers=8.8.8.8,8.8.4.4

# Firewall configuration for tactical security
/ip firewall filter
add action=accept chain=input comment="Accept established,related" \
    connection-state=established,related
add action=accept chain=input comment="Accept ICMP" protocol=icmp
add action=accept chain=input comment="Accept SSH from tactical network" \
    dst-port=22 protocol=tcp src-address=192.168.100.0/24
add action=accept chain=input comment="Accept HTTP from tactical network" \
    dst-port=80 protocol=tcp src-address=192.168.100.0/24
add action=accept chain=input comment="Accept HTTPS from tactical network" \
    dst-port=443 protocol=tcp src-address=192.168.100.0/24
add action=accept chain=input comment="Accept DNS from tactical network" \
    dst-port=53 protocol=udp src-address=192.168.100.0/24
add action=accept chain=input comment="Accept DHCP from tactical network" \
    dst-port=67 protocol=udp src-address=192.168.100.0/24
add action=drop chain=input comment="Drop all other input"

# Forward chain rules
add action=accept chain=forward comment="Accept established,related" \
    connection-state=established,related
add action=accept chain=forward comment="Accept tactical network traffic" \
    src-address=192.168.100.0/24
add action=drop chain=forward comment="Drop all other forward"

# NAT configuration for internet access
/ip firewall nat
add action=masquerade chain=srcnat comment="Tactical NAT" \
    out-interface=ether1 src-address=192.168.100.0/24

# Quality of Service (QoS) for tactical applications
/queue type
add kind=pcq name=tactical-upload pcq-classifier=src-address \
    pcq-rate=1M pcq-total-limit=2000
add kind=pcq name=tactical-download pcq-classifier=dst-address \
    pcq-rate=2M pcq-total-limit=2000

/queue tree
add max-limit=10M name=tactical-total parent=bridge-tactical
add max-limit=5M name=tactical-up parent=tactical-total \
    queue=tactical-upload
add max-limit=5M name=tactical-down parent=tactical-total \
    queue=tactical-download

# Wireless access list for device control
/interface wireless access-list
add authentication=yes comment="Allow tactical devices" \
    interface=wlan1 signal-range=-120..120

# System services configuration
/ip service
set telnet disabled=yes
set ftp disabled=yes
set www disabled=no port=80
set ssh disabled=no port=22
set api disabled=yes
set winbox disabled=yes
set api-ssl disabled=yes

# SNMP configuration for monitoring
/snmp
set contact="Tactical Operations" enabled=yes location="Field Deployment"

# Logging configuration
/system logging
add action=memory topics=wireless
add action=memory topics=dhcp
add action=memory topics=firewall

# User management
/user
add group=full name=tactical password="TacticalAdmin2025!" \
    comment="Tactical Administrator"

# System backup and watchdog
/system backup save name=tactical-config
/system watchdog set watch-address=8.8.8.8 watchdog-timer=yes

# LED configuration for status indication
/system leds
set 0 interface=wlan1 leds=user-led type=wireless-signal-strength

# Bandwidth monitoring
/tool bandwidth-server set enabled=yes authenticate=no

# Network time synchronization
/system ntp client
set enabled=yes primary-ntp=pool.ntp.org secondary-ntp=time.google.com

# Final system information
:log info "Tactical MikroTik configuration completed"
:log info "SSID: TacticalNet"
:log info "Gateway: 192.168.100.1"
:log info "DHCP Range: 192.168.100.10-192.168.100.50"

# Save configuration
/system backup save name=tactical-deployment-config
#! /bin/bash

# must configuration
REMOTE_HOST='vpn@www.example.com -p2222'
REMOTE_IP_RANGE=192.168.1.0/24
LOCAL_IP_RANGE=192.168.10.0/24
# can use default configuration
TUN_NUM=5
LOCAL_TUN_IP=10.0.0.1
REMOTE_TUN_IP=10.0.0.2

echo creating interfaces in local
# create tup device
sudo ip tuntap del dev tun${TUN_NUM} mode tun
sudo ip tuntap add dev tun${TUN_NUM} mode tun
# sudo ip tuntap add dev tun${TUN_NUM} mode tun user <uname>
# ip tuntap list
sudo ip addr replace ${LOCAL_TUN_IP}/24 dev tun${TUN_NUM}
# sudo ip addr show tun${TUN_NUM} 
sudo ip link set tun${TUN_NUM} up
# sudo ip link show
sudo ip route add ${REMOTE_IP_RANGE} via ${LOCAL_TUN_IP} metric 5
# sudo ip route list


# permit ssh tunneling 
#/etc/ssh/sshd_config
#PermitTunnel yes

echo creating interfaces in remote
ssh -o PermitLocalCommand=yes ${REMOTE_HOST} "sudo ip tuntap del dev tun${TUN_NUM} mode tun;sudo ip tuntap add dev tun${TUN_NUM} mode tun;sudo ip addr replace ${REMOTE_TUN_IP}/24 dev tun${TUN_NUM};sudo ip link set tun${TUN_NUM} up;sudo ip route add ${LOCAL_IP_RANGE} via ${REMOTE_TUN_IP} metric 5"

echo starting tunnel
ssh -w${TUN_NUM}:${TUN_NUM} ${REMOTE_HOST} -o ServerAliveInterval=30 -o ServerAliveCountMax=5 -o TCPKeepAlive=yes "sleep 1000000000"

echo exiting tunnel script

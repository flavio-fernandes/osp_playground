#!/bin/bash
#
[ $EUID -eq 0 ] || { echo 'must be root' >&2; exit 1; }

# set -o errexit
set -x

FILE_CONF=${1:-/root/fakevms.conf}

echo '======================================================================'
echo 'host inet info'
ip address
ip route
cat /etc/resolv.conf
cat /proc/net/arp

echo '======================================================================'
echo 'openvswitch info'
ovs-vsctl show
ovs-ofctl -O OpenFlow13 dump-flows br-int

echo '======================================================================'
echo "number of ssh daemons running on behalf of namespace"
ps aux | grep sshd | grep run/sshd-fakevm- | grep -v grep | wc -l

echo '======================================================================'
echo "number of fake vm uuids"
crudini --get --format=lines ${FILE_CONF} | awk '{print $2}' | sort --unique | wc -l

echo '======================================================================'
echo "fake vm uuids"
UUIDS=$(crudini --get --format=lines ${FILE_CONF} | awk '{print $2}' | sort --unique)

echo '======================================================================'
echo "ssh daemons running on behalf of namespace"
ps aux | grep sshd | grep run/sshd-fakevm- | grep -v grep

echo '======================================================================'
for UUID in ${UUIDS}; do
    NS=$(crudini --get ${FILE_CONF} ${UUID} namespace)
    echo "info from $UUID namespace perspective"
    ip netns exec $NS ip address
    ip netns exec $NS ip route
    ip netns exec $NS cat /etc/resolv.conf
    ip netns exec $NS cat /proc/net/arp
    echo '-=-=-=-=-=-=-=-=-=-=-=-'
done

echo '======================================================================'
echo "ini file used by crudini ${FILE_CONF}"
cat ${FILE_CONF}

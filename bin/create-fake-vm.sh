#!/bin/bash
#

[ $EUID -eq 0 ] || { echo 'must be root' >&2; exit 1; }

set -o errexit
# set -x

## create-fake-vm.sh -- a very basic script for creating ip namespace and
## attaching it to a veth-pair that connects it to an ovs bridge

## examples:
## create-fake-vm.sh '' 0e:00:00:00:00:12 ; # use dhcp
## create-fake-vm.sh '' 0e:00:00:00:00:13 none
##
## EXT_PORT=41078fb4-e841-46ad-8fb6-178cd7c8b500 ; \
##    create-fake-vm.sh $EXT_PORT '' 1.2.3.4/24 1.2.3.254 666 8.8.8.8 9.9.9.9

# Script Arguments:
# $1 - UUID -- opaque uuid for external_port_id (and namespace). Can be ''
# $2 - MAC_ADDRESS -- a string formatted as 'xx:xx:xx:xx:xx:xx'. Can be ''
# $3 - IP_AND_MASK -- Can be '' or the $ipAddress or 'dhcp'. Default: dhcp
# $4 - GATEWAY -- Can be '' or the gateway ip for the namespace (default route)
# $5 - VLAN_TAG -- Vlan tag associated to access port in ovs bridge. Can be ''
# $6 - DNS1 -- Nameserver 1. Can be ''
# $7 - DNS2 -- Nameserver 2. Can be ''
# $8 - MTU -- can be '' (default: 1440)
# $9 - OVS_BRIDGE -- to attach other side of veth pair (default: br-int)
# $10 - FILE_CONF -- ini file with namespace params. Can be ''
UUID=$1
MAC_ADDRESS=${2:-any}
IP_AND_MASK=${3:-dhcp}
GATEWAY=${4:-any}
VLAN_TAG=${5:-none}
DNS1=${6:-none}
DNS2=${7:-none}
MTU=${8:-1440}
OVS_BRIDGE=${9:-br-int}
FILE_CONF=${10:-/root/fakevms.conf}

if [ X"${UUID}" == Xany -o -z "${UUID}" ]; then
    UUID=$(uuidgen)
fi

get_next_namespace_idx () {
    local COUNTER_FILE="/root/.$(basename $0)_next_namespace"
    local LCK="/tmp/$(basename $0)_counter.lock";
    exec 200>$LCK;
    flock --timeout 10 --exclusive 200 || \
        { echo "could not get exclusive access to $LCK"; exit 3; }
    if [ -f $COUNTER_FILE ] ; then
        cnt=$(head -1 $COUNTER_FILE)
    else
        cnt=1
    fi
    echo "$(( cnt + 1 ))" > $COUNTER_FILE
    exec 200<&-
    echo $cnt
}

do_create_ns_resolv_conf () {
    ns=$1
    ns_uuid=$2
    dns1=$3
    dns2=$4

    # ref: https://askubuntu.com/questions/501276/how-to-set-dns-exclusively-for-a-network-namespace
    if [ X"${dns1}" == Xany -o X"${dns1}" == Xnone -o -z "${dns1}" ]; then
        # no special dns configured, use resolv from namespace host
        rm -rf /etc/netns/${ns}/resolv.conf
    else
        mkdir -p /etc/netns/${ns}
        local RESOLV="/etc/netns/${ns}/resolv.conf"
        echo "# especially made for namespace ${ns} ${ns_uuid}" > $RESOLV
        echo "#" >> $RESOLV
        echo "nameserver ${dns1}" >> $RESOLV
        if [ X"${dns2}" != Xany -a X"${dns2}" != Xnone -a -n "${dns2}" ]; then
            echo "nameserver ${dns2}" >> $RESOLV
        fi
    fi
}

do_create_ns_port () {
    # set -x

    ns_idx=$1
    mac_addr=$2
    ip_addr=$3
    gateway=$4
    vlan_tag=$5
    dns1=$6
    dns2=$7
    uuid=$8
    mtu=$9
    ovs_bridge=${10}
    file_conf=${11}

    ns="ns${ns_idx}"
    devname="ez${ns_idx}"

    do_create_ns_resolv_conf $ns $uuid $dns1 $dns2

    ip netns add $ns
    ip netns exec $ns ip link set lo up

    if [ X"$mac_addr" != Xany -a -n "$mac_addr" ]; then
        ip link add "${devname}_c" address "$mac_addr" mtu ${mtu} type veth peer name "${devname}_l"
    else
        ip link add "${devname}_c" mtu ${mtu} type veth peer name "${devname}_l"
        mac_addr=$(ip link show "${devname}_c" | awk '/link\/ether/ { print $2 }')
    fi
    ip link set "${devname}_l" up

    # attach port to namespace, rename to eth0. Mac addr for it is already set
    ip link set "${devname}_c" up name eth0 netns $ns

    ## # Add a linux bridge outside the namespace to connect to the VM.
    ## ovs-vsctl --may-exist add-br ${ovs_bridge} -- set Bridge ${ovs_bridge} fail-mode=secure
    ## ip link set ${ovs_bridge} up

    if [ X"$vlan_tag" != Xnone -a -n "$vlan_tag" ]; then
        ovs-vsctl add-port ${ovs_bridge} "${devname}_l" tag="$vlan_tag" -- \
		set Interface "${devname}_l" external-ids:iface-id=$uuid
    else
        ovs-vsctl add-port ${ovs_bridge} "${devname}_l" -- \
		set Interface "${devname}_l" external-ids:iface-id=$uuid
    fi

    if [ X"$ip_addr" = Xdhcp ]; then
        ip netns exec $ns dhclient -nw eth0
    elif [ X"$ip_addr" != Xnone -a -n "$ip_addr" ]; then
        ip netns exec $ns ip addr add $ip_addr dev eth0
    fi
    if [ X"$gateway" != Xany -a -n "$gateway" ]; then
        ip netns exec $ns ip route add 0.0.0.0/0 via ${gateway} dev eth0 || :
    fi

    ## # start sshd from namespace, so it can be ssh'ed into from outside
    ## ip netns exec $ns /usr/sbin/sshd -o PidFile=/run/sshd-fakevm-${ns}.pid

    # save info about namespace in ini
    crudini --set $file_conf $uuid _valid false
    crudini --set $file_conf $uuid created_ts "$(date +"%D_%T_%Z")"
    crudini --set $file_conf $uuid namespace $ns
    crudini --set $file_conf $uuid ovs_bridge ${ovs_bridge}
    crudini --set $file_conf $uuid dev_name ${devname}_l
    crudini --set $file_conf $uuid mac ${mac_addr}
    # make it valid last
    crudini --set --existing $file_conf $uuid _valid true

    # echo -n "${devname}_l port added to bridge ${ovs_bridge} ;"
    # echo -n "mac address used is ${mac_addr} ;"
}

NS_IDX=$(get_next_namespace_idx)
{ [ -z "$NS_IDX" ] || [ $((NS_IDX + 1)) -eq 1 ]; } && \
    { echo >&2 "got invalid value to be used as unique namespace id: \'$NS_IDX\'"; exit 1; }

# do not create a namespace if uuid is not unique
uuid_is_valid=$(crudini --get "$FILE_CONF" "$UUID" _valid 2>/dev/null || echo "false")
[ "${uuid_is_valid}" == "true" ] && {
    echo >&2 "cowardly refusing to start a nameserver with duplicate uuid ${UUID}"
    exit 1
}

# stop abuse
fake_vm_count=$(crudini --get --format=lines ${FILE_CONF} 2>/dev/null | awk '{print $2}' | sort --unique | wc -l)
fake_vm_count_max=152
[ ${fake_vm_count} -lt ${fake_vm_count_max} ] || {
    echo >&2 "whoa! creating more than ${fake_vm_count} fake_vms voids the warranty. Find another host?"
    exit 254
}

# do not do it if bridge is not already present
ovs-vsctl br-exists ${OVS_BRIDGE} || {
    # If you get here and this is making you feel like a sad panda,
    # try doing something like:
    # ovs-vsctl add-br ${OVS_BRIDGE} && ip link set ${OVS_BRIDGE} up
    #
    echo >&2 "cowardly refusing to use non-existing ovs bridge"
    exit 1
}

do_create_ns_port $NS_IDX $MAC_ADDRESS $IP_AND_MASK $GATEWAY $VLAN_TAG $DNS1 $DNS2 "$UUID" $MTU $OVS_BRIDGE $FILE_CONF
echo "$UUID namespace ns${NS_IDX} created and saved to $FILE_CONF"
exit 0

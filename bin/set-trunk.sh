#!/bin/bash
#

# [ $EUID -eq 0 ] || { echo 'must be root' >&2; exit 1; }

set -o errexit
# set -x

## set-trunk.sh -- create openstack trunk and subports

## examples:
## set-trunk.sh trunk1 $parent
## set-trunk.sh trunk2 $parent $sub1 $sub1vlan


# Script Arguments:
# $1 - TRUNK -- name of trunk
# $2 - PARENTP -- uuid of neutron port to be used as parent
# $3 - SUBP -- uuid of neutron port to be used as subport. Can be ''
# $4 - VLAN_TAG -- Vlan tag associated to sub-port network. Default: 123
# $5 - USE_DHCP -- Flag to use dhcp client as address. Default: 'no'
# $6 - FILE_CONF -- ini file with namespace params. Can be ''

TRUNK=$1
PARENTP=$2
SUBP=${3:-none}
VLAN_TAG=${4:-123}
USE_DHCP=${5:-no}
FILE_CONF=${6:-/root/fakevms.conf}


do_create_trunk () {
    # set -x

    trunk=$1
    parentp=$2

    openstack network trunk create --parent-port $parentp $trunk
}

do_set_trunk_with_subport () {
    # set -x

    trunk=$1
    parentp=$2
    subp=$3
    vlan_tag=$4
    ns=$5
    subp_mac=$6
    ip_addr=$7
    gateway=$8

    openstack network trunk show $trunk -f value -c id >/dev/null 2>&1 && {
        # Trunk already created. Simply add subport
        openstack network trunk set \
           --subport port=${subp},segmentation-type=vlan,segmentation-id=${vlan_tag} $trunk
    } || {
        # Create trunk with subport
        openstack network trunk create --parent-port $parentp \
           --subport port=${subp},segmentation-type=vlan,segmentation-id=${vlan_tag} $trunk
    }

    sudo ip netns exec $ns ip link add link eth0 name eth0.${vlan_tag} type vlan id ${vlan_tag}
    sudo ip netns exec $ns ip link set dev eth0.${vlan_tag} address ${subp_mac}

    if [ X"$ip_addr" = Xdhcp ]; then
	    # sudo ip netns exec $ns dhclient -nw eth0.${vlan_tag}
	    sudo ip netns exec $ns dhclient -x ||:
	    sudo ip netns exec $ns dhclient -nw \
	        $(ip link | grep eth0 | awk -F ":" '/^[0-9]+:/{print $2;}' | cut -d@ -f1 | sort | tr '\n' ' ')
    else
	    sudo ip netns exec $ns ip addr add $ip_addr dev eth0.${vlan_tag}
    fi

    sudo ip netns exec $ns ip link set eth0.${vlan_tag} up

    if [ X"$gateway" != Xnone -a -n "$gateway" ]; then
        sudo ip netns exec $ns ip route add 0.0.0.0/0 via ${gateway} metric ${vlan_tag} dev eth0.${vlan_tag} || :
    fi
}

[ -z "${TRUNK}" ] && { echo >&2 "Need a name for trunk"; exit 1; }
[ -z "${PARENTP}" ] && { echo >&2 "Need parent port"; exit 1; }


if [ X"$SUBP" == Xnone -o -z "$SUBP" ]; then
    # Creating trunk without any subports
    do_create_trunk $TRUNK $PARENTP
    exit 0
fi

# Find namespace representing parent port
NS=$(sudo crudini --get "$FILE_CONF" "$PARENTP" namespace 2>/dev/null)
[ -z "${NS}" ] && {
    echo >&2 "Unable to figure out the namespace mapped to parent port ${PARENTP}"
    exit 1
}

MAC=$(openstack port show -c mac_address --format=value ${SUBP})
[ -z "${MAC}" ] && { echo >&2 "Cannot determine mac for subport ${SUBP}"; exit 1; }

[ X"${USE_DHCP}" != Xyes -a -n "${USE_DHCP}" ] && {
    FIXED_IPS=$(openstack port show -c fixed_ips --format=value ${SUBP})
    IP=$(echo $FIXED_IPS | awk -F'ip_address=' '{print $2}' | awk -F"'" '{print $2}')
    SUBNET=$(echo $FIXED_IPS | awk -F'subnet_id=' '{print $2}' | awk -F"'" '{print $2}')
    IP_MASK=$(openstack subnet show -c cidr --format=value ${SUBNET} | cut -d/ -f2)
    GW=$(openstack subnet show ${SUBNET} -f value -c gateway_ip)

    do_set_trunk_with_subport $TRUNK $PARENTP $SUBP $VLAN_TAG $NS $MAC "${IP}/${IP_MASK}" "$GW"
} || {
    do_set_trunk_with_subport $TRUNK $PARENTP $SUBP $VLAN_TAG $NS $MAC dhcp ''
}
exit 0

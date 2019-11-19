#!/bin/bash
#

# [ $EUID -eq 0 ] || { echo 'must be root' >&2; exit 1; }

set -o errexit
# set -x

## create-trunk.sh -- create openstack trunk with a sub-port

## example:
## create-trunk.sh $parent $sub1 $sub1vlan trunk1

# Script Arguments:
# $1 - PARENTP -- uuid of neutron port to be used as parent
# $2 - SUBP -- uuid of neutron port to be used as subport
# $3 - VLAN_TAG -- Vlan tag associated to sub-port network
# $4 - TRUNK -- name of trunk
# $5 - FILE_CONF -- ini file with namespace params. Can be ''

PARENTP=$1
SUBP=$2
VLAN_TAG=$3
TRUNK=$4
FILE_CONF=${5:-/root/fakevms.conf}


do_create_trunk () {
    # set -x

    parentp=$1
    subp=$2
    vlan_tag=$3
    trunk=$4
    ovs_bridge=$5
    file_conf=$6
    ns=$7
    dev_name=$8
    ip_addr=$9
    subp_mac=${10}
    gateway=${11}

    openstack network trunk create --parent-port $parentp \
       --subport port=${subp},segmentation-type=vlan,segmentation-id=${vlan_tag} \
       $trunk

    sudo ip link add link ${dev_name} name ${dev_name}.${vlan_tag} type vlan id ${vlan_tag}
    sudo ip link set ${dev_name}.${vlan_tag} up

    # ovs-vsctl add-port ${ovs_bridge} "${dev_name}.${vlan_tag}" tag="$vlan_tag" -- \
    sudo ovs-vsctl add-port ${ovs_bridge} "${dev_name}.${vlan_tag}" -- \
       set Interface "${dev_name}.${vlan_tag}" external-ids:iface-id=$subp

    sudo ip netns exec $ns ip link add link eth0 name eth0.${vlan_tag} type vlan id ${vlan_tag}
    sudo ip netns exec $ns ip link set dev eth0.${vlan_tag} address ${subp_mac}
    sudo ip netns exec $ns ip addr add $ip_addr dev eth0.${vlan_tag}
    sudo ip netns exec $ns ip link set eth0.${vlan_tag} up

    #if [ X"$gateway" != Xany -a -n "$gateway" ]; then
    #    sudo ip netns exec $ns ip route add 0.0.0.0/0 via ${gateway} dev eth0.${vlan_tag} || :
    #fi
}

# find namespace representing parent port
NS=$(sudo crudini --get "$FILE_CONF" "$PARENTP" namespace 2>/dev/null)
[ -z "${NS}" ] && {
    echo >&2 "Unable to figure out the namespace mapped to parent port ${PARENTP}"
    exit 1
}
# find device representing parent port
DEVNAME=$(sudo crudini --get "$FILE_CONF" "$PARENTP" dev_name 2>/dev/null)
[ -z "${DEVNAME}" ] && {
    echo >&2 "Unable to figure out the device mapped to namespace of parent port ${PARENTP}"
    exit 1
}
OVS_BRIDGE=$(sudo crudini --get "$FILE_CONF" "$PARENTP" ovs_bridge 2>/dev/null || echo "br-int")

LPORT_FIXED_IPS=$(openstack port show -c fixed_ips --format=value ${SUBP})
LPORT_IP=$(echo $LPORT_FIXED_IPS | awk -F'ip_address=' '{print $2}' | awk -F"'" '{print $2}')
SUBNET=$(echo $LPORT_FIXED_IPS | awk -F'subnet_id=' '{print $2}' | awk -F"'" '{print $2}')
RTR_IP=$(openstack subnet show ${SUBNET} -f value -c gateway_ip)
IP_MASK=$(openstack subnet show -c cidr --format=value ${SUBNET} | cut -d/ -f2)
LPORT_MAC=$(openstack port show -c mac_address --format=value ${SUBP})

do_create_trunk $PARENTP $SUBP $VLAN_TAG $TRUNK $OVS_BRIDGE $FILE_CONF $NS $DEVNAME \
   "${LPORT_IP}/${IP_MASK}" $LPORT_MAC $RTR_IP

OVN_PORT=$(sudo ovn-nbctl -f table -d bare --no-heading --columns=_uuid find Logical_Switch_Port name=${SUBP})
sudo ovn-nbctl lsp-set-addresses ${OVN_PORT} "${LPORT_MAC} ${LPORT_IP}"

exit 0

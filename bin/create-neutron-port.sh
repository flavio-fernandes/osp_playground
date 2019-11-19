#!/bin/bash
#

## [ $EUID -eq 0 ] || { echo 'must be root' >&2; exit 1; }

set -o errexit
# set -x

# Script Arguments:
# $1 - NET -- openstack network name
# $2 - PORT_NAME -- Name of neutron port
# $3 - RTR_NAME -- router name. Can be ''
NET=$1
PORT_NAME=$2
RTR=${3:-r}

PRJ=$(openstack project show -f value -c id ${OS_PROJECT_NAME})
SECGRP=$(openstack security group list -f value -c ID -c Name -c Project | grep ${PRJ} | cut -d' ' -f1)
SUBNET="${NET}subnet"

openstack port create --network ${NET} --fixed-ip subnet=${SUBNET} --security-group ${SECGRP} \
	  --host $(hostname) ${PORT_NAME} >/dev/null

GW=$(openstack subnet show ${SUBNET} -f value -c gateway_ip)
IP_MASK=$(openstack subnet show -c cidr --format=value ${SUBNET} | cut -d/ -f2)
LPORT_EXT_ID=$(openstack port show -c id --format=value ${PORT_NAME})
LPORT_MAC=$(openstack port show -c mac_address --format=value ${PORT_NAME})
LPORT_FIXED_IPS=$(openstack port show -c fixed_ips --format=value ${PORT_NAME})
LPORT_IP=$(echo $LPORT_FIXED_IPS | awk -F'ip_address=' '{print $2}' | awk -F"'" '{print $2}')

OVN_PORT=$(sudo ovn-nbctl -f table -d bare --no-heading --columns=_uuid find Logical_Switch_Port name=${LPORT_EXT_ID})
sudo ovn-nbctl lsp-set-addresses ${OVN_PORT} "${LPORT_MAC} ${LPORT_IP}"

echo "${LPORT_EXT_ID} created with mac ${LPORT_MAC} and address ${LPORT_IP}"
echo '# To create a fake vm (assuming this is a parent-like port), do:'
echo "sudo $(dirname "$0")/create-fake-vm.sh ${LPORT_EXT_ID} ${LPORT_MAC} ${LPORT_IP}/${IP_MASK} ${GW}"

exit 0

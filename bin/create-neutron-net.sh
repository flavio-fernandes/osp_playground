#!/bin/bash
#

##[ $EUID -eq 0 ] || { echo 'must be root' >&2; exit 1; }

set -o errexit
# set -x

# Script Arguments:
# $1 - NET -- openstack network name
# $2 - SUBNET_RANGE -- IPv4 cidr formated as w.x.y.z/mask
# $3 - RTR_NAME -- router name. Can be ''
NET=$1
SUBNET_RANGE=$2
RTR=${3:-r}

PRJ=$(openstack project show -f value -c id ${OS_PROJECT_NAME})
SECGRP=$(openstack security group list -f value -c ID -c Name -c Project | grep ${PRJ} | cut -d' ' -f1)
SUBNET="${NET}subnet"

openstack router show ${RTR} -f value -c id >/dev/null 2>&1 || \
    openstack router create ${RTR} >/dev/null

openstack network create --provider-network-type geneve ${NET} >/dev/null
openstack subnet create --subnet-range ${SUBNET_RANGE} --network ${NET} ${SUBNET} >/dev/null
openstack router add subnet ${RTR} ${SUBNET}

exit 0

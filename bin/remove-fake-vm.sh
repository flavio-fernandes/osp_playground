#!/bin/bash
#
[ $EUID -eq 0 ] || { echo 'must be root' >&2; exit 1; }

set -o errexit
# set -x

## This script is intended to be run where the namespace exists.
## It reverses create-fake-vm.sh
## remove-fake-vm.sh $UUID

## example: remove-fake-vm.sh 7fe8d6db-69e2-4f31-9ac9-a122197e9bb2

# Script Arguments:
# $1 - UUID -- opaque uuid for namespace
# $2 - FILE_CONF -- ini file with namespace params. Can be ''
UUID=$1
FILE_CONF=${2:-/root/fakevms.conf}

[ -z "${UUID}" ] && { echo >&2 "usage: $0 <uuid> [<file_conf>]"; exit 10; }

do_remove_ns_port () {
    ns=$1
    ovs_bridge=$2
    devname=$3
    mac_addr=$4

    # sanity: make sure mac is what we expect
    IF_INFO=$(ip netns exec $ns ip link show eth0 2>/dev/null | awk '/link\/ether/ { print $2 }')
    [ "$IF_INFO" == "$mac_addr" ] || [ -z "$IF_INFO" ] || \
        { echo >&2 "unexpected mac in namespace $ns $IF_INFO is not $mac_addr"; exit 1; }

    # stop sshd running on behalf of namespace
    ns_sshd_pid="/run/sshd-fakevm-${ns}.pid"
    [ -e "${ns_sshd_pid}" ] && {
        echo "stopping sshd ${ns_sshd_pid}"
        kill -9 $(cat "${ns_sshd_pid}") ||:
        rm -f "${ns_sshd_pid}"
    }

    ip netns exec $ns ip link set dev eth0 down ||:

    # de-attach port from namespace
    ip netns exec $ns ip link set dev eth0 name "${devname}_2" ||:
    ip netns exec $ns ip link set "${devname}_2" netns 1 ||:

    ip link set "${devname}" down ||:
    ovs-vsctl br-exists ${ovs_bridge} && \
        ovs-vsctl --if-exists del-port ${ovs_bridge} "${devname}"

    ip link del "${devname}" ||:
    ## sudo ip link del "${devname}_2"

    ip netns delete $ns ||:
    [ -d /etc/netns/${ns} ] && rm -rf /etc/netns/${ns} ||:
}

# do not mess with invalid or non-existing entry
uuid_is_valid=$(crudini --get "$FILE_CONF" "$UUID" _valid 2>/dev/null || echo "NO_FOUND")
[ "${uuid_is_valid}" == "true" ] || {
    [ "${uuid_is_valid}" == "NO_FOUND" ] && {
        echo >&2 "uuid not in ${FILE_CONF}. Is ${UUID} already removed?"
        exit 0
    }
    echo >&2 "cowardly refusing to remove invalid uuid ${UUID}"
    exit 2
}

# assign variables from section of file
# http://www.pixelbeat.org/programs/crudini/
eval $(crudini --get --format=sh "$FILE_CONF" "$UUID")

# if removal goes okay, update config file and
# trim blank lines that have more than 2 empties
# ref: https://unix.stackexchange.com/questions/72739/how-to-remove-multiple-blank-lines-from-a-file#72745
[ "${_valid}" == "true" ] && \
    do_remove_ns_port $namespace $ovs_bridge $dev_name $mac && \
    crudini --del $FILE_CONF $UUID && \
    cat $FILE_CONF | sed -r ':a; /^\s*$/ {N;ba}; s/( *\n *){2,}/\n\n/' > ${FILE_CONF}.tmp && \
    mv -f ${FILE_CONF}.tmp ${FILE_CONF} && \
    echo namespace $namespace $UUID removed and "$FILE_CONF" updated && \
    exit 0

# should not get here
echo "ERROR: namespace was not properly removed uuid:${UUID} ns:${ns} valid:${_valid}" >&2
exit 1

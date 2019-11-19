#!/bin/bash
#
[ $EUID -eq 0 ] || { echo 'must be root' >&2; exit 1; }

set -o errexit
#set -x

## example: remove-all-fake-vm.sh

# Script Arguments:
# $1 - FILE_CONF -- ini file with namespace params. Can be ''
FILE_CONF=${1:-/root/fakevms.conf}

cd "$(dirname $0)"
for uuid in $(crudini --get --format=lines ${FILE_CONF} | awk '{print $2}' | sort --unique) ; do \
    ./remove-fake-vm.sh $uuid
done
exit 0

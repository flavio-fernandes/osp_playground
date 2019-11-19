# osp_playground
Deploying OVN on Openstack scripts

Pre-reqs are listed in bindep.txt

Steps for creating a trunk port under a namespace, and then
adding a sub-port into it.

```
$ create-neutron-net.sh net1 10.1.1.0/24
$ create-neutron-net.sh net2 20.2.2.0/24

$ create-neutron-port.sh net1 parent
$ parent=$(openstack port show -f value -c id parent)
$ p_mac=$(openstack port show -f value -c mac_address parent)
$ sudo ./bin/create-fake-vm.sh $parent $p_mac

$ create-neutron-port.sh net2 sub1
$ sub1=$(openstack port show -f value -c id sub1)
$ sub1vlan=123

$ set-trunk.sh trunk1 $parent $sub1 $sub1vlan

$ openstack network trunk show trunk1
$ openstack port show sub1
```


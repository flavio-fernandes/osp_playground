# osp_playground
Deploying OVN on Openstack scripts

Pre-reqs are listed in bindep.txt

Steps for creating a trunk port under a fake vm, and then
adding a sub-port into it.

```
$ create-neutron-net.sh net1 10.1.1.0/24
$ create-neutron-net.sh net2 20.2.2.0/24

$ create-neutron-port.sh net1 parent
$ parent=$(openstack port show -f value -c id parent)
$ p_ip_raw=$(openstack port show -c fixed_ips --format=value parent)
$ p_ip=$(echo $p_ip_raw | awk -F'ip_address=' '{print $2}' | awk -F"'" '{print $2}')
$ p_mac=$(openstack port show -c mac_address --format=value parent)
$ gw=$(openstack subnet show net1subnet -f value -c gateway_ip)
$ sudo ./bin/create-fake-vm.sh $parent ${p_ip}/24 $p_mac $gw

$ create-neutron-port.sh net2 sub1
$ sub1=$(openstack port show -f value -c id sub1)
$ sub1vlan=123

$ create-trunk.sh $parent $sub1 $sub1vlan trunk1

$ openstack network trunk show trunk1
$ openstack port show sub1
```


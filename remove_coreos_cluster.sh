#!/bin/bash

for i in $(virsh list --all --name | grep coreos); do
	virsh destroy $i; virsh undefine $i && rm -rf /var/lib/libvirt/images/coreos/$i && rm -f /var/lib/libvirt/images/coreos/$i.qcow2
	ssh-keygen -f "/home/$USER/.ssh/known_hosts.coreos" -R $i
	chown $USER:$USER /home/$USER/.ssh/known_hosts.coreos
done

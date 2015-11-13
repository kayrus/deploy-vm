#!/bin/bash

for i in $(virsh list --all --name | grep ubuntu); do
	virsh destroy $i; virsh undefine $i && rm -rf /var/lib/libvirt/images/ubuntu/$i && rm -f /var/lib/libvirt/images/ubuntu/$i.qcow2
	ssh-keygen -f "/home/$USER/.ssh/known_hosts.ubuntu" -R $i
	chown $USER:$USER /home/$USER/.ssh/known_hosts.ubuntu
done

#!/bin/bash
USER=
for i in $(virsh list --all --name | grep k8s); do
	virsh destroy $i; virsh undefine $i && rm -rf /var/lib/libvirt/images/coreos/$i && rm -f /var/lib/libvirt/images/coreos/$i.qcow2
	ssh-keygen -f "/home/$USER/.ssh/known_hosts.k8s" -R $i
	chown $USER:$USER /home/$USER/.ssh/known_hosts.k8s
done

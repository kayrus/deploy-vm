#!/bin/bash

USER_ID=1000
USER=$(getent passwd "${USER_ID}" | cut -d: -f1)
HOME=$(getent passwd "${USER_ID}" | cut -d: -f6)

for i in $(virsh list --all --name | grep ubuntu); do
  virsh destroy $i; virsh undefine $i && rm -rf /var/lib/libvirt/images/ubuntu/$i && rm -f /var/lib/libvirt/images/ubuntu/$i.qcow2
  ssh-keygen -f "${HOME}/.ssh/known_hosts.ubuntu" -R $i
  chown ${USER}:${USER} ${HOME}/.ssh/known_hosts.ubuntu
done

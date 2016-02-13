#!/bin/bash

print_red() {
  echo -e "\e[91m$1\e[0m"
}

if [ -z $1 ]; then
  echo "Enter OS_NAME and VM_PREFIX"
  exit 1
fi

OS_NAME=$1
VM_PREFIX=${2:-$OS_NAME}

USER_ID=${SUDO_UID:-$(id -u)}
USER=$(getent passwd "${USER_ID}" | cut -d: -f1)
HOME=$(getent passwd "${USER_ID}" | cut -d: -f6)

IMG_PATH=/var/lib/libvirt/images/${OS_NAME}

VMS=$(virsh list --all --name | grep "^${VM_PREFIX}" | tr '\n' ' ')

if [ -z "$VMS" ]; then
  echo "Nothing to delete, exiting"
  exit 0
fi

VM_LIST=$(print_red "$VMS")
read -p "Are you sure to remove '$VM_LIST'? " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  exit 1
fi

for VM_HOSTNAME in $VMS; do
  virsh destroy $VM_HOSTNAME; virsh undefine $VM_HOSTNAME && rm -rf $IMG_PATH/$VM_HOSTNAME && rm -f $IMG_PATH/$VM_HOSTNAME.qcow2
  if [[ $(selinuxenabled 2>/dev/null) ]]; then
    echo "Removing SELinux configuration"
    semanage fcontext -d -t virt_content_t "$IMG_PATH/$VM_HOSTNAME(/.*)?"
    restorecon -R "$IMG_PATH"
  fi
  if [ -f "${HOME}/.ssh/known_hosts.${OS_NAME}" ]; then
    sudo -u $USER ssh-keygen -f "${HOME}/.ssh/known_hosts.${VM_PREFIX}" -R $VM_HOSTNAME
  fi
done

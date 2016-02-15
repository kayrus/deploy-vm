#!/bin/bash

usage() {
  echo "Usage: $0 %os_name% [%vms_prefix%]"
}

print_red() {
  echo -e "\e[91m$1\e[0m"
}

if [ -z $1 ]; then
  usage
  exit 1
fi

case "$1" in
  coreos);;
  centos);;
  ubuntu);;
  debian);;
  fedora);;
  *)
    echo "'$1' OS prefix is not supported"
    exit 1;;
esac

export LIBVIRT_DEFAULT_URI=qemu:///system

OS_NAME=$1
VM_PREFIX=${2:-$OS_NAME}

USER_ID=${SUDO_UID:-$(id -u)}
USER=$(getent passwd "${USER_ID}" | cut -d: -f1)
HOME=$(getent passwd "${USER_ID}" | cut -d: -f6)

IMG_PATH=${HOME}/.libvirt/${OS_NAME}

VMS=$(virsh list --all --name | grep "^${VM_PREFIX}" | tr '\n' ' ')

if [ -z "$VMS" ]; then
  echo "Nothing to delete, exiting"
  exit 0
fi

VM_LIST=$(print_red "$VMS")
read -p "Are you sure to remove '$VM_LIST'? (Type 'y' when agree) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  exit 1
fi

for VM_HOSTNAME in $VMS; do
  virsh destroy $VM_HOSTNAME
  virsh undefine $VM_HOSTNAME
  virsh vol-delete ${VM_HOSTNAME}.qcow2 --pool $OS_NAME
  rm -rf ${IMG_PATH}/$VM_HOSTNAME
  if [[ $(selinuxenabled 2>/dev/null) ]]; then
    echo "Removing SELinux configuration"
    semanage fcontext -d -t virt_content_t "$IMG_PATH/$VM_HOSTNAME(/.*)?"
    restorecon -R "$IMG_PATH"
  fi
  if [ -f "${HOME}/.ssh/known_hosts.${OS_NAME}" ]; then
    if [ -n "${SUDO_UID}" ]; then
      sudo -u $USER ssh-keygen -f "${HOME}/.ssh/known_hosts.${VM_PREFIX}" -R $VM_HOSTNAME
    else
      ssh-keygen -f "${HOME}/.ssh/known_hosts.${VM_PREFIX}" -R $VM_HOSTNAME
    fi
  fi
done

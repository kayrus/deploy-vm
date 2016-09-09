#!/usr/bin/env bash

print_red() {
  printf '%b' "\033[91m$1\033[0m\n"
}

print_green() {
  printf '%b' "\033[92m$1\033[0m\n"
}

usage() {
  echo "Usage: $0 %os_name% [%vms_prefix%]"
  echo "  Supported OS:"
  print_green "    * coreos [k8s]"
  print_green "    * atomic-centos"
  print_green "    * atomic-fedora"
  print_green "    * clearlinux"
  print_green "    * centos"
  print_green "    * ubuntu"
  print_green "    * ubuntu-core"
  print_green "    * debian"
  print_green "    * fedora"
  print_green "    * opensuse"
  print_green "    * freebsd"
  print_green "    * windows"
}

check_hypervisor() {
  export LIBVIRT_DEFAULT_URI=qemu:///system
  if ! virsh list > /dev/null 2>&1; then
    export LIBVIRT_DEFAULT_URI=bhyve:///system
    if ! virsh list > /dev/null 2>&1; then
      print_red "Failed to connect to the hypervisor socket"
      exit 1
    fi
  fi
}

check_hypervisor

if [ -z $1 ]; then
  usage
  exit 1
fi

case "$1" in
  coreos);;
  atomic-centos);;
  atomic-fedora);;
  clearlinux)DISK_FORMAT="raw";;
  centos);;
  ubuntu);;
  ubuntu-core);;
  debian);;
  fedora);;
  opensuse);;
  freebsd);;
  windows)DISK_FORMAT="vmdk";;
  *)
    echo "'$1' OS prefix is not supported"
    usage
    exit 1;;
esac

OS_NAME=$1
VM_PREFIX=${2:-$OS_NAME}

USER_ID=${SUDO_UID:-$(id -u)}
USER=$(getent passwd "${USER_ID}" | cut -d: -f1)
HOME=$(getent passwd "${USER_ID}" | cut -d: -f6)

IMG_PATH="${HOME}/libvirt_images/${OS_NAME}"
DISK_FORMAT=${DISK_FORMAT:-qcow2}

VMS=$(virsh list --all --name | grep "^${VM_PREFIX}" | tr '\n' ' ')

if [ -z "$VMS" ]; then
  echo "Nothing to delete, exiting"
  exit 0
fi

VM_LIST=$(print_red "$VMS")
read -p "Are you sure to remove '$VM_LIST'? (Type 'y' when agree) " -n 1 -r
echo
if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
  exit 1
fi

for VM_HOSTNAME in $VMS; do
  virsh destroy $VM_HOSTNAME
  virsh undefine $VM_HOSTNAME
  # Hack when "virsh vol-delete" doesn't have permissions to delete the volume
  rm -f "${IMG_PATH}/$VM_HOSTNAME.${DISK_FORMAT}"
  virsh vol-delete ${VM_HOSTNAME}.${DISK_FORMAT} --pool $OS_NAME
  rm -rf "${IMG_PATH}/$VM_HOSTNAME"

  if [ -f "${HOME}/.ssh/known_hosts.${OS_NAME}" ]; then
    if [ -n "${SUDO_UID}" ]; then
      sudo -u "$USER" ssh-keygen -f "${HOME}/.ssh/known_hosts.${VM_PREFIX}" -R $VM_HOSTNAME
    else
      ssh-keygen -f "${HOME}/.ssh/known_hosts.${VM_PREFIX}" -R $VM_HOSTNAME
    fi
  fi
done

virsh pool-destroy $OS_NAME
virsh pool-undefine $OS_NAME

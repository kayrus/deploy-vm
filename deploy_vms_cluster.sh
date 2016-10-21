#!/usr/bin/env bash

set -e

usage() {
  echo "
Usage: $0 -o %OS_NAME% [options]
Options:
    -o|--os             OS_NAME
                        Supported OS list
                        * centos
                        * atomic-centos
                        * atomic-fedora
                        * clearlinux (not yet supported)
                        * ubuntu
                        * ubuntu-core (not yet supported)
                        * debian
                        * fedora
                        * opensuse
                        * windows
                        * freebsd
    -c|--channel        CHANNEL
                        channel name
    -r|--release        RELEASE
                        OS release
    -s|--size           CLUSTER_SIZE
                        Amount of virtual machines in a cluster.   [default: 1]
    -p|--pub-key        PUBLIC_KEY
                        Path to public key. Private key path will
                        be detected automatically.                 [default: ~/.ssh/id_rsa.pub]
    -i|--config         CLOUD_CONFIG
                        Path to cloud-config.                      [default: internal]
    -m|--ram            RAM
                        Amount of memory in megabytes for each VM. [default: 512]
    -u|--cpu            CPUs
                        Amount of CPUs for each VM.                [default: 1]
    -v|--verbose        Make verbose
    -h|--help           This help message

This script is a wrapper around libvirt for starting a cluster of virtual machines.
"
}

print_red() {
  printf '%b' "\033[91m$1\033[0m\n"
}

print_green() {
  printf '%b' "\033[92m$1\033[0m\n"
}

check_cmd() {
  which "$1" >/dev/null || { print_red "'$1' command is not available, please install it first, then try again" && exit 1; }
}

check_genisoimage() {
  if which genisoimage >/dev/null; then
    GENISOIMAGE=$(which genisoimage)
  else
    if which mkisofs >/dev/null; then
      GENISOIMAGE=$(which mkisofs)
    else
       print_red "Neither 'genisoimage' nor 'mkisofs' command is available, please install it first, then try again"
       exit 1
    fi
  fi
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

handle_channel_release() {
  if [ -z "$1" ]; then
    print_green "$OS_NAME doesn't use channel"
  else
    : ${CHANNEL:=$1}
    if [ -n "$OPTVAL_CHANNEL" ]; then
      CHANNEL=$OPTVAL_CHANNEL
    else
      print_green "Using default $CHANNEL channel for $OS_NAME"
    fi
  fi
  if [ -z "$2" ]; then
    print_green "$OS_NAME doesn't use release"
  else
    : ${RELEASE:=$2}
    if [ -n "$OPTVAL_RELEASE" ]; then
      RELEASE=$OPTVAL_RELEASE
    else
      print_green "Using default $RELEASE release for $OS_NAME"
    fi
  fi
}

check_cmd wget
check_cmd virsh
check_cmd virt-install
check_cmd qemu-img
check_cmd xzcat
check_cmd bzcat
check_cmd cut
check_cmd sed
check_genisoimage
check_hypervisor

USER_ID=${SUDO_UID:-$(id -u)}
USER=$(getent passwd "${USER_ID}" | cut -d: -f1)
HOME=$(getent passwd "${USER_ID}" | cut -d: -f6)

trap usage EXIT

while [ $# -ge 1 ]; do
  case "$1" in
    -o|--os)
      OPTVAL_OS_NAME="$2"
      shift 2 ;;
    -c|--channel)
      OPTVAL_CHANNEL="$2"
      shift 2 ;;
    -r|--release)
      OPTVAL_RELEASE="$2"
      shift 2 ;;
    -s|--cluster-size)
      OPTVAL_CLUSTER_SIZE="$2"
      shift 2 ;;
    -p|--pub-key)
      OPTVAL_PUB_KEY="$2"
      shift 2 ;;
    -i|--config)
      OPTVAL_CLOUD_CONFIG="$2"
      shift 2 ;;
    -m|--ram)
      OPTVAL_RAM="$2"
      shift 2 ;;
    -u|--cpu)
      OPTVAL_CPU="$2"
      shift 2 ;;
    -v|--verbose)
      set -x
      shift ;;
    -h|-help|--help)
      usage
      trap - EXIT
      trap
      exit ;;
    *)
      break ;;
  esac
done

trap - EXIT
trap

RAM_min=0
CPUs_min=0

OS_NAME=$OPTVAL_OS_NAME

case "$OS_NAME" in
  coreos)
    echo "Use ./deploy_coreos_cluster.sh script"
    exit 1
    ;;
  atomic-centos)
    BOOT_HOOK="bootcmd:
  - echo 'DHCP_HOSTNAME=\${HOSTNAME}' >> /etc/sysconfig/network
runcmd:
  - systemctl restart NetworkManager"
    handle_channel_release '' 7
    SSH_USER=centos
    IMG_NAME="CentOS-Atomic-Host-${RELEASE}-GenericCloud.qcow2"
    IMG_URL="http://cloud.centos.org/centos/${RELEASE}/atomic/images/CentOS-Atomic-Host-${RELEASE}-GenericCloud.qcow2.xz"
    ;;
  atomic-fedora)
    BOOT_HOOK="bootcmd:
  - echo 'DHCP_HOSTNAME=\${HOSTNAME}' >> /etc/sysconfig/network
runcmd:
  - systemctl restart NetworkManager"
    handle_channel_release 23 20160223
    SSH_USER=fedora
    IMG_NAME="CentOS-Atomic-Host-${RELEASE}-GenericCloud.qcow2"
    IMG_URL="https://download.fedoraproject.org/pub/alt/atomic/stable/Cloud-Images/x86_64/Images/Fedora-Cloud-Atomic-${CHANNEL}-${RELEASE}.x86_64.qcow2"
    ;;
  centos)
    BOOT_HOOK="bootcmd:
  - echo 'DHCP_HOSTNAME=\${HOSTNAME}' >> /etc/sysconfig/network
runcmd:
  - service network restart"
    handle_channel_release '' 7
    IMG_NAME="CentOS-${RELEASE}-x86_64-GenericCloud.qcow2"
    IMG_URL="http://cloud.centos.org/centos/${RELEASE}/images/CentOS-${RELEASE}-x86_64-GenericCloud.qcow2.xz"
    ;;
  fedora)
    BOOT_HOOK="bootcmd:
  - echo 'DHCP_HOSTNAME=\${HOSTNAME}' >> /etc/sysconfig/network
runcmd:
  - service network restart"
    handle_channel_release 23 20151030
    IMG_NAME="Fedora-Cloud-Base-${CHANNEL}-${RELEASE}.x86_64.qcow2"
    IMG_URL="https://download.fedoraproject.org/pub/fedora/linux/releases/${CHANNEL}/Cloud/x86_64/Images/Fedora-Cloud-Base-${CHANNEL}-${RELEASE}.x86_64.qcow2"
    ;;
  opensuse)
    BOOT_HOOK="bootcmd:
  - echo 'DHCP_HOSTNAME=\${HOSTNAME}' >> /etc/sysconfig/network
runcmd:
  - service network restart"
    handle_channel_release '' 13.2
    IMG_NAME="openSUSE-${RELEASE}-OpenStack-Guest.x86_64.qcow2"
    IMG_URL="http://download.opensuse.org/repositories/Cloud:/Images:/openSUSE_${RELEASE}/images/openSUSE-${RELEASE}-OpenStack-Guest.x86_64.qcow2"
    SKIP_SSH_CHECK=true
    ;;
  debian)
    BOOT_HOOK="runcmd:
  - service networking restart"
    handle_channel_release 8.5.0 current
    IMG_NAME="debian-${CHANNEL}-openstack-amd64.qcow2"
    IMG_URL="http://cdimage.debian.org/cdimage/openstack/${RELEASE}/debian-${CHANNEL}-openstack-amd64.qcow2"
    ;;
  ubuntu)
    BOOT_HOOK="runcmd:
  - service networking restart"
    handle_channel_release xenial current
    # extra size for images
    IMG_SIZE="10G"
    IMG_NAME="${CHANNEL}-server-cloudimg-amd64.qcow2"
    if [ "$CHANNEL" = "yakkety" ]; then
      IMG_URL="https://cloud-images.ubuntu.com/daily/server/${CHANNEL}/${RELEASE}/${CHANNEL}-server-cloudimg-amd64.img"
    else
      IMG_URL="https://cloud-images.ubuntu.com/daily/server/${CHANNEL}/${RELEASE}/${CHANNEL}-server-cloudimg-amd64-disk1.img"
    fi
    ;;
  ubuntu-core)
    BOOT_HOOK="runcmd:
  - service networking restart"
    handle_channel_release 15.04 current
    SSH_USER=ubuntu
    IMG_NAME="core-${CHANNEL}-amd64.qcow2"
    IMG_URL="https://cloud-images.ubuntu.com/ubuntu-core/${CHANNEL}/core/stable/${RELEASE}/core-stable-amd64-disk1.img"
    ;;
  freebsd)
    handle_channel_release 10.3 RELEASE
    #SKIP_CLOUD_CONFIG=true
    #NETWORK_DEVICE="e1000"
    IMG_NAME="FreeBSD-${CHANNEL}-${RELEASE}-amd64.qcow2"
    IMG_URL="http://ftp.freebsd.org/pub/FreeBSD/releases/VM-IMAGES/${CHANNEL}-${RELEASE}/amd64/Latest/FreeBSD-${CHANNEL}-${RELEASE}-amd64.qcow2.xz"
    SKIP_SSH_CHECK=true
    ;;
  clearlinux)
    LATEST=$(curl -s https://download.clearlinux.org/latest)
    IMG_NAME="clear-${LATEST}-kvm.img"
    IMG_URL="https://download.clearlinux.org/releases/${LATEST}/clear/clear-${LATEST}-kvm.img.xz"
    DISK_FORMAT="raw"
    SKIP_SSH_CHECK=true
    ;;
  windows)
    check_cmd bsdtar
    WIN_VARIANTS="IE6.XP IE7.Vista IE8.XP IE8.Win7 IE9.Win7 IE10.Win7 IE10.Win8 IE11.Win7 IE11.Win8.1 IE11.Win10"
    handle_channel_release '' IE11.Win7
    for WIN_VARIANT in $WIN_VARIANTS; do
      if [ "$RELEASE" = "$WIN_VARIANT" ]; then
        FOUND_RELEASE=true
        break;
      fi
    done
    if [ -z $FOUND_RELEASE ]; then
      print_red "$RELEASE is not a correct release name"
      print_green "Available releases for $OPTVAL_OS_NAME:"
      for WIN_VARIANT in $WIN_VARIANTS; do
        print_green "  * $WIN_VARIANT"
      done
      exit 1
    fi
    IE_VERSION=$(echo "$RELEASE" | cut -d. -f1)
    WIN_VERSION=$(echo "$RELEASE" | cut -d. -f2,3)
    if [ "$WIN_VERSION" = "XP" ]; then
      WIN_VERSION_EXTRA="Win$WIN_VERSION"
    else
      WIN_VERSION_EXTRA=$WIN_VERSION
    fi
    IMG_NAME="${IE_VERSION}-${WIN_VERSION}-disk1.vmdk"
    if [ "$RELEASE" = "IE11.Win10" ]; then
      IMG_URL="https://az792536.vo.msecnd.net/vms/VMBuild_20150801/VirtualBox/MSEdge/Windows/Microsoft%20Edge.Win10.For.Windows.VirtualBox.zip"
    else
      IMG_URL="https://az412801.vo.msecnd.net/vhd/VMBuild_20141027/VirtualBox/${IE_VERSION}/Windows/${IE_VERSION}.${WIN_VERSION}.For.Windows.VirtualBox.zip"
    fi
    DISK_BUS="ide"
    DISK_FORMAT="vmdk"
    NETWORK_DEVICE="rtl8139"
    RAM_min=1024
    CPUs_min=2
    SKIP_CLOUD_CONFIG=true
    SKIP_SSH_CHECK=true
    ;;
  '')
    print_red "OS should be specified"
    usage
    exit 1
    ;;
  *)
    print_red "'$1' OS is not supported"
    usage
    exit 1
    ;;
esac

SSH_USER=${SSH_USER:-$OS_NAME}

virsh list --all --name | grep -q "^${OS_NAME}1$" && { print_red "'${OS_NAME}1' VM already exists"; exit 1; }

: ${CLUSTER_SIZE:=1}
if [ -n "$OPTVAL_CLUSTER_SIZE" ]; then
  if [[ ! "$OPTVAL_CLUSTER_SIZE" =~ ^[0-9]+$ ]]; then
    print_red "'$OPTVAL_CLUSTER_SIZE' is not a number"
    usage
    exit 1
  fi
  CLUSTER_SIZE=$OPTVAL_CLUSTER_SIZE
fi

: ${INIT_PUB_KEY:="$HOME/.ssh/id_rsa.pub"}
if [ -n "$OPTVAL_PUB_KEY" ]; then
  INIT_PUB_KEY=$OPTVAL_PUB_KEY
fi

if [ -z "$INIT_PUB_KEY" ] || [ ! -f "$INIT_PUB_KEY" ]; then
  print_red "SSH public key path is not valid or not specified"
  if [ -n "$HOME" ]; then
    PUB_KEY_PATH="$HOME/.ssh/id_rsa.pub"
  else
    print_red "Can not determine home directory for SSH pub key path"
    exit 1
  fi

  print_green "Will use default path to SSH public key: $PUB_KEY_PATH"
  if [ ! -f "$PUB_KEY_PATH" ]; then
    print_red "Path $PUB_KEY_PATH doesn't exist"
    PRIV_KEY_PATH=$(echo "${PUB_KEY_PATH}" | sed 's#.pub##')
    if [ -f "$PRIV_KEY_PATH" ]; then
      print_green "Found private key, generating public key..."
      if [ -n "$SUDO_UID" ]; then
        sudo -u "$USER" ssh-keygen -y -f "$PRIV_KEY_PATH" | sudo -u "$USER" tee "${PUB_KEY_PATH}" > /dev/null
      else
        ssh-keygen -y -f "$PRIV_KEY_PATH" > "${PUB_KEY_PATH}"
      fi
    else
      print_green "Generating private and public keys..."
      if [ -n "$SUDO_UID" ]; then
        sudo -u "$USER" ssh-keygen -t rsa -N "" -f "$PRIV_KEY_PATH"
      else
        ssh-keygen -t rsa -N "" -f "$PRIV_KEY_PATH"
      fi
    fi
  fi
else
  PUB_KEY_PATH="$INIT_PUB_KEY"
  print_green "Will use following path to SSH public key: $PUB_KEY_PATH"
fi

OPENSTACK_DIR="openstack/latest"
PUB_KEY=$(cat "${PUB_KEY_PATH}")
PRIV_KEY_PATH=$(echo ${PUB_KEY_PATH} | sed 's#.pub##')
CDIR=$(cd `dirname $0` && pwd)
IMG_PATH="${HOME}/libvirt_images/${OS_NAME}"
DISK_BUS=${DISK_BUS:-virtio}
NETWORK_DEVICE=${NETWORK_DEVICE:-virtio}
DISK_FORMAT=${DISK_FORMAT:-qcow2}

if [ -n "$OPTVAL_CLOUD_CONFIG" ] && [ -f "$OPTVAL_CLOUD_CONFIG" ]; then
  USER_DATA_TEMPLATE=$OPTVAL_CLOUD_CONFIG
  print_green "Will use custom cloud-config (${USER_DATA_TEMPLATE})"
fi
: ${RAM:=512}
if [ -n "$OPTVAL_RAM" ]; then
  if [[ ! "$OPTVAL_RAM" =~ ^[0-9]+$ ]]; then
    print_red "'$OPTVAL_RAM' is not a valid amount of RAM"
    usage
    exit 1
  fi
  RAM=$OPTVAL_RAM
fi

if [ "${RAM_min}" -gt "$RAM" ]; then
  print_red "Recommended RAM for $OS_NAME should not be less than ${RAM_min}"
  exit 1
fi

: ${CPUs:=1}
if [ -n "$OPTVAL_CPU" ]; then
  if [[ ! "$OPTVAL_CPU" =~ ^[0-9]+$ ]]; then
    print_red "'$OPTVAL_CPU' is not a valid amount of CPUs"
    usage
    exit 1
  fi
  CPUs=$OPTVAL_CPU
fi

if [ "${CPUs_min}" -gt "$CPUs" ]; then
  print_red "Recommended CPUs for $OS_NAME should not be less than ${CPUs_min}"
  exit 1
fi

IMG_EXTENSION=""
if [[ "${IMG_URL}" =~ \.([a-z0-9]+)$ ]]; then
  IMG_EXTENSION=${BASH_REMATCH[1]}
fi

case "${IMG_EXTENSION}" in
  bz2)
    DECOMPRESS="| bzcat";;
  xz)
    DECOMPRESS="| xzcat";;
  zip)
    DECOMPRESS="| bsdtar -Oxf - '${IE_VERSION} - ${WIN_VERSION_EXTRA}.ova' | tar -Oxf - '${IE_VERSION} - ${WIN_VERSION_EXTRA}-disk1.vmdk'";;
  *)
    DECOMPRESS="";;
esac

if [ ! -d "$IMG_PATH" ]; then
  mkdir -p "$IMG_PATH" || { print_red "Can not create $IMG_PATH directory" && exit 1; }
fi

CC="#cloud-config
password: passw0rd
chpasswd: { expire: False }
ssh_pwauth: True
users:
  - default:
    ssh-authorized-keys:
      - '${PUB_KEY}'
${BOOT_HOOK}
"

for SEQ in $(seq 1 $CLUSTER_SIZE); do
  VM_HOSTNAME="${OS_NAME}${SEQ}"
  if [ -z $FIRST_HOST ]; then
    FIRST_HOST=$VM_HOSTNAME
  fi

  if [ ! -d "$IMG_PATH/$VM_HOSTNAME/$OPENSTACK_DIR" ]; then
    mkdir -p "$IMG_PATH/$VM_HOSTNAME/$OPENSTACK_DIR" || { print_red "Can not create $IMG_PATH/$VM_HOSTNAME/$OPENSTACK_DIR directory" && exit 1; }
  fi

  virsh pool-info $OS_NAME > /dev/null 2>&1 || virsh pool-create-as $OS_NAME dir --target "$IMG_PATH" || { print_red "Can not create $OS_NAME pool at $IMG_PATH target" && exit 1; }
  # Make this pool persistent
  (virsh pool-dumpxml $OS_NAME | virsh pool-define /dev/stdin)
  virsh pool-start $OS_NAME > /dev/null 2>&1 || true

  if [ ! -f "$IMG_PATH/$IMG_NAME" ]; then
    trap 'rm -f "$IMG_PATH/$IMG_NAME"' INT TERM EXIT
    eval "wget \"$IMG_URL\" -O - $DECOMPRESS > \"$IMG_PATH/$IMG_NAME\"" || { rm -f "$IMG_PATH/$IMG_NAME" && print_red "Failed to download image" && exit 1; }
    trap - INT TERM EXIT
    trap
  fi

  if [ ! -f "$IMG_PATH/${VM_HOSTNAME}.${DISK_FORMAT}" ]; then
    qemu-img create -f $DISK_FORMAT -b "$IMG_PATH/$IMG_NAME" "$IMG_PATH/${VM_HOSTNAME}.${DISK_FORMAT}" $IMG_SIZE || \
      { print_red "Failed to create ${VM_HOSTNAME}.${DISK_FORMAT} volume image" && exit 1; }
    virsh pool-refresh $OS_NAME
  fi
  UUID=$(cat /proc/sys/kernel/random/uuid)
  if [ -n "$USER_DATA_TEMPLATE" ] && [ -f "$USER_DATA_TEMPLATE" ]; then
    sed "s#%PUB_KEY%#$PUB_KEY#g;\
         s#%BOOT_HOOK%#$BOOT_HOOK#g" "$USER_DATA_TEMPLATE" > "$IMG_PATH/$VM_HOSTNAME/$OPENSTACK_DIR/user_data"
  else
    echo "$CC" > "$IMG_PATH/$VM_HOSTNAME/$OPENSTACK_DIR/user_data"
  fi
  echo -e "{ \"instance-id\": \"iid-${VM_HOSTNAME}\", \"local-hostname\": \"${VM_HOSTNAME}\", \"hostname\": \"${VM_HOSTNAME}\", \"dsmode\": \"local\", \"uuid\": \"$UUID\" }" > "$IMG_PATH/$VM_HOSTNAME/$OPENSTACK_DIR/meta_data.json"

  CC_DISK=""
  if [ -z $SKIP_CLOUD_CONFIG ]; then
    $GENISOIMAGE \
      -input-charset utf-8 \
      -output "$IMG_PATH/$VM_HOSTNAME/cidata.iso" \
      -volid config-2 \
      -joliet \
      -rock \
      "$IMG_PATH/$VM_HOSTNAME" || { print_red "Failed to create ISO image"; exit 1; }
    echo -e "#!/bin/sh\n$GENISOIMAGE -input-charset utf-8 -R -V $CC_VOL_ID -o \"$IMG_PATH/$VM_HOSTNAME/cidata.iso\" \"$IMG_PATH/$VM_HOSTNAME\"" > "$IMG_PATH/$VM_HOSTNAME/rebuild_iso.sh"
    chmod +x "$IMG_PATH/$VM_HOSTNAME/rebuild_iso.sh"
    virsh pool-refresh $OS_NAME
    if [ "$LIBVIRT_DEFAULT_URI" = "bhyve:///system" ]; then
      DISK_TYPE="bus=sata"
    else
      DISK_TYPE="device=cdrom"
    fi
    CC_DISK="--disk path=\"$IMG_PATH/$VM_HOSTNAME/cidata.iso\",${DISK_TYPE}"
  fi

  eval virt-install \
    --connect $LIBVIRT_DEFAULT_URI \
    --import \
    --name $VM_HOSTNAME \
    --ram $RAM \
    --vcpus $CPUs \
    --os-type=linux \
    --os-variant=virtio26 \
    --network network=default,model=${NETWORK_DEVICE} \
    --disk path="$IMG_PATH/$VM_HOSTNAME.${DISK_FORMAT}",format=${DISK_FORMAT},bus=$DISK_BUS \
    $CC_DISK \
    --vnc \
    --noautoconsole \
#    --cpu=host
done


if [ "x${SKIP_SSH_CHECK}" = "x" ]; then
  MAX_SSH_TRIES=50
  for SEQ in $(seq 1 $CLUSTER_SIZE); do
    VM_HOSTNAME="${OS_NAME}${SEQ}"
    TRY=0
    while true; do
      TRY=$((TRY+1))
      if [ $TRY -gt $MAX_SSH_TRIES ]; then
        print_red "Can not connect to ssh, exiting..."
        exit 1
      fi
      echo "Trying to connect to ${VM_HOSTNAME} VM, #${TRY} of #${MAX_SSH_TRIES}..."
      set +e
      RES=$(LANG=en_US ssh -l $SSH_USER -o BatchMode=yes -o ConnectTimeout=1 -o PasswordAuthentication=no -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ${PRIV_KEY_PATH} $VM_HOSTNAME "uptime" 2>&1)
      RES_CODE=$?
      set -e
      if [ $RES_CODE -eq 0 ]; then
        break
      else
        echo "$RES" | grep -Eq "(refused|No such file or directory|reset by peer|closed by remote host|authentication failure|failure in name resolution|Could not resolve hostname)" && sleep 1 || true
      fi
    done
  done
  print_green "Cluster of $CLUSTER_SIZE $OS_NAME nodes is up and running."
fi

print_green "Use following command to connect to your cluster: 'ssh -i \"$PRIV_KEY_PATH\" $SSH_USER@$FIRST_HOST'"

#!/usr/bin/env bash

set -e

usage() {
  echo "
Usage: $0 [options]
Options:
    -c|--channel        CHANNEL
                        channel name (stable/beta/alpha)           [default: stable]
    -r|--release        RELEASE
                        CoreOS release                             [default: current]
    -s|--size           CLUSTER_SIZE
                        Amount of virtual machines in a cluster.   [default: 2]
    -p|--pub-key        PUBLIC_KEY
                        Path to public key. Private key path will
                        be detected automatically.                 [default: ~/.ssh/id_rsa.pub]
    -i|--master-config  MASTER_CLOUD_CONFIG
                        Path to k8s master node cloud-config.      [default: ./k8s_master.yaml]
    -I|--node-config    NODE_CLOUD_CONFIG
                        Path to k8s node cloud-config.             [default: ./k8s_node.yaml]
    -t|--tectonic       TECTONIC
                        Spawns Tectonic cluster on top of k8s.
    -m|--ram            RAM
                        Amount of memory in megabytes for each VM. [default: 512]
    -u|--cpu            CPUs
                        Amount of CPUs for each VM.                [default: 1]
    -v|--verbose        Make verbose
    -h|--help           This help message

This script is a wrapper around libvirt for starting a cluster of CoreOS virtual
machines.
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

make_configdrive() {
  if [ selinuxenabled 2>/dev/null ] || [ "$LIBVIRT_DEFAULT_URI" = "bhyve:///system" ]; then
    # We use ISO configdrive to avoid complicated SELinux conditions
    $GENISOIMAGE -input-charset utf-8 -R -V config-2 -o "$IMG_PATH/$VM_HOSTNAME/configdrive.iso" "$IMG_PATH/$VM_HOSTNAME" || { print_red "Failed to create ISO image"; exit 1; }
    echo -e "#!/bin/sh\n$GENISOIMAGE -input-charset utf-8 -R -V config-2 -o \"$IMG_PATH/$VM_HOSTNAME/configdrive.iso\" \"$IMG_PATH/$VM_HOSTNAME\"" > "$IMG_PATH/$VM_HOSTNAME/rebuild_iso.sh"
    chmod +x "$IMG_PATH/$VM_HOSTNAME/rebuild_iso.sh"
    if [ "$LIBVIRT_DEFAULT_URI" = "bhyve:///system" ]; then
      DISK_TYPE="bus=sata"
    else
      DISK_TYPE="device=cdrom"
    fi
    CONFIG_DRIVE="--disk path=\"$IMG_PATH/$VM_HOSTNAME/configdrive.iso\",${DISK_TYPE}"
  else
    CONFIG_DRIVE="--filesystem \"$IMG_PATH/$VM_HOSTNAME/\",config-2,type=mount,mode=squash"
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
    -i|--master-config)
      OPTVAL_MASTER_CLOUD_CONFIG="$2"
      shift 2 ;;
    -I|--node-config)
      OPTVAL_NODE_CLOUD_CONFIG="$2"
      shift 2 ;;
    -m|--ram)
      OPTVAL_RAM="$2"
      shift 2 ;;
    -u|--cpu)
      OPTVAL_CPU="$2"
      shift 2 ;;
    -t|--tectonic)
      TECTONIC=true
      shift ;;
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

OS_NAME="coreos"
PREFIX="k8s"
MASTER_PREFIX="${PREFIX}-master"
NODE_PREFIX="${PREFIX}-node"
SSH_USER="core"

virsh list --all --name | grep -q "^${PREFIX}-[mn]" && { print_red "'$PREFIX-*' VMs already exist"; exit 1; }

: ${CLUSTER_SIZE:=2}
if [ -n "$OPTVAL_CLUSTER_SIZE" ]; then
  if [[ ! "$OPTVAL_CLUSTER_SIZE" =~ ^[0-9]+$ ]]; then
    print_red "'$OPTVAL_CLUSTER_SIZE' is not a number"
    usage
    exit 1
  fi
  CLUSTER_SIZE=$OPTVAL_CLUSTER_SIZE
fi

if [ "$CLUSTER_SIZE" -lt "2" ]; then
  echo "'$CLUSTER_SIZE' is lower than 2 (minimal k8s cluster size)"
  usage
  exit 1
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

# Enables automatic hostpath provisioner based on claim (test and development feature only)
# Experimental, see more here: https://github.com/kubernetes/kubernetes/pull/30694
K8S_AUTO_HOSTPATH_PROVISIONER=false # true or false
if [ "x$K8S_AUTO_HOSTPATH_PROVISIONER" = "xtrue" ]; then
  K8S_HOSTPATH_PROVISIONER_MOUNT_POINT="start"
else
  K8S_HOSTPATH_PROVISIONER_MOUNT_POINT="stop"
fi

PUB_KEY=$(cat "${PUB_KEY_PATH}")
PRIV_KEY_PATH=$(echo ${PUB_KEY_PATH} | sed 's#.pub##')
CDIR=$(cd `dirname $0` && pwd)
IMG_PATH="${HOME}/libvirt_images/${OS_NAME}"
RANDOM_PASS=$(openssl rand -base64 12)
TECTONIC_LICENSE=$(cat "$CDIR/tectonic.lic" 2>/dev/null || true)
DOCKER_CFG=$(cat "$CDIR/docker.cfg" 2>/dev/null || true)

if [ "$TECTONIC" = "true" ]; then
  : ${MASTER_USER_DATA_TEMPLATE:="${CDIR}/k8s_tectonic_master.yaml"}
else
  : ${MASTER_USER_DATA_TEMPLATE:="${CDIR}/k8s_master.yaml"}
fi
if [ -n "$OPTVAL_MASTER_CLOUD_CONFIG" ]; then
  if [ -f "$OPTVAL_MASTER_CLOUD_CONFIG" ]; then
    MASTER_USER_DATA_TEMPLATE=$OPTVAL_MASTER_CLOUD_CONFIG
  else
    print_red "Custom master cloud-config specified, but it is not available"
    print_red "Will use default master cloud-config path (${MASTER_USER_DATA_TEMPLATE})"
  fi
fi

: ${NODE_USER_DATA_TEMPLATE:="${CDIR}/k8s_node.yaml"}
if [ -n "$OPTVAL_NODE_CLOUD_CONFIG" ]; then
  if [ -f "$OPTVAL_NODE_CLOUD_CONFIG" ]; then
    NODE_USER_DATA_TEMPLATE=$OPTVAL_NODE_CLOUD_CONFIG
  else
    print_red "Custom node cloud-config specified, but it is not available"
    print_red "Will use default node cloud-config path (${NODE_USER_DATA_TEMPLATE})"
  fi
fi

ETCD_DISCOVERY=$(curl -s "https://discovery.etcd.io/new?size=$CLUSTER_SIZE")

handle_channel_release stable current

: ${RAM:=512}
if [ -n "$OPTVAL_RAM" ]; then
  if [[ ! "$OPTVAL_RAM" =~ ^[0-9]+$ ]]; then
    print_red "'$OPTVAL_RAM' is not a valid amount of RAM"
    usage
    exit 1
  fi
  RAM=$OPTVAL_RAM
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

K8S_RELEASE="v1.5.6"
K8S_IMAGE="gcr.io/google_containers/hyperkube:${K8S_RELEASE}"
#K8S_IMAGE="quay.io/coreos/hyperkube:${K8S_RELEASE}_coreos.0"
FLANNEL_TYPE=vxlan

ETCD_ENDPOINTS=""
for SEQ in $(seq 1 $CLUSTER_SIZE); do
  if [ "$SEQ" = "1" ]; then
    ETCD_ENDPOINTS="http://k8s-master:2379"
  else
    NODE_SEQ=$[SEQ-1]
    ETCD_ENDPOINTS="$ETCD_ENDPOINTS,http://k8s-node-$NODE_SEQ:2379"
  fi
done

POD_NETWORK=10.100.0.0/16
SERVICE_IP_RANGE=10.101.0.0/24
K8S_SERVICE_IP=10.101.0.1
DNS_SERVICE_IP=10.101.0.254
K8S_DOMAIN=skydns.local
IMG_NAME="coreos_${CHANNEL}_${RELEASE}_qemu_image.img"
IMG_URL="https://${CHANNEL}.release.core-os.net/amd64-usr/${RELEASE}/coreos_production_qemu_image.img.bz2"
SIG_URL="https://${CHANNEL}.release.core-os.net/amd64-usr/${RELEASE}/coreos_production_qemu_image.img.bz2.sig"
GPG_PUB_KEY="https://coreos.com/security/image-signing-key/CoreOS_Image_Signing_Key.asc"
GPG_PUB_KEY_ID="07F23A2F63D6D4A17F552EF348F9B96A2E16137F"

set +e
if gpg --version > /dev/null 2>&1; then
  GPG=true
  if ! gpg --list-sigs $GPG_PUB_KEY_ID > /dev/null; then
    wget -q -O - $GPG_PUB_KEY | gpg --import --keyid-format LONG || { GPG=false && print_red "Warning: can not import GPG public key"; }
  fi
else
  GPG=false
  print_red "Warning: please install GPG to verify CoreOS images' signatures"
fi
set -e

IMG_EXTENSION=""
if [[ "${IMG_URL}" =~ \.([a-z0-9]+)$ ]]; then
  IMG_EXTENSION=${BASH_REMATCH[1]}
fi

case "${IMG_EXTENSION}" in
  bz2)
    DECOMPRESS="bzcat";;
  xz)
    DECOMPRESS="xzcat";;
  *)
    DECOMPRESS="cat";;
esac

if [ ! -d "$IMG_PATH" ]; then
  mkdir -p "$IMG_PATH" || { print_red "Can not create $IMG_PATH directory" && exit 1; }
fi

if [ ! -f "$MASTER_USER_DATA_TEMPLATE" ]; then
  print_red "$MASTER_USER_DATA_TEMPLATE template doesn't exist"
  exit 1
fi

if [ ! -f "$NODE_USER_DATA_TEMPLATE" ]; then
  print_red "$NODE_USER_DATA_TEMPLATE template doesn't exist"
  exit 1
fi

for SEQ in $(seq 1 $CLUSTER_SIZE); do
  if [ "$SEQ" = "1" ]; then
    VM_HOSTNAME=$MASTER_PREFIX
    COREOS_MASTER_HOSTNAME=$VM_HOSTNAME
    USER_DATA_TEMPLATE=$MASTER_USER_DATA_TEMPLATE
  else
    NODE_SEQ=$[SEQ-1]
    VM_HOSTNAME="${NODE_PREFIX}-$NODE_SEQ"
    USER_DATA_TEMPLATE=$NODE_USER_DATA_TEMPLATE
  fi

  if [ ! -d "$IMG_PATH/$VM_HOSTNAME/$OPENSTACK_DIR" ]; then
    mkdir -p "$IMG_PATH/$VM_HOSTNAME/$OPENSTACK_DIR" || { print_red "Can not create $IMG_PATH/$VM_HOSTNAME/$OPENSTACK_DIR directory" && exit 1; }
    sed "s#%PUB_KEY%#$PUB_KEY#g;\
         s#%HOSTNAME%#$VM_HOSTNAME#g;\
         s#%DISCOVERY%#$ETCD_DISCOVERY#g;\
         s#%RANDOM_PASS%#$RANDOM_PASS#g;\
         s#%MASTER_HOST%#$COREOS_MASTER_HOSTNAME#g;\
         s#%K8S_RELEASE%#$K8S_RELEASE#g;\
         s#%K8S_IMAGE%#$K8S_IMAGE#g;\
         s#%FLANNEL_TYPE%#$FLANNEL_TYPE#g;\
         s#%POD_NETWORK%#$POD_NETWORK#g;\
         s#%SERVICE_IP_RANGE%#$SERVICE_IP_RANGE#g;\
         s#%K8S_SERVICE_IP%#$K8S_SERVICE_IP#g;\
         s#%DNS_SERVICE_IP%#$DNS_SERVICE_IP#g;\
         s#%K8S_DOMAIN%#$K8S_DOMAIN#g;\
         s#%K8S_HOSTPATH_PROVISIONER_MOUNT_POINT%#$K8S_HOSTPATH_PROVISIONER_MOUNT_POINT#g;\
         s#%K8S_AUTO_HOSTPATH_PROVISIONER%#$K8S_AUTO_HOSTPATH_PROVISIONER#g;\
         s#%TECTONIC_LICENSE%#$TECTONIC_LICENSE#g;\
         s#%DOCKER_CFG%#$DOCKER_CFG#g;\
         s#%ETCD_ENDPOINTS%#$ETCD_ENDPOINTS#g" "$USER_DATA_TEMPLATE" > "$IMG_PATH/$VM_HOSTNAME/$OPENSTACK_DIR/user_data"
    make_configdrive
  else
    print_green "'$IMG_PATH/$VM_HOSTNAME/$OPENSTACK_DIR' directory exists, usigng existing data"
    make_configdrive
  fi

  virsh pool-info $OS_NAME > /dev/null 2>&1 || virsh pool-create-as $OS_NAME dir --target "$IMG_PATH" || { print_red "Can not create $OS_NAME pool at $IMG_PATH target" && exit 1; }
  # Make this pool persistent
  (virsh pool-dumpxml $OS_NAME | virsh pool-define /dev/stdin)
  virsh pool-start $OS_NAME > /dev/null 2>&1 || true

  if [ ! -f "$IMG_PATH/$IMG_NAME" ]; then
    trap 'rm -f "$IMG_PATH/$IMG_NAME"' INT TERM EXIT
    if [ "${GPG}" = "true" ]; then
      eval "gpg --enable-special-filenames \
                --verify \
                --batch \
                <(wget -q -O - \"$SIG_URL\")\
                <(wget -O - \"$IMG_URL\" | tee >($DECOMPRESS > \"$IMG_PATH/$IMG_NAME\"))" || { rm -f "$IMG_PATH/$IMG_NAME" && print_red "Failed to download and verify the image" && exit 1; }
    else
      eval "wget \"$IMG_URL\" -O - | $DECOMPRESS > \"$IMG_PATH/$IMG_NAME\"" || { rm -f "$IMG_PATH/$IMG_NAME" && print_red "Failed to download the image" && exit 1; }
    fi
    trap - INT TERM EXIT
    trap
  fi

  if [ ! -f "$IMG_PATH/${VM_HOSTNAME}.qcow2" ]; then
    qemu-img create -f qcow2 -b "$IMG_PATH/$IMG_NAME" "$IMG_PATH/${VM_HOSTNAME}.qcow2" || \
      { print_red "Failed to create ${VM_HOSTNAME}.qcow2 volume image" && exit 1; }
    virsh pool-refresh $OS_NAME
  fi

  eval virt-install \
    --connect $LIBVIRT_DEFAULT_URI \
    --import \
    --name $VM_HOSTNAME \
    --ram $RAM \
    --vcpus $CPUs \
    --os-type=linux \
    --os-variant=virtio26 \
    --disk path="$IMG_PATH/$VM_HOSTNAME.qcow2",format=qcow2,bus=virtio \
    $CONFIG_DRIVE \
    --vnc \
    --noautoconsole \
#    --cpu=host
done

if [ "x${SKIP_SSH_CHECK}" = "x" ]; then
  MAX_SSH_TRIES=50
  MAX_KUBECTL_TRIES=300
  for SEQ in $(seq 1 $CLUSTER_SIZE); do
    if [ "$SEQ" = "1" ]; then
      VM_HOSTNAME=$MASTER_PREFIX
    else
      NODE_SEQ=$[SEQ-1]
      VM_HOSTNAME="${NODE_PREFIX}-$NODE_SEQ"
    fi
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
  print_green "Cluster of $CLUSTER_SIZE $OS_NAME nodes is up and running, waiting for Kubernetes to be ready..."
  for SEQ in $(seq 1 $CLUSTER_SIZE); do
    if [ "$SEQ" = "1" ]; then
      VM_HOSTNAME=$MASTER_PREFIX
    else
      NODE_SEQ=$[SEQ-1]
      VM_HOSTNAME="${NODE_PREFIX}-$NODE_SEQ"
    fi
    TRY=0
    while true; do
      TRY=$((TRY+1))
      if [ $TRY -gt $MAX_KUBECTL_TRIES ]; then
        print_red "Can not verify Kubernetes status, exiting..."
        exit 1
      fi
      echo "Trying to check whether ${VM_HOSTNAME} Kubernetes node is up and running, #${TRY} of #${MAX_KUBECTL_TRIES}..."
      set +e
      RES=$(LANG=en_US ssh -l $SSH_USER -o BatchMode=yes -o ConnectTimeout=1 -o PasswordAuthentication=no -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ${PRIV_KEY_PATH} $MASTER_PREFIX "/opt/bin/kubectl get nodes $VM_HOSTNAME | grep -q Ready" 2>&1)
      RES_CODE=$?
      set -e
      if [ $RES_CODE -eq 0 ]; then
        break
      else
        sleep 1
      fi
    done
  done
  print_green "Kubernetes cluster is up and running..."
fi

print_green "Use following command to connect to your cluster: 'ssh -i \"$PRIV_KEY_PATH\" core@$COREOS_MASTER_HOSTNAME'"

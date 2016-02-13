#!/bin/bash -e

usage() {
  echo "Usage: $0 %cluster_size% [%pub_key_path%]"
}

print_green() {
  echo -e "\e[92m$1\e[0m"
}

if [ "$1" == "" ]; then
  echo "Cluster size is empty"
  usage
  exit 1
fi

if ! [[ $1 =~ ^[0-9]+$ ]]; then
  echo "'$1' is not a number"
  usage
  exit 1
fi

if [[ -z $2 || ! -f $2 ]]; then
  echo "SSH public key path is not specified"
  if [ -n $HOME ]; then
        PUB_KEY_PATH="$HOME/.ssh/id_rsa.pub"
  else
        echo "Can not determine home directory for SSH pub key path"
        exit 1
  fi

  print_green "Will use default path to SSH public key: $PUB_KEY_PATH"
  if [ ! -f $PUB_KEY_PATH ]; then
        echo "Path $PUB_KEY_PATH doesn't exist"
        exit 1
  fi
else
  PUB_KEY_PATH=$2
  print_green "Will use this path to SSH public key: $PUB_KEY_PATH"
fi

OS_NAME="coreos"
PUB_KEY=$(cat ${PUB_KEY_PATH})
PRIV_KEY_PATH=$(echo ${PUB_KEY_PATH} | sed 's#.pub##')
CDIR=$(cd `dirname $0` && pwd)
IMG_PATH=/var/lib/libvirt/images/${OS_NAME}
RANDOM_PASS=$(openssl rand -base64 12)
USER_DATA_TEMPLATE=${CDIR}/user_data
ETCD_DISCOVERY=$(curl -s "https://discovery.etcd.io/new?size=$1")
CHANNEL=alpha
#CHANNEL=beta
#CHANNEL=stable
RELEASE=current
#RELEASE=899.1.0
#RELEASE=681.2.0
RAM=512
CPUs=1
IMG_NAME="coreos_${CHANNEL}_${RELEASE}_qemu_image.img"
IMG_URL="http://${CHANNEL}.release.core-os.net/amd64-usr/${RELEASE}/coreos_production_qemu_image.img.bz2"

if [ ! -d $IMG_PATH ]; then
  mkdir -p $IMG_PATH || (echo "Can not create $IMG_PATH directory" && exit 1)
fi

if [ ! -f $USER_DATA_TEMPLATE ]; then
  echo "$USER_DATA_TEMPLATE template doesn't exist"
  exit 1
fi

for SEQ in $(seq 1 $1); do
  VM_HOSTNAME="${OS_NAME}${SEQ}"
  if [ -z $FIRST_HOST ]; then
    FIRST_HOST=$VM_HOSTNAME
  fi

  if [ ! -d $IMG_PATH/$VM_HOSTNAME/openstack/latest ]; then
    mkdir -p $IMG_PATH/$VM_HOSTNAME/openstack/latest || (echo "Can not create $IMG_PATH/$VM_HOSTNAME/openstack/latest directory" && exit 1)
  fi

  if [ ! -f $IMG_PATH/$IMG_NAME ]; then
    wget $IMG_URL -O - | bzcat > $IMG_PATH/$IMG_NAME || (rm -f $IMG_PATH/$IMG_NAME && echo "Failed to download image" && exit 1)
  fi

  if [ ! -f $IMG_PATH/$VM_HOSTNAME.qcow2 ]; then
    qemu-img create -f qcow2 -b $IMG_PATH/$IMG_NAME $IMG_PATH/$VM_HOSTNAME.qcow2
  fi

  sed "s#%PUB_KEY%#$PUB_KEY#g;\
       s#%HOSTNAME%#$VM_HOSTNAME#g;\
       s#%DISCOVERY%#$ETCD_DISCOVERY#g;\
       s#%RANDOM_PASS%#$RANDOM_PASS#g;\
       s#%FIRST_HOST%#$FIRST_HOST#g" $USER_DATA_TEMPLATE > $IMG_PATH/$VM_HOSTNAME/openstack/latest/user_data

  if [[ $(selinuxenabled 2>/dev/null) ]]; then
    echo "Making SELinux configuration"
    semanage fcontext -d -t virt_content_t "$IMG_PATH/$VM_HOSTNAME(/.*)?" || true
    semanage fcontext -a -t virt_content_t "$IMG_PATH/$VM_HOSTNAME(/.*)?"
    restorecon -R "$IMG_PATH"
  fi

  virt-install \
    --connect qemu:///system \
    --import \
    --name $VM_HOSTNAME \
    --ram $RAM \
    --vcpus $CPUs \
    --os-type=linux \
    --os-variant=virtio26 \
    --disk path=$IMG_PATH/$VM_HOSTNAME.qcow2,format=qcow2,bus=virtio \
    --filesystem $IMG_PATH/$VM_HOSTNAME/,config-2,type=mount,mode=squash \
    --vnc \
    --noautoconsole \
#    --cpu=host
done

print_green "Use this command to connect to your cluster: 'ssh -i $PRIV_KEY_PATH core@$FIRST_HOST'"

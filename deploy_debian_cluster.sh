#!/bin/bash -e

usage() {
  echo "Usage: $0 %cluster_size% [%pub_key_path%]"
}

print_green() {
  echo -e "\e[92m$1\e[0m"
}

export LIBVIRT_DEFAULT_URI=qemu:///system

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

OS_NAME="debian"
PUB_KEY=$(cat ${PUB_KEY_PATH})
PRIV_KEY_PATH=$(echo ${PUB_KEY_PATH} | sed 's#.pub##')
CDIR=$(cd `dirname $0` && pwd)
IMG_PATH=/var/lib/libvirt/images/${OS_NAME}
CHANNEL=8.3.0
RELEASE=current
RAM=512
CPUs=1
IMG_NAME="${OS_NAME}_${CHANNEL}_${RELEASE}_qemu_image.img"
IMG_URL="http://cdimage.debian.org/cdimage/openstack/${RELEASE}/debian-${CHANNEL}-openstack-amd64.qcow2"

if [ ! -d $IMG_PATH ]; then
  mkdir -p $IMG_PATH || (echo "Can not create $IMG_PATH directory" && exit 1)
fi

CC="#cloud-config
password: passw0rd
chpasswd: { expire: False }
ssh_pwauth: True
users:
  - default:
    ssh-authorized-keys:
      - '${PUB_KEY}'
runcmd:
  - service networking restart
"

for SEQ in $(seq 1 $1); do
  VM_HOSTNAME="${OS_NAME}${SEQ}"
  if [ -z $FIRST_HOST ]; then
    FIRST_HOST=$VM_HOSTNAME
  fi

  if [ ! -d $IMG_PATH/$VM_HOSTNAME ]; then
    mkdir -p $IMG_PATH/$VM_HOSTNAME || (echo "Can not create $IMG_PATH/$VM_HOSTNAME directory" && exit 1)
  fi

  if [ ! -f $IMG_PATH/$IMG_NAME ]; then
    wget $IMG_URL -O - > $IMG_PATH/$IMG_NAME || (rm -f $IMG_PATH/$IMG_NAME && echo "Failed to download image" && exit 1)
  fi

  if [ ! -f $IMG_PATH/$VM_HOSTNAME.qcow2 ]; then
    qemu-img create -f qcow2 -b $IMG_PATH/$IMG_NAME $IMG_PATH/$VM_HOSTNAME.qcow2
  fi

  echo "$CC" > $IMG_PATH/$VM_HOSTNAME/user-data
  echo -e "instance-id: iid-${VM_HOSTNAME}\nlocal-hostname: ${VM_HOSTNAME}\nhostname: ${VM_HOSTNAME}" > $IMG_PATH/$VM_HOSTNAME/meta-data

  genisoimage \
    -input-charset utf-8 \
    -output $IMG_PATH/$VM_HOSTNAME/cidata.iso \
    -volid cidata \
    -joliet \
    -rock \
    $IMG_PATH/$VM_HOSTNAME/user-data \
    $IMG_PATH/$VM_HOSTNAME/meta-data || (echo "Failed to create ISO images"; exit 1)

  virt-install \
    --connect qemu:///system \
    --import \
    --name $VM_HOSTNAME \
    --ram $RAM \
    --vcpus $CPUs \
    --os-type=linux \
    --os-variant=virtio26 \
    --disk path=$IMG_PATH/$VM_HOSTNAME.qcow2,format=qcow2,bus=virtio \
    --disk path=$IMG_PATH/$VM_HOSTNAME/cidata.iso,device=cdrom \
    --vnc \
    --noautoconsole \
#    --cpu=host
done

print_green "Use this command to connect to your cluster: 'ssh -i $PRIV_KEY_PATH ${OS_NAME}@$FIRST_HOST'"

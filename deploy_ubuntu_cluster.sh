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

PUB_KEY=$(cat ${PUB_KEY_PATH})
PRIV_KEY_PATH=$(echo ${PUB_KEY_PATH} | sed 's#.pub##')
CDIR=$(cd `dirname $0` && pwd)
LIBVIRT_UBUNTU=/var/lib/libvirt/images/ubuntu
#CHANNEL=trusty
CHANNEL=vivid
CHANNEL=wily
RELEASE=current
RAM=512
CPUs=1
IMG_NAME="ubuntu_${CHANNEL}_${RELEASE}_qemu_image.img"

if [ ! -d $LIBVIRT_UBUNTU ]; then
  mkdir -p $LIBVIRT_UBUNTU || (echo "Can not create $LIBVIRT_UBUNTU directory" && exit 1)
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
  UBUNTU_HOSTNAME="ubuntu$SEQ"
  if [ -z $FIRST_HOST ]; then
    FIRST_HOST=$UBUNTU_HOSTNAME
  fi

  if [ ! -d $LIBVIRT_UBUNTU/$UBUNTU_HOSTNAME ]; then
    mkdir -p $LIBVIRT_UBUNTU/$UBUNTU_HOSTNAME || (echo "Can not create $LIBVIRT_UBUNTU/$UBUNTU_HOSTNAME directory" && exit 1)
  fi

  if [ ! -f $LIBVIRT_UBUNTU/$IMG_NAME ]; then
    wget https://cloud-images.ubuntu.com/daily/server/${CHANNEL}/${RELEASE}/${CHANNEL}-server-cloudimg-amd64-disk1.img -O - > $LIBVIRT_UBUNTU/$IMG_NAME || (rm -f $LIBVIRT_UBUNTU/$IMG_NAME && echo "Failed to download image" && exit 1)
  fi

  if [ ! -f $LIBVIRT_UBUNTU/$UBUNTU_HOSTNAME.qcow2 ]; then
    qemu-img create -f qcow2 -b $LIBVIRT_UBUNTU/$IMG_NAME $LIBVIRT_UBUNTU/$UBUNTU_HOSTNAME.qcow2
  fi

  echo "$CC" > $LIBVIRT_UBUNTU/$UBUNTU_HOSTNAME/user-data
  echo -e "instance-id: iid-${UBUNTU_HOSTNAME}\nlocal-hostname: ${UBUNTU_HOSTNAME}" > $LIBVIRT_UBUNTU/$UBUNTU_HOSTNAME/meta-data

  genisoimage \
    -input-charset utf-8 \
    -output $LIBVIRT_UBUNTU/$UBUNTU_HOSTNAME/cidata.iso \
    -volid cidata \
    -joliet \
    -rock \
    $LIBVIRT_UBUNTU/$UBUNTU_HOSTNAME/user-data \
    $LIBVIRT_UBUNTU/$UBUNTU_HOSTNAME/meta-data || (echo "Failed to create ISO images"; exit 1)

  virt-install \
    --connect qemu:///system \
    --import \
    --name $UBUNTU_HOSTNAME \
    --ram $RAM \
    --vcpus $CPUs \
    --os-type=linux \
    --os-variant=virtio26 \
    --disk path=$LIBVIRT_UBUNTU/$UBUNTU_HOSTNAME.qcow2,format=qcow2,bus=virtio \
    --disk path=$LIBVIRT_UBUNTU/$UBUNTU_HOSTNAME/cidata.iso,device=cdrom \
    --vnc \
    --noautoconsole
done

print_green "Use this command to connect to your cluster: 'ssh -i $PRIV_KEY_PATH ubuntu@$FIRST_HOST'"

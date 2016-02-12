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
LIBVIRT_CENTOS=/var/lib/libvirt/images/centos
RELEASE=6
RELEASE=7
RAM=512
CPUs=1
IMG_NAME="CentOS-${RELEASE}-x86_64-GenericCloud.img"

if [ ! -d $LIBVIRT_CENTOS ]; then
  mkdir -p $LIBVIRT_CENTOS || (echo "Can not create $LIBVIRT_CENTOS directory" && exit 1)
fi

CC="#cloud-config
password: passw0rd
chpasswd: { expire: False }
ssh_pwauth: True
users:
  - default:
    ssh-authorized-keys:
      - '${PUB_KEY}'
bootcmd:
  - echo 'DHCP_HOSTNAME=\${HOSTNAME}' >> /etc/sysconfig/network
runcmd:
  - service network restart
"

for SEQ in $(seq 1 $1); do
  CENTOS_HOSTNAME="centos$SEQ"
  if [ -z $FIRST_HOST ]; then
    FIRST_HOST=$CENTOS_HOSTNAME
  fi

  if [ ! -d $LIBVIRT_CENTOS/$CENTOS_HOSTNAME ]; then
    mkdir -p $LIBVIRT_CENTOS/$CENTOS_HOSTNAME || (echo "Can not create $LIBVIRT_CENTOS/$CENTOS_HOSTNAME directory" && exit 1)
  fi

  if [ ! -f $LIBVIRT_CENTOS/$IMG_NAME ]; then
    wget http://cloud.centos.org/centos/${RELEASE}/images/CentOS-${RELEASE}-x86_64-GenericCloud.qcow2.xz -O - | xzcat > $LIBVIRT_CENTOS/$IMG_NAME || (rm -f $LIBVIRT_CENTOS/$IMG_NAME && echo "Failed to download image" && exit 1)
  fi

  if [ ! -f $LIBVIRT_CENTOS/$CENTOS_HOSTNAME.qcow2 ]; then
    qemu-img create -f qcow2 -b $LIBVIRT_CENTOS/$IMG_NAME $LIBVIRT_CENTOS/$CENTOS_HOSTNAME.qcow2
  fi

  echo "$CC" > $LIBVIRT_CENTOS/$CENTOS_HOSTNAME/user-data
  echo -e "instance-id: iid-${CENTOS_HOSTNAME}\nlocal-hostname: ${CENTOS_HOSTNAME}\nhostname: ${CENTOS_HOSTNAME}" > $LIBVIRT_CENTOS/$CENTOS_HOSTNAME/meta-data

  genisoimage \
    -input-charset utf-8 \
    -output $LIBVIRT_CENTOS/$CENTOS_HOSTNAME/cidata.iso \
    -volid cidata \
    -joliet \
    -rock \
    $LIBVIRT_CENTOS/$CENTOS_HOSTNAME/user-data \
    $LIBVIRT_CENTOS/$CENTOS_HOSTNAME/meta-data || (echo "Failed to create ISO images"; exit 1)

  virt-install \
    --connect qemu:///system \
    --import \
    --name $CENTOS_HOSTNAME \
    --ram $RAM \
    --vcpus $CPUs \
    --os-type=linux \
    --os-variant=virtio26 \
    --disk path=$LIBVIRT_CENTOS/$CENTOS_HOSTNAME.qcow2,format=qcow2,bus=virtio \
    --disk path=$LIBVIRT_CENTOS/$CENTOS_HOSTNAME/cidata.iso,device=cdrom \
    --vnc \
    --noautoconsole
done

print_green "Use this command to connect to your cluster: 'ssh -i $PRIV_KEY_PATH centos@$FIRST_HOST'"

#!/bin/bash -e

usage() {
  echo "Usage: $0 %cluster_size%"
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
bootcmd:
  - echo 'DHCP_HOSTNAME=\${HOSTNAME}' >> /etc/sysconfig/network
runcmd:
  - service network restart
"

for SEQ in $(seq 1 $1); do
  CENTOS_HOSTNAME="centos$SEQ"

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

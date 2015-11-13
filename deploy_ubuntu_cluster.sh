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

LIBVIRT_UBUNTU=/var/lib/libvirt/images/ubuntu
#CHANNEL=trusty
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
packages:
 - ifenslave
write_files:
-   content: |
      auto eth0
      iface eth0 inet manual
          bond-master bond0
      auto eth1
      iface eth1 inet manual
          bond-master bond0
      auto bond0
      iface bond0 inet dhcp
          pre-up ip addr flush dev eth0
          pre-up ip addr flush dev eth1
          slaves eth0 eth1
          bond-mode balance-rr
          bond-miimon 100
          bond-downdelay 200
          bond-updelay 200
    path: /etc/network/interfaces.d/eth0.cfg
    permissions: '0644'
runcmd:
 - service networking restart
"

for SEQ in $(seq 1 $1); do
        UBUNTU_HOSTNAME="ubuntu$SEQ"

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

	genisoimage -input-charset utf-8 -output $LIBVIRT_UBUNTU/$UBUNTU_HOSTNAME/cidata.iso -volid cidata -joliet -rock $LIBVIRT_UBUNTU/$UBUNTU_HOSTNAME/user-data $LIBVIRT_UBUNTU/$UBUNTU_HOSTNAME/meta-data || (echo "Failed to create ISO images"; exit 1)

        virt-install --connect qemu:///system --import --name $UBUNTU_HOSTNAME --ram $RAM --vcpus $CPUs --os-type=linux --os-variant=virtio26 --network=network:default --network=network:default --disk path=$LIBVIRT_UBUNTU/$UBUNTU_HOSTNAME.qcow2,format=qcow2,bus=virtio --disk path=$LIBVIRT_UBUNTU/$UBUNTU_HOSTNAME/cidata.iso,device=cdrom --vnc --noautoconsole

done

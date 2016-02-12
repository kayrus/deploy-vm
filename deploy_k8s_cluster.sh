#!/bin/bash -e

usage() {
  echo "Usage: $0 %k8s_cluster_size%"
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

if [[ "$1" -lt "2" ]]; then
  echo "'$1' is lower than 2 (minimal k8s cluster size)"
  usage
  exit 1
fi

LIBVIRT_PATH=/var/lib/libvirt/images/coreos
MASTER_USER_DATA_TEMPLATE=$LIBVIRT_PATH/k8s_master_user_data
NODE_USER_DATA_TEMPLATE=$LIBVIRT_PATH/k8s_node_user_data
ETCD_DISCOVERY=$(curl -s "https://discovery.etcd.io/new?size=$1")
CHANNEL=stable
K8S_RELEASE=v1.0.2
FLANNEL_TYPE=vxlan
K8S_NET=10.100.0.0/16
K8S_DNS=10.100.0.254
K8S_DOMAIN=skydns.local
RAM=512
CPUs=1

if [ ! -d $LIBVIRT_PATH ]; then
  mkdir -p $LIBVIRT_PATH || (echo "Can not create $LIBVIRT_PATH directory" && exit 1)
fi

if [ ! -f $MASTER_USER_DATA_TEMPLATE ]; then
  echo "$MASTER_USER_DATA_TEMPLATE template doesn't exist"
  exit 1
fi

if [ ! -f $NODE_USER_DATA_TEMPLATE ]; then
  echo "$NODE_USER_DATA_TEMPLATE template doesn't exist"
  exit 1
fi

for SEQ in $(seq 1 $1); do
  if [ "$SEQ" == "1" ]; then
    COREOS_HOSTNAME="k8s-master"
    COREOS_MASTER_HOSTNAME=$COREOS_HOSTNAME
    USER_DATA_TEMPLATE=$MASTER_USER_DATA_TEMPLATE
  else
    NODE_SEQ=$[SEQ-1]
    COREOS_HOSTNAME="k8s-node-$NODE_SEQ"
    USER_DATA_TEMPLATE=$NODE_USER_DATA_TEMPLATE
  fi

  if [ ! -d $LIBVIRT_PATH/$COREOS_HOSTNAME/openstack/latest ]; then
    mkdir -p $LIBVIRT_PATH/$COREOS_HOSTNAME/openstack/latest || (echo "Can not create $LIBVIRT_PATH/$COREOS_HOSTNAME/openstack/latest directory" && exit 1)
  fi

  if [ ! -f $LIBVIRT_PATH/coreos_${CHANNEL}_qemu_image.img ]; then
    wget http://${CHANNEL}.release.core-os.net/amd64-usr/current/coreos_production_qemu_image.img.bz2 -O - | bzcat > $LIBVIRT_PATH/coreos_${CHANNEL}_qemu_image.img
  fi

  if [ ! -f $LIBVIRT_PATH/$COREOS_HOSTNAME.qcow2 ]; then
    qemu-img create -f qcow2 -b $LIBVIRT_PATH/coreos_${CHANNEL}_qemu_image.img $LIBVIRT_PATH/$COREOS_HOSTNAME.qcow2
  fi

  sed "s#%DISCOVERY%#$ETCD_DISCOVERY#g;\
       s#%HOSTNAME%#$COREOS_HOSTNAME#g;\
       s#%MASTER_HOST%#$COREOS_MASTER_HOSTNAME#g;\
       s#%K8S_RELEASE%#$K8S_RELEASE#g;\
       s#%FLANNEL_TYPE%#$FLANNEL_TYPE#g;\
       s#%K8S_NET%#$K8S_NET#g;\
       s#%K8S_DNS%#$K8S_DNS#g;\
       s#%K8S_DOMAIN%#$K8S_DOMAIN#g" $USER_DATA_TEMPLATE > $LIBVIRT_PATH/$COREOS_HOSTNAME/openstack/latest/user_data

  if [[ selinuxenabled ]]; then
    echo "Making SELinux configuration"
    semanage fcontext -a -t virt_content_t "$LIBVIRT_PATH/$COREOS_HOSTNAME(/.*)?"
    restorecon -R "$LIBVIRT_PATH"
  fi

  virt-install \
    --connect qemu:///system \
    --import \
    --name $COREOS_HOSTNAME \
    --ram $RAM \
    --vcpus $CPUs \
    --os-type=linux \
    --os-variant=virtio26 \
    --disk path=$LIBVIRT_PATH/$COREOS_HOSTNAME.qcow2,format=qcow2,bus=virtio \
    --filesystem $LIBVIRT_PATH/$COREOS_HOSTNAME/,config-2,type=mount,mode=squash \
    --vnc \
    --noautoconsole
done

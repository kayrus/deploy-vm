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

if [[ "$1" -lt "2" ]]; then
  echo "'$1' is lower than 2 (minimal k8s cluster size)"
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
LIBVIRT_PATH=/var/lib/libvirt/images/coreos
RANDOM_PASS=$(openssl rand -base64 12)
MASTER_USER_DATA_TEMPLATE=${CDIR}/k8s_master_user_data
NODE_USER_DATA_TEMPLATE=${CDIR}/k8s_node_user_data
ETCD_DISCOVERY=$(curl -s "https://discovery.etcd.io/new?size=$1")
CHANNEL=alpha
RELEASE=current
K8S_RELEASE=v1.1.7
FLANNEL_TYPE=vxlan
K8S_NET=10.100.0.0/16
K8S_DNS=10.100.0.254
K8S_DOMAIN=skydns.local
RAM=512
CPUs=1
IMG_NAME="coreos_${CHANNEL}_${RELEASE}_qemu_image.img"

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

  if [ ! -f $LIBVIRT_PATH/$IMG_NAME ]; then
    wget http://${CHANNEL}.release.core-os.net/amd64-usr/${RELEASE}/coreos_production_qemu_image.img.bz2 -O - | bzcat > $LIBVIRT_PATH/$IMG_NAME || (rm -f $LIBVIRT_PATH/$IMG_NAME && echo "Failed to download image" && exit 1)
  fi

  if [ ! -f $LIBVIRT_PATH/$COREOS_HOSTNAME.qcow2 ]; then
    qemu-img create -f qcow2 -b $LIBVIRT_PATH/$IMG_NAME $LIBVIRT_PATH/$COREOS_HOSTNAME.qcow2
  fi

  sed "s#%PUB_KEY%#$PUB_KEY#g;\
       s#%HOSTNAME%#$COREOS_HOSTNAME#g;\
       s#%DISCOVERY%#$ETCD_DISCOVERY#g;\
       s#%RANDOM_PASS%#$RANDOM_PASS#g;\
       s#%MASTER_HOST%#$COREOS_MASTER_HOSTNAME#g;\
       s#%K8S_RELEASE%#$K8S_RELEASE#g;\
       s#%FLANNEL_TYPE%#$FLANNEL_TYPE#g;\
       s#%K8S_NET%#$K8S_NET#g;\
       s#%K8S_DNS%#$K8S_DNS#g;\
       s#%K8S_DOMAIN%#$K8S_DOMAIN#g" $USER_DATA_TEMPLATE > $LIBVIRT_PATH/$COREOS_HOSTNAME/openstack/latest/user_data

  if [[ selinuxenabled ]]; then
    echo "Making SELinux configuration"
    semanage fcontext -d -t virt_content_t "$LIBVIRT_PATH/$COREOS_HOSTNAME(/.*)?" || true
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

print_green "Use this command to connect to your cluster: 'ssh -i $PRIV_KEY_PATH core@$COREOS_MASTER_HOSTNAME'"

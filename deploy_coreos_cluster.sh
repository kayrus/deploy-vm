#!/bin/bash -e

usage() {
  echo "Usage: $0 %cluster_size% [%pub_key_path%]"
}

print_green() {
  echo -e "\e[92m$1\e[0m"
}

OS_NAME="coreos"

export LIBVIRT_DEFAULT_URI=qemu:///system
virsh nodeinfo > /dev/null 2>&1 || (echo "Failed to connect to the libvirt socket"; exit 1)
virsh list --all --name | grep -q "^${OS_NAME}1$" && (echo "'${OS_NAME}1' VM already exists"; exit 1)

USER_ID=${SUDO_UID:-$(id -u)}
USER=$(getent passwd "${USER_ID}" | cut -d: -f1)
HOME=$(getent passwd "${USER_ID}" | cut -d: -f6)

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
    PRIV_KEY_PATH=$(echo ${PUB_KEY_PATH} | sed 's#.pub##')
    if [ -f $PRIV_KEY_PATH ]; then
      echo "Found private key, generating public key..."
      sudo -u $USER ssh-keygen -y -f $PRIV_KEY_PATH | sudo -u $USER tee ${PUB_KEY_PATH} > /dev/null
    else
      echo "Generating private and public keys..."
      sudo -u $USER ssh-keygen -t rsa -N "" -f $PRIV_KEY_PATH
    fi
  fi
else
  PUB_KEY_PATH=$2
  print_green "Will use this path to SSH public key: $PUB_KEY_PATH"
fi

PUB_KEY=$(cat ${PUB_KEY_PATH})
PRIV_KEY_PATH=$(echo ${PUB_KEY_PATH} | sed 's#.pub##')
CDIR=$(cd `dirname $0` && pwd)
IMG_PATH=${HOME}/.libvirt/${OS_NAME}
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

IMG_EXTENSION=""
if [[ "${IMG_URL}" =~ \.([a-z0-9]+)$ ]]; then
  IMG_EXTENSION=${BASH_REMATCH[1]}
fi

case "${IMG_EXTENSION}" in
  bz2)
    DECOMPRESS="| bzcat";;
  xz)
    DECOMPRESS="| xzcat";;
  *)
    DECOMPRESS="";;
esac

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
    sed "s#%PUB_KEY%#$PUB_KEY#g;\
         s#%HOSTNAME%#$VM_HOSTNAME#g;\
         s#%DISCOVERY%#$ETCD_DISCOVERY#g;\
         s#%RANDOM_PASS%#$RANDOM_PASS#g;\
         s#%FIRST_HOST%#$FIRST_HOST#g" $USER_DATA_TEMPLATE > $IMG_PATH/$VM_HOSTNAME/openstack/latest/user_data
    if [ -n $(selinuxenabled 2>/dev/null || echo "SELinux") ]; then
      # We use ISO configdrive to avoid complicated SELinux conditions
      mkisofs -input-charset utf-8 -R -V config-2 -o $IMG_PATH/$VM_HOSTNAME/configdrive.iso $IMG_PATH/$VM_HOSTNAME || (echo "Failed to create ISO image"; exit 1)
      CONFIG_DRIVE="--disk path=$IMG_PATH/$VM_HOSTNAME/configdrive.iso,device=cdrom"
    else
      CONFIG_DRIVE="--filesystem $IMG_PATH/$VM_HOSTNAME/,config-2,type=mount,mode=squash"
    fi
  fi

  virsh pool-info $OS_NAME > /dev/null 2>&1 || virsh pool-create-as $OS_NAME dir --target $IMG_PATH || (echo "Can not create $OS_NAME pool at $IMG_PATH target" && exit 1)

  if [ ! -f $IMG_PATH/$IMG_NAME ]; then
    eval "wget $IMG_URL -O - $DECOMPRESS > $IMG_PATH/$IMG_NAME" || (rm -f $IMG_PATH/$IMG_NAME && echo "Failed to download image" && exit 1)
  fi

  if [ ! -f $IMG_PATH/${VM_HOSTNAME}.qcow2 ]; then
    virsh pool-refresh $OS_NAME
    virsh vol-create-as --pool $OS_NAME --name ${VM_HOSTNAME}.qcow2 --capacity 10G --format qcow2 --backing-vol $IMG_NAME --backing-vol-format qcow2 || (echo "Failed to create ${VM_HOSTNAME}.qcow2 volume image" && exit 1)
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
    $CONFIG_DRIVE \
    --vnc \
    --noautoconsole \
#    --cpu=host
done

print_green "Use this command to connect to your cluster: 'ssh -i $PRIV_KEY_PATH core@$FIRST_HOST'"

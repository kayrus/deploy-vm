#!/bin/bash -e

print_green() {
  echo -e "\e[92m$1\e[0m"
}

usage() {
  echo "Usage: $0 %os_name% %cluster_size% [%pub_key_path%]"
  echo "  Supported OS:"
  print_green "    * centos"
  print_green "    * ubuntu"
  print_green "    * debian"
  print_green "    * fedora"
}

if [ "$1" == "" ]; then
  usage
  exit 1
fi

OS_NAME="$1"

case "$1" in
  coreos)
    echo "Use ./deploy_coreos_cluster.sh script"
    exit 1
    ;;
  centos)
    BOOT_HOOK="bootcmd:
  - echo 'DHCP_HOSTNAME=\${HOSTNAME}' >> /etc/sysconfig/network
runcmd:
  - service network restart"
    RELEASE=7
    IMG_NAME="CentOS-${RELEASE}-x86_64-GenericCloud.img"
    IMG_URL="http://cloud.centos.org/centos/${RELEASE}/images/CentOS-${RELEASE}-x86_64-GenericCloud.qcow2.xz"
    ;;
  fedora)
    BOOT_HOOK="bootcmd:
  - echo 'DHCP_HOSTNAME=\${HOSTNAME}' >> /etc/sysconfig/network
runcmd:
  - service network restart"
    CHANNEL=23
    RELEASE=20151030
    IMG_NAME="Fedora-Cloud-Base-${CHANNEL}-${RELEASE}.x86_64.qcow2"
    IMG_URL="https://download.fedoraproject.org/pub/fedora/linux/releases/${CHANNEL}/Cloud/x86_64/Images/Fedora-Cloud-Base-${CHANNEL}-${RELEASE}.x86_64.qcow2"
    ;;
  debian)
    BOOT_HOOK="runcmd:
  - service networking restart"
    CHANNEL=8.3.0
    RELEASE=current
    IMG_NAME="${OS_NAME}_${CHANNEL}_${RELEASE}_qemu_image.img"
    IMG_URL="http://cdimage.debian.org/cdimage/openstack/${RELEASE}/debian-${CHANNEL}-openstack-amd64.qcow2"
    ;;
  ubuntu)
    BOOT_HOOK="runcmd:
  - service networking restart"
    CHANNEL=xenial
    RELEASE=current
    IMG_NAME="ubuntu_${CHANNEL}_${RELEASE}_qemu_image.img"
    IMG_URL="https://cloud-images.ubuntu.com/daily/server/${CHANNEL}/${RELEASE}/${CHANNEL}-server-cloudimg-amd64-disk1.img"
    ;;
  *)
    echo "'$1' OS is not supported"
    usage
    exit 1
    ;;
esac

export LIBVIRT_DEFAULT_URI=qemu:///system
virsh nodeinfo > /dev/null 2>&1 || (echo "Failed to connect to the libvirt socket"; exit 1)
virsh list --all --name | grep -q "^${OS_NAME}1$" && (echo "'${OS_NAME}1' VM already exists"; exit 1)

USER_ID=${SUDO_UID:-$(id -u)}
USER=$(getent passwd "${USER_ID}" | cut -d: -f1)
HOME=$(getent passwd "${USER_ID}" | cut -d: -f6)

if [ "$2" == "" ]; then
  echo "Cluster size is empty"
  usage
  exit 1
fi

if ! [[ $2 =~ ^[0-9]+$ ]]; then
  echo "'$2' is not a number"
  usage
  exit 1
fi

if [[ -z $3 || ! -f $3 ]]; then
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
  PUB_KEY_PATH=$3
  print_green "Will use this path to SSH public key: $PUB_KEY_PATH"
fi

PUB_KEY=$(cat ${PUB_KEY_PATH})
PRIV_KEY_PATH=$(echo ${PUB_KEY_PATH} | sed 's#.pub##')
CDIR=$(cd `dirname $0` && pwd)
IMG_PATH=${HOME}/libvirt_images/${OS_NAME}
RAM=512
CPUs=1

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

CC="#cloud-config
password: passw0rd
chpasswd: { expire: False }
ssh_pwauth: True
users:
  - default:
    ssh-authorized-keys:
      - '${PUB_KEY}'
${BOOT_HOOK}
"

for SEQ in $(seq 1 $2); do
  VM_HOSTNAME="${OS_NAME}${SEQ}"
  if [ -z $FIRST_HOST ]; then
    FIRST_HOST=$VM_HOSTNAME
  fi

  if [ ! -d $IMG_PATH/$VM_HOSTNAME ]; then
    mkdir -p $IMG_PATH/$VM_HOSTNAME || (echo "Can not create $IMG_PATH/$VM_HOSTNAME directory" && exit 1)
  fi

  virsh pool-info $OS_NAME > /dev/null 2>&1 || virsh pool-create-as $OS_NAME dir --target $IMG_PATH || (echo "Can not create $OS_NAME pool at $IMG_PATH target" && exit 1)

  if [ ! -f $IMG_PATH/$IMG_NAME ]; then
    eval "wget $IMG_URL -O - $DECOMPRESS > $IMG_PATH/$IMG_NAME" || (rm -f $IMG_PATH/$IMG_NAME && echo "Failed to download image" && exit 1)
  fi

  if [ ! -f $IMG_PATH/${VM_HOSTNAME}.qcow2 ]; then
    virsh pool-refresh $OS_NAME
    virsh vol-create-as --pool $OS_NAME --name ${VM_HOSTNAME}.qcow2 --capacity 10G --format qcow2 --backing-vol $IMG_NAME --backing-vol-format qcow2 || \
      qemu-img create -f qcow2 -b $IMG_PATH/$IMG_NAME $IMG_PATH/${VM_HOSTNAME}.qcow2 || \
      (echo "Failed to create ${VM_HOSTNAME}.qcow2 volume image" && exit 1)
    virsh pool-refresh $OS_NAME
  fi

  echo "$CC" > $IMG_PATH/$VM_HOSTNAME/user-data
  echo -e "instance-id: iid-${VM_HOSTNAME}\nlocal-hostname: ${VM_HOSTNAME}\nhostname: ${VM_HOSTNAME}" > $IMG_PATH/$VM_HOSTNAME/meta-data

  mkisofs \
    -input-charset utf-8 \
    -output $IMG_PATH/$VM_HOSTNAME/cidata.iso \
    -volid cidata \
    -joliet \
    -rock \
    $IMG_PATH/$VM_HOSTNAME/user-data \
    $IMG_PATH/$VM_HOSTNAME/meta-data || (echo "Failed to create ISO image"; exit 1)
  virsh pool-refresh $OS_NAME

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

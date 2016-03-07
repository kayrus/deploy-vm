#!/bin/bash -e

print_green() {
  echo -e "\e[92m$1\e[0m"
}

usage() {
  echo "Usage: $0 %os_name% %cluster_size% [%pub_key_path%]"
  echo "  Supported OS:"
  print_green "    * centos"
  print_green "    * atomic-centos"
  print_green "    * atomic-fedora"
  print_green "    * clearlinux (not yet supported)"
  print_green "    * ubuntu"
  print_green "    * ubuntu-core (not yet supported)"
  print_green "    * debian"
  print_green "    * fedora"
  print_green "    * windows"
  print_green "    * freebsd"
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
  atomic-centos)
    BOOT_HOOK="bootcmd:
  - echo 'DHCP_HOSTNAME=\${HOSTNAME}' >> /etc/sysconfig/network
runcmd:
  - systemctl restart NetworkManager"
    RELEASE=7
    SSH_USER=centos
    IMG_NAME="CentOS-Atomic-Host-${RELEASE}-GenericCloud.qcow2"
    IMG_URL="http://cloud.centos.org/centos/${RELEASE}/atomic/images/CentOS-Atomic-Host-${RELEASE}-GenericCloud.qcow2.xz"
    ;;
  atomic-fedora)
    BOOT_HOOK="bootcmd:
  - echo 'DHCP_HOSTNAME=\${HOSTNAME}' >> /etc/sysconfig/network
runcmd:
  - systemctl restart NetworkManager"
    CHANNEL=23
    RELEASE=20160223
    SSH_USER=fedora
    IMG_NAME="CentOS-Atomic-Host-${RELEASE}-GenericCloud.qcow2"
    IMG_URL="https://download.fedoraproject.org/pub/alt/atomic/stable/Cloud-Images/x86_64/Images/Fedora-Cloud-Atomic-${CHANNEL}-${RELEASE}.x86_64.qcow2"
    ;;
  centos)
    BOOT_HOOK="bootcmd:
  - echo 'DHCP_HOSTNAME=\${HOSTNAME}' >> /etc/sysconfig/network
runcmd:
  - service network restart"
    RELEASE=7
    IMG_NAME="CentOS-${RELEASE}-x86_64-GenericCloud.qcow2"
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
    #CHANNEL=testing
    #RELEASE=testing
    IMG_NAME="debian-${CHANNEL}-openstack-amd64.qcow2"
    IMG_URL="http://cdimage.debian.org/cdimage/openstack/${RELEASE}/debian-${CHANNEL}-openstack-amd64.qcow2"
    ;;
  ubuntu)
    BOOT_HOOK="runcmd:
  - service networking restart"
    CHANNEL=xenial
    RELEASE=current
    IMG_NAME="${CHANNEL}-server-cloudimg-amd64.qcow2"
    IMG_URL="https://cloud-images.ubuntu.com/daily/server/${CHANNEL}/${RELEASE}/${CHANNEL}-server-cloudimg-amd64-disk1.img"
    ;;
  ubuntu-core)
    BOOT_HOOK="runcmd:
  - service networking restart"
    CHANNEL=15.04
    RELEASE=current
    SSH_USER=ubuntu
    IMG_NAME="core-${CHANNEL}-amd64.qcow2"
    IMG_URL="https://cloud-images.ubuntu.com/ubuntu-core/${CHANNEL}/core/stable/${RELEASE}/core-stable-amd64-disk1.img"
    ;;
  freebsd)
    CHANNEL=10.2
    #SKIP_CLOUD_CONFIG=true
    #NETWORK_DEVICE="e1000"
    IMG_NAME="FreeBSD-${CHANNEL}-RELEASE-amd64.qcow2"
    IMG_URL="http://ftp.freebsd.org/pub/FreeBSD/releases/VM-IMAGES/${CHANNEL}-RELEASE/amd64/Latest/FreeBSD-${CHANNEL}-RELEASE-amd64.qcow2.xz"
    ;;
  clearlinux)
    LATEST=$(curl -s https://download.clearlinux.org/latest)
    IMG_NAME="clear-${LATEST}-kvm.img"
    IMG_URL="https://download.clearlinux.org/releases/${LATEST}/clear/clear-${LATEST}-kvm.img.xz"
    DISK_FORMAT="raw"
    ;;
  windows)
    WINDOWS_VARIANT="IE6.XP.For.Windows.VirtualBox.zip"
    WINDOWS_VARIANT="IE7.Vista.For.Windows.VirtualBox.zip"
    WINDOWS_VARIANT="IE8.XP.For.Windows.VirtualBox.zip"
    WINDOWS_VARIANT="IE8.Win7.For.Windows.VirtualBox.zip"
    WINDOWS_VARIANT="IE9.Win7.For.Windows.VirtualBox.zip"
    WINDOWS_VARIANT="IE10.Win7.For.Windows.VirtualBox.zip"
    WINDOWS_VARIANT="IE10.Win8.For.Windows.VirtualBox.zip"
    WINDOWS_VARIANT="IE11.Win8.1.For.Windows.VirtualBox.zip"
    WINDOWS_VARIANT="IE11.Win7.For.Windows.VirtualBox.zip"
    WINDOWS_VARIANT="Microsoft%20Edge.Win10.For.Windows.VirtualBox.zip" # https://az792536.vo.msecnd.net/vms/VMBuild_20150801/VirtualBox/MSEdge/Windows/Microsoft%20Edge.Win10.For.Windows.VirtualBox.zip
    WINDOWS_HOSTNAME="IE11Win7"
    IE_VERSION="IE11"
    WIN_VERSION="Win8.1"
    WIN_HOSTNAME="${IE_VERSION}${WIN_VERSION}"
    IMG_NAME="${IE_VERSION}-${WIN_VERSION}-disk1.vmdk"
    IMG_URL="https://az412801.vo.msecnd.net/vhd/VMBuild_20141027/VirtualBox/${IE_VERSION}/Windows/${IE_VERSION}.${WIN_VERSION}.For.Windows.VirtualBox.zip"
    DISK_BUS="ide"
    DISK_FORMAT="vmdk"
    NETWORK_DEVICE="rtl8139"
    RAM=1024
    CPUs=2
    SKIP_CLOUD_CONFIG=true
    ;;
  *)
    echo "'$1' OS is not supported"
    usage
    exit 1
    ;;
esac

OS_NAME="$1"
SSH_USER=${SSH_USER:-$OS_NAME}

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

OPENSTACK_DIR="openstack/latest"
PUB_KEY=$(cat ${PUB_KEY_PATH})
PRIV_KEY_PATH=$(echo ${PUB_KEY_PATH} | sed 's#.pub##')
CDIR=$(cd `dirname $0` && pwd)
IMG_PATH=${HOME}/libvirt_images/${OS_NAME}
DISK_BUS=${DISK_BUS:-virtio}
NETWORK_DEVICE=${NETWORK_DEVICE:-virtio}
DISK_FORMAT=${DISK_FORMAT:-qcow2}
RAM=${RAM:-512}
CPUs=${CPUs:-1}

IMG_EXTENSION=""
if [[ "${IMG_URL}" =~ \.([a-z0-9]+)$ ]]; then
  IMG_EXTENSION=${BASH_REMATCH[1]}
fi

case "${IMG_EXTENSION}" in
  bz2)
    DECOMPRESS="| bzcat";;
  xz)
    DECOMPRESS="| xzcat";;
  zip)
    DECOMPRESS="| bsdtar -Oxf - '${IE_VERSION} - ${WIN_VERSION}.ova' | tar -Oxf - '${IE_VERSION} - ${WIN_VERSION}-disk1.vmdk'";;
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

  if [ ! -d $IMG_PATH/$VM_HOSTNAME/$OPENSTACK_DIR ]; then
    mkdir -p $IMG_PATH/$VM_HOSTNAME/$OPENSTACK_DIR || (echo "Can not create $IMG_PATH/$VM_HOSTNAME/$OPENSTACK_DIR directory" && exit 1)
  fi

  virsh pool-info $OS_NAME > /dev/null 2>&1 || virsh pool-create-as $OS_NAME dir --target $IMG_PATH || (echo "Can not create $OS_NAME pool at $IMG_PATH target" && exit 1)
  # Make this pool persistent
  (virsh pool-dumpxml $OS_NAME | virsh pool-define /dev/stdin)
  virsh pool-start $OS_NAME > /dev/null 2>&1 || true

  if [ ! -f $IMG_PATH/$IMG_NAME ]; then
    eval "wget $IMG_URL -O - $DECOMPRESS > $IMG_PATH/$IMG_NAME" || (rm -f $IMG_PATH/$IMG_NAME && echo "Failed to download image" && exit 1)
  fi

  if [ ! -f $IMG_PATH/${VM_HOSTNAME}.${DISK_FORMAT} ]; then
    qemu-img create -f $DISK_FORMAT -b $IMG_PATH/$IMG_NAME $IMG_PATH/${VM_HOSTNAME}.${DISK_FORMAT} || \
      (echo "Failed to create ${VM_HOSTNAME}.${DISK_FORMAT} volume image" && exit 1)
    virsh pool-refresh $OS_NAME
  fi
  UUID=$(cat /proc/sys/kernel/random/uuid)
  echo "$CC" > $IMG_PATH/$VM_HOSTNAME/$OPENSTACK_DIR/user_data
  echo -e "{ \"instance-id\": \"iid-${VM_HOSTNAME}\", \"local-hostname\": \"${VM_HOSTNAME}\", \"hostname\": \"${VM_HOSTNAME}\", \"dsmode\": \"local\", \"uuid\": \"$UUID\" }" > $IMG_PATH/$VM_HOSTNAME/$OPENSTACK_DIR/meta_data.json

  CC_DISK=""
  if [ -z $SKIP_CLOUD_CONFIG ]; then
    mkisofs \
      -input-charset utf-8 \
      -output $IMG_PATH/$VM_HOSTNAME/cidata.iso \
      -volid config-2 \
      -joliet \
      -rock \
      $IMG_PATH/$VM_HOSTNAME || (echo "Failed to create ISO image"; exit 1)
    echo -e "#!/bin/sh\nmkisofs -input-charset utf-8 -R -V $CC_VOL_ID -o $IMG_PATH/$VM_HOSTNAME/cidata.iso $IMG_PATH/$VM_HOSTNAME" > $IMG_PATH/$VM_HOSTNAME/rebuild_iso.sh
    chmod +x $IMG_PATH/$VM_HOSTNAME/rebuild_iso.sh
    virsh pool-refresh $OS_NAME
    CC_DISK="--disk path=$IMG_PATH/$VM_HOSTNAME/cidata.iso,device=cdrom"
  fi

  virt-install \
    --connect qemu:///system \
    --import \
    --name $VM_HOSTNAME \
    --ram $RAM \
    --vcpus $CPUs \
    --os-type=linux \
    --os-variant=virtio26 \
    --network network=default,model=${NETWORK_DEVICE} \
    --disk path=$IMG_PATH/$VM_HOSTNAME.${DISK_FORMAT},format=${DISK_FORMAT},bus=$DISK_BUS \
    $CC_DISK \
    --vnc \
    --noautoconsole \
#    --cpu=host
done

print_green "Use this command to connect to your cluster: 'ssh -i $PRIV_KEY_PATH $SSH_USER@$FIRST_HOST'"

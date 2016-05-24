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
IMG_PATH=${HOME}/libvirt_images/${OS_NAME}
RANDOM_PASS=$(openssl rand -base64 12)
TECTONIC_LICENSE=$(cat $CDIR/tectonic.lic 2>/dev/null || true)
DOCKER_CFG=$(cat $CDIR/docker.cfg 2>/dev/null || true)
if [ "$TECTONIC" == "true" ]; then
  MASTER_USER_DATA_TEMPLATE=${CDIR}/k8s_tectonic_master.yaml
else
  MASTER_USER_DATA_TEMPLATE=${CDIR}/k8s_master.yaml
fi
NODE_USER_DATA_TEMPLATE=${CDIR}/k8s_node.yaml
ETCD_DISCOVERY=$(curl -s "https://discovery.etcd.io/new?size=$1")
CHANNEL=alpha
RELEASE=current
K8S_RELEASE=v1.1.8
FLANNEL_TYPE=vxlan

ETCD_ENDPOINTS=""
for SEQ in $(seq 1 $1); do
  if [ "$SEQ" == "1" ]; then
		ETCD_ENDPOINTS="http://k8s-master:2379"
  else
    NODE_SEQ=$[SEQ-1]
    ETCD_ENDPOINTS="$ETCD_ENDPOINTS,http://k8s-node-$NODE_SEQ:2379"
  fi
done

POD_NETWORK=10.100.0.0/16
SERVICE_IP_RANGE=10.101.0.0/24
K8S_SERVICE_IP=10.101.0.1
DNS_SERVICE_IP=10.101.0.254
K8S_DOMAIN=skydns.local
RAM=512
CPUs=1
IMG_NAME="coreos_${CHANNEL}_${RELEASE}_qemu_image.img"
IMG_URL="http://${CHANNEL}.release.core-os.net/amd64-usr/${RELEASE}/coreos_production_qemu_image.img.bz2"
SIG_URL="http://${CHANNEL}.release.core-os.net/amd64-usr/${RELEASE}/coreos_production_qemu_image.img.bz2.sig"
GPG_PUB_KEY="https://coreos.com/security/image-signing-key/CoreOS_Image_Signing_Key.asc"
GPG_PUB_KEY_ID="50E0885593D2DCB4"

set +e
if gpg --version > /dev/null 2>&1; then
  GPG=true
  if ! gpg --list-sigs $GPG_PUB_KEY_ID > /dev/null; then
    wget -q -O - $GPG_PUB_KEY | gpg --import --keyid-format LONG || (GPG=false && echo "Warning: can not import GPG public key")
  fi
else
  GPG=false
  echo "Warning: please install GPG to verify CoreOS images' signatures"
fi
set -e

IMG_EXTENSION=""
if [[ "${IMG_URL}" =~ \.([a-z0-9]+)$ ]]; then
  IMG_EXTENSION=${BASH_REMATCH[1]}
fi

case "${IMG_EXTENSION}" in
  bz2)
    DECOMPRESS="bzcat";;
  xz)
    DECOMPRESS="xzcat";;
  *)
    DECOMPRESS="cat";;
esac

if [ ! -d $IMG_PATH ]; then
  mkdir -p $IMG_PATH || (echo "Can not create $IMG_PATH directory" && exit 1)
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
    VM_HOSTNAME="k8s-master"
    COREOS_MASTER_HOSTNAME=$VM_HOSTNAME
    USER_DATA_TEMPLATE=$MASTER_USER_DATA_TEMPLATE
  else
    NODE_SEQ=$[SEQ-1]
    VM_HOSTNAME="k8s-node-$NODE_SEQ"
    USER_DATA_TEMPLATE=$NODE_USER_DATA_TEMPLATE
  fi

  if [ ! -d $IMG_PATH/$VM_HOSTNAME/openstack/latest ]; then
    mkdir -p $IMG_PATH/$VM_HOSTNAME/openstack/latest || (echo "Can not create $IMG_PATH/$VM_HOSTNAME/openstack/latest directory" && exit 1)
    sed "s#%PUB_KEY%#$PUB_KEY#g;\
         s#%HOSTNAME%#$VM_HOSTNAME#g;\
         s#%DISCOVERY%#$ETCD_DISCOVERY#g;\
         s#%RANDOM_PASS%#$RANDOM_PASS#g;\
         s#%MASTER_HOST%#$COREOS_MASTER_HOSTNAME#g;\
         s#%K8S_RELEASE%#$K8S_RELEASE#g;\
         s#%FLANNEL_TYPE%#$FLANNEL_TYPE#g;\
         s#%POD_NETWORK%#$POD_NETWORK#g;\
         s#%SERVICE_IP_RANGE%#$SERVICE_IP_RANGE#g;\
         s#%K8S_SERVICE_IP%#$K8S_SERVICE_IP#g;\
         s#%DNS_SERVICE_IP%#$DNS_SERVICE_IP#g;\
         s#%K8S_DOMAIN%#$K8S_DOMAIN#g;\
         s#%TECTONIC_LICENSE%#$TECTONIC_LICENSE#g;\
         s#%DOCKER_CFG%#$DOCKER_CFG#g;\
         s#%ETCD_ENDPOINTS%#$ETCD_ENDPOINTS#g" $USER_DATA_TEMPLATE > $IMG_PATH/$VM_HOSTNAME/openstack/latest/user_data
    if selinuxenabled 2>/dev/null; then
      # We use ISO configdrive to avoid complicated SELinux conditions
      genisoimage -input-charset utf-8 -R -V config-2 -o $IMG_PATH/$VM_HOSTNAME/configdrive.iso $IMG_PATH/$VM_HOSTNAME || (echo "Failed to create ISO image"; exit 1)
      echo -e "#!/bin/sh\ngenisoimage -input-charset utf-8 -R -V config-2 -o $IMG_PATH/$VM_HOSTNAME/configdrive.iso $IMG_PATH/$VM_HOSTNAME" > $IMG_PATH/$VM_HOSTNAME/rebuild_iso.sh
      chmod +x $IMG_PATH/$VM_HOSTNAME/rebuild_iso.sh
      CONFIG_DRIVE="--disk path=$IMG_PATH/$VM_HOSTNAME/configdrive.iso,device=cdrom"
    else
      CONFIG_DRIVE="--filesystem $IMG_PATH/$VM_HOSTNAME/,config-2,type=mount,mode=squash"
    fi
  fi

  virsh pool-info $OS_NAME > /dev/null 2>&1 || virsh pool-create-as $OS_NAME dir --target $IMG_PATH || (echo "Can not create $OS_NAME pool at $IMG_PATH target" && exit 1)
  # Make this pool persistent
  (virsh pool-dumpxml $OS_NAME | virsh pool-define /dev/stdin)
  virsh pool-start $OS_NAME > /dev/null 2>&1 || true

  trap 'rm -f "$IMG_PATH/$IMG_NAME"' INT TERM EXIT
  if [ ! -f $IMG_PATH/$IMG_NAME ]; then
    if [ $GPG ]; then
      eval "gpg --enable-special-filenames \
                --verify \
                --batch \
                <(wget -q -O - $SIG_URL)\
                <(wget -O - $IMG_URL | tee >($DECOMPRESS > $IMG_PATH/$IMG_NAME))" || (rm -f $IMG_PATH/$IMG_NAME && echo "Failed to download and verify the image" && exit 1)
    else
      eval "wget $IMG_URL -O - | $DECOMPRESS > $IMG_PATH/$IMG_NAME" || (rm -f $IMG_PATH/$IMG_NAME && echo "Failed to download the image" && exit 1)
    fi
  fi
  trap - INT TERM EXIT
  trap

  if [ ! -f $IMG_PATH/${VM_HOSTNAME}.qcow2 ]; then
    qemu-img create -f qcow2 -b $IMG_PATH/$IMG_NAME $IMG_PATH/${VM_HOSTNAME}.qcow2 || \
      (echo "Failed to create ${VM_HOSTNAME}.qcow2 volume image" && exit 1)
    virsh pool-refresh $OS_NAME
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

print_green "Use this command to connect to your cluster: 'ssh -i $PRIV_KEY_PATH core@$COREOS_MASTER_HOSTNAME'"

## Install libvirt on Ubuntu:

```sh
sudo apt-get install -y libvirt-bin virtinst qemu-kvm virt-manager git wget genisoimage
```

## Install on Fedora/CentOS:

```sh
sudo yum install -y libvirt virt-install qemu-kvm virt-manager git wget genisoimage
```

## Configure local resolver to use libvirt's dnsmasq:

```sh
echo 'nameserver 192.168.122.1' | sudo tee -a /etc/resolvconf/resolv.conf.d/head && sudo resolvconf -u
```

**NOTE**: This works only in Debian/Ubuntu

## Add current user into `libvirt` group (will allow you to run scripts without `sudo`):

```sh
sudo usermod -aG libvirtd $USER # for Debian/Ubuntu
sudo usermod -aG libvirt $USER # for CentOS/Fedora
```

**NOTE**: You have to relogin into your UI environment to apply these changes.

## Configure ~/.ssh/config

```sh
cat dot_ssh_config >> ~/.ssh/config
```

## Run CoreOS VMs cluster (works with all deploy scripts) of 3 nodes

```sh
./deploy_coreos_cluster.sh 3
```

May require sudo access to add exceptions for SELinux

`user_data` file works only for CoreOS and contains a template for CoreOS configuration and it configures `etcd2` and `fleet`.

## Run other VMs cluster of 3 nodes

```sh
./deploy_vms_cluster.sh centos 3
```

## Completely destroy and remove all related VMs cluster data

```sh
./remove_cluster.sh coreos
```

## VMs notes for the fleet tests

### CoreOS

Should be run using docker as there is no go binary

### Ubuntu

You have to install these packages inside (Ubuntu 16.04 Xenial is only supported):

```sh
apt-get update
apt-get install -y golang-go etcd machinectl
```

### CentOS

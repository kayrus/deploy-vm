Install libvirt on Ubuntu:

```sh
apt-get install -y libvirt-bin virtinst qemu-kvm virt-manager git
```

Install on Fedora:

```sh
dnf install -y libvirt virt-install qemu-kvm virt-manager git
```

Configure local resolver to use libvirt's dnsmasq:

```sh
echo 'nameserver 192.168.122.1' | sudo tee -a /etc/resolvconf/resolv.conf.d/head && sudo resolvconf -u
```

Configure ~/.ssh/config

```sh
cat dot_ssh_config >> ~/.ssh/config
```

Run VMs cluster (works with all deploy scripts) of 3 nodes

```sh
sudo ./deploy_coreos_cluster.sh 3
```

`user_data` file works only for CoreOS and contains a template for CoreOS configuration and it configures `etcd2` and `fleet`.

Completely destroy and remove all related VMs cluster data (works with all destroy scripts):

```sh
sudo ./destroy_coreos_cluster.sh
```

## VMs notes

### CoreOS

Should be run using docker as there is no go binary

### Ubuntu

You have to install these packages inside (Ubuntu 16.04 Xenial is only supported):

```sh
apt-get update
apt-get install -y golang-go etcd machinectl
```

### CentOS

## Install libvirt on Ubuntu

```sh
sudo apt-get install -y libvirt-bin virtinst qemu-kvm virt-manager git wget genisoimage
sudo service libvirt-bin start
```

For the Windows VM support install `bsdtar` (this tool allows to extract zip archive from stdin):

```sh
sudo apt-get install bsdtar
```

## Install on Fedora/CentOS

```sh
sudo yum install -y libvirt virt-install qemu-kvm virt-manager git wget genisoimage NetworkManager
sudo service libvirtd start
```

For the Windows VM support install `bsdtar` (this tool allows to extract zip archive from stdin):

```sh
sudo yum install bsdtar
```

This string inside your `~/.profile` will allow you to use `virsh`:

```sh
export LIBVIRT_DEFAULT_URI=qemu:///system
```

## Configure local resolver to use libvirt's dnsmasq

* Ubuntu 18.04 (`systemd-resolved` [(c)](https://wiki.ubuntu.com/SecurityTeam/TestingEnvironment#Tell_systemd-resolved_to_use_libvirt.27s_dnsmasq_for_VMs_only_.2817.04.2B-.29))

The setting below is not preserved on reboot:

```sh
systemd-resolve --set-dns=192.168.122.1 --set-domain=vm --interface=virbr0
```

Verify:

```sh
systemd-resolve --status virbr0
```

Add the following section into libvirt default network (`sudo virsh net-edit default`):

```xml
  <domain name='vm' localOnly='yes'/>
```

And restart the network:

```sh
sudo virsh net-destroy default
sudo virsh net-start default
```

* Ubuntu/Debian

```sh
virsh net-dumpxml default | sed -r ":a;N;\$!ba;s#.*address='([0-9.]+)'.*#nameserver \1#" | sudo tee -a /etc/resolvconf/resolv.conf.d/head && sudo resolvconf -u
```

* Fedora/CentOS

```sh
sudo systemctl enable NetworkManager
echo -e "[main]\ndns=dnsmasq" | sudo tee -a /etc/NetworkManager/NetworkManager.conf
virsh net-dumpxml default | sed -r ":a;N;\$!ba;s#.*address='([0-9.]+)'.*#server=\1\nall-servers#" | sudo tee /etc/NetworkManager/dnsmasq.d/libvirt_dnsmasq.conf
sudo systemctl restart NetworkManager
```

## Add current user into `libvirt` group (will allow you to run scripts without `sudo`)

```sh
sudo usermod -aG libvirtd $USER # for Debian/Ubuntu14.04/Ubuntu16.04
sudo usermod -aG libvirt $USER # for CentOS/Fedora/Ubuntu18.04
```

**NOTE**: You have to relogin into your UI environment to apply these changes.

## Allow libvirt to read VMs images in your home directory

### ACL solution

#### Add permissions

```sh
setfacl -m "u:libvirt-qemu:--x" $HOME # for Debian/Ubuntu
setfacl -m "u:qemu:--x" $HOME # for CentOS/Fedora
```

#### Remove permissions

##### Remove ACL entries only for libvirt

```sh
setfacl -m "u:libvirt-qemu:---" $HOME # for Debian/Ubuntu
setfacl -m "u:qemu:---" $HOME # for CentOS/Fedora
```

##### Remove all custom ACL entries

```sh
setfacl -b $HOME
getfacl $HOME
```

### Groups solution

#### Add permissions

```sh
sudo usermod -aG $USER libvirt-qemu # for Debian/Ubuntu
sudo usermod -aG $USER qemu # for CentOS/Fedora
chmod g+x $HOME
```

#### Remove permissions

```sh
sudo usermod -G "" libvirt-qemu # for Debian/Ubuntu
sudo usermod -G "kvm" qemu # for CentOS/Fedora
chmod g-x $HOME
```

## Configure virsh environment

```sh
echo "export LIBVIRT_DEFAULT_URI=qemu:///system" >> ~/.bashrc
```

## Configure ~/.ssh/config

```sh
cat dot_ssh_config >> ~/.ssh/config
chmod 600 ~/.ssh/config
```

## Run Flatcar VMs cluster of 3 nodes

```sh
./deploy_flatcar_cluster.sh -s 3
```

`user_data` file works only for Flatcar and contains a template for Flatcar configuration and it configures `etcd2` and `fleet`.

## Try out Tectonic

Create Tectonoic credentials files:

* `tectonic.lic` # raw base64 encoded licence
* `docker.cfg` # raw base64 encoded dockercfg

Deploy cluster:

```sh
./deploy_k8s_cluster.sh --tectonic
```

Enter your Kubernetes master node:

```sh
ssh core@k8s-master # [-i ~/.ssh/id_rsa]
```

Get Tectonic `admin@example.com` password:

```sh
kubectl --namespace=tectonic-system get secret tectonic-identity-admin-password -o template --template="{{.data.password}}" | base64 -d && echo
```

Login Tectonic:

[https://k8s-master:32000](https://k8s-master:32000)

Username: `admin@example.com`
Password: see above

## Run other VMs

### Linux

Run three CentOS VMs

```sh
./deploy_vms_cluster.sh -o centos -s 3
```

### Windows

Run one Windows IE11.Win7 VM

```sh
./deploy_vms_cluster.sh -o windows -r IE11.Win7 -m 1024 -u 2
```

### FreeBSD guest (experimental)

Download and run FreeBSD:

```sh
./deploy_vms_cluster.sh -o freebsd # for 10.3 RELEASE
./deploy_vms_cluster.sh -o freebsd -c 11.0 -r RC1 # for 11.0 RC1
```

FreeBSD QEMU images don't support `cloud-init`, so you have to configure network and ssh manually through the console:

```sh
dhclient vtnet0
echo 'sshd_enable=YES' >> /etc/rc.conf
echo 'ifconfig_DEFAULT=DHCP' >> /etc/rc.conf
echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config
service sshd start
passwd
```

## FreeBSD host (experimental)

```sh
pkg install bash wget bzip2 gnupg cdrtools libvirt qemu virt-manager
kldload vmm
libvirtd -d
ifconfig tap create
ifconfig bridge create
ifconfig bridge0 addm tap0 up
```

virt-install version > 1.4 should use following parameters:

```sh
--nographic \
--console nmdm,source.master=/dev/nmdm0A,source.slave=/dev/nmdm0B \
--network bridge=bridge0 \
```

and without `--vnc` flag. VNC flag produces following XML:

```xml
<graphics type="vnc" port="-1" keymap="en-us"/>
```

which causes `internal error: cannot determine default video type` error message.

## Completely destroy and remove all related VMs cluster data

```sh
./remove_cluster.sh flatcar
```

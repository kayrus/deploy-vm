Install libvirt on Ubuntu:

```sh
apt-get install libvirt-bin virtinst qemu-kvm virt-manager git

```

Install on Fedora:

```sh
dnf install virt-install qemu-kvm libvirt virt-manager
```

Configure local resolver to use libvirt's dnsmasq:

```sh
echo 'nameserver 192.168.122.1' | sudo tee -a /etc/resolvconf/resolv.conf.d/head && sudo resolvconf -u
```

Configure ~/.ssh/config

```sh
cat dot_ssh_config >> ~/.ssh/config
```

Install libvirt on Ubuntu:

```sh
apt-get install libvirt-bin virtinst qemu-kvm virt-manager git

```

Configure local resolver to use libvirt's dnsmasq:

```sh
echo 'nameserver 192.168.122.1' | sudo tee -a /etc/resolvconf/resolv.conf.d/head && sudo resolvconf -u
```

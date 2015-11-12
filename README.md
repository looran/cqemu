cqemu
=====

qemu VM command-line manager

### Usage

```bash
usage: cqemu [-ph] (new|start) vm-name [options]
    -p : pretend, only print commands and do not execute anything
    -h : this help

Actions:
    new <vm-name> (template <vm-name> | <disk-size> <conf-profile>) [-o conf-options] [qemu-options...]
    start <vm-name> [-o conf-options] [qemu-options...]
    show <vm-name>
    rm <vm-name>
    ls

Default conf-options, per conf-profile:
linux-desk : cores=2;ram="2G";virtio_disk=1;internet=0;share="";display="qxl"
linux-server : cores=2;ram="2G";virtio_disk=0;internet=1;share="";display="curses"
windows : cores=2;ram="2G";virtio_disk=0;internet=0;share="/home/share";display="qxl"

Examples:
    cqemu new myvm 20GB linux-desk
    cqemu new myvm 20GB windows
    cqemu new myvm 20GB linux-server
    cqemu new myvm template basevm
    cqemu new myvm template basevm internet=1
    cqemu start myvm
    cqemu start myvm -o share=/mnt/usb
    cqemu start myvm -cdrom /data/mycd.iso
```


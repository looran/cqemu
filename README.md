cqemu
=====

qemu VM command-line manager

### Usage

```bash
usage: cqemu [-ph] (new|start|show|rm|ls) [vm-name] [options]
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

### Dependencies

* spicy (spice-gtk package) : spice client used by default, can be changed in ~/.cqemu/cqemurc
* qemu of course
* KVM enabled kernel

### Examples

#### Create a Windows 7 VM

```base
$ cqemu new win7 20GB windows

[-] Running mkdir /home/user/vms/win7
[-] Running qemu-img create -f raw -o size=20GB /home/user/vms/win7/disk.img
Formatting '/home/user/vms/win7/disk.img', fmt=raw size=21474836480
[-] Running ln -s /home/user/.cqemu/conf.profile.windows > /home/user/vms/win7/conf_profile
[*] Created VM /home/user/vms/win7
```

#### Start the Windown 7 VM with the install CD

```bash
$ cqemu start win7 -cdrom /home/user/win7install.iso

spice_port=4290
[-] Running $(sleep 2; spicy --title "win7_bin (spice_port=4290)" -h 127.0.0.1 -p 4290 </dev/null >/dev/null 2>/dev/null) &
[-] Running qemu-system-x86_64 --enable-kvm -cpu host -smp cores=2 -m 2G -soundhw hda -drive file=/home/user/vms/win7/disk.img -net user,restrict=on,smb=/home/share -net nic,model=virtio -display curses -vga qxl -global qxl-vga.vram_size=64000000 -global qxl-vga.vram_size_mb=64000000 -global qxl-vga.vgamem_mb=32000000 -spice port=4290,disable-ticketing -device virtio-serial-pci -device virtserialport,chardev=spicechannel0,name=com.redhat.spice.0 -chardev spicevmc,id=spicechannel0,name=vdagent -cdrom /home/user/win7install.iso
```

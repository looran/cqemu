cqemu
=====

simple qemu VM command-line manager

### Usage

```bash
$ cqemu
usage: cqemu [-ph] (new|start|show|spice|ssh vm-dir [options]) | show-profiles
   -p : pretend, only print commands and do not execute anything
   -h : this help

actions
   new <vm-dir> <profile_name> <disk_size> <network_mode>
   start <vm-dir> [<network_mode>] [<display_mode>] [qemu-options...]
   show <vm-dir>
   spice <vm_name>
   ssh <vm_name> <username>
   show-profiles
profiles
   linux_desk linux_serv raspi3 windows
network_mode
   net-none net-user net-tap[-<ip>/<mask>]
display_mode
   display-none display-curses display-sdl display-qxl
environnment variables
   QEMU_RUNAS=nobody
   SPICE_CLIENT=spicy
examples
   cqemu new mylinux linux-desk 20G net-user
   cqemu new mywindows windows 20G net-none
   cqemu new myserver linux-server 20G net-tap-192.168.0.1/24
   cqemu start mylinux
   cqemu start mylinux net-none -cdrom /data/mycd.iso
```

#### Profiles and modes

```bash
$ cqemu show-profiles
--- profiles ---
linux_desk (display-qxl)
   sudo qemu-system-x86_64 --enable-kvm -cpu host -smp cores=2 -m 2G -device intel-hda -device hda-duplex -drive file=/disk.img,if=virtio,format=raw -chroot /var/empty -runas nobody -sandbox on,obsolete=deny,spawn=deny
linux_serv (display-sdl)
   sudo qemu-system-x86_64 --enable-kvm -cpu host -smp cores=2 -m 2G -drive file=/disk.img,format=raw -chroot /var/empty -runas nobody -sandbox on,obsolete=deny,spawn=deny
raspi3 (display-sdl)
   sudo qemu-system-aarch64 -M raspi3 -kernel /kernel.img -chroot /var/empty -runas nobody -sandbox on,obsolete=deny,spawn=deny
windows (display-qxl)
   sudo qemu-system-x86_64 --enable-kvm -cpu host -smp cores=2 -m 4G -drive file=/disk.img -chroot /var/empty -runas nobody -sandbox on,obsolete=deny,spawn=deny
--- network modes ---
net-none : -nic none
net-user : -netdev user,id=net0,hostfwd=tcp:127.0.0.1:-:22,hostfwd=tcp:127.0.0.1:-:21 -device virtio-net-pci,netdev=net0
net-tap[-<ip>/<mask>] : -netdev tap,id=net0,ifname=,script=no,downscript=no -device virtio-net-pci,netdev=net0
--- display modes ---
display-none : -display none
display-curses : -display curses
display-sdl : 
display-qxl : -vga none -device qxl-vga,max_outputs=1,vgamem_mb=256,vram_size_mb=256 -spice port=,disable-ticketing -device virtio-serial-pci -device virtserialport,chardev=spicechannel0,name=com.redhat.spice.0 -chardev spicevmc,id=spicechannel0,name=vdagent
```

### Dependencies and requirements

* qemu of course
* if desktop profiles are used: KVM enabled kernel
* if display qxl used: spicy (spice-gtk package), the spice client used by default

### Installation

```bash
$ sudo make install
```

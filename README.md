cqemu
=====

simple qemu VM command-line manager

### Usage

```bash
$ cqemu
usage: cqemu [-h] (new|start|show|spice|ssh vm-dir [options]) | show-profiles

actions
   new <vm_name> <profile_name> <disk_size> <network_mode>
   start <vm_dir> [<network_mode>] [<display_mode>] [qemu-options...]
   show <vm_dir>
   mon <vm_dir> [<netcat_options>]
   spice <vm_dir>
   ssh <vm_dir> <username>
   show-profiles
profiles
   linux-desk linux-serv raspi3 windows
network_mode
   net-none net-user net-tap[-<ip>/<mask>]
display_mode
   display-none display-curses display-sdl display-virtio display-qxl-spice display-virtio-spice
environnment variables
   QEMU_RUNAS=nobody
   SPICE_CLIENT=spicy
examples
   cqemu new mylinux linux-desk 20G net-user
   cqemu new mywindows windows 20G net-tap-192.168.0.1/24
   cqemu start mylinux
   echo stop |cqemu mon mylinux -q0
   cqemu start mywindows net-none -cdrom /data/mycd.iso
```

#### Profiles and modes

```bash
$ cqemu show-profiles
--- profiles ---
linux-desk
   sudo qemu-system-x86_64 --enable-kvm -cpu host -smp cores=2 -m 2G -device intel-hda -device hda-duplex -drive file=/disk.img,if=virtio,format=raw -chroot /var/empty -runas nobody -sandbox on,obsolete=deny,spawn=deny
   default display: display-virtio-spice
linux-serv
   sudo qemu-system-x86_64 --enable-kvm -cpu host -smp cores=2 -m 2G -drive file=/disk.img,format=raw -chroot /var/empty -runas nobody -sandbox on,obsolete=deny,spawn=deny
   default display: display-sdl
raspi3
   sudo qemu-system-aarch64 -M raspi3 -kernel /kernel.img -chroot /var/empty -runas nobody -sandbox on,obsolete=deny,spawn=deny
   default display: display-sdl
windows
   sudo qemu-system-x86_64 --enable-kvm -cpu host -smp cores=2 -m 4G -drive file=/disk.img -chroot /var/empty -runas nobody -sandbox on,obsolete=deny,spawn=deny
   default display: display-qxl-spice
--- network modes ---
net-none : -nic none
net-user : -netdev user,id=net0,hostfwd=tcp:127.0.0.1:-:22,hostfwd=tcp:127.0.0.1:-:21 -device virtio-net-pci,netdev=net0
net-tap[-<ip>/<mask>] : -netdev tap,id=net0,ifname=tap-,script=no,downscript=no -device virtio-net-pci,netdev=net0
--- display modes ---
display-none : -display none
display-curses : -display curses
display-sdl : 
display-virtio : -vga virtio -display gtk,gl=on
display-qxl-spice : -vga none -device qxl-vga,max_outputs=1,vgamem_mb=256,vram_size_mb=256 -spice disable-ticketing,image-compression=off,seamless-migration=on,unix,addr=/spice.sock -device virtio-serial-pci -device virtserialport,chardev=spicechannel0,name=com.redhat.spice.0 -chardev spicevmc,id=spicechannel0,name=vdagent
display-virtio-spice : -vga virtio -spice disable-ticketing,image-compression=off,seamless-migration=on,unix,addr=/spice.sock -device virtio-serial-pci -device virtserialport,chardev=spicechannel0,name=com.redhat.spice.0 -chardev spicevmc,id=spicechannel0,name=vdagent
```

### Dependencies and requirements

* qemu of course
* if desktop profiles are used: KVM enabled kernel
* if display qxl used: spicy (spice-gtk package), the spice client used by default

### Installation

```bash
$ sudo make install
```

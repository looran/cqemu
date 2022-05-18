cqemu
=====

simple qemu VM command-line manager

### Usage

```bash
$ cqemu
usage: cqemu [-h] (new|start|show|mon|spice|user <vm-dir> [options]) | show-profiles

actions
   new <vm_name> <profile_name> <disk_size> <network_mode> [<fsshare_mode>]
   start <vm_dir> [<network_mode>] [<fsshare_mode>] [<display_mode>] [qemu-options...]
   show <vm_dir>
   mon <vm_dir> [<netcat_options>]
   spice <vm_dir>
   user <vm_dir> <user-action> [<user-args...>]
   show-profiles
profiles
   linux-desk linux-serv raspi3 windows
network_mode
   net-none net-user[:<user_options>] net-tap[:<ip>/<mask>]
fsshare_mode
   fsshare-none fsshare:<path>
   (use "share /home/myuser/share virtiofs rw,user 0 0" in guest fstab)
display_mode
   display-none display-curses display-sdl display-virtio display-qxl-spice[:n] display-virtio-spice[:n]
environnment variables
   QEMU_CHROOT=/var/empty
   QEMU_RUNAS=nobody
   SPICE_CLIENT=remote-viewer
   VIRTIOFSD_PATH=/usr/libexec/virtiofsd
examples
   cqemu new vm_windows windows 20G net-user
   cqemu new vm_linux linux-desk 20G net-tap:192.168.0.1/24 fsshare:VM_DIR/share
   cqemu start vm_windows
   echo system_powerdown |cqemu mon vm_windows -q0
   cqemu start vm_windows net-none -cdrom /data/mycd.iso
user actions example
   echo 'conf_user_actions="onstart-iptables: sudo iptables -D INPUT -i tap-vm_linux -d 192.168.0.1 -p tcp --dport 9999 -j ACCEPT"' >> vm_linux/conf"
   cqemu user vm_linux onstart-iptables
```

#### Profiles and modes

```bash
$ cqemu show-profiles
--- profiles ---
linux-desk
   sudo qemu-system-x86_64 --enable-kvm -cpu host -smp cores=2 -m 3G -device intel-hda -device hda-duplex -drive file=VM_DIR/disk.img,if=virtio,format=raw -chroot /var/empty -runas nobody -sandbox on,obsolete=deny,spawn=deny,resourcecontrol=deny -monitor tcp:127.0.0.1:,server,nowait
   default display: display-virtio-spice
linux-serv
   sudo qemu-system-x86_64 --enable-kvm -cpu host -smp cores=2 -m 3G -drive file=VM_DIR/disk.img,format=raw -chroot /var/empty -runas nobody -sandbox on,obsolete=deny,spawn=deny,resourcecontrol=deny -monitor tcp:127.0.0.1:,server,nowait
   default display: display-sdl
raspi3
   sudo qemu-system-aarch64 -M raspi3 -kernel VM_DIR/kernel.img -chroot /var/empty -runas nobody -sandbox on,obsolete=deny,spawn=deny,resourcecontrol=deny -monitor tcp:127.0.0.1:,server,nowait
   default display: display-sdl
windows
   sudo qemu-system-x86_64 --enable-kvm -cpu host -smp cores=2 -m 3G -drive file=VM_DIR/disk.img,format=raw -chroot /var/empty -runas nobody -sandbox on,obsolete=deny,spawn=deny,resourcecontrol=deny -monitor tcp:127.0.0.1:,server,nowait
   default display: display-qxl-spice
--- network modes ---
net-none: -netdev user,id=net0 -nic none
net-user: -netdev user,id=net0,hostfwd=tcp:127.0.0.1:VM_SSH_PORT_HOST-:22 -device virtio-net-pci,netdev=net0
net-tap: -netdev tap,id=net0,ifname=tap-VM_NAME,script=no,downscript=no -device virtio-net-pci,netdev=net0
--- fsshare modes ---
fsshare-none: 
fsshare:<path>: -object memory-backend-memfd,id=mem,size=VM_MEMORY,share=on -numa node,memdev=mem -chardev socket,id=char0,path=VM_PATH/fsshare.sock -device vhost-user-fs-pci,chardev=char0,tag=share
--- display modes ---
display-none: -display none
display-curses: -display curses
display-sdl: 
display-virtio: -vga virtio -display gtk,gl=on
display-qxl-spice[:n]: -vga qxl -spice disable-ticketing,image-compression=off,seamless-migration=on,unix,addr=VM_PATH/spice.sock -device virtio-serial-pci -device virtserialport,chardev=spicechannel0,name=com.redhat.spice.0 -chardev spicevmc,id=spicechannel0,name=vdagent
display-virtio-spice[:n]: -vga virtio -spice disable-ticketing,image-compression=off,seamless-migration=on,unix,addr=VM_PATH/spice.sock -device virtio-serial-pci -device virtserialport,chardev=spicechannel0,name=com.redhat.spice.0 -chardev spicevmc,id=spicechannel0,name=vdagent
```

### Dependencies and requirements

* qemu of course
* if x86 profiles are used: KVM enabled in kernel
* if fsshare:<path> option is used: virtiofs enabled in qemu
* if display-qxl-spice or display-virtio-spice options are used: remote-viewer (virt-viewer package), the spice client used by default

### Installation

```bash
$ sudo make install
```

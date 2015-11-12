#!/bin/sh

# cqemu - qemu VM command-line manager
# 2015, Laurent Ghigonis <laurent@gouloum.fr>

PROG=$(basename $0)
CONF="$HOME/.cqemu"

set -e

# HELPERS

usageexit() {
	cat <<-_EOF
	usage: $PROG [-ph] (new|start) vm-name [options]
	    -p : pretend, only print commands and do not execute anything
	    -h : this help

	Actions:
	    new <vm-name> (template <vm-name> | <disk-size> <conf-profile>) [-o conf-options] [qemu-options...]
	    start <vm-name> [-o conf-options] [qemu-options...]
	    show <vm-name>
	    rm <vm-name>
	    ls

	Default conf-options, per conf-profile:
	$(find $CONF/conf.profile.* |while read c; do echo "$(echo $c |sed "s/.*\.\(.*\)/\1/g") : $(cat $c)"; done)

	Examples:
	    $PROG new myvm 20GB linux-desk
	    $PROG new myvm 20GB windows
	    $PROG new myvm 20GB linux-server
	    $PROG new myvm template basevm
	    $PROG new myvm template basevm internet=1
	    $PROG start myvm
	    $PROG start myvm -o share=/mnt/usb
	    $PROG start myvm -cdrom /data/mycd.iso
	_EOF
	exit 1
}

conf_init() {
	[ ! -d $CONF ] && echo "[*] First run, creating $CONF" && echo && mkdir -p $CONF
	[ ! -e $CONF/conf.profile.windows ] && echo -e "cores=2;ram=\"2G\";virtio_disk=0;internet=0;share=\"/home/share\";display=\"qxl\"" > $CONF/conf.profile.windows
	[ ! -e $CONF/conf.profile.linux-desk ]   && echo -e "cores=2;ram=\"2G\";virtio_disk=1;internet=0;share=\"\";display=\"qxl\"" > $CONF/conf.profile.linux-desk
	[ ! -e $CONF/conf.profile.linux-server ]  && echo -e "cores=2;ram=\"2G\";virtio_disk=0;internet=1;share=\"\";display=\"curses\"" > $CONF/conf.profile.linux-server
	[ ! -e $CONF/cqemurc ] && echo -e "vms=$HOME/vms\nspice_client=spicy" > $CONF/cqemurc
	source $CONF/cqemurc
}

err() { echo "$prog Error: $1"; exit $2; }
trace() { echo "[-] Running $@"; [ $pretend -eq 1 ] && return; eval "$@" ||exit 10; }

# ACTIONS

do_new() {
	[ $# -lt 2 ] && usageexit
	trace mkdir $vmdir

	if [ X"$1" = X"template" ]; then
		trace cp -Rp $vms/$2/* $vmdir/
	else
		[ $# -ge 1 ] && disksize="$1" || disksize="20GB"
		trace qemu-img create -f raw -o size="$disksize" $vmdir/disk.img
		[ ! -e $CONF/conf.profile.$2 ] && echo "ERROR: profile $2 does not exist !" && exit
		trace "echo $2 > $vmdir/conf_profile"
	fi
	shift; shift

	if [ X"$1" = X"-o" ]; then
		trace "echo $2 > $vmdir/conf"
		shift; shift
	fi

	if [ X"$1" != X"" ]; then
		trace echo "$@ > $vmdir/qemu_options"
	fi

	echo "[*] Created VM $vmdir"
}

do_start() {
	profile=$(cat $vmdir/conf_profile)
	source $CONF/conf.profile.$profile
	[ -e $vmdir/conf ] && source $vmdir/conf

	cmd="qemu-system-x86_64"
	cmd="$cmd --enable-kvm "
	cmd="$cmd -cpu host -smp cores=$cores"
	cmd="$cmd -m $ram"
	cmd="$cmd -soundhw hda "
	[ $virtio_disk -eq 1 ] \
		&& cmd="$cmd -drive file=$vmdir/disk.img,if=virtio " \
		|| cmd="$cmd -drive file=$vmdir/disk.img "
	if [ $internet -eq 0 ]; then
		[ X"$share" != X"" ] \
			&& cmd="$cmd -net user,restrict=on,smb=$share -net nic,model=virtio " \
			|| cmd="$cmd -net none "
	else
		[ X"$share" != X"" ] \
			&& cmd="$cmd -net user,smb=$share -net nic,model=virtio " \
			|| cmd="$cmd -net none -net nic,model=virtio "
	fi
	if [ $display = "qxl" ]; then
		spice_port=$(($RANDOM % 500 + 4000))
		echo "spice_port=$spice_port"
		cmd="$cmd -display curses "
		cmd="$cmd -vga qxl -global qxl-vga.vram_size=64000000  -global qxl-vga.vram_size_mb=64000000 -global qxl-vga.vgamem_mb=32000000 "
		cmd="$cmd -spice port=${spice_port},disable-ticketing "
		cmd="$cmd -device virtio-serial-pci -device virtserialport,chardev=spicechannel0,name=com.redhat.spice.0 -chardev spicevmc,id=spicechannel0,name=vdagent "
		trace "\$(sleep 2; $spice_client --title \"win7_bin (spice_port=${spice_port})\" -h 127.0.0.1 -p ${spice_port} </dev/null >/dev/null 2>/dev/null) &"
	fi
	cmd="$cmd $@"

	trace $cmd
}

do_show() {
	find $vmdir |tail -n+2 |sort |while read f; \
		do [ $(basename $f) = "disk.img" ] && continue; echo "=== $f ==="; cat $f; done
}

do_rm() {
	trace ls $vmdir
	echo "[?] Are you sure to \"rm -rf $vmdir\" ? [Enter / Ctrl-C]"; read ;
	trace rm -rf $vmdir
}

do_ls() {
	echo -e "$(du -Lhcs $vms |tail -n1 |cut -d\t -f1)\t$vms"
	find -L $vms -maxdepth 1 -type d |tail -n+2 |sort |while read v; \
		do echo -e "$(du -Lhcs $v |tail -n1 |cut -d\t -f1)\t$(basename $v)"; done
}

# MAIN

conf_init
[ X"$1" = X"ls" ] && do_ls && exit 0
[ $# -lt 2 -o X"$1" = X"-h" ] && usageexit
pretend=0; [ X"$1" = X"-p" ] && pretend=1 && shift
action=$1
vmname=$2
vmdir=$(readlink -f "$vms/$vmname")
shift; shift

case $action in
new)
	[ $# -lt 2 ] && usageexit
	do_new $@
	;;
start)
	do_start $@
	;;
show)
	do_show $@
	;;
rm)
	do_rm $@
	;;
*)
	usageexit
	;;
esac


#!/bin/bash

# cqemu - simple qemu VM command-line manager
# 2015 Laurent Ghigonis <ooookiwi@gmail.com> initial version
# 2021 Laurent Ghigonis <ooookiwi@gmail.com> complete rewrite

usageexit() {
	cat <<-_EOF
	usage: $PROG [-h] (new|start|show|mon|spice|user <vm-dir> [options]) | show-profiles

	actions
	   new <vm_name> <profile_name> <disk_size> <network_mode> [<fsshare_mode>]
	   start <vm_dir> [<network_mode>] [<fsshare_mode>] [<display_mode>] [qemu-options...]
	   show <vm_dir>
	   mon <vm_dir> [<netcat_options>]
	   spice <vm_dir>
	   user <vm_dir> <user-action> [<user-args...>]
	   show-profiles
	profiles
	   $PROFILES
	network_mode
	   $NETWORK_MODES
	fsshare_mode
	   $FSSHARE_MODES
	   (use "share /home/myuser/share virtiofs rw,user 0 0" in guest fstab)
	display_mode
	   $DISPLAY_MODES
	environnment variables
	   QEMU_CHROOT=$QEMU_CHROOT
	   QEMU_RUNAS=$QEMU_RUNAS
	   SPICE_CLIENT=$SPICE_CLIENT
	   VIRTIOFSD_PATH=$VIRTIOFSD_PATH

	examples
	   $PROG new vm_windows windows 20G net-user
	   $PROG new vm_linux linux-desk 20G net-tap:192.168.0.1/24 fsshare:VM_DIR/share
	   $PROG start vm_windows
	   echo system_powerdown |$PROG mon vm_windows -q0
	   $PROG start vm_windows net-none -cdrom /data/mycd.iso
	user actions examples
	   echo 'conf_user_actions="onstart-iptables: sudo iptables -D INPUT -i tap-vm_linux -d 192.168.0.1 -p tcp --dport 9999 -j ACCEPT"' >> vm_linux/conf"
	   $PROG user vm_linux onstart-iptables
	_EOF
	exit 1
}
PROFILES="linux-desk linux-serv raspi3 windows"
NETWORK_MODES="net-none net-user[:<user_options>] net-tap[:<ip>/<mask>"]
FSSHARE_MODES="fsshare-none fsshare:<path>"
DISPLAY_MODES="display-none display-curses display-sdl display-virtio display-qxl-spice[:n] display-virtio-spice[:n]"

err() { echo -e "$PROG error: $1" >&2; exit 1; }
trace() { echo "# $*" >&2; "$@" ||exit 10; }

set_vm_vars() {
	# sets vm_* variables from vm_name argument
	dir="$1"
	vm_name="$(basename $dir)"
	vm_path="$(readlink -f $dir)"
	vm_monitor_port="9$(echo $vm_path |md5sum |tr -d 'a-z' |cut -c-3)"
	vm_ssh_port_host="$(($vm_monitor_port + 1))"
}

vm_conf_load() {
	[ ! -d $vm_path ] && err "VM directory does not exist : $vm_path"
	. "$vm_path/conf"
}

substitute_vars() {
	cmd="$1"
	cmd="$(echo "$cmd" |sed s:VM_NAME:${vm_name}:g)"
	cmd="$(echo "$cmd" |sed s:VM_DIR:${vm_path}:g)"
	cmd="$(echo "$cmd" |sed s/VM_SSH_PORT_HOST/$vm_ssh_port_host/g)"
	echo "$cmd"
}

spice_client_start() {
	[ -z "$1" ] && delay=0 || delay=$1
	spice_path="${vm_path}/spice.sock"
	spice_cmd="$SPICE_CLIENT -t cqemu-$vm_name spice+unix://$spice_path"
	echo "delaying spice client : $spice_cmd"
	[ ! -w $spice_path ] && trace sudo chown ${USER}: $spice_path
	$(sleep $delay; [ ! -w $spice_path ] && trace sudo chown ${USER}: $spice_path; trace $spice_cmd) &
}

set_profile_vars() {
	profile="$1"
	viewonly="$2"
	LINUX_DEFAULTS="qemu-system-x86_64 --enable-kvm -cpu host -smp cores=2 -m 3G"
	case $profile in
	linux-desk)
		cmd="sudo $LINUX_DEFAULTS -device intel-hda -device hda-duplex -drive file=VM_DIR/disk.img,if=virtio,format=raw"
		display="display-virtio-spice" # gl acceleration with spice integration, good linux support
		;;
	linux-serv)
		cmd="sudo $LINUX_DEFAULTS -drive file=VM_DIR/disk.img,format=raw"
		display="display-sdl"
		;;
	raspi3)
		kernel="VM_DIR/kernel.img"
		[ -z "$viewonly" -a ! -e $kernel ] && err "profile raspi3: kernel image '$kernel' does not exist"
		cmd="sudo qemu-system-aarch64 -M raspi3 -kernel $kernel"
		display="display-sdl"
		;;
	windows)
		cmd="sudo qemu-system-x86_64 --enable-kvm -cpu host -smp cores=2 -m 3G -drive file=VM_DIR/disk.img,format=raw"
		display="display-qxl-spice" # not accelerated but windows does not have virtio-vga drivers
		;;
	*)
		err "invalid profile: $profile'. choices: $PROFILES"
		;;
	esac
	if [ ! $QEMU_CHROOT/etc/resolv.conf ]; then
		echo "creating chroot $QEMU_CHROOT/etc/resolv.conf in case qemu user networking is used"
		trace mkdir -p $QEMU_CHROOT/etc/
		trace cp /etc/resolv.conf $QEMU_CHROOT/etc/resolv.conf
	fi
	cmd="$cmd -chroot $QEMU_CHROOT -runas $QEMU_RUNAS -sandbox on,obsolete=deny,spawn=deny,resourcecontrol=deny -monitor tcp:127.0.0.1:$vm_monitor_port,server,nowait"
	profile_qemu_cmd="$cmd"
	profile_display_mode="$display"
}

set_qemu_net() {
	net=$1
	viewonly=$2
	case $net in
		net-none) qemu_netdev="user,id=net0"; qemu_net="-nic none" ;;
		net-user*)
			IFS=':' read -r _ options <<< "$net"
			[ ! -z "$options" ] && options=,$(substitute_vars "$options")
			qemu_netdev="user,id=net0,hostfwd=tcp:127.0.0.1:${vm_ssh_port_host}-:22${options}"
			qemu_net="-device virtio-net-pci,netdev=net0"
			;;
		net-tap*)
			iface="tap-$vm_name"
			IFS=':' read -r _ ip <<< "$net"
			qemu_netdev="tap,id=net0,ifname=$iface,script=no,downscript=no"
			qemu_net="-device virtio-net-pci,netdev=net0"
			[ ! -z "$viewonly" ] && return
			$conf_pre ip a s dev $iface >/dev/null 2>&1 || \
				trace $conf_pre sudo ip tuntap add user $USER mode tap name $iface
			trace $conf_pre sudo ip a f dev $iface
			[ ! -z "$ip" ] && trace $conf_pre sudo ip a a $ip dev $iface
			trace $conf_pre sudo ip link set $iface up promisc on
			;;
		*) err "invalid network mode: $net. choices: $NETWORK_MODES" ;;
	esac
}

set_qemu_fsshare() {
	fsshare=$1
	viewonly=$2
	case $fsshare in
		fsshare-none) qemu_fsshare="" ;;
		fsshare:*)
			IFS=':' read -r _ dir <<< "$fsshare"
			dir=$(substitute_vars "$dir")
			sock="${vm_path}/fsshare.sock"
			qemu_fsshare="-object memory-backend-memfd,id=mem,size=VM_MEMORY,share=on -numa node,memdev=mem -chardev socket,id=char0,path=$sock -device vhost-user-fs-pci,chardev=char0,tag=share"
			[ ! -z "$viewonly" ] && return
			[ ! -e $VIRTIOFSD_PATH ] && err "virtiofsd not found, VIRTIOFSD_PATH=$VIRTIOFSD_PATH does not exist"
			[ ! -d $dir ] && err "shared directory does not exist : $dir"
			vm_memory=$(sed -n "s/^conf_qemu_cmd_base.*-m \([0-9]*[MG]\) .*/\1/p" $vm_path/conf)
			qemu_fsshare="$(echo $qemu_fsshare |sed s/VM_MEMORY/$vm_memory/)"
			trace sudo $VIRTIOFSD_PATH --socket-path=$sock -o source=$dir -o cache=always &
			trace sleep 1
			trace sudo chown $USER $sock
			;;
		*) err "invalid fsshare mode: $fsshare. choices: $FSSHARE_MODES" ;;
	esac
}

set_qemu_display() {
	display_mode=$(echo $1 |cut -d: -f1)
	display_count=$(echo $1 |cut -d: -f2 -s)
	viewonly=$2
	case $display_mode in
		display-none) qemu_display="-display none" ;;
		display-curses) qemu_display="-display curses" ;;
		display-sdl) qemu_display="" ;;
		display-virtio) qemu_display="-vga virtio -display gtk,gl=on" ;;
		display-qxl-spice*)
			qemu_display="-vga qxl -spice disable-ticketing,image-compression=off,seamless-migration=on,unix,addr=${vm_path}/spice.sock -device virtio-serial-pci -device virtserialport,chardev=spicechannel0,name=com.redhat.spice.0 -chardev spicevmc,id=spicechannel0,name=vdagent"
			extra_device="qxl"
			[ ! -z "$viewonly" ] && return
			spice_client_start
			;;
		display-virtio-spice*)
			qemu_display="-vga virtio -spice disable-ticketing,image-compression=off,seamless-migration=on,unix,addr=${vm_path}/spice.sock -device virtio-serial-pci -device virtserialport,chardev=spicechannel0,name=com.redhat.spice.0 -chardev spicevmc,id=spicechannel0,name=vdagent"
			extra_device="virtio"
			[ ! -z "$viewonly" ] && return
			spice_client_start 2
			;;
		*) err "invalid display mode: $display_mode. choices: $DISPLAY_MODES" ;;
	esac
	if [ ! -z "$display_count" -a ! -z "$extra_device" ]; then
		for d in $(seq 2 $display_count); do
			qemu_display="$qemu_display -device $extra_device";
		done
	fi
}

PROG=$(basename $0)
QEMU_CHROOT="${QEMU_CHROOT:-/var/empty}"
QEMU_RUNAS=${QEMU_RUNAS:-nobody}
SPICE_CLIENT="${SPICE_CLIENT:-remote-viewer}"
VIRTIOFSD_PATH="${VIRTIOFSD_PATH:-/usr/libexec/virtiofsd}"
USER=$(whoami)

set -e

[ $# -lt 1 -o "$1" = "-h" ] && usageexit

action="$1"
shift
case $action in
new)
	[ $# -lt 4 ] && usageexit
	dir=$1
	set_vm_vars $dir
	[ -d $vm_path ] && err "VM already exists in $vm_path"
	profile=$2
	disk_size=$3
	net_mode=$4
	[ $# -eq 5 ] && fsshare_mode=$5 || fsshare_mode="fsshare-none"
	echo "[+] validating VM profile"
	set_profile_vars $profile
	set_qemu_net $net_mode checkonly
	set_qemu_fsshare $fsshare_mode checkonly
	echo "[+] creating new VM configuration"
	mkdir "$vm_path"
	cat > "$vm_path/conf" <<-_EOF
# cqemu configuration file for VM '$vm_name'
# creation date : $(date +%Y%m%d_%H%M%S)
# creation host : $(uname -a)
# creation path : $vm_path
conf_qemu_cmd_base="$profile_qemu_cmd"
conf_net="$net_mode"
conf_fsshare="$fsshare_mode"
conf_display="$profile_display_mode"
conf_pre=""
conf_user_actions=""
_EOF
	trace cat "$vm_path/conf"
	echo "[+] creating new VM image"
	trace qemu-img create -f raw -o size="$disk_size" $vm_path/disk.img
	echo "[*] DONE, new VM '$vm_name' created in $vm_path"
	;;
start)
	[ $# -lt 1 ] && usageexit
	dir=$1
	shift
	set_vm_vars $dir
	vm_conf_load
	while true; do case $1 in
		net-*) conf_net=$1; shift ;;
		fsshare*) conf_fsshare=$1; shift ;;
		display-*) conf_display=$1; shift ;;
		-*) qemu_user_opts="$@"; break ;;
		"") break ;;
		*) err "invalid option: $@" ;;
	esac done
	echo "pre command  : $conf_pre"
	echo "network mode : $conf_net"
	echo "fsshare mode : $conf_fsshare"
	echo "display mode : $conf_display"
	trace sudo date # get sudo password before qemu
	set_qemu_net "$conf_net"
	set_qemu_fsshare $conf_fsshare
	set_qemu_display $conf_display
	while read -r line; do
		IFS=':' read -r action_name action_cmd <<< "$line"
		if [[ $action_name == onstart* ]]; then
			echo "starting onstart action $action_name"
			cmd=$(substitute_vars "$action_cmd")
			[[ $action_name == onstart-nopre* ]] \
				&& trace /bin/sh -c "$cmd" \
				|| trace $conf_pre /bin/sh -c "$cmd"
		fi
	done <<< "$conf_user_actions"
	trace $conf_pre $(substitute_vars "$conf_qemu_cmd_base") $qemu_display -netdev "$qemu_netdev" $qemu_net $qemu_fsshare $qemu_user_opts
	;;
show)
	[ $# -lt 1 ] && usageexit
	dir=$1
	set_vm_vars $dir
	echo "configuration for VM '$vm_name':"
	[ ! -e $vm_path/conf ] && err "VM configuration not found in $vm_path/conf"
	trace cat $vm_path/conf
	trace qemu-img info $vm_path/disk.img
	echo "VM monitor port : 127.0.0.1:$vm_monitor_port"
	echo "VM ssh port     : 127.0.0.1:$vm_ssh_port_host"
	;;
mon)
	[ $# -lt 1 ] && usageexit
	dir=$1
	shift
	set_vm_vars $dir
	vm_conf_load
	trace $conf_pre nc $@ -nvvv 127.0.0.1 $vm_monitor_port
	;;
spice)
	[ $# -ne 1 ] && usageexit
	dir=$1
	set_vm_vars $dir
	vm_conf_load
	trace sudo date # get sudo password before spice socket chown in spice_client_start()
	spice_client_start
	;;
user)
	[ $# -eq 0 ] && usageexit
	dir=$1
	set_vm_vars $dir
	vm_conf_load
	[ $# -eq 1 ] && echo -e "conf_user_actions=\n$conf_user_actions" && exit 0
	action=$2
	shift 2
	found=0
	while read -r line; do
		IFS=':' read -r action_name action_cmd <<< "$line"
		if [ "$action" = "$action_name" ]; then
			cmd=$(substitute_vars "$action_cmd")
			[[ $action_name == nopre* ]] \
				&& trace /bin/sh -c "$cmd $@" \
				|| trace $conf_pre /bin/sh -c "$cmd $@"
			found=$(($found+1))
		fi
	done <<< "$conf_user_actions"
	[ $found -eq 0 ] && err "user action '$action' not found for VM '$vm_name'.\nconf_user_actions=\n$conf_user_actions"
	;;
show-profiles)
	vm_ssh_port_host="VM_SSH_PORT_HOST"
	vm_name="VM_NAME"
	vm_path="VM_PATH"
	echo "--- profiles ---"
	for p in $PROFILES; do
		set_profile_vars $p viewonly
		echo "$p"
		echo "   $profile_qemu_cmd"
		echo "   default display: $profile_display_mode"
	done
	echo "--- network modes ---"
	for n in $NETWORK_MODES; do
		n="$(echo $n |cut -d'[' -f1)"
		set_qemu_net $n viewonly
		echo "$n: -netdev $qemu_netdev $qemu_net"
	done
	echo "--- fsshare modes ---"
	for f in $FSSHARE_MODES; do
		set_qemu_fsshare $f viewonly
		echo "$f: $qemu_fsshare"
	done
	echo "--- display modes ---"
	for d in $DISPLAY_MODES; do
		set_qemu_display $d viewonly
		echo "$d: $qemu_display"
	done
	;;
*)
	usageexit
	;;
esac

#!/bin/bash

# cqemu - simple qemu VM command-line manager
# 2015 Laurent Ghigonis <ooookiwi@gmail.com> initial version
# 2021 Laurent Ghigonis <ooookiwi@gmail.com> complete rewrite

usageexit() {
	cat <<-_EOF
	usage: $PROG [-h] (new|start|show|spice|ssh vm-dir [options]) | show-profiles

	actions
	   new <vm_name> <profile_name> <disk_size> <network_mode>
	   start <vm_dir> [<network_mode>] [<display_mode>] [qemu-options...]
	   show <vm_dir>
	   spice <vm_dir>
	   ssh <vm_dir> <username>
	   show-profiles
	profiles
	   $PROFILES
	network_mode
	   $NETWORK_MODES
	display_mode
	   $DISPLAY_MODES
	environnment variables
	   QEMU_RUNAS=$QEMU_RUNAS
	   SPICE_CLIENT=$SPICE_CLIENT
	examples
	   $PROG new mylinux linux-desk 20G net-user
	   $PROG new mywindows windows 20G net-none
	   $PROG new myserver linux-server 20G net-tap-192.168.0.1/24
	   $PROG start mylinux
	   $PROG start mylinux net-none -cdrom /data/mycd.iso
	_EOF
	exit 1
}
PROFILES="linux-desk linux-serv raspi3 windows"
NETWORK_MODES="net-none net-user net-tap[-<ip>/<mask>"]
DISPLAY_MODES="display-none display-curses display-sdl display-qxl"

err() { echo "$PROG error: $1" >&2; exit 1; }
trace() { echo "# $*" >&2; "$@" ||exit 10; }

set_vm_vars() {
	# sets vm_* variables from vm_name argument
	dir="$1"
	vm_name="$(basename $dir)"
	vm_path="$(readlink -f $dir)"
	vm_spice_port="9$(echo $vm_path |md5sum |tr -d 'a-z' |cut -c-3)"
	vm_ssh_port_host="$(($vm_spice_port + 1))"
	vm_ftp_port_host="$(($vm_spice_port + 2))"
}

vm_conf_load() {
	[ ! -d $vm_path ] && err "VM directory does not exist : $vm_path"
	. "$vm_path/conf"
}

spice_client_start() {
	spice_cmd="$conf_pre $SPICE_CLIENT --title ${vm_name}...port=${vm_spice_port} -h 127.0.0.1 -p ${vm_spice_port} </dev/null >/dev/null 2>/dev/null) &"
	echo "delaying spice client on port ${vm_spice_port} : $spice_cmd"
	$(sleep 2; $spice_cmd) &
}

set_profile_vars() {
	profile="$1"
	viewonly="$2"
	LINUX_DEFAULTS="qemu-system-x86_64 --enable-kvm -cpu host -smp cores=2 -m 2G"
	case $profile in
	linux-desk)
		cmd="sudo $LINUX_DEFAULTS -device intel-hda -device hda-duplex -drive file=$vm_path/disk.img,if=virtio,format=raw"
		display="display-qxl"
		;;
	linux-serv)
		cmd="sudo $LINUX_DEFAULTS -drive file=$vm_path/disk.img,format=raw"
		display="display-sdl"
		;;
	raspi3)
		kernel="$vm_path/kernel.img"
		[ -z "$viewonly" -a ! -e $kernel ] && err "profile raspi3: kernel image '$kernel' does not exist"
		cmd="sudo qemu-system-aarch64 -M raspi3 -kernel $kernel"
		display="display-sdl"
		;;
	windows)
		cmd="sudo qemu-system-x86_64 --enable-kvm -cpu host -smp cores=2 -m 4G -drive file=$vm_path/disk.img"
		display="display-qxl"
		;;
	*)
		err "invalid profile: $profile'. choices: $PROFILES"
		;;
	esac
	cmd="$cmd -chroot /var/empty -runas $QEMU_RUNAS -sandbox on,obsolete=deny,spawn=deny"
	profile_qemu_cmd="$cmd"
	profile_display_mode="$display"
}

set_qemu_display() {
	display=$1
	viewonly=$2
	case $display in
		display-none) qemu_display="-display none" ;;
		display-curses) qemu_display="-display curses" ;;
		display-sdl) qemu_display="" ;;
		display-qxl)
			# max_outputs=1 : workaround QEMU 4.1.0 regression with QXL video
			# see https://wiki.archlinux.org/index.php/QEMU#QXL_video_causes_low_resolution
			qemu_display="-vga none -device qxl-vga,max_outputs=1,vgamem_mb=256,vram_size_mb=256 -spice port=${vm_spice_port},disable-ticketing -device virtio-serial-pci -device virtserialport,chardev=spicechannel0,name=com.redhat.spice.0 -chardev spicevmc,id=spicechannel0,name=vdagent"
			[ ! -z "$viewonly" ] && return
			spice_client_start
			;;
		*) err "invalid display mode: $display. choices: $DISPLAY_MODES" ;;
	esac
}

set_qemu_net() {
	net=$1
	viewonly=$2
	case $net in
		net-none) qemu_net="-nic none" ;;
		net-user) qemu_net="-netdev user,id=net0,hostfwd=tcp:127.0.0.1:${vm_ssh_port_host}-:22,hostfwd=tcp:127.0.0.1:${vm_ftp_port_host}-:21 -device virtio-net-pci,netdev=net0" ;;
		net-tap*)
			ip="$(echo $net |cut -d- -f3)"
			qemu_net="-netdev tap,id=net0,ifname=$iface,script=no,downscript=no -device virtio-net-pci,netdev=net0"
			[ ! -z "$viewonly" ] && return
			iface="tap-$vm_name"
			user=$(whoami)
			$conf_pre ip a s dev $iface >/dev/null 2>&1 || \
				trace $conf_pre sudo ip tuntap add user $user mode tap name $iface
			[ ! -z "$ip" ] && trace $conf_pre sudo ip a a $ip dev $iface
			trace $conf_pre sudo ip link set $iface up promisc on
			trace sudo sysctl -w net.bridge.bridge-nf-call-iptables=0
			trace sudo sysctl -w net.bridge.bridge-nf-call-ip6tables=0
			trace sudo sysctl -w net.bridge.bridge-nf-call-arptables=0
			;;
		*) err "invalid network mode: $net. choices: $NETWORK_MODES" ;;
	esac
}

PROG=$(basename $0)
QEMU_RUNAS=${QEMU_RUNAS:-nobody}
SPICE_CLIENT="${SPICE_CLIENT:-spicy}"

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
	echo "[+] validating VM profile"
	set_profile_vars $profile
	set_qemu_net $net_mode viewonly
	echo "[+] creating new VM configuration"
	mkdir "$vm_path"
	cat > "$vm_path/conf" <<-_EOF
# cqemu configuration file for VM '$vm_name'
# creation date : $(date +%Y%m%d_%H%M%S)
# creation host : $(uname -a)
# creation path : $vm_path
conf_qemu_cmd_base="$profile_qemu_cmd"
conf_qemu_cmd_opts=""
conf_display="$profile_display_mode"
conf_net="$net_mode"
conf_pre=""
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
		display-*) conf_display=$1; shift ;;
		-*) qemu_user_opts="$@"; break ;;
		"") break ;;
		*) err "invalid option: $@" ;;
	esac done
	echo "pre command  : $conf_pre"
	echo "network mode : $conf_net"
	echo "display mode : $conf_display"
	trace sudo date # get sudo password before qemu
	set_qemu_net $conf_net
	set_qemu_display $conf_display
	trace $conf_pre $conf_qemu_cmd_base $qemu_display $qemu_net $conf_qemu_cmd_opts $qemu_user_opts
	;;
show)
	[ $# -lt 1 ] && usageexit
	dir=$1
	set_vm_vars $dir
	echo "configuration for VM '$vm_name':"
	[ ! -e $vm_path/conf ] && err "VM configuration not found in $vm_path/conf"
	trace cat $vm_path/conf
	trace qemu-img info $vm_path/disk.img
	echo "VM spice port : 127.0.0.1:$vm_spice_port"
	echo "VM ssh port   : 127.0.0.1:$vm_ssh_port_host"
	echo "VM ftp port   : 127.0.0.1:$vm_ftp_port_host"
	;;
spice)
	[ $# -ne 1 ] && usageexit
	dir=$1
	set_vm_vars $dir
	vm_conf_load
	spice_client_start
	;;
ssh)
	[ $# -ne 2 ] && usageexit
	dir=$1
	user=$2
	shift 2
	set_vm_vars $dir
	vm_conf_load
	trace $conf_pre ssh -o StrictHostKeyChecking=no -o IdentitiesOnly=yes -p $vm_ssh_port_host $user@127.0.0.1 "$@"
	;;
show-profiles)
	echo "--- profiles ---"
	for p in $PROFILES; do
		set_profile_vars $p viewonly
		echo "$p ($profile_display_mode)"
		echo "   $profile_qemu_cmd"
	done
	echo "--- network modes ---"
	for n in $NETWORK_MODES; do
		set_qemu_net $n viewonly
		echo "$n : $qemu_net"
	done
	echo "--- display modes ---"
	for d in $DISPLAY_MODES; do
		set_qemu_display $d viewonly
		echo "$d : $qemu_display"
	done
	;;
*)
	usageexit
	;;
esac

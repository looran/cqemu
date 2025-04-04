#!/bin/bash

# cqemu - simple qemu VM command-line manager
# 2015-2023 Laurent Ghigonis <ooookiwi@gmail.com>
# 2015 initial version
# 2021 complete rewrite

VERSION=20230730

usageexit() {
	cat <<-_EOF
	usage: $PROG [-h] (new|start|show|mon|spice|vnc|user <vm-dir> [options]) | show-profiles | show-examples
	v$VERSION

	actions
	   new <vm_name> <profile_name> <disk_size> <network_mode> [<fsshare_mode>]
	   start <vm_dir> [<network_mode>] [<fsshare_mode>] [<display_mode>] [qemu-options...]
	   show <vm_dir>
	   mon <vm_dir> [<netcat_options>]
	   spice <vm_dir> | <remote_ssh_host>:<vm_dir>
	   vnc [-low] <remote_ssh_host>:<vm_dir>
	   user <vm_dir> <user-action> [<user-args...>]
	   show-profiles
	   show-examples
	profiles
	   $PROFILES
	network_mode
	   $NETWORK_MODES
	fsshare_mode
	   $FSSHARE_MODES
	   (use "share /home/myuser/share virtiofs rw,user 0 0" in guest fstab)
	display_mode [:vnc]
	   $DISPLAY_MODES
	environnment variables
	   QEMU_CHROOT=$QEMU_CHROOT
	   QEMU_RUNAS=$QEMU_RUNAS
	   SPICE_CLIENT=$SPICE_CLIENT
	   VNC_CLIENT=$VNC_CLIENT
	   VIRTIOFSD_PATH=$VIRTIOFSD_PATH
_EOF
	exit 1
}

showexamples() {
	cat <<-_EOF
example commands:

# create VMs with different profiles and settings
$PROG new vm_windows windows 20G net-user
$PROG new vm_linux linux-desk 20G net-tap:192.168.0.1/24 fsshare:VM_DIR/share
# start and powerdown VM
$PROG start vm_windows
echo system_powerdown |$PROG mon vm_windows -q0
# start VM with disabled network and extra qemu options
$PROG start vm_windows net-none -cdrom /data/mycd.iso
# start VM with 2 monitors and VNC enabled
$PROG start vm_windows display-qxl-spice:2:vnc
# connect from a remote host to a VM
$PROG spice 10.1.2.3:vm_windows
$PROG vnc 10.1.2.3:vm_windows

example of user actions:

echo 'conf_user_actions="onstart-iptables: sudo iptables -D INPUT -i tap-vm_linux -d 192.168.0.1 -p tcp --dport 9999 -j ACCEPT"' >> vm_linux/conf"
$PROG user vm_linux onstart-iptables
	_EOF
}
PROFILES="linux-desk linux-serv raspi3 windows"
NETWORK_MODES="net-none net-user[:<user_options>] net-tap[:<ip>/<mask>]"
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
	cmd="$(echo "$cmd" |sed s:VM_TAP_IFACE:${vm_tap_iface}:g)"
	cmd="$(echo "$cmd" |sed s:VM_DIR:${vm_path}:g)"
	cmd="$(echo "$cmd" |sed s/VM_SSH_PORT_HOST/$vm_ssh_port_host/g)"
	echo "$cmd"
}

spice_client_start() {
	[ -z "$1" ] && delay=0 || delay=$1
	spice_path="${vm_path}/spice.sock"
	spice_cmd="$SPICE_CLIENT -t cqemu-$vm_name spice+unix://$spice_path"
	echo "delaying spice client : $spice_cmd"
	$(sleep $delay; trace $spice_cmd) &
}

set_profile_vars() {
	profile="$1"
	viewonly="$2"
	LINUX_DEFAULTS="qemu-system-x86_64 --enable-kvm -cpu host -smp cores=4 -m 3G"
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
		cmd="sudo qemu-system-x86_64 --enable-kvm -cpu host -smp cores=4 -m 3G -drive file=VM_DIR/disk.img,format=raw"
		display="display-qxl-spice" # not accelerated but windows does not have virtio-vga drivers
		;;
	*)
		err "invalid profile: $profile'. choices: $PROFILES"
		;;
	esac
	# note: if using GL, we should remove resourcecontrol=deny to allow mesa pthread optimisations
	cmd="$cmd -run-with chroot=$QEMU_CHROOT -runas $QEMU_RUNAS -sandbox on,obsolete=deny,resourcecontrol=deny,spawn=deny -monitor tcp:127.0.0.1:$vm_monitor_port,server,nowait"
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
			vm_tap_iface="tap-${vm_name:0:11}"
			IFS=':' read -r _ ip <<< "$net"
			qemu_netdev="tap,id=net0,ifname=$vm_tap_iface,script=no,downscript=no"
			qemu_net="-device virtio-net-pci,netdev=net0"
			[ ! -z "$viewonly" ] && return
			$conf_pre ip a s dev $vm_tap_iface >/dev/null 2>&1 || \
				trace $conf_pre sudo ip tuntap add user $USER mode tap name $vm_tap_iface
			trace $conf_pre sudo ip a f dev $vm_tap_iface
			[ ! -z "$ip" ] && trace $conf_pre sudo ip a a $ip dev $vm_tap_iface
			trace $conf_pre sudo ip link set $vm_tap_iface up promisc on
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
	viewonly=$2
	case $display_mode in
		display-none) qemu_display="-display none" ;;
		display-curses) qemu_display="-display curses" ;;
		display-sdl) qemu_display="-display sdl" ;;
		display-virtio) qemu_display="-vga virtio -display gtk,gl=on" ;;
		display-qxl-spice*)
			display_device="qxl"
			;;&
		display-virtio-spice*)
			display_device="virtio"
			;;&
		display*spice*)
			qemu_display="-vga $display_device -spice disable-ticketing=on,seamless-migration=on,unix=on,addr=${vm_path}/spice.sock -device virtio-serial-pci -device virtserialport,chardev=spicechannel0,name=com.redhat.spice.0 -chardev spicevmc,id=spicechannel0,name=vdagent"
			[ ! -z "$viewonly" ] && return
			display_count=$(echo $1 |cut -d: -f2 -s)
			if [ ! -z "$display_count" ]; then
				for d in $(seq 2 $display_count); do
					qemu_display="$qemu_display -device $display_device";
				done
			fi
			spice_client_start 3
			;;
		*) err "invalid display mode: $display_mode. choices: $DISPLAY_MODES" ;;
	esac
	[[ "$display_mode" != *spice* && $conf_qemu_cmd_base == *spawn=deny* ]] \
		&& echo "NOTE: removing sandbox 'spawn=deny' to allow for display $display_mode" \
		&& conf_qemu_cmd_base="$(echo $conf_qemu_cmd_base |sed 's/,spawn=deny//')" \
		|| true
	opt=$(echo $1 |cut -d: -f3 -s)
	if [ "$opt" = "vnc" ]; then
		qemu_display="$qemu_display -vnc unix:${vm_path}/vnc.sock"
	fi
}

PROG=$(basename $0)
QEMU_CHROOT="${QEMU_CHROOT:-/var/empty}"
QEMU_RUNAS=${QEMU_RUNAS:-nobody}
SPICE_CLIENT="${SPICE_CLIENT:-remote-viewer}"
VNC_CLIENT="${VNC_CLIENT:-vncviewer}"
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
	echo v$VERSION
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
			echo "executing onstart action $action_name"
			cmd=$(substitute_vars "$action_cmd")
			[[ $action_name == onstart-nopre* ]] \
				&& trace /bin/sh -c "$cmd" \
				|| trace $conf_pre /bin/sh -c "$cmd"
		fi
	done <<< "$conf_user_actions"
	if [ ! $QEMU_CHROOT/etc/resolv.conf ]; then
		echo "creating chroot $QEMU_CHROOT/etc/resolv.conf in case qemu user networking is used"
		trace sudo mkdir -p $QEMU_CHROOT/etc/
		trace sudo cp /etc/resolv.conf $QEMU_CHROOT/etc/resolv.conf
	fi
	$(sleep 2; ls ${vm_path}/*.sock 2>/dev/null |grep -q '.*' && trace sudo chown ${USER} ${vm_path}/*.sock) & # delay set socket permissions after qemu startup
	trace $conf_pre $(substitute_vars "$conf_qemu_cmd_base") $qemu_display -netdev "$qemu_netdev" $qemu_net $qemu_fsshare $qemu_user_opts
	while read -r line; do
		IFS=':' read -r action_name action_cmd <<< "$line"
		if [[ $action_name == onstop* ]]; then
			echo "executing onstop action $action_name"
			cmd=$(substitute_vars "$action_cmd")
			[[ $action_name == onstop-nopre* ]] \
				&& trace /bin/sh -c "$cmd" \
				|| trace $conf_pre /bin/sh -c "$cmd"
		fi
	done <<< "$conf_user_actions"
	;;
show)
	[ $# -lt 1 ] && usageexit
	dir=$1
	set_vm_vars $dir
	#echo "configuration for VM '$vm_name':"
	[ ! -e $vm_path/conf ] && err "VM configuration not found in $vm_path/conf"
	echo --------------------------------------------------------------------------------
	echo $vm_path/conf
	cat $vm_path/conf
	echo --------------------------------------------------------------------------------
	trace qemu-img info $vm_path/disk.img
	echo --------------------------------------------------------------------------------
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
	if [[ "$1" == *:* ]]; then
		remote=$(echo $1 |cut -d: -f1)
		path="$(echo $1 |cut -d: -f2)"
		[ "$(basename $path)" != "spice.sock" ] \
			&& path="$path/spice.sock"
		[ $(echo $path |cut -c1) != "/" ] \
			&& path="$HOME/$path" # works only if remote user home == local user home
		trace rm -f /tmp/spice.sock
		trace ssh -L /tmp/spice.sock:"$path" $remote -fNT
		vm_path="/tmp"
		vm_name="$remote:$(basename $(dirname $path))"
	else
		dir=$1
		shift
		set_vm_vars $dir
		vm_conf_load
	fi
	spice_client_start
	;;
vnc)
	[ $# -lt 1 ] && usageexit
	client_opts=""
	[ $1 = "-low" ] \
		&& client_opts="-LowColorLevel=1 -FullColor=0 -AutoSelect=0" \
		&& shift
	remote=$(echo $1 |cut -d: -f1)
	path="$(echo $1 |cut -d: -f2)"
	[ "$(basename $path)" != "vnc.sock" ] \
		&& path="$path/vnc.sock"
	[ $(echo $path |cut -c1) != "/" ] \
		&& path="$HOME/$path" # works only if remote user home == local user home
	trace rm -f /tmp/vnc.sock
	trace ssh -L /tmp/vnc.sock:"$path" $remote -fNT
	trace $VNC_CLIENT $client_opts /tmp/vnc.sock
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
show-examples)
	showexamples
	;;
*)
	usageexit
	;;
esac

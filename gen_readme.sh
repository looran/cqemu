#!/bin/sh

D="$(dirname $0)"
README="$(dirname $0)/README.md"

cat > $README <<-_EOF
cqemu
=====

simple qemu VM command-line manager

### Usage

\`\`\`bash
$ cqemu
$($D/cqemu.sh |sed s/qemu.sh/qemu/)
\`\`\`

#### Profiles and modes

\`\`\`bash
$ cqemu show-profiles
$($D/cqemu.sh show-profiles |sed s/qemu.sh/qemu/)
\`\`\`

### Dependencies and requirements

* qemu of course
* if x86 profiles are used: KVM enabled in kernel
* if fsshare:<path> option is used: virtiofs enabled in qemu
* if display-qxl-spice or display-virtio-spice options are used: remote-viewer (virt-viewer package) is the spice client used by default
* if vnc mode is used: vncviewer (tigervnc package) is the vnc client used by default

### Installation

\`\`\`bash
$ sudo make install
\`\`\`
_EOF

echo "[*] DONE, generated $README"

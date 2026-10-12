# Managed QEMU virtual machines

`vinix-vm` imports a raw guest image into a private qcow2 disk and keeps a
separate firmware-variable image, QMP socket, serial log and execution log per
VM. It supports x86_64 and AArch64 QEMU machines, 64 MiB to 64 GiB of memory and
1 to 64 virtual CPUs, subject to available host resources and QEMU support.

```
v -enable-globals -gc none -cc gcc -o vinix-vm tools/development/vm.v
./vinix-vm init vm.json /home/developer/vm-state
./vinix-vm start /home/developer/vm-state
```

The manager stays in the foreground and owns QEMU until it exits. From another
terminal, use `status`, `pause`, `resume`, `reset`, `shutdown`, or `stop` followed
by the state path. `shutdown` requests guest powerdown; `stop` quits QEMU and
can interrupt guest writes. SIGINT/SIGTERM request powerdown, wait five seconds,
then quit and retire the owned process group. Exit status is saved in
`exit.json`. A file lock prevents a second manager or offline snapshot operation
from opening a running VM. A failed or killed manager never signals a saved PID.

Example configuration (supply actual hashes from `vinix-build hash`):

```json
{
  "schema": 1,
  "architecture": "aarch64",
  "accelerator": "tcg",
  "memory_mib": 2048,
  "cpus": 2,
  "qemu": {"path": "/usr/bin/qemu-system-aarch64", "sha256": "QEMU_HASH"},
  "qemu_img": {"path": "/usr/bin/qemu-img", "sha256": "QEMU_IMG_HASH"},
  "disk": {"path": "/home/developer/vinix-guest.img", "sha256": "RAW_IMAGE_HASH"},
  "firmware_code": {"path": "/usr/share/qemu/edk2-aarch64-code.fd", "sha256": "CODE_HASH"},
  "firmware_vars": {"path": "/usr/share/qemu/edk2-arm-vars.fd", "sha256": "VARS_HASH"},
  "jit": true,
  "network": true,
  "ssh_port": 2222,
  "shared_directory": "/home/developer/shared",
  "guest_agent": true,
  "start_paused": false
}
```

Select `kvm` on a compatible Linux host or `hvf` on a compatible macOS host to
request hardware acceleration. Failure to initialize that accelerator is an
error; the manager does not select TCG as a fallback. Installed Vinix currently
needs `tcg`: `/dev/kvm` is absent and its small native Intel hypervisor cannot
run QEMU. `jit: true` requests Vinix's existing `VINIX_ALLOW_WX` execution mode;
the kernel still requires an administrator-authorized executable mount. The
manager never modifies mount policy, identities, capabilities or device access.

Network access is disabled unless `network` is true. User-mode networking needs
no tap device or root. Optional SSH forwarding binds only to 127.0.0.1; SSH
authentication and the guest server remain the guest's responsibility. The
shared directory is explicitly selected and exposed read-only through virtio-9p.
A guest needs a working 9p driver; Vinix's own 9p guest support is unqualified.
The guest-agent option creates a private `agent.sock` endpoint connected to
`org.qemu.guest_agent.0`; a Linux guest can run its packaged `qemu-ga` there.
This command does not expose remote control, inject credentials, or install
guest software. No guest-agent implementation for Vinix is claimed.

While the VM is stopped:

```
./vinix-vm snapshot-create /home/developer/vm-state before-update
./vinix-vm snapshot-restore /home/developer/vm-state before-update
./vinix-vm snapshot-delete /home/developer/vm-state before-update
```

Snapshots pair qcow2 disk state with a hashed copy of the VM's firmware variables.
They do not save RAM or running devices. A pending-operation receipt blocks
startup if the operation fails or is interrupted. Recover an incomplete
operation by inspecting `snapshot.pending.json`, `snapshot.log`, the qcow2
snapshot list and the preserved variable images; finish the selected disk/vars
restoration before removing that marker. Disk and variables are separate files,
so power-loss atomicity across them is not claimed. There is no implicit
overwrite of an existing snapshot, source image or state directory.

State must be owned by the calling user with mode 0700. QEMU option paths must
be absolute and contain no comma or newline; state paths are limited to 80 bytes
for Unix sockets. Start requires the originally pinned QEMU executable. Import
checks all pinned inputs before and after copying/conversion. Firmware templates
and raw images can be removed after import.

`v -enable-globals -cc cc test tools/development/vmcore` exercises real QEMU:
two CPUs, pause/resume/status/quit, concurrent-start and live-snapshot refusal,
disk write/restore, paired firmware restore and independent VM variables.
Set `VINIX_VM_TEST_FIRMWARE` to the QEMU firmware directory if needed. These
host tests do not qualify a guest OS, hardware virtualization or Vinix-hosted
QEMU. See QEMU's [QMP specification](https://www.qemu.org/docs/master/interop/qmp-spec.html)
and [image tool documentation](https://www.qemu.org/docs/master/tools/qemu-img.html).

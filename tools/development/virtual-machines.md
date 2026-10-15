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

Snapshot restoration resolves the exact name in `qemu-img info` JSON to one
unique internal ID before preparing variables or publishing a pending operation.
This keeps numeric names usable: qcow2's
[restore lookup](https://github.com/qemu/qemu/blob/v11.1.0/block/qcow2-snapshot.c#L573)
tries IDs before names, so passing a numeric name directly could restore another
snapshot's disk while loading the intended variables. Existing snapshot receipts
remain compatible. Missing or duplicate names, invalid/duplicate IDs and failed
inventory commands refuse restoration before changing disk or variables.
Snapshot operations inspect the disk through the pinned image tool under the
offline lock. Inventory commands have a 30-second deadline and a 1 MiB output
limit. `snapshot-info.json` and `snapshot-info.log`
retain the successful inventory and command diagnostics.

New receipts also record `disk_identity`, a SHA-256 of the snapshot's ID,
name and creation seconds/nanoseconds from QEMU's
[snapshot metadata](https://github.com/qemu/qemu/blob/v11.1.0/qapi/block-core.json#L13).
Restore and deletion compare that identity before preparing variables or a
pending operation. A deleted and recreated backend snapshot cannot silently
reuse the old firmware sidecar, even when qcow2 recycles its ID. Creation
refuses a backend name that already exists without sidecars; deletion refuses
duplicate names. Successful creation records identity only after inspecting
the new backend snapshot. A failed final inspection leaves the pending marker
and copied variables for recovery.

Legacy receipts without `disk_identity` retain exact-name lookup and firmware
hash checks; their original backend identity cannot be established retroactively.
The binding detects metadata replacement rather than hashing the snapshot's
disk contents. Managed operations share the offline lease; concurrent external
image editing remains outside this protocol. To replace a managed snapshot,
delete and recreate it through the manager while the VM is stopped.

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

On 15 October 2026 the snapshot-identity regressions reproduced wrong disk
restoration and an accepted missing name against the previous implementation.
The corrected complete `vmcore` suite passed on the Darwin ARM host with
QEMU 11.1.1 and V `be2eb40`. Real qcow2 tests distinguish the disk bytes and
firmware variables of `anchor`, `1` and `2`, restore each pair, and retain the
other snapshot after deletion. Missing/duplicate names and an unreadable
inventory preserve disk/variables without leaving a pending marker or temporary
variable image. Metadata checks also cover malformed JSON, incorrect formats,
empty/NUL-containing IDs and duplicate IDs. The existing real QEMU lifecycle,
locking, live-snapshot refusal and independent-variable checks also passed.

The subsequent snapshot-binding regressions reproduced duplicate backend
creation, ambiguous deletion and stale-sidecar acceptance after a real qcow2
ID was recycled. The complete host `vmcore` suite then passed with identity
binding on the same QEMU/V versions. Refused operations preserve the exact
disk hash, current variables, existing sidecars and manifest, and leave no
new pending marker or temporary variable image. Legacy receipt restoration,
numeric names, ordinary snapshot round trips and the existing QEMU lifecycle
checks also pass. Power-loss atomicity and Vinix-hosted QEMU qualification
remain separate work.

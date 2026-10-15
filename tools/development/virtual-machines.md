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

A monitor that still accepts connections blocks restart and every offline
snapshot operation, including recovery, even after the manager has died. The
one-second transport probe does not require a QMP greeting or status reply:
a silent or malformed service is still occupied. Only a missing socket or an
explicit connection refusal counts as inactive. Other connection errors and
timeouts keep the operation blocked. Unexpected files, directories and symlinks
at `qmp.sock` are preserved for inspection. Use the existing monitor to stop a
surviving VM; an unresponsive monitor requires manual inspection rather than
automatic socket removal or PID-based signaling.

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

With that transport enabled and a running guest agent, query it from the host:

```
./vinix-vm guest-ping /home/developer/vm-state
./vinix-vm guest-info /home/developer/vm-state
./vinix-vm guest-osinfo /home/developer/vm-state
./vinix-vm guest-network /home/developer/vm-state
```

These commands return JSON for agent health, agent version/capabilities,
guest OS details and guest interfaces respectively. Integer counters retain
their exact values. Each exchange has a five-second socket deadline, a 1 MiB
total receive budget including discarded stale data, and a JSON nesting limit
of 64. Missing, disabled, paused or unresponsive agents fail without starting
the VM or changing its configuration. Guest policy errors are returned to the
caller. No arbitrary RPC, guest execution, file access, freeze, password change
or time adjustment is exposed by this CLI.

The client follows QEMU's
[guest-agent synchronization protocol](https://www.qemu.org/docs/master/interop/qemu-ga-ref.html#command-guest-sync-delimited):
it sends a reset sentinel and a random integer nonce, discards stale data until
the delimited nonce response, then correlates the query response by transaction
ID. Every query opens a fresh connection and resynchronizes after earlier
timeouts. A persistent private `agent.lock` serializes query processes without
taking the running VM's lock. Older state directories acquire that file on
their first query. The endpoint must be a socket owned by the calling user;
symlinks and nonprivate state or lock files are refused.

The guest administrator must install and authorize its agent. The manager's
allowlist does not change the agent's own policy or restrict other clients
that already have access to the private socket. For an administrator-selected
read-only agent policy, QEMU supports an explicit
[RPC allowlist](https://www.qemu.org/docs/master/interop/qemu-ga.html#cmdoption-qemu-ga-a)
containing `guest-sync-delimited`, `guest-ping`, `guest-info`,
`guest-get-osinfo` and `guest-network-get-interfaces`. Availability of those
queries depends on the guest's agent and platform. No guest-side permissions
are granted by invoking these commands.

While the VM is stopped:

```
./vinix-vm snapshot-create /home/developer/vm-state before-update
./vinix-vm snapshot-restore /home/developer/vm-state before-update
./vinix-vm snapshot-delete /home/developer/vm-state before-update
```

Snapshots pair qcow2 disk state with a hashed copy of the VM's firmware variables.
They do not save RAM or running devices. A pending-operation receipt blocks
startup if the operation fails or is interrupted. Recover it while stopped:

```
./vinix-vm snapshot-recover /home/developer/vm-state
```

Recovery uses the same private-state, pinned-tool, offline and ownership-lock
checks as ordinary snapshot operations. New pending journals record the action, snapshot
name, firmware hash and backend identity, and are published through a temporary
file and rename so an interrupted write cannot replace a complete journal with
partial JSON. Failed commands retain the journal and saved variables even if
the backend already changed the image. Recovery commands log separately to
`snapshot-recover.log`, preserving the original `snapshot.log`.

Before replay or cleanup, recovery runs the pinned tool's
[consistency check](https://www.qemu.org/docs/master/tools/qemu-img.html#cmdoption-qemu-img-arg-check)
without repair options, with a 300-second deadline and diagnostics in
`snapshot-check.log`. Any nonzero status keeps the operation blocked; this
includes leaked clusters as well as corrupt or unreadable images.

Recovery reapplies a verified restore target before replacing the firmware
variables, or finishes a deletion whose matching backend may already be gone.
It tolerates interrupted sidecar cleanup and repeated restore failures. For
creation, it finishes manifest publication only if the journal already records
the new backend identity. If creation never produced a named backend, it
abandons the preparation and removes its verified firmware copy. If the backend
exists but its identity was never recorded, recovery refuses to adopt it.
Changed firmware, conflicting manifests, ambiguous names and replaced backend
identities also refuse recovery while retaining the evidence. Legacy pending
markers without the new journal fields require manual recovery; legacy
completed snapshot receipts remain readable.

For these refused cases, inspect `snapshot.pending.json`, `snapshot.log`, the
qcow2 snapshot list and the preserved variable images; establish the selected
disk/vars pair before removing the marker. A preparation interrupted before
the first journal publication may also leave an orphan sidecar for inspection.
Disk, variables and receipts are separate files; this process-interruption
protocol does not provide a power-loss transaction or repair corrupt qcow2
images. There is no implicit overwrite of an existing snapshot, source image
or state directory.

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

The subsequent host recovery checks reproduced loss of the saved firmware
copy after a real successful creation followed by an injected command failure.
The corrected checks use a V delegate around real `qemu-img` to fail before or
after create/restore/delete, repeat a failed restore recovery, and interrupt
manifest publication and sidecar cleanup. Recovery verifies both the disk bytes
and firmware pair for numeric names. Missing/changed metadata, firmware and
manifests, legacy journals, and unresolved creation identity remain blocked.
Failed image checks, changed tool pins and nonprivate state also refuse recovery.
The real QEMU lifecycle test also checks that recovery refuses a running VM.
The complete host `vmcore` suite passed on the same QEMU/V versions. The
updated CLI also cross-compiled and linked as static Linux ELF64 for AArch64
and x86_64, with both machine IDs checked. Build logs, source/compiler/binary
hashes and the receipt are retained locally in
`/tmp/vinix-vm-recovery-build-51315`; those cross-builds do not establish
installed-Vinix execution or guest OS qualification.

The monitor-liveness regression reproduced acceptance of a listening socket
that never sent its QMP greeting. The corrected host VM and QMP suites passed
on the same QEMU/V versions. Restart and all four snapshot operations preserve
the socket inode, disk, firmware, logs and pending marker while that listener is
occupied. Missing/refused sockets pass the offline guard; unexpected
monitor paths and access errors refuse without being treated as stale. One
hundred successful, failed and cancelled transport probes retain their exact
descriptor baseline. A real QEMU run kills its owning manager, confirms the
record lock is released, and still refuses replacement and snapshots while
preserving monitor control and disk/firmware hashes. It stops that VM through
QMP and waits for the image lock to be released, without signaling a saved
QEMU PID. These remain host lifecycle checks rather than Vinix-hosted QEMU
acceptance.
The updated CLI also builds as static Linux ELF64 for AArch64 and x86_64.
The checked machine IDs, source/compiler/binary hashes and build logs are
retained locally in `/tmp/vinix-vm-monitor-build-62727`.

Host guest-query checks use V protocol fixtures to exercise stale/partial
output, wrong synchronization nonces, transaction correlation, exact 64-bit
counters, agent policy errors, closure, deadlines, cancellation, and byte/JSON
depth limits. The public CLI also checks concurrent-query refusal, queries
while the VM lease is held, unchanged disk/firmware/pending files, disabled
transport, nonprivate state/locks and unsafe endpoint paths. The real QEMU
lifecycle fixture enables the virtio-serial agent channel and verifies its
socket, alongside the existing lifecycle and snapshot checks. These fixtures
do not qualify a packaged `qemu-ga` inside a guest or provide Vinix's missing
guest-side virtio-serial driver and agent.
All eight host VM/QMP test files passed on 15 October 2026 with QEMU 11.1.1
and V `be2eb40`. The updated CLI cross-compiled and linked as static Linux
ELF64 for AArch64 and x86_64; both machine IDs were checked. Source/compiler/
binary hashes, logs and the build receipt are retained locally in
`/tmp/vinix-vm-guest-build-86620`.

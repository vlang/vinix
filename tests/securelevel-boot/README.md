# Boot securelevel policy checkpoint

The kernel accepts one `vinix.securelevel=-1|0|1|2` boot option. It establishes
the initial level and a floor before SMP and userspace. The common
`security.set_securelevel` entry point serializes runtime changes behind
`/proc/sys/kernel/securelevel`. Even PID 1 cannot lower the boot floor. Without
the option, the historical initial level 0 and minimum -1 remain available.
Malformed, oversized, empty, and duplicate policy options stop boot. Runtime
writes accept only the supported values with surrounding ASCII whitespace,
bounded to 64 bytes.

This supplies an administrator-selected integrity restriction. The bootloader,
kernel, command line, and ext2 root are still unauthenticated. An attacker who
can replace boot artifacts can select a different floor. No executable signing,
fault-time content authentication, protected credential heap, or general MAC
framework is provided by this checkpoint.

Host securelevel/reboot operations require initial user namespace authority.
Mount and hostname controls require that authority when acting on the initial
mount/UTS namespaces; a container root can still configure its own private
namespaces. Changing immutable/append flags also requires initial user
namespace `CAP_LINUX_IMMUTABLE`.

Tmpfs and ext2 recheck immutable/append protection under the resource lock
through write and truncate publication. This closes the bypass through a file
description opened before `FS_IOC_SETFLAGS`. Regular file `O_APPEND` chooses EOF
and enforces `RLIMIT_FSIZE` under that same lock, then returns the actual write
end for the descriptor position. Ext2 owns attribute persistence in its setter.
An uncertain inode write keeps the union of old and requested protection bits
in memory and returns the I/O error; a successful retry resolves the state.
This failure rule cannot authenticate or repair corrupted storage.

There is a conservative mapping compatibility restriction: setting any
immutable/append bit returns `EBUSY` while any `MAP_SHARED` range remains,
including read-only and never-faulted ranges. A protected file rejects new
shared mappings with `EPERM`, including read-only ones. Private COW mappings
remain available. Existing global mapping ownership carries the admission
through fork, split, mremap, and final unmap; no page revocation is implemented.

Run from an isolated worktree with a kernel built for the requested architecture:

```sh
V=/Users/alex/code/v/v python3 tests/securelevel-boot/host.py
V=/Users/alex/code/v/v python3 tests/securelevel-boot/dispatch.py
V=/Users/alex/code/v/v python3 tests/securelevel-boot/attribute_faults.py
python3 tests/kernel-gaps/test_runner.py
python3 tests/securelevel-boot/run.py --arch aarch64 --state-dir /tmp/securelevel-arm
python3 tests/securelevel-boot/run.py --arch x86_64 --state-dir /tmp/securelevel-x86
python3 tests/securelevel-boot/persistent.py --state-dir /tmp/securelevel-ext2
```

Each architecture suite boots default, explicit -1, 0, 1, and 2 policies, then
three malformed policies. Negative boot tests opt in to expected-panic mode,
require both the panic and exact rejection reason, and reject userspace entry.
The common runner also rejects timeout, nonzero launch exit, and later failure
output. Production panic messages remain visible on serial.

Valid guests test PID 1 lowering, strict writes, namespace-local capability
rejection, private namespace controls, old-descriptor writes/writev/pwrite/
sendfile, immutable truncate/chmod/unlink, append-only writes, shared aliases
and their lifetime/error paths, concurrent level changes, concurrent append
descriptor positions, and partial/failed append writes at `RLIMIT_FSIZE`.
The persistent aarch64 guest repeats file tests on ext2, then host `e2fsck`
and `debugfs` check disk consistency and persisted protection flags.

The dispatch fixture checks generated C for interface/output promotion in the
production append helper. The fault fixture extracts the production ext2
attribute setter and exact-transfer wrapper unchanged. It injects read failure,
positive short metadata transfers, and write failure before/after publication.
It asserts policy state and lock release. Native guests measure slab deltas for
2,000 tunable writes and 2,000 zero-length appends against a separate
`/proc/slabinfo` reader control. The integrated metric reader retains zero
objects; the guest requires exactly zero growth in all 18 ARM64 or 14 x86 slab
classes and large pages for both repeated paths and the control. These measurements cover the
policy write and append dispatch paths, not every existing filesystem
allocation site.

Remaining findings: SEC3 needs an administrator trust/key format, signed ELF
metadata and executable fault validation bound to writable aliases; SEC4 needs
registered mandatory policies and object-label lifecycle; SEC5 needs physically
separate typed/data allocation domains with real callers; SEC6 needs protected
credential/security storage and narrow updates without writable aliases; SEC9
still needs authenticated boot artifacts/root and a defined developer mode.

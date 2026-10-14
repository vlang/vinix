# Persistent UNIX socket qualification

Binding a pathname used to discard its original filesystem resource. The live
endpoint's unlink callback then returned success without removing the ext2
directory entry or updating the endpoint's link count. Replacing another socket
also left its zero-link inode without the resource needed for final cleanup.

The VFS now transfers that original resource into the socket before publishing
the endpoint, under the same writer transaction. Socket link/unlink operations
delegate to it and publish a new link count only after backend success. The
endpoint retains the backing reference while pathname, descriptors, overlay
entries or peer pointers retain it. Its final retirement winner reconciles the
VFS link count, including rename replacements, and releases the backing resource
after grace. The repository-required independent lifetime review checked the
source and generated C on both architectures; no new boxing or pointer promotion
was introduced by these changes.

On 14 October 2026, native QEMU guests ran the V `--case sockets` fixture as
UID/GID 1000 with supplementary groups cleared and networking disabled. Root
prepared the private 128-MiB ext2 volume and mounts. Controls and fixes use the
same final fixture and declaration-only ABI header.

| Retained state under `build/development17-20261013` | Result |
| --- | --- |
| `socket-arm-before-d`, `socket-x86-before-e` | Saved committed kernels report nlink 1 after successful unlink; held-descriptor assertion 410 fails. Read-only `debugfs` still finds `socket-target` on disk. |
| `socket-arm-after-b`, `socket-x86-after-b` | Replacement, live connections, unlink/rebind, held `O_PATH` descriptors, hardlinks, cross-parent moves, permission refusal and read-only remount all pass. |
| `socket-arm-all-a`, `socket-x86-all-a` | Existing concurrent replacement, backend rename failure, mixed lifetime, disk persistence, whiteout and opacity regressions pass. |

Each socket batch performs 32 cycles on direct ext2 and 32 on the overlay upper.
Every cycle replaces a bound socket, establishes a connection, unlinks its path,
transfers a byte through the surviving connection and rebinds/removes the name.
Both batches settle for 25 seconds. All 18 ARM slab classes and the large count,
and all 14 x86 slab classes and the large count, remain equal. The mixed lifetime
regression also stays flat. All four final volumes pass read-only `e2fsck -f -n`.
The global allocation audit still fails with the same 182 baseline file/kind
findings; its allowlist was not expanded.

| Final input | SHA-256 |
| --- | --- |
| AArch64 kernel | `9054b02f690f92b4310f56acb464070615d8a54a9cc170f32041dd5d38fe28e1` |
| x86_64 kernel | `7869a8bd447b308acbb0f26a5e2e1170bf411c2c84085ecde63025f733fc64f7` |
| Socket fixture | `8115a51d2e0ac1118999f2265a5b7e29ce3a6d33c22f82635d89ef6e25ad180f` |

The kernels were built in the existing isolated `9b01dbca2` worktrees with the
previous filesystem fixes and this socket patch, using the preserved
`f6358ec` V compiler and kernel link seed 17. A concurrent per-open creation
bookkeeping change in the shared checkout is outside those worktrees; the V
evidence checker normalizes only its three exact source differences. The
assertion-enabled host checker verifies source/input hashes, control failures,
complete memory samples, native verdicts and all four read-only filesystem
checks. The ARM desktop regression's boot-disk kernel was extracted while the
guest was running and independently matched to the qualified kernel.

Early fixture ABI compilation failures and host disk exhaustion attempts are
retained separately. `socket-arm-after-a` reached guest PASS but could not write
its receipt, and `socket-x86-after-a` could not stage its ISO; neither is a final
qualification result. Only completed owned scratch was reclaimed; kernels,
volumes, serial logs and available receipts were preserved.

This qualifies clean namespace changes and resource retirement. Power-loss
recovery, injected backend I/O failures, wider socket metadata interfaces and
full database/server/container qualification remain open.

## Metadata description release

A second correction preserves a listening endpoint when a separate `O_PATH`
description closes. The prior unref callback treated every non-null Handle as a
transport close. The extended fixture closes such a metadata description before
connecting to the renamed listener. Both kernels from the namespace correction
fail that connection with `ECONNREFUSED` at assertion 407. The callback now treats
an `O_PATH` release like a namespace/epoll reference release while other owners
remain; the existing last-reference cleanup still runs. Independent review
verified Handle lifetime, short-circuiting before a null dereference and
allocation-free generated C on both architectures.

`socketpath-arm-before-a` and `socketpath-x86-before-a` retain the failing
controls. `socketpath-arm-after-a` and `socketpath-x86-after-a` pass the extended
socket test, including closing metadata descriptions during every cycle on both
backends. The `socketpath-*-all-a` regressions also pass. Complete live allocation
samples stay flat, writes-after-free counters stay zero, and all four volumes
pass read-only filesystem checks. The global allocation audit retains the same
182 baseline findings.

| Metadata-release input | SHA-256 |
| --- | --- |
| AArch64 kernel | `b7bb1185d65cabe39eaf1f756096ed6e5c6603f1c538a0b9222d81d5483493dc` |
| x86_64 kernel | `48a27d88d0e8e2f852a7821d91ea5412c4cf6b708a7ba92c575ad9d8becab576` |
| Extended socket fixture | `a94360c44d8ad9072f392ee1cb906c4bc6ad64f7523c2d5af21d72fb80bfaa9e` |

The broader ARM syscall/churn/cache/desktop run uses the preceding namespace
kernel, independently extracted from its boot disk. The metadata-release kernels
are qualified by the extended native socket tests and complete overlay
regressions above.
That ARM run completes 36 batches of 200 syscalls with zero bytes retained per
operation, and four batches of 300 short-lived processes with zero retained
bytes or additional slab pages. It also passes the 32-MiB cache workload
(16 MiB cached) and the idle, app and drag checks. Its JSON, serial log, screenshots
and assertion-enabled evidence result are retained as `socket-desktop-perf-a*`
and `socket-perf-evidence-checked.log` under the same artifact root.

The subsequent [socket metadata authorization correction](socket-access.md)
prevents these filesystem descriptions from being used for transport operations,
while preserving metadata queries and descriptor passing.

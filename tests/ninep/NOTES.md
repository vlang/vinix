# Mission16-A implementation limits and safety contract

The client implements the canonical 9P2000.L operations: version, attach,
walk, lopen, lcreate, read, write, clunk, getattr, setattr, readdir, fsync,
mkdir, renameat and unlinkat. The brief's stat/wstat/create/remove/rename
names are provided through these Linux-dialect operations, not through a
second legacy 9P2000 protocol. Unknown mount options and unsupported dialects
are rejected. Options trans=virtio, version=9p2000.L, cache=none and bounded
msize=4096..65536 are accepted. Policy flags remain enforced by the VFS.

V cannot import a module component beginning with a number. Production
protocol files are therefore in kernel/fs/ninep rather than kernel/fs/9p.
The import probe and failure are recorded in m16a-driver-codex.log; the host
suite compiles the actual replacement import and production sources.

Up to 32 successfully initialized tag sessions are retained for the boot.
Each session's own tag bytes, requested msize and original attach UID key
the cache. Rejected cached mounts never close or free it. Ordinary and lazy
unmount only detach an attachment; the VFS retains its normal busy-path and descriptor
checks. There is no PID1-only unmount restriction. A new mount creates a new
root view, using the existing connection without renegotiating or resetting
another view's FIDs. This avoids unsafe claims that every copied namespace,
private thread mount table or nsfs description has released the backend.

Retention is intentional and bounded: each session has 65536-byte request and
reply buffers, a bounded split ring, at most 1024 resource nodes and 2048
FIDs including temporary and opened FIDs. Namespace nodes follow the VFS
permanent mount-cache model. Repeated remounts consume bounded root-view slots
and ultimately fail ENOSPC instead of allocating without limit. Temporary
operation FIDs are clunked. Open descriptions share one retained server FID
per access mode of a resource, so read, write and fsync can continue after
unlink. Each mode's last description close clunks its FID; dup/fork share a
description and O_PATH does not open a server FID. Ordinary unlink/grace
reclamation clears resource slots and releases FIDs after retained descriptions
close. Unmount does not reclaim sessions or cached root views. A poisoned
cached session refuses further operations and mounts until reboot; it is
never transparently reset under retained users.

The AMD64 transport handles transitional virtio-9p PCI via the legacy BAR0
interface. Modern-only PCI is not supported. ARM code handles legacy QEMU
MMIO v1, not modern MMIO v2; ARM runtime remains unqualified until explicitly
reported. Distinct exported tags have separate devices, sessions, FID budgets
and buffers. Active PCI binding pins the DMA domain, refuses suspend while
claimed, and has no hot-remove teardown that could free in-flight mappings.
Suspend/hotplug are not qualified features.

All external sizes are validated before copies or allocation. A timeout or
invalid completion resets before freeing DMA. Failed reset quarantines all
mappings for the boot. The client marks itself dead and clears buffer pointers
on transport failure. begin/call/negotiate/cleanup reject dead sessions before
accessing packet buffers. Malformed replies poison the client; server errno
replies are bounded numeric errno values, never allocated error strings.

Data is not cached. Read/write/open and permission callbacks fetch remote
attributes. The stat-snapshot callback refreshes and copies attributes under
the session lock, using a retained opened FID when available so descriptor
stat can observe the unlinked inode as well.

New host names are discovered, but host removal/replacement of a cached name
fails closed with EBUSY. Cached populated subtrees are never retired by a
permission callback. A fresh remount view can observe the changed namespace.
Symlinks, special files, hardlinks, xattrs/ACLs, mmap and rename replacement
are not implemented. This is not a full POSIX/coherent-host-namespace claim.
Regular-file creation requests O_EXCL from the server even when the caller
did not request it: the VFS invokes this callback only for an absent name.
A competing host creator therefore returns EEXIST without modifying its file;
the VFS applies the caller's O_EXCL policy and any ordinary retry.

Guest namespace mutations record publication using fixed owned name bytes.
Discovery refuses EBUSY between backend RPC completion and VFS publication,
so it cannot create a duplicate node or retire the source of an in-flight
rename. Tests include discovery before publication and before name adoption.

chmod uses the actual ModeResource hook and a mode-only setattr. Other
metadata persistence compares edits with the previous host snapshot, fetches
fresh attributes, rejects same-field conflicts, and sends only changed fields.
This is not a server-side atomic compare-and-swap: an independent host writer
can still race the RPC. Concurrent guest metadata writers also inherit the
VFS's non-transactional stat editing. Fixed attach credentials are not
multiuser server authentication; local VFS permission checks remain in force.

The V host suites copy production protocol, facade and transport sources.
They cover malformed lengths/counts, overflow, FID bounds, completion policy,
timeout cleanup/quarantine, retained descendants, namespace publication,
chmod, selective metadata masks, cached remount behavior, host creation races,
open-description rollback and unlink/read/write/fsync with final-FID release.
Both host runners accept V and CC overrides (CC defaults to clang); the
facade tests compile the production owned-open dispatch as well as the backend.
Actual kernel builds and disposable-QEMU receipts are recorded separately in
the mission report. Host simulations are never presented as guest receipts.

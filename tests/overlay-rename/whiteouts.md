# Durable ext2 overlay whiteouts

An overlay with an ext2 upper now uses real 0/0 character inodes to hide deleted
lower entries. Unlink and empty-directory removal replace the upper name through
the backing rename. A lower-source rename moves the copied-up inode and installs
its source whiteout in one backing transaction. The overlay publishes its maps
after the backing operation succeeds.

Recreating a file, symlink, directory or hardlink over a marker stages the new
inode privately. The previous marker stays named until identity/ACL setup and
the final backing rename succeed. Failed publication discards the candidate and
keeps the lower entry hidden. User device-node creation still requires its normal
authorization; overlay's internal markers do not grant that capability.

The upper and work parents must belong to the same filesystem and cannot overlap.
Persistent staging uses `workdir/work`, a real directory with permission bits
000 owned by the mount creator. Regular files, symlinks, mounts, foreign
filesystems and accessible work directories are refused. Removed layer/work
directories are refused even when reached through an open descriptor's
`/proc/self/fd` link. Resolution and owner registration hold the VFS lock so
directory removal cannot retire the node between those steps. Final ownership and
setgid inheritance come from the destination parent. Removing a work parent
invalidates every attached overlay's work pointer before normal descriptor/CWD
and grace-period retirement, allowing the removed inode to be reclaimed. Later
staging returns `ENOENT` without replacing the destination.

Use the [V guest controller](README.md) with isolated kernels and fresh state
directories. Root prepares the mounts; all overlay mutation workloads run as
UID/GID 1000 with supplementary groups cleared and networking disabled.
`--case all` includes concurrent replacements, backend errors, remounts,
recreation and removal of a work directory shared by two overlays. `--case disk`
checks the storage operations with the work directory left in place. Both cases
record immutable input hashes and retained serial logs. Run `e2fsck -f -n` on
the private volume only after the controller has retired its owned guest.

Qualification evidence is retained under `build/development17-20261013`.
Saved kernels from `9a20f3de8` in `whiteout-arm-before-b` and
`whiteout-x86-before-b` pass regular-upper persistence, then fail because the
renamed lower source reappears after overlay remount. Those controls retain their
earlier fixture, which predates the work-directory refusal/removal assertions.

| Final native run | Result |
| --- | --- |
| `whiteout-arm-after-e` | All cases pass; 2,496/4,224 concurrent reads, zero missing names, listings or bad data; read-only `e2fsck` clean. |
| `whiteout-x86-after-e` | All cases pass; 3,712/3,744 concurrent reads, zero missing names, listings or bad data; read-only `e2fsck` clean. |
| `whiteout-arm-disk-e` | Storage case passes with the work directory left in place; read-only `e2fsck` clean. |

Both runs preserve both names on rejected upper-source and lower-source renames,
hold replaced descriptors beyond the grace period, check directory parent link
counts, verify all three durable markers after remount, recreate all four entry
types and refuse further staging in both overlays after their shared work parent
is removed. Another volume remount checks recreated backing entries and hardlink
identity. The normal user's mount and mknod attempts remain unauthorized.

| Input | SHA-256 |
| --- | --- |
| Before ARM kernel | `fe2746f27759c3f1e27166fa0c785a093e73987a21e7d01a50766310c063bd26` |
| Before x86 kernel | `4ff3454595830483103c70d29328834a9743f4312ec2561c2faa8472c0ac163d` |
| Final ARM kernel | `11646c9e5d4e2bcd6272844a4565fe346d908e6e32457e8de0e02d80480d4a59` |
| Final x86 kernel | `7e0835f67468bce795d5cc5d90a1d7654c878bedd4ac46cf7ebf255cd6b1397a` |
| Final fixture | `6977458cb978192f71c3eca4e595600d0f430ba7325bdda287debb8c60364705` |

The isolated worktrees use the same `9b01dbca2` baseline as the earlier rename
qualification, with the filesystem patches from `eefa7da3a` and `9a20f3de8`
plus this change. Both kernels were compiled with the preserved
`compiler-f6358ec/v-from-bootstrap` snapshot and link-shuffle seed 17. This
excludes concurrent sessions' unrelated kernel edits. The independent source
and generated-C review on both architectures approved the final lifetimes,
rollback, lock order and work-owner invalidation; its record is retained in
`whiteout-lifetime-review.md`.

Both final kernels also pass the native authenticated HTTP/account/job/build
gate, in `whiteout-arm-http-c` and `whiteout-x86-http-c`, with 19 independently
validated records each. The allocation allowlist audit still fails: its 182
file/kind counts match the earlier rename qualification exactly, with no
allowlist expansion. `whiteout-evidence-final.log` records the input/source
identity checks, control failures, final guest verdicts, filesystem checks and
native gate counts.

The final overlay slab samples retain 4,018 additional size-256 objects, 2,012
size-96 objects and 4,037 size-16 objects after 2,000 replacements and grace
periods on each architecture. The earlier rename-only runs retain 4,023, 2,012
and 4,044 respectively; the new fixture also prepares and retires refused work
entries before sampling. These samples demonstrate continued broad overlay
retention, rather than a leak-free mount. The comparisons are retained in
`whiteout-slabs.log`.

The final ARM kernel passes the full `ops,churn,cache,idle,apps,drag` desktop
run. All 36 batches of 200 syscall operations retain zero bytes per operation;
all four 300-process churn batches retain zero bytes per run. The cache workload
writes 32 MiB and records 16 MiB cached; the three desktop scenarios pass their
process-count and duration checks. `whiteout-desktop-perf-d.json`,
`whiteout-desktop-shots-d`, `whiteout-desktop-serial.log` and
`whiteout-perf-evidence.log` retain the report, screenshots, complete capture and
validation. The extracted boot-disk kernel input matches the final ARM hash.
Some live echoed output was lost while the host disk filled; the complete
capture and final report contain all 36 operation records.

The initial implementation passed native assertions but its permanent work pin
left a removed directory's inode and block allocated. Independent review and
read-only `e2fsck` identified that new defect; the final implementation uses
intrusive work-owner tracking and invalidates the pointers before retirement.
Those failed checks remain in `whiteout-*-after-c-e2fsck.log`. ISO creation
failures caused by host disk exhaustion are retained separately. The partial
desktop run `whiteout-desktop-perf-b` was stopped when the work-pin correction
required new kernels; `whiteout-desktop-perf-c` was stopped when final mount
registration checks required another build.

This qualifies clean remount persistence and real name-rejection rollback on the
tested ext2 volumes. Plain ext2 does not provide crash-atomic transactions. This
suite does not qualify power-cut recovery, journaled overlay crash cuts,
persistent opaque-directory markers, foreign device-node encodings or a
mainstream rootless OCI runtime. Existing upper/lower overlay ownership still
retains nodes across repeated replacement; that broader lifetime issue remains
open. Roadmap section 17 remains incomplete.

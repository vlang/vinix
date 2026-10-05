# Cached procfs mount cycles

Vinix shares a cached procfs root between mounts of one PID namespace and
reuses inactive namespaces' trees. Mounting that root over itself previously
returned success, then made proc path resolution fail with ELOOP. Mounting it
over its own `sys` child left ordinary reads usable but hid the new mount from
mountinfo: the cached root's covering mount and the child's parent formed an
ancestry cycle.

`ProcFS.mount_checked` now selects the actual cached root under `procfs_lock`
and rejects targets in that root's own tree with EBUSY. This includes global,
current-view and inactive-view reuse, before assigning or retargeting a reused
view. `new_mount` handles the canonical `procfs` kind, including Linux's `proc`
spelling, through the permanent registered template. Denials allocate no unused
filesystem instance or interface box. Existing interface callers delegate with
a nil target. No cached tree is freed.

The guard follows bounded scalar parent pointers in the selected tree. This
fix covers procfs cached-root attachment and its own descendants; it does not
claim complete Linux procfs remount or generic bind/move graph semantics.

## Run

Use a worktree with the existing kernel dependency symlinks and build both
architectures. The VM drivers and ARM sysroot can come from the main checkout.

```sh
make -C kernel ARCH=aarch64 ALLOC_TRACK=1 LIMINE_MP=1 CC=clang \
  AR=/opt/homebrew/opt/llvm/bin/llvm-ar V=/path/to/v -j4
ALLOC_TRACK=1 NPROC=4 V=/path/to/v ./scripts/build-amd64.sh --no-userland --no-iso
python3 tests/procfs-mount/check-generated.py kernel/obj/blob.c
python3 tests/procfs-mount/check-generated.py build-amd64-kernel/obj/blob.c

VINIX_VM_RUNNER_ROOT=/path/to/main-checkout VINIX_QEMU_RT_NO_BUILD=1 \
  VINIX_KERNEL_DIR="$PWD/kernel" VINIX_QEMU_TIMEOUT=600 \
  python3 tests/procfs-mount/run.py
VINIX_VM_RUNNER_ROOT=/path/to/main-checkout \
  VINIX_AMD64_KERNEL="$PWD/build-amd64-kernel/bin/vinix" \
  VINIX_LIMINE_CACHE=/tmp/vinix-procfs-mount-limine VINIX_QEMU_TIMEOUT=600 \
  python3 tests/procfs-mount/run.py --arch amd64
```

The optional Limine cache holds only the small pinned bootloader files; the ISO
builder verifies their hashes. Each guest uses a standalone initramfs, without
building or copying a desktop image. `--case reuse` isolates the inactive-view
test; the default requires all five feature markers exactly once.

## Coverage and measured results

The full guest checks:

- 3,000 rejected self mounts in the initial namespace and 1,000 in a fresh PID
  namespace, alternating `proc` and `procfs`, with unchanged mountinfo, readable
  proc paths and a descriptor kept open across the denials.
- Rejected `/proc/sys` descendant mounts in both views, with unchanged graph.
- A legitimate same-view alias, read-only remount and `/proc` bind alias, each
  remaining readable and removable.
- A namespace's tree left mounted in the shared mount namespace after all its
  PID members are reaped. Four synchronized new PID namespaces each reject 128
  root and 128 `sys` descendant attachments. The old self link stays ENOENT,
  mountinfo stays unchanged and the original `sys/kernel/ostype` remains readable.
- Successful reuse at a different directory, which then retargets the old alias,
  and a fresh PID namespace's first proc mount over a different inherited tree.

Both final tracked production builds and both full guests pass. Denial samples
report these actual Slab values:

| Architecture | Initial 3,000 denials | PID namespace 1,000 denials |
| --- | --- | --- |
| ARM64 | 1,296 → 1,296 KiB | 2,160 → 2,160 KiB |
| AMD64 | 992 → 976 KiB | 1,388 → 1,388 KiB |

The measurement permits at most 16 KiB of startup variation after warming; no
denial sample grew here. Allowed tree construction, a few processes, and the
small directory fixtures are outside these repeated-denial samples. Existing
directory retirement and AMD64 process residuals are measured separately by
`tests/process-churn`; these results do not claim those lifetimes are fixed.

Inspection of both actual generated C files confirms direct borrowing of the
registered template's `_object`, no per-denial instantiate/box/memdup, one
selection lock with release on every return, all three ancestry guards before
inactive assignment/retarget, a nil-target interface delegate and persistent
receiver pointers in constructed roots. The ancestry walk itself allocates
nothing. Independent source, lifetime and generated-C review accompanies this
change.

The allocation audit still exits 1 on this base: 352 ARM and 245 x86 sites,
compiler exits 0/1, and 157 failing file/kind categories. All reported file/kind
counts and failing categories match the earlier baseline audit; no allowance
was changed. The x86 scratch-copy audit compilation remains distinct from its
successful production build. The report is
`/tmp/vinix-procfs-mount-alloc-audit.log`.

## Reproduction evidence

The unfixed draft is preserved against base `679ee739` under
`/tmp/vinix-procfs-mount-artifacts/baseline/`, with matching tracked ELFs/C and
its exact patch. Its old `kind == 'proc'` precheck was unreachable after type
normalization, so it is baseline evidence rather than a fixed build.

`/tmp/vinix-procfs-mount-{arm,amd64}-baseline.log` shows self mount returning 0
and subsequent mountinfo and meminfo reads failing with errno 40. The focused
ARM serial reuse baseline separately shows a stale-root mount returning 0 and
its meminfo failing with ELOOP. The descendant baseline prints the mountinfo
graph without the successfully mounted `/proc/sys` entry; the stale-descendant
baseline also shows the formerly invisible self link changed to `/proc/1`.

Those logs are `/tmp/vinix-procfs-mount-arm-reuse-serial-baseline.log`,
`/tmp/vinix-procfs-mount-arm-descendant-baseline.log` and
`/tmp/vinix-procfs-mount-arm-stale-descendant-baseline.log`. Initial concurrent
failure logs remain separate, since serial output can interleave. The earlier
equality-only stage and its passing guests are archived as superseded evidence;
its descendant graph assertion failed and prompted the ancestry extension.

Final logs are `/tmp/vinix-procfs-mount-{arm,amd64}-fixed.log`, the matching
`-fixed-build.log` files and `/tmp/vinix-procfs-mount-generated-checks.log`.
`/tmp/vinix-procfs-mount-artifacts/final/` records the final exact kernel patch,
ELFs/C, guest sources and hashes, including baseline graph and bind coverage.

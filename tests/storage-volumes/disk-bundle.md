# Offline disk membership qualification

Run the maintained V controller in new private work directories:

```sh
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --host --work /tmp/vinix-plan-disks-host
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --arch aarch64 --kernel /path/to/arm/kernel/bin/vinix \
  --work /tmp/vinix-plan-disks-arm
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --arch amd64 --kernel /path/to/x86/kernel/bin/vinix \
  --work /tmp/vinix-plan-disks-x86
```

`plan_disks_test.v` runs under ASan/UBSan with the existing plan, bundle, growth,
inspection and mapping tests. It imports complete empty/populated plans while
retaining existing desired geometry and modes. Invalid identities, rows and
duplicate keys/global slots leave all fields and inactive storage unchanged.
Empty first/middle/last removal preserves relative order and slot ownership,
clears trailing storage and retains one participant. Populated/absent/last-disk
removal fails. The 64-disk/64-slot set remains encodable at 6208 bytes after
removal and reenrollment. Real files verify checksums, unchanged sources and
previous bundle bytes, corrupt inputs, symlink/nonregular/missing source refusal,
wrong file types, no publication temporaries and syntax rejection before I/O.

Both wrappers run through the shared publisher fault fixture: EINTR and short
writes succeed; write/file-fsync/close/rename faults preserve the old bundle;
directory-fsync failure returns nonzero with the new complete bundle visible.
The source file survives every case. Publisher descriptors and temporaries drain.
Both complete architecture utilities pass the generated allocation/runtime
audit. Existing restore model and init sanitizer regressions remain enabled.

Actual guests reject populated/absent removal and repeated enrollment without
changing bytes. A valid empty plan with no attached physical match can be
enrolled offline and inspected. Live check and restore reject its absence
before actions, leaving existing generations unchanged. Forgetting it restores
the exact original bundle. Removing desired rows and their disk enrollment
preserves a held live descriptor and its data. With the omitted physical
identity changed, the remaining set still checks and replays successfully.
Reenrollment restores the exact desired bytes offline while live checks fail
until the physical identity returns; replay then keeps all generations.
`PLAN DISKS PASSED:` is required by the controller.

Each of 200 warmup and 200 measured cycles runs four successful membership
commands: preview and enroll two empty unavailable disks, then preview and
forget both by identity before live restoration. Including physical capacity verification
and pool membership/query/allocation, growth and expansion batch previews/publications,
there are forty commands per cycle, or 16000 utility processes. Strict
acceptance requires flat slab classes and large
allocation pages. The 1800-second allowance accommodates x86 TCG. A reordered
reboot runs production init against the actual disk-resident two-disk bundle,
requiring all five mappings, durable data, modes and replay idempotence.

Membership edits change saved enrollment only. They do not remove live mappings,
release physical extents or create storage pools/RAID. Bounds, serialized
administration, normal file permissions and subsequent live preflight still
apply. See [the command contract](../../docs/storage-volumes.md#offline-disk-membership).

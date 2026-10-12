# Bounded extent allocation qualification

Run the maintained V controller in private work directories:

```sh
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --host --work /tmp/vinix-plan-space-host
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --arch aarch64 --kernel /path/to/arm/kernel/bin/vinix \
  --work /tmp/vinix-plan-space-arm
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --arch amd64 --kernel /path/to/x86/kernel/bin/vinix \
  --work /tmp/vinix-plan-space-x86
```

`plan_space_test.v` runs with the existing plan tests under ASan/UBSan. An
independent sector-cell oracle checks all 256 small fragmentation patterns,
every nonempty subwindow and three alignments, including unsorted rows and
read-only occupancy. A brute-force placement oracle checks first fit and
insufficient contiguous space without changing existing desired rows. Tests
verify exact checksum roundtrips, all 65 possible gaps, cross-disk global slots,
4096-byte sectors, rounding near the u64 limit and an alignment of 2^63.
Invalid bounds/alignment, indices, slots, modes, versions and sizes preserve
both complete desired state and output storage.

Real files prove that inspection changes no bytes and allocation publishes the
expected geometry/mode. Duplicate slots, corrupt inputs, symlinks, directories
and missing files fail without replacement or temporary files. Strict CLI
argument counts, decimal overflow and invalid ranges/modes fail before I/O.
The allocation wrapper also runs every shared-publisher fault: interrupted and
short writes succeed; write/file-fsync/close/rename failures preserve old bytes;
directory-fsync failure returns nonzero after the new complete bundle appears.
Descriptors and temporary files drain. Both production architecture utilities
and guest fixtures undergo the generated allocation/runtime audit.

Guests require `PLAN SPACE PASSED:`. They verify aligned gap output, unchanged
inspection bytes, first-fit saved offsets and no implicit live creation. An
alignment-trimmed tail cannot satisfy another allocation; no-space and
cross-disk slot failures retain the complete bundle. An unlisted live mapping
at the selected extent blocks all preflight actions and restoration. Removing
the conflict allows explicit application with the expected read-only geometry
and unchanged raw data. Removing the desired row restores exact original bytes
while a held live descriptor and generation survive until explicit removal.

The repeated workload uses first-fit allocation for the scratch mappings in each
of 200 warmup and 200 measured forty-command cycles, including physical capacity
verification and pool membership/query/allocation, growth and expansion batch previews/publications,
for 16000 utility processes.
No scratch mapping is created. Slab classes and large allocation pages must
remain flat; the existing failure-only delayed snapshot does not relax the
strict verdict. A reordered second boot restores the actual persistent two-disk,
five-mapping bundle through production init and verifies data/modes/generations.

The caller chooses the allocation region. A gap is relative to saved desired
mappings, not filesystem free space or a live reservation. Kernel protections
and complete live mapping preflight still apply; pool/spanning/RAID behavior is
outside this increment. See [the command contract](../../docs/storage-volumes.md#bounded-extent-allocation).

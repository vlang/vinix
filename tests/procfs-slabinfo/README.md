# Slab statistics without formatter allocations

The production `/proc/slabinfo` path samples classes into caller-stack storage
and streams the requested byte range through `kernel/slabreport`. It keeps the
existing text schema, regenerates each read and samples shards under separate
locks. It does not promise an atomic whole-heap snapshot. The optional XNU zone
backend returns `EOPNOTSUPP`; its counters need a separate implementation.

`check.v` imports the actual production formatter through a relative module
link. Its explicit checks remain active with `-prod`. All offsets through EOF,
small/large/zero counts, guarded output, decimal boundaries and full-width
unsigned counters run against independent expected text. Huge offsets and
zero-length reads use a null output pointer to detect accidental writes.

```sh
v -cc cc -o /external/slabinfo-check tests/procfs-slabinfo/check.v
/external/slabinfo-check selftest
v -prod -cc cc -o /external/slabinfo-check-prod tests/procfs-slabinfo/check.v
/external/slabinfo-check-prod selftest
```

`prepare.v ROOT REVISION FRESH-WORKTREE baseline|fixed` creates a sparse Git
worktree and links this checkout's untracked kernel dependencies. Fixed mode
overlays only the three implementation files and removes the old conditional
snapshot filename. Build each architecture from clean outputs with
`PROD=true ALLOC_TRACK=1 LIMINE_MP=1 KERNEL_LINK_SEED=42`; preserve the kernel,
generated C, source/tool pins and logs before cleaning for the next target.
The retained qualification uses baseline `80087c58b` and the feature overlay.

`build-native.v COMPILER RECIPE-DIRECTORY FRESH-STATE` reuses an explicit
`generate.argv.json`/`link.argv.json` recipe. It changes the source/output paths
and compiler selection, keeps strict static links with format/pointer errors,
and retains commands, inputs and outputs. Use the 16 KiB/eighteen-class profile
on ARM and the default 4 KiB/fourteen-class profile on x86.

The native program verifies complete reports assembled from seven positioned
read sizes, output guards, zero reads and high-offset EOF, then measures 200
ordinary reads per credential group after the maintained warmup and grace.
It requires flat objects, backing pages and large pages, with zero corruption
counters. Different positioned request sizes own different syscall bounce
buffers, so their numeric snapshots need not match each other. Exact bytes
for partial ranges are independently checked by the host formatter controls.

Run it with the existing guest controller and restored launcher support:

```sh
build-support/run-v-tool.sh tests/linux-compat/execown-run.v \
  aarch64 /external/kernel /external/native /external/support \
  /external/fresh-native-state slabinfo 300
```

The controller pauses PID1 after completion and explicitly retires QEMU;
completion does not claim a natural guest shutdown. `generated.v BLOB.c` checks
all thirteen formatter/sampler functions and thirteen injected-allocation
refusals. It complements the required independent lifetime review.
`evidence.v COMPLETE-FOCUSED-STATE` checks the retained paired builds, final
native receipts, complete flat snapshots, source/input identities, generated-C
scope and unchanged allocation-policy refusals. Missing/duplicated rows,
missing completion, shortened cohorts and corruption counters must refuse.

`performance.v OWNER PREPARATION-PROFILE KERNEL FRESH-STATE` reruns the retained
fixed six-scenario ARM plan with the selected kernel. It preserves the qualified
owner/adapter, source/compiler inventories, operation counts, observer bounds,
grace waits and resource limits. Apply the original full-heap and reader-warm
checkers to the complete resulting serial log; successful execution alone does
not establish flatness or broader Linux/POSIX compatibility.

See [qualification and retained evidence](../../docs/linux-slabinfo-observer.md).

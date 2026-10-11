# Bundle inspection and read-only preflight qualification

The maintained V controller includes offline inspection and shared live
preflight tests:

```sh
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --host --work /tmp/vinix-bundle-check-host
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --arch aarch64 --kernel /path/to/arm/kernel/bin/vinix \
  --work /tmp/vinix-bundle-check-arm
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --arch amd64 --kernel /path/to/x86/kernel/bin/vinix \
  --work /tmp/vinix-bundle-check-x86
```

Use fresh work directories. The controller owns disposable disk images and
QEMU; neither command selects a host physical disk.

Host entries run under ASan/UBSan. Inspection tests verify MBR signature and
canonical GPT byte order, terminator/buffer canaries, offline operation,
unchanged saved bytes, final-symlink/corruption refusal and CLI argument rules.
Real output sinks exercise immediate write and buffered flush failures; online
flush failure also requires complete descriptor cleanup without mutation.
The growth syscall model also compiles the production complete-set preflight,
replacing only device discovery and synchronous status/identity/close boundaries.
It asserts read-only discovery, captured generations and old lengths, every
action kind, no create/grow calls, and closure of all retained descriptors on
late discovery, mapping and final identity failures. A restoration regression
uses the same preflight with writable discovery and applies the expected growth
and missing mappings. Both architectures' complete generated utilities retain
the allocation/runtime audit, and init policy sanitizer tests still run.

The guest captures actual command output. It requires saved MBR identities and
geometry, a grow/keep preview, a mixed create/keep/grow preview, and no action rows
when a later-disk or unlisted-extension conflict fails preflight. Successful and
failed checks leave capacities, generations, missing slots and bundle bytes
unchanged. First-boot acceptance requires `PLAN CHECK PASSED:` in addition to
the bundle/growth markers.

Each repeated cycle saves the bundle, plans unchanged capacity, checks explicit
growth, explicitly replays it, and runs boot restoration. After 200 warmup cycles,
200 measured cycles must retain no slab objects or additional large allocation
pages. The flushed ext2 bundle and phase marker stay in the guest filesystem for
a second boot with reordered physical disks. Production init restores the grown
views, and the fixture checks existing and extension data and idempotence.

These checks validate discovery/geometry previews. A preview does not reserve
configuration or promise that the later mutating ioctl will pass the kernel's
privilege, mount/swap, policy or resource checks. Administration remains serialized.
See [the command contract](../../docs/storage-volumes.md#bundle-inspection-and-preflight).

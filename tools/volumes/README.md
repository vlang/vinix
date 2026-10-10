# vinix-volume

Native V block-volume management utility. See
[the storage interface and limits](../../docs/storage-volumes.md) for commands,
privileges, ABI, lifetime and geometry rules.

`vinix-volume discard DEVICE OFFSET_BYTES LENGTH_BYTES` deallocates a range
through supported block backends. The offset and length are decimal bytes.
See the storage documentation for extent protection and interruption behavior.

`vinix-volume save DEVICE PLAN` atomically saves the selected whole disk's
managed views. `vinix-volume restore DEVICE PLAN` verifies disk identity and
geometry, rejects conflicting slots and creates missing mappings. Repeated
restore keeps matching views. Use a persistent filesystem for the plan; disk
discovery and automatic boot replay are not provided.

The image builders call `build-support/storage-tools/stage.v`, which uses the
repository's V module producer and a static target musl compiler. To install it
into an existing target filesystem:

```sh
V=/path/to/v build-support/run-v-tool.sh build-support/storage-tools/stage.v \
  --arch x86_64 --staging /path/to/userland
```

For ARM, use `--arch aarch64` and `--cc` or `VINIX_MUSL_CC_AARCH64` to select the
cross compiler executable (arguments are not shell-split). Staging verifies the
compiler and output ELF architecture and
replaces only `usr/sbin/vinix-volume` atomically.

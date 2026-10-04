This native ARM fixture checks a genuinely read-only VirtIO disk backed by a
read-only NBD ext2 export. It reads and releases a `PROT_READ | MAP_SHARED`
mapping, synchronizes the file, then reads 16 MiB through an 8 MiB block cache.
A separate inode-table page and known file bytes must remain readable after
eviction. It also checks automatic read-only mounting, immutable bind and
filesystem aliases, and raw device writes returning `EROFS`.

Run each kernel in a fresh directory; failed reports are preserved:

```sh
VINIX_PRUNE_BUILD=0 python3 tests/virtio-ro/run.py \
  --work /absolute/path/to/results --kernel-dir /absolute/path/to/kernel \
  --runner-root /absolute/path/to/main-checkout
```

The runner records kernel, native fixture and source hashes. Its host files
stay read-only and their content hashes must remain unchanged. It uses only
virtual disks and makes no physical disk requests. `--prepare-only` compiles
and prepares the fixture without starting an exporter or VM.

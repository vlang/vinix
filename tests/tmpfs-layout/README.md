# What a tmpfs file costs

A tmpfs file of up to 2 KiB is one allocation from the kernel heap's slab
classes, 64 bytes at the least; anything larger is kept a page at a time.
Either way a file takes about what it holds.

It used to be one buffer for any file up to 1 MiB: whole pages, a power of two
of them as the buffer doubled, with the heap's page of bookkeeping in front. A
file of 100 bytes took two pages, which is 32 KiB where a page is 16 KiB, and
one of 70 KiB took 132 KiB. On a system that runs from memory, where the root
is a tmpfs, that is what every file a package installs cost.

`guest.c` is PID 1 of a 1 GiB guest. It writes files of sizes on both sides
of the limit a byte, seven bytes, a hundred and a page at a time and reads
them back; checks that holes and what a truncation cut read as zeroes; grows
a file across the limit by appending and by `ftruncate`; maps small files
privately and shared; and measures what ten thousand files of 100 bytes and
two thousand of 70 KiB take from free memory.

```sh
python3 tests/kernel-gaps/run.py --source tests/tmpfs-layout/guest.c \
    --arch aarch64 --kernel-dir kernel \
    --expect 'TMPFS-LAYOUT PASS all' --fail 'TMPFS-LAYOUT FAIL' --timeout 400
```

Use `--arch x86_64 --kernel-dir build-amd64-kernel` for amd64.

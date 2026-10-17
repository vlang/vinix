# Compressed image decoder

```sh
v run tests/initramfs-gzip/run.v
VINIX_GZIP_SAMPLE=build-release/work/amd64-desktop/initramfs-desktop.tar v run tests/initramfs-gzip/run.v
```

Release ISOs carry their image gzip-compressed, and the kernel inflates it
(`kernel/initramfs/gzip.v`). This runs that decoder on the host against the
system gzip at levels 1, 6 and 9, with and without a stored file name: text,
long runs, zeros, a one-byte and an empty file, incompressible data (stored
blocks), mixed stored and compressed data, and a real tar archive. It reads the
`vinix-image-id=` header comment the ISO scripts write without inflating, and
refuses a wrong CRC, a wrong recorded size, truncated data and any of 200 bit
flips that would change the output. `VINIX_GZIP_SAMPLE` also inflates a given
file, such as a release image, and prints the speed.

The decoder is compiled on its own, as in `tests/initramfs-writes`: it imports
nothing from the kernel. Release ISO boot checks then exercise it for real.

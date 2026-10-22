# Mission16-A guest qualification

`guest.v` is an ordinary V userland program using libc `mount(2)`, file I/O,
directory operations and `umount(2)`. It can be installed directly as `/init`.
It uses only standard C headers; no shell, `system()`, custom ABI header,
reboot or deployment helper is involved.

The parent owns compilation, the kernel, QEMU, host monitoring and commits.
For example, with a default V compiler and an existing musl cross compiler:

```sh
CC=/absolute/path/to/x86_64-linux-musl-gcc \
  /absolute/path/to/v -os linux -arch amd64 \
  -cc /absolute/path/to/x86_64-linux-musl-gcc -gc none -cflags -static \
  -o /parent/owned/output/init tests/ninep/guest.v
```

`-gc none` avoids needing a cross-built Boehm GC archive. The probe streams
large files through 64 KiB buffers. Its local copy requires at least 100 MiB
of free space on `/tmp` (and sufficient guest RAM if the root is tmpfs).
The parent should verify the output is a static Linux ELF before booting.

Prepare `/mnt` as an existing empty directory in the initramfs; `/dev` and
`/dev/com1` must already be supplied by kernel initialization. The probe
duplicates `/dev/com1` onto stdout and stderr. It creates `/tmp` if needed.
Export a fresh writable host directory under the fixed virtio mount tag
`share`, containing:

- `host-small.txt`: initial nonempty text different from `host-edit-v2\n`.
- `host-big.bin`: exactly 104857600 bytes; retain its host SHA-256 for comparison.

Do not precreate `guest-ready`, `host-updated.txt` or `m16a-directory`.
The parent host monitor must wait for `guest-ready` to contain `ready\n`,
overwrite **the existing host-small.txt file in place** with the exact bytes
`host-edit-v2\n`, close it, and only then create `host-updated.txt`. Do not
replace `host-small.txt` by atomic rename: the guest deliberately retains its
original open descriptor, rewinds it, and reads the same vnode after the
marker appears. The marker's contents are unrestricted. The guest waits at
most 90 seconds using a monotonic deadline; the parent still needs an overall
watchdog for a blocked filesystem operation or kernel failure.

All accepted stages emit `M16A:` serial lines. In order the probe:

1. Calls real `mount` with NULL, empty, unknown and malformed source tags,
   requiring `-1` and nonzero errno for each. The malformed candidate is
   `share/invalid` followed by LF; it must not select the valid `share` export.
   These checks require graceful rejection, without prescribing an errno.
2. Mounts `share` on `/mnt` as `9p` with
   `trans=virtio,version=9p2000.L,cache=none,msize=65536`.
3. Writes and reads back `guest-small.txt` containing
   `mission16-a guest-small-v1\n`, logging its SHA-256.
4. Logs initial host text as hex and SHA-256, writes `guest-ready`, waits for
   `host-updated.txt`, then verifies `host-edit-v2\n` through the retained fd.
5. Exercises mkdir/create/rename/read/list/unlink/rmdir, checking removed names
   return ENOENT. Listings use `os.ls` against the actual mount.
6. Copies `/mnt/host-big.bin` to `/tmp/guest-copy.bin`, hashes the source while
   copying, independently hashes the local readback, and checks both size and
   digest. Logs both SHA-256 values, copy time and total time in milliseconds.
7. Creates local `/tmp/guest-source.bin` as 1600 repetitions of a 65536-byte
   block whose byte at index `i` is `(i * 31 + 17) & 255`, then copies that file
   to `/mnt/guest-big.bin`. Hashes the generated stream and independently
   hashes the copy source and share readback, checking exactly 100 MiB. Logs
   both digests, write time and total time. The parent must independently
   verify the host file's size and SHA-256 against the generated digest.
8. Lists the share root, unmounts, remounts with the same options, verifies
   `guest-small.txt` and `guest-ready` persist, and finally unmounts.

The parent must compare the logged source digest with its own `host-big.bin`
digest and independently verify `guest-small.txt`, `guest-big.bin` and markers.
Mount success alone does not establish that the server negotiated every
requested option; protocol/device evidence belongs to the parent lane.

The terminal record is `M16A:OUTCOME PASS status=0 ... parked=1` or
`M16A:OUTCOME FAIL status=1 ... parked=1`, preceded by a detailed failure line.
Both outcomes sleep forever so PID 1 never returns and panics the kernel;
`status` is a logged result, not a process exit code. The parent terminates
only its owned QEMU after collecting the outcome and host verification.
There is no `--dispatch-regression` mode: tmpfs option parsing, proc, overlay
and parent-provided `/dev/sd0` ext2 checks remain separate optional tests.

Host controllers (V)

Compile `run.v` on fecv3, then invoke it with four absolute paths:
repository, production kernel ELF, compiled guest init, and a new output
directory. It refuses an existing directory, creates deterministic 100 MiB
fixtures, assembles a private ISO using the repository's existing builder,
boots QEMU with no NIC and a private QMP socket, performs the host edit
handshake, and independently verifies host hashes. A 300-second deadline
bounds the guest run. Its defer stops only that guest through its QMP socket.

Compile `badtag.v` and pass the exact positive qualification ISO plus a new
output directory. It boots that unchanged ISO with QEMU export tag `not-share`
instead of `share`. Success means the real guest mount returns ENODEV and
userspace reaches its parked failure outcome, not a kernel panic. This is an
expected-negative boot, not a file-sharing success. Both controllers retain
the QEMU argv, serial log, and host-verification receipts in their output dirs.

`../mount-specifier/guest.v` is the separate legacy-mount regression PID 1.
It needs a small disposable ext2 disk at `/dev/sd0` containing `fixture.txt`
with exactly `m16a-ext2-fixture` followed by LF. It checks tmpfs permissions
and write/read, proc meminfo, ext2 read/write, and overlay lower/upper paths.

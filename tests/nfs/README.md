# Mission17B disposable NFSv3 qualification tools

`guest.v` and `rig.v` are independent V programs. Compile each file separately.
The RW mountpoint is `/mnt/nfs`. The guest is a static Linux ABI PID 1 that calls libc `mount`, `open`, `read`,
`write`, `lseek`, `mkdir`, `rename`, `unlink`, `rmdir`, and `umount`; directory
enumeration uses V's libc-backed `os.ls`. There is no guest shell, mount helper,
Python, PVE deployment, host service management, or persistent guest disk.
The parent owns `kernel/fs/nfs`, `tests/nfs/protocol`, server provisioning,
the kernel build, the real static guest build, and wire/protocol evidence.

Build locally or on fecv3, using explicit existing toolchains:

```sh
/absolute/path/to/v -prod -cc cc -gc none -o /tmp/m17b-rig tests/nfs/rig.v
/absolute/path/to/v -prod -os linux -arch amd64 \
  -cc /absolute/path/to/x86_64-linux-musl-gcc -gc none -cflags -static \
  -o /tmp/m17b-init tests/nfs/guest.v
file /tmp/m17b-init
```

The parent must verify a **static x86-64 Linux ELF** before boot. On macOS,
`v -os linux -arch amd64 -gc none -o /tmp/m17b-guest.c tests/nfs/guest.v`
checks Linux C generation only; it does not establish static linking or runtime
qualification. Use a compiler with a matching, complete vlib and record its
version with the build receipts.

The rig requires `tar`, `xorriso`, `qemu-system-x86_64` with slirp and virtio
networking, a kernel ELF, and an existing bootable Limine ISO template containing
`/boot/limine-bios-cd.bin`, `/boot/limine-bios.sys`,
`/boot/limine-uefi-cd.bin`, and `/EFI/BOOT/BOOTX64.EFI`.
V orchestrates direct argument-vector tool calls. The rig extracts those four
boot files, writes its own minimal Limine config, and assembles a new CD with
BIOS and UEFI boot entries. It does not replay hybrid partition metadata,
invoke repository shell builders, download dependencies, or modify the template.
The CD is intended for QEMU `-cdrom`, not hybrid USB disk boot; no Limine
`bios-install` is needed for CD boot. Optional `--repo PATH` is accepted for
compatibility with the SMB2 rig's invocation and is unused.

The parent must provision a **dedicated disposable privileged kernel-nfsd
container in a separate network namespace**, named `m17b-*`:

- Publish rpcbind 111, nfsd 2049, and fixed mountd 20048 to **127.0.0.1 only**.
  Publish both TCP and UDP where the driver's rpcbind/MOUNT transport requires
  them. Keep mountd pinned to 20048; the rig does not start or alter host nfsd,
  rpcbind, mountd, firewall rules, or port mappings.
- Export the existing empty `--share` backing directory as `/export/share`,
  `rw,sync,no_subtree_check,no_root_squash,sec=sys`, with AUTH_SYS uid 0 able to
  create, rename, and delete files. This is a public disposable root fixture.
- Export the **separate existing empty `--readonly` backing directory** as
  `/export/readonly`, with actual server `ro,sync,no_subtree_check,no_root_squash,sec=sys`.
  The rig writes `m17b-ro.txt` there before boot. The guest mounts with flags=0
  and actually calls `write` on this existing file; a client read-only flag or
  only a write-open failure does not qualify. The host later verifies unchanged
  bytes. Mounting a server RW export read-only does not satisfy this gate.
- Do not export `/export/m17b-not-exported`. Retain server export configuration
  and packet/protocol evidence for AUTH_SYS, NFSv3, and READDIRPLUS. libc mount
  and listing receipts alone cannot establish wire procedure numbers. The
  parent must also check the kernel's helpful EXPORT listing after the denied
  missing-export mount; the tools require clean denial but do not guess the
  driver's diagnostic text.

The two backing directories must be empty, distinct, and neither nested in the
other. The rig refuses existing contents before creating its named fixtures;
it never clears a directory or overwrites an old qualification. Bind mount these
directories into the container before running. The server can serve the empty
directories while the rig prepares fixtures. Keep the container isolated from
real workloads: the final gate intentionally stops it.

Run on fecv3, with a new output path whose existing parent directory is outside
both backing directories:

```sh
/tmp/m17b-rig \
  --kernel /parent/build/kernel/bin/vinix \
  --init /tmp/m17b-init \
  --template /parent/images/bootable-limine.iso \
  --share /parent/m17b-nfs/share \
  --readonly /parent/m17b-nfs/readonly \
  --out /parent/runs/m17b-qualification-001 \
  --stop-container m17b-nfs-qualification \
  --timeout 900
```

`--out` must not exist and its basename must start `m17b-`; the rig creates it
mode 0700. Timeout is an integer 30..900 seconds, default 900, starting at QEMU
launch; independent bounded watchdogs cover ISO tools and Docker calls. Default
acceleration is KVM; use `--accel tcg` if needed. `--qemu PATH` selects a QEMU
executable. BIOS is default; `--firmware /path/to/OVMF_CODE.fd` attaches a
read-only pflash CODE image for UEFI. Budget 2 GiB guest RAM, 200 MiB local
guest tmpfs for two real 100 MiB files, and at least 500 MiB host space plus
kernel/template artifacts. Every retained run artifact uses `m17b-*` naming.

The QEMU user network is
`user,id=m17bnet,net=10.0.2.0/24,host=10.0.2.2,dhcpstart=10.0.2.15`, with
`virtio-net-pci,netdev=m17bnet`. Slirp's host address reaches the host loopback
container publications. There are no guest-forwarded ports, host forwarding
helpers, shared filesystems, extra disks, or daemonized QEMU processes.
The initramfs contains only the static `/sbin/init`, empty mount directories,
and `/etc/hosts` plus `/etc/m17b-sources`. `/etc/hosts` includes
`10.0.2.2 fecv3`. The default sources are explicitly raw IP:

```text
10.0.2.2:/export/share
10.0.2.2:/export/readonly
10.0.2.2:/export/m17b-not-exported
```

Kernel `/etc/hosts` support is not assumed or claimed. The mount receipt says
`hostname_mode=raw-ip-hosts-unproven`. If the parent verifies hosts resolution,
pass `--source fecv3:/export/share`, `--ro-source fecv3:/export/readonly`, and
`--missing-source fecv3:/export/m17b-not-exported`; the guest reports the exact
configured source. There is no silent hostname-to-IP fallback.

PID 1 mounts devtmpfs if needed, redirects stdout/stderr to `/dev/com1`, checks
uid=0/euid=0, and waits up to 30 seconds for the kernel DHCP publication of a
nameserver in `/etc/resolv.conf`. Every NFS mount is a real libc
`mount(source, target, "nfs", 0, "soft,rsize=65536,wsize=65536")` call, with the RW target `/mnt/nfs`. The
first RW mount retries only network reachability/connection errors, at most
three attempts with one-second pauses. The remount and both other export mounts
each get exactly one attempt. All mount calls report rc/errno; successful
receipts normalize errno to 0 rather than printing stale libc errno.

The guest emits `M17B:` receipts only after the following assertions:

1. RW mount, write/read exact `mission17b guest-small-v1` plus LF in
   `guest-small.txt`, and SHA256. Host verification independently hashes it.
2. Read `host-small.txt`, retain that open descriptor, create `guest-ready`,
   and wait up to 90 seconds for `host-updated.txt`. The rig opens the existing
   host inode with `r+`, overwrites the same 13 bytes in place from `host-edit-v1`
   plus LF to `host-edit-v2` plus LF, closes it, and creates the marker. The
   guest rewinds the retained descriptor and requires the new exact content.
   Replacing the inode or reopening the guest descriptor does not qualify.
3. `mkdir m17b-directory`, create a file, rename `before.txt` to `after.txt`,
   list and require the renamed entry and absence of the old entry, read its
   content, unlink it, rmdir, and require ENOENT after each deletion. The parent
   correlates these real getdents/listing calls with READDIRPLUS evidence.
4. Copy the real 104857600-byte `host-big.bin` to local `/tmp/guest-copy.bin`
   through a 65536-byte buffer, hashing the source and independently hashing
   the local result. Copy that same local file back to NFS as
   `host-roundtrip.bin`, close it, and independently hash its NFS readback.
   Record bytes, SHA256 and timing. The host separately hashes the returned
   backing file and original. A synthetic digest without file I/O cannot pass.
5. Generate another real local 100 MiB `/tmp/guest-source.bin`, copy it to
   NFS `guest-big.bin`, and hash its readback. Each source consists of 1600
   65536-byte blocks: byte `i` is `(i * 13 + 7) & 255` for the host source and
   `(i * 31 + 17) & 255` for the guest source. The host generates an independent
   expected guest file and hashes the actual output, rather than trusting the
   serial's claimed digest.
6. List root entries, close descriptors, unmount/remount RW, verify the small
   file and marker persist, and hash the full returned 100 MiB again. Retain
   this RW mount through the shutdown gate.
7. Attempt one mount of the missing export on `/mnt-negative`. Require clean
   `-1` with EACCES, ENOENT or EPERM, the MOUNT denial variants; a transport
   failure or silently accepted mount fails the gate. Continue in userspace.
8. Mount the actual RO export on `/mnt-ro` with flags=0, read its fixture,
   open the existing file O_WRONLY, and attempt **actual `write(fd,"X",1)`**.
   Require `-1/EROFS` (30), close and unmount. Unsupported open behavior that
   prevents reaching the actual write is reported as a failure.
9. Open existing `m17b-stop-probe.bin` on the retained RW mount, without reading
   any of its 8192 unique fixture bytes. Emit exactly
   `M17B:stop-server-ready quiet_seconds=2 wait_seconds=8 retained_rw_mount=1`.
   Make **no NFS calls for eight seconds**, including the initial two-second
   quiet window. The rig stops its explicitly named dedicated container once.
   After the wait, attempt the first real 4096-byte read on that descriptor.
   Require a negative transport failure within 20000 ms. Reading existing
   never-read content avoids passing on a cached negative lookup or cached
   metadata. A successful read, EOF, panic, blocked operation or arbitrary
   programming errno fails. Accepted failures are EIO, EPIPE, ENETDOWN,
   ENETUNREACH, ECONNABORTED, ECONNRESET, ENOTCONN, ETIMEDOUT, ECONNREFUSED,
   EHOSTDOWN or EHOSTUNREACH; the exact transport failure depends on shutdown.
   Emit the raw rc/errno/elapsed time, then perform local write/read syscalls
   and emit `userspace-continues PASS`. Do not unmount the dead RW server.

`--stop-container` is optional only to allow an external parent controller to
stop the same dedicated server on the serial barrier. Omitting it **does not
skip the shutdown gate**: the rig prints a manual-stop receipt and the guest
still demands a bounded transport failure. The parent must preserve its own
stop evidence in that mode. With the option, the rig rejects names without the
`m17b-` prefix, inspects the exact running container name/network namespace and
immutable ID, and stops that ID with one `docker stop --time 1` invocation after
the complete serial receipt. The ID prevents a reused name targeting another
container. No Docker stop retry, container restart, host service stop, or cleanup
stop happens. A failed/uncertain Docker command aborts with its retained log.

PID 1 emits `M17B:OUTCOME PASS status=0 ... parked=1` or a detailed failure and
`M17B:OUTCOME FAIL status=1 ... parked=1`, then sleeps forever. It never exits
PID 1. The rig drains both child output pipes, polls complete serial lines,
detects panic/failure, prints progress every ten seconds, checks required
receipts and their order/fields/timings, independently hashes host files, and
checks small contents, RO preservation and directory cleanup. It writes
`m17b-host-verification.txt` and prints the independent hashes before reporting
`M17B-HOST:OUTCOME PASS qemu-stopped=1`. This host PASS, plus the parent's server,
EXPORT diagnostic and wire evidence, is the qualification evidence chain.

The watchdog/error/success paths kill and reap **only the exact QEMU child**.
Cleanup uses POSIX kill/waitpid directly, retrying interrupted waits; it avoids
the V 0.5.2 signal_kill/wait state interaction that can leave zombies.
They never use process-name kills, process groups, shared PID files, or stop
host services. SIGKILL of the rig bypasses its cleanup; retained
`m17b-qemu.pid` and `m17b-qemu-argv.txt` identify its child for parent inspection.
All logs, generated ISO/root, input SHA256 manifest, fixture backing files and
expected data remain in place for review; there is no automatic deletion.

Audit existing artifacts without another boot or server stop:

```sh
/tmp/m17b-rig --verify /parent/runs/m17b-qualification-001 \
  --share /parent/m17b-nfs/share --readonly /parent/m17b-nfs/readonly
/tmp/m17b-rig --hash /parent/m17b-nfs/share/host-roundtrip.bin
sha256sum /parent/m17b-nfs/share/host-roundtrip.bin
```

`--verify` validates the saved run; it does not establish current server health
or substitute for a new guest execution. `--hash` is a standalone streaming
host utility with no guest qualification claim. Its V read loop accepts EOF
only after exactly the initial file size and rejects read failures or changing
length. This lane makes no production driver changes and performs no commits
or pushes.

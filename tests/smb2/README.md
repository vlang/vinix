# Mission17A disposable SMB2 qualification

These two standalone V programs are qualification tooling, separate from the
production driver and protocol tests. They do not provision Samba, modify host
services, deploy to PVE, register anything, or commit. The parent owns the kernel,
static guest build, private Samba container, and protocol/authentication evidence.

Build on fecv3 with an existing V compiler and musl cross compiler:

```sh
/absolute/path/to/v -cc cc -gc none -o /tmp/m17a-rig tests/smb2/rig.v
/absolute/path/to/v -os linux -arch amd64 \
  -cc /absolute/path/to/x86_64-linux-musl-gcc -gc none -cflags -static \
  -o /tmp/m17a-init tests/smb2/guest.v
file /tmp/m17a-init
```

Verify the guest is a **static x86-64 Linux ELF**. Compile the files separately;
they are independent `module main` programs. No Python, guest shell or dynamic
libraries are needed. Local checks can generate Linux C with `v -os linux
-gc none -o /tmp/m17a-guest.c tests/smb2/guest.v`; that is not a guest execution.

Requirements: `tar`, `xorriso`, `qemu-system-x86_64` with slirp and virtio networking,
an existing bootable amd64 ISO template from `build-support/build-amd64-iso.sh`, and the parent's SMB2-capable
kernel ELF. The rig uses the maintained `build-support/build-amd64-iso.sh`
assembler with explicit kernel, minimal initramfs, build-directory and output
overrides. The required reference template is checked but left untouched; its
hybrid partition metadata is not replayed. BIOS is the default; pass `--firmware` for a
read-only OVMF CODE image if needed. No guest data disk is attached. Default
acceleration is KVM; `--accel tcg` is available. Budget 2 GiB guest RAM, 200 MiB
local guest `/tmp`, and several hundred MiB host disk plus the template's size.

The parent must configure a **private disposable Samba container** before boot:

- Publish only `127.0.0.1:445:445`; do not start, stop or reconfigure host Samba.
- `[share]` exports the dedicated directory passed to `--share`, authenticated RW
  for user `m17a`, domain `WORKGROUP`, with the public disposable credential in
  `guest.v`. Configure NTLMv2 authentication and SMB2; disable NTLMv1. Do not use
  a real account or password. The probe never logs its option strings.
- `[guest]` exports **the same backing directory**, anonymous `guest ok = yes`,
  **server `read only = yes`**. Samba's Unix identity must read the fixture files;
  the authenticated identity must create, rename and delete files. Configure
  `map to guest = Never` and use an anonymous guest-only share, so named
  wrong-password authentication cannot silently become a guest session.
- Do not define `m17a-missing-share`. The driver must support anonymous mount
  option `guest` and translate server write denial on a read-only share to EROFS.

The share directory must already exist and be empty. The rig refuses any existing
contents and writes only its fixture names there. Give the container the backing
directory before running the rig; it may serve that initially empty directory.
Run entirely on fecv3, with fresh absolute paths, for example:

```sh
/tmp/m17a-rig \
  --repo /home/agent/build/vinix-smb2 \
  --kernel /parent/build/kernel/bin/vinix \
  --init /tmp/m17a-init \
  --template /parent/images/bootable-limine.iso \
  --share /parent/m17a-samba/share \
  --out /parent/runs/m17a-qualification-001 \
  --timeout 600
```

`--out` must be new and its basename must start `m17a-`; it is created mode 0700.
All run artifacts and logs use `m17a-*` names. QEMU runs as a direct child with
`-netdev user,id=m17anet,net=10.0.2.0/24,host=10.0.2.2,dhcpstart=10.0.2.15`
and `-device virtio-net-pci,netdev=m17anet`. The rig creates no SMB forwarding helper,
virtio shared filesystem, QEMU daemon, shared process-name kill, or port scan.
The guest connects to `//10.0.2.2/share` on direct TCP 445; slirp's host address
reaches the container's loopback publication. No alternate server port is assumed.

The initramfs installs the probe as `/sbin/init` and includes `/dev`, `/proc`,
`/mnt`, `/tmp`, `/etc`. PID1 mounts devtmpfs if `/dev/com1` is absent, redirects
stdout/stderr to it, then polls for the kernel's DHCP resolver publication for
30 seconds. `/etc/resolv.conf` starts absent: its appearance with a nameserver
is the network-ready signal. The initial real libc call is
`mount("//10.0.2.2/share", "/mnt", "smb2", 0, options)`, with options
`user=m17a,domain=WORKGROUP,password=<disposable fixture>`.
It makes at most three attempts, retrying only ENETUNREACH, EHOSTUNREACH,
ENETDOWN, ETIMEDOUT or ECONNREFUSED, with one-second pauses. EACCES is never
retried. Subsequent mounts each get one attempt: five SMB2 attempts normally,
at most seven including startup retries. Failed mounts release their session slot;
the authenticated remount reuses its session. The driver retains at most four
published sessions, not one slot per attempted mount.
The host watchdog bounds a blocked syscall as well as a hung kernel.

Every accepted guest stage emits `M17A:` only after its assertions:

1. Authenticated mount, small known-content write/read and SHA256.
2. Retain an open `host-small.txt` descriptor, create `guest-ready`, and wait
   up to 90 seconds for `host-updated.txt`. The rig overwrites the existing host
   inode in place with `host-edit-v2` plus LF, closes it, then creates the marker.
   The guest rewinds the retained descriptor and requires the new exact bytes.
3. Directory create/list/rename/delete, checking contents and ENOENT after removal.
4. Copy the actual 104857600-byte `host-big.bin` through a 64 KiB buffer to
   local `/tmp/guest-copy.bin`. Stream-hash the source and independently hash
   the local file. Copy that local file back to `host-roundtrip.bin` on SMB2
   and independently hash its readback: the same 100 MiB travels both directions.
   The rig also hashes that returned host file against the original fixture.
   Log size, digests, copy time and elapsed milliseconds.
5. Create a real local 100 MiB `guest-source.bin`, copy it to `guest-big.bin`
   on SMB2, then independently stream-hash the share readback. The source is
   1600 blocks of 65536 bytes, block byte `i = (i * 31 + 17) & 255`.
   The host source uses `(i * 13 + 7) & 255`. No synthetic-only hash qualifies.
6. List the root, unmount/remount, require persisted small file and ready marker,
   then unmount. File descriptors are closed before unmount.
7. Exactly one wrong-password mount requires `-1/EACCES`; exactly one missing
   share mount requires `-1/ENOENT`. Execution continues in userspace.
8. Anonymous `//10.0.2.2/guest` mount with **flags=0**, read the shared fixture,
   and require `open(existing-file, O_WRONLY)` to return `-1/EROFS`. This is
   deliberately not a client read-only mount. Unmount and emit continuation.

The authenticated mount receipt identifies the NTLMv2 fixture requirement;
libc mount success alone cannot prove the negotiated authentication mechanism.
The parent must retain Samba/protocol evidence for NTLMv2. A different errno,
unsupported option, stale retained descriptor, panic, or timeout is a failure,
not a waived qualification. This tooling supplies no production compatibility fix.

PID1 emits `M17A:OUTCOME PASS status=0 ... parked=1` or a detailed failure and
`M17A:OUTCOME FAIL status=1 ... parked=1`, then sleeps forever in both cases.
It never exits PID1. The rig polls serial every 100 ms, prints milestones with
elapsed time and ten-second progress updates, verifies every required receipt,
independently hashes both host files, checks small contents and cleanup, and
writes `m17a-host-verification.txt`. **Only then** does it report host PASS.
Its normal/error cleanup kills and reaps only its own QEMU child. SIGKILL of
the rig bypasses cleanup; the retained `m17a-qemu.pid` and argv identify its
specific child for parent inspection, never a blanket QEMU kill.

Host verification can be resumed without rebooting or spending more sessions:

```sh
/tmp/m17a-rig --verify /parent/runs/m17a-qualification-001 --share /parent/m17a-samba/share
/tmp/m17a-rig --hash /parent/m17a-samba/share/guest-big.bin
sha256sum /parent/m17a-samba/share/guest-big.bin
```

The V hash loop treats `os.Eof` plus actual EOF at the expected size as successful
completion; other read errors and changing lengths fail. `--hash` is a host-only
utility and makes no guest qualification claim. Preserve the run directory and
backing share for the parent's review; neither is automatically deleted.

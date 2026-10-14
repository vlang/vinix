# Overlay rename qualification

This V controller runs native Vinix guests with a private tmpfs overlay and,
for disk cases, a fresh 128-MiB ext2 volume (4 MiB for `opaque-full`). Root prepares
the mounts and transfers the private directories; all rename workloads run as
UID/GID 1000 after clearing
supplementary groups. An unprivileged mount attempt must fail with `EPERM`.
An unprivileged device-node creation attempt must also fail with `EPERM`.
The parent performs the final unmount/remount check after the worker exits.

Build each kernel in an isolated worktree with the dependency symlinks described
in `AGENTS.md`, then use fresh result directories:

```sh
V_C_ERROR_BUG_REPORT_DISABLED=1 USE_TCG=1 build-support/run-v-tool.sh \
  tests/overlay-rename/run.v --arch x86_64 \
  --kernel-dir /path/to/x86-worktree/kernel --state-dir /path/to/fresh-x86-result

V_C_ERROR_BUG_REPORT_DISABLED=1 USE_TCG=0 build-support/run-v-tool.sh \
  tests/overlay-rename/run.v --arch aarch64 \
  --kernel-dir /path/to/arm-worktree/kernel --state-dir /path/to/fresh-arm-result
```

The ARM command uses HVF on macOS; use TCG without host acceleration. The
controller uses the maintained guest build/boot tools, a declaration-only musl
ABI header and `mke2fs` (`VINIX_MKE2FS` can select it). It owns a QEMU process with
networking disabled and records kernel, fixture, ABI, init, ISO and disk hashes
in `receipt.json`. Guest serial output is retained in `serial.log`. A positive
verdict is required for every selected case; assertion failures fail the run.
The timeout defaults to 360 seconds to include the chained retirement waits.

The default `--case all` includes:

- `atomic`: two phases of 1,000 tmpfs-upper replacements, with concurrent opens
  and directory listings. The second phase adds nine filler names to exercise
  map growth and collision shifts. Reads must return one complete eight-byte
  version, and the destination must stay present. Each phase holds the original
  descriptor for 6.5 seconds and checks content, UID 1000, mode 0600 and nlink 0.
  It prints slab samples before and after the phases.
- `retention`: held directory descriptors and cwd, socket `O_PATH` descriptors,
  stacked copy-up and a rename that retires nonempty layer arrays. Two batches
  each perform 1,000 replacements and 100 repetitions of file, hardlink,
  symlink, directory and socket creation/removal. Both batches allow 25 seconds
  for chained retirement and backend queues. Every live slab class and the
  large-allocation count must match; growth fails the host gate even when all
  guest functional checks pass. See [retirement qualification](retention.md).
- `failure`: a lower tmpfs file has a 256-byte basename that ext2 cannot encode.
  Renaming either an upper file or a copied-up lower file over it must return
  `ENAMETOOLONG` while preserving both merged paths and the lower content.
  This reaches the real backing rename;
  it uses no fault injection or extra authorization.
- `disk`: an ext2 upper file replaces an existing upper inode held past the
  grace period. A lower source is copied up and renamed, leaving its old merged
  path hidden and its lower content unchanged. An upper source replaces a
  whiteout destination. Empty upper directories replace one another in the
  same parent and across parents, verifying both parent link counts. After
  unmount/remount, regular upper content, ownership, permissions and source
  removal must persist. Lower-file deletion, lower-directory removal and
  lower-source rename must leave real 0/0 character whiteouts in the upper,
  owned by UID/GID 1000. After both the volume and overlay remount, those paths
  must stay hidden. File, symlink, directory and hardlink recreation over the
  markers must succeed, and another volume remount checks their backing content,
  ownership, permissions and hardlink identity. Private staging rejects regular
  files, symlinks and work directories accessible to other users; the staging
  directory's setgid bit must not leak into the recreated directory.
  A removed work directory reached through `/proc/self/fd` must be refused
  with `ENOENT` while its descriptor still holds it alive.
- `opaque`: lower directories are removed, then recreated or replaced by an
  upper-directory rename. The new contents stay visible and former lower
  children stay absent from opens and listings before and after both layers
  remount. Trusted opacity attributes remain inaccessible to the ordinary
  user. Root checks persisted markers, final identity, unchanged lower content
  and the remounted upper parent's link count.

`--case opaque-full` separately fills a 4-MiB ext2 volume to force real
`ENOSPC` during opacity installation. It checks repeated failed mkdir rollback,
exact disk block/inode recovery, failed rename path preservation, successful
recovery after space is released and persisted markers after remount. It prints
slab samples after the first and third failures. This longer case is not part
of the default `all` selection.

That case also runs 2,000 `statfs`/`fstatfs` measurements as UID/GID 1000 and
checks consistent backing values. The host compares live slab samples and
fails on retained objects even if guest functional checks pass. See the
[filesystem-stat leak qualification](statfs.md).

The default `all` case additionally removes the shared work directory beneath
two mounted overlays, waits past the grace period and verifies that both refuse
further staging with `ENOENT` while preserving the destination. `disk` leaves
the work directory in place. After the owned guest exits, check either private
volume without modifying it:

```sh
e2fsck -f -n /path/to/result/store.ext2
```

`--case sockets` separately qualifies UNIX stream sockets on direct ext2 and
an ext2 overlay upper. UID/GID 1000 replaces a bound endpoint, connects through
the renamed path, unlinks it, keeps descriptors and an established connection
across the grace period, and rebinds the removed name. Hardlinks and moves across
directories must preserve inode identity and update held-descriptor link counts.
Closing a separate `O_PATH` description of the listener must preserve its ability
to accept a new connection through the renamed pathname.
Metadata descriptions must also refuse all 16 tested socket operations with
`EBADF`, preserve output buffers and pending connections, and remain transferable
as `SCM_RIGHTS` payloads after the original descriptor closes. The listener's
pathname has mode 0000 during these metadata checks.
Ordinary pathname opens of the live socket must return `ENXIO` after permission
validation. The fixture covers three access modes with eight flag combinations,
exclusive creation, directory-only lookup, symlink following and metadata-only
symlink lookup, while preserving the listener and socket inode metadata.
Pathname connections and named datagram sends must require write permission on
the socket inode. Mode 0000, read-only and execute-only sockets refuse access;
write-only sockets permit it. The extended cycles also check record sockets,
empty receive queues after refused sends, retained datagram targets after a
failed reconnect, connected traffic after chmod and abstract sockets under a
restrictive umask. See [pathname permission evidence](socket-permissions.md).
Unnamed, paired, accepted and abstract UNIX descriptors must report the owning
credentials and permit an ordinary creator's metadata changes. A worker accepts
an inherited root listener after dropping to UID/GID 1000; the new descriptor
belongs to the worker while captured peer credentials retain the root listener
identity. Pair/accepted traffic and descriptor passing continue after mode
changes. See [descriptor ownership evidence](socket-ownership.md).
Root also creates sockets with inherited ACLs before the account drop. Named
UID 1000 denials must override writable other bits; explicit grants, masked
grants and a changed inode owner must produce the expected connection result.
The fixture checks empty refused queues, ownership-update rollback on ext2 and
persisted mode, owner, ACL and timestamps after remount. Repeated socket cycles
inherit ACLs and exercise chmod and lookup before retirement. See
[backing ACL and metadata evidence](socket-acl.md).
Pathname xattr calls must read, list, update and remove that live inode's access
ACL. Explicit ACL updates must immediately control new connections, preserve
established traffic, reject invalid permissions and unauthorized namespaces,
and survive transport retirement and disk remount. Socket descriptions remain
unsupported for filesystem ACLs; all four descriptor xattr calls reject
`O_PATH` with `EBADF` before inspecting user pointers or writing output buffers.
See [pathname socket xattr evidence](socket-xattrs.md).
The creation probe checks umasks `0000`, `0022`, `0077`, `0222` and `0777` for
stream, record and datagram sockets, with and without a default ACL. It verifies
pathname/O_PATH metadata and actual access, then checks persisted masked ACLs
after remount. See [socket creation-mask evidence](socket-umask.md).
Two batches each run 32 cycles on each backend; every live slab class and the
large-allocation count must match. A protected-directory bind must fail with
`EACCES`. Root remounts the volume read-only, verifies that removed names stay
absent, and checks that an ordinary-account bind fails with `EROFS`.
See [persistent socket qualification](sockets.md) for controls, pins and limits.

`--case socket-access` runs one socket cycle on tmpfs without an ext2 volume or
retention sampling. It supports running the exact same native probe ELF in a
Linux reference guest. Compile the V reference controller from the repository root:

```sh
V_C_ERROR_BUG_REPORT_DISABLED=1 v -cc cc \
  -path "$PWD/tests/native-guest-tools|$PWD/tests/linuxkpi|@vlib|@vmodules" \
  -o /tmp/vinix-socket-reference tests/overlay-rename/socket-reference.v

/tmp/vinix-socket-reference --arch aarch64 --kernel /path/to/linux-arm64 \
  --init /path/to/native-socket-access-result/init \
  --state-dir /path/to/fresh-linux-reference
```

Use `--arch x86_64` and a matching Linux kernel/probe for x86. The reference uses
HVF on ARM and TCG on x86, 512 MiB, two CPUs and no networking. Its V launcher
mounts procfs and executes the preserved probe. Both runs must report
`OVERLAY SOCKET REFERENCE: PASS` and `OVERLAY GUEST: PASS`; the reference receipt
pins the shared probe, Linux kernel, launcher source/C/ELF, cpio, QEMU and serial
output. This case checks denied creation of a real device (1:3); disk cases
retain Vinix's separate refusal of user-created 0/0 whiteouts. See
[socket metadata authorization evidence](socket-access.md).
The expanded probe also checks [ordinary socket pathname opens](socket-open.md).

[Durable whiteout evidence and limits](whiteouts.md) and
[persistent directory opacity](opacity.md) record the current storage
qualifications. The following results and pins describe the earlier rename
fix in commit `9a20f3de8`, whose fixture did not yet check persisted whiteouts.

Results from 2026-10-13 are retained under `build/development17-20261013`:

| Run | Result |
| --- | --- |
| `overlay-x86-before-e` | Saved pre-fix kernel: 57 missing opens and two missing listings in the first 1,000 replacements. |
| `overlay-x86-failure-before-d` | Saved pre-fix kernel: errno 36, source preserved, merged destination lost. |
| `overlay-arm-failure-before-a` | Same failed-backend destination loss on the saved ARM kernel. |
| `overlay-x86-after-a` | All cases pass; 2,368/2,112 concurrent reads, zero missing paths, listings or bad data. |
| `overlay-arm-after-b` | All cases pass; 3,968/2,944 concurrent reads, zero missing paths, listings or bad data. |
| `overlay-x86-after-b` | Final fixture also checks cross-parent directories; all cases pass, 2,208/2,816 reads, zero errors. |
| `overlay-arm-after-c` | Final fixture also checks cross-parent directories; all cases pass, 2,176/4,096 reads, zero errors. |

The final kernels were built from isolated `9b01dbca2` worktrees plus the six
filesystem changes committed in `eefa7da3a` and this overlay/ext2 patch. Kernel
link shuffling used seed 17. The preserved V compiler snapshot
`/Users/alex/.cache/vinix-linux-compat/compiler-f6358ec/v-from-bootstrap`
was used after the live compiler began rejecting baseline pointer syntax; the
compatibility retry also rejected the required `-target-libc-headers` flag.
The initial ARM attempt ran out of disk space, then its fresh build passed.
Those failed build and fixture-compilation logs remain separate from guest passes.

| Input | SHA-256 |
| --- | --- |
| Before x86 kernel | `abbf8e176bd68c45191c3c6274052e1bca262ed7b95a20b4d05449134dec10f1` |
| Before ARM kernel | `2033980d61274fd37a0b69ad3df04aca261162de0a40a8c5d9f37ffeb6573c2d` |
| Final x86 kernel | `4ff3454595830483103c70d29328834a9743f4312ec2561c2faa8472c0ac163d` |
| Final ARM kernel | `fe2746f27759c3f1e27166fa0c785a093e73987a21e7d01a50766310c063bd26` |
| Final fixture | `ce25cf4add6d7056388b1d847a3a16eccfb21912a009762efcc9730dc74b7cea` |

An independent lifetime review checked the generated C, cloned-name ownership,
held descriptors, lock ordering and post-commit retirement. It found the missing
cached parent link-count update; the final patch and directory assertion address
that finding. The final review is retained in `overlay-lifetime-review.md`.

Both final kernels also passed the native authenticated HTTP/account/job/build
gate (`overlay-arm-http-a` and `overlay-x86-http-a`), with 19 independently
validated records each. The allocation allowlist audit still fails; its 182
file/kind counts match the pre-fix audit exactly. The allowlist was not expanded.

The final ARM kernel passed the full `ops,churn,cache,idle,apps,drag` desktop
harness run. All 36 syscall batches of 200 operations retained zero bytes per
operation, and all four 300-process churn batches retained zero bytes per run.
The cache workload wrote 32 MiB and recorded 16 MiB cached. Idle, application
launch and drag met their process-count and duration checks. The report and
screenshots are retained in `overlay-desktop-perf-a.json` and
`overlay-desktop-shots-a`; `overlay-perf-evidence.log` records the report checks.

The earlier rename qualification left overlay allocations retained. After the
two phases and grace periods, both earlier kernels retained 4,023 size-256
objects, 2,012 size-96 objects and 4,044 size-16 objects. The pre-fix ARM control
retains the same size-256/size-96 counts and 4,045 size-16 objects. An earlier
4,000-replacement phase exhausted the existing owner metadata budget; its x86
log records `Denied.owner 1`, `Requested 8198`, `OwnerBytes 61898188` and
`OwnerLimit 61902848`. The bounded fixture exposes this growth rather than
claiming a leak-free overlay. `overlay-evidence.log` records the comparisons.
The [counted ownership and retirement correction](retention.md) now covers
these per-operation allocations with matched controls and a strict memory gate.

The earlier disk persistence test qualified regular upper files. Durable ext2
whiteout hiding is now covered by the additional qualification linked above.
Retention across mounts, crash consistency,
unsupported rename flags, full OCI security/delegation and mainstream
rootless-runtime acceptance remain open.

# Package recovery on persistent storage

The V controller creates a disposable 64 MiB ext2 disk, boots the package/account
guest, and kills QEMU with SIGKILL at a transaction checkpoint. It then boots the
same disk again, without copying package state or repairing the filesystem from
the host. The package CLI performs preparation and recovery; the interrupted
upgrade calls the same `pkgcore.transact` implementation with an in-process
checkpoint callback. Production CLI commands expose no checkpoint switch.

```sh
v -path '@vlib|@vmodules|tests/hardware-platform' run tests/packages/persistence-check.v \
  --arch aarch64 --kernel /build/arm/kernel/bin/vinix \
  --state-dir /tmp/packages-persist-arm --failures-only
v -path '@vlib|@vmodules|tests/hardware-platform' run tests/packages/persistence-check.v \
  --arch x86_64 --kernel /build/x86/kernel/bin/vinix \
  --state-dir /tmp/packages-persist-x86 --failures-only
```

The [hardware controller requirements](../hardware-platform/README.md) apply.
Install `mke2fs` or set `VINIX_MKE2FS` to its executable. The disk uses 4 KiB
blocks, 128-byte inodes and the supported ext2 filetype/sparse-super/large-file
features. AArch64 uses the kernel's `vinix.qemu_persist=1` persistent-home boot
path; x86_64 mounts the prepared disk from userspace. `--list` prints the cases;
`--scenario NAME` selects one. State directories must be new or empty.

| Case | Cut point | State expected after reboot |
| --- | --- | --- |
| `packages-crash-staged` | Payloads, launchers, lease and state are flushed in `.stage-2`, before publication. | Version 1 remains active; the next transaction retires the abandoned stage. |
| `packages-crash-published` | Generation 2 is renamed into place and its parent flushed, before replacing `current`. | Version 1 remains active; generation 2 is unused and later collected. |
| `packages-crash-activated` | `current` points to generation 2 and its parent flush has completed, while the transaction still holds its lock. | Version 2 is active with version 1 available for rollback. |

Preparation signs a local repository, installs version 1, refreshes version-2
metadata, seeds a durable partial version-2 object and writes a user-owned personal
file. Only preparation uses a global `sync`; the upgrade must flush its own writes.
The callback writes the cut marker directly to the console and waits forever:
there is no return, deferred cleanup, guest sync or guest shutdown after it.
The host requires the SIGKILL outcome before proceeding to the recovery boot.

After reboot, the guest verifies the complete active payload and launcher state,
removes repository payloads and upgrades from verified cached content with
`--offline`. It rolls back, removes the app, verifies launcher removal, rolls back
again and collects garbage. Only the restored generation remains; the personal
file retains its contents, UID and mode, and no partial object remains. This
qualifies resumption of the seeded local partial object, rather than an HTTP
connection interrupted in flight.

Passing retained runs write `qualification.json` with target, completed
checkpoints and hashes/sizes for the kernel, initial disk, guest, package CLI and
both serial logs of every case. `--failures-only` removes passing boot/disk images
while preserving those logs and the receipt. Keep images by omitting that option.
The disk contains only throwaway fixture signing credentials.

The controller now also keeps `initial.ext2` in the state directory, even with
`--failures-only`, so the receipt's formatted-input digest can be checked against
the exact initial filesystem. This blank formatted image contains no signing
credentials. See [captured durability qualification](durability-check.md) for
renewed runs of all three checkpoints on both targets.

`--keygen` instead selects the publisher seed scenario and requires a new
`--state-dir`. It kills QEMU after the real CLI's `keygen` returns and before any
extra guest sync or metadata write. Reboot reads the same seed with `key-public`,
checks its mode/owner/length and rejects a replacement key generation. The
controller compares the public key in the two serial logs before issuing its
six-artifact receipt (kernel, initial image, guest, service and two serial logs).
No host filesystem repair or seed write occurs between boots. See
[key creation qualification](keygen-check.md) for recorded runs and limits.

All three cases passed on 2026-10-12 on each architecture. Hash receipts:
[AArch64](results/2026-10-12/persistence-aarch64.json) and
[x86_64](results/2026-10-12/persistence-x86_64.json).

The tests exercise the three completed package checkpoints on a QEMU-backed ext2
volume. They do not cut inside a filesystem rename, sector write or flush, inject
device I/O errors, or model loss of the host's write cache. Physical-device and
filesystem crash consistency still require wider qualification. Application
execution and permissions are checked separately by
[the production sandbox suite](runtime-check.md).

## Selected repository refresh cuts

Add `--refresh` to the persistence command and use a fresh state directory.
The fixture installs version 1 from a local publisher, seeds an authenticated
HTTPS snapshot from its image bundle, then withdraws that bundle. It stages a
new local release and interrupts an offline refresh of that repository alone.

| Case | Cut point | Local sequence after reboot |
| --- | --- | --- |
| `refresh-cut-fetched` | Both signed metadata files have been copied into the refresh workspace. | Catalog 1, history 1. |
| `refresh-cut-history` | Sequence 2 and its digest have been persisted to trust history. | Catalog 1, history 2. The stale catalog refuses an upgrade review. |
| `refresh-cut-catalog` | The catalog replacement has completed before the worker retires its workspace. | Catalog 2, history 2. |

In the two cases with the new floor, the regular CLI refuses the old signed
index and a differently signed index at sequence 2. It accepts the exact
sequence-2 retry in every case and can repeat it without changing the catalog
or history. The cached HTTPS snapshot, its trust floor, the repository
configuration and the installed generation stay intact. The fixture verifies
the active payload before and after recovery and checks workspace retirement.

The cut worker calls the same `Service.refresh_repository` path as the CLI.
Only that worker is built with the intermediate history checkpoint. Preparation
and recovery use the ordinary package binary. The cut suspends the worker at
completed application checkpoints, and the host kills QEMU before rebooting
the same ext2 disk.

On 2026-11-24, revision `3766de2fb34bb3aac8f798702abff8d970c1548c`
passed all three cuts on AArch64 (HVF) and x86_64 (TCG). Each run required
QEMU to exit from SIGKILL on the first boot and recorded guest shutdown after
the recovery assertions on the second. Both target CLI binaries lacked the
history checkpoint included in their respective cut workers. The refresh,
service and trust-recovery host suites passed, along with the focused
selected-refresh test under ASan/UBSan with leak detection disabled.

The [retained archive](/Users/alex/.local/state/vinix/r14-refresh-crash-4Lnrax/qualification.tar.gz)
contains the source snapshot, target inputs, disk images, receipts, serial
and QMP logs. All 11 receipt sizes and digests matched per target. A fresh
extraction matched all 155 SHA-256 manifest entries. The archive's SHA-256 is
`81f832e157766eb9ee5cb1ee7ace9f1a02ba520b20001f3b9f3aef3193c8abab`.

These runs qualify recovery at completed metadata checkpoints on QEMU ext2.
Cuts during writes, physical storage power loss and wider filesystem
qualification remain open.

### Refresh workspace recovery

Both full and selected refresh create the scratch directory relative to the
captured package state directory. They check both directory identities between
metadata transfers, after reporting verification progress and before publishing
history or the catalog. A workspace replacement causes refusal and preserves
the replacement and its contents. Cleanup can still retire work through the
captured parent if the state pathname moves.

The host regression moves the fetched index into a replacement directory while
the copy still holds the original file open. The refresh must refuse before
fetching the signature into that directory. Additional cases replace the
workspace or its parent at verification and check both metadata files before
retrying the original signed update.

On 2026-11-24, revision `889981df0dd0a3dc8cdf06262a2d7918e38b046b`
passed the workspace replacement, selected refresh, administration and
trust-recovery host checks. The replacement cases also passed under ASan/UBSan
with leak detection disabled. All three refresh cuts passed on AArch64 (HVF)
and x86_64 (TCG), with guest shutdown after each recovery.

With V `2655544`, the existing tracked history-publication refusal test
recorded 126,976 retained bytes across 64 calls on both the baseline
`4931136dc` and the tested revision. Both runs failed the zero-retention
assertion.

The [retained archive](/Users/alex/.local/state/vinix/r14-refresh-workspace-SeRxp9/qualification.tar.gz)
contains the tested source, matched tracking inputs and logs, initial disks,
and 11 verified receipt entries per target. The QEMU runs used
`--failures-only`. The independent archive checker verified all 111 sealed
files. Archive SHA-256
`048fb49a88ad55f08b886934ee64123c00c65ba2fce1eccdee1b04bc0ecd5869`.

## Reviewed publisher enrollment cuts

Add `--enrollment` to the persistence command and use a fresh state directory.
The fixture installs an app from one publisher, then obtains a read-only
enrollment review for a second publisher with a separately supplied key.
The cut CLI applies that approval through the normal `repo-apply` path.

| Case | Cut point | Trust state after reboot |
| --- | --- | --- |
| `enrollment-cut-history` | Sequence 2 and its digest have been persisted. | The replay floor is durable and the new publisher remains disabled. |
| `enrollment-cut-configuration` | The configuration replacement and flush have completed. | The same floor is durable and the new publisher is enabled. |

Both cases recover the exact catalog and installed generation from before
enrollment. The regular CLI refuses sequence 1, a different signed index at
sequence 2 and the original approval. A new review binds the exact sequence-2
index to the recovered trust state. Applying it retires the abandoned
enrollment workspace. The selected refresh then loads the new publisher's
app and keeps the original publisher snapshot and installed generation.

Only the cut CLI is compiled with the checkpoints. It pauses while holding
the writer lock, and QEMU is killed before cleanup or a guest sync. Preparation
and recovery use the regular CLI.

On 2026-11-24, revision `981868d00cd9ff29be85f0321239af9ca23c57d7`
passed both cuts on AArch64 (HVF) and x86_64 (TCG). All four runs verified
SIGKILL at the selected checkpoint and guest shutdown after recovery. The
test confirmed the checkpoint symbol only in the cut CLI on both targets.
The host administration and trust-recovery suites and the selected-refresh
regression passed. The administration suite also passed under ASan/UBSan
with leak detection disabled.

The [retained archive](/Users/alex/.local/state/vinix/r14-enrollment-crash-jGaipQ/qualification.tar.gz)
contains the source snapshot, target tools and inputs, initial ext2 images,
and serial and QMP logs. The runs used `--failures-only`. All nine receipt
sizes and digests matched per target. The independent archive checker
verified all 94 sealed file payloads and the gzip stream. Archive SHA-256
`1bd4bc60d439a7bf1f8c8baa41c878067a3ce661f0e0bdb79a60258042d759ab`.

These runs qualify the reviewed enrollment sequence on disposable QEMU ext2
disks. Production publisher enrollment and physical storage crash testing
remain separate release requirements.

### Enrollment workspace recovery

Enrollment captures the package state directory before creating or retiring
its `enrollment` workspace. A retry can remove interrupted work from an
ordinary administrator-owned directory on the same filesystem. An alias,
unexpected file or shared writable root causes enrollment to refuse and
preserve the entry. Restore an ordinary private workspace, or move the
unexpected entry aside, before retrying.

Enrollment rechecks the captured state and workspace identities before and
after fetching signed metadata. Cleanup uses the captured directory and leaves
a replacement workspace untouched. Tests cover a replaced workspace or state
path, nested interrupted work, a child symlink, and successful use of the same
approval after a workspace refusal leaves configuration and replay history
intact.

On 2026-11-24, revision `9aed436f8236d92b5eb15de66043657bf3ca2cf1`
passed the host administration, enrollment ownership and trust-recovery
suites and the focused refresh checks. The administration suite also passed
under ASan/UBSan with leak detection disabled. Both enrollment cuts passed on
AArch64 (HVF) and x86_64 (TCG), with guest shutdown after each recovery.

The [retained archive](/Users/alex/.local/state/vinix/r14-enrollment-workspace-iCrtBS/qualification.tar.gz)
contains the source snapshot, nine verified receipt entries per target, the
initial disks and logs. The runs used `--failures-only`. The independent
archive check verified all 90 sealed files. Archive SHA-256
`aec5383cd8610bea8412938a0a0ef5a425f72230fcf9d860cb5d3289e196b25b`.

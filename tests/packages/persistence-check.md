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

All three cases passed on 2026-10-12 on each architecture. Hash receipts:
[AArch64](results/2026-10-12/persistence-aarch64.json) and
[x86_64](results/2026-10-12/persistence-x86_64.json).

The tests exercise the three completed package checkpoints on a QEMU-backed ext2
volume. They do not cut inside a filesystem rename, sector write or flush, inject
device I/O errors, or model loss of the host's write cache. Physical-device and
filesystem crash consistency still require wider qualification. Application
execution and permissions are checked separately by
[the production sandbox suite](runtime-check.md).

# Software maintenance across cold boots

The newer [installed-system check](software-installed-check.md) uses the real
blank-disk installer and retains the complete userland root. The ext2 subtree
mode and receipts below keep their original scope.

`native-catalog-check.v --persistent` joins production image staging, the actual
Software controller, authentication, isolated launch and persistent ext2 storage.
It boots the same guest four times with the same 128 MiB disk. The host never
copies consumer state, rewrites trust, repairs the filesystem or changes the disk
between boots. Each boot must end in a guest-initiated QMP shutdown.

The first boot copies the staged `/etc`, empty `/var` and `/home` into three
disk subtrees and bind mounts them at their ordinary production paths. This
keeps package configuration/state directories ordinary and root owned. Subsequent
boots mount those same subtrees without copying them or recreating accounts.
`/run` and its authentication/launch sockets start fresh on each boot.

| Boot | Required behavior |
| --- | --- |
| 1 | Begin with staged publisher trust, signed offline media and empty consumer state. Create administrator/standard accounts once. Install Hello, Counter and Memo through Software; save a memo, grant Hello a literal document and retain independent counters for both accounts. |
| 2 | Compare the retained activation pointer, state, cached catalog, replay history, trust, password database and user files byte for byte, including UID/GID/mode. Reopen Counter and Memo, then refresh changed signed media and review an upgrade of all three apps to 1.1.0 through Software. |
| 3 | Verify the exact retained upgrade before mutation. Hide both image repository object directories. Reopen native apps, review rollback to 1.0.0, uninstall every app and check registration removal, then reinstall all three at 1.1.0 from persistent cache. |
| 4 | Verify the exact retained reinstall, complete payload integrity and architecture/publisher provenance, restored launchers and private-data ownership. Reopen Counter and Memo without repository payloads. |

Every boot checks the root-owned active package state, unchanged release
configuration, per-user data, administrator audit attribution, absence of
passwords in the audit and cleanup of package sockets. Counter remains `1` for
each user; Memo retains `Saved through ordinary Software`. The byte comparison
also includes Hello's literal document path with spaces and shell punctuation.
The record on the disk contains hashes and metadata rather than password or
document contents. The disk itself contains throwaway test account credentials.

The check exposed an ext2 remount bug: populated inodes reported `st_dev=0`,
while newly created inodes reported the mounted filesystem's device ID. Package
stage admission correctly refused the mixed identities after reboot. Ext2 now
sets that ID while populating inodes, matching its creation and mount paths.
The guest verifies that retained account, generation and user-data inodes report
the mounted ext2 device before maintenance. This changes no allocation or object
lifetime; both kernels are built from isolated worktrees.

The input pin checks, supported image staging tool and headless Software tree
fixture are shared with [the Software image check](software-image-check.md).
Both complete signed releases contain the builder's real native executables;
1.1.0 changes package metadata over the same executable bytes. The signing seed
stays outside the guest. A receipt records the architecture, four boots,
`qemu-ext2-retained-subtrees` platform, kernel/tools/app input hashes, initial and
final disk hashes, all four serial logs and QMP events.

## Qualification, 2026-10-16

Both isolated kernel builds and six host controller checks passed. The final
guests completed all four workflows and four guest-initiated shutdowns each:

| Architecture | Four-boot Software lifecycle |
| --- | --- |
| AArch64 | PASS, 68.0 s |
| x86-64 | PASS, 69.9 s |

The failing baseline on both architectures retains the package-stage refusal.
The descriptor diagnostic measured parent device `0` and new stage device `5`,
with matching relative/absolute stage identities, UID 0 and mode 0700. The final
runs include the ext2 population fix and the explicit retained-inode device
check. The source ledger compares every tracked kernel input with both isolated
worktrees and pins the generated C, build logs and compiler alongside the
controller/services, native catalog and UI fixture inputs.

- [AArch64 receipt](results/2026-10-16/software-persistence-aarch64.json), [QMP](results/2026-10-16/software-persistence-aarch64.qmp.txt), [fourth boot](results/2026-10-16/software-persistence-aarch64.boot-4.serial.txt)
- [x86-64 receipt](results/2026-10-16/software-persistence-x86_64.json), [QMP](results/2026-10-16/software-persistence-x86_64.qmp.txt), [fourth boot](results/2026-10-16/software-persistence-x86_64.boot-4.serial.txt)
- [Host results](results/2026-10-16/software-persistence-host.txt), [source/toolchain/artifact ledger](results/2026-10-16/software-persistence-toolchain.json), [device diagnostic](results/2026-10-16/software-persistence-device-diagnostic.txt), [baseline pins](results/2026-10-16/software-persistence-baseline.json)
- [V guest invocation](results/2026-10-16/software-persistence-guest.v), [isolated kernel build](results/2026-10-16/software-persistence-kernel.v), [evidence verifier](results/2026-10-16/software-persistence-retain.v)

## Reproduction

Use the [hardware controller requirements](../hardware-platform/README.md),
`mke2fs` (or `VINIX_MKE2FS`), native catalog builder inputs, reviewed V compiler,
headless ui2 module, and matching kernel/sandbox:

```sh
v -path '@vlib|@vmodules|.|tests/hardware-platform|tools/accounts' \
  -o /tmp/native-catalog-check tests/packages/native-catalog-check.v
VINIX_HWTEST_TCG=1 V=/path/to/reviewed/v VFLAGS=-nocache \
  VINIX_PACKAGE_TEST_UI2=/path/to/headless/modules \
  VINIX_NATIVE_CATALOG_INPUTS=/build/native-inputs \
  VINIX_NATIVE_CATALOG_SANDBOX=/build/aarch64-root/usr/bin/vinix-sandbox \
  /tmp/native-catalog-check --persistent --arch aarch64 \
  --kernel /build/aarch64-kernel --state-dir /build/new-cold-boot-state
```

Repeat for x86_64 with its kernel/sandbox and a new short state directory.
The state directory keeps the initial disk, final disk, fixture binaries,
generated C, image inputs, all serial logs and the receipt. `--list` lists this
scenario without formatting a disk or compiling a guest. The existing default,
`--image` and `--software` modes remain available.

## Scope

This qualifies orderly cold boots and ordinary Software/service maintenance of
retained native packages on QEMU ext2. Software builds its actual UI trees with
headless presentation helpers. The OS and tools boot from the original initramfs
each time. It does not qualify an installed system disk boot, a compositor,
graphical login, display/audio brokers, broader foreign runtimes, device errors
or write-cache power loss. Abrupt cuts at completed transaction checkpoints have
their own [persistent recovery check](persistence-check.md). Public publisher
selection and advertised catalog migration remain open. No roadmap 14 checkbox
is closed by this fixture.

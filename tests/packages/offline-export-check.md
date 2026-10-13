# Reviewed offline export qualification

Software's **Export offline** workflow exports the selected catalog package or
all explicitly installed application roots, using current authenticated versions
and their dependencies. A complete destination review precedes package review;
long canonical paths are paged before confirmation becomes available. Publisher
keys, descriptions, target architecture, licenses, firmware/proprietary flags,
permissions and runtime dependencies remain visible in the closure review.
Confirmation freezes the original destination and package IDs as literal argv.

`mirror-review` reads under the package reader lock, without creating destination
parents, fetching objects or modifying installed state. `mirror-apply` checks its
separate review domain under the writer lock, binding configuration, exact signed
indexes, resolved closure and destination argument/path/ancestor device/inode.
It rechecks destination/cache space, including both copies on a shared disk, and
then follows the existing verified private staging and atomic publication path.
Progress reports resolve, transfer/copy and verification, with completion only
after durable publication. A failed export retains recoverable cache data;
expired catalogs, revoked trust and changed policy still require fresh admission.

The host mirror runner checks read-only review, unchanged installed generation,
dependency/publisher closure, stale names/destination, changed policy and signed
metadata, replacement of an existing media ancestor, cross-command fingerprint
refusal and lock ordering. Existing cases cover corruption, destination races,
disk-space failure, abrupt termination, readable object modes, retry and clean
offline installation. New recovery cases verify that partially filled verified
cache does not stale a review, and failure never reports completion.

The protocol runner refuses unsupported formats, missing space fields, unsafe
destinations, empty/duplicate roots and non-export rows. The Software fixture
checks bounded text entry, read-only pending review, full path paging, installed
root selection, dependency provenance and permissions, literal confirmation,
progress, stale diagnostics, cancellation and the active-operation close guard.
The real desktop launcher fixture measures destination/closure redraw, paging
and 100 review/retirement cycles with `-gc none -manualfree -d track_heap`.

Run the host checks with:

```sh
v run tests/packages/distribution-check.v --direct-tests --cross --desktop
```

The existing Linux runtime guest scenario now checks reviewed export before
transferring its real dynamically linked musl application/runtime closure. It
rejects a changed destination before parent creation, forces acquisition failure,
checks that no final tree or completion event appears, removes a successfully
cached upstream object and retries with the same review. A clean offline client
enrolls the original publisher key and installs the signed closure through a
reviewed deployment lock. Ordinary-account readers can read exported objects;
the exporter's installed generation remains zero. The scenario also exercises
Linux sandbox launch, package/trust/policy reviews, runtime updates and rollback.

```sh
v -no-skip-unused -path '.|tests/hardware-platform|@vlib|@vmodules' \
  -o /tmp/linux-check tests/packages/linux-runtime-check.v
V=/path/to/v VINIX_HWTEST_TCG=1 \
  VINIX_LINUX_SANDBOX=/build/target-root/usr/bin/vinix-sandbox \
  VINIX_MUSL_COPYRIGHT=/build/musl-COPYRIGHT \
  /tmp/linux-check --arch aarch64 --kernel /build/aarch64-kernel \
  --state-dir /build/new-offline-export-arm
```

Repeat with x86_64 inputs and a fresh state directory. The optional sandbox input
is checked for ELF class and target at guest admission. Omitting it invokes the
production V security-tools builder. Guest service/init/account/session binaries
are built fresh. Passing receipts pin eleven artifacts, including guest init,
the native sandbox, musl loader, dynamic application/library, service,
account/session tools and serial log. Guests must emit `PACKAGE MIRROR REVIEW`,
all existing Linux workflow markers and a clean poweroff within the 180-second
functional deadline.

The 2026-10-13 full distribution driver passed 27 assertion runners, SDK context
heap checks, CLI/PTY/Software checks, both target staging builds and desktop type
checks for both architectures. The final standalone desktop launcher run checks
100 form redraws, destination redraw/paging and closure redraws with zero retained
tracked bytes. Its 100 review/retirement cycles retain 100 bytes, matching the
100-byte baseline measured by decoding 100 plain JSON booleans; this test does
not claim the underlying JSON decoder is leak-free. The new mirror protocol
assertion runner passes clang ASan/UBSan with leak detection disabled.

Final QEMU TCG guests use the final validation guards and fresh
service/init/account/session binaries, with eleven receipt hashes independently
checked against retained target inputs. Every required workflow marker and
clean poweroff is present:

- [AArch64 receipt](results/2026-10-13/offline-export-aarch64.json) and
  [serial log](results/2026-10-13/offline-export-aarch64.serial.txt): 36.1 seconds;
  [QMP log](results/2026-10-13/offline-export-aarch64.qmp.txt) records guest shutdown.
- [x86_64 receipt](results/2026-10-13/offline-export-x86_64.json) and
  [serial log](results/2026-10-13/offline-export-x86_64.serial.txt): 39.5 seconds;
  [QMP log](results/2026-10-13/offline-export-x86_64.qmp.txt) records guest shutdown.
- [Host results](results/2026-10-13/offline-export-host.txt) and
  [compiler/source ledger](results/2026-10-13/offline-export-toolchain.json).

The initial guest runs also passed. A user continuation interrupted an earlier
host/guest build attempt before completion; those logs have no passing receipt.
Rebuildable boot media from completed owned runs was removed to recover disk
space, retaining binaries, roots, logs and receipts. Compiler/desktop notices
and generated-standard-library C warnings are retained in the local build logs.

These are host/headless UI and emulated guest functional checks. They do not
qualify a mounted USB hardware device, graphical broker, public publisher,
arbitrary Wine/Apple runtime, performance or power-cut durability. Export retains
catalog expiry and only supplies the selected closure's payloads. Publisher
enrollment, broader catalog migration and the roadmap 14 acceptance gate remain
open.

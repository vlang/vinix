# Composed catalog qualification

The additive `compose-catalog` publisher command combines complete reviewed
profile locks into one pinned catalog. Sources are scoped under profile IDs,
while package manifests, selectors, file pins and permission/license/firmware
disclosures remain unchanged. Both the old unscoped source names and the new
scoped names use the same catalog builder and signed release/store workflow.
See the [SDK contract](../../tools/packages/SDK.md#compose-application-catalogs).
The additive `compose-catalog-for` command explicitly selects one supported host
from mixed single/dual-host inputs; see its
[separate qualification](composition-target-check.md). The strict command's
identical-target-set requirement remains unchanged.

`pkgcore/composition_test.v` covers deterministic catalog/provenance bytes,
unchanged manifests/pins/selectors, both architecture installs, ordinary consumer
license/firmware refusal, duplicate profiles and package identities, mismatched
target sets, invalid/oversized source paths, unknown fields, disk-space refusal,
pre-publication corruption, destination races and staging cleanup. It verifies
that ancestor and final source-directory symlinks fail, changed pinned payloads
fail, and replacement of a profile namespace after capture cannot redirect import.
The existing catalog tests continue to cover unscoped imports and publication.
The CLI fixture checks literal lock paths, composition, duplicate/existing-output
refusal and a composed import with identical package metadata.

The real guest controller is V and reuses the previously qualified pinned
[SQLite inputs](sqlite-profile-check.md) and [FFmpeg inputs](ffmpeg-profile-check.md).
It verifies all 70 input payload hashes and both build records before staging.
The complete source notices, FFmpeg source archive and build instructions stay
with the payload. Both architecture roots are publisher data; only the matching
installed architecture executes.

```sh
v -no-skip-unused -path '.|tests/hardware-platform|@vlib|@vmodules' \
  -o /tmp/composition-check tests/packages/composition-runtime-check.v
V=/path/to/v VINIX_HWTEST_TCG=1 \
  VINIX_SQLITE_INPUTS=/build/sqlite-inputs \
  VINIX_FFMPEG_INPUTS=/build/ffmpeg-inputs \
  VINIX_COMPOSITION_SANDBOX=/build/target-root/usr/bin/vinix-sandbox \
  /tmp/composition-check --arch aarch64 --kernel /build/aarch64-kernel \
  --state-dir /build/new-composition-arm
```

Repeat for `x86_64` with the corresponding sandbox, kernel and fresh state
directory. Toolchain/firmware/TCG options follow the hardware-platform controller.
The guest creates a fixture signing key and two ten-package releases: SQLite,
FFmpeg, FFprobe and their two explicit runtimes, each on both architectures.
It requires canonical composition independent of pair order, a single publisher
identity, a reviewed five-package ordinary-account install, real SQLite WAL
database integrity and PCM audio generation/inspection, an explicit FFprobe file
grant, and ordinary ownership of retained data. The later release changes only
the SQLite library/runtime. Reviewed upgrade and rollback preserve all other
package manifests and the database/media; removing all roots leaves no active
packages, and hiding the release forces a reviewed offline reinstall from cache.

The 2026-10-13 full host driver passed 24 signing/core/protocol/registry assertion
runners, the CLI and host PTY checks, and Software UI/worker checks. The final
composition assertions additionally passed clang ASan/UBSan with leak detection
disabled, including the later count/depth and formatting cases. FAT sizing
boundary assertions passed separately. Target service/account/session binaries
were built afresh for both guest runs; their kernels and native sandboxes are the
previously qualified cached artifacts.

The first AArch64 attempt stopped before boot: the fixed 64 MiB FAT boot image
could not fit the larger initramfs and kernel. The harness now sizes that image
from all inputs, reserves filesystem headroom and rejects oversized FAT files
or payload totals. Its focused boundary tests cover small, larger and oversized
inputs. The final AArch64 run uses a 128 MiB boot volume. The x86_64 ISO run
passed before that architecture-specific harness correction.

Retained receipts have 79 hashes each: 70 profile payloads, two build records,
kernel, guest init, sandbox, service, account/session tools and serial log.
Both runs print every required marker and power off cleanly within the
600-second functional deadline:

- [AArch64 receipt](results/2026-10-13/composition-aarch64.json) and
  [serial log](results/2026-10-13/composition-aarch64.serial.txt): 132.1 seconds.
- [x86_64 receipt](results/2026-10-13/composition-x86_64.json) and
  [serial log](results/2026-10-13/composition-x86_64.serial.txt): 85.6 seconds.
- [Host results](results/2026-10-13/composition-host.txt),
  [first AArch64 attempt](results/2026-10-13/composition-aarch64-first.txt) and
  [compiler/source ledger](results/2026-10-13/composition-toolchain.json).

The [base catalog](results/2026-10-13/composition-base.catalog.json) and
[runtime-update catalog](results/2026-10-13/composition-math.catalog.json), with
[base provenance](results/2026-10-13/composition-base.provenance.json) and
[update provenance](results/2026-10-13/composition-math.provenance.json), are
canonical locks generated from those pinned inputs through the same producer
functions. They contain no signing key or signed public repository.

UI/graphical broker integration, arbitrary upstream application/ABI coverage,
upstream authentication, public publisher enrollment and power-cut durability
remain separate acceptance work. The fixture key is used only for qualification.

# Signed offline repositories in release images

Production `tools/packages/stage.v` accepts `--repositories DIRECTORY` and
`VINIX_PACKAGE_IMAGE_REPOSITORIES`; the explicit option wins. A reviewed package
configuration must already select the publisher keys and target URLs under
`file:///usr/share/vinix-packages/repositories/ID`. The input directory contains
the corresponding complete signed `publish-release` exports, with no extra
repository, publisher workspace or secret files. No default trust or acceptance
of proprietary/firmware terms is added.

Preparation validates the complete signed metadata and dependency/runtime
closures, organization policy, source layout and every authenticated payload.
It creates a private capture before compilation. Later changes or removal of
the source cannot alter that captured release. Temporary/destination disk checks
include simultaneous copies on a shared filesystem and 64 MiB of build headroom.
The desktop cache includes the selected bundle and its content hashes.

Publication repeats captured root/configuration and destination-parent checks,
copies into a private image stage, verifies and flushes contents, and publishes the
whole bundle exclusively. Existing matching exports are verified and preserved;
different, damaged, linked or concurrently created destinations refuse. Expiry
is checked again before publication. Ordinary failures retire unpublished stages
and the owned plan's private capture; close is repeatable. An image build remains
a sequence of staging operations and must finish before distribution.

The bundle does not initialize the consumer catalog, replay floors or generations,
and does not change trust/policy. Normal guest Refresh authenticates the bundled
index before reviewed installation. Later updates still require signed publisher
metadata and ordinary package review; the bundle is an initial offline source.

## Qualification

All **32 focused native compile/run checks passed**: eight core runners (bundle,
configuration, release, mirror, signatures, copy, policy and catalog), the new
fixture under ASan/UBSan, desktop cache assertions, signed CLI lifecycle,
controller compilation/three mode listings, and staging compilation/four
preflight checks. Sanitizers disable leak detection and make undefined behavior
fatal; no measured allocation-retirement claim is made.

The maintained core fixture covers both architecture configurations, retained
canonical configuration, source removal after capture, exclusive publication,
idempotent retry and real offline dependency installation from the published
export into a separate consumer. Negative checks cover extra/unconfigured files,
bad signatures/keys, corrupt payloads, source and object-directory aliases, NUL
paths, shared write access, organization allowlists, explicit proprietary-license
and firmware approval, space refusal, capture interruption, changed staged
objects, concurrent destinations, configuration drift, retained state without
configuration, aliased parents and replaced image roots.

The image controller now publishes its initial native release outside the guest
and passes that bundle to the production staging command. Only the resulting
image bundle is booted. Guest package state begins empty and the first refresh
uses the already present signed export at its configured target path, without a
guest-side repository-copy/enrollment step or a trust-file edit.

Both the CLI image scenario and ordinary Software controller scenario run the
new assertion fixture in the guest and maintain real Hello, Counter and Memo
payloads. Their existing launch, updates, rollback, removal and cache-reinstall
checks remain required. The test supplies a newer signed release as changed
local repository media; it does not generate that release or rewrite trust in
the guest. The Software path also retains administrator/standard account checks
and separate private data through native window protocols 1 and 2.

| Architecture | CLI image | Ordinary Software image |
| --- | --- | --- |
| AArch64 | PASS, 41.3 s | PASS, 51.1 s |
| x86-64 | PASS, 51.0 s | PASS, 73.1 s |

All four final guests require complete workflow markers and guest-initiated QMP
shutdown. Receipts and the source/toolchain ledger pin generated C, captured
inputs, staged tools, bundle bytes, configuration, native payloads and logs.
The unchanged isolated socket-qualification kernels are inputs. Headless Software UI trees qualify the
controller/service path, not compositor presentation or graphical login. These
initramfs runs do not qualify persistent-device crash durability, a public release
publisher, migration of the advertised Alpine/vendor catalog or broader foreign
runtime/display/audio support. Roadmap 14 remains open.

Reproduce with the native builder's pinned inputs and matching sandbox/kernel:

```sh
v -path '@vlib|@vmodules|.|tests/hardware-platform|tools/accounts' \
  -o /tmp/native-catalog-check tests/packages/native-catalog-check.v
VINIX_HWTEST_TCG=1 V=/path/to/reviewed/v VFLAGS=-nocache \
  VINIX_NATIVE_CATALOG_INPUTS=/build/native-inputs \
  VINIX_NATIVE_CATALOG_SANDBOX=/build/aarch64-root/usr/bin/vinix-sandbox \
  /tmp/native-catalog-check --image --arch aarch64 \
  --kernel /build/aarch64-kernel --state-dir /build/new-bundle-image-state
```

Repeat for x86_64 and with `--software` plus `VINIX_PACKAGE_TEST_UI2` for the
ordinary Software workflow. Each run needs a new state directory. The default
controller mode retains explicit enrollment for the legacy native-catalog check.

- [Host checks](results/2026-10-16/image-repositories-host.txt), [core fixture](results/2026-10-16/image-repositories-core.txt), [sanitizers](results/2026-10-16/image-repositories-asan.txt), [CLI](results/2026-10-16/image-repositories-cli.txt), [preflight](results/2026-10-16/image-repositories-preflight.txt)
- [Source/toolchain/artifact ledger](results/2026-10-16/image-repositories-toolchain.json), [V host checks](results/2026-10-16/image-repositories-host.v), [V guest invocation](results/2026-10-16/image-repositories-guest.v)
- [AArch64 CLI receipt](results/2026-10-16/image-repositories-aarch64.json), [serial](results/2026-10-16/image-repositories-aarch64.serial.txt), [staging](results/2026-10-16/image-repositories-aarch64.stage.txt), [Software receipt](results/2026-10-16/image-repositories-aarch64.software.json), [Software serial](results/2026-10-16/image-repositories-aarch64.software.serial.txt)
- [x86-64 CLI receipt](results/2026-10-16/image-repositories-x86_64.json), [serial](results/2026-10-16/image-repositories-x86_64.serial.txt), [staging](results/2026-10-16/image-repositories-x86_64.stage.txt), [Software receipt](results/2026-10-16/image-repositories-x86_64.software.json), [Software serial](results/2026-10-16/image-repositories-x86_64.software.serial.txt)

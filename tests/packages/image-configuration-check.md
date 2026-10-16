# Release image package configuration

`tools/packages/stage.v` can initialize a fresh image from an explicitly reviewed
format-1 package configuration using `--config FILE` or
`VINIX_PACKAGE_IMAGE_CONFIG`. The option takes precedence. With neither input,
the existing unenrolled default is retained. No demonstration publisher key,
proprietary-license acceptance or firmware permission is supplied automatically.

Preparation captures one bounded ordinary source before compilation, validates
its schema, target architecture, policy, launch account name and new Ed25519
publisher points, then retains canonical bytes. Later source replacement or
removal cannot change the prepared result. Image roots and configuration parents
must remain controlled ordinary directories. Publication uses the existing
flushed exclusive atomic metadata writer and never overwrites a concurrent file.

Existing valid configuration is preserved byte-for-byte, including when the
release input is missing. Malformed, unsafe or wrong-architecture existing
configuration refuses. Missing configuration beside nonempty package state
requires recovery; staging cannot reset the retained installation's trust or
policy. These checks repeat at publication. The owned V `ImageConfiguration`
plan provides repeatable close after publication or refusal.

The desktop image cache records both the environment-selected configuration
path and its contents. The cache fixture changes equal-length input while
restoring its timestamp and still requires a different key. Removing the input
selection restores the unenrolled fixture's key.

## Qualification, 2026-10-16

All **33 focused native compile/run checks passed**: the configuration fixture,
schema, key generation, exclusive atomic writes, administration, service,
native profile, release, catalog and distribution regressions; final fixture and
ASan/UBSan; signed CLI lifecycle and staging/driver builds; option/environment
preflight and desktop cache checks. Sanitizers disable leak detection and make
undefined behavior fatal. This is a functional/lifetime check, not a measured
allocation-retirement claim.

The configuration fixture covers both architecture configurations, source
capture, exact policy/key/account preservation, empty defaults, invalid and
small-order publisher keys, schema errors, oversized input, linked/FIFO sources,
unsafe roots/parents/targets, concurrent destination creation, root replacement,
changed existing architecture and missing configuration beside retained state.
It also acquires a real signed repository into each seeded root and verifies
install, registration removal and rollback without further configuration edits.
Invalid CLI option/environment input refuses before compiler lookup and leaves
the staging root empty.

The native catalog controller's new `--image` mode verifies/captures the existing
native builder's pinned inputs and publishes complete 1.0.0 and 1.1.0 fixture
releases on the host. It generates a temporary fixture key outside the image,
then invokes the production staging tool with its reviewed configuration. The
guest starts with empty package state and that already staged trust/policy/
launch account. Its native application workflow consumes these staged releases
without publishing its application catalog or editing the trust file in the guest.

The normal CLI then refreshes and reviews/installs the three real native SDK
apps. Hello reads an explicitly granted document; Counter and Memo persist
ordinary-user data through protocols 1 and 2. Upgrade, rollback, uninstall,
registration removal, collection and cache reinstall retain private data. The
configuration must remain byte-identical throughout. The same guest also runs
the new configuration assertion fixture. Host signing seeds/workspaces are not
copied into the image.

| Architecture | Production-staged image | Existing native catalog regression |
| --- | --- | --- |
| AArch64 | PASS, 26.9 s | PASS, 70.6 s |
| x86-64 | PASS, 27.2 s | PASS, 87.0 s |

All four guests require complete markers and guest-initiated QMP shutdown.
Receipts pin the unchanged isolated socket-qualification kernels, fresh init,
staged tools, input builder record, native payloads, signed release exports,
configuration and logs. The staged image tools use the production C-generation
flags and retain generated-C compiler warnings. The original native-catalog
scenario still covers its explicit enrollment path after sharing the consumer
lifecycle code.

This proves a clean **initramfs** image acquiring and maintaining the native
catalog from preconfigured release trust. Full ordinary-user graphical login,
Software interaction, public release publisher selection, online distribution,
legacy Alpine migration, broader foreign-runtime support and persistent-device
acceptance remain roadmap 14 gates. The fixture key/repository is test data, not
a production trust root. A complete image build remains a sequence of staging
operations; publish its output only after all operations succeed.

Repeat with the existing native builder's inputs, a target sandbox and kernel:

```sh
v -path '@vlib|@vmodules|.|tests/hardware-platform|tools/accounts' \
  -o /tmp/native-catalog-check tests/packages/native-catalog-check.v
VINIX_HWTEST_TCG=1 V=/path/to/reviewed/v VFLAGS=-nocache \
  VINIX_NATIVE_CATALOG_INPUTS=/build/native-inputs \
  VINIX_NATIVE_CATALOG_SANDBOX=/build/aarch64-root/usr/bin/vinix-sandbox \
  /tmp/native-catalog-check --image --arch aarch64 --kernel /build/aarch64-kernel \
  --state-dir /build/new-short-state
```

Repeat for x86_64 with matching inputs and a new state path. Omit `--image` to
run the existing explicit-enrollment scenario. Run the local configuration
assertion file with `-gc none -manualfree` and the repository module path; the
normal distribution driver discovers it as a package core test.

- [Native checks](results/2026-10-16/image-configuration-host.txt), [final fixture](results/2026-10-16/image-configuration-core.txt), [sanitizers](results/2026-10-16/image-configuration-asan.txt), [CLI lifecycle](results/2026-10-16/image-configuration-cli.txt), [staging preflight](results/2026-10-16/image-configuration-preflight.txt)
- [Source/toolchain/artifact pins](results/2026-10-16/image-configuration-toolchain.json), [V host checks](results/2026-10-16/image-configuration-host.v), [V guest invocation](results/2026-10-16/image-configuration-guest.v)
- [AArch64 image receipt](results/2026-10-16/image-configuration-aarch64.json), [serial](results/2026-10-16/image-configuration-aarch64.serial.txt), [staging](results/2026-10-16/image-configuration-aarch64.stage.txt), [existing scenario](results/2026-10-16/image-configuration-aarch64.legacy.serial.txt)
- [x86-64 image receipt](results/2026-10-16/image-configuration-x86_64.json), [serial](results/2026-10-16/image-configuration-x86_64.serial.txt), [staging](results/2026-10-16/image-configuration-x86_64.stage.txt), [existing scenario](results/2026-10-16/image-configuration-x86_64.legacy.serial.txt)

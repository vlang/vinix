# Explicit catalog host selection qualification

`compose-catalog-for ARCH NEW_LOCK_DIRECTORY PROFILE CATALOG.json...` and the
public V `pkgcore.compose_catalog_for` API select `aarch64` or `x86_64` from
complete reviewed inputs. This permits composing the AArch64 Apple profile with
dual-host profiles without inventing an x86-64 Apple runtime. The original
`compose-catalog` retains its identical-target-set requirement. See the
[SDK contract](../../tools/packages/SDK.md#compose-application-catalogs).

The later [composition ownership qualification](composition-ownership-check.md)
measures planning and refusal lifetimes while preserving these canonical bytes
and exercises the rebuilt composition CLI inside both target guests.

The maintained V host driver builds the CLI, runs five core assertion suites
and the complete distribution CLI fixture, then repeats composition and Apple
profile assertions under clang ASan/UBSan (leak detection disabled). Its seventeen
build/run checks cover:

- Deterministic locks/provenance on both host selections, input order and JSON
  formatting independence, unchanged selected manifests/pins/selectors and shared
  packages. Full canonical input digests include omitted variants; changes there
  alter provenance even when selected catalog bytes stay unchanged.
- Mixed single/dual-host catalogs, unchanged strict composition, unsupported
  host refusal and packing without the omitted host's payload roots.
- Complete validation before selection: missing variants, unsafe sources,
  unresolved dependencies and unknown fields on the omitted host still refuse.
  Shared identity collisions, invalid profile IDs/counts and invalid targets refuse.
- Disk-space refusal, changed staged metadata, destination races, failure cleanup
  and retry. Existing scoped-root capture, symlink and changed-payload refusals
  continue through the same catalog builder.
- Real Apple/native producer API locks in one signed AArch64 catalog, explicit
  runtime dependencies, license/firmware policy refusal before activation, offline
  install, independent app removal, association cleanup and rollback.
- Literal CLI paths, CLI/API equivalence, argument counts, occupied destinations,
  publisher-schema admission and the existing signed distribution CLI lifecycle.

```sh
v -no-skip-unused -o /tmp/composition-target-check tests/packages/composition-target-check.v
V=/path/to/reviewed/v /tmp/composition-target-check /build/new-target-composition-check
```

The work directory must be new. The receipt records the compiler hash and each
completed check; individual logs remain beside it. Host fixtures use generated
ELF/Mach-O bytes for structural and package-lifecycle assertions, not execution.

The [Apple runtime guest controller](apple-runtime-check.v) now invokes the
production target-selection CLI for both app/runtime releases. It combines the
AArch64 Apple producer lock with a dual-host shared notice catalog, verifies
full Apple source provenance, refuses an x86-64 composition, packs and signs the
three-package catalog, then reviews installation of both roots. The shared
notice participates in upgrade, rollback, clean uninstall and offline cache
reinstall alongside real sandboxed Mach-O execution and retained private data.
The controller requires both composition markers and guest-initiated poweroff.

## Qualification, 2026-10-16

All seventeen host checks passed with the retained V 0.5.2 compiler, including
both sanitizer suites. The AArch64 guest passed in **18.6 seconds**, with both
composition markers, five Mach-O successes and normal poweroff. The package CLI,
guest init, account/session tools and launcher were built afresh; the kernel,
production sandbox and static iOS runtime match the prior
[Apple profile qualification](apple-profile-check.md) artifacts.

Four controller list/input/unsupported-host checks passed. Fresh x86-64
production staging built the package CLI, session runner and Linux runner in
**23.8 seconds**; each output has the expected ELF target. This tooling build
does not imply x86-64 Apple runtime execution.

The first guest attempt stopped during compilation because its shared-catalog
fixture omitted the required `format` field. After correcting that fixture,
the controller built and booted a fresh state directory successfully.

- [Host receipt](results/2026-10-16/composition-target-host.json),
  [composition assertions](results/2026-10-16/composition-target-composition.txt),
  [producer integration](results/2026-10-16/composition-target-profiles.txt) and
  [CLI regression](results/2026-10-16/composition-target-cli.txt).
- [Composition sanitizer](results/2026-10-16/composition-target-composition-sanitize.txt)
  and [producer sanitizer](results/2026-10-16/composition-target-profiles-sanitize.txt).
- [AArch64 receipt](results/2026-10-16/composition-target-aarch64.json),
  [serial log](results/2026-10-16/composition-target-aarch64.serial.txt) and
  [QMP log](results/2026-10-16/composition-target-aarch64.qmp.txt).
- [x86-64 tooling build](results/2026-10-16/composition-target-x86_64.json),
  [first build diagnostic](results/2026-10-16/composition-target-first-build.txt)
  and [source/artifact ledger](results/2026-10-16/composition-target-toolchain.json).

These checks do not qualify arbitrary upstream application catalogs, translation
runtimes, Apple graphical services or crash/power-cut durability. Section 14's
broader catalog and installed-device acceptance remain open.

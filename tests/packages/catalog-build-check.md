# Pinned catalog construction qualification

`pack-catalog` builds a private publisher workspace atomically from a format-1
catalog recipe. Each ID/version covers the declared host targets, every runtime
closure resolves, and imports must match the reviewed file inventory, lengths,
hashes and executable flags. The canonical workspace is consumed by the existing
signed release publisher. The [SDK contract](../../tools/packages/SDK.md#build-a-pinned-application-catalog)
describes input roots, disclosures, space checks, recovery and publishing.

The maintained `pkgcore/catalog_test.v` runner checks:

- Canonical metadata and equal release signatures after reordering the catalog.
- Offline install/remove of the app/runtime/data closure on both declared targets,
  with proprietary-license/firmware denial until the consumer explicitly permits it.
- Refusal of incomplete target coverage, duplicate identities, source/architecture
  mismatches and missing runtimes.
- Refusal of changed bytes, executable flags, extra selected files, source-root
  symlinks, occupied destinations and unknown/duplicate/escaped schema keys.
- Required payload pins and explicit proprietary/firmware flags.
- Captured source descriptors surviving replacement of a source directory's path.
- Space refusal, final object integrity refusal and destination races, without a
  visible partial workspace or leftover staging directory after handled failures.

The CLI fixture uses literal paths with spaces, punctuation and dollar signs,
checks the returned workspace digest and refuses reuse of an occupied destination
and a changed source. The existing package distribution driver includes this
runner along with signing, all package/core/protocol/registry runners, CLI,
Software UI/heap, both package staging targets and both desktop typechecks.

```sh
v -no-skip-unused -o /tmp/package-check tests/packages/distribution-check.v
/tmp/package-check --direct-tests --cross --desktop
```

Set `V` and the staged UI/desktop environment as described in the package README.
The catalog runner is also compiled with clang ASan/UBSan and executed using
`ASAN_OPTIONS=detect_leaks=0 UBSAN_OPTIONS=halt_on_error=1`. Leak detection is
disabled; this check covers the exercised catalog/import paths.

The real `packages-linux` guest fixture uses `pack-root` to inventory its built
Linux app, static runner, musl loader, shared library and redistribution notices,
then builds its publisher workspace through `pack-catalog`. A reordered recipe
must have the same canonical digest, and changed payload bytes must fail with no
published destination. The resulting workspace goes through signing, release
publication, offline installation and ordinary-account sandbox execution, plus
the existing update, rollback, trust, organization and clean-uninstall checks.
`PACKAGE CATALOG` is a required marker on both targets.

The 2026-10-13 [host receipt](results/2026-10-13/catalog-toolchain.json) records
19 assertion runners, CLI/UI/build checks and the passing catalog sanitizer run.
The guest receipts retain artifact hashes and serial logs:

- [AArch64 receipt](results/2026-10-13/catalog-aarch64.json) and [serial](results/2026-10-13/catalog-aarch64.serial.txt).
- [x86_64 receipt](results/2026-10-13/catalog-x86_64.json) and [serial](results/2026-10-13/catalog-x86_64.serial.txt).

Guest qualification uses QEMU TCG, the retained kernel tuple and a 600-second
functional deadline. Both completed every marker and powered off cleanly:
AArch64 in 140.7 seconds and x86-64 in 92.1 seconds.
These fixtures qualify catalog construction and the exercised
Linux loader/sandbox contract. They do not authenticate arbitrary upstream roots,
qualify every advertised application, establish a performance threshold or provide
ordinary-user graphical-session coverage. Release publisher enrollment and the
remaining advertised catalog/runtime migration remain acceptance work.

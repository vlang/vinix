# Release application declarations in staged images

The later [installed-release audit check](release-audit-check.md) carries this
declaration through real blank-disk installation and four installed-root boots,
and adds an ordinary **Check release apps** action for baseline drift.

Selecting advertised application requirements now makes normal package staging
publish the exact resolved format-2 lock to
`/usr/share/vinix-packages/applications.json`. Software's **Deployment → Review
release apps** discovers this optional file and starts the ordinary read-only
proposal. Full-set changes, including removals, still need confirmation and
administrator approval. Publisher trust, permissions, licensing, architecture,
dependency/runtime bounds and exact metadata pins keep their existing gates.

The stager owns a closeable `ImageApplications` plan before compiler lookup.
It captures the canonical lock, configuration identity and report independently
of original requirements/bundle files. Check reports give the fixed image path,
publish/preserve/none decision, byte count and newline-inclusive SHA-256.
`--check` changes no image files. Normal staging publishes the matching bundle
and configuration before declaring applications; it initializes no consumer
generation or automatic deployment.

Publication checks the captured root, configuration, captured/published bundle,
signed expiry, payload integrity, controlled parents and free space with 64 MiB
headroom. A new file uses exclusive atomic publication and mode 0644. An identical
controlled single-link file is preserved. Different/changed files, aliases,
FIFOs, directories, hard links, shared-write parents and unexpected modes refuse.
Pre-publication failures retire temporary files. Errors after publication say
the file was saved; a retry preserves its complete bytes. A changed declared set
requires a fresh image staging root.

The existing [image application fixture](../../tools/packages/pkgcore/image_applications_test.v)
now covers both target locks, independent digests and reports, removed original
inputs, required publication order, preservation, occupied/late destinations,
changed trust/payload/root/parents, injected write/space/flush/checkpoint failures,
concurrent owner bytes and retry. Existing export, requirements, catalog, policy,
dependency and atomic-writer checks run alongside these assertions.

The [Software fixture](software_release_fixture.v) checks optional discovery,
missing/alias refusal with retained drafts, full-closure read-only proposals,
frozen literal filenames, separate confirmation and late chooser retirement.
Its warmed allocation mode includes full/compact rendering, repeated discovery,
missing-file diagnostics, navigation and retirement. Discovery uses stack stat
scratch after the first allocation check exposed retained standard-helper buffers.

The [native catalog controller](native-catalog-check.v) builds reviewed
requirements and uses the production staging CLI. The actual Software controller
then discovers the image declaration as an ordinary administrator and installs
Hello, Counter and Memo in one approved transaction. Its existing launch,
standard-account refusal, private data, upgrade, rollback, uninstall and cached
reinstall checks continue afterward. These are real guest services and native
SDK programs with headless UI trees; compositor presentation is not exercised.

Reproduce using the maintained V drivers and the same pinned compiler, generated
desktop assets, headless ui2 module and target toolchains as the linked checks:

```sh
v -o /tmp/image-check tests/packages/image-export-check.v
/tmp/image-check NEW_HOST_WORK
v -o /tmp/distribution-check tests/packages/distribution-check.v
/tmp/distribution-check --direct-tests --software-only --desktop
v -path '@vlib|@vmodules|.|tools/accounts|tests/hardware-platform' -o /tmp/image-runtime tests/packages/image-export-runtime-check.v
/tmp/image-runtime --arch aarch64 --kernel KERNEL --state-dir NEW_CORE_WORK
v -path '@vlib|@vmodules|.|tools/accounts|tests/hardware-platform' -o /tmp/catalog-runtime tests/packages/native-catalog-check.v
/tmp/catalog-runtime --software --arch aarch64 --kernel KERNEL --state-dir NEW_SOFTWARE_WORK
```

Repeat guest checks with `--arch x86_64`. They require `VINIX_HWTEST_TCG=1`;
native checks also require verified `VINIX_NATIVE_CATALOG_INPUTS`, target
`VINIX_NATIVE_CATALOG_SANDBOX` and `VINIX_PACKAGE_TEST_UI2`. The retained V guest
helper records the selected toolchain/kernel paths. Work directories must be new.

This adds a declared release catalog workflow. Production publisher enrollment,
legacy Alpine/vendor catalog migration, full graphical sessions, autonomous
installed boot and broader foreign-runtime/device/crash acceptance remain open.

## Recorded results, 2026-10-16

All 32 package/cache/CLI host checks and fourteen focused Software compile/run
checks passed. Core and UI ASan/UBSan checks passed with leak detection disabled.
The maintained Software-only driver passed its functional suite, all 27 allocation
modes, both full desktop Linux architecture typechecks and launcher checks. After
warmup, 1,000 release discovery/full/compact/navigation cycles retained zero
tracked bytes; this does not measure whole-service or broker allocation freedom.

Fresh core guests passed on AArch64 (88.5 s) and x86_64 (71.4 s), covering image
declaration preservation and failure boundaries alongside existing export and
deployment assertions. Fresh Software guests passed on AArch64 (23.3 s) and
x86_64 (27.0 s). Both used the production stager, discovered the declared native
catalog as an ordinary user, reviewed the exact complete set and installed it
after separate administrator approval. Native launches, private data, standard
account refusal, update, rollback, uninstall and cached reinstall also passed.
The kernels match the earlier Software qualification; no kernel change was made.

The initial retained-discovery allocation failure and malformed test-manifest
build refusals are recorded separately. Final product sources remained unchanged
during the successful qualification runs. Compiler, source, copied controller,
staged declaration, guest program and raw-log hashes are retained. These runs
exercise headless UI trees and initramfs images; persistent installed-root and
full graphical presentation acceptance remain separate gates.

- [host summary](results/2026-10-16/image-catalog-host.txt)
- [package/cache/CLI checks](results/2026-10-16/image-catalog-core-host.json)
- [focused Software checks](results/2026-10-16/image-catalog-ui-host.json)
- [controller checks](results/2026-10-16/image-catalog-ui.txt)
- [allocation checks](results/2026-10-16/image-catalog-memory.txt)
- [sanitizers](results/2026-10-16/image-catalog-asan.txt)
- [maintained Software driver and target checks](results/2026-10-16/image-catalog-driver.txt)
- [AArch64 core guest](results/2026-10-16/image-catalog-core-aarch64.json)
- [x86_64 core guest](results/2026-10-16/image-catalog-core-x86_64.json)
- [AArch64 Software guest](results/2026-10-16/image-catalog-software-aarch64.json)
- [x86_64 Software guest](results/2026-10-16/image-catalog-software-x86_64.json)
- [initial attempts](results/2026-10-16/image-catalog-attempts.txt)
- [source/toolchain/artifact ledger](results/2026-10-16/image-catalog-toolchain.json)

# SQLite application profile qualification

The `sqlite-catalog` publisher command inventories a concrete SQLite CLI and
separate musl/SQLite runtime on both supported architectures. The
[SDK profile](../../tools/packages/SDK.md#sqlite-cli-publisher-profile) defines
the prepared roots, compatibility range, notices, data directory and limits.
The existing signed release/store workflow installs this closure without an
image rebuild or manual runtime changes.

`pkgcore/sqlite_profile_test.v` checks canonical output, complete architecture
and runtime coverage, unchanged application metadata for a runtime-only update,
explicit permission/license disclosures, both pinned imports and cleanup. It
refuses wrong ELF targets/types/interpreters, invalid program-header bounds,
missing notices, incompatible versions, source-root links and existing outputs.
These structural tests use synthetic headers; real executables are qualified
separately below. The existing distribution driver includes this assertion
runner with package/registry/protocol tests, CLI, Software UI/heap, both target
staging builds and both desktop typechecks.

The V input builder, `sqlite-build.v`, checks all four upstream source files
against [sqlite-source.json](sqlite-source.json) before compiling its private
snapshot. This source lock records the cached SQLite 3.53.4 amalgamation bytes
and upstream download URL. It is a content/provenance pin, not evidence of an
authenticated network download or an upstream signature. Authenticate source
delivery independently before using it for a public release.

The builder invokes each target's musl compiler for the unmodified upstream C
sources and V for the SDK runner. Implementation, orchestration and test tooling
are V. The base shared library omits optional math functions; the second enables
them. Extension loading is disabled in both. Each variant has the exact same
PIE CLI and static runner bytes for its architecture. The builder retains the
SQLite header notice, musl copyright and Vinix license, plus source pins, build
commands and artifact hashes in `build.json`.

```sh
v -no-skip-unused -o /tmp/sqlite-build tests/packages/sqlite-build.v
/tmp/sqlite-build /trusted/sqlite-amalgamation-3530400 /build/new-sqlite-inputs
v -no-skip-unused -path '.|tests/hardware-platform|@vlib|@vmodules' \
  -o /tmp/sqlite-check tests/packages/sqlite-runtime-check.v
VINIX_HWTEST_TCG=1 VINIX_SQLITE_INPUTS=/build/new-sqlite-inputs \
  VINIX_SQLITE_SANDBOX=/build/target-root/usr/bin/vinix-sandbox \
  /tmp/sqlite-check --arch aarch64 --kernel /build/aarch64-kernel \
  --state-dir /build/new-sqlite-aarch64
```

Repeat the final command for `x86_64` with that target's kernel, sandbox and new
state directory. Set `V`, cross compilers, sysroots, firmware and Limine paths
as described by the hardware-platform controller. The SQLite controller requires
TCG and retains all fixture hashes, service/session/init binaries, kernel and
serial log. Both architecture roots are publisher data in the guest; only the
guest's matching installed closure executes.

The real `packages-sqlite` scenario generates a fixture key, builds both catalog
locks, imports all four packages per release, signs two successive repositories,
enrolls the key offline and installs through the production service. It requires:

- Actual SQLite version 3.53.4, WAL mode, table writes, database reopen and
  `PRAGMA integrity_check` returning `ok` under the ordinary launch account.
- Account-owned database files and refusal to create a database elsewhere in
  that account's home. The upstream shell can fall back to an in-memory database
  and exit successfully after a denied `.open`; the check requires its error
  diagnostic and verifies that no outside file was created.
- A visible runtime-only update from 1.0.0 to 1.1.0, with the exact application
  manifest unchanged; `ceil()` becomes available from the new real library.
- Rollback removing that function while retaining database contents, followed
  by another runtime update.
- Uninstall removing the active app/runtime closure and retaining the database.
  Hiding the repository payload directory then reinstalling in offline mode
  must use the verified cache, restore the new library and reopen the same data.
- Every required serial marker, no forbidden failure marker and guest-initiated
  clean poweroff, judged by the existing hardware-platform QMP controller.

The 2026-10-13 [toolchain receipt](results/2026-10-13/sqlite-toolchain.json)
records the pinned V compiler, 20 passing assertion runners, CLI/Software/heap,
both package staging builds and desktop typechecks/launchers. The affected
launch regression passed again after adding advisory locks to baseline file
operations. The profile runner also passed clang ASan/UBSan with leak detection
disabled; this checks its exercised paths, not leak freedom.

Retained evidence includes the [input build record](results/2026-10-13/sqlite-input-build.json),
[base catalog](results/2026-10-13/sqlite-base.catalog.json) and
[updated runtime catalog](results/2026-10-13/sqlite-math.catalog.json).
These catalog locks pin the qualified bytes; they are not signed public releases.
Guest receipts each record 36 artifact hashes and a 600-second functional deadline:

- [AArch64 receipt](results/2026-10-13/sqlite-aarch64.json) and
  [serial log](results/2026-10-13/sqlite-aarch64.serial.txt): 46.3 seconds.
- [x86_64 receipt](results/2026-10-13/sqlite-x86_64.json) and
  [serial log](results/2026-10-13/sqlite-x86_64.serial.txt): 46.8 seconds.

Both runs printed every required marker and powered off cleanly. The retained
kernel and sandbox inputs are the previously qualified cached binaries; this
application increment does not change the kernel.

These are application lifecycle checks on the retained kernel/compiler tuple.
They do not establish performance thresholds, persistence across power cuts,
arbitrary SQLite builds/versions, upstream authentication, public publisher
enrollment or ordinary-user graphical-session/terminal integration. The fixture
key does not enroll a supported public repository. Other advertised applications
and compatibility runtimes remain separate roadmap acceptance work.

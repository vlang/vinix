# Packing inventory and reply ownership

Direct packing now owns its decoded template and growing payload inventory until
it transfers the successful reply. Any failure retires both owners, including
partly walked files and a payload whose hash/copy/cache checkpoint refused.
Successful packing separately retires the template's discarded `files` array.
Local path strings and the publisher encoder buffer are released on every exit.

Payload and directory-entry strings move into their owning arrays without V's
implicit variable-append clone. Inventory growth retires superseded buffers.
Captured source and copy verification use synchronous stack stat records.
These changes preserve the existing type, identity, size, executable-mode,
hash, entry-count and traversal checks.

Object publication now replaces the literal digest path. A directory occupying
that slot refuses publication and retains its contents; the former `os.rename`
directory behavior could put the object inside that directory. A refused walk
still retains already completed objects and `.new` partials for inspection and
retry. No new publisher transaction or arbitrary concurrent-writer guarantee is
introduced.

`pkgcore.pack` and `pkgcore.pack_root` return independently owned `Package`
metadata. Call `package.close()` after use; repeated close is safe and resets
the reply. This leaves saved manifests and objects available. Do not close
package records borrowed from states, catalogs or plans: their owning object
controls their lifetime. Both CLI commands encode and close their reply.

The [ownership fixture](../../tools/packages/pkgcore/pack_ownership_test.v) covers:

- Twelve cold/cache walk cases with 16 and 64 files. Each tests success, late
  hash refusal and late copy/cache refusal. The cached cases run 128 times and
  cold cases eight times under `-d track_heap -gc none -manualfree`, for **816
  tracked walks**. Every case retains zero bytes and allocations after closing
  its inventory. Ordinary functional builds run two attempts per case.
- Complete public packing calls measured separately after reply retirement:
  1/32-file success, refusal after locking and a 32-file late hash refusal,
  each repeated sixteen times. These calls still include workspace, lock and
  durability helper scratch; they are not claimed to retain zero bytes.
- Direct/prepared-root replies after argument/template/private-workspace
  retirement and sibling close, discarded template inventories, literal launch
  declarations, repeated close and exact legacy encoder/manifest bytes.
- Late package validation, manifest publication and object-slot directory
  failures. Existing saved metadata or recovery bytes survive and corrected
  input permits an exact retry. The production pack/root CLI replies preserve
  the same complete JSON schema and declarations.

The retained baseline measures **19,275 bytes / 64 allocations** for a cached
one-file call and **79,526 bytes / 411 allocations** for a cached 32-file call,
after releasing the original reply. A late 32-file refusal retained **61,254
bytes / 470 allocations**. After this change, those calls retain **12,896 bytes /
37 allocations** on success and **12,152 bytes / 31 allocations** on refusal in
the host probe. The 32-file successful case retains about **84% fewer bytes**.
The remaining whole-call helper ownership and complete prepared-root/profile
construction are separate open boundaries. This increment changes no kernel
code and makes no kernel leak or media power-loss claim.

The [host controller](pack-ownership-check.v) performs 45 build/test checks:
production CLI, sixteen assertion suites, literal CLI maintenance, tracked
packing, three clang ASan/UBSan suites and tracked native-profile regression.
Existing suites cover captured copy/resume, source mutation, bounded imports,
publisher locking, all five publisher profiles and signed catalog/composition
maintenance. Sanitizer leak detection is disabled; allocation measurements use
the separate tracker.

The [guest controller](pack-ownership-runtime-check.v) builds seven assertion
programs on both architectures: tracked ownership, source packing, copy,
prepared-source mutation, import, catalog and signed releases. It requires all
twelve zero-retention markers, every process result and guest shutdown within
300 seconds. Receipts pin the unchanged qualification kernel, PID 1, seven
executables and raw serial output. Structural application fixtures are packaged
and maintained, not executed as applications.

```sh
v -o /tmp/pack-ownership-check tests/packages/pack-ownership-check.v
V=/path/to/reviewed/v /tmp/pack-ownership-check /build/new-pack-owner-host

v -path '@vlib|@vmodules|.|tools/accounts|tests/hardware-platform' \
  -o /tmp/pack-ownership-runtime-check tests/packages/pack-ownership-runtime-check.v
VINIX_HWTEST_TCG=1 V=/path/to/reviewed/v VFLAGS=-nocache \
  /tmp/pack-ownership-runtime-check --arch aarch64 --kernel /build/aarch64-kernel \
  --state-dir /build/new-pack-owner-arm
```

Repeat with `x86_64`, its kernel and a fresh state directory. Cross compilers,
sysroot and Limine follow the
[hardware controller requirements](../hardware-platform/README.md).
Production publisher/catalog migration, graphical sessions, broader foreign
runtimes and full section 14 acceptance remain open.

## Recorded results, 2026-10-17

All **45 host build/test checks** passed, including production pack/root JSON
replies, three ASan/UBSan suites, every publisher profile, signed literal CLI
maintenance and the existing tracked native-profile metadata checks. All **816
measured walks** retained zero bytes and allocations in the host and both guests.
Complete packing still retained the separate helper scratch reported above;
the 18 KB / 64-allocation test ceiling is not a zero-retention claim.

Fresh QEMU TCG runs passed AArch64 (**110.4 seconds**) and x86_64
(**56.1 seconds**). Each completed all seven assertion programs and requested
guest shutdown. Whole-call guest success retained 8,408 bytes / 6 allocations
on AArch64 and 8,411 bytes / 6 allocations on x86_64, independent of the tested
1/32-file count. These measurements qualify their stated fixture boundaries;
they do not establish complete prepared-root/profile ownership or graphical
application/runtime acceptance. No qualification attempt failed in these final
host or guest runs.

- [Original retention](results/2026-10-17/pack-ownership-baseline.txt) and
  [baseline fixture](results/2026-10-17/pack-ownership-baseline.v).
- [Host receipt](results/2026-10-17/pack-ownership-host.json),
  [check summary](results/2026-10-17/pack-ownership-host.txt),
  [functional assertions](results/2026-10-17/pack-ownership-core.txt),
  [tracked memory](results/2026-10-17/pack-ownership-memory.txt),
  [ownership sanitizer](results/2026-10-17/pack-ownership-asan.txt),
  [literal CLI](results/2026-10-17/pack-ownership-cli.txt) and
  [native metadata regression](results/2026-10-17/pack-ownership-native.txt).
- AArch64 [receipt](results/2026-10-17/pack-ownership-aarch64.json),
  [report](results/2026-10-17/pack-ownership-aarch64.txt),
  [serial](results/2026-10-17/pack-ownership-aarch64.serial.txt) and
  [QMP](results/2026-10-17/pack-ownership-aarch64.qmp.txt).
- x86_64 [receipt](results/2026-10-17/pack-ownership-x86_64.json),
  [report](results/2026-10-17/pack-ownership-x86_64.txt),
  [serial](results/2026-10-17/pack-ownership-x86_64.serial.txt) and
  [QMP](results/2026-10-17/pack-ownership-x86_64.qmp.txt).
- [Source, compiler and artifact ledger](results/2026-10-17/pack-ownership-toolchain.json)
  and [V retention/verifier](results/2026-10-17/pack-ownership-retain.v).
  Run the verifier with `--verify` from the repository to check retained local
  hashes. Baseline source is the preceding commit plus the retained fixture;
  copy that fixture into `tools/packages/pkgcore` in an isolated baseline
  checkout to rebuild it with tracking and `--pack-owned-baseline`.
  Whitespace checks recognize raw serial CR with `core.whitespace=cr-at-eol`.

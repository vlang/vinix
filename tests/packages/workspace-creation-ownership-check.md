# First workspace creation ownership

Export target preparation now owns its trimmed name, parent paths, ancestor
walk, physical paths and returned destination. Every refusal retires that
scratch, including existing/dangling entries, unsafe ancestors and file parents.
Physical path resolution and occupancy checks retain the admitted-parent and
new-destination rules. Publication still uses captured staging directories and
exclusive rename through their held parents.

Recursive package directory creation now uses one terminated byte buffer and
synchronous stat records instead of `os.mkdir_all`'s split/concatenation scratch
and `os.mkdir`'s retained resolution buffers. It preserves POSIX parent aliases,
dot components, repeated/trailing separators and umask. Existing ancestors are
left unchanged. Callers still admit the final directory's ownership, mode and
ordinary no-follow identity separately; `owned_directory` enforces its explicit
leaf mode. Failed creation leaves completed parents available for inspection
and corrected retry. The helper is not an exclusive publication primitive or a
snapshot of concurrent owner changes.

The [creation fixture](../../tools/packages/pkgcore/workspace_creation_ownership_test.v)
measures **1,408 helper calls**: flat/eight-level export preparation, fresh
publisher workspaces and private directory creation, plus existing destination,
dangling alias, unsafe parent, file parent and native mkdir failure. Each case
runs 128 times and requires zero retained bytes and allocations after retiring
its result or error.

It also measures **192 complete first packing calls**: 1/32 files, flat/eight-level
missing parents, success and refusal after locking, plus 32-file late hash/copy
refusals. Every attempt starts without a repository, child directories, lock or
cached objects. Each case runs sixteen times and requires zero retained bytes
and allocations after closing the reply/error. Unmeasured retry verifies the
complete inventory and exact saved manifest. These include cold object copies.

Fixture setup initializes immutable process-wide JSON field metadata before
measurement. This does not create or warm filesystem output. The original
baseline did not initialize the payload encoder cache, so its first successful
call includes that one-time metadata; subsequent baseline rows already share it.
The qualified boundary is filesystem/call storage, not process initialization.

Functional checks also exercise relative `alias/..`, trailing separators,
restrictive umask, unchanged ancestor modes, symlink-leaf refusal, empty/NUL
paths, a non-directory prefix and retained partial parents after exceeding a
native path limit, followed by corrected retry. macOS uses a 300-byte component;
the guests exceed Vinix's 4,096-byte copied-path bound with 8,192 bytes, since
its tmpfs accepts the host's overlong component. Existing workspace containment and
publisher exclusion tests remain mandatory.

The baseline retained **9,750 bytes** for flat export preparation, **47,075** for
eight-level preparation, **13,911/51,252** for fresh workspaces and
**5,358/39,486** for private directories. Complete 32-file first packing retained
**30,844 bytes** with a flat destination and **74,137** with missing parents;
late hash/copy refusal retained **25,202/66,511**. The new measurements require
zero retained V bytes and allocations for each stated boundary.

The [host controller](workspace-creation-ownership-check.v) runs **79 build/test
checks**: production CLI, 27 functional suites, literal signed CLI maintenance,
four tracked fixtures and seven ASan/UBSan suites. It includes all five
publisher profiles, catalog/composition/export/mirror maintenance, captured
copy/import, consumer lifecycle, coordination locks and service operations.
Sanitizer leak detection is disabled; the separate tracker measures retained
V allocations.

The [guest controller](workspace-creation-ownership-runtime-check.v) builds 15
programs for each target and requires all creation, existing helper and packing
zero-retention markers, 24 fresh creation case processes, five fresh workspace
case processes and shutdown. Each creation case keeps all 128 helper or sixteen
first-pack attempts; process boundaries contain unmeasured fixture setup/cleanup.
It records `/proc/kernel-resources` before and after six seconds of cleanup
before each creation case and before the workspace batch. This follows the
existing export-retirement fixture's five-second unlinked-node grace boundary.
The scenario deadline is 600 seconds, including these waits.
The initial unsplit guest runs reported out-of-memory errors after five creation
case markers on both targets. Those failed attempts are retained separately;
passing cohorts do not establish a kernel cause or qualify an unlimited unsplit
fixture lifetime. The first cohort runs then refused the fixture's assumption
that tmpfs rejects 300-byte names; both failures are retained too. The maintained
fixture exceeds each platform's actual native limit. A third x86 run without
inter-case cleanup exited at the deep one-file locked case without child output;
the ARM controller was interrupted before reporting an outcome. Those attempts
are retained as failures/incomplete evidence too. The current qualification's
receipts pin the unchanged kernel, PID 1, fifteen executables and raw serial
output. Structural application fixtures are maintained as packages, not executed
as applications.

These checks do not qualify complete prepared-root/profile/catalog/release
construction ownership, all consumer allocations, kernel heap behavior, media
power-loss recovery, production publisher/catalog migration, graphical sessions
or broader foreign runtime/device acceptance. The section 14 acceptance gates
remain open.

```sh
v -o /tmp/workspace-creation-check tests/packages/workspace-creation-ownership-check.v
V=/path/to/reviewed/v /tmp/workspace-creation-check /build/new-creation-host

v -path '@vlib|@vmodules|.|tools/accounts|tests/hardware-platform' \
  -o /tmp/workspace-creation-runtime tests/packages/workspace-creation-ownership-runtime-check.v
VINIX_HWTEST_TCG=1 V=/path/to/reviewed/v VFLAGS=-nocache \
  /tmp/workspace-creation-runtime --arch aarch64 --kernel /build/aarch64-kernel \
  --state-dir /build/new-creation-arm
```

Repeat with `x86_64`, its kernel and a fresh state directory. Cross compilers,
sysroot and Limine follow the
[hardware controller requirements](../hardware-platform/README.md).

## Recorded results, 2026-10-17

The host qualification passed all **79** checks, including seven ASan/UBSan
suites. All 23 creation ownership cases measured zero retained V bytes and
allocations. The complete native profile diagnostic retained **138,349 bytes
in 557 allocations**, compared with **165,933/648** in the preceding increment;
complete profile ownership remains open despite the reduction. Its separately
qualified metadata boundary still measures zero.

Both unchanged kernels passed all 15 program groups, 24 creation cases and five
publisher-workspace cases, including all 23 zero-retention creation markers:

| Target | Result | Time | Evidence |
| --- | --- | --- | --- |
| AArch64, QEMU TCG | PASS | 509.5 s | [receipt](results/2026-10-17/workspace-creation-ownership-aarch64.json), [serial](results/2026-10-17/workspace-creation-ownership-aarch64.serial.txt) |
| x86_64, QEMU TCG | PASS | 309.0 s | [receipt](results/2026-10-17/workspace-creation-ownership-x86_64.json), [serial](results/2026-10-17/workspace-creation-ownership-x86_64.serial.txt) |

Each run records 25 before/after cleanup pairs. Every recorded resource
`Denied` counter is zero. Charged resources fall during cleanup, but the samples
do not establish a cause for the earlier failures or qualify an unsplit lifetime.
The failed unsplit, invalid-limit and no-cleanup attempts remain in the adjacent
`failed-1`, `failed-2` and `failed-3` records for each architecture; ARM's third
attempt is explicitly marked interrupted without an outcome.

The [host receipt](results/2026-10-17/workspace-creation-ownership-host.json),
[baseline](results/2026-10-17/workspace-creation-ownership-baseline.txt),
[creation measurements](results/2026-10-17/workspace-creation-ownership-memory.txt),
[native diagnostic](results/2026-10-17/workspace-creation-ownership-native.txt) and
[source/compiler/artifact ledger](results/2026-10-17/workspace-creation-ownership-toolchain.json)
retain this increment's evidence. The [V retainer](results/2026-10-17/workspace-creation-ownership-retain.v)
checks the recorded hashes with `--verify` while the pinned local build artifacts
are available. Historical source pins describe this snapshot and will differ
after subsequent implementation changes.

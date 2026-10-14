# Fixed publisher profile inventory qualification

Native, SQLite and FFmpeg publisher profiles now share a check of the complete
imported file inventory. Each fixed recipe must produce exactly its declared
file paths; every declared notice/build source must remain nonempty and at most
1 MiB. The check runs before inspecting executable objects or the pinned FFmpeg
source archive, so those required objects must actually be present at their
declared paths. The existing ELF checks and archive length/hash/mode checks then
admit the captured payload bytes.

Previously SQLite and FFmpeg preflight checked notices and the archive as
ordinary files, but their import allowed directory selectors. Replacing a file
with a one-file directory could retain the inventory count while changing its
path. A missing `sources/ffmpeg.tar.xz` then skipped the per-file source-pin check.
Notice lengths were also not checked after copying. The before-change CLI
reproduction observes the private staging directory after preflight and replaces
either the notice or archive while the first large fixture executable imports.
Both architectures start with valid structural ELF headers and the real pinned
FFmpeg archive; the fixture executables are never run. The old CLI accepts all
four cases and publishes locks containing empty notices or substituted paths.
The final CLI refuses all four, retains no output lock and cleans the stage.
This tests publisher input consistency before signing; no release key is enrolled.

Native's equivalent checks now use the same helper, with its existing contracts
and canonical output preserved. Generic `pack-root` directory selectors keep
their existing behavior. Source publishers still review/authenticate their inputs
and qualify runtime behavior before signing a release.

`pkgcore/profile_inventory_test.v` exercises both architectures and every fixed
recipe with exact inventories, missing/extra/duplicate files, one-file-directory
path substitutions and empty/oversized notices. The inclusive 1 MiB notice limit
remains accepted. SQLite/FFmpeg assertion runners use the existing private
checkpoint seam to replace files after preflight deterministically. They require
inventory/notice diagnostics before publication, disk-space refusal and staging
cleanup. SQLite also restores each damaged notice and requires a retry to emit
the original lock bytes. FFmpeg's synthetic source fixture stays intentionally
unpinned: its post-preflight tests must fail on the substituted inventory/notice
before the archive hash check, while its original source-pin refusal remains.

The host checks compare real Native, SQLite and FFmpeg catalog bytes with their
previously retained locks. They also run the existing signed CLI lifecycle,
catalog/composition/import/release regressions and profile sanitizers. The
[composed catalog guest controller](composition-runtime-check.v) rebuilds the
service and imports the retained real SQLite and FFmpeg inputs on each target.
Its signed five-package install exercises SQLite WAL/database integrity and
FFmpeg/FFprobe audio workflows under the isolated ordinary launch account,
runtime-only upgrade, rollback, clean uninstall and cache-only reinstall with
retained database/media. Only matching-architecture packages execute; both input
architectures are staged as publisher data with their build-record hashes checked.

Run the focused assertions from this checkout with a reviewed V compiler:

```sh
/path/to/v -nocache -no-skip-unused -gc none -manualfree \
  -path '@vlib|@vmodules|.' -o /tmp/profile-inventory \
  tools/packages/pkgcore/profile_inventory_test.v
/tmp/profile-inventory
```

The maintained distribution driver discovers all four profile assertion files.
See [composition qualification](composition-check.md) for the guest command,
required pinned inputs, sandbox and kernel selection. Sanitizers disable leak
detection; these checks make no whole-process allocation claim. Public publisher
enrollment, broader catalog migration and graphical/runtime acceptance remain
separate roadmap requirements.

## Recorded results, 2026-10-14

All eight core runners passed: inventory, SQLite, FFmpeg, native, catalog,
composition, import and release. All three profile runners passed clang
ASan/UBSan with leak detection disabled and undefined behavior fatal. The full
signed CLI lifecycle passed. Real Native, SQLite and FFmpeg profile output
exactly matches the previously retained catalog bytes.

The same four production-CLI input races accepted before the fix are now
refused with inventory/notice diagnostics, no output lock and no leftover stage.
Restoring both FFmpeg source archives permits retry at the refused destination,
producing six variants with both exact upstream source pins. Synthetic fixture
executables in these admission probes are never launched.

Both fresh TCG composition guests passed every required marker and clean
poweroff: AArch64 in 103.297 seconds, x86_64 in 145.604 seconds. They rebuilt init,
the package service and account/session programs with the final implementation,
using retained target kernels and production sandboxes. Each receipt checks
79 artifact hashes, including 70 profile inputs and both build records; QMP
shutdown logs are retained separately. Concurrent kernel edits were excluded
by reusing the recorded kernels. These are headless application-maintenance
checks, not new graphical/ABI acceptance.

Evidence: [before](results/2026-10-14/profile-inventory-baseline.txt),
[accepted source-directory lock](results/2026-10-14/profile-inventory-before-source.catalog.json),
[after](results/2026-10-14/profile-inventory-after.txt),
[restored retry](results/2026-10-14/profile-inventory-recovery.txt),
[host checks](results/2026-10-14/profile-inventory-host.txt),
[sanitizers](results/2026-10-14/profile-inventory-asan.txt),
[AArch64 receipt](results/2026-10-14/profile-inventory-aarch64.json),
[serial](results/2026-10-14/profile-inventory-aarch64.serial.txt),
[QMP](results/2026-10-14/profile-inventory-aarch64.qmp.txt),
[x86_64 receipt](results/2026-10-14/profile-inventory-x86_64.json),
[serial](results/2026-10-14/profile-inventory-x86_64.serial.txt),
[QMP](results/2026-10-14/profile-inventory-x86_64.qmp.txt) and
[source/compiler/artifact ledger](results/2026-10-14/profile-inventory-toolchain.json).

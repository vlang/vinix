# Launch-plan ownership

Sandbox and account-session planners return independent `Launch` values.
`Launch.close()` releases argument strings, vector storage and paths, resets all
fields and supports repeated close. Requests, decoded state, selected account
and input paths can be retired before reading a returned plan; two independently
created plans do not share ownership. Manually assembled borrowed values retain
their caller's lifetime and must not use this retirement helper.

Dependency traversal now borrows installed manifests explicitly and retires its
queue, key map and result vector. The frozen compiler's ordinary struct append
previously deep-copied each manifest. Planning also retires selected-package
scratch, generation numbers, paths, promises, library lists/joins, SDK
environment, DISPLAY input and intermediate template substitutions. Partial
arguments are released on every refusal. Vector growth releases old buffers.
Document target checks use stack native stat scratch while preserving regular
target checks and alias following. Synchronous application/session consumers
defer plan cleanup until after child completion, including refusal before spawn.
The standalone application runner also retires its owned installed snapshot.

The allocation fixture checks 36 architecture/kind/mode combinations: both
architectures, native/Linux/Windows/Apple planning, regular/terminal/command/
command-terminal launches and native window protocols 1/2. It checks 0/1/64
dependencies with shared edges/cycles, 256 documents/arguments, five account
handoff modes with 0/1/64/256 documents, and eight policy/publisher/SDK/document
refusals. Each tracked case repeats 1000 times with zero retained bytes.
Untracked and sanitizer loops repeat 32 times. Source-retirement and sibling
retirement assertions exercise ownership separately from allocation counts.

Matched probes use an unchanged production snapshot from `f0d623522`, under
the same compiler/options and fixtures. SHA-256 hashes of the complete encoded
`Launch` value match for all 56 successful sandbox/session cases. Accepted old
plans are compared for bytes only, since their fields had mixed ownership and
no public retirement method. Retention comparisons measure only refusals, where
there is no returned owner, and explicitly retire error objects/messages.

| Five warmed refusals | Previous retained bytes | Current retained bytes |
| --- | ---: | ---: |
| Revoked dependency publisher | 300,450 | 0 |
| Weak dependency publisher | 283,330 | 0 |
| Undeclared file permission | 432,040 | 0 |
| Dependency policy allowlist | 293,980 | 0 |
| Invalid SDK data directory | 431,940 | 0 |
| Directory as document | 436,955 | 0 |
| Relative document | 436,235 | 0 |
| Missing document | 437,115 | 0 |

Existing literal-command, context, session, distribution, document target,
state, window, private-data, namespace, registration-parent and service tests
run alongside the new fixture. Native ASan/UBSan checks use the manual-free
build; heap retention is measured by the separate allocation tracker, with
fixture setup outside the measured region. No kernel change is involved.

This qualifies plan ownership and existing pre-execution checks. It does not
measure every service/process allocation, run foreign applications, grant a
graphical seat or qualify new runtime compatibility. Roadmap 14 remains open
for production publisher enrollment, catalog migration, graphical login/display
integration and wider foreign-runtime/filesystem acceptance.

## Recorded results, 2026-10-16

All **40 focused compile/run checks** passed: thirteen core pairs, tracked and
ASan/UBSan pairs, matched previous/current comparison pairs, four CLI/driver
checks and two guest-tool builds. All 56 complete plan hashes match. The tracked
fixture passed its 1000-cycle assertions; the sanitizer fixture passed without
invalid reads, frees or undefined behavior.

Fresh QEMU TCG guests passed with clean shutdown and ten verified artifact
hashes each: AArch64 **19.5 seconds**, x86_64 **19.8 seconds**. The seven native
workers cover ownership, commands, sessions, SDK context, regular document
targets, installed namespaces and registration parents. Deadlines qualify
functionality rather than performance. The frozen compiler's normal guest
pruning is retained; enabling `no-skip-unused` on the minimal init exposed
unlinked standard-library capture helpers before boot, so those extra flags
are used only for the native host assertions.

To repeat the allocation fixture from the repository root, use the pinned V
compiler (or the supported compiler selected for the checkout):

```sh
v -nocache -no-skip-unused -gc none -manualfree -d track_heap \
  -path '@vlib|@vmodules|.|tools/accounts' -o /tmp/launch-ownership \
  tools/packages/pkgcore/launch_ownership_test.v
/tmp/launch-ownership
v -path '@vlib|@vmodules|.|tests/hardware-platform' \
  -o /tmp/launch-ownership-guest tests/packages/launch-ownership-runtime-check.v
/tmp/launch-ownership-guest --arch aarch64 --kernel /absolute/kernel --state-dir /absolute/empty-directory
```

Select `x86_64` for the other target. Cross-compiler/sysroot selection follows
the hardware qualification harness. The retained comparison module is copied as
`launch_comparison_test.v` into an isolated copy of `pkgcore`; build it with
`-d track_heap` and the host flags above. Add `-d plan_baseline` only when
compiling the unchanged previous implementation.

- [matched complete plans and refusal retention](results/2026-10-16/launch-ownership-baseline.txt)
- [exact V comparison fixture](results/2026-10-16/launch-ownership-comparison.v)
- [host results](results/2026-10-16/launch-ownership-host.json), [summary](results/2026-10-16/launch-ownership-host.txt)
- [core assertions](results/2026-10-16/launch-ownership-core.txt)
- [tracked allocations](results/2026-10-16/launch-ownership-memory.txt)
- [sanitizers](results/2026-10-16/launch-ownership-asan.txt)
- [signed CLI lifecycle](results/2026-10-16/launch-ownership-cli.txt)
- [source/toolchain/artifact pins](results/2026-10-16/launch-ownership-toolchain.json)
- [AArch64 receipt](results/2026-10-16/launch-ownership-aarch64.json), [report](results/2026-10-16/launch-ownership-aarch64.txt), [serial](results/2026-10-16/launch-ownership-aarch64.serial.txt), [QMP](results/2026-10-16/launch-ownership-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-16/launch-ownership-x86_64.json), [report](results/2026-10-16/launch-ownership-x86_64.txt), [serial](results/2026-10-16/launch-ownership-x86_64.serial.txt), [QMP](results/2026-10-16/launch-ownership-x86_64.qmp.txt)

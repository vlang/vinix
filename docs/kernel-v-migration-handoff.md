# Kernel C to V: next-session handoff

Updated 2026-10-06 in `/Users/alex/code/vinix` on macOS ARM64/zsh.
The language snapshot below pins committed source
`90990bb7e4f4b5363f91e551f24df5ef49b0c9fb`. Re-read HEAD, `AGENTS.md` and
working-tree status: other sessions actively edit and commit this checkout.

## Current request

Continue migrating first-party C to V. The latest user instruction is
**“only 3rd party libs can stay in C.”** This supersedes the previous exception
for independent C fixtures and small native C bindings. Preserve ABI, atomic
orders, allocation/lifetime behavior, exact independent assertions and
immutable original Git revisions. Do not move implementation bodies into
headers, strings or build generators, and do not mark own C as vendored.
Generated C remains a build artifact; instruction-only architecture assembly
expresses native entry points that V cannot represent. Native declaration
headers should be generated from maintained V ABI/configuration metadata.

Work in stages, run relevant host checks, build both kernel architectures,
verify the appropriate complete QEMU guests and commit each completed stage
using only its reviewed paths. No push is requested. Pending changes and old
binaries are not evidence that a future stage passed.

## Completed work

The preceding requested implementation batch completed **at least 10,191
original C implementation lines** in 15 scopes. Its stage arithmetic, commits,
full tests, measured residuals and limitations remain in
[kernel-v-migration.md](kernel-v-migration.md). The current native-boundary
continuation adds **2,406 original production C lines**, **453 original fixture
lines** and **111 desktop header lines**, counted separately.

| Completed continuation | Commit |
| --- | --- |
| Tracker native frame capture | `129c1f39` |
| Security native boundaries | `49d01613` |
| SRCU bindings | `09de736d` |
| Console/benchmark variadic entries | `987dbcc6` |
| Common LinuxKPI bindings | `d91f43b1` |
| LinuxKPI runtime/logger bindings | `aa1d5bb8` |
| Desktop backtraces/presenter and existing execinfo fixture | `a2fa1fac` |
| Apple reporter | `4d18ab71` |
| Venus availability probe | `a9f22eed` |
| Dota early client | `a55c5147` |
| ARM init syscall/restorer boundary | `5dc7b03d` |
| AGX native adapter and existing fixture | `06fd0680` |
| Task/wait bindings | `2103d3d8` |
| Workqueue bindings | `a774ab2a` |
| Dota low mappings, existing parser/probe fixtures | `5115a9e7` |
| Steam i386/x86_64 robust-list preloads | `032eaa2d` |
| QEMU VNC window client | `45f28820` |

`kernel/c/*.c` now has **zero non-fixture maintained files**. Public header
algorithms and independent fixtures still remain C. The instruction applies
throughout the repository, including support utilities, tests and SDK headers.
The current committed census contains 237 non-vendored `.c` paths / 54,233 lines
(19 kernel fixtures / 5,448 lines, 210 test paths / 47,713 lines, two Apple
fixtures / 168 lines, five support files / 899 lines and hello / five lines).
This census is a scope guide, not a translation tally; genuine retained musl
evidence requires provenance classification and headers/embedded sources are
additional work. Recount before selecting the next stage.

The immutable archive (`7ee28d8e`) pins 145 records by exact commit/path/blob,
SHA256, bytes and mode. It recovers 108 frozen first-party/generated C snapshots
(75,192 lines), two frozen shell builders and one embedded init outside the
checkout. It earns **zero translation credit**. All records, 510 campaign
integrity assertions and three byte-identical recomputations passed. Genuine
patched musl evidence remains preserved. Use
`tests/alloc-bench/materialize-evidence.py`; never restore frozen benchmark C
as maintained implementation.

## In progress at this handoff

The shared checkout has uncommitted coordinated work. Re-read diffs before
continuing and do not commit others' paths:

- Four native LinuxKPI fixtures (cache 242, i915 138, PCI 308, runtime 430) are V
  in `kernel/linuxkpi/*fixture`; original C deletions and exact integration are
  pending. Full host sanitizers/golden/upstream/header checks passed, both
  architecture builds passed and 700 source hashes were frozen. The first
  native guest failed the generic early compatibility selftest, so the stage
  is **not committed/validated** yet. Diagnose its exact unchanged condition;
  do not weaken assertions. Source/proof files: `fixture-native-source.json`,
  `fixture-native-kernels.json`, `fixture-native-qemu.log`, `fng/serial.log`.
- Task/time/timer 353, sync 160, wound/wait 321 and I/O 460 native fixtures are
  being prepared in `.pending` V paths. Keep their original integration until
  the preceding stage succeeds. Preserve every original loop/deadline, native
  callback address and join/unlink before stack expiry.
- LinuxKPI first-party overlay header algorithms are moving to
  `headercore/primitive.v`, with surgical foreign-field metadata additions in
  common/wait modules. Full host and standalone header checks pass; final
  isolated builds/native guest and own-path commit remain required. Preserve
  generic exchange/CAS widths including 128-bit, and native long-long spelling.
- Android runtime 610 is in native V with actual pthread types and generated
  readonly 128-thunk data. Frozen original-C/V host and x86 native comparisons
  passed; final ARM repeat after readonly-table correction is pending. Its
  genuine pinned musl statistics provider is mandatory; a stale staging loader
  lacked that export and failed the original C before reaching V.
- Office PE ABI 123, Xinput launcher 73, Wine host boundary 22 and hello 5 are next
  support scopes. Main-kernel native/header algorithms and generated declaration
  headers are still outstanding, as are remaining independent test sources.

## Validation and evidence

Current local cache:
`/Users/alex/.cache/vinix-c-to-v/firstparty-only-20261006-011023/`.
The older 10,191-line batch cache is
`/Users/alex/.cache/vinix-c-to-v/batch-next-10k-20261005-220015/`.
These are machine-local caches; the committed migration document is durable.

Completed kernel-native stages passed sanitizer fixtures, both builds and
appropriate guests. Full LinuxKPI diagnostics passed four-CPU qemu64/TCG,
LINUXKPI=1, PROD=false, -O2, with exact free-page baselines. Final task/wait/WQ
x86 ELF SHA256:
`3b6164b1853caa8adac1aceca0a32d32a22b6023f83fbf2cf43c4104d9783399`;
ARM:
`86860faa0b4fa595eb53b5ce1d551e0d5c8bd323ae6b593631e9a30c5a20c179`.
The first full run failed an original timer callback watchdog/count condition;
the closest untouched C-boundary kernel passed and the identical new frozen
kernel passed on repeat. Preserve the failed attempt and both comparison logs.
Host contention is a plausible explanation, not established causation. No
assertion or fixture deadline changed.

Desktop native backtraces, full links and `idle,apps,drag` passed on both
architectures. The presenter passed 67 sanitizer failure/lifetime cases and 32
zero-resource lifecycles. ARM init passed all three boot policies/all six
markers; one earlier run could not save evidence after host ENOSPC. Steam
passed actual 32/64-bit layouts, 16 × 1,000 concurrent table cycles and four
translated original-C/V variants. Dota passed actual patched-translator C/C,
C/V and V/V, all 50 original probe conditions and 24 parser cases × 257 chunk
boundaries. VNC passed 34 differential outcomes, both native mocks and actual
ARM X11 link. New lifetimes received independent review.

The existing allocation-site check still rejects the same 158 sites on the
unchanged baseline (354 ARM, 293 x86, 414 distinct); keep the allowlist intact.
Earlier repeated ops/churn found identical warm heap deltas, but unchanged VFS
retention remains: mkdir 208 B/op and rename residuals. Do not claim universal
flat memory. See the migration record for raw measurements and exact inputs.
Physical Apple protocols/graphics, Darwin tracing, XNU execution and actual VMX
under TCG remain unverified. Native QEMU mocks do not establish hardware results.
Completed disposable guest image inputs may be removed after recording hashes;
serial logs, ELFs, metadata and removal manifests remain.

## Build and test setup

The verified tools remain `/Users/alex/code/v/v` (**V 0.5.2 e690943**), Apple
Clang 21.0.0 and `/opt/homebrew/bin/ld.lld` (**LLD 23.1.0**). The genuine x86
GCC sampler uses GCC 14.2.0 from
`/opt/homebrew/Cellar/musl-cross/0.9.11/libexec/bin/x86_64-linux-musl-gcc`.
Respect `build-support/find-v.sh` and recheck versions before a new stage.
Use explicit `make -C <worktree>/kernel`, not a root userland build.

Current isolated source trees include `worktree-arm` and `worktree-x86`
inside the first-party cache above. Other worktrees elsewhere in
`/Users/alex/.cache/vinix-c-to-v/` contain earlier bases and staged copies.
Prefer fresh worktrees from current HEAD. Reuse or symlink untracked
freestanding headers, architecture-specific cc-runtime dependencies,
`c/{lwip,uacpi,flanterm}` and `c/nanoprintf.h`. Build each architecture's
runtime archive separately. `kernel/get-deps` resets/cleans dependencies;
do not run it through shared dependency symlinks.

Set `port_arm` and `port_x86` to separate prepared worktrees, and guest
variables to unused state directories. Build/test shapes remain:

```sh
V_C_ERROR_BUG_REPORT_DISABLED=1 make -C "$port_arm/kernel" -j4 \
  ARCH=aarch64 CC=clang V=/Users/alex/code/v/v LIMINE_MP=1 STACK_GUARD_TEST=0 \
  LD_AARCH64=/opt/homebrew/bin/ld.lld

V_C_ERROR_BUG_REPORT_DISABLED=1 make -C "$port_x86/kernel" -j4 \
  ARCH=x86_64 LINUXKPI=0 CC=clang V=/Users/alex/code/v/v \
  LIMINE_MP=1 STACK_GUARD_TEST=0 LD_X86_64=/opt/homebrew/bin/ld.lld

python3 tests/hypervisor/run-vm.py --arch x86_64 \
  --kernel-dir "$port_x86/kernel" --state-dir "$port_x86_guest" --timeout 3600

V_C_ERROR_BUG_REPORT_DISABLED=1 make -C "$port_x86/kernel" -j4 \
  ARCH=x86_64 LINUXKPI=1 PROD=false CC=clang V=/Users/alex/code/v/v \
  LIMINE_MP=1 STACK_GUARD_TEST=0 LD_X86_64=/opt/homebrew/bin/ld.lld \
  LINUXKPI_SOURCE_DIR=/Users/alex/code/vinix/third_party/linux-i915/linux-6.6.157

tests/linuxkpi/run.sh
python3 tests/linuxkpi/run_vm.py --kernel "$port_x86/kernel/bin/vinix" \
  --state-dir "$port_guest" --cpu qemu64 --timeout 3600
python3 tests/hypervisor/run-vm.py --arch aarch64 \
  --kernel-dir "$port_arm/kernel" --state-dir "$port_arm_guest" --timeout 3600

python3 tests/init-policy/run.py
python3 tests/init-policy/run-vm.py --kernel-dir "$port_arm/kernel" \
  --state-dir "$port_init_guest" --timeout 600
```

Run host tests from the checkout containing the new source. Test default
x86 boot before its `LINUXKPI=1` rebuild replaces the binary. `PROD=false`
is required for LinuxKPI diagnostic markers; LinuxKPI remains opt-in and
x86-only. The full harness requires every marker, not merely startup or
userspace. Guest directories must be new; `--limine-dir` can reuse a verified
bootloader cache. Build/guest runs can take minutes or tens of minutes under
host load; inspect progress and failure logs before calling them hung.

For the sampler, follow [tests/alloc-bench/README.md](../tests/alloc-bench/README.md)
exactly: settle the kernel configuration, generate the shared V sampler,
compile that artifact with genuine GCC and the prescribed flags, replace the
sampler object and relink without allowing make to rebuild it with Clang.
Never compare benchmark captures from different workload/compiler policies.

## Porting constraints learned in these batches

- Kernel V uses `-gc none -manualfree`. Preserve explicit ownership and inspect
  generated C and `nm -u` for implicit allocator imports. Fixed arrays use
  `[a, b]!`; avoid interpolation, heap literals, escaping locals and dynamic
  array/interface allocations on repeated paths. Follow `AGENTS.md` for
  measured leak checks and lifetime review.
- Under `-os vinix`, V `int` is 64-bit. Use `i32`/`u32` for C integer ABIs,
  explicit pointer/word widths and the original atomic memory orders.
- Foreign globals need `@[c_extern] __global C.name`. Unprefixed names can
  create separate storage. Globals can collide with locals across modules:
  `memory.slabs` collided with a cache parameter, and workqueue's local
  `queues` collided with `sysvmsg.queues`. Inspect generated declarations.
- Exported V functions have native and C-wrapper addresses. Preserve the
  actual registered C callback address through narrow accessors when Linux
  compares work/timer/wait functions or native APIs unregister callbacks.
- Use explicit `voidptr` comparisons for pointer identity where V can emit
  structural comparisons, especially nested workqueue conditions.
- Preserve public native layouts; generate declaration headers from maintained V
  ABI/configuration metadata. `VINIX_V_RUNTIME` guards prevent generated
  opaque-signature conflicts; escape reserved fields as `C.@type`/`C.@read`.
  Check private pool sizes/alignment and opaque storage with static assertions.
- Unmodified upstream Linux macros/inlines may be called by native V bindings.
  First-party header algorithms belong in V; do not move complete C bodies
  into headers, strings or adapters. Keep broad upstream Linux headers out of the main generated V blob.
- Published stack waiter/run/cancel/barrier records must remain stack values
  and be detached under the same lock before their frames disappear. Saving
  callbacks/task identities before wake or invocation avoids later reads of
  self-free work/timer/wait records. Inspect outpointer/field-address arguments:
  passing `&run.generation` originally moved the whole run record to the heap.
- Preserve `jiffies`/`jiffies_64` as one word, including Darwin's assembler
  alias. Preserve absolute timeout capture, locked finish-wait guarantees,
  tick widths and exact timer/callback retirement before freeing owners.
- The V compiler lacks ARM's `%w` operand modifier. Use the existing native
  32-bit MMIO binding; inspect optimized counters, volatile stores and barriers.
- Extend production-core fixture generators rather than changing independent
  expected results. Host aliases for `strchr`, `strpbrk`, `strsep` avoid libc/
  sanitizer interposition; freestanding memory exports likewise need host aliases.
- Native variadic register access, restorers and raw syscalls use instruction-only
  assembly when V cannot express the ABI. V owns parsing/output/policy. Keep
  callback identity and synchronous stack buffer borrowing intact across these boundaries.
- Empty condition-call loop bodies were dropped by this V compiler; explicit
  `continue` preserves EINTR/reaping loops. Names such as `print` can trigger
  built-in conversion behavior; inspect generated calls and allocator symbols.
- Unsafe blocks do not replace width/overflow/volatile/assembly checks.
  Chained macro assignments and `~false` produced incorrect early translations.
- Copy sources into worktrees with fresh modification times: stale timestamps
  can retain an old `blob.c.o`. Do not overwrite corrected ports with old scratch
  translation scripts. Never restore generated C as maintained source.

## Git and language statistics

Inspect `git diff HEAD -- <owned paths>` before every exact-path commit. Plain
`git diff` can be empty when another session staged changes. Avoid broad
staging, checkout-wide cleanup/reset, or unrelated desktop/build commits.

Linguist 7.27.0 at committed source
`90990bb7e4f4b5363f91e551f24df5ef49b0c9fb` reports **V 49.24%, C 13.10%**,
430 C files, 400 Python files and 281 shell files. The inventory records every
committed blob size and pinned reproduction command. All 2,180 classified blobs
were verified against Git; no Verilog or vendored trees appear. The archive
changes maintained source inventory but contributes no translation credit.
`.gitattributes` remains unchanged, with own fixtures/headers counted honestly.

Local Linguist runs in Lima VM `vlin`, using
`/Users/alex/.cache/vinix-linguist/repository.git` with alternates to this
checkout. Pass explicit `--rev <full-committed-source-SHA>`. The checked helper
in the current first-party cache is `refresh-linguist-safe.py`. It verifies
all listed bytes, source hash, reproduction command and percentages. Regenerate
from a committed source revision after further ports; do not infer percentages
from line counts or count archived evidence as translated work.

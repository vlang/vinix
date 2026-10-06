# Kernel C to V: next-session handoff

Updated 2026-10-06 in `/Users/alex/code/vinix` on macOS ARM64/zsh.
The language snapshot below pins committed source
`bbf1e243e21ab58b46a4853c0e88383ff45b290a`. Re-read HEAD, `AGENTS.md` and
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
continuation adds **3,251 original production C lines**, **9,655 original fixture
lines** and **250 header implementation lines** (111 desktop, 139 kernel),
counted separately. Seventeen stack-pointer/syscall/variadic boundary lines use instruction-only
assembly and receive no V algorithm credit.

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
| Android native runtime | `1d6730ac` |
| Xinput native launcher / Wine host boundary | `bea41f8e` |
| Office PE ABI | `7df94498` |
| Cache/i915/PCI/runtime native fixtures (1,118 lines) | `3b3b131d` |
| Seven task/time/sync/I/O/sequence fixtures (1,582 lines) | `cbb528e0` |
| Kernel native headers / ARM PCI fixture (37 / 57 lines) | `6b3769f2` |
| IPv6 / common serial / smoke fixtures (201 lines) | `7dfa57c5` |
| LinuxKPI typed/generic header operations (100 lines) | `9f47270e` |
| Hello and greeting builders (17 production lines) | `47be3479` |
| Android ATL configuration fixture (71) | `5a8e6928` |
| ACPI native fixture (206) and builtin exclusion | `18c49a10` |
| Hypervisor/ARM PCI native fixtures (77 V lines; 9 assembly) | `d5591540` |
| Hypervisor ABI entry (5 V lines; six native constraints retained) | `5daec594` |
| Apple boot/converter fixtures (168) | `c93d331c` |
| Duplicate Apple helpers retired (33; zero new V credit) | `6c351501` |
| SMC independent fixture (536) | `9e09a18a` |
| Tracker independent policy fixture (72) | `283e8276` |
| Console independent policy fixture (90) | `80ae43a1` |
| Remaining LinuxKPI kernel fixtures (2,687) | `33be42d7` |
| x86 console syscall fixture (57) | `b3fdcb83` |
| Native allocation-tracker guest fixture (58) | `ac285e42` |
| Random host hooks (29 V; three variadic boundary lines excluded) | `3d667aeb` |
| SMT native guest (39) | `12854d0f` |
| Stack diagnostic fixture (55) | `87d95202` |
| Real protected-frame oracle (57) | `15048510` |
| Seven standalone LinuxKPI fixtures (199) | `f7ccc132` |
| Pointer/preemption runtime header policies (2) | `112e18aa` |
| ANS ext2/platform fixtures (268) | `2a19e1d2` |
| ANS controller/media original fixture scope (815) | `34e728c4` |
| SPI/speaker provider consumer repairs (zero extra credit) | `e29fe952` |
| AGX encoder independent fixture (289) | `083cb12b` |
| Strict syscall diagnostics (46) | `6f506fd8` |
| AGX verifier independent fixture (420) | `bbf1e243` |

`kernel/c/*.c` now has **zero maintained first-party files**, including
fixtures. Public header algorithms and independent host/native fixtures still
remain C. The instruction applies throughout the repository. At the pinned
source, the committed non-vendored `.c` census contains 187 test paths /
45,282 lines, including genuine patched musl evidence. This is a scope guide,
not a translation tally; headers and embedded sources are additional work.
Do not mistake zero kernel C for completion of the repository-wide request.

The immutable archive (`7ee28d8e`) pins 145 records by exact commit/path/blob,
SHA256, bytes and mode. It recovers 108 frozen first-party/generated C snapshots
(75,192 lines), two frozen shell builders and one embedded init outside the
checkout. It earns **zero translation credit**. All records, 510 campaign
integrity assertions and three byte-identical recomputations passed. Genuine
patched musl evidence remains preserved. Use
`tests/alloc-bench/materialize-evidence.py`; never restore frozen benchmark C
as maintained implementation.

## In progress at this handoff

The shared checkout has coordinated uncommitted work. Re-read diffs and each
stage's input hashes before continuing; completed commits above are separate:

- Pointer/preemption runtime policies and the seven standalone programs are
  committed. The broader native constexpr/type family is being represented in
  checked compiler metadata with zero new V algorithm credit. Preserve all
  4,099 assertions, single-evaluation/ICE behavior, rejection domains and
  arbitrary native integer widths. Both fresh debug default kernels booted;
  the complete compatibility guest is in progress on immutable ELF
  `8e5a969a929f38418b9d7f65ec21050bc7e701dee1d8e2f29040b7a9265fe15f`.
- LinuxKPI host fixtures and the pthread/TLS scheduler model passed a complete
  private true-V ARM sanitizer workload and all original boundary cases.
  Maintained integration, actual x86 host ABI checks and both native SDK/model
  guests are in progress. Pending work is not credited. The frozen compiler
  ignores V `thread_local` under `-os vinix`; native TLS storage retains real
  pthread isolation. Preserve all original assertions, ownership and deadlines.
- Speaker and QEMU-core independent fixtures are being ported in bounded
  stages. ANS and both independent AGX fixtures are committed; native model
  success does not establish physical hardware operation.
- Further first-party kernel/SDK headers, native guest programs and hardware
  protocol fixtures remain to port. Keep immutable original Git references for
  comparison. Declaration-only native ABI headers do not justify retaining
  first-party C implementation bodies.

## Validation and evidence

Current local cache:
`/Users/alex/.cache/vinix-c-to-v/firstparty-only-20261006-011023/`.
The older 10,191-line batch cache is
`/Users/alex/.cache/vinix-c-to-v/batch-next-10k-20261005-220015/`.
These are machine-local caches; the committed migration document is durable.

The latest independent AGX encoder/verifier scopes passed original-C/V
sanitizers on actual ARM/x86 hosts and all eight native model guests. All
73 checks, 16 branch goldens and the verifier's sole explicit calloc/free
pair remain intact. Strict syscall diagnostics passed original-C/V guests
on both architectures with PROD=false and strict SMAP/PAN; the failed status
copy remains retryable. Debug ELF hashes: ARM
`a10010c78606e25d469728452269c1aa432f553017a104d2cf93e24a2ab53b9a`,
x86 `a741183dee9ec04a7879a4ab328a506b927e0d61faa850d1b0cdbce5cc95bb78`.
The protected stack-frame oracle passed real compiler checks on Darwin ARM
and Rosetta x86; it is a host fixture, with no native musl startup claim.
ANS retained all 38 model cases and passed original-C/V sanitizers and both
native guests. Scratch providers omit only eight documented, unexecuted ARM
hardware bindings, with unchanged exercised algorithms and zero physical
hardware/x86-production claims. New lifetime boundaries received peer review.
Local receipts include `agx-{encode,verify}-fixture-validation.json`,
`syscall-diag-validation.json`, `stack-protector-validation.json`,
`ans-{ext2,model}-stage-validation.json` and `header-policy-validation.json`.

The final six kernel fixtures passed the complete four-CPU qemu64 LinuxKPI
guest with exact free-page equality. Tested ELF SHA256:
`4e82332380efae4a53e266b3f97a0ec41ca7efdc42569d17e363bf0e7dd94fd3`.
`fixture-final-source.json` pins base `9f47270e`, 788 source paths and 30
owned changes. Its first V run failed the original worker check; untouched C
passed, then the identical frozen V ELF passed on repeat. The cause remains
unknown. Logs, private diagnostic objects and the failed attempt are retained;
no assertions, deadlines or tracing policy changed. Both architecture builds,
default x86 boot, both ACPI guests and ARM PCI passed.

Tracker/console independent policy fixtures passed ASan/UBSan and both native
guests, including console debug/production variants. The actual ALLOC_TRACK=1
kernels passed original-C/V live-site guests on both architectures; all 16
assertions and 128 pipe-pair closures remain. One ARM image stalled in firmware;
a fresh-image repeat used identical kernel/init bytes and passed. x86 console
original-C/V syscall guests matched all ten checks and worker collection.
Apple boot/converter and SMC original-C/V sanitizer/native model fixtures passed;
physical firmware remains unverified. Hypervisor model cases passed all five
VM executions, but real native guests exercised absent-device behavior only;
nested VT-x is still required to verify actual VMX entry.

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

The corrected first four fixture guest passed after restoring original unsigned
`MKDEV` literal arguments; expected values remain unchanged. The next seven
fixtures and typed/generic headers passed the complete four-CPU guest with
exact free-page equality. Its tested LinuxKPI ELF SHA256 is
`195c83c50c0d295da8e510b8046a946ac071fa73cf6ce9ed2be3f33bad4636cd`.
ARM PCI/full-DAIF ELF is
`638c983715bb1d51a3fe00901a79cb0e4dcf355b7d183545b3c55beacb0c156d`;
default x86 ELF is
`bcfec8fd702ac3697ea3f65bd13c6a04edbf7df00c18b869d42f3f9657b63d9c`.
`fixture-next-source.json` freezes 763 paths from committed source plus exact
owned changes. Another session's uncommitted user-copy paths were excluded;
the earlier accidental mixed snapshot's compilation failure is retained.
The original-C/V IPv6 verdict and class measurements match byte for byte on
both architectures: 500 exchanges, all classes flat, slab delta zero. Both V
PID1/fork/COW/mmap smoke guests passed. Native header and generic atomic/IRQ
oracles passed, including 128-bit operations and original lvalue sequencing.

Android and Xinput/Wine host/strict-native/both-architecture fixtures passed;
actual ARM X11 links passed. Office host and native Win64 export checks passed;
translated Wine executed both SDK PE fixtures, each returning unique success
code 73 after all checks. A skipped fixture returning zero fails. Earlier
stale Android statistics-provider and Wine NLS-layout failures remain evidence;
full Office/APK UI was not rerun.

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

Freeze V and its vlib together: the displayed **V 0.5.2 e690943** version stayed
unchanged while other sessions replaced source/library inputs. The final
fixture stage uses cache `toolchain-v/v`, source
`95136d4de1dabe575e37fc36b5a3e793580c8f72`, binary SHA256
`335214a9c904435eb87e580948a7de76c2b4de03a65f0ee23babaa76981a7373`.
The unconditional POSIX backtrace builtin is explicitly excluded by the kernel;
an unchanged default control reproduced that toolchain failure. Recheck Clang
and `/opt/homebrew/bin/ld.lld`; the frozen native fixture builds use LLVM tools. The genuine x86
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
runtime archive separately with LLVM ar; Darwin ar cannot index ELF runtime
objects correctly. `kernel/get-deps` resets/cleans dependencies;
do not run it through shared dependency symlinks.

Set `port_arm` and `port_x86` to separate prepared worktrees, guest variables
to unused state directories and `port_v` to a verified frozen compiler binary.
Respect `find-v.sh`; pass `VINIX_V_COMPILER="$port_v"` to host generators.
Build/test shapes remain:

```sh
V_C_ERROR_BUG_REPORT_DISABLED=1 make -C "$port_arm/kernel" -j4 \
  ARCH=aarch64 CC=clang AR=/opt/homebrew/opt/llvm/bin/llvm-ar V="$port_v" LIMINE_MP=1 STACK_GUARD_TEST=0 \
  LD_AARCH64=/opt/homebrew/bin/ld.lld

V_C_ERROR_BUG_REPORT_DISABLED=1 make -C "$port_x86/kernel" -j4 \
  ARCH=x86_64 LINUXKPI=0 CC=clang AR=/opt/homebrew/opt/llvm/bin/llvm-ar V="$port_v" \
  LIMINE_MP=1 STACK_GUARD_TEST=0 LD_X86_64=/opt/homebrew/bin/ld.lld

python3 tests/hypervisor/run-vm.py --arch x86_64 \
  --kernel-dir "$port_x86/kernel" --state-dir "$port_x86_guest" --timeout 3600

V_C_ERROR_BUG_REPORT_DISABLED=1 make -C "$port_x86/kernel" -j4 \
  ARCH=x86_64 LINUXKPI=1 PROD=false CC=clang AR=/opt/homebrew/opt/llvm/bin/llvm-ar V="$port_v" \
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
`bbf1e243e21ab58b46a4853c0e88383ff45b290a` reports **V 71.68%, C 6.50%**,
440 C files, 447 Python files and 284 shell files. The inventory records every
committed blob size and pinned reproduction command. All 2,435 classified blobs
were verified against Git; no Verilog or vendored trees appear. The archive
changes maintained source inventory but contributes no translation credit.
`.gitattributes` remains unchanged, with own fixtures/headers counted honestly.
Concurrent commits include a 17,850,662-byte `desktop/font_data.v` blob;
the percentages describe the whole pinned source, not this port batch.

Local Linguist runs in Lima VM `vlin`, using
`/Users/alex/.cache/vinix-linguist/repository.git` with alternates to this
checkout. Pass explicit `--rev <full-committed-source-SHA>`. The checked helper
in the current first-party cache is `refresh-linguist-safe.py`. It verifies
all listed bytes, source hash, reproduction command and percentages. Regenerate
from a committed source revision after further ports; do not infer percentages
from line counts or count archived evidence as translated work.

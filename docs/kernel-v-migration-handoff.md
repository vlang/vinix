# Kernel C to V: next-session handoff

Updated 2026-10-07 in `/Users/alex/code/vinix` on macOS ARM64/zsh.
The language snapshot below pins committed source
`b5245a1330d8ce652b111552d5c0fcbdec64e915`. Re-read HEAD, `AGENTS.md` and
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
continuation adds **3,844 original production C lines**, **17,577 original fixture/benchmark
lines** and **265 header implementation lines** (111 desktop, 146 kernel, eight
Wi-Fi tool lines),
counted separately. Twenty-nine stack-pointer/syscall/variadic/ordering boundary lines use
instruction-only assembly and receive no V algorithm credit.

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
| Speaker transport/thermal fixture (1,234) | `3ab257ae` |
| Raw stat retention guest (88) | `09d3db88` |
| Sampler ownership fixture (72 V; three variadic lines excluded) | `7ebf1a38` |
| Wi-Fi protocol fixture (178) | `afa873f9` |
| Wi-Fi platform fixture (80) | `3baf57e1` |
| Wi-Fi control fixtures (99 V; one variadic line excluded) | `8c9ddf47` |
| Wi-Fi tool native header policies (8) | `46ea29c7` |
| Portable allocation benchmark (419) | `5b37c952` |
| Large-I/O lifetime guest (56) | `bc0b9a77` |
| Network randomness independent oracle (320) | `b39872cf` |
| Memory primitive independent oracle (107) | `42ed5d38` |
| Speculation policy independent oracle (134) | `5ecc81c0` |
| Sparse page-table lifetime independent oracle (193) | `439e6c12` |
| QEMU signal/first-touch/restart independent scopes (241) | `fb74d12a` |
| Native clock-control independent oracle (163) | `7ddfcb65` |
| QEMU interrupted nanosleep independent scope (40) | `60f5c267` |
| SPI keyboard independent fixture (564) | `558dc058` |
| SPI touchpad independent fixture (505) | `775f7f2a` |
| Native x86 poll independent fixture (85) | `003f5861` |
| POSIX timer signal independent fixture (230) | `ad82c434` |
| Display-hotplug independent oracle (147) | `d21ed758` |
| Verified-boot standalone protocol fixture (40) | `8b96b191` |
| QEMU blocked-thread exit/exec independent scope (38) | `22c5d6ee` |
| QEMU pollfd ABI independent scope (22) | `eecdee92` |
| Resource-open lifetime fixture (133) | `b11fb04e` |
| Shared pipe/socket stream fixture (119) | `68c1e163` |
| QEMU epoll independent scope (30) | `b5f1c0f9` |
| QEMU syscall argument independent scope (10) | `3cf43ef1` |
| Socket I/O lifetime fixture (234) | `bebccef1` |
| Fsync error-scope fixture (76) | `5e6795e1` |
| Procfs mount lifetime fixture (242) | `2d9e508f` |
| Native x86 FPU header operations (7) | `56b89d09` |
| Native x86 exception/reaping fixture (97) | `369289a4` |
| Procfs map lookup lifetime fixture (221) | `94143cac` |
| Native listen backlog/word-width fixture (141) | `085f0347` |
| Procfs thread/exec locking fixture (174) | `090b78d8` |
| Directory/procfs retention fixture (131) | `42bcf709` |
| Dumpability/secure-loader fixture (99) | `95234fa2` |
| LinuxKPI native PID 1 fixture (28) | `a754ffc7` |
| Native N64 emulator regression fixture (488) | `b01fdc9f` |
| Native N64 bridge (366; four capture lines excluded) | `320172df` |
| Native MIPS PADDLE cartridge (227; four sync lines excluded) | `41c9ddd6` |
| EXT2 read-ahead fixture (113) | `bb26e71d` |
| Reboot-persistence fixture (90) | `72a92ec8` |
| Sparse EXT2 fixture (185) | `0a7d88fb` |
| Init-policy guest fixture (78) | `8fd0f13a` |
| Init-policy syscall host fixture (178) | `b5245a13` |
| Native kmod descriptor (29 metadata lines, zero credit) | `ad0ba5d0` |
| Canonical callback contracts (zero credit) | `03ad7bb3` |
| Const string/log-record contracts (zero credit) | `e79802e4` |
| Distinct benchmark differential output archive (zero credit) | `944c12e1` |
| Native integer constant-expression metadata (zero credit) | `0fe3679c` |
| Native high-byte string semantics correction (zero credit) | `bc9a5ea4` |

`kernel/c/*.c` now has **zero maintained first-party files**, including
fixtures. Public header algorithms and independent host/native fixtures still
remain C. The instruction applies throughout the repository. At the pinned
source, the committed non-vendored `.c` census contains 152 paths / 38,164
lines: 149 test paths / 37,447 lines and three build-support paths / 717 lines.
All committed identities/sizes/lines are verified using pinned-source Git
attributes with global/system attributes disabled. Genuine patched musl evidence
and first-party PS2 follow-up scopes remain included. This is a scope guide, not a translation tally; native headers and
authored embedded C are additional work.
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

The user's latest instruction is to commit pending code before continuing.
Reviewed scopes were committed separately: retention (`42bcf709`), dumpability
(`95234fa2`), N64 integration (`8d172d26`), LinuxKPI host fixtures (`705ce393`)
and pending QEMU inputs (`909ae53d`). LinuxKPI PID 1 (`a754ffc7`), N64 guest
(`b01fdc9f`), CPU-mask storage (`f4d9ad6d`), EXT2 read-ahead/sparse, reboot
persistence, init-policy guest/host and N64 bridge/homebrew are subsequent completed
stages recorded above.
The host and pending QEMU scopes are explicit checkpoints,
not completed native ports. Re-read diffs and each stage's input hashes before
continuing; preserve the unresolved results below:

- Pointer/preemption runtime policies, standalone programs and the broader native
  integer constexpr/type metadata are committed (`0fe3679c`). All 4,099 original
  assertions remain; metadata receives zero V algorithm credit. Both default
  builds/boots and host checks passed. Initial SRCU failure, exact-instruction
  original-header full PASS and identical V ELF repeat full PASS remain preserved
  in `constexpr-final-validation.json`; no intrinsic deadline or assertion changed.
- LinuxKPI host fixtures and the pthread/TLS scheduler model passed a complete
  private true-V ARM sanitizer workload and all original boundary cases.
  Actual x86 tests and an immutable original-C control both exposed the same
  void-pointer/native-typed callback sanitizer mismatches. Native ARM original
  C/V controls both exposed high-byte strchr and strreplace signedness bugs.
  The high-byte correction is committed as `bc9a5ea4` after both fresh builds/boots
  and the complete four-CPU compatibility guest. Canonical native callback
  (`03ad7bb3`) and const string/log-record contracts (`e79802e4`) are committed
  separately with zero algorithm credit; actual x86 original-C sanitizers now
  pass without those function diagnostics.
  The fixed native ARM V workload passes all 26 groups and seven child boundary
  modes; its original-C control passed too. Both original-C and V native x86 workloads
  failed with the same generic
  child verdict under two CPUs; the original-C run took about 38 minutes.
  The complete V workload passes halt-on-error ASan/UBSan on both actual host
  ABIs, as does the immutable x86 C control. The final native ARM C control and
  identical V repeat pass all 26 groups and seven boundary modes; the first
  final V image hit the unchanged bound-CPU routing assertion. That failure's
  cause remains unknown and its evidence is preserved. The original four-CPU
  x86 `max`/TCG control expired at its unchanged 3,600-second allowance with no
  fixture verdict. A correctly labelled per-CPU QMP snapshot shows kernel TLB
  polling; interrupt-disabled polling alone does not establish deadlock.
  The fresh original-C `qemu64` control failed with child wait status nine
  (SIGKILL); its V pair failed the original bound-CPU routing assertion. Both
  causes remain unknown and their evidence is preserved. A separate failure-only
  diagnostic also ended with SIGKILL before printing routing operands. Its cause
  remains unknown; it retained exact assertions and is not the validation ELF.
  Both comparisons retain four CPUs, exact workloads and 3,600-second budgets,
  recording CPU/kernel configuration changes without claiming earlier failures
  resolved. Both fresh default architecture builds/boots and the opt-in build
  pass for the composed 23-path contract stage. Its complete guest initially
  failed the unchanged I/O timeout/early/signal assertion. The identical ELF
  repeat and matching old-ABI control both then passed all 38 required groups,
  16 exact free-page baselines and 25 no-pages-retained markers. The first
  failure's cause remains unknown; all evidence is preserved. The broader host
  fixture stage still receives no credit pending native x86 completion. The frozen compiler
  ignores V `thread_local` under `-os vinix`; native TLS storage retains real
  pthread isolation. Preserve all original assertions, ownership and deadlines.
- Speaker, ANS, both independent AGX and all three Wi-Fi fixture scopes are
  committed. The Wi-Fi const callback ABI fix (`e89f3526`) passed both fresh
  builds/boots and receives zero credit. QEMU-core partial fixture work retains
  all original checks and receives no credit yet. ARM original-C/V full feature
  and persistence guests passed on normal PROD=true. Original debug controls and
  the normal x86 control expired at their 300/900-second outer limits, without
  weakening assertions. Fresh x86 original-C/V runs use the same documented
  3,600-second outer allowance equally; all intrinsic deadlines/counts/assertions
  remain. The original `max`/TCG x86 control also expired at 3,600 seconds during
  the unchanged 4,000 joined-thread churn. A fresh original-C `qemu64` control
  with the corrected default kernel passed the 270-line scope's memory groups,
  then failed an untouched alarm assertion: nine 50-ms timer firings in a second
  against the required ten. Its V pair has not launched. CPU/kernel changes are
  explicit, the failure is preserved, and no causal resolution is claimed.
  Separate signal (77), first-touch (113) and restart (51) scopes are committed
  as `fb74d12a`: both host sanitizer ABIs, strict complete adapted SDK links and
  six paired native guests pass all 61 original checks with original reap-body
  lifetimes. A separate 40-line interrupted nanosleep scope (`60f5c267`) passed both
  host sanitizer ABIs, strict SDK links and paired native cases with nine original
  checks. Blocked-thread exit/exec (38, `22c5d6ee`) and pollfd ABI (22, `eecdee92`)
  also passed both host/SDK/native comparisons with two/ten original checks.
  Those historical stages account for 341 lines; the later epoll/syscall
  ports bring the credited subset to 381. The broader 270-line stage
  remains pending. Preserve old failure evidence and explicit configurations.
- SPI keyboard/touchpad (564/505), POSIX timer (230), x86 poll (85), hotplug
  policy (147) and verified-boot protocol (40) fixtures are committed with exact
  assertions and native controls. Their detailed receipts are listed below.
- Resource-open (133), shared-stream (119), epoll (30) and syscall argument
  (10) scopes are now committed after complete native comparisons. The QEMU
  completed subset totals 381 original lines; 3,040 original lines plus 18
  integration lines remain. Its base/memory (270) and futex (18) `.pending`
  inputs are committed as `909ae53d` with zero completed credit and are not
  selected by the normal runner. Preserve their original controls and the
  stale historical futex diagnostic tags documented in `tests/qemu-core/README.md`.
- The N64 integration commit initially added first-party C in the core bridge,
  MIPS homebrew and native guest fixture. The guest is now V (`b01fdc9f`);
  bridge (`320172df`) and homebrew (`41c9ddd6`) are subsequently V too.
  Their original native capture/sync lines use instruction-only assembly with
  zero V credit; this provides no third-party exemption for first-party source.
  The original core/frontend/homebrew builds, native guest,
  73 catalog/pinning assertions and desktop input/frame checks passed; those
  tests do not establish a C-to-V port or a fresh compositor build.
- Further first-party kernel/SDK headers, native guest programs and hardware
  protocol fixtures remain to port. Keep immutable original Git references for
  comparison. Declaration-only native ABI headers do not justify retaining
  first-party C implementation bodies.

## Validation and evidence

An earlier completed fixture update adds 2,223 original lines: resource-open,
shared streams, QEMU epoll/syscall arguments, socket I/O, fsync scope, procfs
mounts/maps/thread locking, x86 exceptions, listen backlog, directory retention
and dumpability, plus the separate LinuxKPI PID 1 and N64 guest. Their immutable
original controls, strict SDK links, full native comparisons and peer lifetime
reviews are recorded in the migration document.
Fsync native NBD coverage is ARM-only; the exception fixture is x86-only.
Measured resource/socket/map/retention classes remain exactly flat. Procfs mount
controls preserve their original 16 KiB tolerance, with x86 V pages decreasing
1364→1348 rather than requiring identical absolute C/V baselines.

The seven-line native FPU header port (`56b89d09`) passed the actual x86
instruction sanitizer fixture, both fresh default builds/boots and full original
C/V four-CPU `qemu64` guests. Each guest requires all 41 markers present at that
stage and 18 exact free-byte/heap equalities; later CPU masks add a 42nd marker.
Receipt: `fpu-stage-validation.json`. Frozen source is `99162a39`; original/V
opt-in ELF hashes are
`050a6a757c7205758fbb076bd009aaacd1814d9a663180716b5d24942d5a50ba` /
`6f3242dfa8d4d20eda39a582c21f5561e4310124e423686a293344431f6e97a7`.
The overflow/spin oracle declaration repairs and host-only processor include
boundary (`47db8e1c`, `8ca75d10`, `df855887`) add no port credit.

The committed CPU-mask feature (`2a5abc36`) passed fresh GNU99/GNU11 sanitizer
runs (15,810,213 assertions each), opt-in/default x86 and default ARM builds,
both complete normal/SSE guests with 42 markers and 19 exact memory equalities,
and default architecture PID 1 boots. Receipt:
`cpu-mask-oct07-final-validation.json`. Its authored embedded C oracle remains
first-party follow-up work; the feature receives zero migration credit.
The missing historical `/tmp` receipt is explicitly unverified, and
its broader draft claims are preserved separately rather than repeated.

The LinuxKPI host checkpoint (`705ce393`) retains zero completion credit for
8,929 original lines despite complete actual ARM/x86 host sanitizer passes and
ARM native controls. Keep its unresolved native x86 failures and exact deadlines;
`tests/linuxkpi/host-fixture-validation.json` pins every input and retained result.
Fresh matched default-kernel (`a5ae7a96`) x86 controls retain all 26 groups,
seven boundary modes, four `qemu64`/TCG CPUs, 1,024 MiB and the original
3,600-second allowance. Original C fails the first bound-CPU expression with
SIGABRT after 1,100.94 seconds; V receives SIGKILL after 907.04 seconds. The
reversed historical pair remains recorded. A cache-only original-C failure-print
diagnostic also receives SIGKILL after 437.62 seconds before printing operands;
its timing changes are diagnostic only. Causes remain unknown. No internal
900-second supervisor watchdog was found; sampled zero OOM counters do not
establish the kill cause. Preserve `host-native-default-pair-20261007/paired-validation.json`
and `host-native-default-pair-20261007/original-C-failure-diagnostic/native-run/validation.json`.

A cache-only debugger run of the exact canonical original-C x86 ELF on the
same default `a5ae7a96…` kernel ended after 661.61 seconds with SIGKILL.
Four complete failure events establish an OOM kill for this run: the
page-fault recovery stack called `oom_kill`, requested signal 9 for PID
34932, delivered it to TID 34932 and reached fatal process exit. The accepted
OOM counter advanced from zero to one; the process had infinite CPU limits,
no CPU-limit kill, seccomp mode or parent-death signal. All original groups,
seven boundary modes, assertions/counts/ownership and the 3,600-second maximum
were selected unchanged. Debugger pauses make this diagnostic-only, with zero
credit for the pending 8,929 lines; earlier C/V SIGKILL and bound-CPU failures
retain their unknown causes. Exact events, raw frames, debugger errors and
verified boot inputs are in `host-native-default-pair-20261007/kill9-provenance`
(`validation.json` SHA256
`7be4df826c6de9eefb97076d7108d0350d1475404aa755642698725553a6dafd`).

The OOM trace does not establish why memory was exhausted. Victim accounting
was 32.75390625 MiB with 204 live threads and 7.203125 MiB free physical pages;
heap/slab ownership, retired-thread backlog and a time series were not captured.
The actual saved fault frame covered only its first 40 bytes, excluding the
faulting user PC. Continue with reviewed read-only baseline/failure allocation
and reaper measurements on the immutable kernel and original workload, keeping
assertions, limits and RAM fixed. Do not substitute stale saved scheduler PCs,
ASan runs with leak detection disabled, source inspection or this diagnostic
for qualified original-C/V native completion.

The QEMU pending checkpoint (`909ae53d`) likewise retains zero credit for 270
base/memory and 18 futex lines until complete native comparisons and integration.

CPU-mask storage (`f4d9ad6d`) retires the first-party 48-line data wrapper
and 23-line host declaration wrapper, with zero algorithm credit. V owns nine
literal permanent objects; native qualifier metadata emits only a typedef and
width assertion. Original-C/V GNU99/GNU11 host comparisons each pass 15,810,213
assertions/17 cold processes. Actual native object payloads, readonly bytes,
required alignment and section flags match; mutable section ordering/padding
0xac versus 0xa8 differs, with no contiguous-layout identity claim. Both kernel
architectures and enabled/default x86 builds pass, as do the full normal
42-marker/19-equality guest and both default boots. No new V-storage SSE run
is claimed. Receipt: `cpu-storage-oct07-final-validation.json`. Embedded C
oracle/fixture and native declaration headers still need migration.

The PID 1 fixture (`a754ffc7`, 28) passed strict freestanding/LLVM/GCC musl
links, independent generated-code/optimized-instruction lifetime review,
complete original-C/V 42-marker guests with 19 exact memory equalities and
both default boots. Its immutable original is `2a5abc36:tests/linuxkpi/guest_init.c`;
the C control's executable sections were independently reproduced byte-for-byte.
Receipt: `linuxkpi-init-stage-validation.json`. It preserves real userspace
interrupt opportunities and adds no host syscall sanitizer, ARM execution or
new kernel-build claim. Its ELF entry uses instruction-only stack alignment;
no original V algorithm credit is assigned to that added boundary.

The N64 guest fixture (`b01fdc9f`, 488) passed strict ARM/x86 SDK links,
ARM original-C/V/default-runner controls, all 45 failure guards and all feature
verdicts. Nine metrics and three 160×120 RGB frames match byte-for-byte;
surface mapping, pipe/child ownership, SRAM, instruction-budget recovery and
original deadlines remain. The initial prefix-length failure is preserved;
the corrected port uses the original 14-byte prefix. Receipt:
`n64-v-fixture-stage/validation.json`. x86 emulator execution, host sanitizers
and a new kernel build are not claimed. The bridge (`320172df`, 366 V/four
native capture lines) and MIPS homebrew (`41c9ddd6`, 227 V/four sync lines) are
now separately qualified and committed. The bridge passes strict ARM/x86 ABI
builds, Darwin C/V ASan/UBSan, live setjmp/longjmp, mixed native variadic classes
and final full ARM feature/boundary/desktop controls against identical upstream
inputs including `93b3c3b6`. The cartridge passes the actual strict MIPS III/o32
backend, all eight repeated inline volatile polls, initialized native bytes,
no linked imports and final ARM C/V full feature comparison. All nine metrics
and three exported frames match. Host complete 296,960-byte save files/logs
match too; host sanitizers cover bridge/fixture, not cartridge/upstream, with
leak detection disabled. The first cartridge assembly-MMIO-call timing mismatch
is retained; direct volatile V views pass the exact comparison. Frozen kernels
are reused, physical N64 operation and native x86 emulator execution remain
unclaimed. Receipts are `n64-v-bridge-stage/native-comparison.json` and
`n64-v-homebrew-stage/native-comparison.json`. Concurrent PS2 first-party C
remains follow-up work.

EXT2 read-ahead (`bb26e71d`, 113) and sparse (`0a7d88fb`, 185) pass strict SDK,
original-C/V native pairs on both architectures, maintained ARM runners,
unchanged allocation bounds and all offline filesystem checks. Read-ahead
retains 400 cold/discard cycles; sparse retains 500 measured cycles, the
16-class bank, six-second settling, private/shared mapping/truncation behavior
and six power-cut phases for both filesystem block sizes. Thirty sparse
power-cut images pass e2fsck. Reboot (`72a92ec8`, 90) passes untouched ARM C/V;
x86's untouched C serial gate fails and a separately pinned one-literal
`/dev/com1` C adaptation passes alongside V, with no extra credit. Init guest
(`8fd0f13a`, 78) passes all three original-C/V ARM policies and all 30 predicates;
production policy source/object/ELF match. x86 SDK builds pass without claiming
x86 raw ARM policy execution. The initial overlong QMP path is preserved.
Receipts: `pagecache-fixture/validation.json`,
`ext2-sparse-fixture/validation.json`,
`reboot-persistence-fixture/final-validation.json` and
`init-policy-guest-fixture/final-validation.json`. Kernel sources are unchanged
since the CPU-storage production builds; these fixture stages reuse recorded
kernels and add no fresh kernel or host syscall sanitizer claim.

Init-policy host (`b5245a13`, 178) preserves all 72 ordered assertions and
passes original-C/V normal/echo variants on actual ARM/x86 host executables
under ASan/UBSan. Strict native ARM LLVM/genuine x86 musl GCC objects and all
eight static SDK links pass. Four direct live native setjmp frames retain
returns_twice/longjmp, fixed trace/output banks, native delay/action layouts,
volatile 32-bit foreign controls and actual callback addresses. Prior three
ARM policy production sources/objects/ABI objects/whole ELFs are independently
rebuilt byte-identical with the frozen profile. Initial different-compiler
metadata and supplemental IR sysroot diagnostics remain recorded. No new
QEMU/kernel run or Darwin leak detector claim is made. Receipt:
`init-policy-host-fixture/final-validation.json`.

The portable benchmark (`5b37c952`) passed all 272 original-C/V host sanitizer
cases, four native musl guests and genuine guest GCC 14.2.0 compilation through
its maintained Vinix runner. All six workloads, failure cleanup and checksum
453 remain; permanent fixed table initialization replaces an uncalled dynamic
initializer. Its retained earlier failure and help-only exact instruction proof
are in `alloc-bench-validation.json`. No new paired timing ratio is claimed.
The Wi-Fi scopes retain all protocol/platform/control checks; original-C/V host
sanitizers and native guests passed. Only 357 of 358 removed fixture lines earn
V credit; one variadic extraction line is native assembly. Eight tool header
helpers passed both host ABIs and all four native C/V boundary guests. Native
models do not establish physical hardware operation.

The large-I/O guest (`bc0b9a77`) passed all 44 original-C/V host fault cases
and four native guests, preserving all 17 original checks, 300 rounds and
seven-second settling. ARM pages stayed 46→46; x86 stayed 132→132 with exact
C/V measurement/verdict parity. Its 240-second outer allowance is unchanged.
`big-io-validation.json` records no allocator imports and peer lifetime review;
the separate forced-vmap configuration was not rerun.

Three more independent oracles retire 561 original C lines: network randomness
(`b39872cf`, 320), memory primitives (`42ed5d38`, 107) and speculation policy
(`5ecc81c0`, 134). Both actual host C/V ASan/UBSan comparisons and all 12
complete native C/V guests passed against immutable ALLOC_TRACK kernels.
Network checks retain all 38 predicates, 64 goldens and draw/port/buffer domains;
memory retains 16 checks and 410,739/226,419 ARM/x86 cases; speculation retains
21 assertions and all 6,144 combinations. Fixed local tables and callback
contexts remain synchronous stack borrows; generated code and both SDK objects
have no allocator imports, and production provider instructions match each
C/V pair. The original speculation C source has a GCC signed-comparison
warning under strict flags; the native pair uses Clang with the actual musl
SDK, and the new V fixture additionally compiles strictly with GCC. No
assertion, intrinsic deadline or workload was weakened. These fixture-only
stages add no new kernel build or physical mitigation claim. Receipts are
`net-random-validation.json`, `memory-runtime-validation.json` and
`speculation-policy-validation.json`, with peer lifetime review.

The page-table oracle (`439e6c12`) passed all four strict SDK C/V native
controls with 45 original checks. ARM covers both 16 KiB probe boundaries;
x86 covers all four 4 KiB probes including LA57 at 256 TiB. Jump-buffer
`returns_twice`, native volatile accesses, actual signal-wrapper identity,
pipe/COW/reap/unmap order, four reuse rounds and the original 1 MiB tolerance
remain. It reuses immutable ALLOC_TRACK kernels and adds no host sanitizer or
new kernel-build claim; targeted LA57 success does not resolve other full
`max`/TCG failures. `pagetable-validation.json` records peer lifetime review.

The V kmod descriptor (`ad0ba5d0`) removes 29 metadata-only C lines with zero
algorithm credit. Static generated data preserves every 196-byte record offset,
alignment and native start/stop relocation. Both native Mach-O objects and the
complete linked x86 kext are byte-identical to original C; both strict musl SDK
data/import checks pass. `kmod-info-validation.json` preserves the limits:
no new genuine Darwin GCC compilation or kext execution is claimed.

The clock-control oracle (`7ddfcb65`, 163) passed strict SDK builds, all four
C/V native controls and its maintained ARM runner with the original 300-second
budget. All 53 checks and timex 208-byte/offset-72 constraints remain, along
with timer/FD/child cleanup and 100×50-ms completion polling. The initial x86
setup omitted serial redirection; its framebuffer success and failed harness
attempt are preserved before the fresh shared-serial C/V controls passed.
`clock-control-fixture/validation.json` records the unchanged production host
arithmetic/security tests, peer lifetime review and immutable reused kernels.

The interrupted nanosleep scope (`60f5c267`, 40) retains all nine original
checks, one-second sleep, 20-ms interruption and remainder bounds. Its native
volatile signal counter and actual exported callback preserve signal identity.
Both actual host sanitizer ABIs, both strict four-module SDK links and three
paired native cases per architecture passed against reused immutable kernels.
`qemu-nanosleep40-final-validation.json` records peer lifetime review; the
scope at that stage left 3,140 original lines plus ten integration lines.
Blocked-thread and pollfd ports left 3,080 plus 14 integration lines;
the later epoll/syscall ports leave 3,040 plus 18 integration lines.

The SPI fixtures (`558dc058`, `775f7f2a`) passed 147/115 original checks,
21/19 groups, 100,000 mutations each, both actual host sanitizer ABIs and all
eight native C/V model controls. Full ARM provider code remains unchanged;
private x86 providers omit only five manifested, unexecuted ARM hardware
entries. Native models add no physical SPI claim. `spi-{keyboard,touchpad}-stage-validation.json`
records no allocator imports and peer lifetime review.

The POSIX timer (`ad82c434`, 230), x86 poll (`003f5861`, 85) and hotplug
(`d21ed758`, 147) fixtures retain all 59/29/47 original checks. Complete native
C/V controls and strict SDK links passed; hotplug also passed both actual host
sanitizer comparisons. Fixed records, exported callbacks, timer/FD/child
ownership and original deadlines remain. Receipts: `posix-timer-fixture/validation.json`,
`poll-validation.json`, `hotplug-validation.json`. They reuse immutable kernels;
x86 poll adds no ARM/host check and physical CD321x/DCP remains untested.

The verified-boot fixture (`8b96b191`, 40) passed both fresh freestanding builds,
byte-identical 120-byte C/V request records, volatile IR/instruction checks,
five host policy tests and all 16 native Limine scenarios. It retains the
40-second budget and rejects config, kernel and module tampering. Both native
pairs ran with Secure Boot disabled; no new firmware trust enrollment or
production-kernel build is claimed. `verified-fixture-validation.json` records
peer review and pinned Limine 12.8.0 inputs.

Completed disposable test images may be retired only after recording hashes;
preserve source, executables, logs and receipts. Recent image-build failures
from a full host disk were setup failures before any fixture verdict.

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

The speaker fixture retained all 175 assertions/20 groups and passed original-C/V
sanitizers on actual ARM/x86 hosts and both complete native model guests. Its
original explicit allocations and frees remain; eight unexecuted hardware entries
are omitted only in manifested scratch providers. The stat guest retained all
32 source checks and three 300-iteration cohorts; original-C/V guests on both
architectures returned identical lines with every measured heap class/page and
post-free counter flat. The sampler retained 20 assertions, exact allocation
counts and every OOM/poison/clock/kext case. Both host sanitizer comparisons and
all four native model guests passed. Three variadic capture lines and the retired
five-line declaration input receive zero algorithm credit. V exports now produce
the public declarations; the default production sampler artifact is byte-identical.
A first sampler V ARM image stalled in firmware; the identical kernel/init passed
with a fresh image and unchanged deadline. Receipts: `speakers-stage-validation.json`,
`stat-buffer-validation.json`, `sampler-fixture-validation.json` and
`sampler-fixture-arm-firmware-stall.json`. These tests add no physical hardware or
comparative benchmark performance claim.

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
`b5245a1330d8ce652b111552d5c0fcbdec64e915` reports **V 72.37%, C 4.83%**,
488 C files, 523 Python files and 287 shell files. The inventory records every
committed blob size and pinned reproduction command. All 2,726 classified blobs
were verified against Git; no Verilog or vendored trees appear. The archive
changes maintained source inventory but contributes no translation credit.
`.gitattributes` remains unchanged, with own fixtures/headers counted honestly.
Concurrent commits include an 18,008,664-byte `desktop/font_data.v` blob;
the percentages describe the whole pinned source, not this port batch.

Local Linguist runs in Lima VM `vlin`, using
`/Users/alex/.cache/vinix-linguist/repository.git` with alternates to this
checkout. Pass explicit `--rev <full-committed-source-SHA>`. The checked helper
in the current first-party cache is `refresh-linguist-safe.py`. It verifies
all listed bytes, source hash, reproduction command and percentages. Regenerate
from a committed source revision after further ports; do not infer percentages
from line counts or count archived evidence as translated work.

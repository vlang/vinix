# Kernel C to V: next-session handoff

Updated 2026-10-06 in `/Users/alex/code/vinix` on macOS ARM64/zsh.
The completed implementation source is
`db601f941aafd7a9335fd2b54cc3dfb41e12e468`; the language inventory was committed
as `56c6c584`. Re-read HEAD, `AGENTS.md` and the working-tree status before
starting: other sessions actively edit and commit this checkout.

## Request to continue

> Continue migrating first-party C implementations to V in
> `/Users/alex/code/vinix`. Read `AGENTS.md`, `docs/kernel-v-migration.md`
> and `docs/kernel-v-migration-handoff.md` first. Work in stages, run the
> relevant tests after each stage, build both kernel architectures, verify in
> QEMU, and commit each completed stage using only its own paths. Preserve C
> ABI, synchronization, allocation and lifetime behavior. Keep upstream
> libraries and independent C fixtures intact. Update the migration record
> and the C/Python/shell Linguist inventory after the ports.

## Completed work

The continuation from `823aeb116eb3b3ab20463ccb9b1c3fba6f0c41ae` migrated
**at least 10,191 original C implementation lines**. This conservative count
excludes native ABI bindings, original diagnostic fixtures and scaffolding.
A further 32-line classic GL example embedded in a shell script became V
without receiving tally credit. Former C implementations were removed or
reduced to narrow native bindings; maintained algorithms and ownership now
live in V. Generated C is a build artifact.

| Completed scope | Native V location | Counted original lines | Commit |
| --- | --- | ---: | --- |
| Console/buffer policy | `kernel/kprint/printf_policy*.v` | 119 | `3a2c4ed6` |
| Allocation instrumentation | `kernel/alloctrack` | 219 | `acad3b2a` |
| Apple ADT/FDT and freestanding helpers | `apple-boot/vcore/tree.v` | 719 | `5f6951c7` |
| Keyed bit waits and wound/wait mutexes | `kernel/linuxkpi/compatcore/{wait_bit,ww_mutex}.v` | 345 | `61572a06` |
| Apple loader/runtime/handoff | `apple-boot/vcore/boot.v` | 1,059 | `5d2c7537` |
| Sandbox, mandatory-policy CLI and audit collector | `tools/{sandbox,security-mac,security-audit}/core` | 665 | `5cfc023e` |
| Darwin AGX trace observation | `tools/agx-re/tracecore/core.v` | 420 | `7149f685` |
| LinuxKPI allocation, formatting and owned logging | `kernel/linuxkpi/compatcore/{runtime,format,printk}.v` | 840 | `6b18ca9e` |
| Linux task state, clocks/sleeps and timer ownership | `kernel/linuxkpi/compatcore/{task,time,timer}.v` | 718 | `2172fb48` |
| Locks/completions, SRCU and workqueues | `kernel/linuxkpi/compatcore/{sync,srcu,workqueue}.v` | 1,704 | `9b785b5f` |
| Shared Vinix/XNU heap sampler | `kernel/heapbench` | 273 | `069f76c3` |
| X11 input and Wine input/selection/process bridge | `build-support/xorg-server/{xinputcore,winehost}` | 1,712 | `58f63ef8` |
| ARM shell, full-userland and desktop init | `build-support/init-aarch64/initcore` | 731 | `58f63ef8` |
| M1 Wi-Fi control utility | `tools/m1-wifi/core` | 110 | `58f63ef8` |
| EGL/GLUT samples | `gl-triangle/{eglcore,glutcore}` | 557 | `58f63ef8` |
| **Total** | | **10,191** | |

The tally excludes 1,573 original diagnostic lines and 25 runtime-fixture
scaffolding lines. The 146-line synchronization and 710-line workqueue fixture
bodies remain byte-for-byte C. Task/time/timer exclude 312 original diagnostic
lines from the count; the private deadline-table observer now has a V ABI
entry while the independent caller's assertions and deadlines remain intact.
For several scopes, the complete new native binding translation units were
subtracted even though they contain declarations and new scaffolding.
The detailed scope arithmetic is in [kernel-v-migration.md](kernel-v-migration.md).

The preceding batch's 9,989 C implementation lines and 1,119 header/include
implementation lines, including SMC, AGX G17, ext2, ANS, SPI, speakers, Wi-Fi,
networking and earlier LinuxKPI helpers, are recorded there too. Keep the
unmodified Linux, nanoprintf, lwIP and other imported libraries intact.

## Remaining kernel C

At the completed source revision, the top-level `kernel/c/*.c` inventory,
excluding files named `*_test.c`, is **611 lines across ten files**. These are
native bindings rather than the previously remaining LinuxKPI engines.
Counts include comments and blank lines.

| File under `kernel/c/` | Lines | Native boundary |
| --- | ---: | --- |
| `alloc_track.c` | 9 | Capture the original native frame and retain it during the V walk |
| `linuxkpi_printk_v_primitives.c` | 97 | Native `va_list`, variadic entries, header/task access and worker creation |
| `linuxkpi_runtime_v_primitives.c` | 89 | Imported PCI tables, Linux field/header access and variadic formatting |
| `linuxkpi_srcu_v_primitives.c` | 83 | Checked SRCU/work/timer layouts and Linux inline/header bindings |
| `linuxkpi_task_v_primitives.c` | 41 | Checked task/time/timer layouts, tick aliases and native worker ABI |
| `linuxkpi_v_primitives.c` | 54 | Existing Linux primitives, task fields, warnings and per-CPU linker storage |
| `linuxkpi_wait_v_primitives.c` | 81 | Checked lock/wait layouts, bit access and actual C callback identities |
| `linuxkpi_workqueue_v_primitives.c` | 81 | Native callback addresses, pthread/header access and variadic queue naming |
| `printf.c` | 63 | Native variadic/nanoprintf entry points and ABI policy calls |
| `printf_benchmark.c` | 13 | Native variadic benchmark entry and nanoprintf callback ABI |
| **Total** | **611** | |

Public C headers, independent C fixtures and committed benchmark source
snapshots remain counted honestly. A larger C language-graph total therefore
does not imply that these migrated engines remain C. Recount from committed
source before selecting further first-party implementations; do not remove
necessary ABI bindings or mark them vendored to change the graph.

## Validation and evidence

Host sanitizer fixtures, required subsystem checks, both architecture builds
and the relevant native guests passed for the ports. Independent lifetime
review covered every new ownership boundary. The allocation-site allowlist
check still fails on the unchanged baseline as described below; this batch
does **not** claim that every repository check passes.

The complete LinuxKPI guest passed on four CPUs with `qemu64`, TCG,
`LINUXKPI=1`, `PROD=false`, and `-O2`. It covered caches/per-CPU storage, task
references, timed waits, timer retirement, ordered/delayed/bound/unbound/
priority/system workqueues, worker OOM rollback, SRCU, wound/wait, bit/I/O
waits, logging, sequence counters, scheduler and FPU. Every measured batch
returned to its exact free-page baseline. Tested kernel ELF SHA256:
`9edf46d7d6f29de1f101567887879526c566dd5cc6e1c00564b5736b22bc7135`.
Both builds, ARM boot and default `LINUXKPI=0` x86 boot also passed.

The final source audit matches all 672 tracked kernel files to `db601f94`
in each architecture tree, and both final builds exited successfully. The
final default x86 hypervisor guest passed with ELF SHA256
`13b771fb76e1e2f47976124d86639045027a15604e29482db58556844cc500a4`;
the GCC sampler object remains unchanged (`a1423ea8…`). Final ARM ELF SHA256
is `945416243c26087a94243d3e47e370881afc3e3c6db2a8a544317c18cc33f7f6`;
its final desktop plan completed all 44 required reports across
`ops,churn,cache,idle,apps,drag`, with screenshot checks for app launch/dragging.

Repeated `ops,churn` comparisons completed 80 reports each on the final V
kernel and unchanged `823aeb11` C kernel (ELF SHA256
`54732d4b8094d88eb3b4c6c7896ebf1008d1ca884c5165f9a2a571add19ba6b5`).
Image, desktop, compiler/dependencies and frozen fixtures matched; counts stayed
at 200 operations per case and 300 executions per program, with one DONE marker
and no errors per completed guest. Raw heap-class/large-page deltas match in 71/72 operation
reports, including all 36 warm reports; the only difference is one additional
64-byte object in V's cold `stat` snapshot.

This is not a universal flat-memory result. Existing VFS retention matches
both kernels, both directories and both rounds: `mkdir` keeps 208 bytes per
operation (+200 objects each in size-16/size-192), while `rename` and
`rename_over` keep 180/160 size-16 objects per 200 operations. These VFS paths
are unchanged by this batch. Whole-machine churn residuals vary from 0–80 KiB
on C and 16–48 KiB on V; no new consistent per-operation object-growth pattern
was observed. Keep these residuals and limitations explicit when discussing
memory verification. Do not weaken assertions or conflate complete metric
collection with zero retained memory.

The shared heap sampler passed 674,496 host allocation/free pairs and all
three native workload phases, with GCC 14.2.0 and checksum 27,358,432. The
GCC-linked x86 kernel also passed the full default hypervisor guest. Its
frozen and ISO-extracted ELF SHA256 is
`1d36d30c4fb63886df8dd77f2f0e3124069d242726d87bc962ed53713f1e8cf5`.
The new sampler has not run inside XNU; historical macOS benchmark captures
remain evidence of their original C workload.

The final V EGL binary passed all eight ARM Mesa fake-G17 rendering/fence/
resource/lifetime cases with an exact dependency image. ELF SHA256:
`4c165b986d67c3230c6d6a75d3678c482379cc612ba8fef795fddacbfdcd15b0`.
One repeat hit an intermittent queue-destroy/retirement timing expectation in
the unchanged ioctl fixture. The original C baseline and final unchanged V
pipeline both passed. Failure/comparison logs remain preserved; no assertion
or deadline was weakened.

The Apple loader passed sanitizer/layout fixtures and complete fake-iBoot
QEMU, with loader SHA256
`029ccc584d10d99a8e558fe1d0a9d5602c26c0148ab0cf85bf62f0bcbfeb537a`.
Real-ADT QEMU stopped at scheduler bootstrap (`spawn done, calling await...`)
with both the untouched C loader and V port. That comparison remains
unverified. Physical Apple boot/protocol/graphics/Wi-Fi operation, physical
Metal tracing and the new XNU kext remain untested. Local TCG cannot verify
actual VMX execution without nested VT-x.

Security utility fixtures and native sandbox/audit guests passed on both
architectures. X11 input and Wine input/selection fixtures passed in both
native architectures, and Wi-Fi passed eleven native device-model cases on
each. ARM shell/full/desktop init guests passed, including signal forwarding,
restart and adopted-child process-group retirement; all nineteen existing
bootstrap assertions passed. These models do not prove operation of physical
hardware or optional GPU/Hyprland/Wi-Fi init branches.

`tests/kernel-allocs/run.sh` reports **158 allowlist rejections** both on the
untouched `823aeb11` baseline and after the ports. Both have 354 ARM warnings,
293 x86 warnings and 414 distinct sites across architectures. Per-file/kind
counts have zero additions or removals. The allowlist and harness were left
unchanged; their delimiters are actual tabs. Production opt-in `compatcore`
generation with `-warn-about-allocs` reports zero allocation warnings, and
new generated code was inspected for implicit allocator imports. This is
baseline evidence, not an allowlist PASS or a replacement for measured
retirement checks.

The diagnostic retirement policy from `94ed1845` remains: deferred reaping
must be quiescent, free bytes stable for 500 ms, and retirement has a
30-second allowance. Exact equality assertions remain intact. Earlier short
baselines counted dying stacks, and extra worker tracing caused a completion
timeout. The passing full guest keeps the original fixture deadlines and
tracing disabled. Under host contention one bound-work marker was followed
by many minutes without output before the worker/SRCU/wound-wait markers
resumed and the suite passed. Compare future failures against an untouched
baseline rather than weakening assertions.

Local evidence is under
`/Users/alex/.cache/vinix-c-to-v/batch-next-10k-20261005-220015/`:

- `compat-all-host-final.log`, `compat-all-{arm,x86}-build*.log`,
  `compat-all-x86-qemu.log`, `compat-all-x86-guest/serial.log`,
  `compat-all-{arm,x86}-kernel.json` and `compat-all-arm-qemu.log`.
- `heap-sampler-host.log`, `heap-gcc-qemu.log`, `heap-gcc-provenance.json`,
  `heap-default-x86-boot.log` and `heap-gcc-x86-kernel.elf`.
- `apple-stage{1,2}-*.log` and `apple-stage2-loader.json`, including the
  preserved real-ADT comparison.
- `gl-mesa-qemu-exact-3.log`, `gl-c-baseline-qemu.log`,
  `gl-mesa-pipeline-2.log`, `gl-vm-final-2/validation.json` and the preserved
  retry/comparison logs. The latter validation is the final committed pipeline;
  the earlier exact-image pass remains separate evidence.
- `wine-host-final*.log`, `wine-{arm,x86}-qemu3.log`,
  `xinput-host-final*.log`, `xinput-{arm,x86}-qemu*.log`,
  `wifi-ctl-validation.json` and `wifi-{arm,x86}-guest.log`.
- `init-policy-host.log`, `init-policy-qemu.log`,
  `init-stage/validation.json` and `init-guests/*/serial.log`.
- `kernel-alloc-sites.log`, `kernel-alloc-baseline-823.log`,
  `kernel-alloc-baseline-compare.json`, `kernel-alloc-opt-core.log` and
  `alloc-opt-core/compat.c`.
- `final-source-{arm,x86}-build.log` for the completed exact-source builds
  and `final-source-x86-qemu.log` for the final default x86 guest.
- `perf-final/final-validation-summary.json`, `combined-validation.json`,
  `warm-validation.json`, `baseline-validation.json`, raw serial logs and
  `retention-review/matched-comparison.{json,txt}`. Missing-directory archive
  setup and firmware-only startup attempts are preserved separately; final
  comparisons used unchanged firmware/configuration/fixtures.

These are machine-local caches. The committed migration document is the
final durable record; do not assume caches exist on another machine or use
an old worktree binary as validation of a future edit.

## Build and test setup

The verified tools remain `/Users/alex/code/v/v` (**V 0.5.2 e690943**), Apple
Clang 21.0.0 and `/opt/homebrew/bin/ld.lld` (**LLD 23.1.0**). The genuine x86
GCC sampler uses GCC 14.2.0 from
`/opt/homebrew/Cellar/musl-cross/0.9.11/libexec/bin/x86_64-linux-musl-gcc`.
Respect `build-support/find-v.sh` and recheck versions before a new stage.
Use explicit `make -C <worktree>/kernel`, not a root userland build.

Current isolated source trees include `worktree-arm` and `worktree-x86`
inside the batch cache above. Other worktrees elsewhere in
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
- Keep public C headers/layouts. `VINIX_V_RUNTIME` guards prevent generated
  opaque-signature conflicts; escape reserved fields as `C.@type`/`C.@read`.
  Check private pool sizes/alignment and opaque storage with static assertions.
- Linux macros/inlines can use narrow native bindings. Algorithms belong in
  V; do not move complete C bodies into headers, strings or adapters. Keep
  broad upstream Linux headers out of the main generated V blob.
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
- Native `va_list`, signal types/restorers and register syscalls remain narrow
  ABI shims. V owns parsing/output/policy. Keep callback identity and synchronous
  stack buffer borrowing intact across these boundaries.
- Empty condition-call loop bodies were dropped by this V compiler; explicit
  `continue` preserves EINTR/reaping loops. Names such as `print` can trigger
  built-in conversion behavior; inspect generated calls and allocator symbols.
- Unsafe blocks do not replace width/overflow/volatile/assembly checks.
  Chained macro assignments and `~false` produced incorrect early translations.
- Copy sources into worktrees with fresh modification times: stale timestamps
  can retain an old `blob.c.o`. Do not overwrite corrected ports with old scratch
  translation scripts. Never restore generated C as maintained source.

## Git and language statistics

Inspect `git diff HEAD -- <owned paths>` before committing those exact paths.
Plain `git diff` can be empty when another session staged pending changes.
Avoid `git add -A`, branch-wide cleanup, resetting shared worktrees and
committing unrelated desktop/build edits. No push is requested. Re-read the
current user request before selecting any further implementation scope.

At source commit `db601f941aafd7a9335fd2b54cc3dfb41e12e468`, Linguist 7.27.0
reports **V 41.85%, C 23.71%**, with **557 C files, 385 Python files and 283
shell files**. Inventory commit `56c6c584` records exact paths and committed
blob sizes in [linguist-files.md](linguist-files.md). `.gitattributes` forces
all `.v` to V and excludes third-party C. No Verilog or vendored trees appear
in the counted inventory. New ABI headers and independent fixtures remain
counted C; do not infer graph percentages from line counts.

Local Linguist runs in Lima VM `vlin`, using the bare cache at
`/Users/alex/.cache/vinix-linguist/repository.git` with object alternates to
this checkout. Pass `--rev <committed-source-SHA>` explicitly. Use the checked
helper at
`/Users/alex/.cache/vinix-c-to-v/batch-next-10k-20261005-220015/refresh-linguist-safe.py`.
The older refresh helper has flawed snapshot-metadata handling. Update the
source SHA and reproduction command, verify listed sizes against committed
blobs, and keep first-party C counted honestly.

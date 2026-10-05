# Kernel C to V: next-session handoff

Prepared 2026-10-05 in `/Users/alex/code/vinix` on macOS ARM64/zsh.
Snapshot HEAD before this handoff: `2a9dc2fe`. Re-read HEAD, `AGENTS.md` and
the working-tree status before starting: other sessions actively edit and
commit this checkout.

## Request to continue

> Continue migrating first-party kernel C implementations to V in
> `/Users/alex/code/vinix`. Read `AGENTS.md`, `docs/kernel-v-migration.md`
> and `docs/kernel-v-migration-handoff.md` first. Work in stages, run the
> relevant tests after each stage, build both architectures, verify in QEMU,
> and commit each completed stage using only its own paths. Preserve C ABI,
> synchronization, allocation and lifetime behavior. Keep upstream libraries
> and independent C fixtures intact. Update the migration record and the
> C/Python/shell Linguist inventory after the ports.

## Completed work

The latest batch migrated **9,989 original C lines across 18 implementations
in ten stages**, plus **1,119 original lines of header/include implementation**.
All these implementation files have been removed; their V replacements are
compiled by the kernel and exercised by the original independent fixtures.
Earlier runtime, memory, integrity, PCI, mitigation, stack and VMX ports are
recorded in [kernel-v-migration.md](kernel-v-migration.md).

| Completed stage | Native V location | Current commit |
| --- | --- | --- |
| SMC protocol | `kernel/apple/smc/core/core.v` | `7629b9fa` |
| AGX G17 verifier | `kernel/lib/agx_fake_g17.v` | `21313466` |
| AGX G17 encoder | `kernel/lib/agx_fake_g17_encode.v` | `21e3352b` |
| Classic ext2 | `kernel/apple/ans/ext2core/core.v` | `e8ffb5fa` |
| ANS controller/policy/GPT/RMW | `kernel/apple/ans/anscore/core.v` | `2cf02b40` |
| Apple SPI keyboard/touchpad | `kernel/apple/spi_keyboard/spicore/core.v` | `1892bd11` |
| J313 speaker transport/thermal model | `kernel/apple/speakers/spkcore/core.v` | `63eb06e0` |
| BCM4378/M1 Wi-Fi | `kernel/apple/wifi/{wificore,m1core}` | `c038ee55` |
| IPv4/IPv6 lwIP adapter | `kernel/netcore/core.v` | `1efaf7c7` |
| LinuxKPI strings/parsers/bitmaps/caches/per-CPU/refcount/taint/I/O scopes | `kernel/linuxkpi/compatcore` | `73ddd8cb` |

Another session rebased the shared branch during the batch. Use the current
commit IDs above; older IDs in local logs identify the original tested
commits. The LinuxKPI port was included by that session in a mixed commit
whose subject begins `Files:`. Do not repeat that broad staging practice.

Small C ABI bindings remain intentionally, including `net_driver_abi.h` and
the 54-line `linuxkpi_v_primitives.c`. The latter binds unmodified Linux
header primitives, task fields, warnings and per-CPU linker storage. Helper
algorithms and cache/per-CPU ownership now live in V. The AGX generator emits
V directly; do not restore generated C as maintained source.

## Remaining kernel C

This is the current top-level `kernel/c/*.c` implementation inventory,
excluding files named `*_test.c`. Counts include comments and blank lines.
The total is **6,488 lines**, including the 54-line ABI binding. Recount
before selecting the next scope; larger language-graph totals also include
C headers, independent fixtures and committed benchmark source snapshots.

| File under `kernel/c/` | Lines | Scope |
| --- | ---: | --- |
| `linuxkpi_wait_bit.c` | 180 | Hashed queues, keyed wakes and wait/action loops |
| `linuxkpi_ww_mutex.c` | 246 | Wound/wait and Wait-Die mutex policies |
| `linuxkpi_task.c` | 267 | Linux task state and native scheduler bridge |
| `linuxkpi_printk.c` | 375 | Owned log records and asynchronous draining |
| `linuxkpi_timer.c` | 396 | Timer callbacks and retirement |
| `linuxkpi_time.c` | 408 | Tick aliases, conversions and timed sleeps |
| `linuxkpi_srcu.c` | 442 | Reader banks, grace periods and callbacks |
| `linuxkpi_format.c` | 530 | Linux formatting subset and pointer-key publication |
| `linuxkpi.c` | 551 | Allocation and common compatibility runtime |
| `linuxkpi_sync.c` | 624 | Locks, wait queues and completions |
| `linuxkpi_workqueue.c` | 1,658 | Ordered/delayed/unbound/bound/priority queues |
| `alloc_track.c` | 228 | Optional allocation instrumentation |
| `heap_benchmark.c` | 334 | Kernel heap benchmark |
| `printf_benchmark.c` | 35 | Formatting benchmark |
| `printf.c` | 160 | Console/buffer policy and C variadic/nanoprintf entry points |
| `linuxkpi_v_primitives.c` | 54 | Existing ABI/header bindings; retain as needed |

A reasonable first stage is `linuxkpi_wait_bit.c`: it is bounded and already
has independent host and native guest coverage. Preserve cache-line alignment
of the boot table, original address/bit hash keys, callback identity, acquire
bit tests, absolute timeout capture and the locked `finish_wait` guarantee
before a waiter's stack record disappears. I/O actions are already V.

Then split time conversion logic from tick/sleep ownership, and port the
remaining LinuxKPI implementations in tested pieces. Leave the large
workqueue engine until its dependencies and callback/lifetime conventions
are established. Benchmark/instrumentation files are a separate small batch.
For formatters, V can own parsing and output policy while a minimal C shim
handles native `va_list` access. Keep nanoprintf and imported Linux unchanged.

## Validation and evidence

Every completed stage passed its host sanitizer tests, architecture builds
and QEMU checks. Network guests covered IPv4/IPv6, SLAAC, scope, socket options
and multicast. Independent 500-exchange workloads retained zero objects in
every measured heap class on both architectures. ARM AGX Mesa passed eight
rendering/lifetime cases. Apple protocols have host MMIO/firmware fixtures;
physical ANS, SMC, SPI, Wi-Fi and speaker operation remain untested. Local
QEMU TCG also cannot verify actual VMX execution without nested VT-x.

The final full LinuxKPI guest passed on four CPUs with `qemu64`, TCG,
`LINUXKPI=1`, `PROD=false`, and `-O2`, including object caches, per-CPU storage,
task references, timer/workqueue variants, worker OOM rollback, SRCU,
wound/wait, bit/I/O waits, logging, sequence counters, scheduler and FPU.
Every measured batch returned to its exact free-page baseline. Tested ELF:
`8c297d8095457670f41394c487ac2b68ae57cce4738a488aa52b93186cf96b69` (SHA256).

Commit `94ed1845` completed the diagnostic retirement adjustment: deferred
reaping must be quiescent, free bytes stable for 500 ms, and retirement has a
30-second allowance. Exact equality assertions remain intact. Earlier short
baselines counted dying stacks; one run returned roughly 4 MiB more free
memory afterward. A five-second settling attempt also expired under host
contention. Extra worker tracing caused a completion timeout; the passing run
had tracing disabled and the original fixture deadline unchanged. Investigate
future failures against the untouched baseline; do not weaken assertions.

Local evidence is under `/Users/alex/.cache/vinix-c-to-v/batch-10k/`:

- `progress.json`: original scope, line counts, commits and completed stages.
- `original/kernel/c/`: frozen original C source for comparisons.
- `compat-host-final3.log`: passing host LinuxKPI sanitizer/header/upstream tests.
- `compat-retirement-qemu.log` and `compat-retirement-qemu/serial.log`: full PASS.
- `compat-retirement-kernel.json`: tested kernel hash and build configuration.
- `net-ipv6-{arm,x86}-qemu.log` and `net-multicast-{arm,x86}-qemu.log`.

These are machine-local caches. The committed migration document is the
durable record; do not assume the caches exist on another machine.

## Build and test setup

The last batch used `/Users/alex/code/v/v`, verified as **V 0.5.2 e690943**,
Clang and `/opt/homebrew/bin/ld.lld`. Respect `build-support/find-v.sh` and
recheck compiler versions before a new stage; other sessions change toolchains.
Use explicit `make -C <worktree>/kernel`, not a root userland build.

Existing isolated worktrees are in `/Users/alex/.cache/vinix-c-to-v/`:
`worktree` (ARM), `worktree-x86` (default x86) and `worktree-compat` (LinuxKPI).
They contain old bases and staged source copies; their old binaries are not
validation of a future change. Prefer fresh worktrees from the current HEAD.
Reuse or symlink untracked freestanding headers, architecture-specific
cc-runtime dependencies, `c/{lwip,uacpi,flanterm}` and `c/nanoprintf.h`.
Build each architecture's runtime archive in isolation. `kernel/get-deps`
resets/cleans dependency repositories, so do not run it through shared
dependency symlinks.

Set `port_arm` and `port_x86` to separate prepared worktree paths, and
`port_guest`, `port_arm_guest` and `port_x86_guest` to unused guest directories.
The following are the build/test shapes used locally:

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
```

Run subsystem host tests from the checkout containing the new source. A
default x86 boot check must use its `LINUXKPI=0` binary, before the opt-in
rebuild replaces it. `PROD=false` is needed for LinuxKPI diagnostic markers;
the API remains opt-in and x86-only. The full guest harness requires every
marker, not just startup or userspace. Guest directories must be new. Its
optional `--limine-dir` can reuse a verified bootloader cache. Under heavy
host load, a build can take minutes and a complete guest tens of minutes;
inspect progress and failure logs before calling it hung.

## Porting constraints learned in this batch

- Kernel V uses `-gc none -manualfree`. Preserve explicit ownership and inspect
  generated C and `nm -u` for implicit allocator imports. Fixed arrays use
  `[a, b]!`; avoid interpolation, heap literals, escaping locals and dynamic
  array/interface allocations on repeated paths. Follow `AGENTS.md` for
  measured leak checks and lifetime review when changing ownership.
- Under `-os vinix`, V `int` is 64-bit. Use `i32`/`u32` for C integer ABIs,
  explicit pointer/word widths, and preserve atomic memory orders.
- A foreign global needs `@[c_extern] __global C.name`; an unprefixed name can
  silently create separate storage. Global names can also collide with locals
  across modules: `memory.slabs` previously collided with a cache parameter.
- An exported V function has a native function and a C wrapper, with distinct
  addresses. Preserve the actual callback pointer registered with C when
  tests or unregister logic compare identity.
- Keep public C headers and ABI layouts. `VINIX_V_RUNTIME` guards accommodate
  generated V declarations without changing normal C caller prototypes.
  Escape reserved field names as `C.@type`/`C.@read` where necessary.
- Linux header macros/inlines can use narrow bindings in
  `linuxkpi_v_primitives.{c,h}`. Algorithms belong in V; do not relocate whole
  C bodies into headers, strings or adapters. Keep broad upstream Linux headers
  out of the main generated V blob; validate opaque storage sizes/alignment
  with static assertions in the binding translation unit.
- Time ports must preserve `jiffies` and `jiffies_64` as the same word, including
  the Darwin host assembler alias. Existing tests check their address identity.
- The V compiler used here does not support ARM's `%w` operand modifier. Reuse
  the existing 32-bit MMIO primitive where needed; check optimized instructions
  for counter reads, volatile accesses and barriers.
- Extend `tests/linuxkpi/compile-v-core.py`/`run.sh` as needed to link the
  production V core into existing independent C fixtures. Host aliases for
  `strchr`, `strpbrk`, `strsep` prevent interposing on sanitizer/libc internals.
- Inspect translation scaffolds carefully: chained macro assignments and
  `~false` produced wrong translations during this batch. Unsafe blocks do not
  replace checks for widths, overflow, volatile MMIO or assembly ordering.
- Copy source into build worktrees with fresh modification times; preserving
  old timestamps can leave stale `blob.c.o`. Never overwrite corrected ports
  with an old scratch translation script.

## Git and language statistics

Always inspect `git diff HEAD -- <owned paths>` and commit only those paths.
Another session previously staged everything, so plain `git diff` could be
empty even with pending changes. Avoid `git add -A`, branch-wide cleanup,
resetting shared worktrees, and committing others' desktop/build edits.
This handoff does not request a push or start another implementation stage.

At source commit `94ed1845`, Linguist 7.27.0 reports **V 39.97%, C 25.32%**,
539 C files, 359 Python files and 280 shell files. See
[linguist-files.md](linguist-files.md) for exact paths and blob sizes.
`.gitattributes` already forces all `.v` to V and excludes third-party C.
Keep first-party implementations and fixtures counted honestly. Regenerate
the inventory from a committed source revision after the next batch; do not
infer percentages from line counts or mark own C as vendored.

Local Linguist is installed in Lima VM `vlin`, with a bare repository cache
at `/Users/alex/.cache/vinix-linguist/repository.git`. Its object alternates
point to this checkout; pass `--rev <committed-source-SHA>` explicitly.
The helper `/Users/alex/.cache/vinix-c-to-v/refresh-linguist-doc.py` can refresh
tables, but inspect its snapshot metadata handling and update the source hash
and reproduction command too. Verify every listed size against committed
blobs and confirm no Verilog or vendored trees appear.

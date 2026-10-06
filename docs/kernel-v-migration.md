# Kernel C to V migration

The [next-session handoff](kernel-v-migration-handoff.md) lists the remaining
implementations, build/test setup and porting constraints from the latest batch.

Port first-party implementations in small stages, preserving their external
interfaces. The current request permits only third-party libraries to remain
in C. Port first-party native bindings, header implementations and independent
fixtures too; preserve original fixture assertions and frozen Git revisions for
differential validation. Generated C from V is a build artifact, not maintained
source. Historical batches below used the earlier fixture/binding exception;
that exception no longer applies to maintained first-party source.
Architecture instructions stay in V inline assembly where its constraints
can express the required ABI and ordering. Naked entry points with exact
fault/recovery labels stay in architecture assembly when V cannot express
their return convention without generating a C statement.

Each stage needs its subsystem tests and builds for both kernel architectures
before committing. Inspect generated C for allocations and optimized machine
code for volatile accesses or assembly ordering when these matter. Kernel
tests build in isolated worktrees to avoid incorporating concurrent changes.

| Stage | Implementations | Status |
| --- | --- | --- |
| Memory runtime | `memcpy`, `memset`, `memmove`, `memcmp`, `atoi` | Committed as `6fd8cf1b`; 410,739 sanitizer cases and both architecture core suites passed |
| Runtime and CPU helpers | Secret erasure, hardware random words, ARM granule switch | Committed as `7e996557`; host erasure/ChaCha/SHA-256, network randomness, both builds/core suites, ARM persistence and both native reseeding tests passed |
| Network randomness | Output pool, IP IDs, TCP ISNs, ephemeral ports, SipHash | Committed as `3f4280f7`; host C ABI/sanitizer and allocator-import checks passed; both builds, network options and IPv4/IPv6 guest suites passed with zero retained objects over 500 socket exchanges |
| Integrity helpers | Verity hashing, tree layout and verification | Committed as `5d7f2d0a`; host C ABI/sanitizers, 267 SHA-256 lengths against hashlib, 139 geometries against the builder, both builds and all verified-root boot/corruption cases passed; 1000 verified reads and 1000 shared fault/unmap cycles retained zero objects/pages on both architectures |
| PCI transactions | Configuration bounds, serialized reads/writes and atomic COMMAND updates | Committed as `6f38f210`; both host C dialects passed with sanitizers and allocator traps; both kernel builds, ARM ECAM/full-DAIF fixture, x86 network-options guest and LinuxKPI host regression passed |
| CPU mitigation policies | Active per-CPU controls and original helper ABI | Committed as `62bdfc72`; host sanitizers passed 12,288 active-policy and 6,144 original-helper cases; allocation failure/retry and allocator-import checks passed; both builds, ARM boot, x86 compatibility guest, 1,024 assembly cases and linked retpoline scan passed |
| Stack protector | Static canary, boot entropy, initialization and fatal handler | Committed as `4fa6dbf2`; host C ABI tests passed 1000 replacements/protected-frame returns and deliberate canary mismatch; allocator imports and LLVM attributes passed; both kernel builds, optimized instruction checks and process/thread retirement guests passed; second measured batches retained zero physical/slab memory; ARM boots covered CPUs with and without FEAT_RNG |
| Stack fault diagnostics | Serial messages and hexadecimal fault evidence in V; naked probes and x86 idle entry in architecture assembly | Committed as `a9090255`; host sanitizer tests passed 2,003 fault records through each serial adapter, with no allocator imports; assembly instruction bytes and every fault/recovery offset matched the original C objects on both architectures; both builds passed in recovery, fatal-overflow and normal configurations; both QEMU recovery/fatal suites and normal retirement guests passed; second measured batches retained zero physical/slab memory; x86 linked retpoline scan passed |
| Apple display hotplug policy | Display-capable cable detection, debounce and one-shot cold-attach action | Committed as `0b5e86cd`; extended C ABI fixture passed against the original C and production V under ASan/UBSan, including unsigned timer wrap, cold attach without HPD, initial attachment, zero debounce and non-1 C truth values; no allocator imports; both kernel builds passed; x86 QEMU reached userspace and passed its linked retpoline scan; ARM QEMU completed the process/thread retirement workload with zero physical/slab retention in the second batch |
| VMX architecture helpers | VT-x controls, FPU state, descriptors and selector reads in V; exact VM entry/exit in assembly | Committed as `bf2fdd33`; host C ABI/sanitizer tests passed 7,680 control cases and all ARM no-op exports with no allocator imports; optimized x86 ports preserved CF/ZF capture, operand order and memory clobbers; all 214 VM-entry instruction bytes matched both the original host and kernel objects; both architecture builds and QEMU boot/syscall guests passed; x86 linked retpoline scan passed |
| SMC protocol core | Read-only RTKit boot, bounded mailbox transactions, capacity/power caching and text formatting | Committed as `7629b9fa`; 27 unchanged host fixtures passed against the V C ABI under ASan/UBSan with no allocator imports; both architecture builds and QEMU boot/syscall checks passed; physical Apple firmware remains untested |
| AGX G17 verifier | Stream layouts, golden writes, descriptor resources and permitted VM bindings | Committed as `21313466`; existing C ABI verifier/encoder and V descriptor fixtures passed with ASan/UBSan and no allocator imports; both builds and boot/syscall guests passed; ARM QEMU Mesa passed depth, stencil, combined rendering, completion and adversarial GEM/VM lifetime checks using matching staged Mesa libraries |
| AGX G17 encoder | Recovered producer graph, unsigned expression evaluation and register stream emission | Committed as `21e3352b`; independent verifier/encoder fixtures, ASan/UBSan, allocator imports and three generator tests passed; both builds passed; ARM QEMU Mesa passed all eight render/lifetime cases, x86 boot/syscall guest passed; generator now emits V directly |
| Classic ext2 | Byte-oriented reads, bounded mutations, dirty/clean mount transitions and preserved C ABI | Committed as `e8ffb5fa`; independent ext2 and ANS media fixtures passed with ASan/UBSan and no allocator imports; both builds and QEMU boot/syscall guests passed; Apple SSD hardware remains untested |
| ANS controller | RTKit/SART transport, partition boot policy, GPT validation, FUA/RMW writes and ordered shutdown | Committed as `2cf02b40`; all 27 independent media groups and 11 ext2 groups passed with ASan/UBSan and no allocator imports; both builds and QEMU boot/syscall guests passed; optimized ARM counter/cache/barrier instructions checked; physical ANS firmware remains untested |
| Apple SPI input | Shared PIO transport, keyboard reports and touchpad protocol/state machine | Committed as `1892bd11`; all 20 keyboard and 19 touchpad groups passed with ASan/UBSan, 200,000 mutated packets and no allocator imports; both builds and QEMU boot/syscall checks passed; physical SPI devices remain untested |
| J313 speakers | ADMAC/MCA playback and sense rings, amplifier sequencing and fixed-point thermal protection | Committed as `63eb06e0`; all 20 hardware and thermal-model tests passed with ASan/UBSan and no allocator imports; both builds and QEMU boot/syscall checks passed; physical amplifiers and acoustic protection remain untested |
| BCM4378 and M1 Wi-Fi | Firmware/protocol parsers, ring ownership, PCIe/DART setup and loader staging | Committed as `c038ee55`; 26 protocol groups, 100,000 parser mutations and eight platform groups passed with ASan/UBSan and no allocator imports; both builds and QEMU boot/syscall checks passed; physical firmware, association and DMA remain untested |
| Native network adapter | Link/timer policy, TCP/UDP PCB and pbuf ownership, IPv4/IPv6 endpoints and multicast memberships | Committed as `1efaf7c7`; original host packet/ownership assertions passed against V under ASan/UBSan with no implicit allocator imports; both builds and socket-option, physical IPv4/IPv6, SLAAC, scope and multicast QEMU suites passed; 500 socket exchanges retained zero objects in every heap class on both architectures |
| LinuxKPI helpers | Bounded strings, integer parsing, bitmaps, packed object caches, per-CPU storage, reference counts, taints and I/O-wait scopes | Committed as `73ddd8cb`; original host suite passed under ASan/UBSan with no implicit allocator imports; x86 opt-in and ARM default builds passed; full four-CPU x86 QEMU diagnostics and ARM boot/syscall guest passed; every measured diagnostic batch retained zero pages |
| Linux driver compatibility | Allocation, Linux formatting/logging, task state, time, timers, synchronization, SRCU and work queues | Completed in `61572a06`, `6b18ca9e`, `2172fb48`, `9b785b5f`; host sanitizers, both builds and full four-CPU QEMU diagnostics passed |
| Benchmark and allocation instrumentation | Console policy, live allocation tracking and the shared kernel heap sampler | Completed in `3a2c4ed6`, `acad3b2a`, `069f76c3`; sanitizer fixtures, both builds and relevant native guests passed |

The first two x86 core attempts after the runtime/CPU-helper port hit the same
free-memory accounting assertion (`tests/qemu-core/test.c:275`) seen during
the memory-runtime port. The untouched C baseline passed on rerun, and the
final migrated-kernel run passed the full core suite with four CPUs and the
native reseeding self-test enabled.

Two normal x86 retirement attempts after the diagnostics port exceeded their
300- and 900-second limits while the host load averaged about 313 across 18
logical CPUs. A previous-kernel comparison also progressed slowly through
warmup and was stopped before completion. The final run used the general
kernel regression harness with a 3600-second limit and passed the complete
workload. Its first batch kept 8 KiB of physical memory and no slab memory;
the second kept neither. The normal ARM run kept 16 then 0 KiB of physical
memory and no slab memory in either batch.

The hotplug port preserves the borrowed state layout and existing controller
allocation/ownership. QEMU does not emulate Apple's CD321x/DCP hardware;
physical cable attachment and firmware display training require testing on
a base M1 machine. Host tests verify the detection/debounce/action policy.

The reseeding test runs 10,000 production reseeds and partial reads, requires
zero retained objects in every heap class and zero large pages, and reaches
userspace. ARM was tested both without FEAT_RNG (native M1 virtualization)
and with it (QEMU `max` under TCG); x86 used QEMU `max` with RDSEED.

The VMX port shares the packed descriptor from the existing C ABI header and
uses `i32` for C `int` returns. It adds no allocations or ownership changes.
The VM-entry routine keeps every guest GPR and the VMCS host stack in the
same instructions as the original global assembly block.

The local x86 QEMU TCG setup does not provide VT-x. Its hypervisor guest
reports the absent device explicitly; passing that boot/syscall check does
not verify VMXON or VMLAUNCH execution. On a suitable x86 host with nested
VT-x, `tests/hypervisor/run-vm.py --require-vmx` requires five VM executions
with IO/HLT exits and complete GPR preservation. That hardware path remains
unverified locally.

## Follow-on batch: approximately 10,000 C lines

This batch replaces 9,989 original C lines across 18 implementations in ten
porting stages, measured from source commit `0e4bee84` before any ports in the
batch. Each implementation below is now V. Independent C fixtures and
third-party code stay in their existing languages. The stage table records
the commits, host tests, both architecture builds and QEMU checks.

| Original implementation | Original lines |
| --- | ---: |
| `kernel/c/apple_ans.c` | 807 |
| `kernel/c/apple_ans_ext2.c` | 792 |
| `kernel/c/apple_smc.c` | 520 |
| `kernel/c/apple_speakers.c` | 1,849 |
| `kernel/c/apple_spi_keyboard.c` | 772 |
| `kernel/c/brcm_m1.c` | 249 |
| `kernel/c/brcm_wifi.c` | 641 |
| `kernel/c/agx_fake_g17.c` | 313 |
| `kernel/c/agx_fake_g17_encode.c` | 1,158 |
| `kernel/c/vinix_net.c` | 1,375 |
| `kernel/c/linuxkpi_string.c` | 181 |
| `kernel/c/linuxkpi_kstrtox.c` | 398 |
| `kernel/c/linuxkpi_bitmap.c` | 300 |
| `kernel/c/linuxkpi_cache.c` | 298 |
| `kernel/c/linuxkpi_percpu.c` | 136 |
| `kernel/c/linuxkpi_refcount.c` | 63 |
| `kernel/c/linuxkpi_taint.c` | 53 |
| `kernel/c/linuxkpi_io.c` | 84 |

The batch also moves 1,119 lines from the ANS policy/GPT/read-write headers,
SPI touchpad header and IPv6 adapter include into V. The native implementations
are in `kernel/apple/{smc,ans,spi_keyboard,speakers,wifi}`, `kernel/lib/agx_fake_g17*.v`,
`kernel/netcore` and `kernel/linuxkpi/compatcore`. The AGX generator emits V directly.

The network adapter still calls unmodified lwIP. `kernel/c/net_driver_abi.h`
only adapts callback types and weak driver symbols. LinuxKPI retains its
upstream Linux headers and a small `linuxkpi_v_primitives.c` binding for their
inline locks, task fields, refcount decrement and scheduler primitives; parsing,
bitmap operations, cache/per-CPU ownership and exported helper algorithms live
in V. These bindings, C ABI headers and independent C tests remain counted as C.

During the LinuxKPI diagnostic run, an ordered-workqueue memory assertion
reported 353,132,544 free bytes before the run and 357,097,472 afterward.
Joined workers had not all completed scheduler reaping when the 50 ms baseline
settled. The diagnostic now observes deferred-reaper quiescence, requires a
500 ms stable baseline and allows 30 seconds for final retirement. Every
post-run comparison still requires exact equality; allocation and ownership
behavior is unchanged. An earlier delayed-work run also hit the retirement
assertion. The original C-helper comparison passed that delayed-work case.

A later run passed native-worker rollback and SRCU, then hit the five-second
baseline deadline after wound/wait warmup. The diagnostic allowance is now
30 seconds and a failure prints the current free bytes and deferred-reaper
state. A run with extra worker tracing also hit the fixture's completion
deadline; the final run uses its original tracing-free fixture and unchanged
completion deadline.

The final LinuxKPI run passed the complete `tests/linuxkpi/run_vm.py` suite
with four CPUs, QEMU TCG `qemu64`, `LINUXKPI=1`, `PROD=false` and `-O2`. It
covered packed object caches, per-CPU isolation, task references, timers, all
workqueue variants, worker allocation failures, SRCU, wound/wait, bit/I/O
waits, formatting, sequence counters, scheduling and i915 copy/FPU preservation.
Every measured batch returned to its exact free-page baseline. The tested
kernel SHA256 is
`8c297d8095457670f41394c487ac2b68ae57cce4738a488aa52b93186cf96b69`.

All ten porting stages are committed. Apple hardware-specific protocols have
host MMIO/firmware fixtures and boot coverage; physical ANS, SMC, SPI, Wi-Fi
and speaker operation still require testing on a supported Apple machine.

## Completed continuation: 10,191 original C lines

The continuation starts from `823aeb116eb3b3ab20463ccb9b1c3fba6f0c41ae`.
That revision has 6,488 lines in 16 top-level kernel C files, including the
54-line existing Linux header binding. Embedded native diagnostic fixtures
remain independent C callers and are recorded separately from translated
implementation lines. The completed scope extends beyond the remaining kernel
implementations into first-party boot and tools code. It covers 12,837 original
C lines and conservatively credits **10,191 translated lines**, excluding
independent diagnostics, native ABI code and other uncredited source lines.
Moving a C fixture receives no translation credit. Counts include comments and
blank lines; the lower bound subtracts entire new C binding files even where
their lines do not correspond directly to retained original implementation.

| Scope | Original C lines | Conservative translated lines | Commit |
| --- | ---: | ---: | --- |
| Console and formatting benchmark policy | 195 | 119 | `3a2c4ed6` |
| Allocation instrumentation | 228 | 219 | `acad3b2a` |
| Apple ADT/FDT and freestanding helpers | 719 | 719 | `5f6951c7` |
| LinuxKPI wait-bit and wound/wait | 426 | 345 | `61572a06` |
| Apple loader runtime and handoff | 1,059 | 1,059 | `5d2c7537` |
| Sandbox, MAC and audit tools | 859 | 665 | `5cfc023e` |
| Darwin AGX observation | 480 | 420 | `7149f685` |
| LinuxKPI allocation, format and logging | 1,456 | 840 | `6b18ca9e` |
| LinuxKPI tasks, clocks and timers | 1,071 | 718 | `2172fb48` |
| LinuxKPI synchronization, SRCU and workqueues | 2,724 | 1,704 | `9b785b5f` |
| Shared Vinix/XNU heap sampler | 334 | 273 | `069f76c3` |
| X11 input and Wine/clipboard bridges | 1,808 | 1,712 | `58f63ef8` |
| ARM init variants | 811 | 731 | `58f63ef8` |
| Wi-Fi CLI | 110 | 110 | `58f63ef8` |
| EGL and GLUT samples | 557 | 557 | `58f63ef8` |
| **Total** | **12,837** | **10,191** | |

A separate 32-line GL C heredoc was also ported and is excluded from both
totals. Upstream dependencies, public ABI layouts, independent C fixtures and
historical benchmark source snapshots remain intact. Each completed stage was
committed using its own reviewed paths.

| Stage | Native V location | Validation |
| --- | --- | --- |
| Console policy (`3a2c4ed6`) | `kernel/kprint/printf_policy*.v` | Complete: independent debug/production C ABI callers passed ASan/UBSan across 1,026 buffer lengths, chunk flushes, integer endpoints, embedded NUL, panic/assertion and serial-only benchmark output; no implicit allocator imports; both architecture builds and QEMU boot/syscall guests passed |

The console entries retain native C variadic/`va_list` access and the unchanged
nanoprintf dependency. V owns output selection, ordinary-print locking, the
256-byte stack buffer, chunk flushing and assertion text emission. The panic
path remains unconditional and lock-free; each callback borrows its live stack
context only during synchronous formatting. This lifetime was independently
reviewed before committing. QEMU does not verify physical UART/terminal devices.

| Stage | Native V location | Validation |
| --- | --- | --- |
| Allocation instrumentation (`acad3b2a`) | `kernel/alloctrack` | Complete: ASan/UBSan with 8,192 live records, deletion/replacement/restart and bounded output; no allocator imports; `ALLOC_TRACK=1` builds and native `/proc/allocsites` QEMU guests passed on both architectures |

The tracker retains its fixed table sizes, hash/probe/deletion behavior, aggregate keys,
acquire/release lock and nonblocking recording policy. A native frame-capture entry
keeps the original call-chain origin; its compiler barrier prevents a tail call
from retiring that frame during the synchronous V walk. Optimized x86 output
retains the CR4 LA57 check. The tables allocate no heap objects, and the new
frame lifetime received independent review.

Apple loader stage 1 moves the ADT reader, FDT writer/converter and freestanding
memory/string helpers (719 original implementation lines) into
`apple-boot/vcore/tree.v`. The public C ABI and independent converter
fixtures remain unchanged. ASan/UBSan passed 410,739 memory cases and the
converter matched 233 XNU register windows (four unsupported nodes skipped).
The AArch64 loader linked with no undefined symbols or allocator imports and
passed the fake-AICv3 QEMU boot, watchdog and firmware-reservation checks.
Caller-provided buffers, recursive bounds, byte alignment with the MMU off and
the static conversion scratch buffer retain their original lifetimes.

Real-ADT QEMU with the frozen ARM kernel stopped after scheduler bootstrap
(`spawn done, calling await...`) with both the unchanged C loader and the V
port. Both comparison guests idled at the same point; this check remains
unverified. Its markers and assertions were unchanged, and physical Apple
boot remains untested.

LinuxKPI wait-bit and wound/wait stage covers 426 original C lines, crediting
345 after subtracting its entire 81-line native binding, and moves policy into
`compatcore/{wait_bit,ww_mutex}.v`. Unchanged independent host callers passed
ASan/UBSan, header and pinned upstream checks; both architecture builds passed.
The ARM boot guest passed and the complete four-CPU x86 LinuxKPI guest passed
all required markers, including exact free-page retirement equality. The
fixed cache-line-aligned wait table, address/bit hashes, acquire tests, captured
absolute deadlines and actual C callback identities remain intact. Every stack
waiter is removed under its queue lock before returning; direct mutex handoff
publishes its saved context and task without reading a detached waiter after
wakeup. Both lifetime paths received independent review.

Apple loader stage 2 translates its remaining 1,059 C lines: boot argument
parsing, framebuffer diagnostics, physical allocation/page tables, ELF loading,
Limine responses, reserved-memory maps, watchdog and final handoff now live in
`apple-boot/vcore/boot.v`. Assembly startup remains unchanged apart from an
instruction-only 32-bit MMIO binding, also used for every volatile framebuffer
store. Host ASan/UBSan passed boot revision, TCR, page-table, ELF and memory-map
cases; 78 public structure field offsets plus sizes/alignment match C. The
freestanding AArch64 loader builds without allocator imports and passes the
complete fake-iBoot QEMU harness. Independent lifetime review verified monotonic
physical ownership and permanent handoff arena copies. The tested loader SHA256
is `029ccc584d10d99a8e558fe1d0a9d5602c26c0148ab0cf85bf62f0bcbfeb537a`.
The real-ADT baseline limitation above still applies.

| Stage | Native V location | Validation |
| --- | --- | --- |
| Security utilities | `tools/{sandbox,security-mac,security-audit}/core` | Complete: unchanged independent C host callers passed ASan/UBSan; all three static target utilities built for aarch64 and x86_64; original sandbox and audit collector QEMU guests passed on both architectures; kernel guest runner's 12 tests passed |

This stage covers 859 original C lines and conservatively counts 665 translated
implementation lines: 192 sandbox, 96 mandatory-policy CLI and 377 audit
collector lines. Native syscall, stat, signal, clock and stdio adapters remain C,
as do every original independent fixture and its native variadic helper. The
build generates V core C into temporary output and links it with these adapters;
generated C is not maintained source.

The sandbox retains the original ordered, fail-closed credential/capability
transitions, bounded arguments and explicit environment. The collector validates
the entire bounded snapshot, reports lost sequences and unavailable outcomes,
and publishes its next stack-owned state only after append and `fsync` succeed.
Descriptor walking, directory/log ownership and permission checks, same-inode
rotation through the existing flock description and error-preserving cleanup
retain their original behavior. New stack-buffer and descriptor lifetimes
received independent review; the V cores introduce no implicit allocations.

| Stage | Native V location | Validation |
| --- | --- | --- |
| AGX trace observation | `tools/agx-re/tracecore/core.v` | Complete: independent typed driver model passed ASan/UBSan and exact frozen-C JSON/allocation parity in four filter/byte-limit modes; arm64 and x86_64 macOS dylibs built with strict format warnings; physical Metal capture remains untested |

This stage covers 480 original C lines and conservatively counts 420 translated
implementation lines. V owns fixed connection/storage/resource tables, filtering,
selector names, JSON emission and explicit temporary snapshots. Native Mach
reads, the pthread initializer and typed dyld interposition remain a small C
ABI adapter; the Objective-C resource hook and public header remain unchanged.
The shared core is generated during the build, with no maintained generated C.

The snapshots free their explicit allocations on failed reads, partial reads
and success. Table entries retain borrowed object identities; observation holds
the original mutex, and real driver hooks run after it is released, with the
grow hook retaining its original call-first order. Stack scratch tables remain
stack values and generated code imports no implicit allocator. These lifetimes
received independent review. The original permanent trace-stream ownership is
preserved; mocked Mach/driver calls do not verify private ABI behavior on Apple
hardware.

LinuxKPI allocation, formatter and logger implementations now live in
`compatcore/{runtime,format,printk}.v`. The 1,456-line original scope contains
405 lines of unchanged independent C diagnostics and 25 lines of fixture
scaffolding; excluding the entire 186-line native binding translations leaves
at least 840 original lines translated. Native C retains imported PCI tables,
Linux header access, `va_list` access and public variadic entry points. V owns
allocation metadata/rollback, formatting and pointer-key publication, bounded
owned log records, worker construction and draining. Host ASan/UBSan, public
headers and untouched upstream fixtures pass; both architecture builds and
ARM boot pass. The complete four-CPU x86 LinuxKPI guest passed every required
marker and exact free-page baseline, using kernel SHA256
`9edf46d7d6f29de1f101567887879526c566dd5cc6e1c00564b5736b22bc7135`.
New allocation and asynchronous record lifetimes received independent review.

Linux task state, clocks/conversions/timed sleeps and timer ownership now live
in `compatcore/{task,time,timer}.v`: at least 718 original lines out of the
1,071-line scope, excluding 312 original diagnostic lines and the entire
41-line native binding. `jiffies` and `jiffies_64` retain identical storage,
including the Darwin assembler alias. Public C integer arguments use `i32`;
task waits preserve locked unlinking, timer retirement waits until callbacks
finish, and detached worker ownership follows the original implementation.
The host sanitizer/alias fixtures, both builds and native guests passed with
the same fully tested LinuxKPI kernel recorded above; lifetime review passed.

Synchronization, SRCU and the workqueue engine now live in
`compatcore/{sync,srcu,workqueue}.v`. The 2,724-line scope retains 146 sync and
710 workqueue diagnostic lines byte-for-byte; subtracting all 164 native
binding lines gives at least 1,704 translated original lines. C bindings keep
Linux layouts/inlines and registered C wrapper addresses. V preserves FIFO
handoffs, locked stack waiter removal, acquire/release orders, reader banks,
grace periods, callback retirement, pool geometry, self-free work callbacks,
ordered/delayed/bound/unbound/priority/system queues and OOM rollback. Host
sanitizers, upstream/header checks, both builds and the full four-CPU guest
passed; every measured batch returned to its exact free-page baseline.
Independent lifetime reviews passed without changing diagnostic deadlines or
assertions. The tested kernel hash is the same `9edf46d7…22bc7135` above.

The shared kernel heap sampler now lives in `kernel/heapbench`, covering 334
original C lines with 273 translated workload/state/timing/kext-entry lines.
Native platform symbols and compiler metadata remain in its small ABI header.
Both platforms compile the same generated V artifact with the prescribed
genuine GCC flags; committed benchmark snapshots and independent C fixtures
remain intact. Build instructions settle the final kernel configuration before
replacing the sampler object with GCC, then relink without rebuilding it.

ASan/UBSan passed 674,496 allocation/free pairs, three-phase allocation and
zeroing failure cleanup, nonmonotonic-clock rejection and the kext entry ABI;
all 26 comparison validation tests passed. Both kernel architectures built
and the ARM boot guest passed. The x86 native sampler completed all three
phases and five samples with GCC 14.2.0, serialized `lfence`/`rdtsc`/`lfence`
instructions and checksum 27,358,432. Its frozen and ISO-extracted kernel
SHA256 is `1d36d30c4fb63886df8dd77f2f0e3124069d242726d87bc962ed53713f1e8cf5`.
Generated code has no implicit allocation imports; stack buffers and explicit
allocation rollback received independent lifetime review. The new sampler has
not been executed inside XNU; historical macOS benchmark captures are preserved
as evidence of their original C workload.

The boot/tools stage ports at least 1,712 original X11 bridge lines (1,808
original lines, excluding both complete C binding files totaling 95 lines and
one uncredited original header line), 731 ARM init policy
lines (811 original lines less 80 native assembly/restorer lines), 110 Wi-Fi
CLI lines and 557 EGL/GLUT sample lines. A separate 32-line GL C heredoc also
became a native V variant and receives no credit in this conservative tally.
Native headers/callbacks, fixed signal-safe state, terminal restoration,
process/descriptor ownership and protocol layouts remain intact. Build scripts
and content keys compile/hash the maintained V modules. Guest GCC rebuild
examples contain generated C artifacts alongside their V source and ABI header;
these artifacts are not committed as maintained implementation. Original C
implementations were removed after validation. Shared script commits exclude
another session's unrelated desktop app-link edits.

Independent host ASan/UBSan fixtures and original-C traces passed. X11 input
and Wine input/selection fixtures passed in both native architectures. Wi-Fi
passed eleven native device-model cases on each architecture. ARM shell,
full-userland and desktop init guests passed, including signal forwarding,
restart and adopted-child process-group retirement; nineteen unchanged
bootstrap assertions and seven content-key tests passed. Both kernel builds
remain covered by the preceding stages. The complete eight-case ARM Mesa
fake-G17 rendering/fence/resource/lifetime suite passed the V EGL binary with
an exact dependency image (ELF SHA256
`4c165b986d67c3230c6d6a75d3678c482379cc612ba8fef795fddacbfdcd15b0`). One
repeat hit an intermittent queue-destroy/retirement timing expectation inside
the unchanged ioctl fixture. The original C baseline and final unchanged V
pipeline both passed; the failure and comparison logs remain preserved. No
assertions or deadlines were weakened. Physical Apple graphics/Wi-Fi and
optional hardware init branches remain untested. New lifetimes received
independent review.

The top-level `kernel/c/*.c` inventory now contains 611 lines in ten native ABI
binding files, excluding `*_test.c`. Wait, mutex, task, time, timer, allocation,
formatter, logging, synchronization, SRCU, workqueue and heap-sampler algorithms
are maintained in V. The surviving C supplies Linux header/layout primitives,
native frame capture and variadic entry points; nanoprintf and imported Linux
remain unchanged. The exact current binding inventory is in
[kernel-v-migration-handoff.md](kernel-v-migration-handoff.md).

Final source reconciliation compared all 672 tracked kernel files on each
build tree against `db601f94` with no differences. Both final builds passed.
The final default x86 GCC-sampler guest passed all phases and reached userspace
with ELF SHA256
`13b771fb76e1e2f47976124d86639045027a15604e29482db58556844cc500a4`;
the sampler object remains byte-identical to the previously tested genuine
GCC object. The final ARM kernel SHA256 is
`945416243c26087a94243d3e47e370881afc3e3c6db2a8a544317c18cc33f7f6`.

The final ARM desktop plan completed all 44 required reports for
`ops,churn,cache,idle,apps,drag`; screenshots confirmed app launch and window
dragging. Two additional `ops,churn` rounds completed all 80 reports on each
of the final V and untouched `823aeb11` C kernels, with unchanged counts of
200 operations per case and 300 executions per program, one completion marker
per guest and no fixture errors.
The C comparison booted ELF SHA256
`54732d4b8094d88eb3b4c6c7896ebf1008d1ca884c5165f9a2a571add19ba6b5`
with the same image, desktop, compiler/dependencies and test fixtures.

Raw heap-class and large-page deltas match in 71 of 72 operation reports,
including all 36 warm reports. The sole difference is one additional 64-byte
object in the V cold `stat` snapshot. These complete runs do not establish
universally flat retention: both kernels retain 208 bytes per `mkdir`
(200 objects each in the 16- and 192-byte classes), and retain 180/160
16-byte objects per 200 `rename`/`rename_over` operations. Those patterns
match in both directories and both rounds, in unchanged VFS code. Churn
whole-machine residuals vary from 0–80 KiB on C and 16–48 KiB on V; no new
consistent per-operation object-growth pattern was observed. Raw residuals
remain recorded rather than being treated as zero or harmless.
`perf-final/final-validation-summary.json`, raw serial logs, screenshots and
the per-class comparison preserve the evidence. The missing-directory image
setup failure and an aborted firmware-only startup are recorded separately;
the completed comparisons keep the original firmware/configuration/assertions.

The required allocation-site check still fails against the existing allowlist.
An isolated check of unchanged starting revision `823aeb11` gives exactly the
same 158 rejected sites: 354 reported ARM sites, 293 x86 sites and 414 distinct
sites across architectures. Comparing site kinds and paths finds no additions
or removals. The opt-in production LinuxKPI V core reports zero allocation
warnings, and generated-code/import checks plus exact guest memory baselines
pass. The allowlist and assertions were not changed. Evidence is preserved in
`kernel-alloc-{sites,baseline-823,opt-core}.log` and
`kernel-alloc-baseline-compare.json` in the batch cache.

Linguist 7.27.0 at committed source
`db601f941aafd7a9335fd2b54cc3dfb41e12e468` reports **V 41.85%, C 23.71%**,
557 C files, 385 Python files and 283 shell files. The regenerated
[inventory](linguist-files.md) records committed blob bytes and the pinned
reproduction command. Every classified path and size was checked against Git
blobs; no Verilog or vendored trees appear. First-party C bindings and fixtures
remain counted honestly, and `.gitattributes` is unchanged by this batch.

Current local evidence is under
`/Users/alex/.cache/vinix-c-to-v/batch-next-10k-20261005-220015/`.
`progress.json` records stage counts and commits; frozen kernels, provenance
and serial logs identify the actual tested artifacts. These caches are local;
this document and the handoff are the durable record.


## First-party native boundaries and fixtures, 2026-10-06

The continued request now includes all maintained first-party C. Completed
ports since the preceding 10,191-line implementation batch remove another
**3,251 original production/native-boundary C lines**, **14,710 original fixture/benchmark
lines** and **258 header implementation lines** (111 desktop, 139 kernel and
eight Wi-Fi tool lines). A further 21 original stack-pointer/syscall/variadic
boundary lines now use instruction-only
assembly and receive no V algorithm credit. New tests, generated lvalue adapters
and archived evidence do not count as translations. The following stages are
committed and validated; pending stages are excluded.

| Completed scope | Original C lines | Commit |
| --- | ---: | --- |
| Allocation tracker native frame capture | 9 | `129c1f39` |
| Security native ABI boundaries | 257 | `49d01613` |
| LinuxKPI SRCU header/layout boundaries | 83 | `09de736d` |
| Console and formatting benchmark native entries | 76 | `987dbcc6` |
| LinuxKPI common header/refcount/per-CPU bindings | 54 | `d91f43b1` |
| LinuxKPI allocation/formatting/logging native bindings | 186 | `aa1d5bb8` |
| Desktop backtraces and EGL presenter | 572 | `a2fa1fac` |
| Apple boot reporter | 64 | `4d18ab71` |
| Venus availability probe | 41 | `a9f22eed` |
| Dota early client preload | 57 | `a55c5147` |
| ARM init raw syscall/signal boundary | 40 | `5dc7b03d` |
| AGX Darwin native tracing adapter | 55 | `06fd0680` |
| LinuxKPI task and wait native boundaries | 122 | `2103d3d8` |
| LinuxKPI workqueue native boundaries | 81 | `a774ab2a` |
| Dota low-mapping preload | 219 | `5115a9e7` |
| Steam 32-bit and 64-bit robust-list preloads | 179 | `032eaa2d` |
| QEMU VNC window client | 311 | `45f28820` |
| Android native runtime | 610 | `1d6730ac` |
| Xinput native launcher and Wine host boundary | 95 | `bea41f8e` |
| Office Windows PE API boundary | 123 | `7df94498` |
| Hello and native greeting builder entries | 17 | `47be3479` |
| **Production/native total** | **3,251** | |

Existing fixtures also became V: desktop execinfo 64 lines (`a2fa1fac`), AGX
tracing 108 (`06fd0680`), Dota maps parser 150 and mapping probe 131
(`5115a9e7`). The 111 desktop header lines are now generated from the real V
ABI. The independent GPU fixture added in `fe295797` is new coverage and earns
zero original-C translation credit. At these committed stages,
`kernel/c/*.c` has **zero maintained non-fixture files**; first-party C fixture
files and header algorithms still remain and must be ported. Genuine upstream
Linux, lwIP, nanoprintf, flanterm, musl and other libraries remain unchanged.

| Further completed fixture/header scope | Original C lines | Commit |
| --- | ---: | --- |
| Cache, i915 policy, PCI and common runtime independent fixtures | 1,118 | `3b3b131d` |
| Task, time, timer, synchronization, wound/wait, I/O and sequence fixtures | 1,582 | `cbb528e0` |
| ARM PCI controller fixture | 57 | `6b3769f2` |
| IPv6 native guest and common serial/smoke fixtures | 201 | `7dfa57c5` |
| Kernel callback/UART/counter and lwIP header algorithms | 37 | `6b3769f2` |
| LinuxKPI typed header helpers and generic exchange/CAS operations | 100 | `9f47270e` |
| Android ATL configuration fixture | 71 | `5a8e6928` |
| ACPI mutex/event native fixture | 206 | `18c49a10` |
| Hypervisor guest and ARM PCI init fixture (V portions) | 77 | `d5591540` |
| Hypervisor ABI fixture entry (V portion) | 5 | `5daec594` |
| Apple boot/converter independent fixtures | 168 | `c93d331c` |
| Apple SMC independent fixture | 536 | `9e09a18a` |
| Allocation tracker independent policy fixture | 72 | `283e8276` |
| Console independent policy fixture | 90 | `80ae43a1` |
| Remaining six LinuxKPI kernel fixtures | 2,687 | `33be42d7` |
| Native x86 console syscall fixture | 57 | `b3fdcb83` |
| Native allocation tracker guest fixture | 58 | `ac285e42` |
| Random host-hook fixture (V portion; three variadic boundary lines excluded) | 29 | `3d667aeb` |
| Native SMT policy guest fixture | 39 | `12854d0f` |
| Stack diagnostic independent fixture | 55 | `87d95202` |
| Real compiler-protected stack-frame oracle | 57 | `15048510` |
| Seven standalone LinuxKPI boundary fixtures | 199 | `f7ccc132` |
| ANS ext2 and platform independent fixtures | 268 | `2a19e1d2` |
| ANS controller/media original fixture scope | 815 | `34e728c4` |
| AGX recovered encoder independent fixture | 289 | `083cb12b` |
| Strict pathname/status-copy diagnostic guest | 46 | `6f506fd8` |
| AGX verifier/provenance independent fixture | 420 | `bbf1e243` |
| LinuxKPI pointer/preemption runtime header policies | 2 | `112e18aa` |
| Speaker independent transport/thermal fixture | 1,234 | `3ab257ae` |
| Raw stat exact-retention guest | 88 | `09d3db88` |
| Kernel sampler ownership fixture (three variadic boundary lines excluded) | 72 | `7ebf1a38` |
| Wi-Fi protocol independent fixture | 178 | `afa873f9` |
| Wi-Fi platform independent fixture | 80 | `3baf57e1` |
| Wi-Fi native control fixtures (one variadic line excluded) | 99 | `8c9ddf47` |
| Wi-Fi native tool header policies | 8 | `46ea29c7` |
| Portable allocation benchmark workloads | 419 | `5b37c952` |
| Large-I/O exact-page lifetime guest | 56 | `bc0b9a77` |
| Network randomness independent oracle | 320 | `b39872cf` |
| Memory primitive independent oracle | 107 | `42ed5d38` |
| Speculation policy independent oracle | 134 | `5ecc81c0` |
| Sparse page-table lifetime independent oracle | 193 | `439e6c12` |
| QEMU signal, first-touch and restart independent scopes | 241 | `fb74d12a` |
| Native clock-control independent oracle | 163 | `7ddfcb65` |
| QEMU interrupted nanosleep independent scope | 40 | `60f5c267` |
| SPI keyboard independent golden/PIO fixture | 564 | `558dc058` |
| SPI touchpad independent protocol/PIO fixture | 505 | `775f7f2a` |
| Native x86 poll independent fixture | 85 | `003f5861` |
| POSIX timer signal independent fixture | 230 | `ad82c434` |
| Display-hotplug independent oracle | 147 | `d21ed758` |
| Verified-boot standalone protocol fixture | 40 | `8b96b191` |
| QEMU blocked-thread exit/exec independent scope | 38 | `22c5d6ee` |
| QEMU pollfd ABI independent scope | 22 | `eecdee92` |

The hypervisor/PCI scope originally contained 86 lines; nine syscall boundary
lines use instruction-only assembly and receive zero V algorithm credit. Its
20-line ABI source retains six native static constraints in a declaration
header; only five entry lines receive V fixture credit. The four-line ACPI
include shim receives zero credit. Five duplicate Apple loader header helpers
(33 lines, `6c351501`) now call the previously existing V implementations;
retiring those duplicates receives zero new translation credit.

ACPI preserves the 4 × 1,000 mutex workload, task identity, event deadlines,
200 gates and exact 18-class residual assertions. Both actual ACPI guests,
both kernel builds, default x86 boot and ARM PCI coverage passed. The current
V library introduced unconditional POSIX backtrace includes despite
`-no-backtrace`; an unchanged ACPI_SYNC_TEST=0 control reproduced the build failure.
The kernel explicitly excludes that unused builtin. The compiler and vlib were
frozen together: V source `95136d4de1dabe575e37fc36b5a3e793580c8f72`,
binary SHA256
`335214a9c904435eb87e580948a7de76c2b4de03a65f0ee23babaa76981a7373`.
The displayed compiler version remains V 0.5.2 e690943 and does not identify
those changing library inputs by itself.

All six final LinuxKPI kernel fixtures passed the full host sanitizer/header/
upstream suite, both architecture builds and complete four-CPU diagnostics.
All 17 independent native fixture objects have no hidden allocator imports.
SRCU, worker and workqueue record layouts, real callback wrapper addresses,
stack-record lifetimes, wait cleanup and native variadic producers received
independent review. Every measured batch returned to its exact free-page
baseline. The tested LinuxKPI ELF SHA256 is
`4e82332380efae4a53e266b3f97a0ec41ca7efdc42569d17e363bf0e7dd94fd3`;
ARM is `265d6720e1cfe6068eb8e876b3e76253b7e3a0b34aa92584877d7e9327af746b`;
default x86 is `a2fa885a872028008f603c2f11cd25b202e6ccc6a79a7f716c6876ea3feb3fed`.
`fixture-final-source.json` pins base `9f47270e`, 788 source paths and 30
explicit owned changes, excluding other sessions' uncommitted source. The
first V guest failed the original worker test. An untouched-C fixture kernel
passed, then the identical frozen V ELF passed on repeat. All logs are retained;
the cause is unknown. Assertions, deadlines, worker tracing and exact memory
retirement rules remain unchanged.

The hypervisor fixture retains all 15 failure tags. Nineteen frozen-C/V model
cases produced identical stdout and exit status under ASan/UBSan, including
all five VM register/IO/HLT executions and failure paths. Both real native
hypervisor guests passed their absent-device path, and ARM PCI init passed.
Actual VMX entry still requires nested VT-x and is unverified locally. The
Darwin variadic ioctl model boundary uses native instructions; mock output
does not establish hardware VM execution.

Apple boot/converter fixtures passed ten binary goldens, 78 ABI field checks,
233 register-node cases and 410,739 memory cases under sanitizers, strict native
objects, loader cross-build and fake-iBoot QEMU. SMC retained all 122 assertions
in 27 cases and 32 explicit frees; frozen-C/V sanitizers and both native model
guests passed. Physical Apple boot and SMC operation remain unverified.

Tracker and console policy fixtures passed their original-C host baselines,
V ASan/UBSan workloads, strict native objects and both architecture guests;
console also passed both debug/production configurations. The actual
ALLOC_TRACK=1 kernel guest preserves all 16 checks, native scanf widths,
128 pipe pairs and descriptor cleanup. Original-C/V guests passed on both
architectures. One V ARM image stalled in firmware before any kernel marker;
the same immutable kernel/init passed with a fresh image. The x86 console
syscall fixture preserved all ten checks, errno/fcntl behavior and worker
collection; original-C/V native verdicts matched exactly. Tested tracker-kernel
SHA256 values are
`388fa8f702fd5e574610cb326f4e8948b3af669f750a6ac5f4602f72d98f6bdf` (ARM) and
`38fd754c28595bfc7a9285fea37cac46bf8624a4acdb4e4eb0f120e4ebe370d2` (x86).

Random host hooks preserve all GP/FP/long-double/overflow-stack variadic
arguments and native hardware-word state. Original-C/V sanitizer traces and
521-line native guest traces matched on both architectures. The native variadic
producer's three original lines receive zero V algorithm credit. SMT guest
original-C/V runs matched disabled/enabled topology policies on x86; the
unchanged production topology host test also passed. Stack serial diagnostics
passed original-C/V sanitizers and four native guest runs. The real canary
fixture passed actual Darwin ARM and Rosetta x86 protected frames, child exit
99 and LLVM checks requiring protected/non-inlined frames and unprotected
initialization/callers. That protected-frame fixture is host-only; no musl
startup placeholder assertion is claimed.

The seven standalone LinuxKPI fixtures passed both actual host architectures
under ASan/UBSan and the complete existing host suite. Their 17 native static
constraints remain intact. Pointer/preemption runtime policies passed 4,099
assertions on four configurations, both architecture builds/default guests
and the complete four-CPU compatibility guest with exact free-page equality.
Its ELF SHA256 is
`855a3a6d01baaf33b6ae6d22de119bef6a1abdae9ac8d0eeb9ddc63d7d31e839`.
Native compiler constant/type constraints receive zero algorithm credit.

ANS preserves all 11 ext2 and 27 controller/media cases, including 202 original
controller assertions. Original-C/V ASan/UBSan output matched; both native model
guests passed. Only eight documented, unexecuted ARM hardware bindings are
omitted in scratch providers; all exercised controller/media bytes are unchanged.
This establishes neither physical ANS operation nor production x86 support.
The transitional include changes are counted once within the frozen original
fixture scope; the unused native TYPE scaffold earns zero new algorithm credit.
SPI and speaker consumers now link the V platform provider (`e29fe952`), with
their original sanitizer workloads passing and zero additional translation credit.

AGX preserves all 16 encoder branch goldens, dense/appended hashes and all 32
encoder plus 41 verifier checks. Original-C/V ASan/UBSan runs passed on actual
ARM/x86 host ABIs; all eight native model guests passed. The verifier retains
one explicit 314-record calloc/free pair; generated output rejects hidden
allocator calls. Strict syscall diagnostics passed original-C/V guests on both
architectures with PROD=false and strict SMAP/PAN, retaining EFAULT checks,
valid stat/statx/getcwd and failed wait4 status-copy followed by retry/exit 37.
The debug ARM ELF is
`a10010c78606e25d469728452269c1aa432f553017a104d2cf93e24a2ab53b9a`;
x86 is `a741183dee9ec04a7879a4ab328a506b927e0d61faa850d1b0cdbce5cc95bb78`.
An earlier unrelated opt-in boot expired before userspace within the unchanged
180-second harness window; its logs remain retained. The default debug
comparison runs passed without changing that window. All new lifetimes
received independent review.

The speaker fixture preserves all 175 original assertions and 20 model groups,
with original-C/V ASan/UBSan parity on both actual host ABIs and both native
model guests passing every marker. Its two aligned DMA allocations retain their
original process lifetime, played storage grows through the original realloc,
and the expectation/played frees remain unchanged. Scratch providers omit only
eight documented unexecuted ARM hardware entries; every retained algorithm byte
is unchanged. Physical speaker operation remains unverified.

The stat-buffer guest retains all 32 source check sites (31 per architecture),
original line diagnostics, warmup, three 300-iteration cohorts and uninterrupted
6.1-second grace periods. Original-C/V native runs on both architectures produced
identical measurement/verdict lines, with every live class, slab page count,
large-page count and post-free counter exactly flat. Native scanf/printf widths
and synchronous stack borrows are preserved; no allocator imports were added.

The sampler ownership fixture preserves all 20 assertions, exactly 674,496
success allocations/frees, all three OOM and poisoned-zeroing positions, constant
clock failure and kext results. Original-C/V ASan/UBSan passed on both host ABIs;
all four native musl model runs passed. The sole explicit calloc/free pair and
bounded 16 KiB log capture remain. Three variadic capture lines use native
instructions and receive zero V algorithm credit. The five-line public C
declaration input is retired with zero algorithm credit; declarations now derive
from V exports and passed both SDK type constraints. The default production
benchmark's generated artifact remains byte-identical. The first V ARM image
stalled entirely in firmware; the identical kernel/init passed with a fresh
image and the same deadline. Its failure log remains preserved. These fixture
clocks provide ownership evidence, not comparative performance measurements.
Local receipts are `speakers-stage-validation.json`, `stat-buffer-validation.json`
and `sampler-fixture-validation.json`. All new lifetimes received peer review.

The Wi-Fi protocol/platform fixtures retain 98/29 assertions, 26/eight model
groups and 100,000 parser mutations. Original-C/V sanitizers passed on both
actual host ABIs; both native musl model guests passed. The native control
fixtures retain all 33 assertions/11 scenarios and match original-C host
return values and output; both native V guests passed. One original variadic
extraction line becomes native assembly and receives no V credit: these three
scopes remove 358 original C lines and credit 357 to V. Eight native tool
header helpers preserve all termios bytes, errno/TLS, volatile wiping and
stat/FILE contracts; all four native C/V boundary guests and both host
sanitizer runs passed. Native const callback correction `e89f3526` passed
both fresh kernel builds/boots and receives zero translation credit. No
physical Wi-Fi or firmware operation is established.

The portable allocation benchmark preserves six workloads, CLI behavior,
5–31 samples, odd/even medians, volatile payload accesses and the original
failure cleanup order. On each actual Darwin ARM/x86 host ABI, all 136
original-C/V controlled-clock/fault cases passed ASan/UBSan, including every
mixed-batch allocation-failure prefix. All four native C/V guests passed
with six results and final checksum 453. An end-to-end Vinix runner also
generated and compiled the artifact with genuine guest GCC 14.2.0 and passed
all six workloads. Its initial shared-artifact dynamic constant table stayed
zero because `_vinit` was not called; maintained V now initializes its
permanent fixed table once. That failure is preserved. Final help text adds
`-I .` to the generated-artifact build command; both SDK executable instruction
bytes remain identical. The evidence filename repair `944c12e1` preserves all
136 distinct output pairs per host ABI. Existing archived results remain
immutable; no new paired Vinix/macOS timing campaign or ratio is claimed.
Local receipts include `alloc-bench-validation.json` and the Wi-Fi stage
receipts. All new lifetime boundaries received peer review.

The large-I/O guest (`bc0b9a77`) preserves all 17 original check sites,
300 rounds of 65,536-byte transfers and byte checks, failed read/write-copy
EFAULT checks, three warm snapshots and seven-second settling. Both actual
host ABIs passed all 22 original-C/V fault cases under ASan/UBSan. All four
native C/V guests passed within their unchanged 240-second outer allowance:
ARM large pages stayed 46→46 and x86 stayed 132→132, with identical control
and V measurement/verdict lines. Generated output retains two permanent
buffers and native ULL stack records; both SDK objects have no allocator
imports. `big-io-validation.json` records peer lifetime review and immutable
kernels. This fixture-only stage does not establish the separate forced-vmap
self-test configuration.

The network-randomness oracle (`b39872cf`) preserves all 38 original checks,
64 literal SipHash answers, 16 offsets, 262,144 ID draws, the 32,768-datagram
reuse floor, 2,000 port picks, 30,000 three-way uniform draws and seven large
unsigned bounds. Its deterministic SplitMix64 provider and permanent ID/port
tables remain independent of the unchanged production V cores. All four native
C/V guests and both actual host sanitizer comparisons passed with identical
output. Signed callback context remains a synchronous stack borrow through
the actual C wrapper; generated static seed/enabled/vector initializers and
no-allocator imports were checked on both SDKs.

The memory primitive oracle (`42ed5d38`) preserves all 16 checks, original
alignment/overlap loops, eight byte values, all inclusive guard-page lengths,
zero-length protected pointers and 13 atoi cases. Actual host C/V ASan/UBSan
comparisons and all four native C/V guests passed: 410,739 cases on ARM's
16 KiB pages and 226,419 on x86's 4 KiB pages. Both original mappings are
unmapped before success. The identical production primitive instructions use
only general registers; an unused Darwin x86 math header is skipped solely
to retain the original x87/SSE restrictions.

The speculation oracle (`5ecc81c0`) preserves 21 original assertion expressions
and line numbers and all 6,144 independent CPUID/MSR combinations. Both actual
host C/V sanitizer comparisons and all four native C/V guests passed. Both
SDKs have identical C/V production provider instructions and no allocator
imports; CPUID outpointers remain synchronous stack borrows. The unchanged
original fixture trips GCC's signed-comparison warning under `-Werror`, so the
native x86 C/V pair uses Clang with the actual musl/GCC CRT SDK; no assertion
or warning policy was weakened. The new V fixture also passes strict native
GCC compilation. These three fixture stages reuse immutable ALLOC_TRACK
kernels, receive 561 original-C lines of credit, preserve the same C/V
3,600-second outer guest budgets, and add no new production or physical
mitigation claim. Local receipts are `net-random-validation.json`,
`memory-runtime-validation.json` and `speculation-policy-validation.json`;
all new lifetime boundaries received independent review.

The sparse page-table oracle (`439e6c12`) preserves all 45 original check
expressions and line tags, native signal-mask jump buffers, volatile fault
loads, pipe-synchronized fork/COW lifetimes and four reuse rounds. Both strict
SDK pairs and all four complete C/V native guests passed against immutable
ALLOC_TRACK kernels: ARM exercises the original 128 MiB/512 GiB probe addresses,
and x86 all four addresses through 256 TiB with LA57. Native IR retains the SDK's
`returns_twice` declaration and volatile byte/signal operations; no allocator
imports appear. This native VM fixture adds 193 lines, with no host sanitizer
or new kernel-build claim. `pagetable-validation.json` records peer review;
these targeted LA57 passes do not resolve other full `max`/TCG workloads.

Three separate QEMU fixture scopes (`fb74d12a`) add 241 original lines:
signals 77, first-touch 113 and syscall restart 51. All 61 original check
expressions and logical lines remain. Both actual host ASan/UBSan workloads,
both complete adapted SDK links and six paired native guests passed; each
architecture covers six signal, two first-touch child and three restart cases.
The native inputs retain the original reap helper body, with external linkage
only and zero extra credit. All 18 canonical fixture/oracle/control objects
match the guest-tested executable sections. Normal generation reads maintained
V only; immutable C recovery is confined to explicit oracle validation. The
source at that stage contained 3,180 original lines plus six integration lines.
The broader pending 270-line stage remains uncredited, including the untouched
original-C alarm failure. `qemu-scoped241-final-validation.json` records scope,
input identity, exact checks, cleanup lifetimes and independent review.

The clock-control oracle (`7ddfcb65`) adds 163 original lines, preserving all
53 checks, the native 208-byte timex layout/time offset 72, wall-clock and
uptime independence, privilege/securelevel rules, timerfd/POSIX timer ownership
and absolute sleep adjustment. Both genuine SDK builds have no allocator
imports; all four complete C/V native guests and the maintained ARM runner
passed with the unchanged 300-second budget. Original FD cleanup, timer deletion
and the 100×50-ms completion poll remain. The initial x86 setup omitted the
shared serial adapter; framebuffer
success and that failed harness attempt remain preserved before fresh identical
C/V serial-enabled controls passed. `clock-control-fixture/validation.json`
records peer lifetime review and reuse of immutable production kernels.

The separate interrupted nanosleep scope (`60f5c267`) adds 40 original lines,
including its signal counter and handler. All nine original check expressions
and logical lines, the one-second sleep, 20-ms interruption delay and native
volatile signal counter remain. Both actual host sanitizer ABIs, both strict
four-module SDK links and three paired native cases per architecture passed.
Normal builds use maintained V without recovering original C. That stage left
3,140 original lines plus ten integration lines; the broader
270-line stage remains uncredited. `qemu-nanosleep40-final-validation.json`
records the immutable inputs, cleanup/callback review and reused kernels.

The SPI keyboard (`558dc058`, 564) and touchpad (`775f7f2a`, 505) fixtures
preserve all 147/115 ordered assertion expressions and lines, 21/19 groups and
100,000 mutations each. Both actual host sanitizer ABIs, strict native SDK pairs
and all eight complete C/V native model guests passed with no allocator imports.
The full ARM production provider is unchanged. Private x86 providers omit only
five manifested, unexecuted ARM hardware entries; exercised algorithms remain
identical. `spi-{keyboard,touchpad}-stage-validation.json` records peer review.
A later whitespace-only fix (`1363af4b`) regenerated identical native code.
These model tests add no physical SPI operation or new kernel-build claim.

The x86 poll oracle (`003f5861`, 85) preserves all 29 original checks, 40-ms
sleeping, both 50-ms child writes, duplicate descriptor readiness, HUP and the
original 32/33-event limits. Strict musl GCC C/V builds and both complete native
guests passed against the reused default kernel. Fixed stack records retain
synchronous poll/read borrows and original reap/close order; no allocator
imports appear. `poll-validation.json` records peer lifetime review. This
x86/Vinix-specific fixture adds no ARM or host sanitizer claim.

The POSIX timer oracle (`ad82c434`, 230) preserves all 59 original check
expressions and lines, signal delivery, native union-sigval callback identity,
timer ownership and deadlines. Both strict SDK pairs, all four complete native
C/V controls, the maintained x86 runner and both generated caller-ownership
checks passed. It reuses the already validated default kernels with unchanged
300-second budgets. `posix-timer-fixture/validation.json` records peer review;
no production kernel change or host syscall simulation is claimed.

The display-hotplug oracle (`d21ed758`, 147) retains all 47 checks, cold attach,
unsigned counter wrap, zero debounce and non-1 C truth values. Both actual host
ASan/UBSan comparisons and all four strict SDK/native C/V controls passed;
production provider source and instructions match each pair exactly. State
remains a synchronous stack borrow, with no allocator imports. Peer review
restored the original diagnostic newline before final host/native validation.
`hotplug-validation.json` preserves the initial unsupported Darwin leak-sanitizer
setup and missing ARM kernel-directory attempt; actual address/undefined
sanitizers halt on errors. Physical CD321x/DCP operation remains untested.

The verified-boot fixture (`8b96b191`, 40) builds fresh standalone freestanding
ELFs for both architectures. Both C/V pairs preserve all 120 request bytes and
native volatile response/MMIO widths, with empty initialization and zero
unresolved runtime symbols. All 16 real Limine scenarios passed: accepted
handoff and rejected config, kernel and module tampering for each pair.
Five unchanged host policy tests passed too. `verified-fixture-validation.json`
records peer review, original 40-second budgets and pinned Limine 12.8.0 builds.
This bootloader fixture adds no production-kernel or Secure Boot enrollment
claim; the native tests ran with firmware authentication disabled.

Two further QEMU scopes port blocked-thread exit/exec (`22c5d6ee`, 38) and
pollfd ABI (`eecdee92`, 22). Both actual host sanitizer ABIs, strict SDK links,
complete maintained-only generators and paired native guests passed six blocked
and eleven poll input/failure cases. All two/ten original checks retain their
expressions and logical lines. The actual thread callback, permanent child
channel, 100-ms settling, exec/reap order, 32/16-bit poll fields and 1,000-ms
poll deadline remain. Retained reap/exec-probe helpers receive zero credit.
`qemu-{blocked38,poll22}-final-validation.json` records independent review;
3,080 original QEMU lines plus 14 integration lines remain at this snapshot.
The broader 270-line scope and complete host-model workload remain uncredited.

Native callback contracts (`03ad7bb3`, 18 paths) and const string/log-record
contracts (`e79802e4`, five paths) receive zero algorithm credit. They preserve
actual C-wrapper identity, field storage, ordering and ownership while matching
native function types. Both actual host halt-on-error sanitizer suites, strict
SDK ABI probes, both fresh default builds/boots and the opt-in build passed.
The composed four-CPU guest initially failed the unchanged I/O timeout/early/
signal group; the same immutable ELF then passed all 38 required groups, as did
a matching old-ABI control from committed `770ba039`. Both successful guests
returned all 16 measured batches to exact page baselines and emitted 25
no-pages-retained markers. The initial failure's cause remains unknown and its
raw evidence is preserved. Tested candidate ELF SHA256:
`8a657993816f5f0b04dd6bac7dcc99f1acfc882f42b3df0e16d2113b714938a0`;
control: `8c54e1fab6779abd29d3627b85a8f4032516fede7bcc75f4cdaf44afebcf4e83`.
`callback-const-production-validation.json` pins the frozen source and toolchain.

The kmod descriptor (`ad0ba5d0`) retires 29 metadata-only C lines with zero
algorithm credit. V owns the fixed 196-byte record; its generator promotes the
compiler's aggregate and two literal arrays to static loader-visible data.
Every native offset, four-byte alignment and both actual start/stop relocations
match the original. ARM/x86 Mach-O objects and the complete linked x86 kext are
byte-identical C/V; both strict musl SDK data/import checks passed. The sampler
is unchanged. `kmod-info-validation.json` records independent review and the
limits: no new genuine Darwin GCC compilation or kext execution was performed.

Native integer constant-expression metadata (`0fe3679c`) preserves all 4,099
assertions, arbitrary native integer widths and single evaluation, with zero
V algorithm credit. Both fresh default builds/boots and the full host checks
passed. Its initial compatibility guest failed the unchanged SRCU deadline;
an exact original-header control had identical executable instructions in
all 105 linked objects and 161 archive members and passed. The identical V
ELF then passed the complete guest with exact page equality. The unresolved
failure, control and repeat remain recorded. The separately committed
high-byte string correction (`bc9a5ea4`) passed signed/unsigned-char original-C
regressions on both host ABIs, both fresh builds/boots and the complete
four-CPU compatibility guest with exact page equality; its tested ELF is
`0076705124da9532dee648347d28941f027d09b58d4f6c5dba6140aa8fcd2d01`.
It receives zero additional port credit.

At committed source `eecdee9228db3dc5edffe0bb8e3a9d4088c2fa17`,
`kernel/c/*.c` has zero maintained first-party files, including fixtures.
The non-vendored `.c` census still contains 166 test paths / 40,555 lines,
including genuine patched musl evidence. Maintained first-party host/native
fixtures and header algorithms remain to port; zero kernel C is not completion
of the repository-wide request. This census is not a translation tally. The
concurrent IRQ diagnostic added nine C guest-init lines; they receive no
translation credit.

The first kernel-fixture guest failed the unchanged i915 device-encoding
condition. Its cause was signed literals passed to the foreign `MKDEV` macro:
V's foreign declaration metadata did not convert the generated C literals.
Explicit `u32` arguments restore the original unsigned inputs, including the
`0xabc` major-number case. The corrected full host suite, both builds and full
four-CPU guest passed. No expected values or deadlines changed.

The next seven fixtures and header helpers passed the full host sanitizer,
standalone-header and upstream tests, both architecture builds, default x86
boot, ARM ECAM/full-DAIF vectors and the complete four-CPU LinuxKPI guest.
Every measured native batch returned to its exact free-page baseline. The
LinuxKPI ELF SHA256 is
`195c83c50c0d295da8e510b8046a946ac071fa73cf6ce9ed2be3f33bad4636cd`;
ARM PCI ELF is
`638c983715bb1d51a3fe00901a79cb0e4dcf355b7d183545b3c55beacb0c156d`;
default x86 ELF is
`bcfec8fd702ac3697ea3f65bd13c6a04edbf7df00c18b869d42f3f9657b63d9c`.
The source snapshot pins committed source plus 763 exact source hashes,
excluding another session's uncommitted user-copy changes. Its first accidental
mixed snapshot failed default x86 compilation; that attempt remains preserved
and is not validation of this migration.

Header differential checks preserve 10 bounded UART traces, 256 actual native
callback invocations, stack alignment and counter ordering. Optimized ARM
counter access is `isb; mrs CNTVCT_EL0; ret`; the stack helper is the
instruction-only `mov x0, sp; ret` leaf. lwIP callbacks retain their exact
registered pointer bytes and borrowed lifetimes. Both architectures passed
500 socket/netlink exchanges with every measured class unchanged and zero slab
byte growth. The V IPv6 fixture retains all 50 original assertions and their
preprocessed diagnostic line numbers; its verdict and class measurements are
byte-identical to the frozen C fixture on both architectures. Native V PID1,
fork/COW, wait and mmap smoke guests also passed on both architectures.

LinuxKPI's generic exchange/CAS handles 8/16/32/64/128-bit native operands,
pointers and signed/volatile values. V owns the atomic operations; generated
native adapters preserve one-time operand capture, type/domain checks and
original IRQ flag-lvalue evaluation order. The 13 IRQ sequencing lines and
other generated type-capture scaffolding receive zero V algorithm credit.
The independent 20-case differential oracle and native 128-bit fixtures passed
on both architectures. Dormant 128-bit code retains the original upstream
`libatomic` requirement without adding those imports to ordinary kernel links.

Android original-C/V host sanitizers, strict native builds and both architecture
musl guests passed, including readonly 128-thunk data, real pthread layouts,
stack/memory/atfork/fortify/statistics behavior and hidden-symbol checks. The
pinned patched musl statistics provider is required; an earlier stale provider
failed the original C before V. Xinput/Wine original traces, host sanitizers,
both native architecture mock guests and the actual ARM X11 production links
passed. The unchanged x86 full X11 link needs the baseline's external libbsd
resolution. Office retains all 33 native Win64 exports and passed 1,024 rounds
of 40 null/output combinations under host sanitizers. Both actual SDK PE
fixtures executed under translated Wine and returned their unique success
code 73; exit zero without execution fails the strengthened runner. Earlier
Wine NLS-layout setup failures remain recorded. Full Office/APK UI operation
was not rerun.

The immutable benchmark evidence archive (`7ee28d8e`) removes 108 frozen
first-party/generated C snapshots totaling 75,192 lines from maintained source,
along with two frozen shell builders and an embedded init. This is archival
work, **not a C-to-V port**. Its manifest pins exact commit, path, blob,
SHA256, byte count and file mode; the materializer reconstructs the original
bytes outside the checkout and rejects path escapes, tampering and overwrites.
All 145 manifest records were verified, all 510 campaign integrity assertions
passed and three recomputations were byte-identical. The 34 genuine patched
musl snapshots remain preserved as upstream evidence.

Kernel native boundaries preserve actual C wrapper callback identities,
borrowed Linux layouts, acquire/release operations, tick alias identity and
variadic native widths. ABI assembly contains architecture instructions;
V owns algorithms and ownership. Both architectures built in isolated
worktrees. Tracker/console native guests passed, and the complete four-CPU
LinuxKPI guest passed after the runtime/SRCU/common stage and again after the
task/wait/workqueue stage with exact free-page equality in every measured
batch. The latter tested x86 ELF SHA256 is
`3b6164b1853caa8adac1aceca0a32d32a22b6023f83fbf2cf43c4104d9783399`;
its ARM counterpart is
`86860faa0b4fa595eb53b5ce1d551e0d5c8bd323ae6b593631e9a30c5a20c179`.
The first full guest hit the original timer watchdog/count check. The closest
untouched C-boundary kernel passed, then the identical frozen new ELF passed
on repeat. The original failure and both comparison logs are retained; host
delay is a possible explanation, not an established cause. No diagnostic
assertions, retirement requirements or deadlines changed.

Desktop backtrace host ASan/UBSan fixtures, native ARM/x86 guests and an x86
frozen-C guest passed. The presenter passed 67 host failure/lifetime cases and
32 repeated lifecycles with zero remaining mocked resources, using ASan,
UBSan and stack-use-after-return checks. Full static desktop links passed on
both architectures using genuine GCC; the ARM dynamic Mesa link passed too.
All six native `idle,apps,drag` scenarios passed (two rounds, 45 seconds each,
15 seconds settling). The borrowed GL vertex storage remains permanent;
caller-freed symbol arrays use one contiguous explicit allocation. Physical
Apple graphics remains unverified.

The Dota early preload passed nine original-C/V sanitizer cases and both
native guest fixtures. Its copied path survives environment removal and its
NODELETE reference retains the original process lifetime. The mapping preload
passed 24 parser cases across 257 chunk boundaries, all 50 original probe
conditions and both architecture model guests. The actual patched ARM-host
translator passed C/C, C/V and V/V runs. An unpatched translator failed the
original C MAP_FIXED_NOREPLACE/partial-host-page condition; that setup failure
is retained separately. No assertions were weakened.

ARM init passed all three native boot policies and all six required markers,
four feature combinations, both echo host fixtures, callback-address and
volatile-storage checks, and strict syscall/restorer disassembly checks. The
first guest reached its markers but ran out of host disk while saving evidence;
only the completed repeat is claimed as PASS. Steam passed frozen-C/V host
sanitizers, 16 concurrent workers each doing 1,000 mapping/unmap cycles, native
32/64-bit layout/export checks, and all four original-C/V translated guest
variants. The i386 table retains 512 borrowed mappings, original saturation,
overflow and failed-unmap behavior; its spin loop retains the optimized branch.
Its instruction-only variadic bridge preserves all six syscall arguments.
Neither Steam shared library imports an allocator.

VNC passed 34 exact original-C/V sanitizer outcomes covering protocol bytes,
partial/EINTR I/O, resize, pointer/key events, descriptor cleanup and XImage
ownership. Both native mock guests and the actual ARM X11 production link
passed. Its sole explicit calloc and XDestroyImage ownership match the original.
Security, Apple reporter, Venus and AGX native adapters passed their relevant
host and native fixtures; physical Darwin/Apple operation remains untested.
All new lifetime boundaries received independent review.

Current machine-local evidence is under
`/Users/alex/.cache/vinix-c-to-v/firstparty-only-20261006-011023/`.
Snapshots, ELF hashes and full serial logs identify tested inputs. Completed
disposable image files may be retired after recording their hashes; their
manifests and logs remain. This document and the handoff are the durable record.

Linguist 7.27.0 at committed source
`eecdee9228db3dc5edffe0bb8e3a9d4088c2fa17` reports **V 71.68%, C 5.90%**,
469 C files, 492 Python files and 285 shell files. All 2,588 classified blob
identities and sizes were checked against Git, including every inventory row.
No Verilog or vendored trees appear and `.gitattributes` is unchanged.
Concurrent commits include an 18,008,664-byte `desktop/font_data.v` blob;
these graph percentages describe the whole pinned revision and are not a
measure of this port batch. Archived source and duplicate-helper retirement
receive zero new port credit; first-party fixtures and headers remain counted
honestly.

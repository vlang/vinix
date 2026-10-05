# Kernel C to V migration

The [next-session handoff](kernel-v-migration-handoff.md) lists the remaining
implementations, build/test setup and porting constraints from the latest batch.

Port first-party implementations in small stages, preserving their external
interfaces. Keep third-party libraries, their C headers, and independent C
test callers. Generated C from V is a build artifact, not maintained source.
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
| Linux driver compatibility | LinuxKPI runtime, synchronization and work queues | Pending |
| Benchmark and allocation instrumentation | Kernel benchmark and allocation tracking implementations | Pending |

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

## Next batch, started 2026-10-05

The continuation starts from `823aeb116eb3b3ab20463ccb9b1c3fba6f0c41ae`.
That revision has 6,488 lines in 16 top-level kernel C files, including the
54-line existing Linux header binding. Embedded native diagnostic fixtures
remain independent C callers and are recorded separately from translated
implementation lines. The requested approximately 10,000-line scope extends
beyond the remaining kernel implementations; subsequent stages are in progress.

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
`apple-boot/vcore/tree.v`. The public C headers and independent converter
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

LinuxKPI wait-bit and wound/wait stage moves 426 original C lines into
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

This stage covers 869 original C lines and conservatively counts 665 translated
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
1,071-line scope, excluding 312 unchanged diagnostic lines and the entire
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

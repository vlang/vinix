# Kernel C to V migration

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
| VMX architecture helpers | VT-x controls, FPU state, descriptors and selector reads in V; exact VM entry/exit in assembly | Committed as `0e4bee84`; host C ABI/sanitizer tests passed 7,680 control cases and all ARM no-op exports with no allocator imports; optimized x86 ports preserved CF/ZF capture, operand order and memory clobbers; all 214 VM-entry instruction bytes matched both the original host and kernel objects; both architecture builds and QEMU boot/syscall guests passed; x86 linked retpoline scan passed |
| SMC protocol core | Read-only RTKit boot, bounded mailbox transactions, capacity/power caching and text formatting | Committed as `e6f0ed1d`; 27 unchanged host fixtures passed against the V C ABI under ASan/UBSan with no allocator imports; both architecture builds and QEMU boot/syscall checks passed; physical Apple firmware remains untested |
| AGX G17 verifier | Stream layouts, golden writes, descriptor resources and permitted VM bindings | Committed as `dddf4cf0`; existing C ABI verifier/encoder and V descriptor fixtures passed with ASan/UBSan and no allocator imports; both builds and boot/syscall guests passed; ARM QEMU Mesa passed depth, stencil, combined rendering, completion and adversarial GEM/VM lifetime checks using matching staged Mesa libraries |
| AGX G17 encoder | Recovered producer graph, unsigned expression evaluation and register stream emission | Committed as `7f935437`; independent verifier/encoder fixtures, ASan/UBSan, allocator imports and three generator tests passed; both builds passed; ARM QEMU Mesa passed all eight render/lifetime cases, x86 boot/syscall guest passed; generator now emits V directly |
| Classic ext2 | Byte-oriented reads, bounded mutations, dirty/clean mount transitions and preserved C ABI | Independent ext2 and ANS media fixtures passed with ASan/UBSan and no allocator imports; both builds and QEMU boot/syscall guests passed; Apple SSD hardware remains untested |
| Network and Apple drivers | lwIP bridge, ANS, SMC, speakers, keyboard, Wi-Fi and GPU helpers | Pending |
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

The next batch covers 9989 lines from the following original C
implementations, measured before any ports in this batch. Independent C
fixtures and third-party code stay in their existing languages. Each finished
stage is committed after host tests, both architecture builds and QEMU checks.

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

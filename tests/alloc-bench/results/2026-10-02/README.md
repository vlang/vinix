# Allocation measurements, 2026-10-02

The shared GCC C kernel workload was run in actual Vinix and macOS Catalina
QEMU guests with matched CPU, RAM, machine and TCG settings. Across all three
recorded cohorts, the optimized Vinix kernel took **21% less time for hot
64-byte pairs, 43% less for mixed slab batches, and 54% less for 256 KiB heap
pairs** than the original Vinix implementation, using pooled sample medians.
Its median was below Catalina's in all three kernel workloads. The original
Vinix kernel's pooled medians were also below Catalina's.

The completed user-space benchmark gives a different result: Vinix remains
slower in **five of six** workloads. These results do not establish that every
Vinix allocation is as fast as macOS. User-space `malloc`, VM policy and kernel
heap allocation have different costs, and these are emulated measurements
with substantial host scheduling noise.

## Direct kernel results

Every number below is TSC ticks per **allocation/free pair**. A lower value is
better. The median pools **all 15 measured samples** from three cohorts;
minimum/maximum ranges retain every sample. No cohort or outlier is discarded.
Each cohort has five samples and one full, untimed warmup per phase.

| Phase | Pairs/sample | Original Vinix | Optimized Vinix | Catalina XNU | Vinix reduction | Optimized Vinix/XNU |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `hot64` | 100,000 | 3,844.790 | 3,032.250 | 13,532.760 | 21.13% | 0.224× |
| `mixed256` | 12,288 | 18,763.184 | 10,634.521 | 27,638.265 | 43.32% | 0.385× |
| `big262144` | 128 | 1,756,093.750 | 805,585.938 | 8,818,304.688 | 54.13% | 0.091× |

| Phase | Original range | Optimized range | Catalina range |
| --- | ---: | ---: | ---: |
| `hot64` | 2,083.060–5,715.200 | 2,152.960–4,397.660 | 4,586.520–18,787.500 |
| `mixed256` | 4,000.732–44,668.620 | 5,939.779–29,003.662 | 6,285.400–54,560.547 |
| `big262144` | 1,604,843.750–2,538,390.625 | 378,250.000–1,506,554.688 | 4,512,453.125–24,567,226.562 |

The per-cohort medians make the variation visible. Cohort numbers identify
recorded invocations; they do not imply that the two OS measurements were
simultaneous or that the host load was identical.

| Phase | Cohort | Original Vinix | Optimized Vinix | Catalina XNU |
| --- | ---: | ---: | ---: | ---: |
| `hot64` | 1 | 3,388.650 | 2,794.440 | 18,199.880 |
| `hot64` | 2 | 3,830.780 | 3,288.490 | 15,003.290 |
| `hot64` | 3 | 5,133.330 | 3,436.130 | 5,314.580 |
| `mixed256` | 1 | 23,628.499 | 9,004.150 | 43,631.510 |
| `mixed256` | 2 | 17,564.860 | 11,868.652 | 27,638.265 |
| `mixed256` | 3 | 14,924.154 | 13,082.438 | 20,499.674 |
| `big262144` | 1 | 2,185,632.812 | 707,250.000 | 21,058,101.562 |
| `big262144` | 2 | 1,627,164.062 | 813,187.500 | 8,818,304.688 |
| `big262144` | 3 | 1,985,820.312 | 961,757.812 | 5,600,500.000 |

`hot64` reuses one 64-byte allocation. `mixed256` allocates 256 simultaneous
objects covering all fourteen Vinix slab classes
(16, 32, 48, 64, 96, 128, 192, 256, 384, 512, 768, 1024, 1536, 2048 bytes),
then frees them in a permutation, for 48 rounds. `big262144` allocates and
frees 256 KiB, exercising physical-page allocation and poisoning.

The exact shared source is [heap_benchmark.c](../../../../kernel/c/heap_benchmark.c).
Vinix calls its kernel `malloc/free`; the macOS diagnostic kext calls actual
XNU `kern_os_malloc/kern_os_free`. Warmup verifies **every requested byte is
zero** on both guests. Timed samples write and verify payload endpoints.
Expected checksums are 25,486,688, 1,855,488 and 16,256, with final
`KALLOC-DONE checksum=27358432`; all runs passed. This is an actual macOS
kernel measurement, not Vinix's optional XNU-inspired allocator backend.

Vinix runs on its boot CPU before its scheduler starts; macOS runs from a
loaded kext with its scheduler and interrupts active. Vinix cohorts are fresh
boots; macOS cohorts are three loads of the same kext in one boot. QEMU TCG
TSC ticks include emulated execution and host scheduling; they are **not
native CPU cycles**. Other sessions performed heavy builds during the Vinix
measurements. The large ranges, particularly on macOS, limit the confidence
of precise speed ratios and prevent extrapolating to native machines.

## Completed user-space results

[bench.c](../../bench.c) compiled natively with GNU GCC in both guests. Each
workload has seven samples after a full warmup. The hot and mixed workloads
use 200,000 pairs/sample; the other workloads use 10,000. Table medians are
recomputed from all raw samples and expressed in nanoseconds per pair.
Vinix uses the optimized kernel.

| Workload | Vinix ns/pair | Catalina ns/pair | Vinix/Catalina |
| --- | ---: | ---: | ---: |
| `malloc_hot_64` | 1,100.000 | 544.900 | 2.019× |
| `malloc_mixed_batch_64` | 10,135.000 | 1,068.285 | 9.487× |
| `malloc_touch_262144` | 839,700.000 | 25,669.400 | 32.712× |
| `mmap_anon_4096` | 61,000.000 | 45,642.400 | 1.336× |
| `mmap_touch_262144` | 819,400.000 | 2,920,654.100 | 0.281× |
| `pipe_create_close` | 103,400.000 | 70,996.200 | 1.456× |

A ratio above one means Vinix took longer. The malloc rows compare musl with
Apple's libmalloc, including their caching and mapping strategies; they do
not directly time the kernel heap. This benchmark does not isolate libc
caching from the cost of obtaining or releasing mapped storage. Vinix
pre-populates these small anonymous mappings, whereas XNU can defer physical
allocation to faults. The untouched/touched mmap rows therefore measure
different VM policies as well as mapping, fault and teardown costs. Pipe
creation also includes syscall and object lifetime costs.

Both guests report 4 KiB pages. Vinix's reported monotonic clock resolution is
1 ms versus Catalina's 1 µs; the longer sample counts reduce quantization.
Raw ranges are preserved, including Catalina's touched-mmap range of
2,368,308.6–5,134,449.6 ns/pair. There is no complete matched original-Vinix
user run, so this report makes no user-space before/after speedup claim.

## VM and build provenance

The common settings are identical **within each comparison group**:

```text
QEMU 11.1.1, x86_64
-machine q35,vmport=off
-accel tcg,thread=single,tb-size=1024
-cpu Penryn,kvm=on,vendor=GenuineIntel,+ssse3,+sse4.2,+popcnt
-m 4096
```

Direct kernel tests use `-smp 1,sockets=1,cores=1,threads=1`; user-space tests
use `-smp 2,sockets=1,cores=2,threads=1`. One vCPU avoids Vinix's secondary CPU
spinning before the scheduler during its boot-time sampler. Firmware and
boot devices differ: Vinix uses Limine, while Catalina uses OpenCore and an
Apple SMC device. No `-icount` setting was added. The two benchmark guests
were timed sequentially; the owned macOS VM was paused for Vinix timing.
Other activity on the shared host was not stopped.

The actual macOS guest is **Catalina 10.15.7 (19H15), Darwin 19.6.0,
XNU 6153.141.2.2~1**. The available local source tree
`third_party/xnu-12377.121.6` is from macOS 26.5 and is **not the guest's
kernel version**. These results compare the available Catalina installation,
not current macOS. The private VM clone booted in single-user mode with SIP
disabled for the diagnostic kext; the reference VM and disk were preserved.

Vinix uses GNU GCC **14.2.0** and macOS GNU GCC **14.3.0**. Their minor versions
differ and can affect generated code. `/usr/bin/gcc` on the host is Apple
Clang and was not used as the GNU compiler. On macOS, **native guest GCC
compiled C to assembly**; because the guest lacked Apple's development
tools, the host's Apple assembler/linker produced x86_64 macOS 10.15 binaries.
The binaries ran only in the guest. The manifests preserve exact commands,
SDK selection and binary/assembly hashes. Both kernels themselves retain
their normal build toolchains; the shared timed C sampler is the translation
unit compiled with GNU GCC on both targets. The Vinix kernel used
V 0.5.2 `0dc6a69` and Apple Clang 21.0.0 for its remaining sources.

User-space common flags are:

```text
-std=c11 -O2 -Wall -Wextra -Werror -fno-builtin
```

Direct-kernel common flags additionally are:

```text
-ffreestanding -fno-stack-protector -mno-red-zone
-mno-80387 -mno-mmx -mno-sse -mno-sse2
```

Target-specific kernel compilation/assembly/link flags are recorded separately.
The frozen original kernel comes from isolated base
`8aa224cacccd031ef3937ea0ae2552ad6a8fdaa3` plus the benchmark plumbing/repair;
the candidate comes from
`173788fad5c06be8e8ad2d950b58cc540621166f` plus the same sampler plumbing and
allocator optimization. The intervening commit repairs benchmark declarations
and serial output, without changing the allocator. Unrelated concurrent
checkout edits were excluded from these frozen measurement builds.

| Artifact | SHA-256 |
| --- | --- |
| Shared user C source | `bd4a0d74f4f1e8d079d55877f8e90925e2622ce990120b54573a5dc94a9a54b9` |
| Shared schema-3 kernel C source | `663fad012d9f55aba73953737bacf245189eafcf784a292d46e2d0a67643d064` |
| macOS kmod descriptor source | `6e49ff7798e4661aad363a3cfd9b2f8cd6c4c39d04001758fa25bbc0b7802b35` |
| Original direct-kernel Vinix binary | `82044d1d58a15730c48400186eeadd1c6e8b432c14a49ebcc4ade75479c243c2` |
| Optimized direct-kernel Vinix binary | `f52a38f7cffddae8f21491f5944a3fa90f95e9475efe3f0400487749be6e9aad` |
| Optimized user-test Vinix kernel binary | `ed7cffaa5cae78dfedb16c81ab160effead02e3d19533689dd668ebbad07ad1d` |
| macOS diagnostic kext binary | `c0e647139d1a299c347fb34f34185b69c798f16582b087bdd3ca3a6e9ca65bc7` |
| macOS user benchmark binary | `aed1e90c728e56b77cbff31c62277eb80762b9a0f54b02e815ce581913352b97` |

## Optimization and validation

The optimization captures the physical allocator's zero/poison word counts
before each fill loop, rather than reloading aliased global page geometry on
every store. Slab free poisoning uses whole 64-bit words for validated,
16-byte-aligned slots and class sizes, replacing the generic byte fill on
this hot path. The generated x86_64 code uses unrolled scalar word stores.
Zero-on-allocation, `0xaa` free poisoning, poison checks, locks, reference
counts and slot-publication order remain enabled. The generic kernel
`memset` implementation and allocation lifetimes are unchanged.

The allocator change is committed as
`b6103e92ec8157668f476d32a58db42f8ebef0b0`. The kext packager's source snapshot
fix is `f4ea2e4d9a7ad28a1d57f8702a618d2a01350d4a`; its rebuilt kext hash
matches the guest-tested binary. The [exact allocator patch](validation/allocator.patch)
and [production integration build manifest](validation/integration-build.json)
reproduce the tested change on base `f4ea2e4d`.

Validation completed:

- Clean production builds passed on **x86_64 and aarch64** with the committed
  allocator change. The integration manifest records compiler commands,
  patch hash, successful exit codes and both resulting kernel hashes.
- Actual QEMU core suites passed on **both architectures**, including
  joined-thread reclamation; ARM also passed a second boot verifying
  persistence. Both kernels enabled `heap_selftest`. Its success message goes
  to the framebuffer; the actual ARM ELF's
  [initialization disassembly](validation/arm-pmm-init.asm) calls the selftest,
  and both ARM boots subsequently reached init and completed the core suite.
- Desktop **idle, apps and drag** completed one short smoke round each.
  These runs verify boot and interaction; they are not a before/after desktop
  performance comparison.
- All **43 comparator tests** passed. Every primary measurement passed its
  strict comparator, including common VM settings/source/flags, sample
  counts, payload checksums and completion records. Independent reviews
  confirmed unchanged lifetimes, lock order and zero/poison coverage.

**The allocation-site audit did not pass and remains incomplete.** Baseline
and candidate both failed with 155 existing allowlist mismatches. Both report
361 ARM sites (V exit 0) and 253 x86 sites (V exit 1), or 425 combined unique
reported sites across 182 file/kind pairs. The normalized reported count
delta is empty, but this is a diagnostic comparison, not a complete audit.
The x86 audit snapshot fails to import `drm.simple` and reports incompatible
`MappingLifetimeResource`/`MappingAttributesResource` interfaces. The relevant
sources and makefile are byte-identical to the unoptimized baseline. Normal
production builds and runtime tests passed; the audit uses a different
warning-report snapshot. The allowlist was not changed to hide these failures.

[Verification details](validation/verification.json) preserve exact commands
and statuses. Supporting records include [x86 core](validation/core-x86_64.log),
[ARM core and persistence](validation/core-aarch64.log),
[ARM build manifest](validation/arm-build.json),
[desktop log](validation/desktop-smoke.log) and
[desktop results](validation/desktop-smoke.json),
[baseline audit](validation/alloc-audit-baseline.log),
[candidate audit](validation/alloc-audit.log),
[audit comparison](validation/alloc-audit-comparison.json), and a
[verbatim x86 diagnostic error excerpt](validation/audit-diagnostic-x86-errors.txt).
The excerpt records the full diagnostic's hash; preceding compiler warnings
are omitted. Full production/ARM compiler warning logs are also omitted;
their original filenames remain in the unchanged build manifests.
Actual production slab-free disassembly is preserved for
[x86_64](validation/integration-slab-free-x86_64.asm) and
[aarch64](validation/integration-slab-free-aarch64.asm), showing scalar word
stores; the [selftest candidate ARM disassembly](validation/arm-slab-free.asm)
provides the same check for the booted binary.

## Records and reproduction

All copied logs and JSON manifests below are unchanged from their run
directories. The direct Vinix manifests record the actual kernel SHA-256;
the build records bind those hashes to the GCC sampler and kernel build
commands. Recorded configuration fields are checked for agreement; a
manifest by itself cannot authenticate a binary's full provenance.

| Group | Raw records and manifests |
| --- | --- |
| Original kernel Vinix | [build](kernel-vinix-before/build.json), [run 1](kernel-vinix-before/run-1/serial.log), [config 1](kernel-vinix-before/run-1/config.json), [run 2](kernel-vinix-before/run-2/serial.log), [config 2](kernel-vinix-before/run-2/config.json), [run 3](kernel-vinix-before/run-3/serial.log), [config 3](kernel-vinix-before/run-3/config.json) |
| Optimized kernel Vinix | [build](kernel-vinix-after/build.json), [run 1](kernel-vinix-after/run-1/serial.log), [config 1](kernel-vinix-after/run-1/config.json), [run 2](kernel-vinix-after/run-2/serial.log), [config 2](kernel-vinix-after/run-2/config.json), [run 3](kernel-vinix-after/run-3/serial.log), [config 3](kernel-vinix-after/run-3/config.json) |
| Kernel Catalina | [run 1](kernel-macos-1/serial.log), [config 1](kernel-macos-1/config.json), [run 2](kernel-macos-2/serial.log), [config 2](kernel-macos-2/config.json), [run 3](kernel-macos-3/serial.log), [config 3](kernel-macos-3/config.json) |
| User Vinix | [run](user-vinix/serial.log), [config](user-vinix/config.json) |
| User Catalina | [run](user-macos/serial.log), [config](user-macos/config.json) |

The [long original-Vinix user run](excluded/user-vinix-before/serial.log)
([config](excluded/user-vinix-before/config.json)) timed out after 600 seconds,
with four completed workloads and only three samples of the fifth. It lacks
`ALLOC-DONE` and is excluded from all primary tables. The earlier
[schema-2 macOS kernel log](excluded/kernel-macos-schema2/serial.log)
([config](excluded/kernel-macos-schema2/config.json)) has a metadata line
truncated by `IOLog`'s line-length limit and is also excluded. Schema 3 emits
three short metadata records; all primary kernel logs include complete
metadata and `KALLOC-DONE`. No missing records were reconstructed.
The user Vinix console also contains an earlier schema-2 boot-time kernel
sampler; only its complete `ALLOC-*` user-space records feed the user table.

From the repository root, validate the preserved comparisons:

```sh
python3 tests/alloc-bench/compare.py \
  tests/alloc-bench/results/2026-10-02/user-vinix/serial.log \
  tests/alloc-bench/results/2026-10-02/user-macos/serial.log
for run in 1 2 3; do
  python3 tests/alloc-bench/compare-kernel.py \
    tests/alloc-bench/results/2026-10-02/kernel-vinix-before/run-$run/serial.log \
    tests/alloc-bench/results/2026-10-02/kernel-macos-$run/serial.log
  python3 tests/alloc-bench/compare-kernel.py \
    tests/alloc-bench/results/2026-10-02/kernel-vinix-after/run-$run/serial.log \
    tests/alloc-bench/results/2026-10-02/kernel-macos-$run/serial.log
done
```

Recompute the pooled kernel statistics directly from all preserved samples:

```sh
python3 - <<'PYTHON'
import importlib.util
from pathlib import Path
from statistics import median
base = Path("tests/alloc-bench")
spec = importlib.util.spec_from_file_location("kalloc", base / "compare-kernel.py")
kalloc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(kalloc)
records = base / "results/2026-10-02"
for phase, (pairs, _) in kalloc.PHASES.items():
    for group in ("before", "after", "macos"):
        raw = []
        for run in range(1, 4):
            folder = (records / f"kernel-macos-{run}" if group == "macos" else
                      records / f"kernel-vinix-{group}/run-{run}")
            parsed = kalloc.parse_log((folder / "serial.log").read_text(),
                                      "xnu" if group == "macos" else "vinix")
            raw.extend(parsed["samples"][phase])
        print(phase, group, len(raw), median(raw) / pairs,
              min(raw) / pairs, max(raw) / pairs)
PYTHON
```

For new runs, follow [the harness build/run instructions](../../README.md)
in fresh output directories and isolated kernel worktrees. Use the recorded
common VM settings, GNU GCC versions/flags, the frozen source hashes, and the
macOS manifest's native-GCC/host-assembly stages. Load/unload the diagnostic
kext three times to capture macOS cohorts; boot the original and optimized
Vinix kernels three times each. Run user workloads with
`--iterations 200000 --samples 7`. Keep raw logs, actual build commands and
binary hashes, and execute timed guest workloads sequentially.

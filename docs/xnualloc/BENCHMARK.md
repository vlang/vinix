# Vinix heap benchmark: bitmap slabs vs XNU zones

Measured 2026-09-11 with the opt-in `-d heap_benchmark` kernel workload. The
comparison uses the merged Vinix reclaimable bitmap-slab backend (the default)
and the XNU-inspired zone/cache backend selected by `-d xnu_zone`.

## Method

Both kernels were production builds made from the same tree with V 0.5.2
`c3358d3`, Apple Clang 21.0.0, `-prod` and `-O2`. Each was booted three times
with QEMU 11.1.1 using the same configuration:

```text
q35, TCG single-thread, cpu=max, 512 MiB RAM, 1 vCPU
```

One vCPU removes secondary CPUs spinning before scheduler startup while still
publishing one valid XNU CPU cache. The benchmark runs after that publication
and before scheduler startup. Each boot performs one unrecorded warm-up of both
workloads, followed by five recorded samples. The table therefore reports the
median of 15 samples. An allocator operation is one `malloc` or one `free`.

| Workload | Operations/sample | Vinix bitmap median TSC ticks/op | XNU zone median TSC ticks/op | XNU change |
|---|---:|---:|---:|---:|
| Hot 64-byte allocate/free pairs | 200,000 | 318.435 | 478.260 | 50.19% slower |
| 256-object mixed-size batches across all 14 classes | 24,576 | 1,245.483 | 1,172.933 | 5.83% faster |

The 15-sample ranges were 316-320 vs 474-483 ticks/op for the hot workload and
1,233-1,252 vs 1,157-1,184 ticks/op for the batch workload. Results were stable
across the three alternating boot pairs after warm-up.

The memory record was identical across all three boots:

| Backend | Permanent cache metadata | Payload retained before trim | Released by trim | Payload unreclaimed after trim |
|---|---:|---:|---:|---:|
| Vinix bitmap | 0 KiB | 32 KiB | 32 KiB | 0 KiB |
| XNU zone | 56 KiB | 176 KiB | 176 KiB | 0 KiB |

## Interpretation

This port is not a universal speedup. Its magazine path helps the mixed burst
by about 6% here, but a hot single-size pair is about 50% slower because the
current correctness-first adapter still takes one interrupt-disabling class
lock and performs live-bitmap, resolver and cache-state work. It also retains
56 KiB of CPU-cache metadata and a larger pre-trim payload working set. Both
backends returned all measured payload pages when explicitly trimmed.

TSC ticks under TCG are suitable only for this same-host, same-configuration
relative comparison; they are not native CPU cycles. This is an uncontended
single-CPU microbenchmark, not an application benchmark or an SMP scalability
result. Bare-metal throughput, tail latency, lock contention, pressure/OOM
behavior and cross-CPU frees remain to be measured before making this backend
the default.

## Reproduction

Add `-d heap_benchmark` to an x86_64 kernel build. Build once without allocator
flags and once with `-d xnu_zone`; keep every other compiler and QEMU option
identical. The serial stream ends with `heap-bench: done` and provides five
`hot`, five `batch`, and one `memory` record. Compare medians, not individual
samples. `tests/xnualloc/README.md` contains the validation and build commands.

Matched QEMU allocation workload comparison.

Vinix: Vinix 0.1.0, x86_64, GCC 14.2.0 (14.2.0), page size 4096 bytes; monotonic clock resolution 10 ns.
macOS: Darwin 19.6.0, x86_64, GCC 14.3.0 (14.3.0), page size 4096 bytes; monotonic clock resolution 1000 ns.
GCC minor/patch versions differ; this can affect generated code and the measured ratio.

Medians are recomputed from raw samples. A ratio above 1 means Vinix took longer.

| Workload | Pairs/sample | Samples | Vinix ns/pair | macOS ns/pair | Vinix/macOS |
| --- | ---: | ---: | ---: | ---: | ---: |
| malloc_hot_64 | 200000 | 7 | 2446.530 | 490.800 | 4.985× |
| malloc_mixed_batch_64 | 200000 | 7 | 2161.390 | 871.880 | 2.479× |
| malloc_touch_262144 | 10000 | 7 | 2295.200 | 21202.300 | 0.108× |
| mmap_anon_4096 | 10000 | 7 | 86384.000 | 31918.200 | 2.706× |
| mmap_touch_262144 | 10000 | 7 | 5829021.600 | 2114348.400 | 2.757× |
| pipe_create_close | 10000 | 7 | 382701.400 | 77342.500 | 4.948× |

malloc workloads compare the guests' userspace allocators and libc implementations. mmap workloads measure VM mapping, faults and teardown; pipe creation exercises syscall and object lifetimes. These do not directly compare Vinix slab allocation with XNU zone allocation.

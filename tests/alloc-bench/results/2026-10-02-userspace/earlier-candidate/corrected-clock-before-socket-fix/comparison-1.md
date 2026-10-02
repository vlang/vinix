Matched QEMU allocation workload comparison.

Vinix: Vinix 0.1.0, x86_64, GCC 14.2.0 (14.2.0), page size 4096 bytes; monotonic clock resolution 10 ns.
macOS: Darwin 19.6.0, x86_64, GCC 14.3.0 (14.3.0), page size 4096 bytes; monotonic clock resolution 1000 ns.
GCC minor/patch versions differ; this can affect generated code and the measured ratio.

Medians are recomputed from raw samples. A ratio above 1 means Vinix took longer.

| Workload | Pairs/sample | Samples | Vinix ns/pair | macOS ns/pair | Vinix/macOS |
| --- | ---: | ---: | ---: | ---: | ---: |
| malloc_hot_64 | 200000 | 7 | 2246.505 | 3223.100 | 0.697× |
| malloc_mixed_batch_64 | 200000 | 7 | 1853.430 | 6618.780 | 0.280× |
| malloc_touch_262144 | 10000 | 7 | 3901.800 | 150105.100 | 0.026× |
| mmap_anon_4096 | 10000 | 7 | 59634.600 | 186526.600 | 0.320× |
| mmap_touch_262144 | 10000 | 7 | 4096873.100 | 7944533.400 | 0.516× |
| pipe_create_close | 10000 | 7 | 207824.300 | 296048.500 | 0.702× |

malloc workloads compare the guests' userspace allocators and libc implementations. mmap workloads measure VM mapping, faults and teardown; pipe creation exercises syscall and object lifetimes. These do not directly compare Vinix slab allocation with XNU zone allocation.

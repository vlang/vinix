All recorded raw samples participate, including outliers; no filtering or selection.

Cohort 1

| Workload | Samples/guest | Vinix ns/pair median [min, max] | Catalina ns/pair median [min, max] | Vinix/Catalina | At or faster |
| --- | ---: | ---: | ---: | ---: | --- |
| malloc_hot_64 | 7/7 | 234.200 [218.445, 252.400] | 330.590 [323.305, 344.795] | 0.708430 | yes |
| malloc_mixed_batch_64 | 7/7 | 315.790 [300.475, 344.530] | 679.120 [633.060, 692.985] | 0.464999 | yes |
| malloc_touch_262144 | 7/7 | 1663.400 [1355.500, 1854.600] | 17006.600 [16088.300, 17533.400] | 0.097809 | yes |
| mmap_anon_4096 | 7/7 | 11555.800 [11172.500, 13118.600] | 23311.200 [22371.100, 24925.500] | 0.495719 | yes |
| mmap_touch_262144 | 7/7 | 553381.200 [539175.600, 627959.000] | 1706616.200 [1347432.500, 2000620.300] | 0.324256 | yes |
| pipe_create_close | 7/7 | 24061.700 [23355.300, 26417.100] | 70689.400 [69228.000, 74200.600] | 0.340386 | yes |

GCC minor/patch versions differ; this can affect generated code and the measured ratio.

Cohort 2

| Workload | Samples/guest | Vinix ns/pair median [min, max] | Catalina ns/pair median [min, max] | Vinix/Catalina | At or faster |
| --- | ---: | ---: | ---: | ---: | --- |
| malloc_hot_64 | 7/7 | 226.720 [224.810, 230.445] | 461.750 [430.510, 465.785] | 0.491002 | yes |
| malloc_mixed_batch_64 | 7/7 | 313.020 [309.265, 347.330] | 877.995 [862.995, 907.555] | 0.356517 | yes |
| malloc_touch_262144 | 7/7 | 1520.300 [1375.200, 1637.700] | 19674.100 [19384.200, 20167.600] | 0.077274 | yes |
| mmap_anon_4096 | 7/7 | 11223.000 [10741.100, 11664.000] | 30022.100 [29927.500, 31802.100] | 0.373825 | yes |
| mmap_touch_262144 | 7/7 | 739101.500 [711936.500, 1587843.700] | 1969034.100 [1826536.800, 2075983.700] | 0.375362 | yes |
| pipe_create_close | 7/7 | 35396.800 [33361.600, 38081.100] | 66476.400 [63699.700, 77728.800] | 0.532472 | yes |

GCC minor/patch versions differ; this can affect generated code and the measured ratio.

Pooled samples from every final cohort

| Workload | Samples/guest | Vinix ns/pair median [min, max] | Catalina ns/pair median [min, max] | Vinix/Catalina | At or faster |
| --- | ---: | ---: | ---: | ---: | --- |
| malloc_hot_64 | 14/14 | 228.850 [218.445, 252.400] | 387.653 [323.305, 465.785] | 0.590348 | yes |
| malloc_mixed_batch_64 | 14/14 | 313.803 [300.475, 347.330] | 777.990 [633.060, 907.555] | 0.403350 | yes |
| malloc_touch_262144 | 14/14 | 1537.300 [1355.500, 1854.600] | 18458.800 [16088.300, 20167.600] | 0.083283 | yes |
| mmap_anon_4096 | 14/14 | 11432.800 [10741.100, 13118.600] | 27426.500 [22371.100, 31802.100] | 0.416852 | yes |
| mmap_touch_262144 | 14/14 | 669947.750 [539175.600, 1587843.700] | 1924765.850 [1347432.500, 2075983.700] | 0.348067 | yes |
| pipe_create_close | 14/14 | 29889.350 [23355.300, 38081.100] | 70205.850 [63699.700, 77728.800] | 0.425739 | yes |

All individual cohorts at or faster: True.
All pooled workloads at or faster: True.

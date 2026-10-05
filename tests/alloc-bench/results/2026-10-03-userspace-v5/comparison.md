# Complete v5 allocation comparison

All recorded raw samples participate, including outliers; no filtering or selection.

Cohort 1

| Workload | Samples/guest | Vinix ns/pair median [min, max] | Catalina ns/pair median [min, max] | Vinix/Catalina | At or faster |
| --- | ---: | ---: | ---: | ---: | --- |
| malloc_hot_64 | 7/7 | 329.425 [301.010, 543.575] | 535.775 [493.600, 558.050] | 0.614857 | yes |
| malloc_mixed_batch_64 | 7/7 | 415.990 [399.895, 441.780] | 832.760 [778.095, 921.540] | 0.499532 | yes |
| malloc_touch_262144 | 7/7 | 1698.400 [1546.400, 3897.300] | 17547.800 [15640.600, 19078.000] | 0.096787 | yes |
| mmap_anon_4096 | 7/7 | 13421.300 [12867.300, 13885.100] | 27264.500 [25081.500, 28905.100] | 0.492263 | yes |
| mmap_touch_262144 | 7/7 | 1406969.900 [948787.600, 1508946.000] | 1641710.200 [1439133.300, 2256949.900] | 0.857015 | yes |
| pipe_create_close | 7/7 | 35114.100 [32271.900, 36194.100] | 48899.400 [46780.800, 55900.500] | 0.718089 | yes |

GCC minor/patch versions differ; this can affect generated code and the measured ratio.

Cohort 2

| Workload | Samples/guest | Vinix ns/pair median [min, max] | Catalina ns/pair median [min, max] | Vinix/Catalina | At or faster |
| --- | ---: | ---: | ---: | ---: | --- |
| malloc_hot_64 | 7/7 | 573.115 [556.565, 608.610] | 436.040 [407.915, 454.225] | 1.314363 | no |
| malloc_mixed_batch_64 | 7/7 | 562.475 [540.635, 604.485] | 843.355 [792.540, 879.890] | 0.666949 | yes |
| malloc_touch_262144 | 7/7 | 2100.900 [1848.300, 2262.900] | 14018.900 [13619.500, 15989.600] | 0.149862 | yes |
| mmap_anon_4096 | 7/7 | 16879.700 [16314.200, 18717.800] | 23865.100 [22509.700, 26084.700] | 0.707296 | yes |
| mmap_touch_262144 | 7/7 | 526523.800 [442534.400, 776461.300] | 1696372.400 [1504664.200, 1987352.700] | 0.310382 | yes |
| pipe_create_close | 7/7 | 20380.900 [19732.200, 25369.900] | 50033.700 [46287.700, 53293.600] | 0.407343 | yes |

GCC minor/patch versions differ; this can affect generated code and the measured ratio.

Pooled samples from every final cohort

| Workload | Samples/guest | Vinix ns/pair median [min, max] | Catalina ns/pair median [min, max] | Vinix/Catalina | At or faster |
| --- | ---: | ---: | ---: | ---: | --- |
| malloc_hot_64 | 14/14 | 550.070 [301.010, 608.610] | 473.913 [407.915, 558.050] | 1.160699 | no |
| malloc_mixed_batch_64 | 14/14 | 491.207 [399.895, 604.485] | 838.058 [778.095, 921.540] | 0.586126 | yes |
| malloc_touch_262144 | 14/14 | 1954.100 [1546.400, 3897.300] | 15955.000 [13619.500, 19078.000] | 0.122476 | yes |
| mmap_anon_4096 | 14/14 | 15099.650 [12867.300, 18717.800] | 25475.250 [22509.700, 28905.100] | 0.592718 | yes |
| mmap_touch_262144 | 14/14 | 862624.450 [442534.400, 1508946.000] | 1668026.400 [1439133.300, 2256949.900] | 0.517153 | yes |
| pipe_create_close | 14/14 | 28820.900 [19732.200, 36194.100] | 49255.200 [46287.700, 55900.500] | 0.585134 | yes |

All individual cohorts at or faster: False.
All pooled workloads at or faster: False.

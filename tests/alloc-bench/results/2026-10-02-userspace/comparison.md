# Complete v4 allocation comparison

All recorded raw samples participate, including outliers; no filtering or selection.

Cohort 1

| Workload | Samples/guest | Vinix ns/pair median [min, max] | Catalina ns/pair median [min, max] | Vinix/Catalina | At or faster |
| --- | ---: | ---: | ---: | ---: | --- |
| malloc_hot_64 | 7/7 | 528.140 [365.700, 843.300] | 509.875 [498.740, 515.570] | 1.035823 | no |
| malloc_mixed_batch_64 | 7/7 | 496.720 [478.180, 510.625] | 922.270 [898.060, 938.890] | 0.538584 | yes |
| malloc_touch_262144 | 7/7 | 2073.300 [1929.500, 2216.800] | 22213.800 [21387.500, 22763.500] | 0.093334 | yes |
| mmap_anon_4096 | 7/7 | 15225.000 [14779.800, 15990.000] | 33123.300 [32289.700, 33955.700] | 0.459646 | yes |
| mmap_touch_262144 | 7/7 | 2353388.300 [1361049.100, 2929328.700] | 2041932.000 [2014455.300, 2101044.200] | 1.152530 | no |
| pipe_create_close | 7/7 | 38447.900 [35365.500, 39905.200] | 70442.200 [68906.800, 77235.100] | 0.545808 | yes |

GCC minor/patch versions differ; this can affect generated code and the measured ratio.

Cohort 2

| Workload | Samples/guest | Vinix ns/pair median [min, max] | Catalina ns/pair median [min, max] | Vinix/Catalina | At or faster |
| --- | ---: | ---: | ---: | ---: | --- |
| malloc_hot_64 | 7/7 | 576.620 [517.385, 824.430] | 464.920 [457.730, 477.200] | 1.240256 | no |
| malloc_mixed_batch_64 | 7/7 | 810.385 [747.890, 878.770] | 898.015 [871.165, 960.510] | 0.902418 | yes |
| malloc_touch_262144 | 7/7 | 2489.800 [2375.300, 2569.100] | 20684.900 [20451.200, 21320.900] | 0.120368 | yes |
| mmap_anon_4096 | 7/7 | 29707.000 [17576.800, 37808.200] | 33000.700 [31267.000, 33794.900] | 0.900193 | yes |
| mmap_touch_262144 | 7/7 | 1304200.400 [1156314.300, 1711726.000] | 1991028.400 [1956164.000, 1995231.200] | 0.655039 | yes |
| pipe_create_close | 7/7 | 36335.300 [35929.200, 38327.500] | 73775.100 [63340.100, 75712.800] | 0.492514 | yes |

GCC minor/patch versions differ; this can affect generated code and the measured ratio.

Pooled samples from every final cohort

| Workload | Samples/guest | Vinix ns/pair median [min, max] | Catalina ns/pair median [min, max] | Vinix/Catalina | At or faster |
| --- | ---: | ---: | ---: | ---: | --- |
| malloc_hot_64 | 14/14 | 537.757 [365.700, 843.300] | 487.970 [457.730, 515.570] | 1.102030 | no |
| malloc_mixed_batch_64 | 14/14 | 629.257 [478.180, 878.770] | 913.452 [871.165, 960.510] | 0.688878 | yes |
| malloc_touch_262144 | 14/14 | 2296.050 [1929.500, 2569.100] | 21354.200 [20451.200, 22763.500] | 0.107522 | yes |
| mmap_anon_4096 | 14/14 | 16783.400 [14779.800, 37808.200] | 33062.000 [31267.000, 33955.700] | 0.507634 | yes |
| mmap_touch_262144 | 14/14 | 1529224.900 [1156314.300, 2929328.700] | 2004843.250 [1956164.000, 2101044.200] | 0.762765 | yes |
| pipe_create_close | 14/14 | 37088.650 [35365.500, 39905.200] | 70883.450 [63340.100, 77235.100] | 0.523234 | yes |

All individual cohorts at or faster: False.
All pooled workloads at or faster: False.

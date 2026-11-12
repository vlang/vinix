# Native field lookup constants

r65/r66's account logs reported failed JNI lookup of APP_OPS_SERVICE and
BOOT_COUNT near a native null-address fault. The SDK lacked both fields.
Their documented contracts are [Context.APP_OPS_SERVICE](https://developer.android.com/reference/android/content/Context#APP_OPS_SERVICE)
and [Settings.Global.BOOT_COUNT](https://developer.android.com/reference/android/provider/Settings.Global#BOOT_COUNT).
The SDK now exposes the public static final String names `appops` and
`boot_count`. This does not synthesize a stored boot counter or change AppOps
authorization. Whether this gap caused the native fault remains unproven.

The ordinary SDK extension and full current SDK builder both install the fields.
The signed regression reads them directly and by reflection, checking String
type, public/static/final modifiers and values. It also resolves the AppOps
service through the new Context name.

Available V0.5.2 6422d39 produced the following under the unchanged guard;
all exited0/0 with complete cleanup:

| Artifact | Elapsed ms | Peak RSS bytes | Shared growth bytes |
|---|---:|---:|---:|
| framework-lookup-constants-20261112-r1 | 2145 | 473726976 | 30441472 |
| current-api-fixture-20261112-r58 | 941 | 186269696 | 1024000 |
| maps-current-20261112-r67 staging | 7893 | 38404096 | 151175168 |

Fresh r67 retains the memory-qualified controller r4 and protocol/launcher r2,
native r5, mandatory core/TLS jars,12GiB/4CPUs and the same8GiB app-data volume.
Volume identity, read-only e2fsck and initial image hash passed before boot.
The full signed regression passed as UID/GID10160: ready/pass once, drained
EOF and exit0. UART snapshot `lookup-constants-api-uart-20261112-r1` full SHA256:
`682ca2f071c2055741a8ef69b793722089d96784bf05ba58edcc52439500369d`.
Plan/readback r1 reconstruct the unchanged export with zero removals, archive:
`8e76bf19c04fbe89d45e41addb903bbc5040635383da1f767be432836879689f`.

Artifacts remain under `/Users/alex/.local/state/vinix/android/`. The API bind
was released before broker preparation. Actual account-flow retry and tile
rendering remain pending; this API pass does not establish either outcome.

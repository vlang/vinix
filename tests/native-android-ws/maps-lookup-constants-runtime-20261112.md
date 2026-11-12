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
was released before broker preparation. The actual retry reached the account
chooser and PreAddAccountActivity after Add account, including its FRP snapshot
and challenge completion. GMS then failed with SIGSEGV, fault address0x898,
PC0x800e6921b94, thread37409 `NTAINER_UPDATED`. There is no login page or
authentication success. Adding these constants did not resolve the native crash.
The SetupLibrary decor-view warnings recur four times; Window.peekDecorView
still returns null despite its eagerly constructed decor. That separate contract
gap is being fixed without attributing the native fault to it.

The600228ms observation completed, minimum MemFree3841216KiB and app-data
space7240425472bytes. No OOM kill was observed. The memory snapshot completed
after GMS exited and therefore cannot identify the native fault's module.
Its copied contents are retained with an inventory; debugfs could not reproduce
guest ownership on the host. The raw disk remains authoritative for metadata.
After guest sync returned and PID1870 was verified as this VM, it was stopped
and confirmed absent before offline extraction. The r67 artifact root retains:

| Artifact | SHA256 |
|---|---|
| maps.retained.log | b6c4ad4846812befa425689a7060758ec9a9ac8e24064522120d576cbccb5a9e |
| broker.retained.log | dde4d778546ba72372dc5bed27478ebbf0bf620798a0f7dabbbdf5b1f22303ea |
| receipt.retained.json | 1a42a025b6a0ad2a1dbcd124ce5064569648367f675e65feb4fe99793204e9c2 |
| serial.log | f0ca43124b27ca59465aa6fd884aafd382b35ddc96f556cdfff96bcbf819372c |
| app-data.ext2 final | 639cc7f9c21f09d354dae67b61643b76bc25542a4f82dd94f57f5eae99a33d41 |
| memory-retained.sha256 | 38897c9e96e44a862e4ad13a276f1914775bf0bbc2284a7b851016f73a040653 |

Tile rendering was not exercised in this retry and remains unresolved.

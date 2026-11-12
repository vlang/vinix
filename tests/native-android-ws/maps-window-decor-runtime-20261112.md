# Window decor visibility

Source parent68b7b4e01. The SDK Window constructor creates a FrameLayout decor,
but peekDecorView returned null unconditionally. The
[Android API contract](https://developer.android.com/reference/android/view/Window#peekDecorView())
returns the existing decor without creating one. The adapter now reads the same
field as getDecorView, with no allocation, attachment or replacement.
This addresses the concrete mismatch behind investigation of the account flow's
SetupLibrary decor warnings; a connection to the native SIGSEGV is unproven.

Both ordinary SDK extension and the complete current builder apply the adapter.
Selected DEX readback includes Window. The signed regression checks peeking
before getDecorView, identical object identity, the decor's ID, unattached state,
and child preservation across repeated peeks.

Available V0.5.2 6f888d6 (executable SHA256
5bb15e45aebb0c174abb4b8c962d6bcb2633aee2f63d5d6f30247becffeb191b)
built the producer and fixture tooling using nocache. No historical V pin was
used. The unchanged guard limits remain RSS629145600, wall300000ms,
reserve1073741824, growth536870912, output4194304.
All three productions exited0/0 with complete cleanup:

| Artifact | Elapsed ms | Peak sampled RSS bytes | Shared growth bytes |
|---|---:|---:|---:|
| framework-window-decor-20261112-r1 | 6050 | 481116160 | 20570112 |
| current-api-fixture-20261112-r59 | 2138 | 191119360 | 4972544 |
| maps-current-20261112-r68 staging | 14352 | 38551552 | 186630144 |

All roots are under `/Users/alex/.local/state/vinix/android/` with logs and
guard receipts. Source copies and hashes are window-decor-inputs-20261112-r1.
SDK jar SHA25665b10a3c6983d10c0a5c82d9c7c50e4c30218b9ae70b061757e62b1a4ac80519;
signed APK275b696104b503b3fd97eb40b79dd0de289cdcfdccc19527e03b11448e83d955.
Fresh r68 retains native r5, the qualified memory controller r4 and paired
protocol/launcher r2, mandatory core/TLS jars,12GiB/4CPUs and8GiB app-data disk.
Volume identity6d01a6a5c67a460e8e882cd0d08dd7ef, read-only e2fsck and initial
hash passed before boot.

The full signed regression passed on ARM as UID/GID10160: ready/pass once,
drained EOF, exit0. Snapshot window-decor-api-uart-20261112-r1 full SHA256
c637202d48318226d9995e8117e1fe85e8c12212f816c6c6f7435b59e2900a78,
receipt2d49352fc1ffefb052b4a4f0ebac3bad56deaa17b37d9d9784a2d1c59d9207bd.
Plan/readback r1 reconstruct the unchanged export with zero removals,
archive360fd5c5f0245cc32bf9300cac282f207ce124c1857b6e96613f6b37aa147d80.
This is byte-export evidence, not a new result from the historical strict importer.

The API bind was released before broker preparation. Real sign-in retry and
map tile/route rendering remain pending; the regression pass proves neither.

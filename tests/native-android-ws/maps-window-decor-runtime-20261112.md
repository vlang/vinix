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

The API bind was released before broker preparation. In the real retry, Add
account reached PreAddAccountActivity and then a Google account error page:
"Something went wrong / There was a problem communicating with Google servers."
The private log identifies CheckinHelper's 10000 ms timeout and a false check-in
result. Later the same log reports successful check-in requests and operation
completion. This establishes neither login nor successful authentication.
There were no decor-view warnings, native fatal signals or OOM kills in the
retained broker log. This observation alone does not attribute earlier crashes
to the Window change. Tile and route geometry were not exercised in this retry.

The 600283 ms watch completed: minimum MemFree 4250832 KiB, minimum app-data
space 7230132224 bytes. Two non-atomic process snapshots, before and after Add
account, completed; their overhead overlapped account startup and may affect
timing. The next retry omits that broad snapshot. After guest sync returned,
owned QEMU PID 27676 was stopped and confirmed absent before offline extraction.
The receipt was still ready-awaiting-user-account-interaction when the VM was
stopped; it is not a completed account-flow result. Snapshot contents were copied
but guest ownership could not be reproduced on the host; the raw disk is the
metadata authority.

Retained r68 artifacts:

| Artifact | SHA256 |
|---|---|
| maps.retained.log | 738b9ae4e1017160f9746f698a7fc3ccf47f52f765a928bcdd4a469f953a413d |
| broker.retained.log | 8e592ad3ed02913f0af27d839a58590ef1a537d9f5bc76e2b4b3bc1dfb9c9895 |
| receipt.retained.json | b379ce0937db494f188198f1e438846823e37125f1e1de14c7f2f9d48f7bf06c |
| serial.log | 552ba6dce02b2a8a954fd9dce58961cb3e8cb618f28f4c1d94900f251ae5bd4e |
| account-visible.png | 5bbf8f29f22ca545ac02c4bc4b36471369ab0b8c697ef91fbd6a919188576764 |
| app-data.ext2 final | f97f9c08095c2e14e52cfd4e96c67acb0edad987211bd14437b528f5b2c5c3fd |
| memory-retained.sha256 | 7cf01916728c5fb6f2f59998e9e2c5afea8f4a7e9131006913f83939cf70ac70 |

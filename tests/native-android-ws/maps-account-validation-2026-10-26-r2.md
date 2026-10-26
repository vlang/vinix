# Maps account deployment: authenticator attachment timeout

The real Maps/GMS controller reached broker startup after the `/run` fix
`e9273eb11`, then failed because the GMS authenticator did not attach before
its deadline. No credentials were supplied; this run does not establish
Google account login or service readiness.

The exported receipt records 18:26:09–18:30:54 UTC on 2026-10-26, broker
PID 42169, `service_ready=false`, broker exit 137 and zero cleanup survivors.
The exit status alone does not identify its cause. The broker log was excluded
from export; only its SHA-256
`06df3ff1d157f4f2cd6b8de9f44ccdf5c22dcd8265ec6c4e7fa355cb6bdc61d8`
was retained. No conclusion here depends on unexported log contents.

The unchanged strict collector accepted the complete UART export: 21 entries,
1,438,679 archive bytes, 2,810 chunks, archive SHA-256
`1c7451bcd203b7e08f5866d3bb19e0dd248b8a35dab4cbe6c502b159a79edb4e`.
Its `import.json` binds the original complete UART, SHA-256
`a783d2f6c095b93a37f368c00ffd975d2427b9e14b6b3d0de595ab29e065a664`.
Results remain in `maps-account-collected-2026-10-26-r2`; this passing
collection validates transport integrity, while the guest outcome remains failed.

Only the exact `maps-account-vm-r2` clone was patched and booted. Original
`maps-account-r2`, manifest
`de73d7510ff7138eaff38f61b8da26c5c48017ba2927e7d1278be58f5c9fca31`,
remains intact. See [staging provenance](maps-account-stage.md) for its full
request, unchanged modules, input audits and 1,910-file clone check. Runtime
inputs were framework r3, account r5, JNI r15, launcher r12, Maps controller r4,
browser deployment r7, token APK r5 and token controller r1. The frozen AArch64
kernel used source revision `577a2d8c29ba6d4a95a655d507ef38414d3b8c77`,
binary SHA-256
`ee6aa1acb31f11b8abf16c4001149ccb92e8f8fe35d0106342bbdbad6e7e57fd`.

The kernel patch used the older optimized host tool; startup and stop used
the native-SHA runner from `078162809`, validated in `222f80c93`. Both complete
tool bundles remain retained. Native runner SHA-256 is
`5bd202a83f0b049ae00376d93691af4b22fab03837356271883a7d515cabb5c2`;
its bundle inventory is
`f710cc58e3d9fe86e9b9df69d34afe6f46e20102423e558dd8b338bfc4459c0c`.
QEMU PID 54974 was stopped through that owned runner at 18:34:21 UTC; the
matching ownership, stop and absence receipts remain in the VM bundle.
Original screenshots, packet capture and UART remain unmodified there.

All artifacts are below `/Users/alex/.local/state/vinix/android/`. The complete
deployment evidence seal is `maps-account-evidence-2026-10-26-r2/manifest.json`.
Its SHA-256 is
`29bcbca28fc53a6b267db8a6477880b5e71cdacd5eee86568cba22ccb16a5938`;
it binds 39 roots and 46,924 entries. Its creation check and separate complete
recheck passed, recorded in adjacent `-seal.log` and `-check.log` files. Preserve
every bound root, including original and booted stages, collection, selected
historical build bundles and upstream inputs, frozen kernel, clone tools and
receipts, both host tool bundles,
collector and host lifecycle logs. Concise pins do not replace these bundles.
This seal binds deployment evidence. Host-tool receipts still require their
original complete compiler dependencies; it does not certify a recursively
complete historical rebuild closure.

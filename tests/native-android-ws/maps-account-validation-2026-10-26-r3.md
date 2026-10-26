# Maps account deployment: account store initialization failure

The real Maps/GMS controller observed the GMS authenticator attach, then the
broker exited with an account store initialization failure. The exported
bounded diagnostic is `stage=8 code=2 detail=0 loader=0`; stage 8 identifies
`ws_store_init` in the retained JNI r16 source. Code 2 is the numeric errno
diagnostic (`ENOENT`), which can be stale and does not identify the failing
SQLite operation or a missing path. No credentials were supplied; this run
does not establish Google account login.

The receipt records 19:20:34–19:21:23 UTC on 2026-10-26, broker PID 22956,
`service_ready=true`, broker exit 1 and zero cleanup survivors. Service
readiness describes authenticator transport attachment. The broker log was
excluded from export; only its SHA-256
`7f98a6e7816ce696b967af94d9f490f30cdfcef306890df243a1d6cac20b1a6e`
was retained. The failure assessment uses the exported structured diagnostic.

The unchanged strict collector accepted 21 entries, 1,438,766 archive bytes
and 2,811 chunks, archive SHA-256
`3c14b3d349b2abc171b39c73f20afdbde276ecef76bf21434cd275d43276bd6f`.
The first collection remains unchanged in
`maps-account-collected-2026-10-26-r3`; its `import.json` records the UART
snapshot read before subsequent metadata diagnostics. After the guest stopped,
the same strict collector accepted the same archive from the complete final
UART, SHA-256
`5417403a73fe6a9d6d3c79000c15073b0eefc4b7ddc95147718e637543d5d2ea`.
That independently bound collection remains in
`maps-account-collected-final-2026-10-26-r3`. Both collections are retained.
Collection validates export integrity; the guest result remains failed.

Only the exact `maps-account-vm-r3` clone was patched and booted. Original
`maps-account-r3`, manifest
`cb252f3d616a705f6c779346ff94b91d9922c61fc9c81804af99aaecc0791741`,
remains intact. See [staging provenance](maps-account-stage.md) for the retained
coupled request, complete inventory checks and exact 1,911-file clone.
Runtime inputs were descriptions framework r1 (2,104 classes), JNI r16,
account r6, launcher r13, Maps controller r5, browser deployment r7, signed
token fixture r7, token controller r2 and standalone UI stage r3. The frozen
AArch64 kernel used source `577a2d8c29ba6d4a95a655d507ef38414d3b8c77`,
binary SHA-256
`ee6aa1acb31f11b8abf16c4001149ccb92e8f8fe35d0106342bbdbad6e7e57fd`.

Kernel patching and owned guest lifecycle used the retained native-SHA host
tools, source `078162809`, validated in `222f80c93`. Tool bundle inventory
SHA-256 is
`f710cc58e3d9fe86e9b9df69d34afe6f46e20102423e558dd8b338bfc4459c0c`.
SIGTERM was requested for owned QEMU PID 76562 at 19:24:35 UTC; matching
ownership, stop and absence receipts confirm absence at 19:24:41 UTC. The initial
stop command reported an ownership race; the owned runner's reconciliation
passed. Both command logs remain retained. Original screenshots, packet
capture and complete final UART remain in the VM root. The fixed-path
`store-path-metadata.png` records file metadata without account contents.

All artifact paths are below `/Users/alex/.local/state/vinix/android/`.
The complete deployment evidence seal is
`maps-account-evidence-2026-10-26-r3/manifest.json`, SHA-256
`33a053da564124e47b073fabc96defb837337a9e54fd2ce1e08f70f64a9e175c`.
It binds 55 roots and 56,822 entries, including original and booted media,
both collections, complete selected producers and upstream inputs, coupled
request lineage, frozen kernel, exact clone tool/source closure, both host
tool bundles and actual lifecycle logs. Its creation check and separate
complete recheck passed, recorded in adjacent `-seal.log` and `-check.log`. Preserve
every bound root; concise pins do not replace the bundles. This seal binds
deployment evidence. Host-tool receipts still require their original complete
compiler dependencies; it does not certify a recursively complete historical
rebuild closure.

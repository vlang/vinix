# Verify a saved installation against a release ISO

Revision `3ca6072be6a07cbfc3531f811c7d9531eede970b` adds
`package-receipt verify-installed`. It verifies the ISO and its published
package receipt, then checks release coverage against a saved snapshot.
The result binds the verified ISO, exact declaration and snapshot digests,
and the generation recorded by the snapshot receipt.
[Command and input contract](../../tools/packages/SDK.md#check-release-image-package-inputs)

The host tests built signed AArch64 and x86-64 fixtures with file and HTTPS
repository declarations. The package service installed from their local
bundles and saved actual snapshots before and after removal. The file
fixtures mapped their repository URLs into the host scratch root. All 140
cases passed, including coverage, drift exit 3 and refusal of changed
snapshot bytes, aliases, wrong counts, wrong architecture and missing
locked roots. Both hosted fixtures also passed with production and
ASan/UBSan verifier builds. Leak detection was disabled for sanitizer runs.
[Host driver](iso-package-receipt-check.v)

The two retained expired ISOs refused current-time verification. At their
recorded release time, both verified and then reported the expected publisher
key drift against the newly installed snapshots.

## Manifest canonicalization ownership

Revision `02a58f5e26b4fd2e591fd4c838b46c56d76f82f4` borrows each input
array header before cloning and sorting it. The baseline generated C
allocated a 504-byte package record during canonicalization. The fixed
code keeps that record on the stack.

| Host workload | Baseline retained bytes | Fixed retained bytes |
| --- | ---: | ---: |
| 1,000 exports of 16-package snapshots | 8,064,000 | 0 |
| 1,000 selection, snapshot and refusal cycles | 1,008,000 | 0 |
| 100 public snapshot, save, audit and refusal cycles | 806,400 | 0 |

The tracked observation suite passed under ASan/UBSan. Catalog and release
regressions passed, and the previously staged hosted fixture locks continued
to match snapshots generated after the fix. Both retained-kernel QEMU
deployment audit runs passed with heap tracking enabled for observations.
AArch64 completed in 24.3 seconds and x86-64 in 39.8 seconds.
[Guest driver](deployment-audit-runtime-check.v)

The independent archive checker verified 3,412 sealed entries. The archive
SHA-256 is
`1325d1524f46d3b432a35897e42bd52f6c5f22f13c20f5a87cd41136211b2866`.
[Qualification archive](/Users/alex/.local/state/vinix/r14-installed-receipt-XOiGQt/qualification.tar.gz)

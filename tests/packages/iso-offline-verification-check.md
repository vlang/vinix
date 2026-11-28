# Verify copied offline release media

Revision `562955c0d2e43c944541815a2e3c5ff01428c490` adds
`package-receipt verify-offline MEDIA_DIRECTORY RECEIPT.json`. It binds the
copied deployment lock and application set to the trusted release receipt,
then verifies the publisher signatures, index digest and sequence, expiry,
object byte counts and complete object inventory. The checker reads the copy
in place. It uses the existing signed-export ownership and mode requirements.
[Command and input contract](../../tools/packages/SDK.md#check-release-image-package-inputs)

All 136 production host scenarios passed across AArch64 and x86-64 file
and HTTPS declaration fixtures. Both hosted matrices also passed their 70
scenarios under ASan/UBSan with leak detection disabled. The new controls
changed the lock, signature and object, removed an object, added a root entry,
substituted symlinks and changed the declared roots and publisher pins. After
restoration the same directory returned its original verification report and
matched the original export byte for byte.
[Host driver](iso-package-receipt-check.v)

The verifier checked both retained mixed-catalog media copies with no tools on
`PATH` and a nonexistent scratch directory. Each contains 2,158 objects and
the lock for seven advertised apps. The original media and signed inputs are
in the earlier archive pinned in the export report. Media assembled from two
expired fixture ISOs refused at current time. Hosted readback, local signed
export checking and index-pin generation also passed.
[Original export qualification](iso-offline-media-check.md)

Both QEMU image-export suites passed with retained kernels and newly built
programs. AArch64 finished in 113.7 seconds and x86-64 in 119.8 seconds.
The new guest assertions checked two signed publishers and duplicate receipt
pin refusal. [Guest driver](image-export-runtime-check.v)

The independent archive checker verified all 2,466 sealed files and links.
The archive SHA-256 is
`191f89094c7a8471a5a61cc7e2da9a81ffc735902a475ff7207d99be50aaf90a`.
[Qualification archive](/Users/alex/.local/state/vinix/r14-offline-verify-Np8JCZ/qualification.tar.gz)

## Verification at the archived release time

Source revision `1578b2cd37a57575ee9abe4d2bd95775fe61acb6` adds the optional
`RELEASE_UNIX_TIME` operand to `verify-offline` and includes `release_time`
in the historical report. Both retained expired media copies passed with
their recorded release time, an empty tool search path and unavailable
scratch storage. Current-time verification and media export refused both
expired inputs. [Command contract](../../tools/packages/SDK.md#check-release-image-package-inputs)

All 136 production host scenarios and both 35-case HTTPS matrices under
ASan/UBSan passed. The sanitizer receipts for the retained expired copies
matched the production receipts byte for byte. Leak detection was disabled.
The local and hosted release checks and hosted index-pin checks also passed.

Both full QEMU image-export suites passed with retained kernels and rebuilt
fixtures, then shut down cleanly. AArch64 completed in 124.8 seconds and x86-64
in 133.7 seconds. The native check used a two-publisher bundle and verified
the boundary at exact expiry, the receipt's index digest, invalid release
times, signature corruption and an exact restored retry.

The complete evidence tar is stored as a Zstandard delta against the preceding
offline media guest archive. Restoring it from the persistent delta reproduced
the tar byte for byte and passed independent verification of 2,631 sealed
files and links. The delta SHA-256 is
`541b0e401e14db632e8ba56229212893c43a613255934ab679d57c747bddea0d`.
[Restore instructions](/Users/alex/.local/state/vinix/r14-archive-media-mQstkM/RESTORE.md)

## Match deployment pins to signed indexes

At `95ef3e231de9180ca2d81f957615bed6c7adf0b3`, current and historical
`verify-offline` match each locked package to its bundled signed index.
Each advertised application needs a lock record. The fixture refused a
missing version, a changed manifest digest, a higher minimum sequence, a
publisher outside the bundle and an omitted application pin. The receipt
and lock digests agreed in each case. The original media passed after
restoration. An older CLI accepted the altered manifest digest that the
updated CLI refused.

All 136 production ISO scenarios and 70 ASan/UBSan scenarios passed, with
sanitizer leak detection disabled. The two retained seven-app releases
reproduced their original verification reports byte for byte. The expired
copies passed at their recorded release times and refused at current time.
The separate tracked publisher test reported the same 48 bytes across two
allocations at its first assertion on the base and patched builds.

Both full QEMU image-export suites passed and shut down cleanly. AArch64
completed in 287.7 seconds and x86-64 in 249.1 seconds. Both first runs
passed the new verification cases and reached the 240-second limit during
later checks. The reruns reused the built guest binaries with an explicit
480-second limit.

The independent archive checker verified 2,526 sealed entries. PAX binary
filename encoding preserves the original UTF-8 bytes. The archive SHA-256 is
`a20f70af8a4a90139d9cb6106295e4ed316fa405e4b33a41f88f858ae70847aa`.
[Qualification archive](/Users/alex/.local/state/vinix/mverify-En3Ak6/qualification.tar.gz)
and [verification record](/Users/alex/.local/state/vinix/mverify-En3Ak6/archive-check.log).

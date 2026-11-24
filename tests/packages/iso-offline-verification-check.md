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

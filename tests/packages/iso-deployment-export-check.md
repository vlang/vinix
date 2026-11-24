# Export a deployment lock from a verified release ISO

Revision `4bbad0e0ea5d078249d823b02b78159183b32419` adds
`package-receipt export-deployment` to verify the ISO and its package
receipt and save the embedded format-2 lock with its exact bytes. Its JSON receipt
records the destination, ISO digest, lock digest and architecture. The
verifier captures the destination's parent before reading the ISO and uses
that descriptor for exclusive publication and flushing.
[Command and input contract](../../tools/packages/SDK.md#check-release-image-package-inputs)

The host suite reused the signed AArch64 and x86-64 ISO fixtures with both file
and HTTPS repository declarations. After removing an installed app, each
fixture recovered the lock byte for byte and used its fresh additive
fingerprint to restore the original package records. It also checked
literal Unicode output paths, existing and dangling-link destinations, and
refusal of incorrect ISO digests and timestamps. All 144 host cases passed.
The 74 hosted fixture cases also passed with each of the production and
ASan/UBSan verifier builds. Leak detection was disabled for sanitizer runs.
[Host driver](iso-package-receipt-check.v)

The two retained expired ISOs exported locks matching their original receipt
digests at their recorded release time. Current-time verification refused
both indexes without creating a lock. An ISO with configuration alone also
refused export without creating a file.

Both QEMU image-export suites passed with retained kernels and newly built
fixtures. AArch64 finished in 136.7 seconds and x86-64 in 138.9 seconds.
The new atomic publication test checks preparation failure, replacement of
the captured parent, cleanup and retry on both targets.
[Guest driver](image-export-runtime-check.v)

The independent archive checker verified all 2,880 sealed files and symlinks.
The GNU tar format preserved the literal UTF-8 filename and long symlink
targets. The archive SHA-256 is
`98a85248e555321681648453eef37dd3bf1297627b4640d6507911e79e8ed19b`.
[Qualification archive](/Users/alex/.local/state/vinix/r14-iso-lock-export-HKeHax/qualification-gnu.tar.gz)

# Save a deployment lock from offline media

Revision `976e82a61f16dd98aa05aab2f81be45e12097a1f` adds
`vinix-package deployment-media-save MEDIA_DIRECTORY NEW_FILE [EXPECTED_SHA256]`.
It resolves the bundle's nonempty format-2 lock against the current catalog,
policy and installed state under the package reader lock. The command saves
the exact bytes to a new file outside the bundle and reports their digest.
The saved lock can be reviewed after disconnecting the media.
[Command and offline workflow](../../tools/packages/SDK.md#check-release-image-package-inputs)

The normal and ASan/UBSan host application suites passed, with leak detection
disabled. The fixture preserved legal whitespace and a Unicode destination.
It refused an unexpected digest, a busy writer, blocked policy, a symlinked lock,
a format-1 document, a destination inside the media and an occupied destination.
The saved lock drove a reviewed cache-only install after disconnecting the
bundle. The consumer fixture used the publisher named in the lock because
the adjacent export fixture intentionally duplicates package IDs across its
two publishers. [Application fixture](../../tools/packages/pkgcore/image_applications_test.v)

The production CLI checked the exact digests from the retained AArch64 and
x86-64 release receipts and saved both locks byte for byte. The saved receipts
reported seven app roots and ten package records per target. Configuration,
catalog, replay history and generation were unchanged by saving. A save with
the optional digest omitted reproduced the same bytes, and a lock for the
other architecture refused. After disconnecting the media, both targets
installed the advertised apps and matched all ten locked records.
[Batch media inputs](repository-media-batch-check.md)

The corrected QEMU suites passed with retained kernels and newly built tests.
AArch64 completed in 119.5 seconds and x86-64 in 126.1 seconds. The bundle
contains the initial fixture refusal logs alongside the final successful runs.
[Guest driver](image-export-runtime-check.v)

The independent archive checker verified all 8,870 sealed files and links.
The archive SHA-256 is
`ef520454e92009e3892b2ce7e3fba7670c136f6f07e45038a24be1b3af0857fa`.
[Qualification archive](/Users/alex/.local/state/vinix/r14-media-lock-Sumj8R/qualification.tar.gz)

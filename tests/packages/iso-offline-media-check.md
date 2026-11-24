# Export offline installation media from a verified release ISO

Revision `a593afff815a246f52caecdfb4e3a415cfba903b` adds
`package-receipt export-offline`. It checks the ISO and package receipt at
the current time, copies the complete bundled signed repositories, and saves
the exact deployment lock as `_deployment.json`. It publishes the directory
exclusively through a captured parent. The destination system still reviews
publisher enrollment and the deployment under its own trust and policy.
[Command and offline workflow](../../tools/packages/SDK.md#check-release-image-package-inputs)

All 136 production host ISO scenarios passed across the AArch64 and x86-64
file and HTTPS declaration fixtures. Both hosted matrices also passed all 70
scenarios under ASan/UBSan, with leak detection disabled. Each successful
fixture exported the exact lock, index, signature and object bytes and restored
the original package records into an empty store through offline reviews.
Existing and dangling-link destinations, an incorrect ISO digest and corrupt
signed objects refused without leaving a staged output. Parallel verification
uses `mkdtemp` after the initial runs exposed a scratch-name collision.
[Host driver](iso-package-receipt-check.v)

The production CLI installed all seven advertised applications from each
retained mixed-catalog ISO's export into a clean offline root. Each export
matched the original signed repository byte for byte, including all 2,158
objects. `verify` passed and `verify-installed` matched all ten locked package
records per architecture. These were package installation checks using the
retained release fixtures. [Mixed-catalog inputs](image-requirements-check.md#paired-review-of-the-advertised-catalog)

Two expired ISOs and one configuration-only ISO refused offline export.
Historical lock export still reproduced the earlier exact locks at their
recorded release times.

Both QEMU image-export suites passed with retained kernels and newly built
test programs. AArch64 completed in 127.0 seconds and x86-64 in 135.0 seconds.
The new test staged two signed publishers and checked concurrent destination
creation, parent replacement, cleanup and successful retry.
[Guest driver](image-export-runtime-check.v)

The independent archive checker verified all 17,501 sealed files and links.
The archive SHA-256 is
`f8475137aea5d01504ae152e501a509e4adf0c8119ac1fb335c0acaf7489ab4e`.
[Qualification archive](/Users/alex/.local/state/vinix/r14-iso-offline-vWmR0y/qualification.tar.gz)

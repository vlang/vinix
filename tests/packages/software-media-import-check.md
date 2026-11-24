# Importing offline bundles in Software

Source revision `a62c7b866861725ead1d57c4411bf69b93584e7f` was qualified on
2026-11-24. Open **Deployment → Offline media…**, enter the absolute directory
and choose **Import media**. After administrator approval, Software passes the
captured directory to the existing signed-bundle import command. It waits for
complete progress and successful process exit before reloading its catalog in
offline mode. If the bundle contains a deployment lock, **Save media lock**
copies it to a new local file for **Review additions** and separate installation
approval. [Offline workflow](../../tools/packages/SDK.md#offline-repository-bundles-in-release-images)

The headless fixture covered full-size and 320×240 controls, literal Unicode and
shell metacharacters, cancellation and authentication refusal, and a complete
progress frame followed by either a held worker or a late failure. An import
with incomplete progress stayed on the media screen. A successful import
reloaded the signed catalog offline and handed the same literal source to lock
saving. A rejected catalog reload kept the previous displayed rows and left
the media directory available. [Software fixture](software_snapshot_fixture.v)

The maintained Software-only distribution suite, standalone package
administrator protocol test and full Linux desktop typechecks for AArch64 and
x86-64 passed. AddressSanitizer and UndefinedBehaviorSanitizer passed for the
full headless Software fixture and save-screen allocation check, with sanitizer
leak detection disabled. The tracked check retained zero bytes across 1,000
media and 1,000 installed-deployment cycles, including rendering the new form.
The archive includes a first build stopped by disk space and an early fixture
with a missing catalog format. The existing import service has separate QEMU
qualification on both targets. [Import service qualification](repository-media-bundle-check.md)

The independent archive checker verified all 874 sealed files. The archive
SHA-256 is `016d266da30777811ff9be30254d3a6fcfdb0850f38b9e6517fb03740acfeead`.
[Qualification archive](/Users/alex/.local/state/vinix/r14-software-media-import-FjolPU/qualification.tar.gz)

## Import with an ISO receipt

Source revision `d5f55530b90282847554a590b77082ed84b3e547` adds
**Import with receipt…** to the offline media screen. The form takes an
absolute ISO receipt path and the receipt SHA-256 from trusted release
checksums. Software freezes the media path, receipt path, and digest for
administrator approval. Cancellation and service refusal preserve the form
for correction or retry. A successful import reloads the catalog offline,
then returns to the approved media directory for lock saving.
[Offline workflow](../../tools/packages/SDK.md#offline-repository-bundles-in-release-images)

The headless fixture checked the 320×240 and full-size forms, keyboard focus,
invalid paste and incomplete digest refusals, literal Unicode and shell
metacharacters, and the exact administrator arguments. It simulated a signed
index mismatch and a complete progress frame before exit. Both the full
Software suite and its ASan/UBSan run passed. Leak detection was disabled.
The tracked save and import form check retained zero bytes across 1,000 media
and 1,000 installed-deployment cycles. Both Linux desktop typechecks passed.
The service has separate native QEMU qualification.
[Receipt-bound service qualification](repository-media-bundle-check.md#receipt-bound-import)

The independent archive checker verified all 863 sealed files. The archive
SHA-256 is `3ce508a14739b28617ce2393f4eba39dd4d763a5c79ac7f0ed4d07602caefc5b`.
[Qualification archive](/Users/alex/.local/state/vinix/r14-software-receipt-import-2N1Kxl/qualification.tar.gz)

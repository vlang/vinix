# Import a complete offline repository directory

Revision `8505d90fd7613c01434afc74b4803ccf540f9fe4` adds
`vinix-package admin update-media MEDIA_DIRECTORY`. It discovers the enrolled
publisher directories within a captured bundle and uses the existing batch
signature, replay, space and acquisition checks. The bundle must be owned by
the importing administrator. Its optional `_deployment.json` stays available
for a separate deployment review.
[Command and offline workflow](../../tools/packages/SDK.md#check-release-image-package-inputs)

The normal and ASan/UBSan host repository suites passed, with leak detection
disabled. The bundle case refused an unenrolled directory, a symlinked bundle
and a symlinked deployment file. A directory added during import caused
refusal before catalog or replay history publication. The exact retry passed
both with and without a deployment file. The administrator request checks
covered the single absolute path form and invalid relative paths.
[Repository fixture](../../tools/packages/pkgcore/image_repositories_test.v)

The production CLI imported two enrolled publishers from one directory into
clean AArch64 and x86-64 alternate roots. The configuration and deployment
lock matched the original bytes after import. After disconnecting the media,
both roots installed the seven advertised apps and the independently signed
fixture app, then passed payload verification. The release audit matched all
ten locked package records on each target. Explicit pairs continued to work.
A partial bundle preserved an omitted publisher's current cached index and
refused when that index was absent. The retained input media are pinned in the
previous qualification archive.
[Batch import inputs](repository-media-batch-check.md)

Both QEMU suites passed with retained kernels and newly built tests. AArch64
completed in 141.2 seconds and x86-64 in 144.1 seconds. The guests exercised
bundle discovery and refusal through the service. Host tests covered the
administrator request contract independently.
[Guest driver](image-export-runtime-check.v)

The independent archive checker verified all 13,242 sealed files and links.
The archive SHA-256 is
`adbc53acc46a38c00ee55ebe0c7161e385507a383beabdf14b8cb420d2cb10e7`.
[Qualification archive](/Users/alex/.local/state/vinix/r14-bundle-import-vQTZER/qualification.tar.gz)

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

## Receipt-bound import

Source revision `9e3d7d9ba2d9e4fa46794425a7eaa98e5a384ee2` adds
`update-media MEDIA_DIRECTORY ISO_RECEIPT.json RECEIPT_SHA256`. The import
checks the exact receipt and lock bytes, target architecture, publisher set,
enrolled keys, signed index digests and sequences, and signed payload byte
counts before acquisition. The catalog uses the same authenticated index
bytes. [Offline workflow](../../tools/packages/SDK.md#check-release-image-package-inputs)

The production and ASan/UBSan host fixtures rejected a semantically identical
receipt or lock with changed bytes, wrong architecture, wrong key, wrong
payload total, missing publisher, and a different release signed by the enrolled
key. The refused attempts left the catalog, replay history, and object cache
untouched. Restoring the approved media allowed import and an exact retry.
The administrator argument checks passed. Leak detection was disabled.

The production CLI imported real exported ISO fixtures using their generated
receipts for both architectures. Each saved lock matched the original and the
consumer retained its configured URL. Both retained expired bundles refused
with their exact receipts. Both complete QEMU suites passed with retained
kernels and rebuilt programs. AArch64 ran in 136.1 seconds and x86-64 in 138.9
seconds. UID 1000 saved and reviewed the lock, and installation verified from
cache after the media was disconnected.

The complete evidence tar restored byte for byte from the persistent
Zstandard delta and passed independent verification of 1,215 sealed files and
links. The delta SHA-256 is
`c7ad34397c6ac3acf879f6e3b6003aedd274dda0699310e196445961de4d3ca1`.
[Restore instructions](/Users/alex/.local/state/vinix/r14-pinned-media-import-pBycTy/RESTORE.md)

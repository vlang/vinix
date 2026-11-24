# Refresh several enrolled publishers from offline media

Revision `fe38e2e2aef9adeebd5198599742a94b8c06d132` extends
`vinix-package admin update-media` to accept multiple repository ID and release
directory pairs. It authenticates the selected indexes with the enrolled keys,
checks replay history and budgets the deduplicated missing objects across the
batch. It publishes one catalog after verification and acquisition. Other
publishers can keep their current authenticated snapshots.
[Command and offline workflow](../../tools/packages/SDK.md#check-release-image-package-inputs)

The host repository suite passed in normal and ASan/UBSan builds with leak
detection disabled. The fixture used two independent publisher keys, reversed
argument order, a shared object and a second publisher's unique object. A bad
signature stopped acquisition. A later corrupt object left the catalog and
replay history unpublished and kept the previously verified object. After
repair, the retry populated the cache and a reviewed install succeeded with
the media disconnected. Administrator request checks covered multi-pair
admission, duplicate IDs and malformed paths.
[Repository fixture](../../tools/packages/pkgcore/image_repositories_test.v)

The production CLI exercised clean AArch64 and x86-64 alternate roots with
two enrolled HTTPS publishers and no cached indexes. Each batch reported one
completion and left the configuration bytes and installed generation intact.
After disconnecting the media, both roots installed the seven mixed-catalog
applications and the independently signed fixture application. Payload
verification passed and the release audit matched all ten locked records on
each architecture. A subsequent single-publisher retry preserved the full
catalog and replay history byte for byte.
[Mixed-catalog inputs](iso-offline-media-check.md)

Both QEMU suites passed with retained kernels and newly built tests. AArch64
completed in 115.7 seconds and x86-64 in 125.1 seconds. The guest fixture
exercised the package service and the host separately checked the
administrator request envelope.
[Guest driver](image-export-runtime-check.v)

The independent archive checker verified all 17,556 sealed files and links.
The archive SHA-256 is
`6e4046642c7028edf84d88f03f5cb718920ecd8e34317a67011f1506089e4367`.
[Qualification archive](/Users/alex/.local/state/vinix/r14-batch-media-jap8jE/qualification.tar.gz)

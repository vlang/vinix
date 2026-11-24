# Import offline media under an enrolled publisher

Revision `4e05fef18703ea3bb3756d40eaaa5113f8b6123f` adds
`vinix-package update-media REPOSITORY_ID RELEASE_DIRECTORY`. It authenticates
the media index as the configured publisher, checks replay floors, and caches
the host and architecture-independent objects allowed by current policy.
Catalog publication follows verified acquisition. The configured URL stays
available for ordinary refresh, and installation uses the normal review flow.
[Command and offline workflow](../../tools/packages/SDK.md#check-release-image-package-inputs)

The image repository suite passed on the host in the normal and ASan/UBSan
builds, with leak detection disabled. A corrupt object in a newer signed index
left the previous catalog and replay history byte-identical. An exact retry
accepted the corrected object, excluded the blocked package's payload, and
then refused the older index. The fixture disconnected the media before a
reviewed install. Administrator protocol checks covered the literal absolute
path, invalid operands and the approved request envelope.
[Repository fixture](../../tools/packages/pkgcore/image_repositories_test.v)

The production CLI imported the retained AArch64 and x86-64 mixed-catalog
exports into clean alternate roots with their original HTTPS configurations.
Both configuration files were byte-identical after import and installation.
Import left generation zero. After disconnecting the media, reviewed offline
installation and payload verification passed for all seven advertised apps.
Each resulting cache contained 2,137 objects.
`verify-installed` matched all ten locked package records per architecture.
A separate two-publisher control refused when the other authenticated snapshot
was absent and preserved that snapshot after a normal targeted refresh.
[Original media qualification](iso-offline-media-check.md)

Both QEMU suites passed with retained kernels and newly built test programs.
AArch64 completed in 114.6 seconds and x86-64 in 123.2 seconds. The guest
test exercised the service directly. The host checked the administrator request
contract independently.
[Guest driver](image-export-runtime-check.v)

The independent archive checker verified all 15,338 sealed files and links.
The archive SHA-256 is
`b90724d117e1aac5ad98fa407044d4bafbe4ba2e6b9e8040c956c0f391be8521`.
[Qualification archive](/Users/alex/.local/state/vinix/r14-media-import-tC4u1O/qualification.tar.gz)

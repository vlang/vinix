# Exact offline deployment in native guests

Source revision `f9ae0ef4d40c5434eee5ecc649d9180a67ad075b` passed the
`packages-image-export` scenario on 2026-11-25. AArch64 completed in 180.0
seconds and x86-64 in 159.0 seconds with the 240-second default. QMP recorded
guest-initiated shutdown on both architectures. The runs booted the retained,
checksum-matched kernels from the signed repository import qualification and
executed freshly built native CLIs and fixtures. Each receipt pins 15 artifacts,
including the production-mode CLI, fixture and raw serial output.
[Guest runner](image-export-runtime-check.v)

The real CLI imported a signed bundle while preserving the consumer's configured
HTTPS URL. An ordinary user with UID 1000 saved the root-owned media's exact lock
bytes to a user-owned directory. After renaming the media directory away, the
same UID reviewed additions and checked missing-package coverage against the
saved digest. Changed bytes, a substituted digest and an omitted digest caused
refusals with unchanged installed metadata. Restoring the original bytes let
the existing review install from cache, reconcile coverage and verify the
installed payloads. The guest fixture runs headless with alternate roots and
structural payloads. The focused host fixture also passed with the production
CLI. [Signed fixture](deployment-snapshot-check.v)

The supplemental host suite reproduced an assertion on blank output from the
existing staging CLI in its sanitizer fixture, including an isolated retry.
The normal staging fixture passed. The host driver and affected package sources
match the preceding revision. The archive preserves the failure logs, both
explicit-timeout passes, the default-timeout runs and the initial build attempts.

The independent checker verified 586 sealed files and links. The archive
SHA-256 is `b9009833f03c5d3295fc89d2124501ca22f235a6ee347c70470179dd73f91f92`.
[Qualification archive](/Users/alex/.local/state/vinix/r14-offline-media-guest-k3y1CW/qualification.tar.gz)

## Host sanitizer follow-up

On 2026-11-25, an instrumented copy of the failing Apple Clang 21 fixture
recorded that the staging child received `SIGKILL` without writing output.
The same staging tool and unchanged fixture passed when the fixture was built
with LLVM Clang 23.1.5. The Apple Clang failure is reproducible on this host.

Source revision `6b689735e1fd2e9c5ddd0f67651ba0dc5f7006e4` makes the sanitizer
compiler selectable and records its path in each receipt. The applications
and export drivers passed all 28 and 32 checks with that override. The
requirements driver passed all 30 checks with LLVM Clang on `PATH`. The three
suites retained ASan and UBSan coverage. A missing compiler was rejected
before creating the work directory in all three drivers.

The independent checker verified all 184 sealed files. The archive SHA-256
is `5e6dbdc970210b3d9657ca7dbce6225b0f6ebe0de7e7fc64cf030dfef4e5bf32`.
[Host qualification archive](/Users/alex/.local/state/vinix/r14-host-sanitizer-Az1boH/host-qualification.tar.gz)

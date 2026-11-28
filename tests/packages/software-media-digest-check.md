# Exact bytes for offline deployment locks

Source revision `9ed47669c2d86a10f0923ce0998ea3812570be1e` was qualified on
2026-11-25. In Software’s **Save media lock** form, the optional **Expected
SHA-256** field takes `deployment_sha256` from a trusted release receipt. Once a
file is saved, Software carries its receipt digest through **Check coverage**,
**Review additions**, and the separately approved apply. The service hashes the
same bytes it decodes. A review fingerprint created with a digest also binds
that digest, so an apply with a missing or different digest is refused.
[Offline workflow](../../tools/packages/SDK.md#offline-repository-bundles-in-release-images)

The signed CLI fixture ran against the normal and sanitized package binaries.
Adding whitespace preserved the unpinned review fingerprint and caused all
three digest-bound operations to refuse. Omitting the digest, substituting the
digest of the changed file, and supplying a fingerprint from an unpinned review
also refused. Installed metadata stayed unchanged until the original bytes were
restored. The original review then applied and coverage matched. The
administrator transport, deployment, audit and review construction tests passed.
[Signed CLI fixture](deployment-snapshot-check.v)

The headless Software fixture covered the 320×240 save form, malformed digest
input, a mismatched save reply and coverage report, coverage reload, and the
literal digest in the approved apply argument list. The maintained Software
suite and both AArch64 and x86-64 Linux typechecks for the CLI and desktop
passed. AddressSanitizer and UndefinedBehaviorSanitizer passed for the Software
fixture, save-screen allocation check, and CLI. Sanitizer leak detection was
disabled. The tracked save-screen check retained zero bytes across 1,000 media
and 1,000 installed-deployment cycles. The archive contains the initial fixture
failure from freeing a borrowed path and the passing runs after the correction.
[Software fixture](software_snapshot_fixture.v)

The independent checker verified all 1,027 sealed files and links. The archive
SHA-256 is `b72edb65726384605668868e8ac17568da2f0acbac06bd6c25ae2e55b0ac51c0`.
[Qualification archive](/Users/alex/.local/state/vinix/r14-software-media-digest-RirCtw/qualification.tar.gz)

## Verified digest from a receipt-bound import

Source revision `d5ea7ef09f6e6937b35b03341b9396c17c07e19b` was qualified on
2026-11-25. The package CLI reports the verified receipt and deployment
digests after publishing the offline catalog. Software waits for successful
worker exit and a single result matching the approved receipt. It uses that
deployment SHA-256 automatically when saving a lock from the approved directory
in the same Offline media view. The save reply must report the same digest,
which then carries into coverage checks, review and separately approved apply.
[Offline workflow](../../tools/packages/SDK.md#offline-repository-bundles-in-release-images)

The host fixture and both native guests checked both result digests from the
real CLI. AArch64 completed in 131.0 seconds and x86-64 in 129.8 seconds.
QMP recorded guest-initiated shutdown on both targets. The Software fixture
exercised an active worker and refused absent, mismatched and duplicate results,
a late worker failure and a mismatched saved digest.
[Signed CLI fixture](deployment-snapshot-check.v) · [Software fixture](software_snapshot_fixture.v)

The Linux desktop typechecks, headless Software suite and LLVM AddressSanitizer
and UndefinedBehaviorSanitizer runs passed. A host suite run with the default
compiler stopped when the session broker crashed, and the rerun with LLVM Clang
passed. Sanitizer leak detection was disabled. After correcting decoder
ownership, 256 valid and 256 invalid decodes retained zero tracked bytes. The
tracked save-screen check retained zero bytes across 1,000 media and 1,000
installed-deployment cycles.

The independent checker verified all 1,456 sealed files and links in the gzip
archive and again after reconstructing the tar from its delta. The gzip
SHA-256 is `05af70ec52eb7d3ab4d6bdaca7381564184717ef2b7a47d6fddbf5ba7b2b38a2`.
The full archive and its delta were copied to persistent storage on 2026-11-28.
The archive passed the independent check again and the delta matched its
recorded checksum.
[Qualification archive](/Users/alex/.local/state/vinix/r14-media-digest-handoff-k943lK/qualification.tar.gz)
and [verification record](/Users/alex/.local/state/vinix/r14-media-digest-handoff-k943lK/restored-archive-check.log).

## Returning to verified media

At `2051d908a4e470e7b772a518cc729f26a1d00348`, reopening **Offline media**
in the same Software window prefills the last receipt-verified directory.
Saving from that directory requires the verified deployment SHA-256. Selecting
another directory offers its own expected digest field. A canceled or refused
re-import preserves the earlier binding. A successful import replaces it and
an import without a receipt leaves the selection unbound.

The headless fixture reproduced an empty media field on baseline `87a5f234f`.
The corrected fixture verified source isolation, navigation through the catalog,
and the original digest on the save and additive review commands. The complete
Software driver passed, including both Linux desktop typechecks and the launcher
fixture. The full headless suite passed under ASan/UBSan with process leak
detection disabled. The tracked allocation check retained zero bytes across
1,000 installed-deployment and 1,000 media cycles, including pin retirement.
[Software fixture](software_snapshot_fixture.v)

The independent checker verified all 1,719 sealed files, including the baseline
and patched sources, host binaries, and test logs. The archive SHA-256 is
`e2edf639604aa55e847763f92372c87b9b1d90149cf3c234ac40aa7d0daf395a`.
[Qualification archive](/Users/alex/.local/state/vinix/mpin.m9ZoYY/qualification.tar.gz)

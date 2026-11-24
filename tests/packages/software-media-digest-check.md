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

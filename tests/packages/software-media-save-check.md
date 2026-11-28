# Saving an offline media lock in Software

Source revision `05fcd7db3d8e0b469e86a430b03f1919327a6743`, qualified on
2026-11-24. After importing the offline bundle, open **Deployment → Save media
lock…** and enter the media directory and a new local filename. Software runs
the existing authenticated save command as the desktop user. The receipt
shows the saved filename, SHA-256, architecture, application roots and package
count. The full-size view offers **Check coverage**. **Review additions** is
available from the full-size and compact receipts, reads the captured local
filename and requires separate approval to install the release apps.
[Offline workflow](../../tools/packages/SDK.md#offline-repository-bundles-in-release-images)

The maintained Software distribution driver passed, including the session
broker chooser and the manual-free allocation suite. The new fixture exercised
literal Unicode and shell metacharacters in both paths, 320×240 and full-size
navigation, writer protection after complete JSON arrived but before exit,
destination binding and additive review and coverage. It rejected mismatched,
truncated, oversized and wrong-type receipts, nonzero exits with valid-looking
JSON and an existing destination. The first run caught an outdated expectation
for the last compact Deployment action. The corrected suite passed.
[Software fixture](software_snapshot_fixture.v)

The strict receipt protocol test and both full desktop Linux typechecks
(AArch64 and x86-64) passed. The complete headless functional suite and the
save-screen allocation check also passed under AddressSanitizer and
UndefinedBehaviorSanitizer. The tracked save check retained zero bytes across
1,000 installed and 1,000 media receipt and retirement cycles. The sanitizer run
had leak detection disabled. Guest publication and installation after media
removal are covered by the earlier service qualification. This run exercised
the Software controller headlessly. [Service qualification](deployment-media-save-check.md)

The independent checker verified all 867 sealed files in the bundle, including
the build inputs, executables and logs. The archive SHA-256 is
`6f949f26b0ca21c0b0a83edfa65dadf4b5e1a2f456d6c2dfdca8cfa634bb39c5`.
[Qualification archive](/Users/alex/.local/state/vinix/r14-software-media-save-Zwqreg/qualification.tar.gz)

## Saving and retrying under restrictive policy

At `942b62da7db438806d3759eb20008f04a2aaf5dd`, supplying the trusted
deployment SHA-256 lets an ordinary user save the exact signed release lock
before local policy allows installation. The save checks publisher trust and
the complete dependency closure. Review and apply enforce current policy.
Software keeps its most recently saved path bound to the digest while the
window is open, including after a refused review. Selecting that path offers
**Check coverage** and **Review additions**. [Offline workflow](../../tools/packages/SDK.md#offline-repository-bundles-in-release-images)

The previous production CLI refused the save under restrictive policy. The new
CLI passed the pinned scenario in production and with ASan/UBSan. An unpinned
save under restrictive policy still refused without creating a file. A matching
digest still refused a lock with a missing dependency or absent publisher trust.
After the media was disconnected, review refused under restrictive policy and
preserved the lock and installed state. Restoring policy allowed the ordinary-user
review and separately approved apply to install from cache. The full native
package-image suites passed and shut down cleanly on AArch64 (308.5 seconds)
and x86-64 (291.7 seconds).
[Native fixture](deployment-snapshot-check.v)

The headless Software checks passed at 320×240 and 640×610, including a changed
file refusal on retry and ordinary deployment review for a different path.
Both Linux desktop typechecks passed. The full headless functional suite also
passed with ASan/UBSan and process leak detection disabled. The tracked save
fixture retained zero bytes across 1,000 installed and 1,000 media cycles.
[Software fixture](software_snapshot_fixture.v)

The desktop driver's separate launcher fixture needed the Fontstash include
path and implementation to link on this host. With both supplied, the mirror
assertions failed on this change and baseline `4f6e57621` because the export
fixture supplied installed versions. Commit `414014fc8e929d6dfaf015d27670c64ce9407723`
adds the link inputs and gives the export rows empty installed versions. The
standalone launcher runner passed both mirror modes with zero tracked bytes
retained. The independent checker verified all 719 files in the rerun archive.
Its SHA-256 is `9c011f15163c757108cc32e9395f3f423572734db00e8b4dc0a74a8dd0b677e5`.
[Launcher rerun archive](/Users/alex/.local/state/vinix/msave-j90lpq/launcher-qualification.tar.gz)

The independent checker verified 2,884 sealed entries in the main archive,
including source, fixture inputs, native builds, serial and QMP logs, and the
host, sanitizer, and baseline launcher runs. Its SHA-256 is
`369da3fd6a32c416af216379a8b5d393df1ded79c5ba2bfd0f05f73b0f5900c7`.
[Qualification archive](/Users/alex/.local/state/vinix/msave-j90lpq/qualification.tar.gz)

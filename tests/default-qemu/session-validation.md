# Desktop session regression — 2026-11-12

Source: the desktop changes in this commit on top of the default-QEMU input
fix. The retained `session-source.patch` applies to
`51f51ed26380bc087ec3cb5e6df6240e39c18d8d`; its SHA-256 is
`34fbd86c58ce688ce8c3c48defb7f564bba86147efffca4c16179d812266a705`.

The `iso-2026-11-12` desktop failed during redraws with a malloc panic or
SIGSEGV. At the captured fault, its kernel memory-owner charge was
127,663,804 bytes against a 127,664,384-byte limit, with 43 denied charges.
The process had 60,866,560 resident bytes and the guest still had more than
1.5 GiB free. Logging in again restored saved windows after the old process
died; this was not an idle screen lock.

Current UI2 gives every Element six allocating stylesheet maps. Frame cleanup
did not release them. Caption placeholders, unused toolbars, and application
root wrappers also discarded their metadata. Cleanup now follows the frame's
lifetime while Calculator's cached declarations retain their own maps.

All 17 desktop memory tests pass with heap tracking, including menus,
themes, Files, Activity Monitor, remote trees and Calculator. The three new
regressions cover 40 desktop redraws, 40 Calculator frames sharing a cached
layout, and closing an unused Calculator. The two UI2 staging tests also pass.
The rebuilt desktop survived the hover sequence in the existing plain QEMU
guest (2 GiB, default devices) without returning to the greeter.

UI2's separate headless native-host dependencies are fixed upstream in
<https://github.com/vlang/ui2/pull/120>. Its query test passes four assertions.

Artifacts and checksums are retained outside Git at:
`/home/pancake/vinix-artifacts/desktop-session-2026-11-12/`.
The bundle includes crash logs, generated C, staged source, build logs,
test results, desktop binaries and screenshots. `vinix-amd64.iso` replaces
the release kernel and desktop, and includes the current session manager
so its isolated groups match the desktop sandbox. It contains no diagnostic
init wrapper or seeded test account.

Rebuild notes: V `596e18de73afb4fd15569c221f5583b9053db80f`, UI2
`f18e784d96a27991974ef8cfdd25b33830a9f067`, Clang 21, release musl SDK.
This is a focused rebuild, not a clean release-pipeline qualification.
Staged compatibility edits replace the obsolete, unused `$vml` helper with
the already-used native Calculator layout, normalize conflicting C read/write
declarations, and use signed memcpy lengths for this V version. Translation
uses `-gc none -manualfree`, followed by static Clang `-O2`; V `-prod` is
omitted because existing `usize` deprecations otherwise prevent translation.
The exact staged inputs are retained for audit. No compiler changes are
proposed as part of the crash fix.

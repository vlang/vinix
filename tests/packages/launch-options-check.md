# Software launch options qualification

Software's **Launch options…** form runs installed applications with quoted
literal arguments, explicit existing-file grants and a choice of working folder.
Batch commands retain their draft and useful diagnostics after failure. Terminal
commands transfer the exact vector to Software's PTY. Input is frozen while a
worker runs; cancellation, reload and close retire the form's storage.

The form defaults to private application data so command-line tools can create
relative outputs. The additive SDK `--data-cwd` option carries this choice across
the isolated ordinary-account handoff. It changes the working folder only;
permissions, path grants, fixed manifest arguments, generation leases and trust
checks retain their normal behavior. Existing CLI commands without the option
continue to work from the installed application's directory. See the
[SDK contract](../../tools/packages/SDK.md#literal-command-arguments).

Launch controls now read installed name/kind/permissions separately from the
pending upgrade's presentation. Tests cover an installed native app with no
document permission whose proposed update is a data package requesting files.
The installed app remains launchable and does not inherit that proposed grant.
The format-1 view fields are additive; older presentations retain their fallback.

`pkgprotocol/command_test.v` covers empty arguments, adjacent quote fragments,
single/double quotes, backslash escapes, literal variables/shell punctuation,
quoted newlines, unmatched quotes, trailing escapes, NUL and count/byte bounds.
`pkgcore/command_test.v` checks parsing, duplicate working-folder refusal, exact
handoff vectors, unchanged grants and the private/installed working-folder plans.
The final installed-presentation assertions run separately through `view_test.v`.

The initial distribution run passed **23** signing/core/protocol/registry runners,
CLI lifecycle/refusal and host PTY tests, then stopped because the new UI fixture
had not initialized the normal search buffer. After correcting that fixture,
the Software worker/UI checks, both target staging builds and both desktop
typechecks passed in the remainder run. That run stopped at the new heap test.
The final launcher test passed separately after explicitly freeing the parser's
consumed error object and retiring an expected-vector allocation made by the
test itself. A final Software-only run verifies the completed form/worker code.
These are separate recorded phases, not one uninterrupted successful driver run.

The native desktop heap tracker measures repeated form editing/rendering,
malformed-quote refusal, file paging/removal, cancellation and terminal transfer.
After warmup, the tracked edit/render/refusal/transfer cycles retain **zero
bytes**. The actual Terminal implementation is used, including its existing
spawn/poll/retirement assertions. A separate clang ASan/UBSan run checks the
quoted-argument protocol; leak detection is disabled there.

Both QEMU TCG guests build a fresh service/account/session fixture with the
previously qualified cached kernel and native sandbox, and reuse the pinned
[FFmpeg 8.0.1 inputs](ffmpeg-profile-check.md). The guest invokes the same quoted
argument parser and vector builder as Software. Through the production CLI it
encodes video into `relative output; $literal.avi`, verifies ordinary ownership
and its location under private data, checks that no file appeared in the
immutable installed payload, and probes it only after an explicit file grant.
The broader real video/audio, PTY, outside-path refusal, shared-runtime removal,
rollback, offline-cache reinstall and media-retention workflow also passes.

Retained evidence contains 50 artifact hashes per guest and a 600-second
functional deadline, including all 42 pinned FFmpeg input files, the input build
record, kernel, init, service, sandbox, account/session tools and serial log:

- [AArch64 receipt](results/2026-10-13/launch-options-aarch64.json) and
  [serial log](results/2026-10-13/launch-options-aarch64.serial.txt): 33.4 seconds.
- [x86_64 receipt](results/2026-10-13/launch-options-x86_64.json) and
  [serial log](results/2026-10-13/launch-options-x86_64.serial.txt): 44.9 seconds.
- [Host results](results/2026-10-13/launch-options-host.txt) and
  [toolchain/evidence ledger](results/2026-10-13/launch-options-toolchain.json).

UI coverage is headless, and guest execution uses the retained kernel/compiler
tuple. It does not qualify graphical login/display brokerage, arbitrary app
argument grammars, performance or persistence across power cuts. Public release
publisher enrollment and the remaining native/Linux/Windows/Apple catalog remain
separate roadmap acceptance work.

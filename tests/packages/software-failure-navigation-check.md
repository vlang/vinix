# Readable compact service diagnostics

Software's **Failure details** can be read in compact windows at least 200 pixels
high, including a 180-pixel-wide view. Cached short pages contain up to three
12-byte lines split at UTF-8 boundaries. They preserve every non-newline byte
of the existing bounded, normalized and escaped diagnostic snapshot. The compact
view shows operation/exit context, page count, truncation disclosure, Back and
Previous/Next. Left/Right and Page Up/Page Down navigate in either view. Paste
cannot execute these navigation keys or dismiss the viewer.

The native desktop draws a label as one line. Both full and compact diagnostic
pages now use separate monospace labels for their prepared lines, so an embedded
newline cannot hide later text. Full pages retain their fourteen 48-byte lines;
compact pages borrow separately prepared owned text. Redraw allocates no text.
Frame capacity includes all fourteen labels and existing controls.

Every short page records its canonical full-page index. Resizing to a full view
shows that page; resizing back restores the exact short-page cursor. Full-page
navigation followed by shrinking starts at the corresponding first short page.
Views below 180 pixels wide or 200 high retain Back and preserve the cursor.
Clearing, replacement and application retirement release both page sets and
reset navigation state. The underlying catalog/form remains unchanged, with no
package operation or retry available while viewing diagnostics.

The maintained [fixture](software_failure_fixture.v) compares complete full and
compact content, checks all short-page UTF-8/byte/row bounds and walks every
compact page through the real builder and keyboard handlers. It checks every
rendered line, element bounds, first/last-page clamps, keyboard variants,
full/compact/narrow/minimum-size resizing, canonical remapping, modal action and
paste isolation, truncation disclosure and clearing. Existing checks retain a
real failed service child, progress filtering, reload retention, later failure
replacement and absent/invalid/oversized diagnostics.
Blank canonical pages also retain a short-page anchor.

The extended `failure-memory` mode measures 1,000 capture/full/compact/all-short-
pages/keys/resize/back/replace/clear cycles after warmup under
`-gc none -manualfree -d track_heap`. No worker is spawned in allocation
measurement. This does not measure whole-service allocation freedom.

These are host headless UI checks and desktop architecture typechecks. Existing
[failure qualification](software-failure-check.md) retains its scope. No new
guest graphical acceptance or complete publisher/catalog/runtime release
qualification is claimed. Service arguments, output retention limits,
authorization and protocol are unchanged.


## Recorded results, 2026-10-15

All 30 focused compile/run checks passed: the complete Software functional
fixture and twenty-five allocation modes, plus ASan/UBSan functional and failure
navigation allocation checks. The maintained Software-only distribution driver
passed independently with all twenty-five allocation modes. Extended failure
cycles retained zero tracked bytes over 1,000 iterations. Allocation checks do
not spawn workers; functional checks retain the real service-child failure.
Sanitizer leak detection was disabled. This does not measure whole-service
allocation freedom.

Both full desktop architecture typechecks passed. Compiler, Software/protocol/UI
inputs, staged sources, binaries and logs are pinned. An initial compile/typecheck local-name
collision and its correction are retained in the execution notes. Service arguments, retained-output bounds, authorization
and protocol are unchanged. No new guest graphical or broader release acceptance
is claimed.

- [focused checks](results/2026-10-15/software-failure-navigation-host.json)
- [summary](results/2026-10-15/software-failure-navigation-host.txt)
- [Software and maintained driver](results/2026-10-15/software-failure-navigation-ui.txt)
- [allocation modes](results/2026-10-15/software-failure-navigation-memory.txt)
- [sanitizers](results/2026-10-15/software-failure-navigation-asan.txt)
- [desktop architecture checks](results/2026-10-15/software-failure-navigation-desktop.txt)
- [execution notes](results/2026-10-15/software-failure-navigation-attempts.txt)
- [compiler/source/artifact ledger](results/2026-10-15/software-failure-navigation-toolchain.json)

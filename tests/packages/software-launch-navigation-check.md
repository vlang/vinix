# Launch-option compact navigation and draft lifetime

Software's Launch options form now keeps Back, status and failure access in
small windows. Editor, grant, working-folder and Run/Run in Terminal controls
appear in the full form. Resize does not change arguments, explicit file grants,
working folder, field focus, selection or file-page position. Escape leaves a
focused field and clears its selection; from an idle form it returns to the
catalog and discards the draft.
Pasted Escape, Enter, editing controls, invalid UTF-8 and oversized replacements
are rejected without changing the field, focus or navigation.

Running batch workers keep their runtime leases and existing close guard.
Back, Escape, repeated launch, file/editor, catalog and external launch actions
cannot change or interrupt them. The compact view explains how to return after
the app exits. Failure diagnostics and the exact draft remain available after
exit for correction, retry or transfer to Terminal. Launch still uses installed
name/kind/permissions, including an explicitly empty installed permission set.
Service arguments, quoting, authorization, file access and protocol are unchanged.

The maintained [fixture](software_launch_navigation_fixture.v) holds real child
workers behind stdin barriers. It checks compact/full controls, resize stability,
file paging/removal, keyboard versus paste behavior, invalid/unsubmitted input,
protected worker success/failure, exact Unicode/space/metacharacter arguments,
empty quoted arguments, distinct file grants and installed working folder,
failure navigation, retry and exact Terminal vector transfer. Catalog query,
filter and selection are preserved when the draft is discarded. Installed
permission checks also cover a pending candidate that advertises extra access.

The `launch-navigation-memory` mode measures 1,000 cycles after warmup under
`-gc none -manualfree -d track_heap`: a 256-file draft, count-bound refusal,
full/compact rendering, file removal/readdition, rejected paste, Escape blur,
failure presentation, Terminal vector transfer and retirement, and idle Back.
The live status is cleared before sampling. The Software-only Terminal stub
checks command ownership and transfer; these checks do not measure real PTY,
whole-service or worker-process allocation freedom.

These are host headless UI checks. Existing [launch-option qualification](launch-options-check.md)
and [terminal qualification](terminal-check.md) retain their scope. Ordinary
graphical sessions, release publisher/catalog migration and broader runtime
acceptance remain separate release gates.


## Recorded results, 2026-10-15

All 28 focused compile/run checks passed: the complete Software functional
fixture and twenty-three allocation modes, plus ASan/UBSan functional and launch
navigation allocation checks. The maintained Software-only distribution driver
passed independently with all twenty-three allocation modes. Navigation retained
zero tracked bytes over 1,000 256-file draft/full/compact/paging/paste/blur/
failure/Terminal-transfer/retirement cycles, including idle Back, after clearing
the live status before sampling. Sanitizer leak detection was disabled. These
checks do not measure real PTY, whole-service or worker-process memory freedom.

The initial allocation run retained 24,862,000 bytes over 1,000 cycles in the
Software-only Terminal stub, which grew its command array without releasing
replaced buffers. The stub now reserves the complete vector and uses the same
array ownership flag as production Terminal, which already did so. The failed
measurement is retained separately; final runs retained zero tracked bytes.

Both full desktop architecture typechecks passed. Compiler, Software/protocol/UI
inputs, staged sources, binaries and logs are pinned. Service, command vectors,
installed permissions, ordinary-account authorization and protocol are unchanged.
No new guest graphical or broader release acceptance is claimed.

- [focused checks](results/2026-10-15/software-launch-navigation-host.json)
- [summary](results/2026-10-15/software-launch-navigation-host.txt)
- [Software and maintained driver](results/2026-10-15/software-launch-navigation-ui.txt)
- [allocation modes](results/2026-10-15/software-launch-navigation-memory.txt)
- [sanitizers](results/2026-10-15/software-launch-navigation-asan.txt)
- [desktop architecture checks](results/2026-10-15/software-launch-navigation-desktop.txt)
- [initial attempts](results/2026-10-15/software-launch-navigation-attempts.txt)
- [compiler/source/artifact ledger](results/2026-10-15/software-launch-navigation-toolchain.json)

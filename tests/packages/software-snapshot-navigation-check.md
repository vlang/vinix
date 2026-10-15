# Installed deployment save navigation

Software's **Save installed…** filename field now distinguishes paste from
keyboard input. A pasted Escape, Enter, Select all or Backspace cannot navigate,
blur, select or delete the draft. Pasted controls, invalid UTF-8 and oversized
edits are refused as a whole, leaving the literal filename and selection intact.
Printable Unicode, spaces and shell metacharacters retain their existing
literal argv behavior and 4096-byte bound. Escape leaves a focused field and
clears its selection before a second Escape returns to Deployment. Pasting
while unfocused or viewing an accepted receipt does nothing.

Compact windows show the current status, Back when idle, and retained failure
access. A pending writer shows a wait message. Draft text, focus and receipt
detail page survive resizing. Filename and follow-up actions remain available
in the full view.

Saving still protects its independently captured destination. The maintained
[fixture](software_snapshot_fixture.v) uses real child processes held behind
stdin barriers after partial and complete receipts. Back, Escape, Save another,
duplicate Save, review/audit/export, generic Cancel, unrelated Stop commands,
editing, pasting, resizing and ordinary closing cannot kill or redirect those
writers. A complete receipt remains provisional until the service exits. Exit 0
admits the bound receipt; a late failure exposes diagnostics and no receipt.
Catalog search/filter/selection remain unchanged. Existing service arguments,
authorization, output limits and final receipt admission are unchanged.

The extended `snapshot-memory` mode measures 1,000 literal paste/control refusal,
focus/selection, full/compact rendering, receipt paging, destination mismatch and
retirement cycles after warmup under `-gc none -manualfree -d track_heap`. The
live status is retired before sampling. These cycles do not spawn workers or
measure whole-service allocation freedom.

These are host headless Software checks. Existing [save qualification](software-deployment-save-check.md)
and [service qualification](deployment-save-check.md) retain their scope.
Ordinary graphical sessions and release publisher/catalog/runtime qualification
remain separate release gates.


## Recorded results, 2026-10-15

All 30 focused compile/run checks passed: the complete Software functional
fixture and twenty-five allocation modes, plus ASan/UBSan functional and save
navigation allocation checks. The maintained Software-only distribution driver
passed independently with all twenty-five allocation modes. Save presentation
retained zero tracked bytes across 1,000 literal paste/control refusal/blur/full/
compact/receipt/paging/mismatch/retirement cycles after clearing the live status.
Allocation checks do not spawn workers; functional checks use real children.
Sanitizer leak detection was disabled. This does not measure whole-service
allocation freedom.

Both full desktop architecture typechecks passed. Compiler, Software/protocol/UI
inputs, staged sources, binaries and logs are pinned. No failed execution
attempts were observed. Service arguments, authorization, output bounds and
final receipt/exit admission are unchanged. No new guest graphical or broader
release acceptance is claimed.

- [focused checks](results/2026-10-15/software-snapshot-navigation-host.json)
- [summary](results/2026-10-15/software-snapshot-navigation-host.txt)
- [Software and maintained driver](results/2026-10-15/software-snapshot-navigation-ui.txt)
- [allocation modes](results/2026-10-15/software-snapshot-navigation-memory.txt)
- [sanitizers](results/2026-10-15/software-snapshot-navigation-asan.txt)
- [desktop architecture checks](results/2026-10-15/software-snapshot-navigation-desktop.txt)
- [execution notes](results/2026-10-15/software-snapshot-navigation-attempts.txt)
- [compiler/source/artifact ledger](results/2026-10-15/software-snapshot-navigation-toolchain.json)

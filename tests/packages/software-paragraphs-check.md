# Native Software warning and status paragraphs

The native renderer draws a single line for each label. Software's common
paragraph helper previously depended on a multiline style the renderer ignores.
It now creates a transparent container with individual monospace line labels.
Lines borrow UTF-8 slices from the container's original text, break at spaces
where possible and preserve explicit newlines. Long unbroken identifiers, keys
and paths use the full row width. When text exceeds the available rows, a
separate final ellipsis marks the omission. The complete original text remains
the container's accessibility label. Existing short single-line labels retain
their style.

The helper budgets eight logical pixels per UTF-8 byte and eighteen pixels per
row. A maintained [font check](software-label-font-check.v), also run by the
distribution driver, validates both native mono atlas scales using the same
advance-to-logical-pixel conversion as the renderer. The prepared disclosure
pages keep their separate existing pagination and line renderer.

The maintained [Software fixture](software_details_fixture.v) reconstructs the
actual drawn lines and checks full text, byte budgets, UTF-8, geometry and
borrowed ownership. It covers explicit blank lines, long Unicode text and paths,
visible overflow and the complete destructive deletion, trust, launch,
deployment, saved-deployment and offline-export warnings at 640 by 610. Publisher
keys and permissions also fit the narrow catalog panel. At 320 by 280 and
640 by 610, administrator explanations remain complete and status stays below
the password and approval controls. These frame builds do not start a worker.

The existing details allocation mode now retires an owned wrapped paragraph and
a borrowed truncated paragraph on each of its 1,000 cycles. All twenty-five
allocation modes remain regression checks. Nine affected modes also run under
ASan/UBSan. Allocation measurements cover the exercised frame lifetimes after
their existing retirement steps; they do not establish whole-service or
spawned-worker allocation freedom.

These are headless host layout checks, native font metric checks and full
desktop architecture typechecks. They do not claim new guest graphical
acceptance. Ordinary graphical sessions, publisher/catalog rollout and broader
runtime release qualification remain open.


## Recorded results, 2026-10-15

All 40 focused compile/run checks passed: the complete Software functional
fixture and twenty-five allocation modes, ASan/UBSan functional and nine affected
allocation modes, and the native font metrics compile/run check. The independent
maintained Software-only distribution driver passed with the font check and all
twenty-five allocation modes. The extended details mode retains zero tracked
bytes over 1,000 owned/borrowed/wrapped/truncated paragraph retirement cycles.
All other allocation modes also pass their existing zero-retention checks.
Sanitizer leak detection was disabled. These checks do not measure whole-service
or spawned-worker allocation freedom.

Both full desktop architecture typechecks passed after the final source change.
Compiler, Software/protocol/UI inputs, staged sources, binaries and logs are
pinned. Initial font-scale and launch-default fixture mistakes were corrected.
A real long-key wrapping failure was then diagnosed and fixed by filling rows
when an identifier exceeds a whole row. All initial logs and source snapshots
are pinned. Service arguments, authorization and protocol are unchanged. No new
guest graphical or broader release acceptance is claimed.

- [focused checks](results/2026-10-15/software-paragraphs-host.json)
- [summary](results/2026-10-15/software-paragraphs-host.txt)
- [Software and maintained driver](results/2026-10-15/software-paragraphs-ui.txt)
- [allocation modes](results/2026-10-15/software-paragraphs-memory.txt)
- [sanitizers](results/2026-10-15/software-paragraphs-asan.txt)
- [desktop architecture checks](results/2026-10-15/software-paragraphs-desktop.txt)
- [execution notes](results/2026-10-15/software-paragraphs-attempts.txt)
- [compiler/source/artifact ledger](results/2026-10-15/software-paragraphs-toolchain.json)

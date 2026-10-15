# Compact organization-policy disclosures

Compact policy windows formerly retained lifecycle controls and diagnostics but
required enlargement to inspect loaded settings and reviews. They now offer
**Read policy** after a complete valid policy or proposal has loaded. The reader
is a read-only modal: Back or Escape returns to the same current policy or frozen
review. Confirm, Cancel, reload, file editing, package actions, failure actions
and application requests cannot run through it. Pending reads and approved saves
cannot open it, and confirmation remains on the full policy screen.

At 180×220 and above, it shows three separately rendered monospace lines per
short page with UTF-8 boundaries and a twelve-byte line bound. Every canonical
heading and body is preserved, including previous/proposed labels, long source
filenames, licensing, publisher keys and installed-app before/after diagnostics.
Prepared short pages are grouped by topic so both previous and proposed settings
remain reachable even though their canonical document pages are interleaved.

Previous/Next, Left/Right and Page keys turn pages within the topic. Topic
controls, Up/Down and Tab/Shift-Tab skip unavailable categories without wrapping.
Full-size reader views show the canonical page and available topic tabs.
Resizing retains the exact short page when its canonical page stays selected;
full-page navigation anchors the first fragment of the new canonical page.
Tiny windows retain Back. No pagination or disclosure text is allocated on redraw.
Clearing/reloading/cancelling policy pages retires their compact cache and modal
state together.

The maintained [policy fixture](software_policy_fixture.v) reconstructs every
canonical heading/body from compact fragments for current policy, a reviewed
change and a long Unicode source/diagnostic review. It traverses every short
page through the actual app dispatcher at 180×220 and 320×240, checks the native
line labels and geometry, all-topic navigation/boundaries, keyboard controls,
full/compact/tiny resizing, read-only modal isolation, Back and frozen intent.
Its existing credential transport, literal confirmation, stale/failure handling
and policy persistence checks remain intact.

[Navigation barriers](software_policy_navigation_fixture.v) check that partial
and complete-before-exit readers and approved saves cannot open the disclosure.
Its 1,000 current/review/render/cancel/retirement cycles now enter the reader,
turn short pages/topics, resize, refuse confirmation and return. The separate
wide-policy allocation mode exercises cache preparation, replacement and cleanup.
All twenty-five allocation modes remain regression checks; ASan/UBSan covers
the functional suite and both policy allocation modes. Native font metrics, the
independent maintained driver and full desktop architecture typechecks qualify
this host change. Sanitizer leak detection is disabled; these checks do not
establish whole-service or spawned-worker allocation freedom or new guest
graphical acceptance. Broader roadmap 14 release qualification remains open.


## Recorded results, 2026-10-15

All 33 focused compile/run checks passed: the complete Software functional
fixture, all twenty-five allocation modes, ASan/UBSan functional plus policy
navigation and wide-policy allocation modes, and native font metrics. The
maintained Software-only distribution driver passed independently with all
twenty-five allocation modes and the font check. Both policy modes retain zero
tracked bytes over 1,000 preparation/navigation/render/cache-retirement cycles.
Sanitizer leak detection was disabled; these checks do not establish whole-
service or spawned-worker allocation freedom. Both full desktop architecture
typechecks passed.

No failed executions were observed. The frozen compiler runs with -nocache,
fallback and automatic compiler error reporting disabled. Compiler, Software/
protocol/UI inputs, staged sources, binaries and logs are pinned. Service
arguments, authorization, reviewed source/fingerprint and public protocols are
unchanged. No new guest graphical or wider publisher/catalog/runtime release
acceptance is claimed.

- [focused checks](results/2026-10-15/software-policy-reader-host.json)
- [summary](results/2026-10-15/software-policy-reader-host.txt)
- [Software and maintained driver](results/2026-10-15/software-policy-reader-ui.txt)
- [allocation modes](results/2026-10-15/software-policy-reader-memory.txt)
- [sanitizers](results/2026-10-15/software-policy-reader-asan.txt)
- [desktop architecture checks](results/2026-10-15/software-policy-reader-desktop.txt)
- [execution notes](results/2026-10-15/software-policy-reader-attempts.txt)
- [compiler/source/artifact ledger](results/2026-10-15/software-policy-reader-toolchain.json)

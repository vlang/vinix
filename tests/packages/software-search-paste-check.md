# Software search clipboard input

Catalog paste events previously passed through keyboard dispatch. Pasted Enter
blurred the search and editing controls could select or delete its query. The
catalog and health fields silently removed malformed/control bytes and clipped
oversized text; audit search already rejected invalid text but an empty selected
paste cleared it.

All three search fields now share literal, bounded insertion. A nonempty paste
must fit the complete 256-byte field and contain valid UTF-8 without C0, DEL or
C1 controls. Refusal preserves query, focus, text selection, result projection
and page, and reports a useful diagnostic. Empty/unfocused pastes are no-ops.
The root dispatcher sends catalog paste directly to its data handler; keyboard
commands retain their existing behavior. Searching during a catalog reload stays
available, while proposals, verification and approved writes retain their guards.

The maintained [catalog fixture](software_view_fixture.v) exercises all three
fields through the actual app dispatcher, selected/unselected. Coverage includes
standalone/embedded controls, malformed/truncated/overlong/surrogate/out-of-range
UTF-8, C1, exact multibyte byte limits, append/replacement overflow, literal
Unicode and shell punctuation, empty/unfocused input and real keyboard editing.
A live catalog reader holds at an input barrier while searching, rejects pasted
Escape and admits its complete response only after successful worker exit.

[Package navigation](software_package_navigation_fixture.v) exercises pasted
controls during partial/complete-before-exit proposals, completed frozen reviews
and approved transaction/refresh workers. Worker identity, query, selection,
proposal/fingerprint, status and output stay intact. The existing verification
barriers also receive pasted controls without stopping their worker. Actual
keyboard Stop/Cancel/Escape and confirmation still have their existing checks.

Catalog, health and audit allocation modes add literal/rejected/selected/empty
input to 1,000 existing reload/search/render/retirement cycles. The full Software
fixture, all twenty-five allocation modes, independent maintained driver,
ASan/UBSan affected modes, native font metrics and both full desktop architecture
typechecks qualify this change. Sanitizer leak detection is disabled; these are
host checks, not whole-service/spawned-worker allocation measurements or new
guest graphical acceptance. Roadmap 14 publisher/catalog/runtime release
qualification and ordinary graphical sessions remain open.


## Recorded results, 2026-10-15

All 36 focused compile/run checks passed: the complete Software functional
fixture, all twenty-five allocation modes, ASan/UBSan functional plus catalog,
health, audit-search, package-navigation and verification-navigation allocation
modes, and the existing native font metrics check. The maintained Software-only
distribution driver passed independently with all twenty-five allocation modes
and the font check. Catalog, health and audit input retains zero tracked bytes
over 1,000 literal/rejected/selected/empty input and existing report/search/
render/retirement cycles. Sanitizer leak detection was disabled. These checks
do not establish whole-service or spawned-worker allocation freedom. Both full
desktop architecture typechecks passed.

No failed executions were observed. Before testing, 71,835,028 bytes of retired,
unpinned generated C were removed after confirming their private package
workspace source paths. The recovery log is pinned; existing evidence, binaries
and sources were preserved. The frozen compiler runs with -nocache, fallback
and automatic compiler error reporting disabled. Compiler, Software/protocol/UI
inputs, staged sources, binaries and logs are pinned. Service arguments, reviewed
intent, authorization and protocol are unchanged. No new guest graphical or
wider publisher/catalog/runtime release acceptance is claimed.

- [focused checks](results/2026-10-15/software-search-paste-host.json)
- [summary](results/2026-10-15/software-search-paste-host.txt)
- [Software and maintained driver](results/2026-10-15/software-search-paste-ui.txt)
- [allocation modes](results/2026-10-15/software-search-paste-memory.txt)
- [sanitizers](results/2026-10-15/software-search-paste-asan.txt)
- [desktop architecture checks](results/2026-10-15/software-search-paste-desktop.txt)
- [execution notes](results/2026-10-15/software-search-paste-attempts.txt)
- [compiler/source/artifact ledger](results/2026-10-15/software-search-paste-toolchain.json)

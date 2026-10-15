# Literal Software repository clipboard input

The repository form previously sent clipboard contents through the key handler.
A pasted Enter could start a trust review, pasted Escape could cancel a review
or stop its reader, and other controls could change focus/selection or be
silently removed from a source URL. Invalid UTF-8 could also enter the form.

A dedicated paste handler now treats clipboard text as literal field data. It
refuses controls (C0, DEL and C1), malformed UTF-8 and oversized input as a whole.
The field, focus and select-all state survive refusal; a diagnostic explains
invalid text or length. ID, URL and key retain their existing 128, 4096 and
64-byte limits. Accepted text is appended or replaces the selected field without
filtering bytes. Empty or unfocused pastes do nothing. All pastes are ignored
during repository reads, frozen reviews and approved writes. Keyboard commands
remain separate; ordinary typed text uses the same validation before insertion.
Repository ID, source and key syntax are still validated before reviewing trust.

The maintained [fixture](software_repository_navigation_fixture.v) checks every
field with and without select-all. Cases include standalone and embedded
controls, invalid/truncated UTF-8, surrogate encodings, C1 controls,
exact-size values, literal Unicode/spaces/shell punctuation, append/replace
overflow, preserved selection and empty/unfocused paste. Real keyboard Enter
starts a literal-argument review, UTF-8 backspace still works, and keyboard
Escape still cancels. Pasted commands leave its fingerprint and URL paging
unchanged. Existing live barriers also exercise pasted controls during partial
and complete-before-exit listing/review workers and approved apply/refresh
workers. No paste can trigger trust publication or cancel these operations.

The existing repository-navigation allocation mode adds accepted/rejected and
selected-field input to each of its 1,000 configuration/review/render/retirement
cycles. All twenty-five allocation modes remain regression checks; repository
navigation and metadata allocation modes also run under ASan/UBSan. These are
headless host tests and full desktop architecture typechecks, not new guest
graphical acceptance or whole-service/spawned-worker allocation measurements.
Ordinary graphical sessions and publisher/catalog/runtime release qualification
remain open.


## Recorded results, 2026-10-15

All 33 focused compile/run checks passed: the complete Software functional
fixture, all twenty-five allocation modes, ASan/UBSan functional plus repository
navigation and metadata allocation modes, and the existing font metrics check.
The maintained Software-only distribution driver passed independently with all
twenty-five allocation modes and the font check. Repository navigation retains
zero tracked bytes over 1,000 valid/rejected/selected-input and existing
configuration/review/render/retirement cycles. Sanitizer leak detection was
disabled. These measurements do not establish whole-service or spawned-worker
allocation freedom. Both full desktop architecture typechecks passed.

No failed executions were observed. All compiler invocations use the frozen
compiler with caching, fallback and automatic compiler error reporting disabled.
Compiler, Software/protocol/UI inputs, staged sources, binaries and logs are
pinned. Service arguments, trust review validation, fingerprints, authorization
and protocol are unchanged. No new guest graphical or wider publisher/catalog/
runtime release acceptance is claimed.

- [focused checks](results/2026-10-15/software-repository-paste-host.json)
- [summary](results/2026-10-15/software-repository-paste-host.txt)
- [Software and maintained driver](results/2026-10-15/software-repository-paste-ui.txt)
- [allocation modes](results/2026-10-15/software-repository-paste-memory.txt)
- [sanitizers](results/2026-10-15/software-repository-paste-asan.txt)
- [desktop architecture checks](results/2026-10-15/software-repository-paste-desktop.txt)
- [execution notes](results/2026-10-15/software-repository-paste-attempts.txt)
- [compiler/source/artifact ledger](results/2026-10-15/software-repository-paste-toolchain.json)

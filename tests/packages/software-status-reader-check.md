# Software status diagnostics

Idle full-screen footers, compact catalog screens and catalog browser notices
offer **Read status**. The reader captures the current status separately from
the retained service failure and prepared package/report pages. Local validation
diagnostics need no failed worker output. Invalid UTF-8 and control bytes appear
as visible escapes; CRLF/newlines and tabs use the existing diagnostic rules.
The last 8,192 source bytes are retained, with an explicit omission notice for
larger messages, including a visible escape if the retained tail splits UTF-8.

Compact views from 180×200 render at most three individual native monospace
lines of twelve UTF-8 bytes; full views use fourteen lines of forty-eight bytes.
Previous/Next and Left/Right/Page keys navigate. Resize anchors preserve the
short page and corresponding full page. Smaller windows retain Back. Back or
Escape frees both page caches and returns to the exact form/search/focus,
selection, review, prepared report and retained failure.

Typing, pasting, maintenance, confirmation, cancellation, failure clearing,
report navigation and application requests cannot act through the status modal.
Empty status, pending workers, administrator prompts, application windows,
terminal sessions and existing readers refuse entry. No package, authorization
or service protocol behavior changes.

The V Software fixture covers twelve idle contexts, complete sanitized text,
native line reconstruction and geometry, page bounds/keys, resize/tiny Back,
the 8,192-byte boundary, split Unicode/invalid tail bytes, separate failure and
report storage, frozen reviews and protected workers. Existing failure and view
allocation modes add 1,000 status-reader capture/render/navigation/Back cycles.
This qualifies host UI behavior, not guest graphical release acceptance or
whole-service/spawned-worker allocation freedom. Roadmap 14 remains open.


## Recorded results, 2026-10-16

All twenty-three focused compile/run checks passed on the first attempt: full
Software functional assertions, fifteen affected allocation modes, ASan/UBSan
functional plus failure/view allocation modes, and native font metrics. Both
full desktop architecture typechecks passed. Failure and view modes retain zero
tracked bytes across 1,000 status-reader capture/render/key/resize/ignored-write/
Back cycles, including entry from rejected catalog search. Sanitizer leak
detection was disabled. No assertion or protocol validation was relaxed.

Twelve idle contexts preserve the exact form, query/focus/text selection, frozen
review, prepared report and retained service failure. Complete sanitized text,
native short-line reconstruction and geometry, page bounds/keys, resize/tiny
Back, exact 8,192-byte and split-Unicode/invalid tails, application requests,
mutation refusal and protected workers passed. Generated C was reviewed for
borrowed reader access, owned scratch cleanup, noslices growth and retirement
of independent page/label/container storage.

The maintained staging list already includes every changed production/fixture
file and was not rerun. Frozen compiler, Software/protocol/UI inputs, staged
copies, binaries, generated C, helper sources and logs are pinned. Cache,
fallback and automatic compiler error reporting were disabled. Service
authorization, protocol, frozen apply arguments, successful-exit admission and
approved-write guards are unchanged. No whole-service/spawned-worker allocation
freedom, guest graphical or broader roadmap release acceptance is claimed.

- [focused checks](results/2026-10-16/software-status-reader-host.json)
- [summary](results/2026-10-16/software-status-reader-host.txt)
- [functional assertions](results/2026-10-16/software-status-reader-ui.txt)
- [allocation checks](results/2026-10-16/software-status-reader-memory.txt)
- [sanitizers](results/2026-10-16/software-status-reader-asan.txt)
- [desktop architecture checks](results/2026-10-16/software-status-reader-desktop.txt)
- [execution notes](results/2026-10-16/software-status-reader-attempts.txt)
- [compiler/source/artifact ledger](results/2026-10-16/software-status-reader-toolchain.json)

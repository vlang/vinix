# Literal deployment and offline-export path input

Deployment and offline-export clipboard events formerly passed through keyboard
handlers. Standalone Enter/Escape could blur a form, editing controls could
select/delete its filename, and pasted Escape could cancel a frozen proposal or
stop a pending review. Embedded invalid filename text was already refused.

Dedicated paste handlers now accept literal filename data only. Controls (C0,
DEL and C1), invalid UTF-8 and values exceeding 4096 bytes are rejected as a
whole, preserving the old path, focus and selection. Empty or unfocused pastes
do nothing. During pending reviews, frozen proposals and approved writes,
path-field pastes are ignored. Keyboard editing, focus changes and cancellation
retain their existing guards. The saved-deployment form delegates accepted
clipboard text to the same insertion path, including empty-paste preservation.
Exporting a saved deployment keeps its captured source path/digest fixed while
allowing the user to choose another destination.

The maintained [deployment fixture](software_deployment_navigation_fixture.v)
checks deployment files, mirror destinations and mirror lock paths through the
actual app paste dispatcher. Each field is tested selected/unselected with
standalone/embedded controls, malformed/truncated/overlong/surrogate/out-of-range
UTF-8, C1 controls, 4096-byte values, append/replacement overflow, literal Unicode,
spaces and shell punctuation, empty/unfocused input and keyboard editing. It
checks that source/digest pins remain fixed while the destination can change.
Deployment, [mirror](software_mirror_navigation_fixture.v) and
[save](software_snapshot_fixture.v) fixtures preserve their existing literal
service-argument, frozen confirmation, failure and writer-retirement checks.

Partial and complete-before-exit deployment/catalog-mirror/locked-mirror review
workers receive pasted controls at real input barriers. Fresh completed reviews
and approved apply/publication workers receive the same inputs. Their worker
identity, proposal, selected source and destination remain unchanged until an
actual keyboard command or authorized action handles them. No paste can start
publication, cancel a proposal or stop a reader.

The existing deployment and mirror allocation modes add literal, refused,
selected and empty input to 1,000 review/render/retirement cycles. All twenty-five
allocation modes remain regression checks. ASan/UBSan covers deployment/mirror
navigation, save and saved-export allocation modes plus the full functional
suite. These are headless host and full desktop architecture checks; they do not
claim new guest graphical acceptance or whole-service/spawned-worker allocation
freedom. Ordinary graphical sessions and publisher/catalog/runtime release
qualification remain open.


## Recorded results, 2026-10-15

All 35 focused compile/run checks passed: the complete Software functional
fixture, all twenty-five allocation modes, ASan/UBSan functional plus deployment
navigation, mirror navigation, save and saved-export allocation modes, and the
existing native font metrics check. The maintained Software-only distribution
driver passed independently with all twenty-five allocation modes and the font
check. Deployment and offline-export path input retains zero tracked bytes over
1,000 literal/rejected/selected/empty input and existing review/render/retirement
cycles. Sanitizer leak detection was disabled. These measurements do not
establish whole-service or spawned-worker allocation freedom. Both full desktop
architecture typechecks passed.

No failed executions were observed. The frozen compiler runs with -nocache,
fallback disabled and automatic compiler error reporting disabled. Compiler,
Software/protocol/UI inputs, staged sources, binaries and logs are pinned.
Service arguments, captured paths/digests, review fingerprints, authorization
and protocol are unchanged. No new guest graphical or wider publisher/catalog/
runtime release acceptance is claimed.

- [focused checks](results/2026-10-15/software-distribution-paste-host.json)
- [summary](results/2026-10-15/software-distribution-paste-host.txt)
- [Software and maintained driver](results/2026-10-15/software-distribution-paste-ui.txt)
- [allocation modes](results/2026-10-15/software-distribution-paste-memory.txt)
- [sanitizers](results/2026-10-15/software-distribution-paste-asan.txt)
- [desktop architecture checks](results/2026-10-15/software-distribution-paste-desktop.txt)
- [execution notes](results/2026-10-15/software-distribution-paste-attempts.txt)
- [compiler/source/artifact ledger](results/2026-10-15/software-distribution-paste-toolchain.json)

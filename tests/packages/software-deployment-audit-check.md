# Software installed deployment checks

Software's **Deployment → Check installed** compares an exact deployment lock
with recorded installed metadata through `--json deployment-audit FILE`.
It reads without administrator authorization, keeps the literal filename frozen,
buffers the complete bounded document and waits for process exit. Exit 0 must
agree with `matches:true`; exit 3 must agree with `matches:false`. Other exits,
malformed/partial/oversized output and contradictory results remain failures.
No partial report becomes available for reconciliation.

The report includes every matching, missing, unexpected and changed package.
Package paging selects a row for detail pages containing expected and installed
versions, every differing field, sequence-floor/requested-root explanations,
architecture, generation, full source filename and captured SHA-256. The report
is an observation of metadata, not payload health or current authorization.

Reload retires old rows and details before starting, preserving the captured
filename. Stop discards incomplete output; closing is allowed for this read-only
worker. Compact windows retain Stop or Back. Back retires report state while
preserving the deployment form and catalog search/filter/selection. **Review
deployment** restores the captured path and obtains a fresh `deployment-review`
proposal. It never reuses the audit as a transaction fingerprint or approval.

The maintained [functional fixture](software_audit_fixture.v) exercises literal
Unicode/space/metacharacter paths, ordinary argv with no authorization prompt,
fragmented complete replies, exit 0/3 consistency, all row states, paging, frozen
reload and fresh review handoff, cancellation, small windows and useful failure
details. It refuses error exits containing valid-looking JSON and oversized
replies. The `audit-memory` mode measures 1,000
decode/detail/render/page/retirement cycles after warmup with `-gc none
-manualfree -d track_heap`. The maintained distribution driver stages the actual
new Software source and fixture and includes that allocation mode.

These are host headless UI checks and desktop architecture typechecks. The
[service qualification](deployment-audit-check.md) covers actual CLI behavior and
ordinary-user metadata reads on both guest architectures. This UI change adds no
claim of ordinary graphical login/display-broker acceptance or completion of the
broader publisher, catalog and foreign-runtime release gates.


## Recorded results, 2026-10-15

All 18 focused compile/run checks passed: complete Software functional tests and
all thirteen allocation modes, plus ASan/UBSan functional and audit allocation
checks. The maintained Software-only distribution driver passed independently.
The audit presentation retained zero tracked bytes across 1,000 complete decode,
detail, render, paging and retirement cycles, including clearing the live window
status before sampling. Sanitizer leak detection was disabled; this does not
measure whole-service allocation freedom.

Both full desktop architecture typechecks passed. Compiler, Software/protocol/UI
inputs, staged test sources, binaries and logs are pinned. Initial wrapped-text
and detail-array growth failures are documented separately; the final path
retires old buffers when growing temporary detail arrays. Service and report
protocol behavior are unchanged; their earlier dual-architecture guest receipts
remain linked above. No new guest graphical or broader release acceptance is
claimed.

- [focused checks](results/2026-10-15/software-deployment-audit-host.json)
- [summary](results/2026-10-15/software-deployment-audit-host.txt)
- [Software and maintained driver](results/2026-10-15/software-deployment-audit-ui.txt)
- [allocation modes](results/2026-10-15/software-deployment-audit-memory.txt)
- [sanitizers](results/2026-10-15/software-deployment-audit-asan.txt)
- [desktop architecture checks](results/2026-10-15/software-deployment-audit-desktop.txt)
- [initial attempt](results/2026-10-15/software-deployment-audit-attempts.txt)
- [compiler/source/artifact ledger](results/2026-10-15/software-deployment-audit-toolchain.json)

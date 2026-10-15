# Saving installed deployments in Software

Software's **Deployment → Save installed…** opens an empty new-filename field.
It saves all requested installed applications and their recorded dependency and
runtime closure through `--json deployment-snapshot-save FILE`, using the
ordinary user's permissions. Existing names remain protected by the service's
atomic no-replace publication. The desktop never writes the deployment file or
builds it from catalog rows. This exports metadata, not payloads, personal data
or repository trust. See [service qualification](deployment-save-check.md).

The bounded UTF-8 path editor preserves literal Unicode, spaces and shell
metacharacters. Control characters, invalid UTF-8 and oversized edits cannot
silently change the filename. The worker captures an independently owned path;
later form changes cannot redirect its receipt or follow-up operations.

Software buffers at most 32 KiB and waits for process exit and drained output.
Only exit 0 with a complete strict format-1 saved receipt naming the captured
destination exposes success. Partial, malformed, oversized or misdirected replies
and error exits with valid-looking JSON remain failures. The receipt's full
filename, saved bytes' SHA-256, architecture, captured installed generation,
requested-root count and complete package count have paged detail controls.

Saving is a writer even though its response is JSON. Back, Escape, repeated Save,
cross-panel commands and ordinary window closing cannot kill the pending write.
Compact windows keep the current status and restore Back after completion. A
failure retains diagnostics, including "saved, but" errors after publication;
missing or incomplete receipts explain that a file may exist. Retrying requires
an explicit new Save action, and existing names remain preserved.

**Check installed** obtains a fresh audit of the captured filename. **Review
deployment** obtains a fresh authenticated proposal, never an approval from the
receipt. **Save another…** starts with an empty field and retires the old receipt,
owned path and detail pages. Back and application retirement release that state
while preserving catalog search, filter and selection.

The maintained [functional fixture](software_snapshot_fixture.v) exercises
fragmented output, both architectures, empty installed generations, long literal
paths and paged receipt details, ordinary argv without an administrator prompt,
pending-write navigation and close guards, fresh audit/review handoff, compact
navigation and useful failure details. It covers pre-publication refusal and
post-publication storage diagnostics. The `snapshot-memory` mode measures 1,000
complete decode/detail/render/page/retirement cycles plus destination-mismatch
rejection after warmup, with `-gc none -manualfree -d track_heap`.

These are host headless Software checks and full desktop architecture
typechecks. The service qualification above covers actual publication and
ordinary-user behavior on both guest architectures. This UI change does not
establish ordinary graphical login/display-broker acceptance or close broader
publisher, catalog and foreign-runtime release gates.


## Recorded results, 2026-10-15

All 19 focused compile/run checks passed: the complete Software functional
fixture and fourteen allocation modes, plus ASan/UBSan functional and snapshot
allocation checks. The maintained Software-only distribution driver passed
independently with all fourteen allocation modes. The snapshot presentation
retained zero tracked bytes across 1,000 complete receipt/detail/render/page/
retirement cycles plus destination-mismatch rejection, after retiring the live
status before sampling. Sanitizer leak detection was disabled; this does not
measure whole-service allocation freedom.

Both full desktop architecture typechecks passed. The compiler, Software,
protocol and UI inputs, staged sources, binaries and logs are pinned. An initial
fixture paging assertion is recorded separately. Package service and protocol
behavior are unchanged; the earlier dual-architecture service receipts remain
linked above. No new guest graphical or broader release acceptance is claimed.

- [focused checks](results/2026-10-15/software-deployment-save-host.json)
- [summary](results/2026-10-15/software-deployment-save-host.txt)
- [Software and maintained driver](results/2026-10-15/software-deployment-save-ui.txt)
- [allocation modes](results/2026-10-15/software-deployment-save-memory.txt)
- [sanitizers](results/2026-10-15/software-deployment-save-asan.txt)
- [desktop architecture checks](results/2026-10-15/software-deployment-save-desktop.txt)
- [initial attempt](results/2026-10-15/software-deployment-save-attempts.txt)
- [compiler/source/artifact ledger](results/2026-10-15/software-deployment-save-toolchain.json)

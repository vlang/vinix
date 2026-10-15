# Offline export from saved deployment receipts

Software's nonempty saved deployment receipt offers **Export offline…**. It
transfers independently owned copies of the captured filename and saved bytes'
SHA-256, retires the receipt and its pages, and opens an empty destination field.
Opening this form acquires no payloads and requires neither catalog selection nor
installed catalog rows. Empty receipts and pending or failed saves cannot start
this flow.

Source and scope stay fixed. Review uses the captured filename even when form
storage changes, and requires the service's deployment digest to match the saved
receipt. Changed bytes reject the complete decoded envelope before confirmation,
with a diagnostic directing the user to save a new snapshot. Source/path or
destination mismatches, unreadable files and malformed responses retain the
existing refusal behavior. A failed or canceled review keeps the source pin;
retry cannot silently switch to catalog resolution or a different document.

The user chooses a new destination and reviews complete paged paths and digest,
then the authenticated exact versions, publishers, permissions, licenses,
firmware declarations, runtimes and space requirements. Confirmation preserves
the reviewed literal paths and fingerprint through administrator approval. The
service rechecks bound inputs before the existing atomic locked-mirror export
and bundles `_deployment.json`. Installed state and personal data remain intact.
See [locked export service qualification](locked-mirror-check.md) and
[Software locked export qualification](software-locked-mirror-check.md).

Back, a general Export offline action, navigation to other maintenance panels,
and application retirement release the source and digest. Canceling a review
keeps them for a fresh review. Catalog search, filter and selection stay intact.

The maintained [fixture](software_snapshot_export_fixture.v) exercises the full
asynchronous save/handoff/review/administrator/apply sequence, literal Unicode
and metacharacter filenames, no catalog selection, an empty destination despite
earlier form contents, fixed source/scope, complete disclosure before package
review, runtime/proprietary/firmware/permission facts, pending-write protection,
progress, source changes, unreadable files, wrong-source replies and empty
snapshots. Its `snapshot-export-memory` mode measures 1,000 successful handoff,
decode, path/package render and retirement cycles plus digest-mismatch rejection
after warmup, with `-gc none -manualfree -d track_heap`.

This change uses the existing package service and protocol. Host headless UI
checks and full desktop architecture typechecks do not establish ordinary
graphical login/display-broker acceptance or complete the wider catalog/runtime
release gates. The service qualifications linked above cover publication on
both guest architectures.


## Recorded results, 2026-10-15

All 20 focused compile/run checks passed on the first attempt: the complete
Software functional fixture and fifteen allocation modes, plus ASan/UBSan
functional and saved-export allocation checks. The maintained Software-only
distribution driver passed independently with all fifteen allocation modes.
The saved-export presentation retained zero tracked bytes across 1,000 handoff,
decode, path/package render and retirement cycles plus digest-mismatch
rejection, after retiring the live status before sampling. Sanitizer leak
detection was disabled; this does not measure whole-service allocation freedom.

Both full desktop architecture typechecks passed. Compiler, Software, protocol
and UI inputs, staged sources, binaries and logs are pinned. Package service and
protocol behavior are unchanged; earlier dual-architecture locked-export service
receipts remain linked above. No new guest graphical or broader release
acceptance is claimed.

- [focused checks](results/2026-10-15/software-snapshot-export-host.json)
- [summary](results/2026-10-15/software-snapshot-export-host.txt)
- [Software and maintained driver](results/2026-10-15/software-snapshot-export-ui.txt)
- [allocation modes](results/2026-10-15/software-snapshot-export-memory.txt)
- [sanitizers](results/2026-10-15/software-snapshot-export-asan.txt)
- [desktop architecture checks](results/2026-10-15/software-snapshot-export-desktop.txt)
- [compiler/source/artifact ledger](results/2026-10-15/software-snapshot-export-toolchain.json)

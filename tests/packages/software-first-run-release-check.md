# Native release applications at first login

When `/usr/share/vinix-packages/applications.json` is an ordinary file, a new
ordinary account is offered **Review release applications** and **Skip for now**
before its first desktop session becomes ready. This does not depend on legacy
registration or `/usr/bin/pkg`. Images without the declaration retain the legacy
optional-app picker.

The prompt explains that the proposal covers the complete declared application
set and may remove other installed packages. Review opens Software and waits for
its initial catalog request to finish before requesting the existing read-only
deployment review. It preserves the literal declaration path, full dependency and
removal proposal, explicit Confirm, and separate administrator approval. It adds
no publisher trust or automatic package operation. Starting a search while the
catalog loads retires the queued handoff instead of replacing the user's input.

A successful choice writes the private per-home `.vinix-first-run-release` record
as exactly `review\n` or `skip\n`, then consumes any legacy pending marker. Both
choices are durable and do not repeat at the next login. Failure to save leaves
the choice open. Reads refuse symlinks, nonregular and oversized records; writes
publish an exclusive random sibling by rename, so crash-leftover temporary files
cannot prevent retry. The record captures one-shot intent before window delivery:
if a crash, failed launch, or cancellation loses Review, Software's ordinary
release-application review remains available to request it again.

The host checkpoint is recorded in
[the result](results/2026-10-22/software-first-run-release-host.txt) and
[the source/artifact ledger](results/2026-10-22/software-first-run-release-host.json).
It covers ordinary-account reachability, durable Skip and Review, bounded invalid
record recovery, failed-save retry and crash leftovers, all seven translated keys,
bundled glyphs, and complete warning/button layout at 320×240, 320×768, 640×480 and
1024×768 in all six languages. The real-child Software fixture checks literal
arguments, duplicate handoff suppression, catalog failure recovery, cancellation,
absence of automatic apply, and the separate Confirm/administrator boundary.

Both target compositors cross-compile from the admitted production sources.
Native framebuffer acceptance of this first-run prompt and its reboot behavior
is a separate pending gate; the earlier installed-Software acceptance does not
qualify this new prompt. The host report also records the broader broker and
translation-suite failures rather than claiming a full-suite pass.

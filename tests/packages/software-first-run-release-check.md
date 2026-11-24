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

If the package service reports that the catalog is unavailable, Software offers
**Refresh offline** and **Refresh with policy** before starting deployment
review. The offline choice reads signed local or bundled indexes. The policy
choice uses the configured repository settings. Refresh requires its own
administrator approval. Cancellation or refusal keeps the refresh choices
available. Successful refresh reloads the authenticated catalog and resumes
the read-only release review. The install still requires **Confirm** and
separate administrator approval.

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

The [native installed-session qualification](software-first-run-native-check.md)
now covers both architectures: the real ordinary-account Review card, complete
read-only Counter proposal, separate Confirm and administrator password, signed
installation, retained private Review decision and no repeated prompt across two
cold boots. Both guests reopen exact saved Counter labels and complete real QMP
guest shutdown. This native result covers Review; durable Skip remains covered
by the host checkpoint. The host report also records the broader broker and
translation-suite failures rather than claiming a full-suite pass.

## First-run catalog refresh qualification

At `c40e40c6f3f947cb3d850597a33c549292033ab2`, the host Software fixture
passed in regular and ASan/UBSan builds with leak detection disabled. It
covered both refresh choices, wide and compact controls, back navigation,
cancelled and refused approval, and the exact read-only commands after a
successful refresh. Both desktop targets typechecked.

The `native-catalog-check --software-bundled-https` initramfs scenario
passed in 91.359 seconds on aarch64 and 93.615 seconds on x86-64. The
headless Software controller and real authentication service rejected a
wrong password, then used the signed bundled catalog to resume first-run
review with no active package generation. A separate confirmation and
administrator approval activated the three-app deployment. Both runs kept the
configured HTTPS publisher, exercised offline maintenance, and ended with a
guest-initiated QMP shutdown. The current refresh screen was exercised through
the Software element tree. Graphical login and public publisher acceptance
remain open for this workflow.

The qualification archive is
`~/.local/state/vinix/r14-first-run-refresh-quTAdY/qualification.tar.gz`.
Its SHA-256 is `c09b17323bf89a02ca4bbb06bd4c26d0928e505e8552b412b4a9a35c29cae110`.
Independent extraction matched all 914 manifest entries and all 61 receipt
artifacts per architecture.

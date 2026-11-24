# Native release applications at first login

When the protected `/usr/share/vinix-packages/applications.json` declares a
nonempty application set for the running architecture, a new ordinary account
is offered **Review release applications** and **Skip for now** before its
first desktop session becomes ready. This does not depend on legacy
registration or `/usr/bin/pkg`. A missing or empty declaration keeps the
legacy optional-app picker available. An invalid declaration leaves setup
pending and produces a diagnostic in the desktop log.

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

**Review release apps** in Software's deployment form offers the same recovery,
including after **Skip for now**. Back returns to the form with its draft path.
An unreadable catalog response keeps the refresh controls available for retry.

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

## Manual release review catalog refresh

At `935091637e2fa1e74b3400dff5dea962a3351633`, the host regression
reproduced the missing refresh screen on the previous revision and passed
on the fixed code in the regular and ASan/UBSan builds with leak detection
disabled. Both desktop targets typechecked. The fixture covers Back with
an unchanged draft, a late file chooser response, cancelled and refused
approval, a malformed catalog reload, and read-only review under both
refresh choices.

Run the single-boot Software image check with
`native-catalog-check --software-manual-release-refresh`. The aarch64
and x86-64 runs passed in 140.3 and 109.5 seconds. Both entered through
the compact deployment form, approved an offline refresh of the signed
HTTPS bundle, and reopened the exact release proposal before any package
generation became active. A separate confirmation and administrator
approval installed the three apps. Both guests retained their staged
trust configuration and performed a guest-initiated QMP shutdown.
The x86-64 run used the retained GCC wrapper for both guest compilation
(`CC_AMD64`) and package staging (`CC_X86_64`) after a generated C
`waitpid` type mismatch in the first staging attempt. These runs use the
headless Software controller. Production graphical login for this
workflow remains open.

The archive is
`~/.local/state/vinix/r14-manual-release-refresh-dBKsQA/qualification.tar.gz`.
Its SHA-256 is `bee9e40252c82ec536070f794a2afead5bb77f97911bce5d979d8ba04a73708d`.
Independent extraction matched all 919 inventory entries.

## Release declaration admission at first login

At `d476d581b`, the baseline host fixture reproduced a first-login prompt
for a malformed declaration. At `d332ebc602e14544dcadeb268275e44e50d8f7d2`,
the setup picker uses the protected release declaration reader. Host suites
cover absent and empty declarations, malformed input, wrong architectures,
missing locks, writable ancestors and aliases. Refusal preserves setup
markers, and restoring the declaration makes review available at the next
login. Both supported formats can open first-login review. The broker route
continues to require the locked format.

The focused host suites passed in normal, production and ASan/UBSan builds.
Process leak detection was disabled for the sanitizer run. The broader
`app_selection` host suite aborted in stylesheet cleanup during that
qualification. The fixture correction is recorded below. Both production
compositors linked statically.

The installed AArch64 and x86_64 guests booted twice with format-1 declarations
and the new compositors. An ordinary account reviewed the signed Counter
proposal after offline catalog refresh, approved installation separately and
reopened its saved data on the second boot. Both retained the Review choice
and shut down through guest poweroff on each boot. The first AArch64 attempt
was stopped after kernel diagnostics split an installation marker in the
serial stream. The unchanged retry passed. The graphical retainer verified
61 AArch64 and 68 x86_64 artifact digests.

The [qualification archive](/Users/alex/.local/state/vinix/r14-first-login-declaration-JE5nGe/qualification.tar.gz)
contains the source snapshot, host and target build evidence, and retained
guest screenshots and transcripts. The independent archive checker verified
all 5,777 sealed entries. The complete guest runs remain at the paths
recorded with their pinned receipts. Archive SHA-256 is
`26cbb5a32b66273781d11e9544c0dbc6c30f36eb0a7a2075d51c7723ce206c05`.

## Setup fixture frame cleanup

ASan reproduced a use-after-free in the optional-app picker and Russian
registration tests from `11cfda7a4`. Both tests reset the frame pool before
releasing the first tree. Its cleanup then traversed reused storage and
read stylesheet maps the newer frame had already released.
At `e7b9ce3e33ac4e1279285677ee96ce29ab8a9a51`, both tests release each
tree before reusing the pool, matching the live setup loops.

All eight suites in the default setup runner passed. The picker, release
choice, release routing, localized application and registration suites
also passed under ASan and UBSan with process leak detection disabled.

The [qualification archive](/Users/alex/.local/state/vinix/r14-picker-stylesheet-eIHeyc/qualification.tar.gz)
contains the baseline traces, fixed logs and source revisions. The
independent checker verified all 33 sealed entries. Archive SHA-256 is
`619ede0cc3e8f804fe9e22b5c93b5bae5cb6ae93e60f6dae42d8ff6bffcc3fe7`.

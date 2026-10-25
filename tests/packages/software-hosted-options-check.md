# Software hosted Launch options

Launch options now sends installed X11 display applications through the same
private authenticated hosted session as ordinary Run. The form freezes the
installed display grant when opened. Candidate permissions cannot choose that
route. The exact validated `run-args` vector keeps literal arguments, allowed
file paths and the working-folder choice. Terminal and non-display workers keep
their existing routes. Native-window protocols do not expose Launch options;
injected option-entry actions now follow that existing UI restriction.

The host's `--package` gate admits only canonical `/usr/bin/vinix-package run`
and `run-args` launches. Its allocation-free argv scan checks package identity,
option grammar and the account protocol's document, argument and byte limits
before creating a display. Signed-session authority and generation-lease
handling remain in use. The ordinary Run helper now releases its cloned strings
as well as its vector storage under `-manualfree`.

Host qualification uses the maintained V driver and nested fixtures:

```sh
V=/Users/alex/code/vinix/build/package-https-runtime-work/toolchain/v
$V -prod -o /external/hosted-options-check tests/packages/software-hosted-options-check.v
/external/hosted-options-check "$V" /Users/alex/code/vinix/build/vmodules /external/fresh-result
```

The explicit checks execute in normal, production, tracked normal, tracked
production and ASan/UBSan builds with `-gc none -manualfree`. They cover frozen
installed permissions, candidate-only display refusal, injected native-window
entry refusal, six admission gates, invalid and unsubmitted drafts, literal
empty/Unicode/metacharacter arguments, both cwd choices, document forwarding,
Terminal capture and a real non-display child barrier with completion/reaping.
The native parser is cross-checked against `pkglaunch.validate_arguments`, with
exact 128-byte ID, 4096-byte value, 256-document/argument, 773-exec-argument and
65536-byte input boundaries and one-over refusals. Tracked checks include a
positive allocation control, 1000 ordinary/custom helper boundary cycles and
10000 raw argv validations, requiring zero retained V bytes and records.
The historical full Software fixture runs separately in normal mode only.

The frozen-input run uses base revision
`185daa693a4785bd92ac27a1b1ec3d155c92e741` plus the feature and fixture
sources recorded in `sources.json`; the base revision alone does not identify
the tested change. The source inventory SHA-256 is
`2910bb8f39300e8f3e0f4a51563602af35c54452a58bfb328905510947ed220a`.
All five variants and the supplementary normal suite passed on 2026-10-26.
The complete external bundle is
`/Users/alex/Library/Caches/vinix-codex/section14/software-hosted-options-20261026-04`.
Its `result.json` SHA-256 is
`f14ed3bef1a0ead62d80373398d37dba107f1b1de7eb825d0df9edd610280bbb`;
the `artifacts.json` SHA-256 is
`a45c58cf2597c5817a9ae0bcc7fa3949cb00e83aac22c701c068aad9bb0a865b`.

The supplementary run exposed an older fixture mismatch:
`software_repository_navigation_fixture.v` used a 4096-byte literal `file://`
URL although the repository validator limits its file suffix to 1024 bytes.
Its boundary-reader prefix now uses valid Unicode HTTPS while retaining the
4096-byte source length, all eight review variants and the maximum counters.
The validator is unchanged. Failed run `software-hosted-options-20261026-03`
is preserved alongside the final bundle; its five focused modes passed before
the historical assertion stopped the driver. Its `normal.historical.log`
SHA-256 is `66117e936be32f7ae86a08acf6f62f7d058c68a5b0a4f3bfdfa8ed9245d01a07`.

This is headless host qualification. A separate capture adapter replaces the
shared fail-closed hosted stub only in the focused stage. The staged helper
calls a controlled effective-UID function to exercise root/ordinary-account
gates; pristine production source and adapted source hashes are preserved
separately. Staged UI native-control guards receive the existing headless
compatibility exclusion. Clang 23 uses the existing socket pointer-warning
compatibility flag. The raw parser is compiled unchanged in an isolated module, while
the real host entry point is reviewed but not executed by these checks. The
capture owns argument copies to inspect them after caller release; it does not
qualify the actual fork, X11 authority, rendering, account sandbox or generation
lease. ASan leak detection is disabled; retained-memory claims apply only to the
specified V-tracked loops. Project/UI inputs and V/Clang executable bytes are
pinned, while imported vlib, thirdparty objects, headers, linker and transitive
tools are not frozen. This is not hermetic or full section 14 acceptance.

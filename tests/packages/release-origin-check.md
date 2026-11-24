# Bundled catalog transition to HTTPS

The [release origin fixture](release-origin-check.v) uses the production image
staging APIs and invokes `vinix-package` against a fresh alternate root for each
target architecture. It stages the [mixed signed catalog](signed-legacy-routing-check.md#mixed-signed-release-approval),
including the reviewed image configuration, bundle and exact application lock.
The host fixture points the initial file URL at that staged copy. Offline
refresh and reviewed deployment install seven application roots and their three
runtime packages.

The fixture serves two signed indexes for the same publisher through a
loopback TLS server. The first review sees sequence 1. The fixture places
sequence 2 at the same URL before applying the review. The stale approval must
leave configuration, history and cached metadata byte-identical. A fresh
review and apply change the URL while preserving the publisher key, policy,
catalog cache and installed generation. A separate refresh and reviewed upgrade
must fetch exactly the missing SQLite runtime objects over HTTPS and leave the
other nine manifests unchanged.

The deployment audit shows drift only for that runtime. Reviewed rollback then
restores the exact ten original packages and a matching audit. The original
image declaration stays byte-identical, the trust floor stays at sequence 2,
and a new HTTPS URL offering the old signed index still fails review.

## Reproduce

Provide the baseline and update bundles described in the
[installed mixed catalog check](signed-legacy-routing-check.md#mixed-catalog-maintenance-on-an-installed-disk).
Use current signed indexes and one reviewed configuration per target. Each
configuration enrolls the one fixture publisher at the image's fixed file URL
and permits online maintenance. The fixture explicitly selects `--offline`
for initial acquisition. Run from the repository root with V, curl and OpenSSL.

```sh
v -path '@vlib|@vmodules|.|tools/accounts' -enable-globals -prod \
  -o /tmp/vinix-package tools/packages/main.v
v -o /tmp/https-fixture tests/packages/https-fixture.v
v -path '@vlib|@vmodules|.|tools/accounts' -enable-globals -prod \
  -o /tmp/release-origin-check tests/packages/release-origin-check.v
/tmp/release-origin-check /tmp/vinix-package /tmp/https-fixture \
  BASELINE_BUNDLE UPDATE_BUNDLE CONFIG_ARM CONFIG_X86 NEW_WORK
```

The runner records argv, command results, complete staged and maintained
roots, and HTTPS requests. It stops and reaps the fixture server on exit.
The recorded qualification uses real signed target payloads with host CLI
execution and a disposable publisher. Native installed-system HTTPS and
production publisher enrollment remain release gates.

## Qualification

At `c1a814ad0`, the production and ASan/UBSan builds passed for both target
declarations. The sanitizer run instrumented the fixture runner and package CLI
with leak detection disabled. Both builds fetched one new SQLite runtime object
per target. Their HTTPS request logs, installed-state receipts and deployment
audits matched exactly. The existing repository administration test file also
passed.

The source configuration copies explicitly enable online maintenance. The
original offline-only configuration and its refusal are retained alongside the
passing runs. An existing work directory was also refused without changing the
captured configuration or HTTPS request log.

The complete signed inputs, source snapshot, tool identities, command logs and
staged roots are archived in
`~/.local/state/vinix/r14-release-origin-M8czca/qualification.tar.gz`.
The archive SHA-256 is `a7492c9f44f459abda345ebc080c4c5ed4c12704ede6fe08bded1b9315fa2eff`.
The `bundle.sha256` manifest has 65,225 file and symlink entries and SHA-256
`fd6a219803875951f30f565ae1ab3844340bbdaab3f5a97f3ece09b4cdba1491`.
All entries matched after extraction into an independent directory.

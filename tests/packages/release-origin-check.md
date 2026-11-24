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
execution and a disposable publisher. The clean-disk follow-up below runs
the maintenance workflow inside Vinix guests.

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

## Clean installed guests

The [installed runner](release-origin-runtime-check.v) builds the target
package CLI and [guest init](release-origin-guest/main.v), stages the same
signed baseline, and starts QEMU with a fresh 4 GiB disk. Use a target network
tools root containing `/usr/bin/curl`, its musl loader and OpenSSL dependencies.
The runner copies that executable and its shared-library closure and gives curl
a CA for the local fixture endpoint only.

```sh
v -prod -enable-globals -path '@vlib|@vmodules|.|tools/accounts|tests/hardware-platform' \
  -o /tmp/release-origin-runtime-check tests/packages/release-origin-runtime-check.v
/tmp/release-origin-runtime-check ARCH KERNEL CURL_ROOT BASELINE_BUNDLE \
  UPDATE_BUNDLE CONFIG NEW_WORK
```

Run once with each target's reviewed configuration, kernel and curl root.
Use the hardware harness's target compilers and firmware settings. The x86-64
run uses the plain UEFI fixture builder and its `VINIX_PLAIN_ISO_LIMINE` input.

On the first boot the real installer formats the fresh disk. The fixture checks
the mounted disk root and image ID, then installs the seven locked applications
from the bundled repository. On the second boot it checks retained bytes,
reviews and approves the same-key HTTPS origin, refreshes separately, upgrades
only the SQLite runtime and rolls back to the original lock. Both the second
and third boots refuse the older signed index. The third boot also checks the
retained configuration, cache, trust history and verified package generation.

All three boots use test media to load the kernel and require guest-originated
QMP shutdowns. The loopback server log must contain the exact metadata requests
and only the newly needed runtime objects. Production publisher enrollment and
public HTTPS repository acceptance remain separate release gates.

### Installed-guest results

At `cac3548fe`, both fresh VJFS guests passed with 2 GiB of RAM and three
guest-originated shutdowns. AArch64 completed in 171.977 seconds under HVF.
x86-64 completed in 483.689 seconds under TCG. Both used curl 8.14.1 and
OpenSSL 3.3.7, fetched one authenticated runtime object, and made exactly
eleven HTTPS requests. The offline control made no HTTPS request. The audit
isolated the SQLite runtime change, then reported a full match after rollback
and again after the final cold boot.

The accepted builds use the retained kernels and a V-built ARM musl GCC
adapter. Earlier link failures and refusals for a missing or mismatched
installer image ID are retained with the run receipts.

The source snapshot, signed inputs, boot media, logs and both installed disks
are archived in
`~/.local/state/vinix/r14-installed-release-origin-ByhN6F/qualification.tar.gz`.
The archive SHA-256 is `53c309120c874d626a9c257bd192ce6ff79721087c2c849b3d65e0872011c290`.
The `bundle.sha256` manifest has 8,805 file and symlink entries and SHA-256
`50d182a0b23412ef0c5e7847303b160e9ef2c6b49040723beb58cc4ecb463a31`.
All entries matched after independent extraction. Each `system.vjfs.zst`
decoded to the corresponding `disk.raw.sha256`.

## Bundled HTTPS publisher

Pass `--bundled-https` after `NEW_WORK` to the installed runner. It stages the
same signed baseline with the disposable publisher's HTTPS URL in the reviewed
configuration. The first boot uses offline refresh and deployment from that
bundled copy. The second boot refreshes the configured URL, checks that an
offline refresh refuses the older bundled sequence, then upgrades and rolls
back. The final boot verifies the retained package generation and trust history.

The recipe requires identical publisher configuration across all three boots.
The host request log must show one index/signature pair from online refresh,
the new runtime object requests, and two index/signature pairs from the older
HTTPS origin used for replay controls. The offline operations use the same
signature and sequence checks over the staged files.

# Hosted signed repository readback

The [readback runner](release-origin-readback-check.v) exercises
`vinix-package check-release-origin` against the real loopback TLS fixture.
It signs two exports with a disposable key. Both fixtures contain two packages
that share two unique objects, including an empty one. A successful run checks
the exact request sequence and the original publisher receipt.

The controls refuse a different signed index, mismatched signature, an index
switch during transfer, and corrupt or missing payloads. Changed local content
and inadmissible identity, transport and root options refuse before making any
HTTPS request. The certificate control uses the wrong hostname. The runner
checks the reviewed local export's bytes after the refusal cases.

The optional mixed-catalog run reads back every distinct object in the
[previously qualified export](signed-legacy-routing-check.md#mixed-signed-release-approval).
It compares the receipt to the reviewed index and checks the exact object
requests, including the metadata pairs before and after the download sequence.

```sh
v -prod -gc none -manualfree -enable-globals -path '@vlib|@vmodules|.|tools/accounts' \
  -o /tmp/vinix-package tools/packages/main.v
v -o /tmp/https-fixture tests/packages/https-fixture.v
v -prod -enable-globals -path '@vlib|@vmodules|.|tools/accounts' \
  -o /tmp/release-origin-readback-check tests/packages/release-origin-readback-check.v
/tmp/release-origin-readback-check /tmp/vinix-package /tmp/https-fixture \
  NEW_WORK [MIXED_RELEASE PUBLIC_KEY_HEX]
```

## Qualification

At `e4d3b2840`, the production and ASan/UBSan builds passed the small positive
case and eleven refusal controls. ASan/UBSan instrumented the package CLI with
leak detection disabled. The production build also matched all 2,158 distinct
objects across 20 signed package variants in the mixed catalog. Its log shows
2,162 requests for the mixed export, including both pairs of metadata reads.
The existing release, image repository and HTTPS transport checks passed, and
the production stager built static tools for AArch64 and x86-64.

The qualification used real signed exports and a loopback TLS origin with a
disposable publisher. Public hosting and production publisher enrollment
remain release gates.

The signed inputs, source, executables, command and request logs, and target
builds are archived in
`~/.local/state/vinix/r14-origin-readback-JnPfFi/qualification.tar.gz`.
Its SHA-256 is `75196b4cffe966b7cd29fa6b4bb38cd647943f17ff2354f702802a3c9e751d11`.
All 4,507 entries in `bundle.sha256` matched after independent extraction.

## Local export verification

At `1787f067b81754688165a23b5ad7a69e18e77b84`, the same signed fixture
exercises `check-release-export` before starting the TLS server. The command
matched the publication receipt and succeeded with an empty tool search path.
Ten controls covered publisher ID and key, argument count, an alternate
installation root, a publisher workspace, a symlinked release directory,
object mode, same-length payload corruption, a missing object and an extra
file. Restoring the export returned the identical receipt. The export bytes
and publisher sequence history matched their originals.

The normal, production and ASan/UBSan host runs passed the small export and
hosted readback cases. Process leak detection was disabled for the sanitizer
run. The production run also matched the local and hosted receipts for all
2,158 objects across 20 mixed-catalog variants. Release and image repository
unit suites passed. Both target CLIs linked statically. The target build logs
retain GCC diagnostics from the generated V runtime code, including the
`waitpid` status pointer warning. Execution checks ran on the host.

The [qualification archive](/Users/alex/.local/state/vinix/r14-release-export-check-WkJkTU/qualification.tar.gz)
contains the signed fixture exports, source revision, host and target builds,
and command and request logs. The independent checker verified all 4,631
sealed files. Archive SHA-256 is
`17c893716b72158e20f988b5bd50ea84ccdb5e6d04b22e45e71496b574b86a16`.

## Image index pins from signed release exports

At `bc66e8fa078f27abf6b9f12e2e6415bc69252923`, the runner signs exports under
two independent keys. The pin command produces the same sorted file in both
argument orders and produces the matching single row with `--offline` and an
empty tool search path. Nine controls cover duplicate IDs, a wrong key, a
damaged export, invalid operands and options, existing destinations and an
aliased destination inside an export. A late failure leaves the destination
absent. Restoring the damaged object returns the exact original pins and
preserves the publisher history.

Normal, production and ASan/UBSan host runs passed, with process leak detection
disabled for the sanitizer run. The production command also generated pins for
the mixed catalog after verifying its 20 variants and 2,158 distinct objects.
Release, image repositories and both atomic-write unit suites passed. Both
target CLIs linked statically. The host exercised a generated pin file through
image staging and ISO preflight for each target and reproduced the previous
reviewed ISO plan. CLI execution checks ran on the host.

The [qualification archive](/Users/alex/.local/state/vinix/r14-publish-index-pins-wHPfiB/qualification.tar.gz)
contains the source, signed inputs, target builds, host checks and both preflight
receipts. The independent checker verified all 2,553 sealed files. Archive
SHA-256 is
`1c718c196a159755ce3cddfc85efaabb611cf2303e00d216005ca24a08e9dfe2`.

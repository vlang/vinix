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

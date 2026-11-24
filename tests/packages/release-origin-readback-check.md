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

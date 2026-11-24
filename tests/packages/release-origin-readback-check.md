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

### Captured pin destination

At `49efa08a1a76e2ed020d2962c3ce3ef3fe12a5e0`, the pin writer keeps its
output directory descriptor open during signed release verification. The
containment walk and atomic publication use that descriptor. The write
refuses a change in the destination path's directory identity before
creating a temporary file.

The host replacement test compares both directories after refusal and
then restores the original for an exact successful retry with the same
descriptor. The containment test moves the captured directory inside
the source while placing a replacement at the old name. That test passed
in the AArch64 and x86-64 publisher workspace guests, both with guest
shutdowns. The containment and filesystem helper matrix retained zero
tracked allocations across all 17 modes.

Production and ASan/UBSan host CLI checks passed with process leak detection
disabled for the sanitizer run. The mixed 2,158-object export readback also
passed. Both target CLIs linked statically. Generated pins reproduced the
reviewed image-staging and ISO preflight results for both architectures.

The [qualification archive](/Users/alex/.local/state/vinix/r14-pin-parent-capture-UXZPqA/qualification.tar.gz)
contains the source, test logs, signed inputs, target builds and both guest
receipts. The independent checker verified all 2,512 sealed files. Archive
SHA-256 is
`b1c4729b4f3024adcca0053014a7eb93dd141349ab239eb71f46e4b46efd7f2e`.

### Image index pins after hosted release verification

At `7f1add84a052e25dbe412f88f09c0ef7de099003`,
`write-hosted-release-index-pins` verifies a complete HTTPS readback for
every selected signed export before publishing the image pin file. The
two-publisher batch and the reversed-order retry produced the exact offline
pin bytes. Twelve refusal cases included a different index from the second
origin after the first had passed, a certificate hostname mismatch, a
destination inside an export, invalid operands and incompatible options.
The fixture checks exact HTTP request order, preserved existing pin files,
absent new outputs on refusal, and unchanged signed exports and publisher
history.

The normal, production and ASan/UBSan host builds passed with real loopback
TLS. The sanitizer run disabled leak detection and symbolization. The
production CLI also verified all 2,158 objects across 20 variants of the
mixed catalog and wrote its exact pin. Image preflight accepted that pin on
both architectures, resolving seven application roots and ten locked packages.
A wrong pin refused on each architecture before modifying its image root.
Normal staging with the two-publisher pins built all three static target
tools on both architectures and copied both signed exports byte for byte.
CLI execution and TLS checks ran on the host against disposable origins.

The [qualification archive](/Users/alex/.local/state/vinix/r14-hosted-index-pins-ggQ1fO/qualification.tar.gz)
contains the source, signed exports, request logs, preflights and static
target builds. The independent checker verified all 2,691 sealed files.
Archive SHA-256 is
`3461c05aaf9734c89f9e04e9121350d416c35837ae003caf7b72fd23134fd700`.

### Exact HTTPS origins in hosted pins

At `6984818255d414b68f8d9d8cc548555a6e64f833`, hosted pins retain the verified
HTTPS URL as a third field. Image staging and ISO planning compare it with
the effective configuration before compiling or modifying the image. The
stager accepts existing two-field rows and can read hosted and digest-only rows
in the same file. The writer refuses batches that would exceed the staging
reader's 8 MiB limit before contacting any origin.

Production and ASan/UBSan host CLIs passed the two-publisher TLS tests with
exact URL and digest output, reversed-input retry and all twelve refusals.
Production readback covered all 2,158 mixed-catalog objects. On both
architectures, the resulting pin admitted seven roots and ten locked packages.
Changing the configured path with the bundle held fixed refused preflight.
Normal staging and ISO planning with the two-publisher fixture also rejected
a changed URL. Production staging with the reviewed URLs built all three
static tools and preserved both signed exports byte for byte.

The AArch64 and x86-64 QEMU TCG image-input suites passed in 200.804 and
154.089 seconds respectively. Both ran all five programs, including mixed pin
formats, exact trailing-slash matching, retained configuration refusal,
restored retry and the writer's size bound. Each initiated shutdown, and all
nine artifact sizes and digests matched per guest. HTTPS checks used loopback
TLS on the host. Leak detection and symbolization were disabled for the
sanitizer runs.

The [qualification archive](/Users/alex/.local/state/vinix/r14-hosted-origin-binding-XKI3wh/qualification.tar.gz)
contains the source snapshot, signed exports, host checks, staging and ISO
plans, and guest receipts. The independent checker verified all 2,679 sealed
files. Archive SHA-256 is
`6202d8e4f89a47d68a801273e9005c2910cf5a9d0231702bbecec5a9a5c0bbc7`.

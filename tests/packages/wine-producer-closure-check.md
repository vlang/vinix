# Parsed source admission for Wine bridge production

`wine-build` now discovers the bridge compiler's source list before the actual
V build. It captures every listed file's hash in `inputs-before-build.json`,
then requires the real build to parse the same ordered list with unchanged
bytes. A missing, changed or newly parsed source refuses before bridge C
compilation and final producer receipts.

The producer retains `logs/sources-before.txt`, `logs/sources-built.txt`,
`logs/discover.log` and its argv alongside the actual V build logs. These
artifacts participate in `outputs.json`. The host producer also embeds and pins
its source-admission helper. The ordinary Win64 retainer requires these
producer artifacts, checks their source admission and exact discovery/build
arguments, and preserves recorded build paths when checking a copied bundle.

The source-list parser rejects CR and NUL before line splitting; CRLF
normalization cannot silently alter a manifest spelling. Unit controls cover
an import outside a manual seed list, changed/omitted/uncaptured files,
duplicates, relative/missing paths, linked manifests and CR input. Production
`wine-source-check.v` passes its baseline and six refusal controls, including
CR input. The earlier failed CR control remains preserved.

Build `wine-producer-closure-check.v` with the repository on V's module path,
using `-prod -gc none -manualfree`, then run:

```text
CHECK /absolute/fresh-prepared-build
```

It independently compares producer input inventories, rehashes every recorded
input, admits the actual source lists, checks retained output hashes, and
requires matching discovery/build commands. It also admits the explicit
[Clang resource-header selection and complete header tree](wine-resource-headers-check.md).
It additionally requires [observed C file admission](wine-c-inputs-check.md).
The [linker archive/replay check](wine-link-inputs-check.md) also requires
captured static link inputs and an identical replay with the pinned linker.
The [host image/environment check](wine-host-images-check.md) adds managed
Clang/LLD image bytes and exact closed child environments, with an explicit
unadmitted OS shared-cache boundary.
The [V source-generation check](wine-v-host-check.md) also requires exact child
environments and observed image admission for discovery and actual C generation.
The [required host receipt](wine-host-required-check.md) binds the exact producer
executable and requires every admitted host artifact in its input map.
This is parsed bridge-source, selected resource-header and observed C admission; complete
C dependency/toolchain closure and hermetic build admission remain separate
requirements. Historical bundles still need
their original complete inputs and original auditors; no missing evidence is
waived.

The external checkpoint is `/Users/alex/.cache/vwwineclosure-20261115-01`.
`pe-01` freshly builds the Win64 probe from this source root. `prepared-01`
freshly builds the owned x86 runtime with 342 parsed inputs, including
`SDKSettings.json` outside the previous manual directory list. Source-list
admission and the producer closure checker pass. `native-02` passes the actual
signed holder-SIGKILL/collection fixture in 129.031 seconds using this new
runtime and PE. Its preceding `native-01` setup refusal records a missing
isolated bootloader path; the selected shared bootloader was linked before
the fresh successful attempt.

The retainer builds successfully. Its owned/holder modes still require their
own full retention admission; this checkpoint does not claim an owned runtime
retainer pass. Distribution inputs come from the retained selected-file
reconstruction at `vwfull-20261113-01/distribution-02/stage`; local-only notices
come from `vwcollect-20261113-01/prepared-03/publisher-notices`. Those original
bundles and the selected kernel remain independently required. Redistribution,
default activation, owned ARM/GUI and broader roadmap 14 acceptance stay open.

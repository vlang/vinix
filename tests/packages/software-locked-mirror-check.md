# Software deployment-lock export qualification

Software's **Export offline** scope now cycles between the selected catalog
application, installed application roots and **Organization deployment lock**.
The lock scope accepts an absolute source filename independently of this
machine's catalog selection or installed roots. It invokes the existing reviewed
deployment mirror service to export exact authenticated application/runtime
versions, including older approved versions, and bundle `_deployment.json`.

Destination and source fields preserve literal text, reject control characters,
invalid UTF-8 and paths exceeding 4096 bytes, and freeze during review/export.
The review rejects responses for another source/destination, missing or invalid
digests and catalog-only envelopes. All parts of the canonical destination,
complete source filename and SHA-256 must be visited before package review opens.
Publisher keys, permissions, proprietary/firmware disclosures and disk budgets
use the existing complete dependency review. Confirmation passes the frozen
paths and fingerprint directly to `mirror-deployment-apply` with progress enabled.
The service checks the exact document again before acquisition or publication.

Asynchronous Software fixtures exercise an empty local application set, older
runtime versions, long source paths, literal spaces/semicolons/dollar signs,
wrong intent, invalid/missing hashes, wrong envelope type, unreadable/root-only
locks, stale confirmation, cancellation, progress and the export close guard.
Changing form buffers after review cannot change confirmation arguments. The
service's atomic publication and offline reproduction remain covered by
[locked mirror qualification](locked-mirror-check.md).

The real desktop fixture checks both catalog and locked exports with the manual
allocator tracker: 100 form redraws, 100 details redraws/page transitions and 100
package-closure redraws retain zero bytes. Each 100-cycle review/cleanup run
retains 100 bytes, equal to 100 plain JSON boolean decodes on the pinned compiler.
This measures UI ownership against the existing decoder baseline; it does not
claim that JSON decoding is leak-free. The desktop and asynchronous fixtures also
pass clang ASan/UBSan with leak detection disabled and undefined behavior fatal.

The 2026-10-13 checks use V revision
`826e96f56ca12fcb8fd02dfd6edf1551008e62a8`. The complete host driver passes 28
assertion runners plus SDK context heap, CLI, PTY and Software checks. The current
desktop passes Linux ARM64 and AMD64 typechecks, and the native real-desktop
launcher/heap fixture passes. Reproduce with the pinned compiler and staged
headless UI assets:

```sh
V_MACOS_V3_NO_FALLBACK=1 /path/to/v -no-skip-unused \
  -o /tmp/distribution-check tests/packages/distribution-check.v
V=/path/to/v V_MACOS_V3_NO_FALLBACK=1 \
  VINIX_PACKAGE_TEST_UI2=/path/to/desktop-assets/modules \
  VINIX_PACKAGE_TEST_DESKTOP=/path/to/desktop-assets \
  VINIX_UI2_SOURCE=/path/to/ui2 CPATH="$PWD/desktop" \
  /tmp/distribution-check --direct-tests --desktop
```

[Host and desktop results](results/2026-10-13/software-locked-mirror-host.txt)
and [compiler/source/artifact ledger](results/2026-10-13/software-locked-mirror-toolchain.json)
retain the passing markers and hashes. Full local logs, staged sources,
generated desktop C, binaries and sanitizer results remain under
`build/package-software-locked-mirror-work`. An initial desktop test-helper
signature error is recorded separately; the corrected fixture supplies the
passing desktop/sanitizer evidence. Compiler notices remain in the build logs.

This step qualifies host/headless presentation and argument/ownership behavior.
It adds no new guest, physical removable-media, power-cut, graphical-session
broker or foreign-runtime qualification. Public publisher enrollment, remaining
catalog/runtime migration and graphical brokerage keep roadmap 14 open.

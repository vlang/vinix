# Package desktop entry string encoding

Signed names and comments containing literal backslashes were written directly
to generated `.desktop` files. An XDG reader interprets sequences such as `\n`,
`\t`, `\r`, `\s` and `\\`, changing the displayed metadata. Whitespace adjacent
to `=` also needs preservation. The [XDG string escape rules](https://specifications.freedesktop.org/desktop-entry/latest/value-types.html)
and [key/value format](https://specifications.freedesktop.org/desktop-entry/latest/basic-format.html)
define the encoding independently of JSON manifest escaping.

The existing launcher builder now doubles literal backslashes and encodes leading
and trailing ASCII spaces as `\s` in Name and Comment. Ordinary internal spaces,
UTF-8 and scalar semicolons keep their existing bytes. Signed manifests remain
unchanged, and actual control characters remain refused by manifest admission.
The helper writes directly into the existing owned builder without new scratch.

Installed registration validation already regenerates the expected launcher with
the same serializer. Old raw launchers requiring escapes therefore become
eligible for normal same-version repair from signed state. Historical raw
launchers remain subject to rollback's existing canonical health check; the
service refuses such a damaged rollback target rather than rewriting a retained
generation. Repair a current generation before relying on it as a rollback
target.

The [maintained V controller](desktop-entry-check.v) runs twenty host build and
control checks. The previous transaction serializer must fail the exact golden
encoding assertion in normal and production builds. Fixed normal/production
tests compare complete launcher bytes and independently decode XDG strings,
including every literal escape spelling, boundary/all-space values, trailing
backslashes, Unicode and empty comments. Explicit checks stay active under
`-prod`; valid inert payloads make control-character refusals meaningful.

The actual signed service fixture installs, repairs an old raw launcher, updates,
uninstalls and rolls back with both AArch64 and x86_64 manifest configurations.
Registry strings and MIME choices must survive each activation. These are host
filesystem transactions with synthetic payloads; they do not execute either
guest architecture or claim graphical launcher interoperability. Existing
installed-health and special-file refusal checks also run. The tracked fixtures
require zero bytes/records after 1000 escaped launcher assemblies and 128 healthy
or registration-damaged discovery cycles. Focused ASan/UBSan disables leak
detection and makes undefined behavior fatal; tracked ownership is measured
separately.

```sh
VEXE=/path/to/v V_MACOS_V3_NO_FALLBACK=1 /path/to/v \
  -backend c -gc none -manualfree -o /tmp/desktop-entry-check \
  tests/packages/desktop-entry-check.v
V=/path/to/v /tmp/desktop-entry-check /path/to/new-results 92d1bf687
```

The driver requires at least 650 MiB free before and after each check, caps
generated output at 48 MiB and retires compiler scratch between builds. The
isolated sparse checkout and controller keep the combined namespace below its
60 MiB allowance. Receipts pin source files, baseline transaction source,
compiler and each executed binary; the retained bundle consists of logs and
receipts. Binary/C outputs and synthetic signed installations are scratch.

## Recorded results, 2026-10-26

Source base: `92d1bf6874486fdef3b676d48e30d4e18ba5abf9`. All twenty checks passed:
both previous-serializer controls failed with the required encoding diagnostic,
and all fixed builds and runs succeeded. The tracked loops retained zero bytes
and records. The complete source input hashes matched before and after execution.

The external bundle is
`/Users/alex/Library/Caches/vinix-codex/section14/package-xdg-20261026/qualification-final`.
Its `SHA256SUMS` SHA-256 is
`499cfaa3cbb249b04f31ac48e3d2616c2aeee41a5e89298da0fb4e01dbb6ab91`;
`inputs.json` SHA-256 is
`2edffefa59a610fdc74cbcf72a81873d287f65f97bb088fc803f386b68842a4b`.
The largest recorded per-check output was 19,108 KiB. Combined namespace samples
during the final run reached 27 MiB, including the sparse checkout, controller
and preserved earlier attempts; free-space checks exceeded 650 MiB throughout.

Earlier attempts remain alongside that bundle: `results/` preserves an invalid
initial fixture's wrong baseline diagnostic; `results-final/` preserves the
missing sparse `desktop.workflowcore` dependency failure; `qualification/`
preserves the interrupted run whose input list omitted `tools/packages/x11auth`.
Those attempts are not successful qualifications. `ATTEMPT-SHA256SUMS` in the
namespace pins their complete retained files with SHA-256
`360b3e6fa0c358283f556b16488fb476a856ec5d5004bf3b132cdd62a8b39f44`.

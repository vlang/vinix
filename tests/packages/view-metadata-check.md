# Complete catalog metadata and owned Unicode search

Software's generic catalog decoder accepted missing/coerced presentation fields
and ambiguous duplicates. The new SDK-1 view reader requires complete typed
headers and base rows, validates installed/update/architecture consistency, and
releases partially decoded records and grown buffers on failure.

Installed launch declarations stay separate from the displayed candidate.
Complete legacy groups (no installed columns, or name/kind/permissions before
window protocol) remain supported; partial groups refuse. Valid unknown
additive fields preserve the existing format-1 compatibility contract and are
syntax/Unicode checked without building a generic JSON tree. Reply, text, row,
permission, integer and extension nesting bounds apply. Missing false flags are
errors, not defaults. Package manifests, signatures, service output and persistent
state formats are unchanged.

Software replaces its catalog only after a complete valid decode. Invalid
asynchronous replies report the reason, retain the last valid view and start no
administrator prompt. Decoded arrays transfer to the UI without deep cloning;
reload and normal close retire their owned text.

Measuring the actual Unicode reload path also exposed a separate search leak:
the pinned `string.to_lower()` retains its rune buffer and the rune-to-string
builder descriptor under manualfree. A 100-cycle diagnostic kept **12,632,000
bytes** across 6,400 rune buffers and 6,400 48-byte descriptors. Software now
streams lowercase Unicode scalar values into one explicitly freed byte buffer,
preserving case matching when the UTF-8 length changes.

Coverage:

- [View reader assertions](../../tools/packages/pkgprotocol/view_reader_test.v):
  complete and escaped Unicode, every required field, typed booleans/counters,
  escaped duplicate known keys, legacy groups, valid additive JSON, invalid
  extension JSON/Unicode/depth, update/launch coherence, and row/text/reply bounds.
- [Reader allocation fixture](view-memory.v): 1,000 wide current/legacy/additive
  and partial-invalid decode/close cycles retain zero tracked bytes.
- [Actual Software fixture](software_view_fixture.v): asynchronous malformed
  replies, prior-view preservation, separate installed grants/protocol, explicit
  legacy details, Unicode case search, and 1,000 reload/search/display/details/
  refusal/retirement cycles retain zero tracked bytes. The qualification driver
  includes this alongside the existing six Software allocation fixtures.
- [Signed CLI fixture](distribution-cli.v): the actual package service's installed
  view and failed-resolution view decode through the public reader while retaining
  provenance and installed permissions.
- [Ordinary-account guest assertions](../accounts/guest/package_metadata.v):
  administrator and standard users read real signed installed catalog/launch
  fields, reject missing flags/coerced protocol/escaped duplicate installed
  permissions, and leave configuration, generations and exports unchanged.

Run host protocol and Software fixtures with the pinned compiler, headless ui2
module and [V distribution driver](distribution-check.v). Both Linux Software
frontends are checked. Reader and Software functional fixtures also run clang
ASan/UBSan with leak detection disabled; retained allocations are measured by the
independent tracked-heap fixtures. The full desktop package-launcher test uses
complete service fixtures and requires zero retained bytes for catalog reloads,
replacing the former generic-decoder allowance.

The [administrator controller](admin-check.v) requires this additional marker on
both architectures:

`PACKAGE VIEW ordinary-admin-standard complete-catalog installed-launch-fields typed-flags nested-refusal read-only PASS`

This qualifies catalog presentation, ownership and ordinary-account service
contracts. Real release publisher enrollment, complete advertised runtime/app
catalogs and ordinary graphical login/display integration remain release gates.

Both QEMU TCG runs passed with clean shutdown and eight verified artifact hashes each: AArch64 **22.767 seconds**, x86_64 **64.085 seconds**. These are functional deadlines, not performance qualification.

The initial Unicode allocation failure led to the measured search fix. An initial x86 boot lacked its default Limine directory; a fresh retry using an existing hash-verified cache passed without changing guest bounds or assertions. The CLI fixture was corrected to include the available uninstalled catalog row, and the Unicode keyboard fixture now initializes focus. All final checks passed.

The full desktop fixture uses a test-only upstream headless control-state guard, existing generated-C compatibility fixes and the original pinned OS/sync helper implementations. Its staging helper also requires the existing hosttest module path. It qualifies package UI lifetimes, not native graphical login.

- [AArch64 receipt](results/2026-10-13/view-metadata-aarch64.json), [serial](results/2026-10-13/view-metadata-aarch64.serial.txt), [QMP](results/2026-10-13/view-metadata-aarch64.qmp.txt).
- [x86_64 receipt](results/2026-10-13/view-metadata-x86_64.json), [serial](results/2026-10-13/view-metadata-x86_64.serial.txt), [QMP](results/2026-10-13/view-metadata-x86_64.qmp.txt).
- [Host checks](results/2026-10-13/view-metadata-host.txt), [initial attempts](results/2026-10-13/view-metadata-attempts.txt), [source/toolchain/artifact ledger](results/2026-10-13/view-metadata-toolchain.json).

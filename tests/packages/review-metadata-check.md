# Complete package confirmation metadata

The package presentation readers now require every format-1 field with its JSON
type. Package flags are explicit even when false; empty strings/arrays and zero
counters are required. This prevents missing firmware/proprietary/requested
flags, unknown fields and escaped duplicate keys from silently changing the
displayed review. Package, repository/history, trust-review, offline-export and
locked deployment-export responses use the same bounded schema/string reader;
every nested review is checked before confirmation becomes available.

The initial reproducer showed that the old package reader accepted a missing
firmware flag, an unknown root field and an escaped duplicate flag. The final
readers refuse missing/null/coerced values, unknown/duplicate fields, malformed
UTF-8/Unicode, integer overflow or noncanonical numbers, trailing data and
excessive collections/strings. Replies remain bounded to 8 MiB, with 8192 review
rows, 4096 intent/requested IDs or repository/history entries, and five named
permissions per package. Package counts are at most 4096 and expiry timestamps
fit nonnegative signed 64-bit seconds. Existing semantic validation still checks
provenance, architecture, versions, dependency intent and export consistency.

Decoded values own their strings/arrays; callers retain the existing `.close()`
contract. Partial failures close all earlier fields/rows, and growing arrays
release replaced buffers under `-gc none -manualfree`. Software releases decoder
errors, clears incomplete reviews and cannot confirm them or request a password.
Signed metadata, CLI output fields, package state and authorization rules are
unchanged; custom format-1 producers must now include the complete schema.

Qualification covers:

- [New schema assertions](../../tools/packages/pkgprotocol/review_reader_test.v)
  remove or null every field at every envelope/row/history level, exercise
  escaped duplicate keys, coercion, integer boundaries, Unicode and collection
  limits, and accept complete Unicode and maximum-u64 responses. All existing
  package protocol assertion runners pass, including policy/personal-data readers
  after sharing their integer/string-array primitives. Clang ASan/UBSan pass with
  leak detection disabled.
- [The service contract](../../tools/packages/pkgcore/review_test.v) round-trips
  an actual signed dependency closure, including proprietary firmware assets,
  through the public decoder. The CLI distribution fixture consumes real signed
  package/deployment/offline responses and keeps its existing transaction,
  policy, rollback and trust-refusal assertions.
- [Reader heap fixture](review-memory.v): 1000 wide valid/partial-invalid cycles
  for all five decoders retain **zero tracked bytes**. Arrays exceed their first
  buffer capacity and invalid responses fail after earlier fields/rows exist.
- [Software fixture](software_metadata_fixture.v): asynchronous missing and
  duplicate firmware replies refuse confirmation before administrator approval;
  1000 package/trust/offline/locked-review decode, page/redraw, refusal,
  cancellation and retirement cycles retain **zero tracked bytes**. Existing
  Software fixtures pass. The full desktop launcher fixture uses complete
  literal metadata and now requires zero retention for these readers, replacing
  its former independent generic-decoder allowance. Both Linux Software target
  frontends accept the sources.
- [Guest assertions](../accounts/guest/package_metadata.v): ordinary
  administrator and standard accounts read all five actual CLI response schemas,
  including retained publisher history and a locked export, with no password.
  Removing a false firmware field is refused in both direct and nested reviews;
  package state/configuration and export destinations stay unchanged. The
  [controller](admin-check.v) also requires the existing policy,
  authenticated-install/remove/rollback/disconnection/trust/audit checks.

Run the host protocol and Software checks through
[distribution-check.v](distribution-check.v) with `--direct-tests` and the pinned
compiler. `--software-only --direct-tests` includes the new page memory fixture;
the full suite also runs [review-memory.v](review-memory.v). Guest commands use
fresh state directories and retained production kernels as documented in
[administrator qualification](admin-check.md). The additional marker is:

`PACKAGE METADATA ordinary-admin-standard complete-package-trust-history-offline-lock typed-flags nested-refusal read-only PASS`

These checks qualify presentation metadata and its service/ordinary-account
contract. Ordinary graphical login/display integration, real publisher enrollment
and the complete compatibility-runtime catalog remain roadmap release gates.

Both QEMU TCG guests passed: AArch64 **30.528 seconds**, x86_64 **68.815 seconds**, each with clean shutdown and eight verified input/serial hashes. Deadlines are functional, not performance qualification.

Initial guest builds hit a fixture variable named with the reserved `lock` keyword. After correction, ARM passed metadata/policy checks but failed the existing detached-worker completion assertion. A fresh ARM retry passed with the same thirty-second bound and state assertions; new failure diagnostics were added. The passing x86 fixture predates only those diagnostics. The disconnected-worker flake remains unexplained.

The full desktop fixture first encountered a missing upstream headless guard, then temporary disk exhaustion and omitted compiler runtime-helper definitions. Its test-only stage guards native control-state branches and links the original pinned OS/sync helper headers; the same generated test C then passes. This qualifies headless package workflows, not a native graphical login. Failed attempts and exact C witnesses are retained.

- [AArch64 receipt](results/2026-10-13/review-metadata-aarch64.json), [serial](results/2026-10-13/review-metadata-aarch64.serial.txt), [QMP](results/2026-10-13/review-metadata-aarch64.qmp.txt).
- [x86_64 receipt](results/2026-10-13/review-metadata-x86_64.json), [serial](results/2026-10-13/review-metadata-x86_64.serial.txt), [QMP](results/2026-10-13/review-metadata-x86_64.qmp.txt).
- [Host checks](results/2026-10-13/review-metadata-host.txt), [initial attempts](results/2026-10-13/review-metadata-attempts.txt), [source/toolchain/artifact ledger](results/2026-10-13/review-metadata-toolchain.json).

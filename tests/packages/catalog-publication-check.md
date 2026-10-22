# Catalog publication lock qualification

The publisher now checks a workspace's `catalog.json` before signing an index.
Both `publish` and `publish-release` require the complete manifest set to match
that catalog's package declarations. An extra, missing, or changed package row
refuses publication before replacing an index/signature or reserving a release
sequence. Rebuild the reviewed catalog workspace after changing its declarations.

Comparison is semantic: package/import order, architecture order, JSON formatting,
and the ordering of files, dependencies, permissions and associations do not
change the result. Launch argument order remains significant. Every other
manifest field, including payload hashes, lengths and executable flags, is
compared. The lock is parsed with the existing strict catalog schema and target
and dependency checks.

The lock reader opens a nonblocking, no-follow descriptor, requires an ordinary
single-link file owned by the effective publisher with no group/other write
bits, and captures at most 8 MiB. Its final descriptor and pathname checks refuse
replacement, removal, changed size or changed permissions. The publisher signs
the admitted declarations and payload hashes; it does not reopen the lock to
build signed bytes.

An absent lock deliberately preserves plain `pack`/`pack-root` workspaces. A
dangling alias or other unreadable/unsafe lock is an error. The optional lock
does not authenticate human review or prevent its owner from deliberately
removing or replacing it. Inputs must remain stable during publication; this is
not protection against a hostile publisher process editing its own files in
place. The consumer release still contains only `index.json`, `index.sig` and
objects. No publisher identity, license permission, production repository or
guest execution qualification is supplied by this change.

## Retained host check, 2026-10-23

The [receipt](results/2026-10-23/catalog-publication-host.json) pins the exact
production/test sources, qualification driver, V compiler and Clang driver,
build/run arguments, binaries and logs. The
[human-readable report](results/2026-10-23/catalog-publication-host.txt) records
the completed suites and generated C for the canonical Package parameter. This
is a host admission check using structural payloads for both target declarations.
It does not execute either target binary. The host compiler installation and SDK
are local inputs; the receipt does not claim a hermetic compiler distribution.

The focused suite runs with `-gc none -manualfree` in four modes: normal,
`-prod`, ASan/UBSan, and `-d track_heap`. Its checks use explicit branches and
panic, because the pinned V compiler removes `assert` statements in `-prod`.
It verifies:

- Matching/reordered locks and a lock-free workspace produce identical signed
  index and signature bytes.
- Changed, extra and missing manifest rows refuse both public publication
  functions, preserve the existing index/signature/history, and allow a restored
  retry at the intended sequence.
- Twenty manifest-field and launch-argument mutations and eight malformed,
  unknown/duplicate schema, format, architecture or source mutations refuse.
- The inclusive size limit, owned captured bytes, aliases, directories,
  hardlinks, unsafe mode, oversized files and FIFOs behave as specified. A
  two-second child alarm bounds the FIFO test. Checkpoint mutations exercise
  replacement, removal, permission changes, growth/shrinkage and injected
  errors, followed by restored retries.
- Nine reader/comparison success and refusal paths, each repeated 128 times
  after warmup, retain zero allocation bytes/records and no file descriptors.

Existing catalog, release, and tracked release-builder ownership suites also
run without `-prod`, preserving their assertion checks. They cover the plain
workspace path and existing release staging/history/refusal behavior.

The new complete comparison exposed a compiler-generated allocation in the
shared canonicalization helper. Explicit synchronous borrowed receivers for its
four array clones prevent heap promotion of the by-value Package parameter.
Only the independent clone buffers are retired; nested manifest fields remain
borrowed. The generated-C check requires a stack parameter and no `memdup` in
that function, alongside the measured complete-path ownership checks above.

The existing release ownership regression also exposed a pre-existing 16-byte
temporary on unresolved-dependency refusal. Formatting its already captured
cause string once preserves the diagnostic and retires that temporary. The
report includes generated C showing one owned cause, its release, and transfer
of the completed message to the returned error. The tracked regression checks
all 38 release success/refusal modes, with zero retained bytes/records and no
descriptor growth.

## Reproduce

Use the repository's pinned V compiler, with Clang available at
`/usr/bin/clang`. From the repository root:

```sh
V=/absolute/path/to/pinned/v
"$V" -cc /usr/bin/clang -o build/catalog-publication-check tests/packages/catalog-publication-check.v
build/catalog-publication-check "$PWD" "$PWD/build/catalog-publication-new" "$V"
```

The output directory must be new. The V driver runs all seven suites, checks the
focused success markers, verifies the generated C, rechecks all pinned source
and tool bytes, and writes `qualification.json`. ASan's leak detector is disabled
on this host; retained allocations are measured separately by the repository's
allocation-free heap tracker. ASan/UBSan still check invalid accesses and
undefined behavior. Keep assertion-based regression suites without `-prod`.

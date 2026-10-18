# Owned package review construction

Package review construction now finishes future-generation admission, disk
estimation and available-space observation before allocating presentation rows.
Final validation retires a refused complete review. Returned reviews clone
their fingerprint as well as their other fields, so callers can retire all
borrowed inputs independently. Ordinary and deployment callers retire the
temporary fingerprint on success and failure.

Generation-counter scans release their path, directory-name strings and array
on success, malformed numeric names, overflow and counter exhaustion. Ordinary,
rollback and deployment admission release temporary comparison fingerprints.
CLI review commands close their returned review and final output string.

Ordinary and deployment fingerprint encoders use an explicitly owned growing
byte buffer and SHA-256 state/digest storage. They retain the exact previous
JSON field order, escaping, omitted repair fields and identity domains; no
package, launch, review or persistent format changes. Stale-review checks still
run under the existing locks, and the service still repeats its final space
check before maintenance.

The [construction fixture](../../tools/packages/pkgcore/review_construction_test.v)
uses sixteen independently owned package inputs with Unicode names and wide
descriptions. On both architecture declarations it measures 128 cycles each of
changed/no-op construction, unavailable space, invalid final presentation,
overflowing disk requirements, noncanonical generations, exhausted counters and
out-of-range counters. Each scope requires zero retained tracked bytes. A
separate 1,000-cycle ordinary/deployment fingerprint scope has the same bound.
Functional assertions compare fingerprints with the previous encoding across
maintenance operations and repair identities, and retire the input states,
root lists and fingerprint before validating/encoding/closing a returned review.

The scope is the complete private review-construction helper, counter scan and
fingerprint functions. It does **not** establish allocation freedom for complete
public service requests: configuration, catalog/state preparation, resolution,
activation and generic CLI encoding have separate lifetimes. Broader section 14
publisher/catalog, graphical-session and foreign-runtime release gates stay open.

Run the [host driver](review-construction-check.v) with a reviewed V compiler:

```sh
v -nocache -o /tmp/review-construction tests/packages/review-construction-check.v
V=/path/to/reviewed/v /tmp/review-construction /build/new-review-construction
```

Its 21 compile/run checks cover tracked construction, signed reviews, deployment
and repair, plus the real CLI, normally and with ASan/UBSan. The
[native controller](review-construction-runtime-check.v) runs construction,
signed review and deployment assertions on each target. It allows 900 seconds
per scenario for TCG. The [retention helper](review-construction-retain.v) saves
reports and binds source, compiler, binary, kernel and evidence hashes; its
`--verify` mode checks the resulting ledger.

The pre-change baseline uses eight mixed construction cycles and 32 paired
fingerprint cycles after initialization. The initial longer baseline exceeded
the allocation tracker's 16,384 live-record capacity; the shortened scope records
retained bytes without overflowing that tracker. It retained **683,272 bytes**
for AArch64 declarations and **683,000 bytes** for x86_64 declarations, plus
10,392–10,536 bytes in each generation refusal scope. The paired fingerprint
scope retained **8,291,264 bytes**. Those are bounded fixture measurements, not
whole-service per-request rates. The later fixed fixture additionally covers
disk-estimate overflow and independent fingerprint ownership.

Recorded 2026-10-18 results:

- [All 21 host checks passed](results/2026-10-18/review-construction-host.txt).
  The [receipt](results/2026-10-18/review-construction-host.json) retains commands,
  source/compiler hashes, timings and artifacts for construction, signed reviews,
  deployment, repair and real CLI controls normally and under ASan/UBSan.
- The [normal](results/2026-10-18/review-construction-construction-run.txt) and
  [sanitized](results/2026-10-18/review-construction-construction-sanitize-run.txt)
  construction/refusal/fingerprint scopes retained zero tracked bytes and
  independently owned responses survived input retirement. ASan used
  `detect_leaks=0`; UBSan stopped on undefined behavior. The
  [shortened old-code baseline](results/2026-10-18/review-construction-baseline.txt)
  records the original retained allocations described above.
- Fresh target fixtures passed on
  [AArch64 in 37.3 seconds](results/2026-10-18/review-construction-aarch64.txt) and
  [x86_64 in 31.0 seconds](results/2026-10-18/review-construction-x86_64.txt),
  using pinned prebuilt kernels and TCG. Each guest runs tracked construction
  and signed review/deployment controls. Raw serial logs are retained beside
  these reports.
- Complete desktop headless typechecks passed for
  [arm64](results/2026-10-18/review-construction-desktop-arm64.txt) and
  [amd64](results/2026-10-18/review-construction-desktop-amd64.txt), using current
  desktop sources and the staged generated Calculator/translation assets.

The frozen compiler was V `0.5.2 826e96f`, executable SHA-256
`d88f743f74a74289a5ae6d151df4b056f09bf6ccd21e8f28137017891d2cb0af`.
The [hash ledger](results/2026-10-18/review-construction-ledger.json) binds the
retained evidence, original measured sources and current source/tool/artifact
inputs. Broader release acceptance and complete service ownership remain open.

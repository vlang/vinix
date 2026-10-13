# Complete data scrub qualification

`data_scrub_test` joins all existing host suites under ASan/UBSan. An
independent 4096-mask oracle verifies all combinations of twelve changed rows,
including multiple early/later mismatches. Invalid later observations preserve
the caller; report encoding rejects them before output. Exact canonical ASCII
is compared against independently constructed rows and standard-library
reference/data SHA-256. Empty desired rows, the complete 64-disk/row/region
case, full-width signed offsets, bit 63 and the 132-argument CLI limit are
covered. Count remainders and complete decimal tokens fail before source I/O.

The shared physical-device model scans both 73728-byte extents, crossing the
64-KiB boundary. Clean, interrupted/short-read and one/two-corruption scans
check complete delivery, all pre/post-read rechecks, canonical reports,
independent digests and status 0/2. A later I/O error after earlier corruption
returns 1, publishes nothing and preserves the old report. All prior pin,
identity/geometry, invalid-transfer and source/destination rejection cases
remain active. Nonregular/symlink/FIFO destinations, source aliases, corrupt
references and invalid participants reject before device opens. Every partial
pin drains. Writer contention preserves the report and permits verification.

Real publication tests cover clean/changed and changed/equal reports under
short/EINTR writes, write/file-fsync/close/rename/directory-fsync faults and
durable retries. Before rename old bytes remain; afterward only the complete
candidate appears. Retry performs both flushes. Buffered stdout failure after
publication returns 1 and drains every device pin without modifying the
reference. Generated utility/guest C is audited for heap/V-runtime dependencies
and strictly compiled for both architectures.

First-boot guests corrupt one page on each physical disk, collect all five rows
with exactly two changed mappings, persist both expected/actual digests and
prove failed-scan rollback, writer exclusion, source/device-node preservation,
exact clean retries, stable generations and readable held descriptors. Both
original pages are restored before other tests. `PLAN SCRUB PASSED:` is
required. Reordered second boot saves the same complete clean report
(`PLAN SCRUB REORDERED BOOT PRESERVED`).

Both architectures retain all previous assertions and **200 warmup + 200
measured 41-command cycles / 16400 utility processes**, adding 400 complete
five-row scrub publications alongside 400 original verifications. Every slab
class and large-page total must stay flat or decrease. Instrumentation warms
both reusable snapshot buffers/readers before baseline; the 1800-second limit
is unchanged. All nine earlier boots remain enabled. Eighth boot saves an
actual nine-row report; ninth production boot reruns the scan and preserves its
exact bytes and live generations (`PLAN SCRUB SAVED:` / `PLAN SCRUB BOOT
PRESERVED`). Independent artifact checks construct clean and two-corruption
reports from the actual saved manifests and raw disk bytes, verify reference
fingerprints, all canonical rows, exact persistence/retries and prior data.

# Process-churn report checker

`check-results` compiles and invokes `check-results.v` directly. Its native
`churncheck` module reads log text, parses fields and checks all seven modes:
exec, slabinfo, waits, directories, pipes, sampling and select. The former Python
entrypoint, `_native.py` binding and callback query/controller are retired.

V checks duplicate fields and cohorts, complete measurements/grace/tracking,
filesystem identity, tracking overflow, six-second grace, timed-workload coverage,
300 ms sleep evidence, slab descriptor settlement and small-object limits.
Thresholds, measurement output order and the guest fixture remain unchanged.
The optional flat checks apply only to the original modes, sizes and subjects;
other classes and unrelated physical-memory growth may remain positive.

Field matching retains Unicode 13 word/whitespace rules. Log reads replace
malformed UTF-8 and normalize CRLF/CR; line splitting also accepts the original
Unicode separators. Decimal and hexadecimal conversion accepts signs,
underscores and Unicode decimal digits, with arbitrary-size V integers. Numeric
aliases cannot create distinct cohort/class keys. Allocation summaries require
unsigned decimal digit sequences at the end of the line. Policy failures produce
`FAIL:` on stderr and status 1, with no partial report on stdout; argument errors
use status 2. Interspersed options, `--mode=...`, unambiguous long-option prefixes,
repeated options, `--help` and `--` are supported.

Run `v -nocache -cc cc test tests/process-churn/churncheck` for policy fixtures.
Compile `check-results.v` separately and set `VINIX_CHURN_CHECK_TOOL` to that
binary to include CLI tests. `VINIX_CHURN_FIXTURE_DIR` optionally saves the seven
qualified input/output fixtures for cold-launcher checks. The shared launcher
keeps compiler messages on stderr and removes its private temporary executable.
There is no Package Session dependency or Python callback API in this command.
This is host report validation; it establishes no new guest memory, kernel,
hardware or QEMU measurements. The separate VM runner still awaits its V port.

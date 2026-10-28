# Metadata audit of a Maps UART export

`uart-frame-audit.v` reads an explicitly SHA-256 pinned, canonical, single-link,
0400 regular UART snapshot of at most 8 MiB. It reports numeric frame positions,
lengths, counts, non-base64 byte codes and digests. It never prints CHUNK lines,
payloads, console text or the archive. Results require a fresh external directory.

```sh
v -o /external/tools/uart-frame-audit tests/native-android-ws/uart-frame-audit.v
/external/tools/uart-frame-audit /external/interval.log SHA256 /external/fresh-audit
/external/tools/uart-frame-audit --self-test /external/fresh-selftest
```

Run compilation and finite checks through `bounded-command.v`, with explicit
memory, wall time, disk reserve, growth and output limits. Keep the executable,
guard receipts and generated results outside Git.

`report.json` is public metadata. Its status is `canonical`, `diagnostic-plan`,
or `unrecoverable`; successful inspection alone does not establish a successful
application test. `plan.json`, when present, is private evidence compatible with
`diagnostic-uart-reconstruct.v`. It contains exact original removal bytes and
must never be printed. Feed it and the unchanged pinned UART to that reconstructor
for archive/schema validation and its public diagnostic receipt.

A diagnostic plan requires complete original, ordered BEGIN/CHUNK/END headers,
canonical decoding of all other chunks, exactly one anomalous chunk and a single
contiguous insertion of at most 512 bytes. The tool fixes the deletion length from
the expected encoded chunk size and enumerates at most 685 exact starting offsets.
Removed bytes must be printable ASCII or TAB/CR/LF, include a non-base64 byte and
contain no export-prefix marker. Every candidate must have canonical base64, the
exact decoded chunk length, and the original complete archive size and SHA-256.
Exactly one deletion offset must match. Invalid bytes alone never determine the
insertion boundaries. Multiple anomalies, ambiguous offsets, payload substitution,
base64-only excess and altered headers produce no plan.

The original strict import failure, snapshots and UART remain unchanged. A
diagnostic derivation does not turn a rejected strict import into a strict pass.
The selftest covers clean exports, same-line and split-line insertions, ambiguous
offsets, damaged or incomplete headers, multiple anomalies, payload substitution,
non-console controls, bad pins, existing output, writable files, symlinks and FIFOs.

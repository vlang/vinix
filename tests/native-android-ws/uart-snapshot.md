# Exact UART intervals

`uart-snapshot.v` preserves a complete, fixed-length snapshot of a growing UART
and optionally extracts exactly the bytes appended since a pinned prior
snapshot. It copies bytes without interpreting frames, removing noise or
repairing output. The original serial file remains open and untouched.

```sh
uart-snapshot /absolute/serial.log /absolute/before-fixtures
# Run the child fixture; wait for its complete END frame and terminal PASS.
uart-snapshot /absolute/serial.log /absolute/after-child --after /absolute/before-fixtures BEFORE_RECEIPT_SHA256
# Run the Settings fixture; wait for its complete END frame and terminal PASS.
uart-snapshot /absolute/serial.log /absolute/after-settings --after /absolute/after-child CHILD_RECEIPT_SHA256
```

Each invocation prints its receipt SHA-256. Use that exact hash for the next
`--after` argument. All paths must be canonical and absolute; output directories
must be fresh. A successful output contains only `full.log`, `interval.log` and
`receipt.json`, with mode 0400 inside a 0500 directory. The receipt pins both
files, the exact interval start/length, prior receipt/full-file hashes, and
source identity. Preserve the complete directories with the original UART.

The helper fixes the snapshot end at the source's initial size, reads that
prefix twice, and rejects truncation, changed bytes or pathname replacement
during capture. Later appends are allowed outside that end. Cross-capture
continuity requires exact equality with the entire prior snapshot; recorded
device/inode fields are descriptive across captures. Prior snapshots must keep
their exact members, read-only modes and pinned contents. Inputs are regular,
single-link files bounded to 8 MiB, matching the diagnostic reconstructor.

Use each `interval.log` independently with the unchanged
`diagnostic-uart-reconstruct.v` version-2 plan. Set `serial_sha256` to that
interval's hash and `frame_prefix` to `VINIX-SERVICE-QUERY-RESULTS-1 ` for these
fixtures; use the BEGIN metadata for archive hash, size and chunk count. Start
with `removals: []`. Reconstruction remains a diagnostic derivation. Two
same-prefix exports in one input are deliberately rejected by that checker.
Take a new baseline before Maps if its interval should exclude the fixtures.

Host binary:
`/Users/alex/.local/state/vinix/android/uart-snapshot-2026-10-27-r1/uart-snapshot`,
SHA-256 `5c168a23bee32c9703c51905cc5e4676861668817b05afd9757d759a92ed0b84`.
Source SHA-256:
`8bb66f0a64eb927115fd0154dd986c02bbb014ca6e3dc075697a7a7a4523ec4a`.
The retained compiler is
`/Users/alex/code/v-tccbin-bootstrap-20261026/v`, SHA-256
`0cc6c1d34c1811a818e4ae89853116861a4b067d4251af257851a7714f0d11fe`,
with its adjacent compatible library. The bounded compile passed at
315,998,208 bytes sampled aggregate RSS under a 600 MiB cap, 300 seconds,
1 GiB disk reserve and 512 MiB shared-volume growth allowance.

The executable selftest passed exact binary preservation (including NUL,
non-UTF-8 and CRLF), appended interval equality, changed-prefix/truncation/
no-append refusal, receipt pin mismatch, existing output, symlink and read
bounds. Independent source review found no blocker for append-only UART use.
Sources, binary, fixture outputs and adjacent guarded receipts/logs are retained
at the external directory above. Its sibling `-seal/manifest.json` pins all
27 retained entries (SHA-256
`e629b3904e8a3fba12ca18289dff359940ee6c489fb22e25a54f9469609f0144`);
the complete readback passed. Initial failed compiler diagnostics are
preserved separately from the successful `-r3` compile. This host check does
not establish guest fixture execution or Maps behavior.

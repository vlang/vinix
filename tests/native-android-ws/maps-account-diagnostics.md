# Maps controller diagnostics — 2026-10-28

The controller now exports capped numeric `auth_pump` and `account_handoff`
diagnostics in its public receipt. It accepts only complete canonical lines of
at most 128 bytes, preserves the first 32 valid records in order and marks
truncation on the next valid record. Pump stages are `1..4`, pending is `0..1`
and status is a canonical signed 32-bit integer. Handoff records use the shared
[`accounthandoff` parser](../../build-support/android/accounthandoff/diagnostics.v)
and its finite schema; raw broker output remains private.

Independent `--trace-tls` and `--trace-onboarding` broker options are persisted
through the protected session and launch receipts. Maps explicitly sets or
unsets each selected environment variable, so ambient terminal variables cannot
enable tracing. Legacy receipts default to disabled. TLS logs remain private
and are excluded from public result archives.

The canonical builder now replaces its bootstrap process and replaces its
source-discovery phase before compiling. The next phase verifies the retained
executable, preparation bindings, source closures, original inputs, revision and
baseline before continuing. This releases discovery workspace under `-gc none`
while preserving the existing compiler, native-input and output checks.

The complete fresh producer passed at
`/Users/alex/.local/state/vinix/android/maps-account-guest-build-2026-10-28-handoff-r2`.
Its real host self-test covers canonical numeric boundaries, malformed and
private extensions, incomplete lines, record ordering/caps, all independent
trace selections, legacy defaults, ambient-variable removal and archive
exclusion. Static ARM compilation, linking, ELF and source/input checks passed.
Two generated-C reviews confirmed that the pump parser and wrappers free their
independent string allocations once; the shared handoff parser allocates nothing
on successful parsing. Independent source reviews approved the phase split and
trace selection. These are producer and host checks; guest diagnostics, imagery
and Google authentication still require runtime validation.

The producer recorded source revision
`98b316c0d90fa7635a4790bada86749d1ef1fa17`; exact working sources are retained
and pinned in its closures. SHA-256 identities:

| Item | SHA-256 |
| --- | --- |
| Controller source | `9d749bbed702614f29b321b0dd5f59acaffa6b529b52a2bf28554c4f95e411e3` |
| Builder source | `6ecb3a66612ba7120bea83192edfd28c83f4c8485a92b5160d0288b78a8b713e` |
| Complete `sha256.json` | `1cf0e472fb977e705204f06fcad806f0c1ea16d213d469d0174c658c27fb041d` |
| `build.json` | `ce59e4bd60301fa65cd9f0fd924f5974d8e4bd9b54d9c750183696bedcd22da9` |
| `current-inputs.json` | `425a314ba814a184cb5840620158ee370055f4201a720e4c4ddedd4e8db0b0be` |
| `bin/maps-account-guest` | `0253f16da634ffef92e1efa2b3102d1ad91af15d1f521081f60e920e78affc6b` |

The external guard receipt
`/Users/alex/.local/state/vinix/android/maps-controller-diagnostics-build-2026-10-28-r4.json`
has SHA-256 `94e9152a9e6fe76e7993125bd2c9e70f69ffe4b7a65fec3c978a01c65c04d680`.
It records exit/child status `0`, complete cleanup, 52.576 seconds, sampled
aggregate RSS 614,170,624 bytes, observed disk growth 495,738,880 bytes and a
minimum 3,614,515,200 free bytes. The retained time log reports peak process RSS
480,362,496 bytes and zero swaps. Limits remained 600 MiB aggregate RSS,
300 seconds, 1 GiB reserve, 1 GiB observed growth and 4 MiB output.

Earlier external producer roots remain unchanged:
`maps-account-guest-build-2026-10-28-diagnostics-r1` hit the RSS guard;
`diagnostics-r2` completed compilation but exposed a pump-parser double free in
the real self-test; and `handoff-r1` hit the RSS guard during host compilation.
The final source removes the duplicate element-free loop and uses the canonical
process replacements described above. Their failed receipts, source snapshots
and the exact temporary restart helper used by `diagnostics-r2` remain external.
No guard was increased to obtain the successful result.

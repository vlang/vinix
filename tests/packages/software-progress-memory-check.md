# Software progress stream ownership

Software ignored unsupported or malformed progress frames but retained the
decoder's owned error. The previous `ab6911db7` progress handler retained 32,000
tracked bytes across 1,000 malformed frames. It now frees each rejected error
before returning, matching the lifetime already used by the health reader.

The last admitted progress event and status survive malformed frames. Human
diagnostics, bounded output, newline recovery after oversized input, phase
counter meaning, service exit admission and transaction authorization retain
their existing behavior. No SDK fields, service commands or persistent records
change.

The [stream fixture](software_progress_memory_fixture.v) exercises twelve
malformed-frame classes, each across 1,000 measured cycles after warmup. Each
cycle streams all eight valid phases in seven-byte fragments, including UTF-8
splits, then a malformed frame, an oversized line, valid transfer recovery,
progress-bar rendering and an unterminated human failure diagnostic. Retirement
must retain zero tracked bytes. Cases include unknown/duplicate fields,
unsupported formats/phases, invalid counters/types/UTF-8/paths, truncated frames
and trailing data. Ignored frames cannot start a worker or approval prompt.

The [host driver](software-progress-memory-check.v) compiles and runs protocol
assertions, the measured UI fixture and the complete Software functional suite,
normally and under ASan/UBSan. It records commands, source/compiler hashes and
artifact hashes, then verifies that inputs have stayed unchanged.

```sh
v -nocache -o /tmp/software-progress-memory tests/packages/software-progress-memory-check.v
V=/path/to/reviewed/v VINIX_PACKAGE_TEST_UI2=/path/to/modules \
  /tmp/software-progress-memory /build/new-software-progress-memory
```

The maintained [distribution driver](distribution-check.v) also stages the new
fixture and runs `progress-memory` in its tracked Software build. Allocation
claims concern the explicitly measured scopes; sanitizer leak detection is
disabled. Headless functional checks and target desktop typechecks leave
graphical-session presentation and broader roadmap-14 release/runtime
acceptance open.

Recorded 2026-10-18 results:

- The [previous-handler control](results/2026-10-18/software-progress-memory-baseline-run.txt)
  failed the first measured case with 32,000 bytes retained. Its
  [handler](results/2026-10-18/software-progress-memory-before.v),
  [fixture](results/2026-10-18/software-progress-memory-before-fixture.v) and
  compile log are retained; the handler matches `ab6911db7` exactly.
- [All ten host compile/run checks passed](results/2026-10-18/software-progress-memory-host.txt),
  including the complete Software functional suite and protocol assertions
  normally and under ASan/UBSan. The
  [receipt](results/2026-10-18/software-progress-memory-host.json) records the
  commands and source/compiler/artifact hashes.
- The [normal](results/2026-10-18/software-progress-memory-ui-memory.txt) and
  [sanitized](results/2026-10-18/software-progress-memory-ui-sanitize-memory.txt)
  stream modes each retained zero tracked bytes across all 12,000 measured
  cycles. Existing decoder retirement assertions also passed in both modes.
  ASan used `detect_leaks=0`; UBSan stopped on undefined behavior.
- Full desktop headless typechecks passed for
  [arm64](results/2026-10-18/software-progress-memory-desktop-arm64.txt) and
  [amd64](results/2026-10-18/software-progress-memory-desktop-amd64.txt), using
  current desktop sources and the staged generated Calculator/translation
  assets. The updated distribution runner also typechecked.

The frozen compiler was V `0.5.2 826e96f`, executable SHA-256
`d88f743f74a74289a5ae6d151df4b056f09bf6ccd21e8f28137017891d2cb0af`.
The [retention helper](software-progress-memory-retain.v) verifies captured
inputs/artifacts before publishing evidence, then checks the final
[ledger](results/2026-10-18/software-progress-memory-ledger.json) with `--verify`.

# Owned complete package collection requests

The [full native stress qualification](collection-stress-check.md) now diagnoses
and resolves the fixture reservation limit recorded below, measuring 64 calls
per case on both targets and running all six retirement controls independently.
The results below preserve the original eight-call native qualification.

`Service.collect()` retires its state-directory path and freshly loaded
configuration on success and refusal. The writer lock still precedes loading
configuration. Explicit `collect(config, directory)` borrows both arguments.
Both calls retire decoded retained states, generation targets and cache
enumeration/removal/flush storage. Partial-download digest checks own their
temporary prefix. Failed cache removal keeps the existing `remove(3)` behavior,
diagnostic text and POSIX code with explicitly owned error storage.

The [fixture](../../tools/packages/pkgcore/collection_request_test.v) measures
24 complete request cases for each architecture declaration. After a warm pass,
each case makes 64 calls: **3,072 measured calls**, requiring zero retained
tracked V bytes after return and caller error disposal. Fixture setup, assertions
against persistent storage and post-case cleanup are outside each measured call.
Fresh-store cases recreate the store before each call; reclamation cases recreate
obsolete trees, abandoned stages, 40 cache objects and partial downloads.

Cases cover service and explicit calls, first store creation, retained payloads,
cache/stage/generation reclamation, a live obsolete-generation lease, unsafe
generation/stage roots, noncanonical generation names, corrupt active/rollback
metadata, cache removal failure, writer contention before configuration reads,
malformed configuration and an invalid service root. Configuration and retained
state bytes stay unchanged. Both referenced payload objects and unrecognized
cache names survive. Collection still works offline after publisher revocation
with malformed catalog/history documents, because it does not authenticate them.
Explicit configuration remains usable after repeated requests.

The pre-change baseline uses two calls per case. AArch64 declarations retained
28,668 bytes for service reclamation and 21,212 for explicit reclamation;
x86_64 retained 28,574 and 21,122. Fresh service calls retained 10,406/10,396 bytes.
Early service refusals retained 7,456/7,452 bytes, and lock/configuration refusals
retained 144/142. These are scoped two-call fixture totals, not whole-process
rates. Original production/test sources, executable and output are retained.

Run the [host driver](collection-request-check.v) with the reviewed compiler:

```sh
v -nocache -o /tmp/collection-request tests/packages/collection-request-check.v
V=/path/to/reviewed/v /tmp/collection-request /build/new-collection-request
```

Its 35 compile/run checks exercise seven core fixtures normally and under
ASan/UBSan, compilation without heap instrumentation and signed real CLI
maintenance through both CLI builds. The tracked retirement control measures
128 successful removals and 128 refusals. Descriptor-limit, stage-recovery,
persistent-state, service and reviewed-cleanup fixtures preserve their existing
protection and retry assertions. ASan uses `detect_leaks=0`; these results claim
only the explicitly tracked request scopes, not zero whole-process retention or
exhaustive filesystem-failure coverage. Uninstrumented runs check behavior.

The [native controller](collection-request-runtime-check.v) runs each of the
48 request cases in its own child, with **8 measured calls per case** and an
8-call warm pass: **384 measured requests per target**. It also runs the tracked
removal-helper-only retirement fixture, 128-generation collection
under `RLIMIT_NOFILE=32`, and signed service maintenance on both architectures.
It uses pinned prebuilt kernels and a 900-second TCG limit. Full desktop headless
typechecks cover both targets. The [retention helper](collection-request-retain.v)
binds source, compiler, kernels, binaries and raw reports; `--verify` checks them.

The first host run and native image creation exhausted the checkout's free disk
space. The failed host log is retained. After reclaiming superseded executables
unreferenced by retained evidence, all original inputs were rehashed, and every
host compilation/run and native build restarted in fresh work directories.
Those restarted 35 checks all passed. Native execution then exposed a separate
stress limit: the 64-call fixture failed during file creation or directory
enumeration with `ENOMEM`, also when each case ran in a separate child. A
diagnostic guest reported over 800 MiB free and no memory pressure. The precise
cause was unqualified at that revision. The later stress qualification above
identifies creator reservations retained across the filesystem grace period. Raw
64-call refusal and memory-diagnostic serial logs are retained. Native repetition
is therefore explicitly bounded to 8, with the 64-call host scope retained.
On x86_64, combining the full older retirement suite and its final allocation
probe in one process also exhausted memory after the broad retirement checks
passed. The final native control selects only that allocation probe; the full
retirement suite remains in normal/sanitized host qualification. Its failed
combined native serial log is retained too.

After adding case selection and the native repetition bound, all original
production/control input hashes were verified. The three request compilations
were repeated against the final harness, and every host run was repeated.
Fifteen unchanged control/CLI compilations were retained from the successful
35-check run; their receipt records have zero seconds. The original input pins,
pre-isolation fixture, receipt and continuation source/binary are retained.
The public host driver still performs every compilation in a new workspace.

Activation/refresh ownership, production publisher/catalog migration, full
graphical sessions and foreign-runtime release acceptance remain separate gates;
roadmap section 14 stays open.

Recorded 2026-10-18 results:

- [All 35 host checks passed](results/2026-10-18/collection-request-host.txt),
  with [commands, source/artifact hashes and timings](results/2026-10-18/collection-request-host.json).
  [Normal](results/2026-10-18/collection-request-request-run.txt) and
  [ASan/UBSan](results/2026-10-18/collection-request-request-sanitize-run.txt)
  runs each report zero retained bytes in all 48 request scopes. The
  [baseline](results/2026-10-18/collection-request-baseline.txt) records the
  original two-call totals.
- Native checks passed on [AArch64 in 41.9 seconds](results/2026-10-18/collection-request-aarch64.txt)
  and [x86_64 in 30.1 seconds](results/2026-10-18/collection-request-x86_64.txt).
  Each measured 384 collection requests plus 128 successful and 128 refused
  removal-helper calls with zero retained tracked bytes. Both also passed the
  128-generation / 32-descriptor control and signed service maintenance.
- Complete desktop headless typechecks passed for
  [arm64](results/2026-10-18/collection-request-desktop-arm64.txt) and
  [amd64](results/2026-10-18/collection-request-desktop-amd64.txt).
- The [64-call failure](results/2026-10-18/collection-request-native-64-refusal.serial.txt),
  [isolated-case failure](results/2026-10-18/collection-request-native-isolated-64-refusal.serial.txt),
  [memory diagnostic](results/2026-10-18/collection-request-native-memory-diagnostic.serial.txt)
  and [combined retirement failure](results/2026-10-18/collection-request-native-combined-retirement-refusal.serial.txt)
  preserve the native stress limits above. The initial
  [host disk-exhaustion log](results/2026-10-18/collection-request-host-no-space.txt)
  is retained separately.

The frozen compiler was V `0.5.2 826e96f`, executable SHA-256
`d88f743f74a74289a5ae6d151df4b056f09bf6ccd21e8f28137017891d2cb0af`.
The [hash ledger](results/2026-10-18/collection-request-ledger.json) binds retained
evidence, original snapshots and current source/tool/artifact inputs.

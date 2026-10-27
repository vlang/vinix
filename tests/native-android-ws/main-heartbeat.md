# Native main-loop heartbeat

Maps renders onboarding but the foreground click replay has no native input
receipt. With `VINIX_ANDROID_TRACE_TREE` or `VINIX_ANDROID_TRACE_THREADS`, the
existing background sampler now emits a native `ANDROID-WS-MAIN` snapshot
before any poll or Java stack lookup. It records the main stage, progress,
monotonic stage age and snapshot consistency. The following `MAIN-POLL` line
records a zero-timeout, non-consuming observation of the fixed main input fd.
There are at most ten snapshot/poll pairs, spaced 30 seconds apart. TREE alone
does not attach a JNI environment. Service runtimes retain their existing
thread diagnostics without enabling the main-surface heartbeat.

The main thread stamps Looper, web/account pumps, input readiness/dispatch,
frame callbacks, rendering and sleep. Input also stamps immediately before
poll, header read and text read. These operations publish native atomic state;
they do not add callbacks, consume input or change Java exception handling.
`stable=0` means a three-attempt snapshot overlapped a publication; interpret
its stage/age as inconclusive. A lone MAIN line can identify a sampler blocked
inside poll. Unchanging progress and increasing age locate a stopped main
stage; readiness bits can distinguish queued input from an empty pipe.

Host check: `check-main-heartbeat.v FRESH_EXTERNAL_DIRECTORY` extracts the
production helpers and tests opt-in behavior, progress/age wrap, bounded reads
of interrupted publication, snapshot-before-poll ordering, and real pipe
readability/HUP/invalid-fd states. The pending byte remains readable afterward.
Source checks cover the finite sampler and main/input checkpoint placement.

The successful 2026-10-27 bundle is
`/Users/alex/.local/state/vinix/android/main-heartbeat-checks-2026-10-27-r3`,
with adjacent `-build` and `-run` JSON receipts/logs. Its `SHA256SUMS` has SHA256
`0c5dc6906560d2d271ecc56c7805acbc8dfa69570b6b3c44b3eb97adc74cc0f3`.
It includes source copies, checker/probe executables and generated source.
The checker build and run passed with aggregate sampled RSS below 179 MB and
zero swaps, under 1 GiB RSS, 300 seconds, 1 GiB reserve, 2 GiB observed disk
growth and 4 MiB output limits; process cleanup passed. The compiler SHA256 is
`0cc6c1d34c1811a818e4ae89853116861a4b067d4251af257851a7714f0d11fe`.
The base revision was `7d9fcf91b7313e1e8e29f214489ad7d020afe424`;
the three changed native sources and checker are preserved in the bundle.
Earlier failed attempts r1/r2 remain retained. This check does not validate
ARM execution, Maps interaction or Google login; those require the successor
native build and fresh VM run.

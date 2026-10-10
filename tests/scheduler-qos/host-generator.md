# Scheduler QoS host fixture generator

`policy.v` owns the original source-function extraction, module generation and
assembly order. Its templates preserve the original V fixture text byte for
byte; that transfer earns no algorithm migration credit. Production functions
still come from `kernel/proc/priority.v`, `kernel/sched/runqueue.v` and
`kernel/time/time.v`. All original capacity, donation, pin-lifetime, saturation
and timer assertions remain independent fixtures.

`policy` invokes V directly. With no arguments its native disposable owner
generates, builds and runs every original assertion. `VEXE` retains precedence
over `V` for the fixture compiler, and empty overrides fail. Temporary files
are removed on success and returned failures. The maintained shell entry
selects its own compiler through `build-support/find-v.sh`.
`VINIX_SCHEDULER_QOS_GENERATOR` can select an already compiled generator.
The generator also exposes `--extract SOURCE NAME` for independent comparisons.
Source reads preserve strict UTF-8 and universal newline behavior, and the
extractor counts all braces exactly as the original controller did.

This host-only port adds no kernel build, guest boot or scheduler hardware claim.

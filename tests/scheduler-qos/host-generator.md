# Scheduler QoS host fixture generator

`policy.v` owns the original source-function extraction, module generation and
assembly order. Its templates preserve the original V fixture text byte for
byte; that transfer earns no algorithm migration credit. Production functions
still come from `kernel/proc/priority.v`, `kernel/sched/runqueue.v` and
`kernel/time/time.v`. All original capacity, donation, pin-lifetime, saturation
and timer assertions remain independent fixtures.

`policy.py` retains the original disposable owner and actual compiler launch,
including `VEXE` precedence over `V`, empty overrides and inherited environment.
The normal path builds its generator through `build-support/run-v-tool.sh`.
`VINIX_SCHEDULER_QOS_GENERATOR` can select an already compiled generator.
The generator also exposes `--extract SOURCE NAME` for independent comparisons.
Source reads preserve strict UTF-8 and universal newline behavior, and the
extractor counts all braces exactly as the original controller did.

This host-only port adds no kernel build, guest boot or scheduler hardware claim.

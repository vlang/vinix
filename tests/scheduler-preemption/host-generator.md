# Enqueue-preemption host fixture generator

`policy.v` owns exact production function extraction and the original fixture
module generation. The four templates preserve the original V text byte for
byte with zero algorithm translation credit. Assertions for affinity, priority,
deadlines, offline CPUs, coalescing and unavailable controllers remain intact.

`policy` invokes V directly. With no arguments it assembles the program before
creating its disposable owner, writes the original metadata/main and modules,
then builds and runs every original assertion. The native owner removes its
temporary tree on success and returned failures.
Normal calls use `build-support/run-v-tool.sh` and `build-support/find-v.sh`;
`VINIX_SCHEDULER_PREEMPTION_GENERATOR` can select an already built generator.
`V` retains its compiler meaning. The generator's `--extract SOURCE
NAME` entry point permits independent comparisons against the old extractor.
Strict UTF-8, universal newlines and literal Unix path bytes are preserved.

This host-only port adds no kernel/QEMU/scheduler hardware evidence.

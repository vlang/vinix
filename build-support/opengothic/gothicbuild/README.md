# Native OpenGothic builder

This module owns the complete maintained OpenGothic build workflow: argument
validation, pinned checkouts and patches, APK index/development selection,
parallel downloads, extraction, compiler and linker arguments, runtime staging,
and demo or installed-game handling. The existing Python entry point keeps its
public signatures, annotations, constants and library objects.

The borrowed-object protocol reuses the package-store bridge and host transport.
Python retains actual Paths, subprocess values, archive readers, executor
managers, entered values and exceptions across synchronous calls. Concurrent
fetches have separate controller processes and object tables. Explicit exits
clear ownership before calling library cleanup; transport fallback retires
contexts after reaping the controller and closing its pipes. Suppressed pool
failures preserve runtime replacement before the original unbound-variable
error. Host V uses its normal garbage collector.

Qualification compares the frozen original complete workflow, ordered helper
and external-tool plans, staged bytes/modes/link targets and error identity on
ARM, actual x86 and ARM ASan/UBSan. It also exercises real loopback curl, local
Git checkouts, six-worker fetches, CLI/cold compilation, context suppression,
group interrupts and forced controller exits. These checks use offline source
and compiler fixtures; they do not establish a fresh upstream OpenGothic build,
renderer result or guest/kernel result. Traceback frame lists differ across
the native transport; actual error, manager traceback argument and cleanup
precedence are preserved.

Set `VINIX_OPENGOTHIC_QUERY` to an already compiled `build_query.v` executable
to qualify one ABI. Otherwise the shared transport compiles it through
`build-support/run-v-tool.sh` and retires its temporary executable at exit.

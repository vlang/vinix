# Native VOffice build policy

`build.v` and `core.v` own input validation, protected-directory checks, mbedTLS
inventory and worker submission, compiler/linker recipes, output publication and
incremental build state. `build_voffice.py` retains its public signatures,
constants, argument parser and interpreter entry point. Existing cache-key
algorithms remain in `build-support/cachekey`; the shared key also hashes the
native builder and its binding/compiler source closure.

The generic package-store library bridge retains actual Python paths, command
and argument objects, executor managers, entered executors, futures and callback
functions. V decides their ordering and explicit exits. Futures are consumed in
submission order; successful context exits are not truth-tested. Exceptions use
the actual caller classes and retain their original object and constructor
arguments. A suppressed failure before assigning outputs still raises the
original unbound-local error. Query processes ignore SIGINT and run in their
own sessions; library workers retain the original interpreter behavior.

The local `voffice-builder-20261009` qualification freezes source commit
`e498309c4cad1e073e40509c953a28b033b911cb`. On ARM64, actual Rosetta x86-64 and
ARM ASan/UBSan it compares 111 helpers, 41 complete build plans and 37 ownership,
exception-class and caller-binding cases, plus actual group SIGINT and 100
queries with exact final descriptor equality. The unchanged
`tests/vlang/test-voffice-cache.sh` checks full fake-toolchain builds, cleaned-work
cache hits, test/compiler-source exclusions, app-only rebuilds, missing outputs
and shared-module rebuilds. Both host ABIs also exercise actual cold compilation
and no-compiler CLI/parser parity. Every added source input is invalidated
independently. Lifetime peer review covers distinct manager/entered objects,
callback/future retention, suppression and consume-before-exit cleanup.

These are host builder checks using the original independent fake-toolchain
fixture. They make no new kernel, VOffice application, guest or device claim.
Retained interpreter bindings remain counted Python, and receive no extra
algorithm credit. The compiler is selected through `find-v.sh`/`run-v-tool.sh`;
`VINIX_OFFICE_QUERY` may select a qualified installed query binary.

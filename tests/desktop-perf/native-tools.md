# Native desktop performance tooling

The current runner, four saved allocation-benchmark runners and three saved v6
preparation drivers use V directly. Eleven Python files (146,185 original bytes,
3,224 lines) are retired from source `5b9e309dba3b594168c7ad30dda42f509f47125d`.
[The receipt](native-translation.json) records every original blob and digest.
No Python executes during implementation or qualification. Guest C samplers,
guest initialization scripts, captured logs and data remain unchanged.

`perfrunner` owns arguments, local assets, compiler recipes, staging and final
verdicts. `perfconsole` owns the PTY, continuous serial reader and process group;
its C header only names SDK storage. `qmpclient` supplies native Unix sockets,
with the original performance policy accepting both return and error replies.
Pointer workers share a mutex and stop before the monitor closes. The reader
joins before its descriptor closes. An exited leader reserves its identity until
descendants have been killed and the sole reap completes. Saved drivers own
the log and PID file, stream input hashes, and validate saved results against
an independent 43-row historical transcript inspection.

Fifteen final cold builds and the full controller/report suites pass on ARM64,
Rosetta x86_64 and ARM ASan/UBSan with V `4eb8f2b`. Checks cover original verdict
cases, unchanged compile recipes, local workflow assets before launch, partial
timeout JSON, DONE at EOF, late panic rejection, historical operation coverage,
empty and multi-chunk hashes, saved-input tampering, real Unix QMP, pointer/drag
events and serial backpressure while a QMP reply waits. One hundred native PTY
captures keep descriptors exactly flat in each profile. Three additional cold
owner builds verify exited leaders, descendant retirement and SIGINT/SIGTERM
while blocked on QMP, including removal of temporary VM images.

The public host-test entry point and the shared source-tooling regression suite
pass. Three native entry points cold-build and show help from a materialized
source closure containing no Python. The actual current sampler cross-builds to
a static AArch64 ELF with the unchanged production compiler recipe. These checks
add no fresh kernel build, QEMU boot, kernel lifetime or performance evidence.
The compiler uses its configured local standard library. Sanitizers check
invalid accesses and undefined behavior with leak detection disabled; flat
descriptor checks do not establish flat heap usage.

Originals and qualification records are retained locally under
`~/.cache/vinix-desktop-perf-native-20261012/`; temporary builds live under
`/Volumes/VinixPythonDeviceScratch/desktop-perf-20261012/`.

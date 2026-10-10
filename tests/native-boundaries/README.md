# Native header boundary checks

Run `tests/native-boundaries/run` on an ARM64 host with Clang, nm, Git and V
available. `CC` selects one compiler executable. The native V command compares
the frozen C headers at `8f7239d1fd4c593746279699f6ff25df5f4dd7bd` with the
maintained V UART, callback, stack-pointer and SMC-counter implementations.
Both fixtures use Clang ASan/UBSan and stack-use-after-return detection.

The unchanged independent fixture checks ten UART traces, 256 callbacks,
16-byte stack alignment and monotonic counter reads. Generated callback and
counter objects must have no allocator imports. Both stdout and stderr must
match before the command prints its complete report. Temporary source and
object directories are removed on success and ordinary errors.

`boundarycheck/core_test.v` covers unsupported host rejection and the Darwin
assembly adaptation. Set `VINIX_BOUNDARY_TOOL` and
`VINIX_BOUNDARY_COMPILER_FIXTURE` to native binaries built from `run.v` and
`compilerfixture` to also exercise real compilation, forced compiler and local
fixture failures, allocator imports, output mismatch and cleanup. These are
host checks; they do not build or boot a kernel.

The ARM command and test suite pass with ordinary and ASan/UBSan host builds.
The Rosetta x86 command rejects the unsupported host before any work is created;
its assembly-adaptation and architecture-rejection tests also pass. The cold
launcher passes from an unrelated working directory and leaves no temporary
files after either success or compiler failure. Qualification logs are
`/tmp/vinix-boundary-{arm,asan,x86}-final.log` and
`/tmp/vinix-boundary-cold-final.log`. No Python was run.

# Native SMC and display-hotplug commands

This stage removes three Python runner/adapter files (11,669 bytes and 221
lines in `37f7152d`) and retires the display-hotplug V bridge that borrowed
Python objects. Both shell commands execute V directly. No Python was written
or executed. Production algorithms, independent fixtures, ABI headers, original
assertions and line tags remain byte-identical to that revision.

SMC keeps its standalone full-core `-shared -no-builtin -os vinix` producer,
manual freeing/nofloat flags, frozen original C, distinct core/fixture allocator
bans, exact binary golden comparison and complete 27-test verdict. Its native
build retains both musl SDK recipes, serial constructor, all output markers,
no networking and 300-second guest deadline. `--host-arch` and `--build-only`
are additional native CLI options; existing invocations remain supported.

Display-hotplug copies and renames only the production module declaration. Its
original module producer, warning/PIC and linker-flag policies, header bytes,
object order, allocator ban and manifest fields are retained. The original
entry/header literals are unchanged dependencies and receive no translation
credit. Host fixture runs retain the 180-second limit, required verdict and
exact status/stdout/stderr parity. Native guests retain their terminal marker,
`check failed` negative policy, no networking and 300-second limit.

V owns each fresh retained state or private temporary, signal scope and direct
subprocess. SMC defaults remain under `/tmp` with mode 0700. Hotplug honours
writable temporary environment candidates, falling back to standard temporary
directories; it no longer creates an unused outer temporary for retained state.
Literal backslashes/newlines and explicit empty path options are covered.
Binary oracles/output and environment bytes stay raw; source/symbol text uses
strict UTF-8 and universal newlines. Python callback-object and traceback APIs
are retired with their callers.

Qualification uses V 0.5.2 `37c0ab3`, actual ARM and Rosetta x86 SDK binaries,
and ARM ASan/UBSan with compiler fallback disabled. Eight shared native tests
pass on all three profiles. Six fresh public entry-point builds pass. On each
profile, production copies and immutable C/header bytes are checked; the
original native module API produces identical hotplug production/fixture C.

Current consumer results:

| Consumer | Result |
| --- | --- |
| Display-hotplug host | Independent original-C/V complete result comparison passes on ARM, x86 and ASan/UBSan. |
| Display-hotplug guest | Static V and original C fixtures build and pass on both prepared kernels. |
| SMC full core | Builds as a strict actual ARM/x86 host object without banned allocator imports. |
| SMC independent mailbox fixture | Compiler-generated undeclared `memdup` remains a strict failure on all three profiles; no 27-test or guest pass is claimed. |

CLI/fresh-state guards, retained literal paths, repeated default-owner failures
and actual controller SIGINT/direct-child retirement are measured on all three
profiles. Both shell frontends compile their native CLI from outside the
checkout and retire their launcher work. ASan uses `detect_leaks=0` on macOS;
there is no LeakSanitizer result. No kernel was rebuilt and no physical mailbox
or CD321x/DCP display behavior was tested.

Evidence is retained under
`/Users/alex/.cache/vinix-python-zero-process-20261011`: `smc-*-host`,
`hotplug-*-host`, `hotplug-*-native`, `hotplug-*-guest*`,
`mailbox-host-*-final.log`, `mailbox-artifacts-*.log`,
`mailbox-units-*-release.log`, `mailbox-owners-*.log` and
`mailbox-cold.log`. Prepared kernel hashes are the same as in
[Apple/Wi-Fi runner qualification](runners.md).

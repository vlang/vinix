# Native policy host commands

These maintained commands compile and run V directly:

```sh
tests/init-policy/run [--arch arm64|amd64] [--work-dir /fresh/path]
tests/alloc-track/run
tests/kernel-print/run
tests/stack-protector/diagnostic
tests/kernel-cpu/logic
tests/network-options/compile-core /path/to/core.c
tests/network-options/run-host network-options test.c
```

The four network `run-host.sh` entrypoints select their original fixture and
use the native controller. Compiler and fixture arguments, allocator guards,
debug/production and init echo variants remain. The network fixture retains
its 60-second deadline, inherited standard streams and kill/reap on timeout.
Other builds and fixtures keep their original lack of a deadline. All temporary
source and executable owners are private and retired after success or failure;
init's explicitly requested fresh work directory remains available for review.
`V` and `VINIX_V_COMPILER` retain the repository compiler selection policy.

The CPU declaration and assertion templates are the unchanged V literals from
the retired controller. They exercise the actual three production arithmetic
functions. The allocation tracker exercises all 8,192 records. Console checks
keep both profiles, all 1,026 chunk lengths and the native variadic ABI. Its
adapter binds the current production panic-terminal hook to the existing
independent byte recorder. On Darwin x86, the controller adapts ELF section and
symbol directives to Mach-O; it keeps the original assembly instructions and
the shared variadic macro. The diagnostic fixture keeps both serial adapters
and all 2,003 hexadecimal fault records. Init preserves the independent syscall
recorder, both echo variants, all three ARM freestanding links and allocation
checks. Its C reference option changes only original register boundaries.

Qualification uses fresh ARM, x86 and ARM ASan/UBSan host executables, with
sanitizers also on the generated fixtures. Both the maintained and original C
init recorders pass; original C policy controls pass through the native reference
adapter. Guard tests preserve Unicode boundaries and each original allocator
set. Forced compiler failures verify seven disposable-owner retirements per
profile. Cold shell entrypoints run from outside the checkout.

The four current network fixture builds still fail under the selected compiler:
it introduces undeclared `memdup` calls for production stack records. The native
port retains the strict compiler flags and allocator guard. Network source
generation passes, and the complete failure path and owner retirement are
checked; no successful network fixture execution is claimed. This change adds
no kernel build, guest boot or physical hardware evidence.

The qualification compiler is an isolated V 0.5.2 `c6bb06f` build, with a private
stdlib declaration-header correction for its truncated RAND_MAX preprocessor
block. The shared compiler and checkout remain untouched. Qualification logs,
original Git controls, generated artifacts and receipts are under
`/tmp/vinix-native-policy-qualification-arm`,
`/tmp/vinix-native-policy-qualification-x86-complete` and
`/tmp/vinix-native-policy-qualification-san-complete`. Local receipts support
the checks; the maintained commands do not depend on those directories.

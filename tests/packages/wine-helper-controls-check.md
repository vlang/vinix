# Production-active Wine helper controls

The pinned V compiler omits `assert` checks under `-prod`. The source-closure,
resource-header, observed C-input, linker and host-image module tests now use
explicit panic conditions for successful observations and expected refusals.
Error propagation alone does not prove an expected refusal was observed.

`wine-helper-controls-check.v` copies the ten current implementation/test files
into an external private fixture and runs each helper in normal and production
manual-free builds. It also builds five separate production mutants, disabling
one real admission check in each private implementation copy. Each mutant must
compile successfully, exit unsuccessfully and report the explicit expected-
refusal failure. Compile failures or unrelated runtime errors do not count.
Tracked source files are never mutated; their hashes and the selected compiler
are rechecked afterward. The driver refuses line-leading `assert` checks in the
copied tests, existing output directories and changes to its embedded source.

```sh
v -backend c -prod -gc none -manualfree -cflags -fno-lto \
  -o /external/check tests/packages/wine-helper-controls-check.v
/external/check /absolute/selected/v /external/fresh-results \
  /original/native/build-guest/cc.log.argv.json
```

The last argument is optional and enables a fresh real static Clang/LLD replay
for both normal and production linker tests. The existing reproducer argument
is removed before invoking the compiler, preserving the original archive.
Real Clang/LLD host tools and real V-to-C generation are required by the driver.
The host-image suites poison parent VFLAGS, VMODULES, VEXE and loader injection
settings, and require altered recorded environments to refuse. Generated
binaries, C, logs, argv, source fixtures and raw observations stay outside Git.

The five mutations disable missing/changed V input rejection, missing/changed
resource-header input rejection, C trace control-byte rejection, unsupported
linker argument rejection and unknown/changed non-system host-image rejection.
Detection must happen at the explicit unit refusal condition in every case.

Earlier production module runs that relied on assertions are superseded for
those assertion checks. Their original evidence remains intact. The existing
44-case full-retainer matrix and 32 owned-receipt controls use explicit errors
and are unaffected. This change qualifies test enforcement; production
admission, kernel code, product defaults and roadmap 14 acceptance are unchanged.

The checkpoint is `/Users/alex/.cache/vwhelpercontrols-20261115-01`, based on
`be740f6d0`. All ten normal/production suites and five production safety mutants
pass in `run-01`, including real C compilation, static linker replay in both
modes and real V source generation under poisoned parent settings. Every mutant
compiles and then fails at its explicit expected-refusal check. The driver
rechecks all copied helper/test source hashes, its own source and the selected
compiler before publishing the result. Original selected compiler and real-link
input bundles remain independently required.

# Native host policy tests

Five commands now invoke V directly:

```sh
tests/hypervisor/host-test --state-dir /new/hypervisor-state [--cc clang]
tests/mounted-disk-policy/host [--state-dir /new/mounted-state]
tests/securelevel-boot/host [--state-dir /new/parser-state]
tests/securelevel-boot/dispatch [--state-dir /new/dispatch-state]
tests/securelevel-boot/attribute-faults [--state-dir /new/attribute-state]
```

The hypervisor state directory remains required. Other commands remove their
default scratch directory on success, failure and SIGINT. Explicit directories
must be fresh and retain source hashes, compiler commands, copied fixtures,
executables and logs. SIGINT returns 130 after retiring the directly owned child.
Compiler selection uses `V` and the repository's maintained native launcher.

The hypervisor runner retrieves the independent C guest at
`9f47270ee3c6754312bc09fc74d8f77e2cfe2229`, SHA256
`debabb14d5507298d1a03ba62141cce9523bc469b9a9740ced68d36e019f3ae0`.
It verifies all 15 original assertion diagnostics, generates the existing V
guest and ABI model, and compares exact stdout, empty stderr and exit status
for all 19 cases under ASan/UBSan. The original 30-second per-process deadline,
six libc remaps, strict compiler flags, five VM iterations and variadic assembly
entry remain intact. Both host architectures use the same original portable
ARM64 producer profile, then link actual native executables for their host.

Mounted-disk admission retains the existing two-phase V generator and original
metadata-preserving production copies. Its unchanged atomic C header now lives
in `hosttemplates/host.h`. The real production identity and policy modules run
under ASan/UBSan with the original 30-second deadline. This covers topology,
provenance, swap exclusivity, write/mount interleaving, cancellation, inventory
growth and securelevels.

Securelevel parser and attribute assertions remain byte-identical. The append
fixture still checks the generated production body for `memdup`, `malloc`,
`new_array` and `string__substr`; it does not execute an artificial dispatch
guest. Its native scanner preserves the original whole-line definition search
and brace counting, with bounded errors for missing or unterminated definitions.

Production ext2 gained transaction and read-only dependencies after the old
Python fixture was written. The fault fixture adds two model fields and narrow
non-journaled transaction stubs, retaining the exact production setter and
transfer-wrapper slices. Journal operations deliberately stop the model.
Two additional assertions verify read-only rejection, unchanged protection and
lock release. This suite does not establish journal failure or durability
behavior. The frozen original model matches byte for byte after removing only
the declared `read_only` and `journal` fields; the C header and append model
match their frozen literals exactly.

The shared native subprocess primitive drains both binary streams, preserves
host architecture preference and working directory, and kills/reaps on failed
communication, timeout or interrupt. Its deadline also applies after both output
streams close. Existing unbounded callers retain their blocking behavior.
Runtime exec failures return 1; they do not inherit argparse's status 2 merely
because the system reports ENOENT.

Qualification on 2026-10-11 passed ARM, Rosetta x86 and ARM ASan/UBSan controller
builds, all five host workflows on each profile, separately instrumented
production parser/attribute models on both architectures, three new source-guard
tests and the two existing capture/preference regression files on all profiles.
Each host profile also passes large binary pipes, nonzero/signal exits, native
working directories, exec errors, timeout before/after EOF, real SIGINT and
60 repeated FD/PID retirement cases. Twelve default-workspace failures,
CLI/fresh-directory guards and real controller interrupt cleanup pass on each
profile. Five cold fronts compile and run outside the checkout.

`check-host-suite.v CONTROLLER FRESH-STATE` reproduces the checks. Its
`--owners CONTROLLER FRESH-STATE` and `--templates` modes allow focused checks.
Evidence is retained under
`/Users/alex/.cache/vinix-python-zero-process-20261011`: `host-check-*-release`,
`host-owners-*-final`, `host-suite-units-*-qualified.log`,
`host-suite-capture-regression-*.log` and `host-cold-fronts.log`.
The final runtime exec-error normalization was followed by fresh controller
builds and all three focused owner qualifications. macOS leak sanitizer is
disabled; no LeakSanitizer claim is made.

This stage retires five Python files / **13,014 original bytes / 304 lines**.
No Python was run, production kernel source changed, assertion weakened,
Linguist override added or historical fixture hidden. This host qualification
adds no kernel build, guest boot, physical device or actual VMX-entry coverage.

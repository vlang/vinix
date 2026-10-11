# Native Apple and Wi-Fi command paths

Fourteen Python files (25,600 bytes and 573 lines in `e5461617`) are retired:
seven Wi-Fi frontends, the shared provider adapter, and the ANS, SPI and speaker
frontends/provider APIs. Shell entry points invoke V directly. The existing
fixture/module/provider generators are native V dependencies. No Python was
written or executed during this stage.

The seven fixture controllers now own argument parsing and work lifetime.
Default work is private `/tmp` storage with mode 0700, independent of `TMPDIR`;
explicit state must be fresh and remains available after failure. Empty path
options retain their current-directory meaning. CLI errors return 2, runtime
errors return 1, and interrupts return 130. A typed CLI error prevents an
`ENOENT` filesystem error from being mistaken for a usage error.

Commands drain both binary streams and retain actual caller environment bytes
and architecture preference. Signal checkpoints kill and reap the direct child
and close all owned pipes. The interrupt handler only stores an atomic flag;
each controller restores the previous handler and retires its private work.
`nm` and source text now use an explicit strict UTF-8/newline contract rather
than a Python locale codec. Frozen Git objects and fixture output remain raw
bytes. Provider copies retain the existing omission and metadata policies.

Module generation calls the native producer. Serial generation retains the
original compiler/link-flag filtering, PIC and warning exceptions. Native guest
execution calls `guesthost.guest` in the controller process so its supervisor
owns QEMU. Receipts record an executable native command with the same markers,
failure strings, networking policy and deadlines. `run-ctl-vm` uses the control
controller directly, deriving `STATE/guest` in V.

Qualification used V 0.5.2 `37c0ab3`, both actual Darwin SDK architectures and
ARM ASan/UBSan. Frozen import guards, allocation counts, marker scanners,
production modules and every independent fixture body are byte-identical to
`e5461617`. The original native module API and replacement CLI produce identical
protocol core C on all three host profiles. The compiler fallback was disabled.

Completed checks include 24 fresh entry-point builds, seven native unit tests on
all three profiles, original/V control and SDK-helper golden comparisons on
both host ABIs, strict control/helper objects and original/V static ELF builds
for both guest architectures, 63 default-owner failures, CLI/fresh-directory and
literal-path checks, and actual controller SIGINT/direct-child retirement on
all three profiles. Eleven shell entry points also compile and run their native
CLI from outside the checkout and retire their launcher directories.

Current limits remain visible as failures:

| Consumer | Current result |
| --- | --- |
| Wi-Fi protocol/platform | Independent fixtures emit undeclared `memdup`; strict compilation rejects them. |
| SPI keyboard/touchpad | Independent fixtures emit undeclared `memdup`; strict compilation rejects them. |
| Speakers | Independent fixture emits undeclared `memdup`; strict compilation rejects it. |
| ANS | The existing single-file provider copy omits accounting helpers from `status.v`; ARM generation rejects them. The x86 backend also rejects the retained ARM assembly. |
| Control guest, prepared ARM kernel | Original C and V complete all eleven scenarios and the terminal verdict. |
| Control guest, prepared x86 kernel | Original C and V reach the same failing `fclose` during bundle creation; both retain the 300-second missing-verdict timeout. |

The strict checks were not relaxed and no kernel or fixture source was changed.
There is no new physical Apple hardware result or successful protocol, SPI,
speaker or ANS guest claim. macOS ASan uses `detect_leaks=0`; these checks do not
claim LeakSanitizer coverage. Full-disk qualification failures were rerun after
retiring completed disposable ISO/firmware-variable copies from this task's
cache; their source objects, disk fixtures, manifests and logs were retained.

Evidence is under `/Users/alex/.cache/vinix-python-zero-process-20261011`:
`apple-runners-qualified` holds host goldens, immutable originals and producer
parity artifacts; `apple-runners-release` holds final binaries and ownership
checks. `apple-units-*-final.log`, `apple-cold-fronts.log`,
`apple-control-*-native`, `apple-control-*-guest-*` and
`apple-helpers-*-native` retain the remaining artifacts. Prepared kernel hashes:
ARM `8866c72f19cba5f95ff22070e193b25cbe0cf57ae89e306067b16a82dba7289f`;
x86 `38fb88ad76e81bb26f9d84267678cf98cd0ccc0aae10573b9b83ddd5ca0b3f0a`.

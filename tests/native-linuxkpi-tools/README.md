The LinuxKPI audit, fixture, golden-data and native host build commands run in
V. Public entrypoints live under `kernel/linuxkpi` and `tests/linuxkpi`; the
PCI configuration runner also uses this module. Select the compiler with `V`
or `VINIX_V_COMPILER`. No Python wrapper is required.

Examples:

```sh
kernel/linuxkpi/upstream verify
kernel/linuxkpi/audit --jobs 4
tests/linuxkpi/audit_generation_test
tests/linuxkpi/exchange_test
tests/linuxkpi/fixture-goldens
tests/linuxkpi/compile-native-host /tmp/linuxkpi-arm --arch aarch64
tests/linuxkpi/run_vm --kernel /path/to/kernel --state-dir /tmp/new-guest
tests/pci-config/run.sh --keep-dir /tmp/new-pci-evidence
```

`kpihost` expands the original Kbuild list, generates private adapters and
bounds, waits for every compiler job before scratch retirement, and publishes
the readiness report atomically. Its four generation regressions use the
verified pinned Linux import and unchanged C caller. The golden-data reader
parses literal C/V tables and fixed numeric expressions without evaluating
source code. It compares all original kstrtox, bool, token, PCI, QP and cache
tables, including the family data covering 3,240 QP indices. Atomic exchange keeps its 30-second
deadline, allocator guard and stack lifetime sanitizer controls.

The native host builder retains the original musl SDK selection, strict flags,
object ordering and 21 independent fixture groups. The host suite generates
its ABI directly and forwards the supplied compiler/source/nm environment.
The full host workload, seven sleep boundaries and standalone checks remain
available through `tests/linuxkpi/run.sh`. Compiler fallback is rejected.

The disposable VM uses the maintained native `agxhost` policy and owns its
child until reaping and log closure finish. Preparation hooks are available
for native tests; default callers use the actual compiler, archive and ISO
builder. `test-vm.v` exercises thirteen real child-process cases, including
failure, panic, timeout, large output, SIGINT and SIGTERM, with exact descriptor
and PID retirement checks. These controlled tests build no kernel or image.

Qualification recorded thirty cold program/profile builds on ARM, x86 and
ASan/UBSan. Each profile passes the VM cases, both architecture recipe controls,
all four actual audit-generation regressions, golden comparisons, actual atomic
exchange and unchanged C/V PCI models under GNU99/GNU11 sanitizers. A separate
suite control verifies the supplied environment, actual native ABI generation
and immediate stop on compiler failure. Public shell syntax, help, invalid
arguments and real V bootstraps pass. Actual CPU-mask and SMP prerequisites
also pass through the translated callers.

The real Kbuild audit reports 5 of 269 translation units passing on the recorded
checkout; this is orchestration evidence, not full i915 readiness. A real ARM
musl host build stops at an existing `memdup` emitted for `PrintRecord` in the
production logging worker. Strict compilation and allocator guards remain;
controlled recipe tests do not establish a successful native host ELF or
runtime workload. No Python or Vinix guest was executed for this batch.

The thirteen retired originals total 54,042 bytes and 1,127 lines at
`3678edd591db0173eb139f44d671a54a4f736887`. The concurrently edited
`tests/linuxkpi/compile-v-fixture.py` remains and receives no retirement credit.
Machine-local inputs, logs, binaries, failures and review receipts are retained
under `~/.cache/vinix-linuxkpi-tools-native-20261012`.

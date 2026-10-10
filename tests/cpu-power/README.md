# CPU idle states and frequency control

Tests for `kernel/cpuidle` and `kernel/cpufreq`. There are two halves, and
neither needs Python.

## On the host: the decisions

    sh tests/cpu-power/run.sh

compiles the kernel's own decision code for this machine and runs it under
`v test`. `cpuidle/` and `cpufreq/` here are one V module each; the sources in
them are links into `kernel/`, under names without an architecture suffix so
that the host compiler takes them:

| here | kernel file | what is tested |
| --- | --- | --- |
| `cpuidle/govern.v` | `kernel/cpuidle/govern.v` | choice of a state by residency and latency limit, disabled states, the typical-interval prediction, `above`/`below`, counter arithmetic |
| `cpuidle/mwait_table.v` | `kernel/cpuidle/mwait_table_amd64.v` | which states are offered for which CPUID: intel_idle's tables, the generic Intel states, AMD, no ARAT, QEMU's emulated MWAIT |
| `cpufreq/policy.v` | `kernel/cpufreq/policy.v` | governors, the user's range, the thermal limit, profiles, the ondemand target |
| `cpufreq/registers.v` | `kernel/cpufreq/registers_amd64.v` | HWP capabilities, request encoding and decoding, SpeedStep ratios and IA32_PERF_CTL, AMD CPPC, APERF/MPERF |
| `cpufreq/apple_dvfs.v` | `kernel/cpufreq/apple_dvfs_arm64.v` | the Apple cluster DVFS sequence against a model of its register block: BUSY, the timeout, the write, the read-back |

These files import nothing from the kernel, which is what lets them be tested
this way; anything that touches a register or the scheduler is elsewhere.

## In a guest: the kernel

`guest.c` is a C program to boot as `/sbin/init`. It

- runs timed sleeps and pairs of threads waking each other through pipes,
  first on idle CPUs and then beside threads of arithmetic whose answer is
  known: a wake-up the idle path lost stops it for good;
- reads `/sys/devices/system/cpu/cpuidle` and every CPU's states, checks that
  each CPU's `usage` and `time` grow across two idle seconds and that the time
  in its states is within 20 % of the idle time `/proc/stat` reports, and that
  a state switched off through `disable` is no longer entered;
- reads every CPU's `cpufreq` files and checks them against each other and
  against `/proc/cpuinfo`; with the driver `none` it checks that every write is
  refused and changes nothing, and with a driver that governors, ranges and
  profiles are taken and put into effect on every CPU;
- runs the workload again, prints `CPUTEST DONE failures=N` and powers off.

Every line it prints starts with `CPUTEST`, and a failed check has `FAIL` in
it. Build it statically for the guest (`-pthread`, and
`-DCONSOLE='"/dev/com1"'` on x86-64, where the console is the serial port),
put it in an initramfs as `/sbin/init`, and boot with the serial port
captured; a run that does not reach `CPUTEST DONE` within a minute has hung.

Kernel command lines worth a run each:

| option | effect |
| --- | --- |
| (none) | x86-64: `halt` under QEMU's emulation, whatever `-cpu`; arm64: `wfi` |
| `vinix.cpuidle=mwait` | x86-64 with `-cpu max`: the MWAIT driver, in its `sti; mwait` form. QEMU's MWAIT does not wait on a machine with several CPUs, so `usage` grows by hundreds of thousands a second; that is the emulator, and why it is not the default |
| `vinix.cpuidle=halt` | x86-64: HLT even where MWAIT would be used |
| `vinix.cpuidle=off` | no idle driver: the scheduler's original loop |
| `vinix.max_cstate=N` | x86-64: offer only the first N idle states |
| `vinix.cpufreq=simulate` | a frequency driver with memory in place of registers, so that the policies, the worker and each driver's own path run in a guest: SpeedStep's on x86-64, Apple's cluster DVFS on arm64 |
| `vinix.cpufreq=off` | x86-64: no frequency driver even where the processor has one |

Two more are for hardware and do nothing in a guest: `vinix.apple_idle=wfi`
(WFI in the idle loop of a physical Apple machine, which otherwise polls) and
`vinix.apple_cpufreq=1` (Apple's cluster DVFS). Both are off by default and
neither has been run on a machine; `kernel/cpuidle/driver_arm64.v` and
`kernel/cpufreq/driver_arm64.v` say why.

## What no test here reaches

No virtual machine available here has HWP, Enhanced SpeedStep, CPPC or Apple's
DVFS registers, or an MWAIT that honours its interrupt-break extension, and
none shows what an idle state does to power. So these are tested as
arithmetic on the host, or through the simulated driver up to the register
write, and have never run against hardware:

- the masked MWAIT entry (`cli; monitor; mwait` with ECX[0] = 1; `sti`) and
  every state deeper than C1;
- the reads and writes of the HWP, SpeedStep, CPPC, APERF and MPERF registers;
- Apple's DVFS registers, and WFI on Apple hardware (`vinix.apple_idle=wfi`).

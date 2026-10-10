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

The guest half is two scenarios of `tests/hardware-platform`, written in V
like the rest of that suite (`guest/cpu_power.v`):

    tests/hardware-platform/run --arch x86_64 --kernel build-amd64-kernel/bin/vinix --scenario cpu-power --scenario cpu-power-simulated
    tests/hardware-platform/run --arch aarch64 --kernel kernel/bin/vinix --scenario cpu-power --scenario cpu-power-simulated

`cpu-power`

- reads `/sys/devices/system/cpu/cpuidle` and every CPU's states, and checks
  that each CPU's `usage` and `time` grow across an idle second, that the
  busiest CPU still spent at least half of it waiting, and that a state
  switched off through `disable` is no longer entered until it is switched on
  again;
- runs 1,600 timed sleeps on four threads and 2,000 pipe round trips between
  two processes beside two threads of arithmetic whose answer is known: a
  wake-up the idle path lost stops one of them for good, and the scenario
  ends by its deadline instead of passing;
- checks that a machine with nothing to set says its frequency driver is
  `none` and refuses a governor and a profile.

`cpu-power-simulated` boots with `vinix.cpufreq=simulate` and checks that
`performance`, `powersave` and a profile each reach every CPU.

Recorded on QEMU 11.1.1 (TCG for x86-64, HVF for AArch64):

```
PASS x86_64 cpu-power (12.4s)
  idle: driver halt, 1 state(s) on 2 CPUs; the busiest CPU waited 937 ms of a second
  wake-ups: 1600 timed sleeps, 2000 pipe round trips and two computing threads done in 2728 ms
PASS x86_64 cpu-power-simulated (7.4s)
  simulated driver: 2 CPUs between 800000 and 3000000 kHz followed performance, powersave and the profile
PASS aarch64 cpu-power (10.0s)
  idle: driver wfi, 1 state(s) on 4 CPUs; the busiest CPU waited 973 ms of a second
  wake-ups: 1600 timed sleeps, 2000 pipe round trips and two computing threads done in 1111 ms
PASS aarch64 cpu-power-simulated (6.9s)
  simulated driver: 4 CPUs between 600000 and 2088000 kHz followed performance, powersave and the profile
```

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

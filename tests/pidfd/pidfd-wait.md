# Waiting through a process descriptor

`tests/linux-compat/pidfdwaitfixture/core.v` checks `waitid(P_PIDFD)` on native
AArch64 and x86-64 Linux syscall tables. The same static musl executable runs
under the Linux reference wrapper. The suite has 20 named cases and 117 checked
wait results. It runs as root/PID 1 and bounds execution with a 120-second alarm.

The cases cover a live child, `O_NONBLOCK` versus explicit `WNOHANG`, exact exit
siginfo, repeated `WNOWAIT`, consumption through a duplicate descriptor and
`ECHILD` after reap. Two children exit separately to check identity selection.
Negative descriptors (including `INT_MIN`), missing and wrong-type descriptors,
nonchildren, option validation and low-32-bit syscall argument conversion are
checked independently. Seven raw argument forms include poisoned upper words;
the eighth form uses musl's `waitid` wrapper.

Copyout cases check `EFAULT` precedence on error paths, `WNOWAIT` claim release,
consumption despite a failed result copy, null siginfo and rusage-before-siginfo
ordering. Eight rounds close a shared descriptor after another thread has
blocked in a pidfd wait. Eight more race that waiter against a sibling thread's
ordinary `wait4`: exactly one must receive the child and the other must return
`ECHILD`. Each action starts only after `/proc/self/task/<tid>/status` reports the
worker sleeping; unavailable status fails setup. A separate live/exit `wait4`
case checks the existing interface. These are bounded correctness cases; they
do not measure allocation retention or guarantee a particular race winner.

Build the host tools with the repository V compiler:

```sh
v -path 'tests/native-guest-tools|tests/linuxkpi|build-support|@vlib|@vmodules' \
  -o /external/pidfdwait-build tests/linux-compat/pidfdwait-build.v
v -o /external/pidfdwait-check tests/linux-compat/pidfdwait-check.v
v -path 'tests/native-guest-tools|tests/linuxkpi|build-support|@vlib|@vmodules' \
  -o /external/pidfdwait-reference tests/linux-compat/pidfdwait-reference.v
/external/pidfdwait-check --self-test
/external/pidfdwait-build /absolute/path/to/v /absolute/arm64/musl/sysroot \
  /external/fresh-build
```

The compile-only helper freezes fixture/controller sources, generated C and
objects, records static ELF checks, and retains the cross compiler subtools,
consumed headers and traced link inputs with SHA-256 inventories. Its compiler
binary pin does not claim a recursive rebuild closure for V itself. Results
remain outside Git. The build directory must be fresh.

The native controller accepts `--cases pidfdwait`; build its usual host runner
and use a separately built kernel:

```sh
tests/linux-compat/run --arch aarch64 --kernel-dir /external/kernel-tree \
  --state-dir /external/fresh-native --cases pidfdwait --timeout 180
/external/pidfdwait-check --mode native \
  --log /external/fresh-native/pidfdwait/serial.log
```

To compare the exact same retained executable against Vinix and Linux, use the
generic V runner's prebuilt mode:

```sh
tests/kernel-gaps/run-native --arch aarch64 --kernel-dir /external/kernel-tree \
  --state-dir /external/fresh-native-prebuilt \
  --prebuilt-init /external/fresh-build/aarch64/init \
  --expect 'LINUX PIDFDWAIT: PASS' --fail 'LINUX PIDFDWAIT DETAIL:' \
  --fail 'LINUX PIDFDWAIT FAIL:' --no-network --timeout 180
/external/pidfdwait-check --mode native \
  --log /external/fresh-native-prebuilt/serial.log
```

Use that retained static executable for a Linux reference boot:

```sh
/external/pidfdwait-reference --arch aarch64 --kernel /absolute/Linux/Image \
  --init /external/fresh-build/aarch64/init --state-dir /external/fresh-reference
```

Repeat with `x86_64` and a matching Linux kernel. The reference runner snapshots
its kernel, probe, wrapper, checker and raw serial, then invokes the retained
checker. The checker requires every exact case count, rejects diagnostic or
failure markers anywhere in the log (including after PASS), and has 30 negative
controls. Compilation and synthetic checker controls alone do not establish
native or Linux runtime success; retain complete boot bundles for those claims.

The 2026-10-26 compile validation used baseline
`ecbd3964aff243304e16df45271c7de8dee4d2da` plus the fixture source SHA
`014f7a34bde47bb0297744cfff8fcddd9d7d54110c1382ffac03a89d3c9d2d20`.
Both static builds passed, and an independent full inventory recheck passed.
The complete bundle is under
`/Users/alex/.local/state/vinix/android/pidfd-wait-fixture-build-2026-10-26-r2`,
whose `sha256.json` SHA is
`a62b9744831e92dc571bf48578ccde021b7cce4f54d0a36f42db7ef9c9c37d31`.
The checker/reference host tools compiled and the 30 negative controls passed
in sibling `pidfd-wait-host-tools-2026-10-26-r2` (inventory SHA
`bf956bd039b0932a97415d41c5a61ce708e31026eb3b37120de2e8ed46d6f400`).
The same retained AArch64 executable passed all 20 cases and 117 checks on the
fixed Vinix kernel in `pidfd-wait-guest-2026-10-26-r1/serial.log`; the semantic
checker also passed. That boot used
`pidfd-wait-kernel-build-2026-10-26-r1/kernel-aarch64-r2/source/kernel`.
The separate kernel validation report records complete boot evidence and any
later x86-64 or Linux reference verdicts. This checkpoint makes no Linux
reference or Google account sign-in success claim.

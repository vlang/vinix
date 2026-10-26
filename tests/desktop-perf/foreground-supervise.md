# Foreground x86 performance supervisor

`foreground-supervise.v` owns the maintained `run-x86 run STATE SHA256`
adapter. It requires a fresh prepared runtime with all six scenarios
(`ops,churn,cache,idle,apps,drag`), the foreground `mon:stdio` QEMU mux,
and an adapter executable matching the prepared input digest.

The sourcecommand owner reserves the child leader with WNOWAIT, uses a
private process group, and performs the sole raw i32 waitpid reap. One
combined pipe preserves stdout/stderr ordering and enforces the output
limit before retaining each chunk. Refusal retains the accepted log prefix,
allows 30 seconds for TERM cleanup, then retires the group. Receipts require
group absence and ECHILD after retirement. A refusal records the child exit
status as unavailable rather than inventing it.

The adapter owns QEMU in a separate session. Success additionally requires
the adapter's zero-status receipt, its exact verified input map (allowing
only the runtime disk digest to change), and the exact guest completion
line. Failure does not prove cleanup of arbitrary escaped descendants.

The outer deadline must exceed the adapter deadline by 60 seconds and is
limited to two hours. Actual df and du observations run every five seconds,
with three-second bounded probes: admission needs 2 GiB free, continued
execution needs 1 GiB, and declared nonoverlapping roots plus supervisor
state may occupy at most 512 MiB. The prepared runtime must be covered by
a charged root. These are sampled bounds, not a filesystem quota.

Build with a complete selected V installation and private temporary/module
directories; preserve coherent V, VEXE and caller compiler environment
markers. For example, from the checkout:

```sh
v -enable-globals -nocache -keepc -cc /absolute/clang \
  -path '@vlib|@vmodules|tools|tests/desktop-perf|tests/hardware-platform|tests/linuxkpi' \
  -o /external/foreground-supervise tests/desktop-perf/foreground-supervise.v
```

The profile is an explicit reviewed document:

```json
{
  "adapter": "/external/run-x86",
  "prepared_state": "/external/attempt/prepared",
  "prepared_sha256": "REVIEWED_SHA256",
  "directory": "/absolute/source-checkout",
  "timeout_seconds": 3660,
  "log_limit_bytes": 33554432,
  "charged_roots": ["/external/attempt", "/absolute/source-worktree"],
  "input_roots": ["/absolute/source-checkout/tests/desktop-perf", "/absolute/source-checkout/tools", "/external/complete-v-root"]
}
```

```sh
/external/foreground-supervise run /external/new-supervisor-state /external/profile.json
```

Input inventories bind modes, literal symlinks, resolved referents and file
digests before and after execution. The wrapper derives the adapter argv
from the validated profile. It does not execute an arbitrary profile command.
Keep the supervisor state outside all declared input trees.

`selfcheck NEW-STATE COMPLETE-V` exercises real spawn/reap behavior for
success, nonzero exit, timeout, output refusal, SIGTERM and a same-group
descendant that keeps the pipe open. It also checks ten prepared-profile and
completion-receipt cases without executing an adapter or QEMU. Each process
case checks the log bound and retirement; the nonzero case checks exact
stderr retention. The descendant case must time out because its inherited
pipe prevents EOF after the leader exits.

`qualify NEW-STATE COMPLETE-V` rebuilds normal and production binaries and
runs all sixteen controls on each. It clears inherited tool selection,
uses private temp/module/cache directories and `-nocache`, selects the
inventoried absolute clang with an explicit SDKROOT, and charges the whole
qualification state throughout. It retains source copies, generated C,
binaries, argv, environments, logs, budgets and receipts. Its complete V
root and recorded host compiler/SDK metadata maps must stay unchanged.
The installed loader and SDK dependency closure are not claimed hermetic.

Host qualification results and checksums are recorded in
`foreground-supervise-report.md`. No guest performance measurement is
implied by the host controls.

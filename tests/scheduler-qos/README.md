# Scheduler scalability and QoS qualification

Build both architectures in isolated worktrees and run:

```sh
V=/path/to/v python3 tests/scheduler-qos/policy.py
V=/path/to/v python3 tests/scheduler-preemption/policy.py
V=/path/to/v tests/kernel-resources/run-host.sh
python3 tests/scheduler-qos/run.py --arch aarch64 --kernel-dir /path/to/arm/kernel
python3 tests/scheduler-qos/run.py --arch x86_64 --kernel-dir /path/to/x86/kernel
```

The guest requires four CPUs and defaults to 8 GiB RAM. It checks utilization
hints, the legacy sched_attr ABI, policy preservation, fork/exec timer-slack
inheritance and nanosleeps that never return early. Private PI cases cover
errors, timeout, signal interruption, owner death and surviving CLONE_VM waiters
across owner exec or forced sibling retirement. Plain and transitive inversion
put a low-priority owner, a busy medium-priority competitor and a high-priority
waiter on CPU 1. Handoff uses live donation ranks.

Concurrent MADV_PAGEOUT competes with 64 contended lock/unlock transactions on
an anonymous page. The test accepts bounded EAGAIN retries, and rejects EFAULT
for the live writable mapping. PI/thread churn warms up, then checks every slab
size class after two equal cohorts and a grace period. Finally, 20 processes
publish 30 runnable workers each before releasing their barrier: 600 workers
complete 24000 eventfd create/close operations while yielding and joining.
`--define SCHED_QOS_SMALL=1` runs the ABI, inheritance and retirement cases
without pageout/churn/600-worker stress.

The host policy test extracts production functions. It covers synthetic mixed
capacities, minimum/capped placement, mandatory affinity, busy-core fallback,
offline/unknown cores, transitive donation, cycle rejection, policy refresh,
retargeting, pin balance, exact withdrawal and repeated donations. Production
timer functions check coalescing bounds, rearm/list ownership, busy-lock retry,
empty idle ceilings and distant absolute deadlines. Mock locks/atomics qualify
decisions; native guests qualify actual publication, interrupts and lifetimes.

Also run process-smp, kernel-job-control, scheduler-preemption, kernel-resources,
resource-groups, paging pressure and POSIX timer guests on both architectures;
then desktop-perf ops/churn/cache and idle/apps/drag on ARM. Compile with
-fstack-usage and inspect generated C for queue, donation, PI and deadline scan
allocations. Run tests/kernel-allocs/run.sh and compare inherited allowance
failures without expanding the allowlist.

Implementation and supported limits are in
[docs/scheduler-qos.md](../../docs/scheduler-qos.md). This test is a correctness
and bounded-retention fixture. It does not establish linear multicore scaling,
hard realtime latency, physical heterogeneous placement or energy savings.

## Recorded qualification

Both builds use `PROD=true ALLOC_TRACK=1` in isolated worktrees. The ARM guest
uses HVF and the x86 guest uses TCG; their timings are not comparable.

| Check | ARM | x86 |
| --- | --- | --- |
| 600 runnable workers / 24000 create-close operations | Pass | Pass |
| Plain and transitive PI with an independent medium-priority competitor | Pass | Pass |
| Signal/timeout withdrawal, owner death, exec and forced retirement | Pass | Pass |
| 64 contended transactions during bounded anonymous pageout | Pass | Pass |
| PI churn after warmup, two 16-iteration cohorts | First cohort -1/+1 objects, second all zero | Both cohorts all zero |
| Legacy/utilization ABI, hint/slack inheritance, no early sleep | Pass | Pass |
| Process SMP, job control, detached churn and scheduler preemption | Pass | Pass |
| Resource exhaustion, CPU quota, paging pressure and POSIX timers | Pass | Pass |

Host production-function tests and private-page/pager tests pass, including
corrupt compressed backing returning EIO and disk ENOMEM surviving refault.
Generated C scans found no implicit heap allocation in queue, donation, PI
retry/retirement or deadline selection. With `-fstack-usage`, the largest
individual x86 kernel frame is 26872 bytes versus the guarded 256 KiB task
stack; ARM's largest frame is 33008 bytes with its unchanged 64 KiB task stack.
Individual frames do not establish a bound on every possible call chain.

ARM desktop-perf ops/churn/cache and idle/apps/drag complete. The preceding
baseline and this build both retain 208 bytes per mkdir and about 6 bytes per
pipe operation in that harness. General 300-program churn retains 32–48 KiB,
with a similar live-object profile to the preceding baseline. These inherited
measurements remain open under the separate retention roadmap item. The
allocation allowance audit exits nonzero on exactly the same 170 groups as the
baseline; no group or allowance was added. This qualification does not claim a
clean global allocation audit or universally flat desktop retention.

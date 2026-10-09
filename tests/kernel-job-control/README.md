# Process stop and continuation regression

The standalone Linux guest runs without a desktop and exercises actual process
and thread execution on four QEMU CPUs. Build the kernel in an isolated worktree
and supply the checkout containing the prepared AArch64 userland and boot files:

```sh
python3 tests/kernel-job-control/run.py --repo /path/to/vinix \
  --kernel /path/to/worktree/kernel --smp 4 --log /tmp/job-control.log
```

Checks cover:

- Four spinning siblings stop before a stopped wait status becomes observable.
- Blocked SIGCONT resumes a job and remains pending for its caught handler;
  ordinary pending handlers wait until continuation, and SIGKILL terminates
  all stopped siblings.
- Ignored/caught SIGTSTP, default catchable stops in orphaned/non-orphaned groups,
  uncatchable SIGSTOP, and SA_NOCLDSTOP notifications.
- wait4/waitid selection of stopped, continued and exited states, WNOWAIT,
  failed status copy retry, and two-process group-directed signals.
- Parent exit sends HUP followed by CONT to 40 newly orphaned stopped groups;
  adoption by an external subreaper in the same session keeps them stopped.
- A stopped SysV message receiver resumes its original receive. A caught
  ordinary handler still gets the message-queue ABI's non-restarting EINTR.
- An exit beyond the first 32 children wakes a blocked parent, and more than
  32 waiting siblings compete safely for one exit (one success, all other
  waiters get ECHILD). ARM uses 70 waiters; x86_64 uses 48 because its two
  2 MiB kernel stacks per thread must fit within the 256 MiB creator ceiling.
- Thread clone/exit racing group stop and repeated process/thread teardown.
- Two batches of 30 processes race creation of live detached CPU-loop threads against external
  SIGKILL and a sibling's exit_group. ARM uses 64 workers and x86_64 uses 48.
  After both the process retirement and reader grace periods,
  every slab class is compared with a no-work diagnostics control and physical
  page retention must stay bounded. An ALLOC_TRACK kernel prints surviving
  call chains as `PERF-SITE teardown` lines.
- Blocking child waits survive a group stop or caught SA_RESTART handler;
  a caught handler without SA_RESTART produces EINTR.
- Two batches of 200 stop/continue pairs report all slab size-class deltas;
  repeated retained allocation growth fails the guest. The small allowance
  of two objects per sample covers the existing /proc measurement path.

The normal guest must finish with `JOB-CHECK DONE failures=0`. Both architectures
can use the disposable native runner:

```sh
python3 tests/process-smp/run.py --arch aarch64 --kernel-dir /work/arm/kernel \
  --source tests/kernel-job-control/check.c --expect 'JOB-CHECK DONE failures=0' \
  --state-dir /tmp/jobs-arm
python3 tests/process-smp/run.py --arch x86_64 --kernel-dir /work/x86/kernel \
  --source tests/kernel-job-control/check.c --expect 'JOB-CHECK DONE failures=0' \
  --state-dir /tmp/jobs-x86
```

That runner uses four CPUs and 4096 MiB by default. Add
`--define JOB_TEARDOWN_ONLY=1 --define JOB_DETACHED_CHURN=1` to run the returning
detached-thread regression alone. The older ARM runner's `--fork-only`
reduces execution to the 40-child blocking-wait regression for baseline
comparisons. Terminal access enforcement and session/group mutation rules are
covered by the separate combined terminal workstream; this core regression
does not claim those checks.

`--teardown-only` runs only the measured clone/teardown regression;
`--cycles-only` runs the 400 stop/continue pairs. The teardown measurement found
discarded process thread-list buffers and a promoted pipe result array. With
those fixed and the shared I/O scratch-buffer fix, repeated allocation groups
disappeared from ALLOC_TRACK output (500 retained allocations before, 27 after).
The remaining class-48 increase of three objects per sample matched the
no-work `/proc` diagnostics control. Other class deltas stayed within two
objects per sample. The final full ARM guest, including the shared ppoll scratch
fix, returned all physical pages in both batches (0 KiB retained).

`--detached-churn` replaces the live workers with repeatedly returning and
detaching threads. The SMP qualification found SIGKILL clearing musl's shared
thread-list lock before process teardown was claimed. A child not yet linked
by its creator could enter pthread exit and fault on its null list link,
reporting SIGSEGV instead of SIGKILL. Fatal/group exit now claims teardown and
retires siblings before clearing that lock; clone publication also cancels
children created during an exit/exec transition. ARM cleanup drains the
scheduler handoff before classifying or permanently stopping a victim.

Use `--define JOB_TEARDOWN_PROCESSES=60 --define JOB_TEARDOWN_BATCHES=6` with
the native runner's detached command for the extended acceptance run: 60 warmup
children and six measured batches of 60, preserving every expected wait status
and the 512 KiB physical-retention limit. Expected `EAGAIN`/`ENOMEM` admission
failures receive bounded retries while teardown continues racing; unexpected
errors or retry exhaustion still fail, and the guest reports the retry count.
A sample waits for a quiet half-second
after both grace periods; it fails if reclamation does not settle within ten
seconds. This prevents measuring an active stack reaper halfway through its
SMP page-table shootdowns.

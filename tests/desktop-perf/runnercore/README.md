The desktop performance runner's post-argument validation, setup and serial
supervision policy is native V. `runner-query.v` uses `_runner_native.py` for
stdlib operations and the shared owned host-controller transport. The public
Python signatures, documentation and argparse construction are retained;
`--help` still works without a V compiler. Native report processing is reused
without additional migration credit.

V validates prepared dictionary sizes and little-endian headers, selects the
sampler compiler/sysroot and exact linker arguments, validates and stages the
measurement plan, builds its configuration, selects the immutable module ISO,
assembles QEMU environment/argv, and handles deadlines, queued EOF, input and
screenshot markers, shutdown sequencing and report status.

The original `Console` thread continuously drains the PTY while the main
controller handles QMP. Pointer movement, QMP transport, PTY/process primitives,
argparse and the temporary VM context manager remain Python. The parent retains
manager and entered value separately and forwards the original exception to
`__exit__`, preserving suppression, active exception context and ignored return
values on successful exit. Dictionary validation also preserves the exception
context of argparse's error.

The private query process has a separate session, so a terminal group interrupt
reaches the original caller and its cleanup before the controller retires.
Compiler installation retains its original session. Captured private waitpid,
monotonic and temporary-directory primitives prevent guest fixture mocks from
controlling the host controller. Its retirement bound stays five seconds;
SIGINT is masked during retirement and the caller's prior handler is restored.

Normal serial shutdown preserves stop, reader join(2), close, join(1), snapshot
and log publication order and original error precedence. Unexpected controller
termination has a parent ownership fallback: the guest PID/master are registered
before Console construction; completed stop/close phases are tracked, and the
parent stops/reaps and drains/closes the guest before retiring VM images.
Terminal native replies retain the original error-phase behavior. Remaining
context owners are retired in reverse order even if an inner exit raises.

Qualification uses frozen source `51f8b95eb49e22ebbd9714144239ea5441a17a32`,
V 0.5.2 `6d549c2f095d5e3e97963e55a2ebf1dc2810db46`, actual ARM64/Rosetta
x86_64 hosts and an ARM ASan/UBSan controller. Each profile compares 80 complete
original/native dictionary, manager, compiler and main workflows, ten real
controller/stream/guest retirement controls, exact descriptor equality over
100 dictionary requests, and two actual group-interrupt pairs while blocked
on a serial queue or UNIX QMP. The 12 original runner fixtures stay unchanged.
Both hosts also check 13 public metadata contracts, the unchanged parser AST,
six CLI pairs and cold private installation under the original guest mocks.

Actual ARM QEMU checks use isolated source and copied, hashed prepared kernel
and desktop inputs. The frozen and native runners pass wakeup and desktop-idle
measurements with the same 15-second settling and five-second sampling plan.
Two earlier native one-second attempts completed the guest but correctly failed
because concurrent kernel diagnostics split a metric line; their failed logs
remain recorded and report assertions were not changed. A native pointer sweep
also passes with an actual QMP screendump while the independent reader drains
serial output. This host controller port does not claim a fresh kernel build, physical-device operation or new
manual-free kernel lifetime validation. Evidence is machine-local under
`~/.cache/vinix-python-to-v/desktop-perf-runner-20261008/`.

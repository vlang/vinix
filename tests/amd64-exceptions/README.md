# AMD64 user exception stack regression

`exceptionfixture/core_amd64.v` runs as PID 1 in an isolated QEMU guest. It faults 48 children while
file, pipe and UNIX socket descriptors remain open, then checks signal status
and socket EOF. Two threads also raise 256 trap/illegal-instruction exceptions;
their returning signal handlers block on a pipe while a peer releases them.
Run with one CPU to force blocking context switches and four CPUs to exercise
concurrent faults.

Build the x86_64 kernel, then run the fixture with a fresh build and guest
directory for each CPU configuration:

```sh
VINIX_V_COMPILER=/path/to/v CC_AMD64=x86_64-linux-musl-gcc \
  python3 tests/amd64-exceptions/run.py --state-dir /tmp/exceptions-build-1 \
  --kernel-dir kernel --guest-state-dir /tmp/exceptions-guest-1 --cpus 1
VINIX_V_COMPILER=/path/to/v CC_AMD64=x86_64-linux-musl-gcc \
  python3 tests/amd64-exceptions/run.py --state-dir /tmp/exceptions-build-4 \
  --kernel-dir kernel --guest-state-dir /tmp/exceptions-guest-4 --cpus 4
```

The runner compiles a static musl executable with strict warnings and checks
the fixture object for implicit allocator imports. It boots q35 with TCG,
`max`, 1 GiB of memory, and the selected CPU count. The default outer budget is
900 seconds; the workload has no internal deadline. `VINIX_OVMF_CODE` can
select the UEFI firmware. `--original-reference` builds an immutable C control
from a supplied file, and `--prebuilt-init` runs an already built executable.

Success ends with `EXCEPTION TEST: PASS`. PID 1 then waits forever; the runner
stops its QEMU instance after every required marker. It records hashes of the
kernel, executable, ISO and firmware beside the serial log. The test creates files on the initramfs tmpfs and
requires no data disk. It covers descriptor teardown and blocking handlers;
it does not exercise disk-backed writeback on fatal exit.

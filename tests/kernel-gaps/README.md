# Isolated kernel guest tests

`run.py` compiles a static C program as PID 1, boots the requested kernel in
QEMU, and requires every supplied success marker. A panic, failure marker,
nonzero runner exit, or timeout without all markers fails the run. The runner
waits two seconds after success to catch late failures, then stops QEMU if the
guest deliberately stays alive. The serial log and image artifacts are retained.

Build the kernel in a separate worktree first. Do not build two architectures
into the same `kernel/obj` directory concurrently.

```sh
python3 tests/kernel-gaps/run.py \
  --source tests/my-feature/test.c --arch aarch64 \
  --kernel-dir /path/to/worktree/kernel --expect 'MY FEATURE: PASS'
```

Use `--arch x86_64` for the second architecture. ARM64 needs the musl sysroot
created by `build-userland-aarch64.sh` (or `VINIX_AARCH64_SYSROOT`); x86-64 needs
`x86_64-linux-musl-gcc`. Both need QEMU and the repository's boot-image tooling.
The runner links a small constructor that redirects x86-64 test output to
`/dev/com1`; ARM64 already writes guest console output to the captured port.
`--state-dir` chooses an artifact directory and `--timeout` sets the boot limit
in seconds. Repeat `--expect` for independent verdicts and `--fail` for
test-specific failures. Never reuse a success marker printed before tests run.
Use `--no-network` for allocation measurements so DHCP setup cannot change the
heap during a measurement. Networking remains enabled for ordinary test boots.

Host checks for the runner's failure handling:

```sh
python3 tests/kernel-gaps/test_runner.py
```

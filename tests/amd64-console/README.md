# amd64 console guest regression

Build the x86_64 kernel, then run the independent V fixture with the native
musl compiler and an unused guest state directory:

```sh
CC_AMD64=x86_64-linux-musl-gcc python3 tests/amd64-console/run.py \
  --kernel-dir /path/to/worktree/kernel --state-dir /path/to/new/guest
```

The init forks a worker, checks zero-length and nonblocking reads from
`/dev/console`, and requires both the console verdict and `TEST RESULT: PASS`.
It reports original assertion line numbers and expressions on failure, then
sleeps as PID1 after collecting the worker. The harness captures COM1 and stops
its own VM; its timeout detects a crash or blocked syscall. This syscall fixture
must run in a Vinix guest.

The original 57-line C fixture is recoverable at commit
`33be42d72dba174bf643ab5be7fc57ab53d974a6:tests/amd64-console/test.c`.
All ten original checks and failure tags remain in `guestfixture/core.v`.

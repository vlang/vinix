# Shared stream I/O regression

The guest forks eight readers of one pipe, socket and PTY open description,
then supplies their input from the parent. Four virtual CPUs make a spinlock
held over a blocked stream read starve the producer deterministically. The
guest also fills a pipe using eight writers and checks that regular files
still serialize their shared offset. It tests dup/fork descriptions, stream
short reads, and ESPIPE for positioned stream I/O.

Run `python3 tests/shared-streams/run.py` for ARM or add `--arch=amd64`.
The runner accepts the same isolated-kernel and cached-runner environment
variables as `tests/stack-policy/run.py`.

The independent workload lives in `streamfixture/core.v`; its narrow ABI header
imports the actual native libc and Linux terminal layouts. The runner generates
and compiles V for the selected architecture. Original reader/writer counts,
transfer sizes, shared-offset checks and the 300-second deadline are retained.

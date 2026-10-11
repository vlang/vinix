# Native NUMA guest controller

`run_vm` and `run.sh` compile and run V directly through
[`systemhost`](../native-system-tools/systemhost/numa.v). The unchanged C guest
and its six feature markers remain, as do the five independent kernel topology
markers, exactly-once feature/pass checks and rejection of nonzero or forced
exit.

The QEMU machine retains two 1 GiB memory backends, CPUs 0–1 and 2–3, distance
20, four CPUs by default and 2048 MiB of RAM. The default deadline is 300 seconds.
At the first verdict the PTY sends Ctrl-A x and waits ten seconds for a clean
exit. A later failure remains a failure. The owner then retires the entire
process group and closes the PTY on all paths, including SIGINT.

Provided init/archive inputs remain supported. `run.sh` builds the original
strict-warning C fixture and snapshots a prebuilt kernel without rebuilding it.
`--kernel-dir DIR`, `--state-dir DIR` and `--build-only` select the kernel,
retain artifacts or prepare without booting. Explicit state contains the launch
hashes and raw serial capture; default scratch is removed.

Host checks exercise fragmented serial, first verdicts, late failures, exit
statuses, descendant retirement and repeated FD closure. They do not establish
NUMA placement in a kernel. See the
[guest qualification and limits](../native-system-tools/README.md).
The previous Python object/query bridge is retired.

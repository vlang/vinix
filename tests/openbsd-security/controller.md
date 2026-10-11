# Native security guest controllers

`run_vm` and `run.sh` compile and run V directly through
[`systemhost`](../native-system-tools/systemhost/security.v). The mount-policy
and IPv6 controllers share this typed implementation. There is no Python query,
object bridge or package server on this path.

The maintained CLI, exact feature counts, failure markers, two-second settling
period and 600-second deadline remain. ARM also requires the pledge-violation
report. Packet parsing keeps all four pcap byte orders and permissive truncated
records. Random IP IDs, ephemeral ports and TCP sequence checks keep the original
thresholds. IPv6 retains its ICMPv6, MLD, IGMP, TCP and UDP requirements and an
IPv6 TCP/UDP echo service with explicitly joined workers.

Provided ARM init/archive inputs and provided x86 ISOs remain supported.
`run.sh [aarch64|amd64]` builds the unchanged strict-warning C fixture, copies a
prebuilt kernel and packages a private ISO. ARM defaults to `VINIX_KERNEL_DIR`
or `kernel`; x86 defaults to `VINIX_AMD64_KERNEL` or
`build-amd64-kernel/bin/vinix`. `--kernel-dir` overrides either. Explicit state
directories retain raw serial, captures and launch hashes; default scratch is
removed. `--build-only` prepares without booting.

The PTY owner retains argument/environment storage through child exec, keeps
the original bounded read and marker window, and retires the whole process
group on success, failure or interrupt. Cleanup output cannot supply missing
features. See the [qualification and guest limits](../native-system-tools/README.md).
The previous Python import/monkey-patching interface is retired with its callers.

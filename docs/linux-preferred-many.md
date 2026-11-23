# Native preferred-many NUMA policy

`set_mempolicy(MPOL_PREFERRED_MANY)` sets a thread's preferred nodes, and
`mbind` sets the same policy on private anonymous ranges. Policy queries
through `get_mempolicy` report mode 5 and the full set of eligible preferred
nodes. The policy rejects empty masks and masks with no eligible nodes. It
inherits with the existing thread or range policy. [Linux 6.12.51 memory policy implementation](https://github.com/gregkh/linux/blob/v6.12.51/mm/mempolicy.c)

The allocator tries the preferred nodes by distance from the current CPU.
It skips direct reclaim on this pass. If all preferred candidates fail, it
tries the normal local-first allocation path. The preferred mask stays
intact when an allocation falls back.

An explicit range can override the node used to order those attempts.
See [home-node qualification](linux-mempolicy-home-node.md).
Indexed weighted interleave has separate qualification. Optional mode flags
and translated or 32-bit policy calls remain open. [Weighted interleave qualification](linux-weighted-interleave.md)

## Qualification

The fixture checks both setters and queries, rejects empty or unavailable
masks, and confirms that an explicit range can override the thread policy.
The pressure runner gives node 0 1,024 MiB and nodes 1 and 2 128 MiB each.
The probe faults 320 MiB with a preferred mask for nodes 1 and 2, samples
one page per MiB, and checks that the first fault uses a preferred node.
The runner requires samples on both preferred nodes and on node 0.

The same native probe ELF per architecture passed on Vinix and Linux
6.12.51 in single-node and three-node guests. Counts below are page
samples for node 0, node 1, and node 2 in that order.

| Architecture | Probe ELF SHA-256 prefix | Vinix samples | Linux samples |
| --- | --- | --- | --- |
| AArch64 | `74f3b91d2424159a` | 124, 128, 68 | 108, 110, 102 |
| x86-64 | `273abc2cbe7e19c4` | 133, 123, 64 | 106, 108, 106 |

Both production kernels were built from `be592f952` plus the archived
source patch. `taskpolicy`, `mbind`, and `mempolicy` regressions passed
on both architectures. The existing AArch64 two-node NUMA test also
passed, including `MPOL_BIND`, `mbind`, and first-touch placement.
The allocation checker output matched the pinned baseline byte for byte,
including its existing failures.

Run the single-node [fixture](../tests/linux-compat/prefmanyfixture/core.v)
with `tests/linux-compat/run --arch ARCH --kernel-dir DIR --state-dir
VINIX-RUN --cases prefmany`. The [Linux reference runner](../tests/linux-compat/syscall-reference.v)
takes `--arch ARCH --case prefmany --kernel LINUX --init VINIX-RUN/prefmany/init
--state-dir LINUX-RUN`. Run the [pressure controller](../tests/linux-compat/prefmany-numa.v)
with `--arch ARCH --platform vinix --input-dir VINIX-RUN --state-dir FRESH-DIR`,
or pass `--platform linux --input-dir LINUX-RUN` for the Linux run.

The restored and verified archive is
`~/.cache/vinix-r15/preferredmany/qualification.tar.zst`, with SHA-256
`83a437c80d1e4e498b0e2ec09975cc87b44fa4dae781f2190e6c68035550f61f`.

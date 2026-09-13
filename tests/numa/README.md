# AArch64 NUMA / multi-socket regression

This test boots a freshly built Vinix kernel on a QEMU machine deliberately
built with two memory nodes — one gigabyte and two vCPUs each, declared twenty
apart — and checks that the kernel discovers that machine and acts on it.

The kernel side is asserted from its own boot log: two nodes read out of ACPI,
CPUs 0–1 on node 0, CPUs 2–3 on node 1, and the distance matrix from the SLIT.
The guest side runs as PID 1 and checks:

- `/sys/devices/system/node/` reports the nodes, their CPU lists, their CPU
  maps, their distances and roughly a gigabyte each, and
  `/sys/devices/system/cpu/{present,online}` reports all four CPUs.
- `getcpu(2)`, with the thread pinned to each of the four CPUs in turn, reports
  that CPU and the node whose sysfs CPU list contains it.
- `get_mempolicy(2)` reports MPOL_DEFAULT for a fresh process, the machine's
  node set for `MPOL_F_MEMS_ALLOWED`, and the caller's own node for
  `MPOL_F_NODE`; `set_mempolicy(2)` rejects an absent node, an unknown mode and
  an empty binding.
- `set_mempolicy(MPOL_BIND)` to each node in turn actually places 192 MiB of
  anonymous memory on that node, measured through the per-node free-memory
  figures, regardless of which node the thread is running on.
- `mbind(2)` on a live mapping places that range's pages on the node it named,
  and rejects an unaligned address.
- With no policy at all, first touch places 128 MiB on the node of the CPU the
  thread is pinned to, for a CPU on each node in turn. This is the check that
  the whole feature exists for, and it runs both nodes as the local one, so
  neither result can come from a kernel that always answers "node 0".

Every check that moves the thread relies on the secondary CPUs actually
scheduling, which on AArch64 they now do. A thread pinned away from the CPU it
is on is handed over on the first `sched_yield(2)` even when it is the only
runnable thread on the machine; the pin helper retries a bounded number of times
so that a kernel which cannot do the handover fails this test rather than
hanging it.

Build the AArch64 userland once to provide the musl test sysroot, then run:

```sh
./build-userland-aarch64.sh
tests/numa/run.sh
```

Set `VINIX_QEMU_NUMA_NO_BUILD=1` to reuse `kernel/bin/vinix`, or
`VINIX_QEMU_TIMEOUT` to change the default 300-second deadline. The boot and
EXT2 images are isolated in temporary directories and removed after the run.

A single-node machine — every machine this test does not build — is the
uniform case the kernel falls back to, and `tests/qemu-core` covers it: it
boots without any `-numa` flags and exercises the same allocator and scheduler
paths with `numa_multinode` false.

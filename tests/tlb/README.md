# CPU address-space tags and large-page regression tests

ARM retains 255 globally exclusive eight-bit ASIDs, non-global TTBR0 leaves,
broadcast break-before-make and invalidation before tag reuse. X86 owns PCIDs
1–4095 when every CPU supports PCID and INVPCID; mutations invalidate inactive
contexts too, and tag ownership survives every teardown acknowledgment. Both
architectures reserve zero for conservative switching and pool exhaustion.
See [implementation and limits](../../docs/address-space-tlb.md).

X86 direct-map 2 MiB leaves replace 512 base leaves and save one 4 KiB leaf
table. Promotion requires an aligned, complete usable-RAM interval with a
verified uniform WB MTRR type. Reserved/MMIO/firmware spans, cache boundaries
and unknown layouts use base pages. Partial remap/protection/unmap splits into
512 equivalent children, synchronously flushes, and changes only the selected
child. Allocation failure preserves the old descriptor and charge.

Build each kernel in an isolated worktree with the repository's dependencies
linked as described in AGENTS.md. The runner never rebuilds a kernel.

```sh
make -C /work/arm/kernel ARCH=aarch64 LIMINE_MP=1 ALLOC_TRACK=1 \
  V=/Users/alex/code/v/v CC=clang VFLAGS='-d tlb_selftest' -j4
make -C /work/x86/kernel ARCH=x86_64 ALLOC_TRACK=1 \
  V=/Users/alex/code/v/v CC=clang LD_X86_64=ld.lld \
  VFLAGS='-d tlb_selftest -d largepage_selftest' -j4
python3 tests/tlb/run.py --arch aarch64 --kernel-dir /work/arm/kernel \
  --state-dir /tmp/tlb-arm --timeout 1200
python3 tests/tlb/run.py --arch x86_64 --kernel-dir /work/x86/kernel \
  --state-dir /tmp/tlb-x86 --timeout 1200
python3 tests/tlb/run.py --arch x86_64 --kernel-dir /work/x86/kernel \
  --cpu max,pcid=off,invpcid=off --state-dir /tmp/tlb-fallback --timeout 1200
python3 tests/tlb/run.py --arch x86_64 --kernel-dir /work/x86/kernel \
  --cpu max,la57=off,pcid=off,invpcid=off --state-dir /tmp/tlb-la48 --timeout 1200
V=/Users/alex/code/v/v python3 tests/tlb/policy.py
```

The disposable native guest uses four CPUs, a static musl fixture and 4096 MiB
of RAM. It checks these paths through actual system calls and the MMU:

- CPU 1 and CPU 0 share one map for 100 protection/unmap/address-reuse rounds,
  alternating read-only and PROT_NONE. A filler consumes the freed frame.
- A non-thread CLONE_VM child warms the map on CPU 1 and stops. CPU 0 protects
  or replaces the mapping while that remote context is inactive, then resumes
  the child. Sixty-four rounds require faults or the new backing value.
  Raw getpid/kill avoids libc's cached thread identity in shared TLS.
- Three hundred fork/COW map recycling cycles preserve private data; 32 execs
  replace maps and exercise tag release/reuse.
- Two live processes pinned to one CPU perform 20,000 alternating scheduling
  rounds, with every slab class through 2048 bytes and large-allocation pages
  measured before and after. The fixture reports, and permits only, the known
  one-object size-48 `/proc/slabinfo` observer retention.
  Both inherit CPU 0 affinity after the recycling cases, exercising ARM's
  second selection after its idle-stack handoff on a shared run queue.

The optional boot self-tests exercise the production pools: every tag is
reserved, exhaustion returns zero, one tag is released/reused, the whole pool
is released, and another 2,000 reuse cycles follow. The x86 probe uses explicit
stack storage; generated C confirms its default members allocate no storage.
ARM also checks TCR tag
selection/width and non-global PROT_NONE. These checks do not claim thousands
of simultaneous full processes. X86 without PCID/INVPCID reports
`TLB: PCID unavailable; conservative switching PASS`.

The x86 large-page boot fixture checks translation, exact child protection,
neighbor survival, failed-allocation rollback and partial unmap. A second
fixture runs after SMP initialization: CPU 1 warms an actual supervisor large
alias over owned aligned RAM through an IPI, returns idle, then reads after
CPU 0 splits/remaps a child. Sixty-four unmap/replacement probes preserve its
neighbor, and final synchronous unmaps precede all backing/table frees. Request
and acknowledgment storage is static; no test actor Thread is allocated.
Require `VMM: SMP large-page split, remap, neighbor survival and teardown PASS`
in the transcript of an x86 self-test build.

`policy.py` extracts production functions, replacing hardware and allocator
ports with host adapters. It verifies all 4095 exclusive PCIDs, ownership until
remote acknowledgment, inactive-tag invalidation, fallback switching, PAT
conversion, MTRR and firmware-entry rejection, exact child remap/protection,
allocation failure and return of every test table page and reservation. It
also runs the production PCID boot self-test. It is policy/ownership
coverage; it does not emulate hardware TLB retention.

Also run sparse-table, process lifecycle, paging pressure, scheduler/PI,
resource/quota and job-control guests on both kernels. Run ARM desktop
`ops,churn,cache` and `idle,apps,drag`, and the allocation audit without expanding
its allowance file. The broader measured-retention roadmap item stays open.

Qualification on 2026-10-10 used isolated kernels, four guest CPUs, ARM HVF and
x86 QEMU 11.1.1 TCG:

| Check | Result |
| --- | --- |
| Both architecture builds, production mode and allocation tracking | PASS |
| Host PCID pool, inactive invalidation, MTRR boundaries, splitting and rollback | PASS |
| ARM TLB guest; x86 five-level default/feature-disabled and four-level guests | PASS |
| X86 boot and SMP large-page translation/protection/replacement/teardown | PASS |
| Both architectures: process lifecycle, sparse tables, paging pressure, scheduler/PI, resources, quotas and job control | PASS |
| ARM desktop idle, apps and drag | PASS |
| ARM operation/churn/cache measurements | Completed; broader retention remains |
| Allocation allowance audit | Same 170 pre-existing excess groups; no additions or allowance changes |

ARM's 20,000 switching rounds kept all measured classes and large pages flat.
All three x86 switching runs had nonincreasing counts as older exited-process
allocations drained. The 600-worker scheduler regression passed on both
architectures after repairing ARM's second selection and x86 map-root/process
lifetimes. Paging pressure included automatic anonymous reclaim and encrypted
disk swap/swapoff; 200 paging cycles kept measured classes flat. X86 TCG used
a 600-second pressure-test timeout after a 240-second run printed its verdicts
but exceeded the runner deadline.

The ARM operation fixture retained zero bytes per mmap/thread operation, but
mkdir retained 208 bytes per operation on tmpfs and ext2. The four 300-run churn
workloads retained 16–48 KiB each. These measurements do not establish complete
kernel leak freedom. Generated C and the lifetime review cover the new paths;
the separate measured-retention roadmap item stays open.

QEMU system TCG lacks PCID/INVPCID. Native x86 results therefore qualify the
conservative path and actual large-page MMU transitions. Host policy tests and
inspection of the compiled INVPCID descriptor/instruction cover the enabled-tag
implementation, but PCID-enabled physical-hardware/KVM qualification remains.
Explicit userspace huge pages, wider tag generations and physical speedup/power
measurements are outside this bounded kernel implementation.

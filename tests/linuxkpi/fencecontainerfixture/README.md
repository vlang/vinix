# DMA-fence array and chain host checks

Run from the repository root with a working V toolchain and a fresh output
directory:

```sh
build-support/run-v-tool.sh tests/linuxkpi/dma_fence_containers.v \
  --keep-directory /tmp/vinix-fence-container-host
```

The V controller verifies the unchanged pinned Linux import, generates the actual
production modules, and compiles the selected generated bodies under strict
GNU99 and GNU11 with ASan/UBSan. Each selected body, export thunk and initialization
guard must match the complete generated production module byte for byte. Three
existing RCU-worker bootstrap completion adapters are explicitly separated from
that parity count. Compiler inputs, include dependencies, binaries, logs and
before/after source hashes are retained in `result.json`. The controller also
inspects every generated fixture body for implicit V boxing, array/string
allocation and deep pointer equality. C supplies original records, original
inline/macro adapters, declarations and compiler primitives only.

Actual array, chain, base fence, IRQ-work, tagged page allocator, ordinary RCU,
task state/wake/schedule and timed-deadline algorithms run unchanged. The fixture
reuses the established low-level CPU/IRQ/thread/context, clock, page and console
transport. Native enqueue/dequeue/park uses independent host threads and yields;
explicit clock ticks exercise the real timeout implementation. RCU grace periods
use the actual backend and its existing bounded CPU-scope observations. A host
IPI is a recorded doorbell followed by an explicit actual dispatcher invocation.
This does not execute native IRQ entry, IRET, real hardware scheduling, or a GPU.
Explicit `calloc/free` supplies host task contexts; callback/fence/vector/chain
allocations use the actual tagged page allocator. Cache algorithms are linked
production bodies, without a cache-ownership coverage claim.

Two controlled scheduling windows are transport only:

- The existing native spinlock transport can stop one designated modeled IRQ
  context before its third acquisition of the real `vkiw_guard`: detached-list
  acquisition, dispatch publication, then postcallback acquisition. The guard
  remains unlocked during the stop. A remote child can overwrite the original
  chain callback/IRQ union and queue it on another CPU. No dispatcher body,
  callback record, flag or atomic result changes.
- The chain `prev` compare/exchange primitive can stop two actors at one exact
  designated address. Both actors already hold the real walk references. The
  transport then runs the identical fully ordered `__sync_val_compare_and_swap`
  and returns its untouched observed pointer, recording one win and one loss.

The union test runs eight complete lifecycles. Two actual IRQ callbacks overlap,
with both real stack running records live and the head reference count at zero.
The terminal chain callback calls original `dma_fence_add_callback` on completed
children; its `-ENOENT` path initializes `cb.node`, so the union is a detached
callback representation. Those bytes must not be interpreted as live IRQ flags.
All 32 union bytes are compared under a held real modeled reader and must survive
both actual postcallback compare/exchanges unchanged. The records retire
`2 -> 1 -> 0`. An IRQ-return transport gate keeps the final original IRQ scope
open after dispatcher retirement; actual RCU must retain both retired chain
owners until that IRQ scope exits, even after the controller releases its own
reader. Child signal actors keep a separate child reference through signal
return. No work or callback storage is dereferenced after its lifetime ends, and
`irq_work_sync` is never applied to the callback representation. The separate
IRQ-work suite covers the public BUSY-bit ABA case.

The remaining executed cases cover ALL/ANY signed negative pending tails, first
error propagation and post-signal preservation, polling semantics, partial and
immediate registration, enable-once races, self-freeing detached callbacks, forty
concurrent array lifecycles, constructor/chain allocation OOM without ownership
theft, both original immutable ops identities, nested shallow iteration and
deadline forwarding, chain input-reference consumption and CAS win/loss, terminal
ordinary fences, context/32-bit/64-bit sequence boundaries, and a 1,024-node
iterative release. Real barriers and joins precede exact host page recovery.
Two new fatal null chain-construction controls preserve all 128 storage bytes,
the child fence and page-call count. Existing base fence wait, custom-ops,
callback-race, RCU-release and fatal-context regressions also run. The expected
pending-release diagnostic in a safe log comes from the deliberately exercised
original warning path. Sanitizer diagnostics are always failures.

There are two safe runs and 24 fatal child runs across the two production C
dialects. Fixture metadata is compiled under strict GNU11. These are host
algorithm, lifetime and transport tests. Native page/live-heap measurements,
native IRQ-return validation, complete unchanged-driver linking, reservation
services and Tiger Lake hardware validation remain separate requirements.

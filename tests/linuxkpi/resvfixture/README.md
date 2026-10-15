# DMA reservation host checks

Run from the repository root with a fresh output directory:

```sh
build-support/run-v-tool.sh tests/linuxkpi/dma_resv.v \
  --keep-directory /tmp/vinix-reservation-host
```

The V controller verifies the unchanged pinned Linux 6.6.157 import and executes
the actual generated production reservation, Wait-Die writer lock, ordinary
mutex initialization/destruction, base/array fence, IRQ work, ordinary RCU,
requested-size page allocator, task and timeout bodies. Each selected body,
export thunk and initialization guard must match the complete generated module
byte for byte. Three existing RCU bootstrap completion adapters are reported
separately. Production bodies compile under strict GNU99 and GNU11 with
ASan/UBSan; compiler inputs, dependencies, logs and source hashes are retained.
All generated fixture bodies are checked for hidden V allocations and deep
pointer equality. Independent definition and outer-identifier parsers record
every body with a unique identifier/occurrence key, including one-line compiler
helpers, conditional alternatives and functions taking callback parameters.
Body and unique-key counts must match. The C contract contains original records, inline/macro
adapters, declarations and compiler primitives only.

Original public reservation APIs use their genuine 48-byte object and iterator,
24-byte private flexible-list header and mutable 32-byte Wait-Die class. V tests
observe usage tags 0 through 3, borrowed locked and retained unlocked iterator
references, reserve/grow/prune/add/replace, copy/get/singleton ownership and
failure cleanup, waits, deadlines and exact requested-size reallocations.
Fences use the default production RCU release. Producers keep their references
through signal return; every thread is joined before its witnesses retire.

The fixture reuses established native CPU/IRQ/thread/context, page and clock
transport. Independent host threads implement enqueue/dequeue/park by yielding;
explicit ticks exercise the actual timeout implementation. Original Wait-Die
locks and reservation ownership execute without a host mutex replacement.
Physical page allocation may return a controlled OOM or retain one actually
freed page and return it on the next allocation. A selected acquire pointer load
may pause after loading and return its untouched observed bits; a producer
signaled callback can pause while the actual RCU/preemption scope stays live.
These debugging gates exercise genuine zero-ref retry, partial copy/get restart
and OOM, empty restart cleanup, preserved weak aggregate prefixes and same-address
list reuse from cached count 4 to live count 1. Ordinary in-place count growth
separately preserves the cached iterator snapshot. Neither boundary changes
reservation, iterator, refcount, rollback or grace-period algorithms. Six fatal
controls also verify unchanged object, list and fence bytes before rejection.
Real native IRQ return, kernel allocation retention and GPU behavior require
separate validation.

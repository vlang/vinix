# Original i915 SW-fence host consumer

Run from the repository root with a fresh output directory:

```sh
build-support/run-v-tool.sh tests/linuxkpi/i915_sw_fence.v \
  --keep-directory /tmp/vinix-sw-fence-host
```

The V controller verifies the pinned Linux 6.6.157 import and compiles the
complete unchanged `i915_sw_fence.c`. All ten configured public functions are
checked in the object and retained in each executed binary. Production V
reservation, fence, timer, IRQ work, wait, task, page allocator, exchange and
ordinary RCU bodies are selected from actual generated modules and checked
byte for byte against their complete generated production modules. Three
existing RCU bootstrap completion adapters are explicitly separate. GNU99 and
GNU11 production objects and whole original SW objects use ASan/UBSan; generated
fixture metadata uses strict GNU11. No original function is extracted or
replaced. Original enum callback identity is retained, including UBSan type
identity. Compiler inputs, dependencies, object imports, binaries, logs and
before/after source hashes are recorded. Every whole-object service import
must have exactly one concrete definition in the linked objects and remain
defined in the executable; compiler/sanitizer imports are listed separately.
An independent function/identifier
scanner checks every fixture body with unique occurrence keys, including
one-line helpers and conditional alternatives.

C supplies original records, original inline/macro adapters, declarations and
compiler primitives. All fixture control flow is V. The sole diagnostic is an
explicit typed transport: after parsing the original header closure, a macro
maps `_printk` to the separate `swh_printk` symbol. A genuine variadic original
control object is compiled separately; complete preprocessed units must match
after normalizing only this identifier. The V sink records the original format,
driver/timeline names, sequence number, hint and call count. Timeout-first
checks every argument; signal-first checks no call. Native printk formatting
and ring algorithms are outside this host suite.

Tests cover pending/notification phases, sticky errors, real task waiting,
reinitialization, separate owner self-free, supplied and allocated graph nodes,
a 512-node continuation chain, dynamic and supplied DMA callbacks, valid
nonblocking page OOM and actual indefinite blocking fallbacks. Reservation
usage filters and partial ENOMEM retain the already-installed dependencies.
A gated acquire load returns its untouched observed tagged pointer after a
writer retires the last old fence reference: real get-unless-zero and ordinary
RCU determine retry and repeated visitation.

Already-signaled DMA inputs transfer the error without allocation. A genuine
DMA enable-signaling callback signals under its held lock, making original
callback registration return `-ENOENT`; supplied, dynamic and timed SW
callbacks then complete inline, including actual timed IRQ/RCU cleanup. An
isolated no-waiter notifier declines COMPLETE and remains signaled at pending
zero, without inventing a recovery operation or freeing protocol.

Timed tests execute original timer setup and rounded expiry, genuine V timer
dispatch/shutdown, original DMA callbacks, real IRQ-work dispatch and embedded
RCU free. They cover signal first, timeout first with required late DMA signal,
and a held IRQ-safe timer callback racing a remote DMA signal. An independent
host actor runs the actual IRQ dispatcher and blocks in real timer shutdown;
another actor releases the timer. After actual IRQ running-record retirement,
an explicit modeled IRQ-return gate keeps its original IRQ scope live while
the ordinary reader ends. Callback backing must survive until that final IRQ
scope ends. Every producer reference survives signal return, every actor is
joined, and page/task/timer/waiter ownership returns to baseline.

Native CPU/IRQ/thread/page/clock operations are disclosed host transport. Clock
ticks and timer dispatch are explicit; enqueue/dequeue/park use independent
host threads and yielding. Atomic-context `cond_resched` returns zero as the
native transport does. Gates pause actors without changing production queue,
reference, timer or grace-period state. This executes the complete original
SW-fence synchronization consumer on a host; native IRQ entry/return, kernel
retained allocations and GPU behavior require separate validation.

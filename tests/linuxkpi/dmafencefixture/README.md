This focused suite executes the production V DMA-fence, allocator, ordinary
RCU, task-state/wake/schedule and timed-deadline bodies with the original Linux
records and inline helpers. Full-module generated-body parity includes export
thunks and initialization guards. Production objects use strict GNU99/GNU11
and ASan/UBSan; generated fixture metadata uses GNU11.

The matrix runs one complete scenario and ten explicit fatal controls for
each production dialect. It covers custom ops and return values; enable-once
and context-ID races; FIFO callbacks, immediate callback self-free and
add/remove/signal races; error/timestamp/union and sequence-wrap behavior;
global/private stub references and reader-held actual RCU freeing; real
finite, infinite, interrupted and retried waits; wait-any OOM, partial setup,
winner, timeout and interruption cleanup; and atomic direct-default fast
paths versus strict wrapper waits. Fatal controls require the original fence
bytes and allocation count to remain unchanged and reject sanitizer faults.

The independent host transport supplies CPU/IRQ scopes, native task reference
observations, enqueue/dequeue/park, pending-signal observation, clock advance
and physical-page transport. Park yields a host pthread until a genuine
production wake or deadline queues it. The production task/time code owns
the wait/wake/deadline algorithm. Three existing completion adapters serve
only RCU-worker bootstrap. Actual native scheduling, IRQ entry/return and
kernel retained-allocation measurements require separate guest evidence.
The pending-release warning uses a metadata adapter to the host console;
production name-hook evaluation, warning condition, error signaling and
callback retirement remain unchanged and are tested explicitly.

Run through `build-support/run-v-tool.sh tests/linuxkpi/dma_fence.v` with a
compatible native producer and host compiler; `--keep-directory DIRECTORY`
preserves generated bodies, actual dependencies, sanitizer logs and hashes.
No original driver source is changed and no GPU completion is claimed.

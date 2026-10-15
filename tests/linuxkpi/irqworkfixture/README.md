Run the focused IRQ-work fixture from the repository root:

```sh
build-support/run-v-tool.sh tests/linuxkpi/irq_work.v --keep-directory NEW_DIRECTORY
```

The fixture executes generated production V backend/facade functions and keeps
their original bodies. Complete-module generation checks the borrowed bodies,
export thunks and initialization guards before execution. The genuine Linux
IRQ-work records, flags and initialization macros come from unchanged headers.

All host runtime logic is V. The host transport supplies CPU/context identity,
IRQ save/restore, spin primitives and IPI doorbell observations. The controller
delivers observed interrupts explicitly; the transport implements no IRQ-work
queue, pending-list, callback or synchronization algorithm. Native delivery,
idle wakeup, IRQ entry/IRET and retained native memory require separate guests.
SMP transport and RCU publication are controlled constructor observations;
false publication rejects bootstrap before true publication permits it. The
host callbacks retain their owners and do not execute an RCU grace period or
deferred free. Real RCU execution remains a separate native fixture check.

Production objects use strict GNU99 and GNU11 with ASan/UBSan. The generated
full host fixture uses GNU11 because repeated foreign typedef metadata requires
C11. The tests cover CPU-number boundaries, duplicate pending submissions,
deferred local execution while IRQs are disabled, local lazy tick kicks, remote
lazy immediate doorbells, callback self-requeue and sleepable synchronization.
A two-CPU overlap case holds two callbacks on one original record: after the
first returns and clears public BUSY, synchronization still waits for the second
stack running record. Callers retain that storage throughout both callbacks and
synchronization; this test does not introduce immediate callback self-free.

Fatal children distinguish explicit validation failures from sanitizer errors,
checking original node flags/link preservation for invalid CPUs, flags and sync
contexts. Queueing runs with allocation failure armed, and production objects
are inspected for hidden allocator imports. NMI, RT and hotplug support are not
claimed.

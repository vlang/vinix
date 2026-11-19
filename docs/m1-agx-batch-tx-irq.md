# Base M1 G13 batch doorbell transmit IRQ

The native G13 submission path transfers job and event ownership, publishes
the firmware ring pointers, and releases all participating ring locks before
notifying the ASC. It carries only the priority and pipe mask into the
notification phase. It sends fragment, vertex and compute doorbells in
reference order, with the priority and pipe type in the Asahi wire positions.
[Asahi work-pipe send](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/gpu.rs#L1245-L1274)

The mailbox allows one IRQ waiter. A concurrent sender can poll the FIFO
without rearming or masking the owner's interrupt. For a batch doorbell,
the worker can drop the manager lock while waiting and must check GPU state
and the 500 ms deadline before retrying. On the first failed doorbell it
stops notifying, marks a live GPU as failed, and returns the full transfer
mask. Shutdown may already have freed the submitted jobs at that point.
Firmware-control sends, submission kicks and standalone submission
doorbells still use polling.

ARM64 and x86-64 kernel builds and all 82 contract test files passed for
`c384c76bace5911800b36deb0a3d6e805a27426c` plus the archived patch.
ASan/UBSan covered both firmware ABIs, doorbell readiness and encoding,
shutdown during a FIFO wait, competing sends, and 84 batch transactions.
Three negative controls caught a second IRQ owner, a send after shutdown,
and bypassed RTKit power gating. The event, queue-unwind and asynchronous
submission suites also passed. The queue-unwind harness now extracts the
queue ID allocator up to the next function's comment.

Generated ARM64 C confirms ring release before notification and no new
allocation or extra job-array copy. Independent lifetime review found no
remaining blocker. The allocation scan reproduced 178 baseline findings.
The pinned source gates passed and the full audit remains `not_equivalent`.
No physical M1 tests, boots or reboots ran.

Evidence is retained under
`/Users/alex/.local/state/vinix/omarchy-m1-batch-tx-irq-20261118/`.
The archive and restored copy passed full inventory verification.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `befad222d38df0b22f470a1678cda9638ee8d3128ff2383c9ea866c241adc22c` |
| `bundle.tar.gz.inventory.txt` | `e728a76c479401c0ed7b7c92cc4012a15e06c2973b8b299439a87ebdf9f822b6` |

## Deadline checks for ASC retries

A polling wait, an unguarded IRQ wait or contention on the FIFO lock could
consume the remaining transmit budget before a retry touched the FIFO.
Timed retries now check the budget after each wait and again with the FIFO
lock held. A final attempt at exactly 500 ms remains valid. Once the budget
expires, the retry returns without publishing either mailbox word.

The sanitizer fixture reproduced a late send on
`4d4535d1f4f5ef37a501726f9097736a33fdc597`. Four new cases cross polling and
IRQ operation with delayed waits and FIFO-lock contention. All four verify
rejection of the expired attempt and successful publication on a fresh send.
The G13 runtime transmit, recovery and job-lifetime fixtures also passed.
AArch64 and x86-64 builds, all 79 local contract tests and 122 archived-reference
checks passed. The allocation scan reproduced the same 176 baseline findings.

Evidence and the tested diff are stored at
`/Users/alex/.local/state/vinix/omarchy-m1-asc-retry-deadline-20261119.UuaYQH/`.
The `bundle.tar.gz` SHA-256 is
`964c7c377fa201eb36c72a89ba995f841278bacd3bfac046400d5f462297f6f8`.
Native M1 firmware validation remains open.

## RTKit power changes during a guarded send

A batch doorbell can release the GPU manager lock while it waits for ASC
FIFO space. An AP or IOP power acknowledgement can clear RTKit application
readiness during that wait while the GPU manager still reports running.
Guarded application sends now check both conditions after reacquiring the
lock and before retrying the FIFO. System endpoint replies retain the
caller's transport check.

The previous revision `14b70da6a121cb0c69f4355f0ac481e3a24186b2` sent the
waiting doorbell after power was revoked. ASan/UBSan passed four regression
cases across both G13 ABIs. They verify cancellation before another FIFO
read or write, successful system replies with application power off, and
a fresh application send after power returns. Existing deadline, shutdown,
RecoverChannel and batch lifetime cases also passed.

AArch64 and x86-64 builds, 79 local contract tests and 122 archived-reference
checks passed. Generated AArch64 C keeps the synchronous guard on the stack.
The allocation scan reproduced the same 176 baseline findings.

Evidence and the tested diff are stored at
`/Users/alex/.local/state/vinix/omarchy-m1-rtkit-application-ready-20261119.xOSxEz/`.
The `bundle.tar.gz` SHA-256 is
`3b7b7a39e89356d16109d5a8da29d71296c70c65ff259aeaf062741c5fbd7b04`.
Native M1 firmware validation remains open.

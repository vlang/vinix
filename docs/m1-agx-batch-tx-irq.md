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

## RTKit crash during a polled send

The receive worker can clear RTKit application readiness while handling a
crash notification, even while a polled doorbell holds the manager lock.
Firmware-led application sends now check readiness before the first FIFO
attempt and after every IRQ or polling wait. The mailbox checks caller
liveness under the caller's lock when one is supplied.

The sanitizer fixture reproduced a stale doorbell on
`0fc58c97b713c294d01711f036b3a2b55fb9d4b8`. Four regression cases passed
across the two G13 ABIs with either no send IRQ or interrupts masked. They
verify that the live doorbell succeeds, a crash during the wait prevents
another FIFO read or either mailbox write, and subsequent sends are rejected.
The existing guarded transmit, system reply and job-lifetime checks passed.

AArch64 and x86-64 kernel builds, all 79 local contract tests and 122
archived-reference checks passed. Generated AArch64 C keeps the readiness
context on the stack. The allocation scan reproduced 176 baseline findings.

Evidence and the tested diff are stored at
`/Users/alex/.local/state/vinix/omarchy-m1-rtkit-polled-readiness-20261119.n0Aejo/`.
The original and restored bundles passed inventory verification. The
`bundle.tar.gz` SHA-256 is
`5050f93928e525b0fad511d78cdd706f97bb3e9861116775b3df49429de9f708`.
Native M1 firmware validation remains open.

## RTKit readiness after ASC FIFO lock contention

The readiness check could pass before the sender had acquired the ASC FIFO
lock. The mailbox now checks readiness and any caller liveness predicate
with that lock held before the first FIFO access and every retry. Cancellation
releases the FIFO lock and any claimed send IRQ.

The sanitizer fixture reproduced a stale doorbell on
`a8b6222d36804aeb2c90fb4907b3ccedc9307498`. Twelve cases passed across the
two G13 ABIs, covering a crash during the first lock acquisition, the polling
wait or retry lock acquisition. Each case checks that cancellation prevents
further FIFO reads and both mailbox writes. The job-lifetime suite, AArch64
and x86-64 builds, 79 local contract tests and 122 pinned-reference checks
passed. The allocation scan reproduced the same 176 baseline findings.

Evidence and the tested diff are stored at
`/Users/alex/.local/state/vinix/omarchy-m1-asc-locked-readiness-20261119.auUuuY/`.
The `bundle.tar.gz` SHA-256 is
`d18db22b6d4b194303963b150652187663099a81e02ada426f1de046f60108d2`.
Native M1 firmware validation remains open.

## System sends after an RTKit crash

The pinned Asahi transport rejects messages to every endpoint after a
coprocessor crash. G13 RTKit now sets a crash flag before reading the log
and checks it under the ASC FIFO lock on each send attempt. System replies
remain available when application power is off and the transport is live.

The sanitizer fixture reproduced a stale IOReport reply on
`30cd542c7dcc775a9d73e2fc4695b8ed08a357db`. All 24 cases passed across
both G13 firmware ABIs, covering IOReport replies and application doorbells
with a crash during the first FIFO lock acquisition, the poll wait or the
retry lock acquisition. They verify cancellation before any further FIFO
access and rejection of a fresh send after the crash.

Both kernel builds, the job-lifetime suite, 79 local contract tests and
122 pinned-reference checks passed. Generated AArch64 C keeps the transmit
context on the stack. The allocation scan reproduced 176 baseline findings.

Evidence and the tested diff are stored at
`/Users/alex/.local/state/vinix/omarchy-m1-rtkit-system-crash-20261119.bFnGkX/`.
The `bundle.tar.gz` SHA-256 is
`882d2f67c44d53cd6f7e91d364d3fe5e515fd54b970adb17cadc82dda2405b16`.
Native M1 firmware validation remains open.

## Application endpoint power during START_EP

START_EP uses the management endpoint and carries its target in the
payload. G13 RTKit now checks the target's power requirement under the
FIFO lock on every attempt. It retries an unsent START_EP once after a
mailbox timeout, as the pinned Asahi implementation does. Cancellation
ends the request.

The sanitizer fixture reproduced a send after application power dropped on
`5011dc2a93db52c7565c4a0c51c0709f786d5191`. Four cases passed across both
G13 ABIs with IRQ-assisted and polled sends. The cases restore power after
cancellation and verify that only a fresh request publishes the two words.
A negative control that retried cancellation reproduced the stale send.
Existing system endpoint, timeout retry and boot transcripts passed.

Both kernel builds, the job-lifetime suite, 79 local contract tests and 122
pinned-reference checks passed. The allocation scan reproduced the same
176 baseline findings.

Evidence and the tested diff are stored at
`/Users/alex/.local/state/vinix/omarchy-m1-rtkit-start-ep-20261119.RhjADr/`.
The `bundle.tar.gz` SHA-256 is
`68048e131a7ca9fff3ed9279bdf29d19e08293aa66a787691983f4bd78a44ee5`.
Native M1 firmware validation remains open.

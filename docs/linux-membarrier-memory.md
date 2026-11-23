# Data-memory barriers

Vinix implements `MEMBARRIER_CMD_GLOBAL`, `MEMBARRIER_CMD_GLOBAL_EXPEDITED`,
and `MEMBARRIER_CMD_PRIVATE_EXPEDITED` on x86-64 and GIC-backed AArch64.
An unregistered caller can issue either global command. The private command
requires a separate registration in the caller's address space. Every online
CPU completes a memory fence before the call returns. x86-64 uses `MFENCE`
through the scheduler's interrupt mailbox, and AArch64 uses `DSB ISH`
through the existing GIC rendezvous. Instruction synchronization retains
its separate operation. [Linux 6.12.51 command contract](https://github.com/gregkh/linux/blob/v6.12.51/include/uapi/linux/membarrier.h#L29)

`MEMBARRIER_CMD_GET_REGISTRATIONS` reports the page map's registration mask.
For a sync-core-only registration Linux reports the plain private bit as
well. The plain private command still returns `EPERM` until its own
registration succeeds. Threads share the mask, fork copies it, a failed
exec preserves it, and a successful exec clears it. [Linux 6.12.51 registration paths](https://github.com/gregkh/linux/blob/v6.12.51/kernel/sched/membarrier.c#L469)

## Qualification

The same native musl probe ELF per architecture passed on Vinix and Linux
6.12.51. It executed 256 relaxed store-load rounds per data command on CPUs
0 and 1 and checked that both loads never saw the old value in the same
round. The global commands used a peer in another process, with the peer
registered for the expedited case. The private command used a pthread.
The probe also verified query bits, command width, errors, registration
across fork and exec, 200 cross-CPU JIT updates, and 400 concurrent
instruction rendezvous calls during TLB changes.

Production Vinix kernels came from `72780fea3` plus this change. The
`1f235dbc3` baseline kernels on both architectures failed at the command
query using the final probe. `runtime` and `mseal` passed on both updated
kernels. The allocation check reported the same existing failures and the
same 306 AArch64 and 254 x86-64 allocation sites as the baseline.

| Architecture | Probe ELF | Vinix kernel | Vinix serial log | Linux serial log |
| --- | --- | --- | --- | --- |
| AArch64 | `5f0a7a483d561e04` | `4e3ed47195094b87` | `e23c8eced151bfa6` | `cd0c5eec50a2d7a0` |
| x86-64 | `0611547e08ad0da6` | `6596b1f0209eff74` | `16618118f657ff69` | `84a58f7a0e9d03f1` |

Hashes are SHA-256 prefixes. The archive is
`~/.cache/vinix-r15/membarrier-memory/qualification.tar.zst`, with SHA-256
`0db2b1607b7cba76b4f1c096e14c4da62d2d2d4a0fd23937e9187f68c9f2caf4`.

## Limits

The expedited commands also fence CPUs running unrelated address spaces.
Their cost scales with the online CPU count. AArch64 systems without the
required GIC transport advertise only `GET_REGISTRATIONS`. The rseq variants
remain unavailable.

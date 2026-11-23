# Expedited instruction synchronization

Native x86-64 `membarrier` now advertises
`MEMBARRIER_CMD_PRIVATE_EXPEDITED_SYNC_CORE` and its registration command.
The scheduler uses its existing TLB interrupt mailbox to request `CPUID` on
every online CPU. Each target acknowledges after serializing its instruction
stream, and the caller serializes its own stream before returning. The same
lock coordinates these requests with TLB invalidation and CPU parking.

On both architectures the command and flags use their low 32 bits. An
unregistered invocation returns `EPERM`. The page map holds the registration,
so threads share it and a fork copies it. A failed exec retains the page map
and its registration. A successful exec starts with a fresh page map. [Linux
6.12.51 syscall and registration](https://github.com/gregkh/linux/blob/v6.12.51/kernel/sched/membarrier.c#L592)
[Linux 6.12.51 fork](https://github.com/gregkh/linux/blob/v6.12.51/kernel/fork.c#L1583)

## Qualification

The same native musl ELF per architecture passed on Vinix and Linux 6.12.51.
The probe checked command width, flags and registration through pthreads,
fork, and failed and successful exec. It pinned the publisher and receiver
to CPUs 0 and 1, made 200 updates through a writable alias of a JIT page, and
called the code through its executable alias on the other CPU. Both threads
then made 400 concurrent rendezvous calls in total while changing write
permissions on resident pages.

Production Vinix kernels were built from `a09c35273` plus this change in
separate worktrees. The previous x86-64 kernel failed at the query and the
previous AArch64 kernel rejected a command whose upper word was set. An
intermediate x86-64 kernel with the rendezvous and command width fixes failed
the fork inheritance check. All three controls used the final probe. The
allocation checker reported the same existing failures and the same 306
AArch64 and 254 x86-64 allocation sites as the baseline.

The `runtime` and `mseal` guest regressions passed on both architectures.
The AArch64 runtime ISO build initially ran out of host disk space and passed
on retry with the same kernel.

| Architecture | Probe ELF | Vinix kernel | Vinix serial log | Linux serial log |
| --- | --- | --- | --- | --- |
| AArch64 | `163aa4a4854b7565` | `41ea91541b6185c9` | `8124ce7bfcee4255` | `138441da38478e08` |
| x86-64 | `337c6638ff1c9eab` | `ce241a0ce53f4f34` | `ebccff0210fe6257` | `ea49dcb4f0610122` |

Hashes are SHA-256 prefixes. The archive is
`~/.cache/vinix-r15/membarrier-sync-core/qualification.tar.zst`, with SHA-256
`4ace04cd0d7c78cf5a32491591dfd67e31edfbce72889171835e761e07f4d916`.

## Limits

On x86-64, the rendezvous covers all online CPUs, including CPUs currently
running unrelated processes. AArch64 uses the existing GIC implementation
where it can target all CPUs. The subsequent [data-memory barrier change](linux-membarrier-memory.md)
adds the global and plain expedited commands. The rseq variants remain unavailable.

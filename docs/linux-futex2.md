# Linux futex2

Native AArch64 and x86-64 programs can use `futex_waitv` (449), `futex_wake`
(454), `futex_wait` (455) and `futex_requeue` (456). These syscalls use the
same queue and key rules as Vinix's legacy `futex` syscall.

- `futex_waitv` imports 1–128 entries before looking up the futex words. Each
  entry takes an aligned 32-bit word, an expected value, and a private or
  shared key. A mismatch returns `EAGAIN`. A wake returns a vector index.
- `futex_wait` adds a mask for waking an individual word. `futex_wake`
  selects waiters with intersecting masks. A zero count validates the mask
  and address without waking a waiter.
- `futex_requeue` compares the source word and can wake or transfer waiters.
  The source and destination select their private or shared keys independently.
  A transferred vector waiter keeps its original index and deadline.
- Both waits accept absolute monotonic and realtime deadlines. An unblocked
  signal interrupts the wait, and `SA_RESTART` restarts it with the original
  deadline. A concurrent wake that removed a node takes precedence over
  cancellation or timeout.

The ABI follows Linux 6.12's word sizes, flag validation and error order.
[Syscall implementation](https://github.com/torvalds/linux/blob/v6.12/kernel/futex/syscalls.c#L170-L412),
[wait and wake implementation](https://github.com/torvalds/linux/blob/v6.12/kernel/futex/waitwake.c#L355-L545).

`tests/linux-compat/run --cases futex2` exercises error order, the largest
vector, mixed key types, masks, a moved waiter, cleanup on failure or timeout,
signal interruption and restart, and wakeups across process boundaries. The
Vinix fixture measures live slab objects and large-page counts after 512 pairs
of maximum-size vectors. One has an expired deadline and a mismatching last
word. The other has an inaccessible last word. The same ELF runs under
`tests/linux-compat/syscall-reference.v --case futex2`.

## Qualification

The Vinix kernels were built from `3fb9fece2` plus the kernel changes in this
commit with `PROD=true` and `LIMINE_MP=1`. The reference kernels run Linux
6.12.51.

| Guest | Passing checks | Probe ELF | Kernel | Serial log |
| --- | --- | --- | --- | --- |
| Vinix AArch64 | 86 | `8c403f6679c4a7a1` | `6092334406bc7de7` | `ed16a66797c2798d` |
| Linux AArch64 | 80 | `8c403f6679c4a7a1` | `c8d8cdec004d4259` | `18d70629675445b2` |
| Vinix x86-64 | 86 | `9a109c859dd26741` | `83b57c2f500fc0e3` | `64e5d548a7a5facb` |
| Linux x86-64 | 80 | `9a109c859dd26741` | `ec9073e710b26f59` | `de4918b410ce3dec` |

Across the 512-cycle cohort, no live slab class grew. Large pages were 85 to
85 on AArch64 and 224 to 221 on x86-64. The kernel allocation checker reports
the existing futex-key and general timer allocations and no new allocation
sites in the changed code. The repository-wide allowance check still fails.

The existing `futex`, `futexkeys`, `futexbits`, `futexop`, and `futexerror`
cases passed on both architectures before the final monotonic timer change.
`futexqueue` passed on both final kernels. Two concurrent x86-64 runs of that
legacy probe reported a waiter timeout. The same probe ELF passed when run
sequentially on the earlier message-queue kernel and the final kernel.

Hashes above are SHA-256 prefixes. Receipts, full checksums and raw evidence are
under `~/.cache/vinix-r15/runs/futex2-{arm,x86}-{vinix,linux}-final`. The x86-64
requeue reruns are in `futex2-x86-requeue-baseline` and
`futex2-x86-requeue-isolated` under the same directory. The allocation
checker log is at `~/.cache/vinix-r15/futex2-arm/allocs-final.log`.

## Limits

Priority-inheritance queues remain separate from the ordinary wait queues.
Native tests cover shared resident words. Shared backing-page replacement and
operation through 32-bit or translated ABIs remain unqualified.
The vector allocation can return `ENOMEM`. Individual keys still use the
legacy futex table's kernel allocator.

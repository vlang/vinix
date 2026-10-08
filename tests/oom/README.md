# Running out of memory

Running out of memory costs a file write or a process, not the machine. Two
amounts of free memory are kept back (`kernel/memory/reserve.v`), both
pressure watermarks, so `/proc/vmpressure` shows the same lines:

- **A file's data leaves the high watermark.** tmpfs keeps its files in
  memory; a write that would go below the watermark fails with `ENOSPC`, and
  `statfs` reports the room above it. A full RAM-backed root still has memory
  to run programs in, the ones that make room on it included. A named file
  filled through a shared mapping stops at the same line, with a fault for
  the writer.
- **A process' own pages leave the critical watermark**, which only the
  kernel's allocations go below: page tables, slab pages, kernel stacks. They
  cannot fail. Anonymous memory, a process' copies of the files it maps, and
  the pages of a memfd or an unlinked file it maps are all its own.

A process that needs a page it cannot have gets a process killed for it
(`kernel/userland/oom.v`): the one with the most resident memory, weighed by
`/proc/<pid>/oom_score_adj` as Linux weighs it. -1000 exempts a process, init
is never chosen, and the process that has taken the screen (`KDSETMODE`, the
desktop) is chosen only when nothing else can be. The process asking is
chosen over a larger one that holds less than twice as much: its going ends
the demand, where a bystander's only feeds it. Whoever needed the page
waits for the memory and tries again; a thread of the process killed dies of
`SIGKILL`. The kernel names what it killed on the console:

    oom: out of memory: killed java[412], which held 1893 MiB

Before, writing a large file to the RAM root — installing a package on a
system booted from the ISO — took free memory down to nothing, and whatever
the kernel allocated next stopped the machine with `Out of memory after
reclaim`. Starting a program was enough.

## Where a thread waits

- A fault taken in userspace waits in its handler, with nothing held, and
  runs the instruction again.
- `mmap()` filling its own pages waits where it stands.
- The kernel copying to or from a process' page for some other syscall waits
  only with interrupts on, which no lock holder has. With them off — the
  whole of a syscall on arm64 — it takes the page from the upper half of the
  reserve, and what is to be killed is settled on the way out of the syscall.
- A fault the kernel itself takes on a process' page takes it from the
  reserve, as it did before there was one.

## The test

`guest.c` is PID 1 of a 1 GiB guest. It fills the root with one file and then
with small ones; takes all the memory there is from a child in each way a
process comes by it (small mappings, page faults, a `read(2)` into untouched
memory, four threads); has a process ask for memory beside an idle one that
holds far more, one that holds about as much, and one that owns the screen;
and fills a named file and a memfd through shared mappings. After each it checks what
was refused or killed, that a new process still starts, and that the memory
came back.

```sh
python3 tests/kernel-gaps/run.py --source tests/oom/guest.c --arch aarch64 \
    --kernel-dir kernel --expect 'OOM PASS all' --fail 'OOM FAIL' --timeout 500
python3 tests/kernel-gaps/run.py --source tests/oom/guest.c --arch x86_64 \
    --kernel-dir build-amd64-kernel --expect 'OOM PASS all' --fail 'OOM FAIL' \
    --timeout 1200
```

On a kernel without the reserves the first step leaves 0M free and the next
one panics.

## What is not covered

- Memory the kernel takes on a process' behalf is not charged to it: a
  process that makes a million empty files, or sockets, takes slab memory
  from the reserve, and killing it gives none of that back.
- On arm64, once less than half of the reserve is left, a syscall that needs
  an untouched page of its caller's paged in fails with `EFAULT` until the
  memory of the process killed comes back: it cannot wait there, and the
  rest of the reserve is the kernel's.
- A process reading another's memory (`process_vm_readv`) holds that address
  space while it waits; if the other is the one killed, it is waited for the
  full five seconds before another is chosen.
- Anonymous memory can now be compressed or stored on an explicitly activated
  encrypted swap device before process OOM recovery. Compression capacity and
  swap space are bounded; mapped-file eviction and kernel-resource charging
  remain incomplete. See [anonymous paging](../../docs/anonymous-paging.md).

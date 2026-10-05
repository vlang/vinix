# OpenBSD security features

Vinix borrows a number of OpenBSD's mitigations. They are on for every
process on both architectures, unless noted otherwise. `tests/openbsd-security/run.sh [aarch64|amd64]`
boots a kernel with a test program as PID 1 and checks the ones below.

## pledge(2)

A process promises which groups of system calls it will keep using. After
that, a call outside those groups kills it with an uncatchable `SIGABRT`, and
the kernel logs the promise the call needed:

```
/usr/bin/tool[42]: pledge "rpath", syscall 56
```

The promise names and their meanings are OpenBSD's: `stdio rpath wpath cpath
dpath tmppath inet mcast fattr chown flock unix dns getpw sendfd recvfd tty
proc exec prot_exec settime id route unveil error`. Vinix also accepts `tape
ps vminfo pf wroute audio video bpf vmm drm disklabel`; the ones with no
Linux counterpart grant nothing. Promises can only be narrowed. With `error`, a
refused call fails with `ENOSYS` and the process keeps running. Children
inherit their parent's promises. The `execpromises` become the promises of
the next program the process executes. If a process gave no `execpromises`,
the program it executes starts unpledged.

Because the syscalls are Linux's, deciding which promise a call needs is
Vinix's work, in `kernel/syscall/table/pledge*.v`. Where the argument that
decides it is in a register, it is checked at syscall entry: an ioctl request,
a socket's family, `PROT_EXEC`, `CLONE_THREAD`, a kill target. Calls that name
a file are judged once the file is resolved (`kernel/fs/policy.v`), as
OpenBSD's `namei` does:

| Access | Promise |
| --- | --- |
| open for reading, `getdents`, `readlink` | `rpath` |
| `stat`, `access`, `chdir`, `statfs` | `rpath` |
| open for writing, `O_TRUNC`, `truncate` | `wpath` |
| `O_CREAT`, `mkdir`, `unlink`, `rename`, `link`, `symlink` | `cpath` |
| `mknod` of a FIFO or device | `dpath` |
| `chmod`, `utimensat`, `setxattr` | `fattr` |
| `chown` | `chown` |
| binding or connecting an `AF_UNIX` socket by name | `unix` |

A few files are reachable without these promises, because libc opens them on
its own: `/dev/null`, `/etc/localtime` and `/usr/share/zoneinfo/`, `/dev/tty`
with `tty`, the password and group files with `getpw`, and the resolver's
files with `dns`. Vinix adds the Linux files the libcs use instead:
`/etc/nsswitch.conf`, `/dev/urandom`, and `/sys/devices/system/cpu/online`.
With `tmppath`, a process can create and remove files under `/tmp/`, as
`mkstemp(3)` does.

These are the differences from OpenBSD, all due to the Linux ABI:

- `stdio` allows `TCGETS` and `TIOCGWINSZ`, because musl and glibc make those
  calls to decide how to buffer stdout. OpenBSD's libc uses `fcntl(F_ISATTY)`
  instead.
- `clone3(2)` fails with `ENOSYS`, without being a violation. Its flags are in
  memory, where they could change after being checked. glibc then falls back
  to `clone(2)`, whose flags are in a register.
- `dns` without `inet` can create IPv4 sockets but can only send or connect
  to port 53.
- `io_uring`, AIO, `ptrace`, `bpf`, `userfaultfd`, `unshare`, `setns`,
  `mount` and SysV IPC are not covered by any promise.

## unveil(2)

The first call hides the whole filesystem except the path it names, with the
access it names: some of `r`, `w`, `x` and `c` (create or remove). Each later
call shows one more path. `unveil(NULL, NULL)` locks the view. A file is
judged by the unveiled path closest above it, and `""` hides a subtree. An
access that is not granted fails with `EACCES`. A path that is not unveiled
fails with `ENOENT`. `O_CREAT` needs `c`, as on OpenBSD, so `fopen(path, "w")`
needs `"wc"`.

Paths are resolved first, and the file the lookup ends at is what gets judged.
So a symbolic link cannot lead out of the view, and relative paths and
`*at()` calls work as expected. Unveiled paths are stored from the system
root, so a later `chroot(2)` does not rename them. `mount`, `umount2` and
`pivot_root` fail with `EPERM` once anything is unveiled. A hard link may not
grant more than the file's own name does, which prevents linking a read-only
file into a writable directory in order to write it. The kernel's own lookups
are not judged: the ELF interpreter, and on arm64 the x86 translator.

The view is inherited across `fork(2)`. `execve(2)` drops it, unless
`execpromises` are in effect, in which case the view carries over, as on
OpenBSD. A pledged process needs the `unveil` promise to call `unveil()`.

There is one difference from OpenBSD. The directories above an unveiled path
can be inspected with `stat(2)`, `access(2)` with `F_OK`, `readlink(2)` and
`chdir(2)`. glibc's `realpath()` and `getcwd()` fallbacks stat every
component. OpenBSD has a `__realpath` syscall so that its libc never needs to.
Inspecting a covered path needs any permission other than `""`.

## Signed signal frames

`rt_sigreturn(2)` loads every register from memory the program controls,
which makes it a useful gadget for an exploit. Sigreturn-oriented
programming forges a signal frame on the stack and calls it. As on OpenBSD,
every frame the kernel builds carries a cookie: a per-process secret XORed
with the frame's address. `rt_sigreturn` checks the cookie before it trusts
anything else in the frame, then clears it so that the frame cannot be
returned through twice. A frame that fails the check kills the process with
`SIGSEGV`. exec picks a new secret, and fork keeps it, because the child
returns through frames that were built for its parent's handlers.

On amd64 the cookie is in the first word of `sigcontext.reserved1`, which
Linux leaves zero and libc never reads. On arm64 it is in the kernel-private
header at the start of the frame, and `rt_sigreturn` also refuses a
ucontext pointer other than the one the kernel wrote. The native Vinix
signal ABI on arm64 is covered too.

A glibc program on arm64 returns from its handlers through a page the kernel
maps, because glibc leaves `sa_restorer` unset. That page used to be at a
fixed address. It now sits at a random page in the gigabyte above the stack,
chosen for each program, much as OpenBSD places its signal trampoline.

## Random process IDs

Once init has pid 1, process and thread IDs are random, as OpenBSD has
made them since 1997, so the next process's pid is not a guess away from the
last one. An ID released in the last 128 is not handed out again, like
OpenBSD's `oldpids`. Neither is one that still names a live process group or
session, which Vinix already checked. If random picks keep landing on
taken IDs in a nearly full table, allocation falls back to the old
sequential scan. PID namespaces number their processes on their own, so
container init is still pid 1 inside the container.

## Random program break

The heap `brk(2)` grows used to start at `0x60000000000` in every process.
Now each program's break starts at a random page in the first 256 MiB of its
arena, as OpenBSD randomizes the start of the data segment. This joins the
randomized PIE base, interpreter base, stack top and `mmap` placement Vinix
already had. On amd64, exec now resets the break and fork copies it, which
arm64 already did.

## Kernel stack protector

The kernel is built with `-fstack-protector-strong`, as OpenBSD has built
its kernel with ProPolice since 2003. Every kernel function with a buffer or
an address-taken local keeps a copy of a secret guard below its return
address, and checks it before returning. If an overflow reached the return
address, the check fails and the kernel panics instead of returning into
whatever was written there. The guard is global (`-mstack-protector-guard=global`),
because the x86-64 default reads it through `%fs`, which in the kernel
belongs to userspace.

`kmain()` calls `vinix_stack_guard_init()` (`kernel/lib/stack_protector.v`)
before anything that will return. It mixes RDRAND (amd64) or RNDR (arm64,
where the CPU has FEAT_RNG) with the cycle counter and the boot stack's
address. The M1 has no RNDR, so there the guard depends on the counter's
jitter since reset. The guard's lowest byte is zero, as glibc makes it, so an
overflow through a string function stops at the terminator it would have to
write there.

## A read-only direct map of the kernel

The kernel maps all of physical memory at one more address, the direct map,
and mapped every page of it writable. That included the pages holding the
kernel's own code and read-only data: W^X at the kernel's addresses, but
writable through their alias. Anything able to write kernel memory at a chosen
address could have patched the kernel's code that way. As OpenBSD and Linux
keep them, those pages are now read-only in the direct map, and not
executable. A write through the alias faults on both architectures.

## The kernel's random generator

The kernel's generator is ChaCha20, as OpenBSD's arc4random is, and it now
works the way arc4random does:

- Fast key erasure. The key that produced a request is replaced before the
  next request can be served, from a block no caller sees. Someone who reads
  the generator's state later cannot work back to output it already gave.
- Reseeding. The generator used to run for the machine's whole life on its
  boot seed, so a state read out once predicted everything after it. Now it
  pools the timing of events, scheduler ticks and keystrokes, as OpenBSD's
  random(4) pools interrupt timings. Half a minute after boot, and every five
  minutes after that, it hashes the key, the pool and whatever the CPU's own
  generator offers (RDSEED or RDRAND, or RNDR where arm64 has it) into a new
  key. A generator that booted without a trustworthy seed becomes ready once
  the CPU contributes one.
- Explicit erasure. Keys, seeds and working blocks are cleared with
  `explicit_bzero`, whose stores the compiler cannot remove as dead.

`tests/krandom/run.sh` runs the generator's own code on the host against
ChaCha20 test vectors and checks each of these.

## minherit(2) and fork-time wiping

A forked child used to get a copy of everything its parent had mapped,
including a user-space random generator's state: parent and child then
produced the same "random" bytes. OpenBSD's `minherit(2)` lets a program say
what fork does with a range, and Linux's `madvise(2)` has the same advice, so
both are there:

- `MAP_INHERIT_ZERO`, `MADV_WIPEONFORK`: the child gets the range filled
  with zeros. The setting stays with the child's copy. Only private anonymous
  memory can be wiped (EINVAL otherwise), as on Linux.
- `MAP_INHERIT_NONE`, `MADV_DONTFORK`: the range is not mapped in the child
  at all.
- `MAP_INHERIT_COPY`, `MAP_INHERIT_SHARE`, `MADV_KEEPONFORK`,
  `MADV_DOFORK` undo those. COPY is accepted only for a private mapping and
  SHARE only for a shared one: the kernel does not turn one into the other.

A request that covers a hole fails with ENOMEM, and one that covers an
immutable range fails with EPERM; either way nothing changes. The setting
moves with a range that `mremap(2)` moves, and exec clears it. `minherit`
needs only the `stdio` promise. OpenBSD's arc4random keeps its state in a
`MAP_INHERIT_ZERO` range, and finding it zeroed after a fork is how it knows
to rekey instead of repeating its parent.

## Random ports, sequence numbers and IP IDs

The kernel's IP stack, lwIP, made up the numbers in its packets the
predictable way. OpenBSD has made each of them random for more than twenty
years, and so does Vinix now (`kernel/socket/inet/net_random.v`):

- **IP IDs.** lwIP numbered datagrams one after another, so anyone who saw
  two of them knew how much else the machine had sent in between, which is
  what an idle scan measures. Each datagram now leaves with an ID from
  OpenBSD's `ip_randomid()`: a shuffle of every ID, read in order, with the
  one just used swapped back into a random place among the 32768 before it.
  No ID comes back within 32768 datagrams, and the next one cannot be told
  from those before. The fragments of a datagram share its ID.
- **TCP initial sequence numbers.** lwIP added the ticks since boot to the
  last one it gave out, so the next connection's could be guessed, and a
  connection forged or reset by someone who could not see its packets. They
  are RFC 6528's now: a clock that ticks every 4 microseconds, plus
  SipHash-2-4 of the connection's addresses and ports under a key made at the
  first connection. OpenBSD's `tcp_set_iss_tsm()` does the same with SHA-512.
- **Ephemeral ports.** A socket that was bound to port 0, or that connected,
  listened or sent without being bound, got the port after the last one
  handed out. Now it gets a free port picked at random from 49152-65535, as
  OpenBSD's `in_pcbpickport()` picks them, so that poisoning a resolver's
  cache means guessing the port its query came from as well as the query's
  ID. `listen(2)` on an unbound socket now binds it too, as on Linux.
- **lwIP's own random numbers**, behind its DNS query IDs and ports and
  DHCP's transaction IDs, came from an xorshift seeded from the clock. They
  come from the kernel's ChaCha20 generator now, a few blocks at a time, with
  each byte cleared from the buffer as it is used.

`tests/net-random/run.sh` checks the code on the host: the SipHash test
vectors, that no ID repeats within 32768, how the sequence numbers move with
the clock and the ports. The QEMU test captures what the guest sends to the
host and checks the sequence numbers, source ports and IP IDs on the wire.

## Writes to freed kernel memory

The kernel's slab allocator fills a freed object with `0xaa`, and refuses a
double free. Now it also checks that poison, as OpenBSD's `malloc(9)` checks
its free lists: a slot about to be handed out again, and every slot of an
empty page about to go back to the page allocator, must still hold it. A
freed object that something went on writing to, a use-after-free that would
otherwise show up as its next owner's data changing under it, is reported in
the kernel log with its size, its address, the first offset that changed and
what was written there:

```
Slab: 192-byte object 0xffff0000a15e5af0 written after it was freed: 0xaaaaaaaaaaaaaaa9 at offset 136
```

That one came from a desktop session: devtmpfs had freed a terminal's
`/dev/pts/N` node while the shell still had it open, and the shell's exit
then took one off the node's count of open files, at offset 136. As
OpenBSD's does, the kernel carries on, and the slot goes to its new owner
zeroed. The first 32 are described; `/proc/slabinfo` counts them all on its
last line, `# written after free`. New slab pages are poisoned when they are
made, so that every free slot holds the poison. The check takes the place of
the zeroing of each allocation and makes one pass over the object, as the
zeroing did. A kernel built with `-d heap_selftest` writes to a freed object
at boot and checks that it is caught.

## Read-only descriptors that nothing writes through

A descriptor opened without write access could still reach the file behind
it for writing, three ways, all now closed:

- `mprotect(2)` never looked at what a mapping was made from, so a
  `MAP_SHARED`, `PROT_READ` mapping of a file opened `O_RDONLY` could be
  raised to `PROT_WRITE` and written through. Such a mapping, and a
  `shmat(2)` with `SHM_RDONLY`, now carry a flag that forks, splits and
  `mremap(2)` keep, and `mprotect` refuses `PROT_WRITE` over it with
  `EACCES`, as Linux does by clearing `VM_MAYWRITE`. A private mapping, a
  copy, may still be made writable.
- `copy_file_range(2)`, `splice(2)`, `tee(2)` and `vmsplice(2)` went
  straight to the files' own read and write, which do not check the
  descriptor's access mode, so one opened only for reading could be written
  and one opened only for writing could be read. They now need the source
  open for reading and the sink for writing, `EBADF` otherwise, and
  `copy_file_range` refuses an `O_APPEND` sink.
- An `O_PATH` descriptor, which is opened with no permission to the file at
  all, could be `mmap(2)`ed and so gave up the file's contents. It is now
  refused with `EBADF`, as on Linux.

SysV shared memory had no permission checks at all: any process could attach,
read and write another user's segment, or take it over with `IPC_SET` or
`IPC_RMID`. `shmget`, `shmat` and `shmctl` now apply the segment's mode and
ownership, as Linux's `ipcperms()` does.

## Memory layouts kept from other users

`/proc/<pid>/maps`, `smaps` and `auxv` say where a process's program,
libraries, stack and heap are, and every user could read them for every
process, which undid all of the randomization above for a local attacker.
They are now for the process itself, for a process whose user and group IDs
are all the reader's effective IDs, and for a reader with `CAP_SYS_PTRACE`,
as Linux's ptrace check has it. Anyone else's read fails with `EACCES`. The
rest of `/proc/<pid>`, `stat` and `status` among them, stays public.

## Immutable and append-only files

A file can be sealed, with `chattr(1)`'s `+i` and `+a`, as OpenBSD seals one
with `schg` and `sappnd`:

- An **immutable** file cannot be changed in any way -- not its data, its
  mode, its owner, its times, its extended attributes or its name -- and
  nothing can be made or removed in an immutable directory. A write, chmod,
  chown, truncate, rename, unlink or hard link to it fails with `EPERM`.
- An **append-only** file opens for writing only in append mode, never to be
  truncated, and cannot be deleted or renamed; its metadata may still change.
  An append-only directory takes new entries but gives none up.

The bits are Linux's `FS_IMMUTABLE_FL` and `FS_APPEND_FL`, set and read with
`FS_IOC_SETFLAGS` and `FS_IOC_GETFLAGS` (what `chattr` and `lsattr` use), and
kept per inode: on tmpfs in memory, on ext2 in the on-disk `i_flags`, where
they are the same bit values, so a sealed file on disk stays sealed across a
remount. Setting them needs `CAP_LINUX_IMMUTABLE`.

The enforcement is at every place a file or a directory entry changes, beside
the read-only-mount checks already there, since a resolved symbolic link must
not redirect the operation past the check.

## securelevel

`kern.securelevel`, at `/proc/sys/kernel/securelevel`, is OpenBSD's lock on
the running system:

| | |
| --- | --- |
| -1 | permanently insecure: as 0, and init does not raise it |
| 0 | insecure: the usual permissions, the default |
| 1 | secure: a set immutable or append-only bit cannot be cleared, even by root |
| 2 | highly secure: as 1 |

It can always be raised, by root with `CAP_SYS_ADMIN`; once it is above 0,
only `init` (pid 1) can lower it, as OpenBSD lowers it on the way to
single-user mode. So a file sealed immutable at securelevel 1 stays sealed for
as long as the machine runs multi-user, which is what `schg` at securelevel 1
guarantees on OpenBSD.

`tests/openbsd-security` seals a file and a directory immutable and
append-only, checks that each kind of change is refused, and that at
securelevel 1 the bits can no longer be cleared.

## Checked copies to and from userspace

OpenBSD never dereferences a pointer a process gave it: every transfer goes
through `copyin`/`copyout`, which check the address. Vinix now does the same.
`kernel/usercopy` resolves each page through the process's page tables and
copies through the kernel's own mapping of the page, so a pointer that leads
nowhere, to a page the process may not write, or into the kernel's half of the
address space is `EFAULT`.

Three things were wrong before, in rising order:

- A syscall that wrote its result straight through a user pointer took a fault
  in the kernel when the pointer was bad, and a fault at a user address taken
  in the kernel had no handler: `fstat(fd, (void *)1)` from any process stopped
  the machine. `fstat`, `fstatat`, `stat`, `lstat`, `statx`, `getcwd`,
  `getdents64`, `getitimer`, `setitimer`, `readlinkat`, `socketpair`,
  `getsockname`, `getpeername` and the block, framebuffer, sound and socket
  `ioctl`s now build their result in the kernel and copy it out.
- A path, an `execve` argument or an environment string was read where the
  process had it, to whatever came first: a terminator or the end of mapped
  memory. They are copied in now, a page at a time, with `PATH_MAX` for a path
  and Linux's limits for `execve`: 128 KiB a string, 2 MiB for both vectors. A
  null `argv` or `envp` is an empty one, as on Linux; it used to be a kernel
  fault.
- `read(2)` and `write(2)` on anything but a regular file, and the socket
  calls, handed the caller's buffer to the driver, which copied to or from
  that address as it stood, whatever it was. `write(pipe, kernel_address, n)`
  put `n` bytes of kernel memory in the pipe for the process to read back, and
  `read(pipe, kernel_address, n)` wrote the pipe's bytes over the kernel's.

So the rule is now the kernel's own, rather than each driver's: a resource's
`read` and `write`, and every socket family, are given kernel memory only.
`read`, `write`, `readv`, `writev`, `pread`, `pwrite`, `sendto`, `recvfrom`,
`sendmsg`, `recvmsg`, `sendmmsg` and `recvmmsg` go through a kernel buffer at
the syscall, and so do a socket call's addresses, its message header, its
vectors and its ancillary data. What a pipe, a socket or a device gives up is
gone from it, so a read first checks that there is somewhere to put it: a
failed read takes nothing. The calls the kernel builds on its own buffers,
`sendfile` and `writev`, have their own way in, so that an address is never
judged the kernel's or the process's by its value.

`writev` and `sendmsg` also sized a kernel allocation by the lengths in the
caller's vector, as large as the caller liked. They gather 1 MiB at a time
now: a stream takes that much and says so, and a datagram that is longer is
`EMSGSIZE`, as it was. A socket address is copied in at no more than its
family's size: a `sockaddr_un` longer than the structure, which used to run
past the name the kernel keeps for a socket, is `EINVAL`.

`tests/openbsd-security` makes each of these calls with an unmapped buffer and
with a kernel address, checks for `EFAULT`, checks that the pipe or socket
lost nothing to the failed call, and that transfers larger than one kernel
buffer, datagrams and records, scattered messages and passed descriptors still
arrive whole.

## SMAP and PAN

With every transfer going through `usercopy`, the kernel has no reason to
touch a page of a process at the process's own address, and the CPU can be
told so. OpenBSD has run with SMAP since 5.3. Vinix turns on SMAP on amd64,
on any CPU that has it, and PAN on arm64 (ARMv8.1): while the bit is set, an
access from the kernel to a page userspace can reach faults. A kernel bug
that follows a pointer an attacker chose -- a null function table, a
corrupted object -- can no longer be steered at memory the attacker prepared.

On amd64 the bit holds only while `EFLAGS.AC` is clear. `SYSCALL` clears it
through the flags mask, and every interrupt entry executes `CLAC`, since
userspace can set AC and an interrupt leaves it as it was. On arm64, clearing
`SCTLR_EL1.SPAN` has every exception into the kernel set `PSTATE.PAN`, and
kernel threads start with it set and keep it across a sleep.

`vinix.user_access=` on the kernel command line chooses what a violation
does:

| | |
| --- | --- |
| `strict` | the fault is a kernel fault, as on OpenBSD. The default |
| `audit` | the access is let through, and the kernel address is logged, once for each path |
| `off` | the bit stays clear |

An audit is how the conversion was done, and how to find a path it missed. The
log has a `user-access:` line for each one, and
`tests/user-access/sites.py kernel/bin/vinix < serial.log` names the function
and what called it:

```
wrote memcpy < pipe__Pipe__read < resource__Resource__read < file__Handle__read < fs__syscall_read
read  stubs__strlen < strlen < vstrlen < tos2 < cstring_to_vstring < fs__user_path < fs__syscall_openat
```

`VINIX_CMDLINE=vinix.user_access=audit` passes the option through
`scripts/run-aarch64.sh` and the amd64 test ISO. A debug kernel (`PROD=false`) audits
unless told otherwise, since it traces each syscall's path argument where the
process has it.

On Apple hardware the kernel runs at EL2. PAN works the same way there, but
it has only been run at EL1, under QEMU, so on those machines it stays off
until `vinix.user_access=audit` or `strict` asks for it.

## Already in place

These came before and are unchanged: W^X for user mappings, `mimmutable(2)`
and immutable ELF text, randomized `mmap`, PIE, interpreter and stack
placement, SMEP, UMIP, NXE and `CR0.WP` on amd64, and PXN on every user page
on arm64.

Not yet: `MAP_STACK` checking and syscall-origin pinning (`pinsyscalls`) would
break Go and statically linked Linux programs, which make syscalls from their
own text and run on stacks that were never mapped with `MAP_STACK`. Mapping
program text execute-only (`xonly`) is native on arm64 but needs memory
protection keys on amd64, and risks Linux binaries that read their own text.

## Calling them

The syscall numbers sit next to `mimmutable(2)`, in ranges Linux leaves
unused:

| | arm64 | amd64 |
| --- | --- | --- |
| `mimmutable` | 247 | 500 |
| `pledge` | 248 | 501 |
| `unveil` | 249 | 502 |
| `minherit` | 250 | 503 |

```c
#include <sys/syscall.h>
#include <unistd.h>

#if defined(__aarch64__)
#define SYS_pledge 248
#define SYS_unveil 249
#define SYS_minherit 250
#else
#define SYS_pledge 501
#define SYS_unveil 502
#define SYS_minherit 503
#endif

static int pledge(const char *promises, const char *execpromises)
{
	return syscall(SYS_pledge, promises, execpromises);
}

static int unveil(const char *path, const char *permissions)
{
	return syscall(SYS_unveil, path, permissions);
}

static int minherit(void *addr, size_t len, int inherit)
{
	return syscall(SYS_minherit, addr, len, inherit);
}
```

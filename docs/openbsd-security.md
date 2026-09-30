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

`kmain()` calls `vinix_stack_guard_init()` (`kernel/c/stack_protector.c`)
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

## Already in place

These came before and are unchanged: W^X for user mappings, `mimmutable(2)`
and immutable ELF text, randomized `mmap`, PIE, interpreter and stack
placement, checked copies to and from userspace in a growing number of
syscalls, SMEP, UMIP, NXE and `CR0.WP` on amd64, and PXN on every user page
on arm64.

Not yet: SMAP and PAN need the kernel's remaining direct dereferences of user
pointers converted to checked copies first. `fstatat` still writes its
`struct stat` straight to the user's buffer, for example. `MAP_STACK`
checking and syscall-origin pinning (`pinsyscalls`) would break Go and
statically linked Linux programs, which make syscalls from their own text
and run on stacks that were never mapped with `MAP_STACK`.

## Calling them

The syscall numbers sit next to `mimmutable(2)`, in ranges Linux leaves
unused:

| | arm64 | amd64 |
| --- | --- | --- |
| `mimmutable` | 247 | 500 |
| `pledge` | 248 | 501 |
| `unveil` | 249 | 502 |

```c
#include <sys/syscall.h>
#include <unistd.h>

#if defined(__aarch64__)
#define SYS_pledge 248
#define SYS_unveil 249
#else
#define SYS_pledge 501
#define SYS_unveil 502
#endif

static int pledge(const char *promises, const char *execpromises)
{
	return syscall(SYS_pledge, promises, execpromises);
}

static int unveil(const char *path, const char *permissions)
{
	return syscall(SYS_unveil, path, permissions);
}
```

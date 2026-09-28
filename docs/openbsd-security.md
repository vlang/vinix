# OpenBSD security features

Vinix borrows a number of OpenBSD's mitigations. They are on for every
process on both architectures, unless noted otherwise. `tests/openbsd-security/run.sh [aarch64|amd64]`
boots a kernel with a test program as PID 1 and checks them.

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

## Calling them

The syscall numbers sit next to `mimmutable(2)`, in ranges Linux leaves
unused:

| | arm64 | amd64 (Linux ABI) | amd64 (Vinix ABI) |
| --- | --- | --- | --- |
| `mimmutable` | 247 | 500 | 49 |
| `pledge` | 248 | 501 | 66 |
| `unveil` | 249 | 502 | 67 |

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

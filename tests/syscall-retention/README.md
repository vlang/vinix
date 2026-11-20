# Repeated syscall retention

Every repeated syscall path must give back what it allocates. This guest runs
each operation 200 times to warm it, waits out two removal grace periods,
snapshots every slab class and the large-page count, runs it 200 more times
and settles again. A slab class that grows by more than 8 objects (a leak of
one object per call grows by the run count) or more than one large page fails
the run and, on an `ALLOC_TRACK=1` kernel, prints the live allocation sites as
`PERF-SITE` lines for `tests/kernel-allocs/sites`.

The operations complement `tests/desktop-perf` ops, which covers pipes,
sockets, epoll, timers, threads, fork and file creation:

- procfs per-process files (status, stat, maps, limits, io, cgroup,
  mountinfo, mounts, auxv), system files (meminfo, cpuinfo, mounts,
  kernel-resources, sys/kernel, net) and magic links;
- a 48-file sysfs walk (100 runs);
- statfs, sysinfo, uname, getrandom, rlimits, rusage, affinity, prctl,
  getcwd and gethostname;
- pipe and console ioctls, /dev/null and /dev/urandom reads;
- sethostname followed by uname, which must report the new name;
- SysV semaphores and shared memory, PTY pairs, signalfd, POSIX timers,
  netlink route dumps, SCM_RIGHTS passing and socket options;
- anonymous mprotect/madvise/mremap and a sealed, synced memfd mapping;
- creating and removing a cgroup;
- xattrs, flock/POSIX/OFD locks, inotify and metadata changes (chmod,
  chown, utimens, truncate, fsync), and sendfile/copy_file_range/splice
  between two files, on tmpfs and on ext2. The runner formats a
  fresh 64 MiB ext2 image with e2fsprogs and attaches it, and the kernel
  mounts it at `/root`; if `/root` is still not ext2 the guest says so and
  skips those.

Build the kernels as for `tests/memory-retention`, then:

```sh
tests/syscall-retention/run --arch aarch64 --kernel-dir /work/arm/kernel --state-dir /tmp/syscall-arm
tests/syscall-retention/run --arch x86_64 --kernel-dir /work/x86/kernel --state-dir /tmp/syscall-x86
```

The runner requires `SYSCALL RETENTION: PASS`, rejects `SYSCALL RETENTION
FAIL`, panics and fatal exceptions, and allows 3000 seconds: each of the 27
measured operations waits about half a minute. AArch64 builds the guest
against `VINIX_AARCH64_SYSROOT` (default `build-aarch64-userland/sysroot`).

When it was added (2026-11-20) it found `sethostname` keeping a copy of the
name and `uname` keeping one per call (4a7fd6664); /proc/<pid>/mountinfo and
/proc/cpuinfo reads had kept two objects each until 8c9c608ed.

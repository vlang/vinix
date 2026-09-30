// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// pledge(2) for the Linux x86-64 syscall numbers. See pledge.v for how a
// call's promise is decided, and proc/pledge.v for what the promises are.
module table

import proc
import x86.cpu.local as cpulocal

// The promise the call `nr` needs, given its arguments. Anything not listed
// is allowed by no promise.
fn pledge_needs(nr u64, a [6]u64) u64 {
	return match nr {
		// read, write, close, fstat, poll, lseek.
		0, 1, 3, 5, 7, 8 { pledge_stdio }
		// open, stat, lstat, access, creat, openat, newfstatat, faccessat,
		// statx, openat2, faccessat2: judged once the file is found, since
		// the whitelist in proc/pledge.v may allow them.
		2, 4, 6, 21, 85, 257, 262, 269, 332, 437, 439 { pledge_stdio }
		9, 10, 329 { pledge_prot(a[2]) } // mmap, mprotect, pkey_mprotect
		// munmap, brk, rt_sigaction, rt_sigprocmask, rt_sigreturn.
		11...15 { pledge_stdio }
		16 { pledge_ioctl(a[1]) }
		// pread64, pwrite64, readv, writev.
		17...20 { pledge_stdio }
		// pipe, select, sched_yield, mremap, msync, mincore, madvise.
		22...28 { pledge_stdio }
		// dup, dup2, pause, nanosleep, getitimer, alarm, setitimer, getpid,
		// sendfile.
		32...40 { pledge_stdio }
		41 { pledge_socket(a[0], a[2]) } // socket
		42 { pledge_socket_fd(a[0], true) } // connect
		43, 49, 50, 288 { pledge_socket_fd(a[0], false) } // accept, bind, listen, accept4
		44 { if a[4] == 0 { pledge_stdio } else { pledge_socket_fd(a[0], true) } } // sendto
		// recvfrom, sendmsg, recvmsg, shutdown, getsockname, getpeername,
		// socketpair.
		45...48, 51, 52, 53 { pledge_stdio }
		54, 55 { pledge_sockopt(a[1], a[2]) } // setsockopt, getsockopt
		56 { pledge_clone(a[0]) } // clone
		57, 58 { p_proc } // fork, vfork
		59, 322 { p_exec } // execve, execveat
		60, 231 { pledge_always } // exit, exit_group
		61, 63 { pledge_stdio } // wait4, uname
		62, 129, 234, 297 { pledge_kill(a[0]) } // kill, rt_sigqueueinfo, tgkill, rt_tgsigqueueinfo
		72 { pledge_fcntl(a[1]) }
		73 { p_flock } // flock
		74, 75, 77 { pledge_stdio } // fsync, fdatasync, ftruncate
		76 { p_wpath } // truncate
		78, 80, 81, 89, 137, 138, 217, 267 { p_rpath } // getdents, chdir, fchdir, readlink, statfs, fstatfs, getdents64, readlinkat
		79 { p_rpath | p_wpath } // getcwd
		// rename, mkdir, rmdir, link, symlink, mkdirat, renameat, linkat,
		// symlinkat, renameat2.
		82, 83, 84, 86, 88, 258, 264, 265, 266, 316 { p_cpath }
		// unlink, unlinkat: "tmppath" may remove what mkstemp() made under
		// /tmp, which fs/policy.v judges by the path.
		87, 263 { p_cpath | proc.pledge_tmppath }
		// chmod, fchmod, utime, utimes, fchmodat, futimesat, utimensat,
		// fchmodat2.
		90, 91, 132, 235, 268, 261, 280, 452 { p_fattr }
		92, 93, 94, 260 { p_chown } // chown, fchown, lchown, fchownat
		// umask, gettimeofday, getrlimit, getrusage, sysinfo, times, getuid,
		// getgid, geteuid, getegid, getppid, getpgrp, getgroups, getresuid,
		// getresgid, getpgid, getsid, capget.
		95...100, 102, 104, 107, 108, 110, 111, 115, 118, 120, 121, 124, 125 { pledge_stdio }
		// setuid, setgid, setreuid, setregid, setgroups, setresuid,
		// setresgid, setfsuid, setfsgid, capset.
		105, 106, 113, 114, 116, 117, 119, 122, 123, 126 { p_id }
		109, 112 { p_proc } // setpgid, setsid
		// rt_sigpending, rt_sigtimedwait, rt_sigsuspend, sigaltstack.
		127, 128, 130, 131 { pledge_stdio }
		133 { pledge_mknod(a[1]) } // mknod
		259 { pledge_mknod(a[2]) } // mknodat
		140, 143, 145...148 { pledge_stdio } // getpriority, sched_getparam, sched_getscheduler, sched_get_priority_*, sched_rr_get_interval
		141, 160 { p_proc | p_id } // setpriority, setrlimit
		142, 144, 203, 314 { pledge_sched_target(a[0]) } // sched_setparam, sched_setscheduler, sched_setaffinity, sched_setattr
		149...152 { pledge_stdio } // mlock, munlock, mlockall, munlockall
		157 { pledge_prctl(a[0]) }
		158 { pledge_stdio } // arch_prctl: the calling thread's FS and GS
		159, 164, 227, 305 { p_settime } // adjtimex, settimeofday, clock_settime, clock_adjtime
		162, 186, 187 { pledge_stdio } // sync, gettid, readahead
		188, 189, 190, 197, 198, 199 { p_fattr } // setxattr family, removexattr family
		191...196 { p_rpath } // getxattr, listxattr families
		200 { pledge_tkill(a[0]) } // tkill
		// time, futex, sched_getaffinity, set_thread_area, get_thread_area,
		// epoll_create, remap_file_pages, set_tid_address, restart_syscall,
		// fadvise64, timer_*, clock_gettime, clock_getres, clock_nanosleep,
		// epoll_wait, epoll_ctl, mbind, set_mempolicy, get_mempolicy, waitid.
		201, 202, 204, 205, 211, 213, 216, 218, 219, 221...226, 228, 229, 230, 232, 233, 237,
		238, 239, 247 {
			pledge_stdio
		}
		251 { p_proc } // ioprio_set
		252, 253, 255 { pledge_stdio } // ioprio_get, inotify_init, inotify_rm_watch
		254 { p_rpath } // inotify_add_watch
		256, 279, 424, 434, 440, 448 { p_proc } // migrate_pages, move_pages, pidfd_*, process_madvise, process_mrelease
		// pselect6, ppoll, set_robust_list, get_robust_list, splice, tee,
		// sync_file_range, vmsplice.
		270, 271, 273...278 { pledge_stdio }
		// epoll_pwait, signalfd, timerfd_create, eventfd, fallocate,
		// timerfd_settime, timerfd_gettime.
		281...287 { pledge_stdio }
		// signalfd4, eventfd2, epoll_create1, dup3, pipe2, inotify_init1,
		// preadv, pwritev.
		289...296 { pledge_stdio }
		299, 306, 307, 309 { pledge_stdio } // recvmmsg, syncfs, sendmmsg, getcpu
		302 { pledge_rlimit(a[2]) } // prlimit64
		315 { pledge_stdio } // sched_getattr
		// seccomp (only narrows), getrandom, memfd_create.
		317, 318, 319 { pledge_stdio }
		// membarrier, mlock2, copy_file_range, preadv2, pwritev2, pkey_alloc,
		// pkey_free.
		324...328, 330, 331 { pledge_stdio }
		334 { pledge_stdio } // rseq
		435 { pledge_unsupported } // clone3
		436, 441 { pledge_stdio } // close_range, epoll_pwait2
		444, 445, 446 { pledge_stdio } // landlock: only narrows
		// memfd_secret, futex_waitv, set_mempolicy_home_node, cachestat,
		// map_shadow_stack, futex2, mseal.
		447, 449, 450, 451, 453, 454, 455, 456, 462 { pledge_stdio }
		// Vinix: mimmutable, pledge, unveil, minherit.
		500, 503 { pledge_stdio }
		501 { pledge_always }
		502 { proc.pledge_unveil }
		else { pledge_never }
	}
}

// Called by syscall_trace() on every syscall of a pledged process. Answers the
// table slot to run: the call itself, or the stand-in that returns the errno
// the call was refused with.
fn pledge_entry(mut t proc.Thread, frame &cpulocal.GPRState, nr u64) u64 {
	t.pledge_syscall = i64(nr)
	code := pledge_verdict(pledge_needs(nr, [frame.rdi, frame.rsi, frame.rdx, frame.r10, frame.r8,
		frame.r9]!))
	if code == 0 {
		return nr
	}
	t.seccomp_errno = code
	return seccomp_verdict_nr
}

// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// pledge(2) for the Linux AArch64 syscall numbers (asm-generic). See
// pledge.v for how a call's promise is decided, and proc/pledge.v for what
// the promises are.
module table

import proc
import aarch64.cpu.local as cpulocal

// The promise the call `nr` needs, given its arguments. Anything not listed
// is allowed by no promise, which is what pledge(2) does with a call it does
// not know.
fn pledge_needs(nr u64, a [6]u64) u64 {
	return match nr {
		// setxattr, lsetxattr, fsetxattr; removexattr, lremovexattr,
		// fremovexattr.
		5, 6, 7, 14, 15, 16 { p_fattr }
		// getxattr .. flistxattr.
		8, 9, 10, 11, 12, 13 { p_rpath }
		17 { p_rpath | p_wpath } // getcwd
		// eventfd2, epoll_create1, epoll_ctl, epoll_pwait, dup, dup3.
		19, 20, 21, 22, 23, 24 { pledge_stdio }
		25 { pledge_fcntl(a[1]) }
		26, 28 { pledge_stdio } // inotify_init1, inotify_rm_watch
		27 { p_rpath } // inotify_add_watch
		29 { pledge_ioctl(a[1]) }
		30 { p_proc } // ioprio_set
		31 { pledge_stdio } // ioprio_get
		32 { p_flock } // flock
		33 { pledge_mknod(a[2]) } // mknodat
		34, 36, 37, 38 { p_cpath } // mkdirat, symlinkat, linkat, renameat
		// unlinkat: "tmppath" may remove what mkstemp() made under /tmp,
		// which fs/policy.v judges by the path.
		35 { p_cpath | proc.pledge_tmppath }
		43, 44 { p_rpath } // statfs, fstatfs
		45 { p_wpath } // truncate
		46, 47 { pledge_stdio } // ftruncate, fallocate
		// faccessat, openat, newfstatat: judged once the file is found, since
		// the whitelist may allow them. musl's fstat() is
		// newfstatat(fd, "", AT_EMPTY_PATH), which names no file at all.
		48, 56, 79 { pledge_stdio }
		49, 50 { p_rpath } // chdir, fchdir
		52, 53 { p_fattr } // fchmod, fchmodat
		54, 55 { p_chown } // fchownat, fchown
		57, 59 { pledge_stdio } // close, pipe2
		61 { p_rpath } // getdents64
		// lseek, read, write, readv, writev, pread64, pwrite64, preadv,
		// pwritev, sendfile, pselect6, ppoll, signalfd4, vmsplice, splice, tee.
		62...77 { pledge_stdio }
		78 { p_rpath } // readlinkat
		// fstat, sync, fsync, fdatasync, sync_file_range, timerfd_*.
		80...87 { pledge_stdio }
		88 { p_fattr } // utimensat
		90 { pledge_stdio } // capget
		91 { p_id } // capset
		93, 94 { pledge_always } // exit, exit_group
		// waitid, set_tid_address.
		95, 96 { pledge_stdio }
		// futex, set_robust_list, get_robust_list, nanosleep, getitimer,
		// setitimer.
		98...103 { pledge_stdio }
		107...111 { pledge_stdio } // timer_*
		112 { p_settime } // clock_settime
		113, 114, 115 { pledge_stdio } // clock_gettime, clock_getres, clock_nanosleep
		118, 119, 122 { pledge_sched_target(a[0]) } // sched_setparam, sched_setscheduler, sched_setaffinity
		// sched_getscheduler, sched_getparam, sched_getaffinity, sched_yield,
		// sched_get_priority_max/min, sched_rr_get_interval, restart_syscall.
		120, 121, 123...128 { pledge_stdio }
		129, 138 { pledge_kill(a[0]) } // kill, rt_sigqueueinfo
		130 { pledge_tkill(a[0]) } // tkill
		131, 240 { pledge_kill(a[0]) } // tgkill, rt_tgsigqueueinfo: by thread group
		// sigaltstack, rt_sigsuspend, rt_sigaction, rt_sigprocmask,
		// rt_sigpending, rt_sigtimedwait.
		132...137 { pledge_stdio }
		139 { pledge_stdio } // rt_sigreturn
		140, 164 { p_proc | p_id } // setpriority, setrlimit
		141, 163, 165, 166 { pledge_stdio } // getpriority, getrlimit, getrusage, umask
		// setregid, setgid, setreuid, setuid, setresuid, setresgid, setfsuid,
		// setfsgid, setgroups.
		143...147, 149, 151, 152, 159 { p_id }
		148, 150, 153, 155, 156, 158, 160 { pledge_stdio } // getresuid, getresgid, times, getpgid, getsid, getgroups, uname
		154, 157 { p_proc } // setpgid, setsid
		167 { pledge_prctl(a[0]) }
		168, 169 { pledge_stdio } // getcpu, gettimeofday
		170, 171, 266 { p_settime } // settimeofday, adjtimex, clock_adjtime
		// getpid, getppid, getuid, geteuid, getgid, getegid, gettid, sysinfo.
		172...179 { pledge_stdio }
		198 { pledge_socket(a[0], a[2]) } // socket
		199 { pledge_stdio } // socketpair
		200, 201, 202, 242 { pledge_socket_fd(a[0], false) } // bind, listen, accept, accept4
		203 { pledge_socket_fd(a[0], true) } // connect
		204, 205, 207, 210, 211, 212, 243, 269 { pledge_stdio } // getsockname .. recvmmsg, sendmmsg
		206 { if a[4] == 0 { pledge_stdio } else { pledge_socket_fd(a[0], true) } } // sendto
		208, 209 { pledge_sockopt(a[1], a[2]) } // setsockopt, getsockopt
		// readahead, brk, munmap, mremap.
		213...216 { pledge_stdio }
		220 { pledge_clone(a[0]) } // clone
		221, 281 { p_exec } // execve, execveat
		222, 226, 288 { pledge_prot(a[2]) } // mmap, mprotect, pkey_mprotect
		223 { pledge_stdio } // fadvise64
		// msync, mlock, munlock, mlockall, munlockall, mincore, madvise,
		// remap_file_pages, mbind, get_mempolicy, set_mempolicy.
		227...237 { pledge_stdio }
		238, 239, 424, 434, 440, 448 { p_proc } // migrate_pages, move_pages, pidfd_*, process_madvise, process_mrelease
		// Vinix: set_tls, sigentry, mimmutable, minherit.
		245, 246, 247, 250 { pledge_stdio }
		248 { pledge_always } // pledge: only ever narrows
		249 { proc.pledge_unveil } // unveil
		260 { pledge_stdio } // wait4
		261 { pledge_rlimit(a[2]) } // prlimit64
		267 { pledge_stdio } // syncfs
		270, 271 { p_proc } // process_vm_readv/writev: unrestricted process inspection
		274 { pledge_sched_target(a[0]) } // sched_setattr
		275 { pledge_stdio } // sched_getattr
		276 { p_cpath } // renameat2
		// seccomp (only narrows), getrandom, memfd_create.
		277, 278, 279 { pledge_stdio }
		// membarrier, mlock2, copy_file_range, preadv2, pwritev2.
		283...287 { pledge_stdio }
		289, 290 { pledge_stdio } // pkey_alloc, pkey_free
		291 { pledge_stdio } // statx: judged once the file is found
		293 { pledge_stdio } // rseq
		435 { pledge_unsupported } // clone3
		436 { pledge_stdio } // close_range
		437, 439 { pledge_stdio } // openat2, faccessat2: judged once the file is found
		441 { pledge_stdio } // epoll_pwait2
		444, 445, 446 { pledge_stdio } // landlock: only narrows
		// memfd_secret, futex_waitv, set_mempolicy_home_node, cachestat.
		447, 449, 450, 451 { pledge_stdio }
		452 { p_fattr } // fchmodat2
		453, 454, 455, 456, 462 { pledge_stdio } // map_shadow_stack, futex2, mseal
		else { pledge_never }
	}
}

// Called on every syscall's way in once the process has pledged. Answers the
// table slot to run: the call itself, or the stand-in that returns the errno
// the call was refused with.
fn pledge_entry(mut t proc.Thread, gpr &cpulocal.GPRState, nr u64) u64 {
	t.pledge_syscall = i64(nr)
	code := pledge_verdict(pledge_needs(nr, [gpr.x0, gpr.x1, gpr.x2, gpr.x3, gpr.x4, gpr.x5]!))
	if code == 0 {
		return nr
	}
	t.seccomp_errno = code
	return seccomp_verdict_nr
}

// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// pledge(2) at syscall entry: which promise a call needs, decided from its
// number and the arguments that are in registers. pledge_arm64.v and
// pledge_amd64.v map each architecture's Linux numbers; what is decided by an
// argument -- an ioctl request, a socket's family -- is decided here, once
// for both.
//
// A call that names a file is let through here with "stdio" when it may yet
// be allowed by the whitelist in proc/pledge.v, and judged in full once fs
// has resolved the file (fs/policy.v); every other call that names a file
// needs its path promise here as well, so that a check missing from a
// handler fails closed.
module table

import proc
import socket
import socket.public as sock_pub

// Allowed whatever the process promised: _exit(2), and pledge(2) itself.
const pledge_always = proc.pledge_set
// Fails with ENOSYS, but is not a violation: clone3(2), whose flags are in
// memory where they could change after being looked at. glibc falls back to
// clone(2), whose flags are in a register.
const pledge_unsupported = u64(1) << 62
// No promise allows it.
const pledge_never = u64(0)

const pledge_stdio = proc.pledge_stdio
const p_rpath = proc.pledge_rpath
const p_wpath = proc.pledge_wpath
const p_cpath = proc.pledge_cpath
const p_fattr = proc.pledge_fattr
const p_chown = proc.pledge_chown
const p_flock = proc.pledge_flock
const p_proc = proc.pledge_proc
const p_exec = proc.pledge_exec
const p_id = proc.pledge_id
const p_settime = proc.pledge_settime
const pledge_socket_any = proc.pledge_inet | proc.pledge_unix | proc.pledge_dns | proc.pledge_route

// ── ioctl(2) ─────────────────────────────────────────────────────────────────

const fionread = u64(0x541b)
const fionbio = u64(0x5421)
const fioclex = u64(0x5451)
const fionclex = u64(0x5450)
const tcgets = u64(0x5401)
const tcgets2 = u64(0x802c542a)
const tiocgwinsz = u64(0x5413)
const tiocspgrp = u64(0x5410)
const tiocsti = u64(0x5412)

fn pledge_ioctl(request u64) u64 {
	req := request & 0xffffffff
	match req {
		// OpenBSD's stdio set, and the queries isatty() and stdio's buffering
		// make on Linux: musl asks TIOCGWINSZ, glibc TCGETS. OpenBSD's libc
		// uses fcntl(F_ISATTY) instead, so it never needed them.
		fionread, fionbio, fioclex, fionclex, tcgets, tcgets2, tiocgwinsz {
			return pledge_stdio
		}
		// Pushing input into a terminal is how a program escapes into its
		// parent shell; OpenBSD removed it outright.
		tiocsti {
			return pledge_never
		}
		// Setting the foreground process group signals others.
		tiocspgrp {
			return pledge_needs_all(proc.pledge_tty | proc.pledge_proc)
		}
		else {}
	}
	kind := (req >> 8) & 0xff
	return match kind {
		0x54 { proc.pledge_tty } // 'T': termios and the rest of the tty
		0x64 { proc.pledge_drm } // 'd': DRM
		0x50, 0x4d { proc.pledge_audio } // 'P', 'M': OSS /dev/dsp and mixer
		0x56 { proc.pledge_video } // 'V': Video4Linux
		0x89 {
			// Interface queries (SIOCGIF*): musl's if_nametoindex() makes them
			// on whichever socket it has. Setting anything is not allowed.
			if pledge_interface_query(req) { pledge_socket_any } else { pledge_never }
		}
		else { pledge_never }
	}
}

fn pledge_interface_query(req u64) bool {
	return match req {
		0x8905, 0x8906, 0x8907, 0x8910, 0x8912, 0x8913, 0x8915, 0x8917, 0x8919, 0x891b, 0x891d,
		0x8921, 0x8927, 0x8933, 0x8938 {
			true
		}
		else {
			false
		}
	}
}

// Needs every one of `promises` rather than any one: marked so that
// pledge_verdict() can tell.
const pledge_all_of = u64(1) << 61

fn pledge_needs_all(promises u64) u64 {
	return promises | pledge_all_of
}

// ── fcntl(2) ─────────────────────────────────────────────────────────────────

fn pledge_fcntl(cmd u64) u64 {
	return match cmd & 0xffffffff {
		// F_DUPFD, F_GETFD, F_SETFD, F_GETFL, F_SETFL, F_GETOWN, F_SETSIG,
		// F_GETSIG, F_GETOWN_EX, F_GETOWNER_UIDS, F_DUPFD_CLOEXEC, the pipe
		// size, seals and write hints.
		0, 1, 2, 3, 4, 9, 10, 11, 16, 17, 1030, 1031, 1032, 1033, 1034, 1035, 1036, 1037, 1038 {
			pledge_stdio
		}
		// F_GETLK, F_SETLK, F_SETLKW, the OFD locks, and leases.
		5, 6, 7, 36, 37, 38, 1024, 1025 {
			proc.pledge_flock
		}
		// F_SETOWN, F_SETOWN_EX: who gets SIGIO.
		8, 15 {
			proc.pledge_proc
		}
		// F_NOTIFY: dnotify, watching a directory.
		1026 {
			proc.pledge_rpath
		}
		else {
			pledge_never
		}
	}
}

// ── prctl(2) ─────────────────────────────────────────────────────────────────

fn pledge_prctl(option u64) u64 {
	return match option & 0xffffffff {
		// About the thread itself: its name, death signal, dumpability,
		// seccomp and no_new_privs (which only ever narrow), timer slack,
		// THP, SVE vector length, pointer authentication, tagged addresses,
		// and naming an anonymous mapping, which glibc does.
		1, 2, 3, 4, 7, 15, 16, 21, 22, 23, 27, 29, 30, 37, 38, 39, 40, 41, 42, 50, 51, 54, 55, 56,
		0x53564d41, proc.pr_vinix_stack_policy, proc.pr_vinix_syscall_policy {
			pledge_stdio
		}
		// PR_SET_KEEPCAPS, PR_CAPBSET_DROP, PR_SET_SECUREBITS, PR_CAP_AMBIENT.
		8, 24, 28, 47 {
			proc.pledge_id
		}
		// PR_SET_CHILD_SUBREAPER, PR_SET_PTRACER.
		36, 0x59616d61 {
			proc.pledge_proc
		}
		else {
			pledge_never
		}
	}
}

// ── sockets ──────────────────────────────────────────────────────────────────

const ipproto_ip = u64(0)
const ipproto_ipv6 = u64(41)
const sol_netlink = u64(270)

fn pledge_multicast_option(level u64, optname u64) bool {
	if level == ipproto_ip {
		// IP_MULTICAST_IF .. IP_DROP_MEMBERSHIP, the source filters and
		// MCAST_JOIN_GROUP .. MCAST_MSFILTER.
		return (optname >= 32 && optname <= 36) || (optname >= 39 && optname <= 48)
	}
	if level == ipproto_ipv6 {
		// IPV6_MULTICAST_IF .. IPV6_DROP_MEMBERSHIP and MCAST_*.
		return (optname >= 17 && optname <= 21) || (optname >= 42 && optname <= 48)
	}
	return false
}

fn pledge_sockopt(level u64, optname u64) u64 {
	lvl := level & 0xffffffff
	opt := optname & 0xffffffff
	// SO_TYPE, SO_ERROR, SO_SNDBUF, SO_RCVBUF: asked of any descriptor by
	// code that only does I/O on it.
	if lvl == u64(sock_pub.sol_socket) && (opt == 3 || opt == 4 || opt == 7 || opt == 8) {
		return pledge_stdio
	}
	if pledge_multicast_option(lvl, opt) {
		return pledge_needs_all(proc.pledge_inet | proc.pledge_mcast)
	}
	if lvl == sol_netlink {
		return proc.pledge_route
	}
	return pledge_socket_any
}

fn pledge_socket(domain u64, protocol u64) u64 {
	return match int(domain & 0xffffffff) {
		sock_pub.af_unix { proc.pledge_unix }
		// "dns" may make the socket; inet.address() keeps it to port 53.
		sock_pub.af_inet, sock_pub.af_inet6 { proc.pledge_inet | proc.pledge_dns }
		// NETLINK_ROUTE: what getifaddrs() and ip(8) read the routes through.
		sock_pub.af_netlink { if protocol == 0 { proc.pledge_route } else { pledge_never } }
		else { pledge_never }
	}
}

// bind(2), listen(2), accept(2): by the family of the socket the descriptor
// names. Something that is not a socket fails in the call itself.
fn pledge_socket_fd(fdnum u64, may_resolve bool) u64 {
	return match socket.family_of(int(i32(fdnum))) {
		sock_pub.af_unix { proc.pledge_unix }
		sock_pub.af_inet, sock_pub.af_inet6 {
			if may_resolve { proc.pledge_inet | proc.pledge_dns } else { proc.pledge_inet }
		}
		sock_pub.af_netlink { proc.pledge_route }
		else { pledge_stdio }
	}
}

// ── processes ────────────────────────────────────────────────────────────────

// Whether `pid`, as the caller numbers processes, is the caller.
fn pledge_is_self(pid i64) bool {
	process := proc.current_thread().process
	return pid == i64(process.pid) || (process.ns_pid > 0 && pid == i64(process.ns_pid))
}

// kill(2): the process itself, or its own process group, with "stdio".
fn pledge_kill(pid u64) u64 {
	target := i64(i32(pid))
	if target == 0 || pledge_is_self(target) {
		return pledge_stdio
	}
	return proc.pledge_proc
}

// tkill(2): one of the caller's own threads, with "stdio".
fn pledge_tkill(tid u64) u64 {
	if proc.tid_in_process(int(i32(tid)), proc.current_thread().process) {
		return pledge_stdio
	}
	return proc.pledge_proc
}

const clone_thread = u64(0x10000)

// clone(2): a thread with "stdio", a process with "proc".
fn pledge_clone(flags u64) u64 {
	if flags & clone_thread != 0 {
		return pledge_stdio
	}
	return proc.pledge_proc
}

// sched_setaffinity(2) and the like: on the caller with "stdio".
fn pledge_sched_target(pid u64) u64 {
	target := i64(i32(pid))
	if target == 0 || pledge_is_self(target)
		|| proc.tid_in_process(int(target), proc.current_thread().process) {
		return pledge_stdio
	}
	return proc.pledge_proc
}

// ── memory and files ─────────────────────────────────────────────────────────

const prot_exec = u64(4)

// mmap(2) and mprotect(2): executable memory needs "prot_exec".
fn pledge_prot(prot u64) u64 {
	if prot & prot_exec != 0 {
		return proc.pledge_prot_exec
	}
	return pledge_stdio
}

const s_ifmt = u64(0o170000)
const s_ififo = u64(0o010000)
const s_ifchr = u64(0o020000)
const s_ifblk = u64(0o060000)

// mknod(2): a FIFO or a device needs "dpath", a plain file "cpath".
fn pledge_mknod(mode u64) u64 {
	kind := mode & s_ifmt
	if kind == s_ififo || kind == s_ifchr || kind == s_ifblk {
		return proc.pledge_dpath
	}
	return proc.pledge_cpath
}

// prlimit64(2) and setrlimit(2): reading a limit with "stdio", changing one
// with "proc" or "id".
fn pledge_rlimit(new_limit u64) u64 {
	if new_limit == 0 {
		return pledge_stdio
	}
	return proc.pledge_proc | proc.pledge_id
}

// ── the verdict ──────────────────────────────────────────────────────────────

// Whether a call needing `needed` may go ahead. Answers 0 when it may, or the
// errno it fails with: ENOSYS for pledge_unsupported, otherwise what
// proc.pledge_fail() says, which also marks the thread to be killed.
fn pledge_verdict(needed u64) u64 {
	if needed & pledge_always != 0 {
		return 0
	}
	if needed & pledge_unsupported != 0 {
		return 38 // ENOSYS
	}
	process := proc.current_thread().process
	promises := process.pledge & ~proc.pledge_set
	if needed & pledge_all_of != 0 {
		wanted := needed & ~pledge_all_of
		if wanted & ~promises == 0 {
			return 0
		}
		return proc.pledge_fail(wanted & ~promises)
	}
	if promises & needed != 0 {
		return 0
	}
	return proc.pledge_fail(needed)
}

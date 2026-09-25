// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module table

// seccomp for Linux programs on amd64: every call a process with a filter
// makes goes through its BPF programs before it runs, as arm64's
// syscall_trace() does. seccomp(2) and prctl(PR_SET_SECCOMP) install them; see
// container.v and proc/seccomp.v.

import errno
import proc
import userland
import x86.cpu.local as cpulocal

// The table slot of the stand-in for a call a seccomp filter turned away.
const seccomp_verdict_nr = u64(511)

// Returns what the call a seccomp filter turned away returns.
fn syscall_seccomp_verdict(_ voidptr) (u64, u64) {
	e := proc.current_thread().seccomp_errno
	if e == 0 {
		return 0, 0
	}
	return errno.err, e
}

// Called by syscall_entry for every Linux call, with the saved registers.
// Answers the table slot to run: the call's own, or the stand-in returning
// the verdict of the process's seccomp filters. A call whose verdict is death
// does not come back from here.
@[export: 'linux_syscall_slot']
pub fn linux_syscall_slot(frame &cpulocal.GPRState) u64 {
	nr := frame.rax
	mut t := proc.current_thread()
	process := t.process
	if process.seccomp_mode == proc.seccomp_mode_disabled {
		return nr
	}
	if process.seccomp_mode == proc.seccomp_mode_strict {
		// read, write, exit and rt_sigreturn are all strict mode allows.
		if nr == 0 || nr == 1 || nr == 60 || nr == 15 {
			return nr
		}
		userland.exit_by_signal(9)
	}
	// The instruction after the syscall is what Linux reports as its address.
	verdict := proc.seccomp_verdict(process.seccomp, nr, frame.rip, [frame.rdi, frame.rsi,
		frame.rdx, frame.r10, frame.r8, frame.r9]!)
	match verdict & proc.seccomp_ret_action_full {
		proc.seccomp_ret_allow, proc.seccomp_ret_log {
			return nr
		}
		proc.seccomp_ret_errno {
			mut e := u64(verdict & proc.seccomp_ret_data)
			if e > 4095 {
				e = 4095
			}
			t.seccomp_errno = e
			return seccomp_verdict_nr
		}
		proc.seccomp_ret_trap {
			userland.sendsig(t, u8(31))
			t.seccomp_errno = errno.enosys
			return seccomp_verdict_nr
		}
		proc.seccomp_ret_trace, proc.seccomp_ret_user_notif {
			// No tracer and no listener: Linux fails the call with ENOSYS.
			t.seccomp_errno = errno.enosys
			return seccomp_verdict_nr
		}
		else {
			// SIGSYS kills the process.
			userland.exit_by_signal(31)
		}
	}
	return seccomp_verdict_nr
}

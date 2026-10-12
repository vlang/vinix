// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module table

// Every amd64 syscall's way in and out, as syscall_table_arm64.v has them for
// arm64: a call goes through the process's seccomp filters, then its pledge(2)
// promises, before it runs. seccomp(2) and prctl(PR_SET_SECCOMP) install the
// filters; see container.v and proc/seccomp.v.

import errno
import proc
import security
import userland
import x86.cpu.local as cpulocal

// The table slot of the stand-in for a call a seccomp filter turned away.
const seccomp_verdict_nr = u64(511)

// Returns what the call a seccomp filter turned away returns.
fn syscall_seccomp_verdict(_ voidptr) (u64, u64) {
	e := proc.current_thread().seccomp_errno
	if e == 0 {
		return proc.current_thread().seccomp_return, 0
	}
	return errno.err, e
}

// Called by syscall_entry on every syscall's way in, with the saved
// registers. Answers the table slot to run: the call's own, or the stand-in
// returning the errno a seccomp filter or pledge(2) refused it with. A call
// whose verdict is death does not come back from here.
@[export: 'syscall_trace']
pub fn syscall_trace(frame &cpulocal.GPRState) u64 {
	proc.cpu_enter_kernel()
	// Dispatch uses the C-int selector's unsigned 32-bit representation.
	// Keep signed metadata and the original register for restart/rollback.
	nr := u64(u32(frame.rax))
	mut t := proc.current_thread()
	t.audit_sequence = 0
	t.syscall_nr = i64(i32(nr))
	t.restart_nr = frame.rax
	t.syscall_x0 = frame.rdi
	t.syscall_x1 = frame.rsi
	t.syscall_x2 = frame.rdx
	t.syscall_x3 = frame.r10
	mut process := t.process
	if !proc.syscall_stack_allowed(mut process, frame.rsp) {
		userland.exit_with_fatal_signal(u8(11))
	}
	if !proc.syscall_origin_allowed(mut process, nr, frame.rip - 2) {
		userland.exit_with_fatal_signal(u8(6))
	}
	if proc.seccomp_mode(t) != proc.seccomp_mode_disabled {
		slot := seccomp_entry(mut t, frame, nr)
		if slot == seccomp_verdict_nr || slot != nr {
			return slot
		}
	}
	// Slot 511 is private to seccomp/pledge verdicts. An ordinary request
	// for that Linux number must reach the assembly ENOSYS bounds path.
	if nr == seccomp_verdict_nr { return u64(512) }
	if process.pledge != 0 {
		return pledge_entry(mut t, frame, nr)
	}
	return nr
}

// Called by syscall_entry on every syscall's way out, with its result and
// errno.
@[export: 'syscall_trace_ret']
pub fn syscall_trace_ret(ret u64, err u64) {
	mut t := proc.current_thread()
	security.audit_complete(t.audit_sequence, ret, err)
	t.audit_sequence = 0
	t.syscall_nr = -1
}

// What a call runs as once the process's seccomp filters have seen it: the
// call itself, or the stand-in returning their verdict.
fn seccomp_entry(mut t proc.Thread, frame &cpulocal.GPRState, nr u64) u64 {
	t.seccomp_return = 0
	if proc.seccomp_mode(t) == proc.seccomp_mode_strict {
		// read, write, exit and rt_sigreturn are all strict mode allows.
		if nr == 0 || nr == 1 || nr == 60 || nr == 15 {
			return nr
		}
		security.audit_seccomp(nr, frame.rip, proc.seccomp_ret_kill_thread)
		userland.exit_thread_with_fatal_signal(u8(9))
	}
	// The instruction after the syscall is what Linux reports as its address.
	verdict := proc.seccomp_verdict(t, nr, frame.rip, [frame.rdi, frame.rsi,
		frame.rdx, frame.r10, frame.r8, frame.r9]!)
	if verdict & proc.seccomp_ret_action_full != proc.seccomp_ret_allow {
		t.audit_sequence = security.audit_seccomp(nr, frame.rip, verdict)
	}
	match verdict & proc.seccomp_ret_action_full {
		proc.seccomp_ret_allow, proc.seccomp_ret_log {
			return if nr == seccomp_verdict_nr { u64(512) } else { nr }
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
			userland.force_seccomp_signal(mut t, nr, frame.rip, verdict & proc.seccomp_ret_data)
			// syscall_rollback leaves orig_rax in Linux's return register.
			t.seccomp_return = frame.rax
			t.seccomp_errno = 0
			return seccomp_verdict_nr
		}
		proc.seccomp_ret_trace, proc.seccomp_ret_user_notif {
			// No tracer and no listener: Linux fails the call with ENOSYS.
			t.seccomp_errno = errno.enosys
			return seccomp_verdict_nr
		}
		proc.seccomp_ret_kill_thread {
			userland.exit_thread_with_fatal_signal(u8(31))
		}
		else {
			// SIGSYS kills the process.
			userland.exit_with_fatal_signal(u8(31))
		}
	}
	return seccomp_verdict_nr
}

// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Signal delivery on amd64. A program expects the kernel to push Linux's
// rt_sigframe onto its stack, enter the handler, and take the frame back in
// rt_sigreturn when the handler returns into its sa_restorer.
//
// Linux numbers signal n as bit n-1 of a sigset; this kernel's masks and
// pending bits use bit n. The Linux entry points convert at the boundary.
module userland

import posixtimer
import proc
import usercopy
import katomic
import lib
import sched
import event
import event.eventstruct
import errno
import time
import x86.cpu.local as cpulocal

const linux_sig_dfl = u64(0)
const linux_sig_ign = u64(1)

const linux_sa_onstack = 0x08000000
const linux_sa_restorer = 0x04000000
const linux_sa_nodefer = 0x40000000
const linux_sa_resethand = int(u32(0x80000000))

// struct rt_sigframe (arch/x86/kernel/signal_64.c): the return address the
// handler's `ret` pops, a struct ucontext, then a siginfo.
const frame_ucontext = u64(8)
const frame_mcontext = u64(48)
const frame_sigmask = u64(304)
const frame_siginfo = u64(312)
const frame_size = u64(440)

// The first word of sigcontext's reserved1[8], which Linux leaves zero and
// libc never reads, holds the cookie that signs the frame; see
// proc/sigcookie.v.
const mc_cookie = u64(192)

// struct sigcontext, from the start of uc_mcontext.
const mc_r8 = u64(0)
const mc_rdi = u64(64)
const mc_rsi = u64(72)
const mc_rbp = u64(80)
const mc_rbx = u64(88)
const mc_rdx = u64(96)
const mc_rax = u64(104)
const mc_rcx = u64(112)
const mc_rsp = u64(120)
const mc_rip = u64(128)
const mc_eflags = u64(136)
const mc_cs = u64(144)
const mc_err = u64(152)
const mc_trapno = u64(160)
const mc_oldmask = u64(168)
const mc_cr2 = u64(176)
const mc_fpstate = u64(184)

const ss_disable = u32(2)

// RFLAGS bits a handler starts without: trap, direction and resume.
const rflags_handler_clear = u64((1 << 8) | (1 << 10) | (1 << 16))

pub fn linux_mask_to_vinix(mask u64) u64 {
	return mask << 1
}

pub fn vinix_mask_to_linux(mask u64) u64 {
	return mask >> 1
}

fn unblockable_mask() u64 {
	return (u64(1) << sigkill) | (u64(1) << sigstop)
}

// The size of a sigset, and the bit signal `signum` has in this kernel's
// masks, which is bit n.
const sigset_size = u64(8)

fn signal_bit(signum int) u64 {
	return u64(1) << u64(signum)
}

fn put_u64(mut buf []u8, offset u64, value u64) {
	for i := u64(0); i < 8; i++ {
		buf[offset + i] = u8(value >> (i * 8))
	}
}

fn put_u32(mut buf []u8, offset u64, value u32) {
	for i := u64(0); i < 4; i++ {
		buf[offset + i] = u8(value >> (i * 8))
	}
}

fn get_u64(buf []u8, offset u64) u64 {
	mut value := u64(0)
	for i := u64(0); i < 8; i++ {
		value |= u64(buf[offset + i]) << (i * 8)
	}
	return value
}

// What SIG_DFL does with `signal`: true to ignore it. Everything else ends the
// process. The stop signals are ignored too, there being no job control.
fn linux_default_ignores(signal int) bool {
	return match signal {
		sigchld, sigcont, sigurg, sigwinch, sigstop, sigtstp, sigttin, sigttou { true }
		else { false }
	}
}

// Deliver `which` to the calling Linux process on its way back to userspace.
fn dispatch_linux_signal(context &cpulocal.GPRState, which int, info_signum int, info_code int, info_addr u64) {
	mut t := unsafe { proc.current_thread() }
	sigaction := t.sigactions[which]
	handler := u64(sigaction.sa_sigaction)

	// A mask sigsuspend() put in place for the wait belongs to the handler's
	// frame, which puts the one from before it back on return.
	previous_mask := if t.saved_mask_valid { t.saved_mask } else { t.masked_signals }
	t.saved_mask_valid = false

	if handler == linux_sig_ign || (handler == linux_sig_dfl && linux_default_ignores(which)) {
		t.masked_signals = previous_mask
		return
	}
	if handler == linux_sig_dfl || sigaction.sa_flags & linux_sa_restorer == 0 {
		// The default action, or a handler with no way back from it.
		exit_by_signal(which)
	}

	// An SA_ONSTACK handler runs on the alternate stack sigaltstack() set up,
	// unless it is already running there. Otherwise the frame goes below the
	// red zone, with the FPU state above it.
	mut sp := context.rsp - 128
	on_altstack := on_sigaltstack(t, context.rsp)
	if sigaction.sa_flags & linux_sa_onstack != 0 && t.sigaltstack_size != 0 && !on_altstack {
		sp = t.sigaltstack_sp + t.sigaltstack_size
	}
	sp = lib.align_down(sp - fpu_storage_size, 64)
	fpstate := sp
	sp = lib.align_down(sp - frame_size, 16) - 8
	frame := sp

	// Freed once pushed, not by a defer: this ends in resume_saved_context()
	// or exit_by_signal(), neither of which returns, and a signal delivered
	// through here lost it every time.
	mut buf := []u8{len: int(frame_size)} @[freed]
	put_u64(mut buf, 0, u64(sigaction.sa_restorer))
	// uc_flags and uc_link stay 0. uc_stack describes the alternate stack as
	// it was when the signal arrived.
	put_u64(mut buf, frame_ucontext + 16, t.sigaltstack_sp)
	put_u32(mut buf, frame_ucontext + 24, altstack_flags(t, context.rsp))
	put_u64(mut buf, frame_ucontext + 32, t.sigaltstack_size)
	mc := frame_mcontext
	registers := [context.r8, context.r9, context.r10, context.r11, context.r12, context.r13,
		context.r14, context.r15, context.rdi, context.rsi, context.rbp, context.rbx, context.rdx,
		context.rax, context.rcx, context.rsp, context.rip, context.rflags]!
	for i, value in registers {
		put_u64(mut buf, mc + u64(i) * 8, value)
	}
	put_u64(mut buf, mc + mc_cs, context.cs | (context.ss << 48))
	put_u64(mut buf, mc + mc_err, context.err & 0xffffffff)
	put_u64(mut buf, mc + mc_trapno, context.err >> 32)
	put_u64(mut buf, mc + mc_oldmask, vinix_mask_to_linux(previous_mask))
	put_u64(mut buf, mc + mc_cr2, info_addr)
	put_u64(mut buf, mc + mc_fpstate, fpstate)
	put_u64(mut buf, frame_sigmask, vinix_mask_to_linux(previous_mask))
	put_u64(mut buf, mc + mc_cookie, proc.sigframe_cookie(t.process, frame))
	put_u32(mut buf, frame_siginfo, u32(which))
	if info_signum == which {
		put_u32(mut buf, frame_siginfo + 8, u32(info_code))
		put_u64(mut buf, frame_siginfo + 16, info_addr)
	}
	// A POSIX timer's signal reports SI_TIMER, the overrun count and the
	// sigevent's value; musl's SIGEV_THREAD helper ignores it otherwise.
	timer_info := posixtimer.signal_info(t, which)
	if timer_info.found {
		put_u32(mut buf, frame_siginfo + 8, u32(timer_info.code))
		put_u32(mut buf, frame_siginfo + 20, u32(timer_info.overrun))
		put_u64(mut buf, frame_siginfo + 24, timer_info.value)
	}
	posixtimer.acknowledge_signal(mut t, which)

	// The registers still hold the program's FPU state; the kernel uses none.
	fpu_save(t.fpu_storage)
	pushed := usercopy.copy_to_user(frame, voidptr(&buf[0]), frame_size)
		&& usercopy.copy_to_user(fpstate, t.fpu_storage, fpu_storage_size)
	unsafe { buf.free() }
	if !pushed {
		// No stack to put the frame on: Linux kills the process with SIGSEGV.
		exit_by_signal(sigsegv)
	}

	t.masked_signals = previous_mask | linux_mask_to_vinix(sigaction.sa_mask)
	if sigaction.sa_flags & linux_sa_nodefer == 0 {
		t.masked_signals |= u64(1) << which
	}
	t.masked_signals &= ~unblockable_mask()
	if sigaction.sa_flags & linux_sa_resethand != 0 {
		t.sigactions[which].sa_sigaction = voidptr(0)
	}

	// Enter the handler as handler(signal, &info, &ucontext), with the frame's
	// return address on top of the stack.
	t.gpr_state = *context
	t.gpr_state.rip = handler
	t.gpr_state.rsp = frame
	t.gpr_state.rdi = u64(which)
	t.gpr_state.rsi = frame + frame_siginfo
	t.gpr_state.rdx = frame + frame_ucontext
	t.gpr_state.rax = 0
	t.gpr_state.rflags &= ~rflags_handler_clear

	sched.resume_saved_context()
}

// rt_sigreturn(): the handler's sa_restorer calls this with the stack pointer
// just past the frame's return address.
pub fn syscall_linux_rt_sigreturn(gpr_state voidptr) (u64, u64) {
	syscall_frame := unsafe { &cpulocal.GPRState(gpr_state) }
	frame := syscall_frame.rsp - 8

	mut buf := []u8{len: int(frame_size)} @[freed]
	if !usercopy.copy_from_user(voidptr(&buf[0]), frame, frame_size) {
		unsafe { buf.free() }
		exit_by_signal(sigsegv)
	}
	mc := frame_mcontext
	// Nothing in the frame is believed until its cookie is, and the cookie is
	// spent, so that the frame cannot be returned through twice. A forged
	// frame is an attack, not a mistake.
	spent := u64(0)
	if get_u64(buf, mc + mc_cookie) != proc.sigframe_cookie(proc.current_thread().process, frame)
		|| !usercopy.copy_to_user(frame + mc + mc_cookie, voidptr(&spent), sizeof(u64)) {
		unsafe { buf.free() }
		exit_by_signal(sigsegv)
	}
	mut context := cpulocal.GPRState{
		r8:     get_u64(buf, mc + mc_r8)
		r9:     get_u64(buf, mc + mc_r8 + 8)
		r10:    get_u64(buf, mc + mc_r8 + 16)
		r11:    get_u64(buf, mc + mc_r8 + 24)
		r12:    get_u64(buf, mc + mc_r8 + 32)
		r13:    get_u64(buf, mc + mc_r8 + 40)
		r14:    get_u64(buf, mc + mc_r8 + 48)
		r15:    get_u64(buf, mc + mc_r8 + 56)
		rdi:    get_u64(buf, mc + mc_rdi)
		rsi:    get_u64(buf, mc + mc_rsi)
		rbp:    get_u64(buf, mc + mc_rbp)
		rbx:    get_u64(buf, mc + mc_rbx)
		rdx:    get_u64(buf, mc + mc_rdx)
		rax:    get_u64(buf, mc + mc_rax)
		rcx:    get_u64(buf, mc + mc_rcx)
		rsp:    get_u64(buf, mc + mc_rsp)
		rip:    get_u64(buf, mc + mc_rip)
		rflags: get_u64(buf, mc + mc_eflags)
	}
	fpstate := get_u64(buf, mc + mc_fpstate)
	mask := linux_mask_to_vinix(get_u64(buf, frame_sigmask))
	unsafe { buf.free() }
	if !valid_sigreturn_context(&context) {
		exit_by_signal(sigsegv)
	}
	sanitize_sigreturn_context(mut context)

	if fpstate != 0 {
		mut t := unsafe { proc.current_thread() }
		mut saved := unsafe { &u8(malloc(fpu_storage_size)) }
		if !usercopy.copy_from_user(voidptr(saved), fpstate, fpu_storage_size) {
			unsafe { free(voidptr(saved)) }
			exit_by_signal(sigsegv)
		}
		asm volatile amd64 {
			cli
		}
		// Keep this CPU's own XSAVE header and take the register contents from
		// the frame: a header, or MXCSR bits, the CPU does not accept would
		// fault the restore inside the kernel.
		fpu_save(t.fpu_storage)
		mut live := unsafe { &u8(t.fpu_storage) }
		unsafe {
			C.memcpy(live, saved, 512)
			if fpu_storage_size > 576 {
				C.memcpy(&live[576], &saved[576], fpu_storage_size - 576)
			}
			mut mxcsr_mask := *&u32(&live[28])
			if mxcsr_mask == 0 {
				mxcsr_mask = 0xffbf
			}
			*&u32(&live[24]) &= mxcsr_mask
		}
		fpu_restore(t.fpu_storage)
		unsafe { free(voidptr(saved)) }
	}

	resume_sigreturn(context, mask)
}

// rt_sigsuspend(mask, sigsetsize): sleep with `mask` in place until a signal
// that gets through it arrives; its handler runs on the way out.
pub fn syscall_linux_rt_sigsuspend(_ voidptr, mask_ptr u64, sigsetsize u64) (u64, u64) {
	if sigsetsize != 8 {
		return errno.err, errno.einval
	}
	mut linux_mask := u64(0)
	if !usercopy.copy_from_user(voidptr(&linux_mask), mask_ptr, 8) {
		return errno.err, errno.efault
	}
	mut t := proc.current_thread()
	temporary := linux_mask_to_vinix(linux_mask) & ~unblockable_mask()
	original := t.masked_signals
	t.masked_signals = temporary

	mut events := []&eventstruct.Event{}
	for katomic.load(&t.pending_signals) & ~temporary == 0 {
		// Nothing to wait on but a signal, which is what ends the wait.
		event.await(mut events, true) or {}
	}
	unsafe { events.free() }

	t.saved_mask = original
	t.saved_mask_valid = true
	return errno.err, errno.eintr
}

// ── alternate signal stack ───────────────────────────────────────────────────

const ss_onstack = u32(1)

// The smallest alternate stack Linux accepts, MINSIGSTKSZ.
const min_sigstack_size = u64(2048)

// struct stack_t: ss_sp, ss_flags (padded to 8), ss_size.
const stack_t_size = u64(24)

// Whether `sp` is on `t`'s alternate signal stack, which is how Linux tells a
// handler already running there.
fn on_sigaltstack(t &proc.Thread, sp u64) bool {
	return t.sigaltstack_size != 0 && sp - t.sigaltstack_sp < t.sigaltstack_size
}

fn altstack_flags(t &proc.Thread, sp u64) u32 {
	if t.sigaltstack_size == 0 {
		return ss_disable
	}
	return if on_sigaltstack(t, sp) { ss_onstack } else { u32(0) }
}

// sigaltstack(ss, old_ss).
pub fn syscall_sigaltstack(gpr_state voidptr, ss_ptr u64, old_ss_ptr u64) (u64, u64) {
	mut t := proc.current_thread()
	frame := unsafe { &cpulocal.GPRState(gpr_state) }
	on_stack := on_sigaltstack(t, frame.rsp)

	// Read the new stack first: a faulting `ss` leaves the old one in place.
	mut incoming_sp := u64(0)
	mut incoming_size := u64(0)
	mut disabling := false
	if ss_ptr != 0 {
		// Changing the alternate stack while running on it would pull it out
		// from under the handler.
		if on_stack {
			return errno.err, errno.eperm
		}
		mut raw := [3]u64{}
		if !usercopy.copy_from_user(voidptr(&raw[0]), ss_ptr, stack_t_size) {
			return errno.err, errno.efault
		}
		flags := u32(raw[1])
		if flags & ~ss_disable != 0 {
			return errno.err, errno.einval
		}
		disabling = flags & ss_disable != 0
		if !disabling {
			if raw[2] < min_sigstack_size {
				return errno.err, errno.enomem
			}
			incoming_sp = raw[0]
			incoming_size = raw[2]
		}
	}

	if old_ss_ptr != 0 {
		mut raw := [3]u64{}
		raw[0] = t.sigaltstack_sp
		raw[1] = u64(altstack_flags(t, frame.rsp))
		raw[2] = t.sigaltstack_size
		if !usercopy.copy_to_user(old_ss_ptr, voidptr(&raw[0]), stack_t_size) {
			return errno.err, errno.efault
		}
	}

	if ss_ptr != 0 {
		t.sigaltstack_sp = incoming_sp
		t.sigaltstack_size = incoming_size
	}
	return 0, 0
}

// ── waiting for a signal ─────────────────────────────────────────────────────

// Sleep until a signal or, when `timeout` is given, the time runs out. True if
// a signal ended the wait.
fn sleep_for_signal(timeout &time.TimeSpec) bool {
	mut events := []&eventstruct.Event{}
	defer {
		unsafe { events.free() }
	}
	mut timer := &time.Timer(unsafe { nil })
	if timeout != unsafe { nil } {
		timer = time.new_timer(*timeout)
		events << &timer.event
	}
	defer {
		if timer != unsafe { nil } {
			timer.disarm()
			unsafe { free(timer) }
		}
	}
	event.await(mut events, true) or { return true }
	return false
}

// Claim the lowest pending signal in `wanted`, a mask in this kernel's layout.
fn take_pending(mut t proc.Thread, wanted u64) ?int {
	for signum := 1; signum < 64; signum++ {
		if wanted & (u64(1) << signum) == 0 {
			continue
		}
		if katomic.btr(mut &t.pending_signals, u8(signum)) {
			return signum
		}
	}
	return none
}

// rt_sigtimedwait(set, info, timeout, sigsetsize): take one of `set` without
// running a handler for it. sigwait() and sigtimedwait() are built on this,
// and so is the helper thread behind a SIGEV_THREAD timer.
pub fn syscall_rt_sigtimedwait(_ voidptr, set_ptr u64, info_ptr u64, timeout_ptr u64, sigsetsize u64) (u64, u64) {
	if sigsetsize != 8 {
		return errno.err, errno.einval
	}
	mut t := proc.current_thread()

	mut linux_set := u64(0)
	if !usercopy.copy_from_user(voidptr(&linux_set), set_ptr, 8) {
		return errno.err, errno.efault
	}
	wanted := linux_mask_to_vinix(linux_set) & ~unblockable_mask()

	mut deadline := time.TimeSpec{}
	mut timed := false
	if timeout_ptr != 0 {
		if !usercopy.copy_from_user(voidptr(&deadline), timeout_ptr, sizeof(time.TimeSpec)) {
			return errno.err, errno.efault
		}
		if deadline.tv_sec < 0 || deadline.tv_nsec < 0 || deadline.tv_nsec >= 1000000000 {
			return errno.err, errno.einval
		}
		timed = true
	}

	for {
		if which := take_pending(mut t, wanted) {
			if info_ptr != 0 {
				// A 128-byte siginfo_t: si_signo, si_errno, then si_code,
				// SI_USER (0) for anything raised by kill(), and SI_TIMER with
				// the overrun count and value for a POSIX timer's.
				mut info := [16]u64{}
				info[0] = u64(u32(which))
				timer_info := posixtimer.signal_info(t, which)
				if timer_info.found {
					info[1] = u64(u32(timer_info.code))
					info[2] = u64(u32(timer_info.overrun)) << 32
					info[3] = timer_info.value
				}
				if !usercopy.copy_to_user(info_ptr, voidptr(&info[0]), 128) {
					// Hand the signal back rather than losing it.
					katomic.bts(mut &t.pending_signals, u8(which))
					return errno.err, errno.efault
				}
			}
			posixtimer.acknowledge_signal(mut t, which)
			return u64(which), 0
		}
		if timed && deadline.tv_sec == 0 && deadline.tv_nsec == 0 {
			return errno.err, errno.eagain
		}
		// A signal outside the set that the mask lets through interrupts the
		// wait; its handler runs on the way out.
		if katomic.load(&t.pending_signals) & ~(t.masked_signals | wanted) != 0 {
			return errno.err, errno.eintr
		}
		if timed {
			if !sleep_for_signal(&deadline) {
				// The timer ran out: look once more, then give up.
				deadline = time.TimeSpec{}
			}
		} else {
			sleep_for_signal(unsafe { nil })
		}
	}
	return errno.err, errno.eagain
}


// pause(): sleep until a signal is delivered, then fail with EINTR once its
// handler has run.
pub fn syscall_pause(_ voidptr) (u64, u64) {
	mut t := proc.current_thread()
	for katomic.load(&t.pending_signals) & ~t.masked_signals == 0 {
		sleep_for_signal(unsafe { nil })
	}
	return errno.err, errno.eintr
}

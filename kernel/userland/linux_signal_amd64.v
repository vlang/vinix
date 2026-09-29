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
import x86.gdt

const linux_sig_dfl = u64(0)
const linux_sig_ign = u64(1)

const linux_sa_onstack = 0x08000000
const linux_sa_restorer = 0x04000000
const linux_sa_nodefer = 0x40000000
const linux_sa_restart = 0x10000000
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

// RFLAGS bits a handler starts without: trap, direction and resume.
const rflags_handler_clear = u64((1 << 8) | (1 << 10) | (1 << 16))

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

// Deliver `which` to the calling Linux process on its way back to userspace.
fn dispatch_linux_signal(context &cpulocal.GPRState, which int, info_signum int, info_code int, info_addr u64, restarting bool) {
	mut t := unsafe { proc.current_thread() }
	sigaction := t.sigactions[which]
	handler := u64(sigaction.sa_sigaction)

	// A mask sigsuspend() put in place for the wait belongs to the handler's
	// frame, which puts the one from before it back on return.
	previous_mask := if t.saved_mask_valid { t.saved_mask } else { t.masked_signals }
	t.saved_mask_valid = false

	// SIG_DFL ignores what Linux's default ignores, and the stop and continue
	// signals too, there being no job control; everything else ends the
	// process. So does a handler with no way back from it, which Linux x86-64
	// requires an sa_restorer for.
	if handler == linux_sig_ign || (handler == linux_sig_dfl && default_ignores(which)) {
		t.masked_signals = previous_mask
		return
	}
	if handler == linux_sig_dfl || sigaction.sa_flags & linux_sa_restorer == 0 {
		exit_with_fatal_signal(u8(which))
	}

	// A handler that did not ask for SA_RESTART sees the syscall fail with
	// EINTR instead of running again behind its back.
	if restarting && sigaction.sa_flags & linux_sa_restart == 0 {
		mut ctx := unsafe { context }
		ctx.rip += 2
		ctx.rcx = ctx.rip
		ctx.rax = u64(-i64(errno.eintr))
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
	// or exit_with_fatal_signal(), neither of which returns, and a signal delivered
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
	put_u64(mut buf, mc + mc_oldmask, previous_mask)
	put_u64(mut buf, mc + mc_cr2, info_addr)
	put_u64(mut buf, mc + mc_fpstate, fpstate)
	put_u64(mut buf, frame_sigmask, previous_mask)
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
		exit_with_fatal_signal(u8(sigsegv))
	}

	t.masked_signals = previous_mask | sigaction.sa_mask
	if sigaction.sa_flags & linux_sa_nodefer == 0 {
		t.masked_signals |= signal_bit(which)
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
	// In 64-bit mode, whatever code the signal interrupted, as Linux runs a
	// handler: 32-bit code an LDT code segment ran among them. sigreturn
	// goes back to that code segment.
	t.gpr_state.cs = u64(gdt.user_code_selector)
	t.gpr_state.ss = u64(gdt.user_data_selector)

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
		exit_with_fatal_signal(u8(sigsegv))
	}
	mc := frame_mcontext
	// Nothing in the frame is believed until its cookie is, and the cookie is
	// spent, so that the frame cannot be returned through twice. A forged
	// frame is an attack, not a mistake.
	spent := u64(0)
	if get_u64(buf, mc + mc_cookie) != proc.sigframe_cookie(proc.current_thread().process, frame)
		|| !usercopy.copy_to_user(frame + mc + mc_cookie, voidptr(&spent), sizeof(u64)) {
		unsafe { buf.free() }
		exit_with_fatal_signal(u8(sigsegv))
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
	mask := get_u64(buf, frame_sigmask)
	selectors := get_u64(buf, mc + mc_cs)
	unsafe { buf.free() }
	if !valid_sigreturn_context(&context) {
		exit_with_fatal_signal(u8(sigsegv))
	}
	sanitize_sigreturn_context(mut context, u16(selectors), u16(selectors >> 48), syscall_frame)

	if fpstate != 0 {
		mut t := unsafe { proc.current_thread() }
		mut saved := unsafe { &u8(malloc(fpu_storage_size)) }
		if !usercopy.copy_from_user(voidptr(saved), fpstate, fpu_storage_size) {
			unsafe { free(voidptr(saved)) }
			exit_with_fatal_signal(u8(sigsegv))
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

// ── alternate signal stack ───────────────────────────────────────────────────

// Whether `sp` is on `t`'s alternate signal stack, which is how Linux tells a
// handler already running there.
fn on_sigaltstack(t &proc.Thread, sp u64) bool {
	return t.sigaltstack_size != 0 && sp - t.sigaltstack_sp < t.sigaltstack_size
}

fn altstack_flags(t &proc.Thread, sp u64) u32 {
	if t.sigaltstack_size == 0 {
		return u32(ss_disable)
	}
	return if on_sigaltstack(t, sp) { u32(ss_onstack) } else { u32(0) }
}

// Whether the thread is running on its alternate signal stack now, for
// sigaltstack(2) in signal.v: whether the stack pointer it made the syscall
// with is on it.
fn thread_on_sigaltstack(t &proc.Thread) bool {
	return on_sigaltstack(t, t.user_stack)
}

// What SIG_DFL does with `signum`: true to ignore it, as Linux ignores it by
// default and, there being no job control, the stop and continue signals as
// arm64 does.
fn default_ignores(signum int) bool {
	return has_default_ignore_action(signum) || signum == sigcont || signum == sigstop
		|| signum == sigtstp || signum == sigttin || signum == sigttou
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

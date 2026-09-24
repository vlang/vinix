// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Signal delivery for Linux programs on amd64.
//
// A native Vinix program registers an entry point with sigentry() and its libc
// builds the handler's frame itself. A Linux program -- everything in the
// Alpine userland -- expects the kernel to push Linux's rt_sigframe onto its
// stack, enter the handler, and take the frame back in rt_sigreturn when the
// handler returns into its sa_restorer. Without that a musl process never had
// a handler run, nor a default action taken: zsh blocked forever waiting for
// the SIGCHLD that tells it a command has finished.
//
// Linux numbers signal n as bit n-1 of a sigset; this kernel's masks and
// pending bits use bit n. The Linux entry points convert at the boundary.
module userland

import proc
import usercopy
import katomic
import lib
import sched
import event
import event.eventstruct
import errno
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

fn unblockable() u64 {
	return (u64(1) << sigkill) | (u64(1) << sigstop)
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

	// The frame goes below the red zone, with the FPU state above it.
	mut sp := context.rsp - 128
	sp = lib.align_down(sp - fpu_storage_size, 64)
	fpstate := sp
	sp = lib.align_down(sp - frame_size, 16) - 8
	frame := sp

	mut buf := []u8{len: int(frame_size)}
	defer {
		unsafe { buf.free() }
	}
	put_u64(mut buf, 0, u64(sigaction.sa_restorer))
	// uc_flags and uc_link stay 0; no alternate stack.
	put_u32(mut buf, frame_ucontext + 24, ss_disable)
	mc := frame_mcontext
	registers := [context.r8, context.r9, context.r10, context.r11, context.r12, context.r13,
		context.r14, context.r15, context.rdi, context.rsi, context.rbp, context.rbx, context.rdx,
		context.rax, context.rcx, context.rsp, context.rip, context.rflags]
	for i, value in registers {
		put_u64(mut buf, mc + u64(i) * 8, value)
	}
	unsafe { registers.free() }
	put_u64(mut buf, mc + mc_cs, context.cs | (context.ss << 48))
	put_u64(mut buf, mc + mc_err, context.err & 0xffffffff)
	put_u64(mut buf, mc + mc_trapno, context.err >> 32)
	put_u64(mut buf, mc + mc_oldmask, vinix_mask_to_linux(previous_mask))
	put_u64(mut buf, mc + mc_cr2, info_addr)
	put_u64(mut buf, mc + mc_fpstate, fpstate)
	put_u64(mut buf, frame_sigmask, vinix_mask_to_linux(previous_mask))
	put_u32(mut buf, frame_siginfo, u32(which))
	if info_signum == which {
		put_u32(mut buf, frame_siginfo + 8, u32(info_code))
		put_u64(mut buf, frame_siginfo + 16, info_addr)
	}

	// The registers still hold the program's FPU state; the kernel uses none.
	fpu_save(t.fpu_storage)
	if !usercopy.copy_to_user(frame, voidptr(&buf[0]), frame_size)
		|| !usercopy.copy_to_user(fpstate, t.fpu_storage, fpu_storage_size) {
		// No stack to put the frame on: Linux kills the process with SIGSEGV.
		exit_by_signal(sigsegv)
	}

	t.masked_signals = previous_mask | linux_mask_to_vinix(sigaction.sa_mask)
	if sigaction.sa_flags & linux_sa_nodefer == 0 {
		t.masked_signals |= u64(1) << which
	}
	t.masked_signals &= ~unblockable()
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

	mut buf := []u8{len: int(frame_size)}
	if !usercopy.copy_from_user(voidptr(&buf[0]), frame, frame_size) {
		unsafe { buf.free() }
		exit_by_signal(sigsegv)
	}
	mc := frame_mcontext
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
	temporary := linux_mask_to_vinix(linux_mask) & ~unblockable()
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

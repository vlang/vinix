module userland

import fs
import memory
import memory.mmap
import elf
import sched
import file
import proc
import aarch64.cpu.local as cpulocal
import aarch64.cpu
import katomic
import posixtimer
import errno
import lib
import strings
import resource
import usercopy
import stat

pub const wnohang = 1

// Linux signal constants (different from mlibc/Vinix-native which use 1, 2, 3)
pub const sig_block = 0

pub const sig_unblock = 1

pub const sig_setmask = 2

pub const sighup = 1

pub const sigint = 2

pub const sigquit = 3

pub const sigill = 4

pub const sigtrap = 5

pub const sigabrt = 6

pub const sigbus = 7

pub const sigfpe = 8

pub const sigkill = 9

pub const sigusr1 = 10

pub const sigsegv = 11

pub const sigusr2 = 12

pub const sigpipe = 13

pub const sigalrm = 14

pub const sigterm = 15

pub const sigstkflt = 16

pub const sigchld = 17

pub const sigcont = 18

pub const sigstop = 19

pub const sigtstp = 20

pub const sigttin = 21

pub const sigttou = 22

pub const sigurg = 23

pub const sigxcpu = 24

pub const sigxfsz = 25

pub const sigvtalrm = 26

pub const sigprof = 27

pub const sigwinch = 28

pub const sigio = 29

pub const sigpoll = sigio

pub const sigpwr = 30

const gpu_desktop_executable = '/usr/bin/vinix-desktop-gpu'

// V's print path reaches both the UART and framebuffer console in production
// kernels. C.printf is intentionally compiled to a no-op in PROD, so it must
// not be used for boot diagnostics that need to be visible on the M1 panel.
fn gpu_exec_trace(enabled bool, stage string) {
	if enabled {
		println('exec[gpu]: ${stage}')
	}
}

pub const sigsys = 31

pub const sigrtmin = 32

pub const sigrtmax = 33

pub const sigcancel = 34

pub const sig_err = voidptr(-1)

// Linux signal disposition constants (different from mlibc which uses -2, -3)
pub const sig_dfl = voidptr(0)

pub const sig_ign = voidptr(1)

pub const sa_nocldstop = 1 << 0

pub const sa_onstack = 1 << 1

pub const sa_resethand = 1 << 2

pub const sa_restart = 1 << 3

pub const sa_siginfo = 1 << 4

pub const sa_nocldwait = 1 << 5

pub const sa_nodefer = 1 << 6

// Linux ignores these signals when the process has not installed a handler.
// Discard them before queueing so an ignored signal cannot spuriously wake and
// interrupt a blocking syscall.
fn has_default_ignore_action(signum int) bool {
	return signum == sigchld || signum == sigurg || signum == sigwinch
}

union SigVal {
	sival_int i32
	sival_ptr voidptr
}

pub struct SigInfo {
pub mut:
	si_signo  i32
	si_code   i32
	si_errno  i32
	si_pid    i32
	si_uid    i32
	si_addr   voidptr
	si_status i32
	si_value  SigVal
}

pub fn syscall_getpid(_ voidptr) (u64, u64) {
	mut t := unsafe { proc.current_thread() }

	return u64(proc.own_pid(t.process)), 0
}

// A parent outside the caller's pid namespace is 0 to it, as a container's
// init sees the runtime that started it.
pub fn syscall_getppid(_ voidptr) (u64, u64) {
	mut t := unsafe { proc.current_thread() }
	process := t.process
	if !proc.numbers_own(process.numbered_in) {
		return u64(process.ppid), 0
	}
	proc.lock_table()
	defer {
		proc.unlock_table()
	}
	return u64(proc.pid_in(proc.process_at(process.ppid), process.numbered_in)), 0
}

pub fn syscall_sigentry(_ voidptr, sigentry u64) (u64, u64) {
	mut t := proc.current_thread()

	t.sigentry = sigentry

	return 0, 0
}

// rt_sigreturn(2). The handler's stack frame holds the context to go back to,
// so this writes it straight into the exception frame the syscall path is about
// to restore. x0 is returned as the syscall result because handle_svc stores it
// over the frame's x0 slot on the way out.
fn valid_sigreturn_context(context &cpulocal.GPRState) bool {
	user_limit := memory.user_address_limit()
	return context.pc != 0 && context.pc < user_limit && context.sp != 0
		&& context.sp < user_limit && context.sp & 0xf == 0
}

fn sanitize_sigreturn_context(mut context cpulocal.GPRState) {
	// The shared architecture mask excludes M[4:0], DAIF, single-step and every
	// reserved bit. M[4:0] therefore remains EL0t after sanitization.
	context.pstate &= cpu.pstate_user_mask
}

pub fn syscall_sigreturn(gpr_state_ptr voidptr, context_arg voidptr, old_mask_arg u64) (u64, u64) {
	mut t := unsafe { proc.current_thread() }

	cpu.interrupt_toggle(false)

	mut frame := unsafe { &cpulocal.GPRState(gpr_state_ptr) }
	mut restored := cpulocal.GPRState{}
	mut restored_mask := u64(0)

	if t.sigentry != 0 {
		// Vinix/mlibc mode: context and mask passed as args (user x0, x1)
		if u64(context_arg) & 0xf != 0 {
			return errno.err, errno.einval
		}
		if !usercopy.copy_from_user(voidptr(&restored), u64(context_arg), sizeof(cpulocal.GPRState)) {
			return errno.err, errno.efault
		}
		restored_mask = old_mask_arg
	} else {
		// Linux/musl mode: read from the signal frame at the user SP. musl's
		// __restore_rt enters here with SP pointing at the frame dispatch left.
		// Frame layout: [prev_mask(8)] [ucontext address(8)]
		//               [GPRState(sizeof)] [optional siginfo and ucontext]
		user_sp := frame.sp
		if user_sp & 0xf != 0 {
			return errno.err, errno.einval
		}

		mut prev_mask := u64(0)
		mut public_context := u64(0)
		if !usercopy.copy_from_user(voidptr(&prev_mask), user_sp, sizeof(u64)) {
			return errno.err, errno.efault
		}
		if !usercopy.copy_from_user(voidptr(&public_context), user_sp + 8, sizeof(u64)) {
			return errno.err, errno.efault
		}
		if !usercopy.copy_from_user(voidptr(&restored), user_sp + 16, sizeof(cpulocal.GPRState)) {
			return errno.err, errno.efault
		}
		// SA_SIGINFO handlers receive a real AArch64 ucontext and are allowed to
		// edit it. HotSpot's guard-page handler, for example, redirects the saved
		// PC to its stack-overflow continuation. Restore those edits instead of
		// blindly resuming the private snapshot and faulting forever.
		if public_context != 0 {
			if public_context & 0xf != 0 {
				return errno.err, errno.einval
			}
			if !usercopy.copy_from_user(voidptr(&restored.x0), public_context + 184, 31 * sizeof(u64)) {
				return errno.err, errno.efault
			}
			if !usercopy.copy_from_user(voidptr(&restored.sp), public_context + 432, 3 * sizeof(u64)) {
				return errno.err, errno.efault
			}
			if !usercopy.copy_from_user(voidptr(&prev_mask), public_context + 40, sizeof(u64)) {
				return errno.err, errno.efault
			}
			if !restore_fpsimd(public_context + 464) {
				return errno.err, errno.efault
			}
		}
		restored_mask = prev_mask
	}

	if !valid_sigreturn_context(&restored) {
		return errno.err, errno.einval
	}
	sanitize_sigreturn_context(mut restored)

	t.gpr_state = restored
	t.masked_signals = restored_mask & ~unblockable_mask()

	t.on_sigaltstack = false

	unsafe {
		*frame = t.gpr_state
	}

	return t.gpr_state.x0, 0
}

fn C.vinix_aarch64_fpu_save(state voidptr)

fn C.vinix_aarch64_fpu_restore(state voidptr)

// Linux's struct fpsimd_context: a record header, FPSR, FPCR and the 32
// vector registers. The kernel's own save area is the registers, then FPSR
// and FPCR, 520 bytes.
const fpsimd_magic = u32(0x46508001)
const fpsimd_context_size = u32(528)
const fpsimd_state_size = 520

// Find the fpsimd_context among the extension records of a signal frame's
// ucontext, at `records`, and load the FP/SIMD registers from it. A frame
// without one leaves them as they are. False when the frame is not there to
// read.
fn restore_fpsimd(records u64) bool {
	mut offset := u64(0)
	for offset + 8 <= 4096 {
		mut header := [2]u32{}
		if !usercopy.copy_from_user(voidptr(&header[0]), records + offset, 8) {
			return false
		}
		magic := header[0]
		size := u64(header[1])
		if magic == 0 || size < 8 || offset + size > 4096 {
			return true
		}
		if magic == fpsimd_magic && size == u64(fpsimd_context_size) {
			mut record := [528]u8{}
			if !usercopy.copy_from_user(voidptr(&record[0]), records + offset, 528) {
				return false
			}
			mut state := [fpsimd_state_size]u8{}
			unsafe {
				C.memcpy(&state[0], &record[16], 512)
				*&u32(&state[512]) = *&u32(&record[8])
				*&u32(&state[516]) = *&u32(&record[12])
			}
			C.vinix_aarch64_fpu_restore(voidptr(&state[0]))
			return true
		}
		offset += size
	}
	return true
}

// Dispatch a signal to _self_, called from the scheduler at the
// end of syscalls, or from exception handlers.
// Linux gives an AArch64 signal handler whose sigaction sets no SA_RESTORER a
// return into the vDSO's __kernel_rt_sigreturn. glibc relies on that and
// leaves sa_restorer unset -- it is whatever its stack held -- so every
// handler of a glibc program returned into garbage: bash and dash died of
// the SIGCHLD of their first child. There is no vDSO here; every program gets
// a page holding just that: mov x8, #139 (rt_sigreturn); svc #0. It sits
// just above the highest place the stack can start.
const sigreturn_page_address = u64(0x70000000000)
const linux_sa_restorer = 0x04000000

fn install_sigreturn_page(mut pagemap memory.Pagemap) ?u64 {
	page := memory.pmm_alloc(1)
	if page == unsafe { nil } {
		errno.set(errno.enomem)
		return none
	}
	code := unsafe { &u32(u64(page) + higher_half) }
	unsafe {
		code[0] = u32(0xd2801168)
		code[1] = u32(0xd4000001)
	}
	cpu.sync_instruction_cache(u64(page) + higher_half, page_size)
	mmap.map_range(mut pagemap, sigreturn_page_address, u64(page), page_size, mmap.prot_read | mmap.prot_exec,
		mmap.map_private) or {
		memory.pmm_free(page, 1)
		return none
	}
	return sigreturn_page_address
}

// Where a Linux handler returns: its own restorer if it asked for one with
// SA_RESTORER, as musl does, or the process's rt_sigreturn page.
fn signal_restorer(process &proc.Process, sigaction &proc.SigAction) u64 {
	if sigaction.sa_flags & linux_sa_restorer != 0 && sigaction.sa_restorer != unsafe { nil } {
		return u64(sigaction.sa_restorer)
	}
	return process.sigreturn_page
}

// Whether a signal the current thread does not block waits for it, one that
// may be delivered at any instruction. Only a Linux frame keeps the FP/SIMD
// registers; a native program's is delivered at its next syscall, as before.
pub fn async_signal_deliverable() bool {
	t := proc.current_thread()
	if unsafe { t == nil } || t.sigentry != 0 {
		return false
	}
	return katomic.load(&t.pending_signals) & ~t.masked_signals != 0
}

pub fn dispatch_a_signal(context &cpulocal.GPRState) {
	dispatch_a_signal_with_fault(context, false, 0, 0)
}

// The part of signal delivery that may happen at any instruction: a signal
// whose action is to end the process. The scheduler tick calls this for a
// thread it has interrupted in userspace, so a loop that makes no syscalls can
// still be killed. A signal with a handler waits for the thread's next
// syscall, as before: running a handler at an arbitrary instruction would need
// the frame to carry the FP/SIMD registers, which it does not.
pub fn dispatch_fatal_signal(_ &cpulocal.GPRState) {
	t := proc.current_thread()
	if unsafe { t == nil } {
		return
	}
	pending := katomic.load(&t.pending_signals)
	if pending & (u64(1) << (sigkill - 1)) != 0 {
		exit_with_fatal_signal(u8(sigkill))
	}
	for i := u8(0); i < 64; i++ {
		bit := u64(1) << i
		if pending & bit == 0 || t.masked_signals & bit != 0 {
			continue
		}
		signum := int(i) + 1
		if t.sigactions[signum].sa_sigaction != sig_dfl || has_default_ignore_action(signum)
			|| signum == sigcont || signum == sigstop || signum == sigtstp
			|| signum == sigttin || signum == sigttou {
			continue
		}
		exit_with_fatal_signal(u8(signum))
	}
}

const linux_sa_restart = 0x10000000

// A syscall that a signal interrupted before it had done anything returns
// ERESTARTSYS. Rewind to the SVC so that it runs again once the signal has
// been dealt with, as Linux does: Go programs rely on SA_RESTART for calls
// they do not retry themselves, such as runc's blocking open of its exec FIFO,
// while the runtime preempts goroutines with SIGURG. The signal dispatched
// next takes the rewind back if its handler was installed without SA_RESTART.
pub fn prepare_syscall_restart(context &cpulocal.GPRState) {
	mut ctx := unsafe { context }
	if ctx.x0 != u64(-i64(proc.interrupted_errno)) {
		return
	}
	mut t := proc.current_thread()
	ctx.x0 = t.syscall_x0
	ctx.pc -= 4
	t.restarting_syscall = true
}

// Linux SA_SIGINFO handlers need the fault address and a usable ucontext. QEMU
// user mode depends on both: translated memory accesses deliberately fault in
// the host and its SIGSEGV handler turns that host context into a guest fault.
fn dispatch_a_signal_with_fault(context &cpulocal.GPRState, synchronous bool, fault_address u64, fault_esr u64) {
	mut t := unsafe { proc.current_thread() }
	restarting := t.restarting_syscall
	t.restarting_syscall = false

	mut which := -1

	for i := u8(0); i < 64; i++ {
		signum := int(i) + 1
		// SIGKILL and SIGSTOP can never be blocked, whatever the mask says. A
		// wait syscall that installed a full temporary mask must not be able to
		// keep the process alive against kill -9.
		unblockable := signum == sigkill || signum == sigstop
		if !unblockable && t.masked_signals & (u64(1) << i) != 0 {
			continue
		}
		if katomic.btr(mut &t.pending_signals, i) == true {
			which = signum
			break
		}
	}

	if which == -1 {
		return
	}
	timer_info := posixtimer.signal_info(t, which)
	posixtimer.acknowledge_signal(mut t, which)

	sigaction := t.sigactions[which]
	handler := sigaction.sa_sigaction

	// SIG_IGN (1): ignore the signal
	if handler == sig_ign {
		return
	}
	// SIG_DFL (0): terminate unless Linux defines an ignored, stop, or
	// continue disposition. Process stop/continue accounting is not implemented
	// yet, so those dispositions remain no-ops; ordinary terminating signals
	// must still tear the process down so kill(2) and shell cleanup work.
	if handler == sig_dfl {
		if !has_default_ignore_action(which) && which != sigcont && which != sigstop
			&& which != sigtstp && which != sigttin && which != sigttou {
			exit_with_fatal_signal(u8(which))
		}
		return
	}

	// A handler that did not ask for SA_RESTART sees the syscall fail with
	// EINTR instead of running again behind its back.
	if restarting && sigaction.sa_flags & sa_restart == 0 && sigaction.sa_flags & linux_sa_restart == 0 {
		mut ctx := unsafe { context }
		ctx.pc += 4
		ctx.x0 = u64(-i64(4))
	}

	// A sigsuspend(2) that installed a temporary mask wants the frame to carry
	// the mask from before the call, so that sigreturn restores that one.
	mut previous_mask := t.masked_signals
	if t.saved_mask_valid {
		previous_mask = t.saved_mask
		t.saved_mask_valid = false
	}

	t.masked_signals |= sigaction.sa_mask
	// Check SA_NODEFER: Vinix value (0x40) OR Linux value (0x40000000)
	if sigaction.sa_flags & sa_nodefer == 0 && sigaction.sa_flags & int(0x40000000) == 0 {
		t.masked_signals |= u64(1) << (which - 1)
	}

	// SA_ONSTACK runs the handler on the stack sigaltstack(2) registered, which
	// is the only way a SIGSEGV handler can run after a stack overflow.
	mut stack_top := context.sp
	if wants_altstack(t, sigaction) {
		stack_top = lib.align_down(t.sigaltstack_sp + t.sigaltstack_size, 16)
		t.on_sigaltstack = true
	}

	if t.sigentry != 0 {
		// ── Vinix/mlibc mode: dispatch via sigentry trampoline ──
		// ARM64 has no redzone. Use the live user SP from the kernel stack
		// frame (or the alternate stack), NOT t.gpr_state.sp which is stale
		// from the last timer preemption.
		mut signal_sp := lib.align_down(stack_top, 16)

		signal_sp -= sizeof(cpulocal.GPRState)
		signal_sp = lib.align_down(signal_sp, 16)
		return_context_addr := signal_sp

		mut siginfo_sp := signal_sp - sizeof(SigInfo)
		siginfo_sp = lib.align_down(siginfo_sp, 16)

		mut siginfo := SigInfo{}
		siginfo.si_signo = i32(which)

		// The stack may be unmapped or too small for the frame, for instance a
		// preemption signal that arrives with the SP deep in a small stack.
		// Write it through the pagemap so that turns into a killed process, as
		// on Linux, rather than a kernel-mode fault that takes the machine down.
		if !usercopy.copy_to_user(return_context_addr, voidptr(context), sizeof(cpulocal.GPRState))
			|| !usercopy.copy_to_user(siginfo_sp, voidptr(&siginfo), sizeof(SigInfo)) {
			exit_with_fatal_signal(u8(sigsegv))
		}

		t.gpr_state = *context
		t.gpr_state.sp = siginfo_sp
		t.gpr_state.pc = t.sigentry
		t.gpr_state.x0 = u64(which)
		t.gpr_state.x1 = siginfo_sp
		t.gpr_state.x2 = u64(handler)
		t.gpr_state.x3 = return_context_addr
		t.gpr_state.x4 = previous_mask

		enter_handler(mut t, context)
	} else if signal_restorer(t.process, &sigaction) != 0 {
		// ── Linux mode: set up signal frame on user stack ──
		// Frame layout: [prev_mask(8)] [pad(8)] [GPRState(sizeof)]
		// A three-argument SA_SIGINFO handler appends siginfo_t and an AArch64
		// ucontext_t. Synchronous faults always require those objects as well.
		// rt_sigreturn still consumes the compact private header at the front;
		// the appended ABI objects are for three-argument handlers.
		//
		// Every frame carries the ucontext, and in it the FP/SIMD registers,
		// as Linux's do: a signal may now arrive at any instruction a thread
		// runs in userspace, not only at a syscall, where the code it cuts
		// into has live values in all of them. rt_sigreturn puts them back.
		wants_siginfo := synchronous || sigaction.sa_flags & sa_siginfo != 0
			|| sigaction.sa_flags & 4 != 0 // Linux SA_SIGINFO
		context_offset := u64(16)
		info_offset := lib.align_up(context_offset + sizeof(cpulocal.GPRState), 16)
		ucontext_offset := info_offset + 128
		ucontext_size := u64(4560)
		frame_size := ucontext_offset + ucontext_size
		mut signal_sp := lib.align_down(stack_top - frame_size, 16)
		uc_address := signal_sp + ucontext_offset

		// Build the whole frame in kernel memory, then push it to the user
		// stack with a single checked copy. A preemption signal can arrive
		// with the SP deep in a small goroutine stack, so the frame may not
		// fit; the checked copy turns that into a killed process (Linux
		// force_sigsegv) instead of a kernel-mode fault that kills the machine.
		mut frame := []u8{len: int(frame_size)}
		base := u64(frame.data)
		unsafe {
			*&u64(base) = previous_mask
			// The private header points rt_sigreturn at the public context so
			// changes made by a three-argument handler are not discarded.
			*&u64(base + 8) = uc_address
			C.memcpy(voidptr(base + context_offset), context, sizeof(cpulocal.GPRState))
		}

		info_base := base + info_offset
		uc_base := base + ucontext_offset
		mut fpsimd := [fpsimd_state_size]u8{}
		C.vinix_aarch64_fpu_save(voidptr(&fpsimd[0]))
		unsafe {
			// siginfo_t: signo, errno, positive si_code, then si_addr. Linux
			// distinguishes an unmapped page from a permission-protected one.
			*&i32(info_base) = i32(which)
			*&i32(info_base + 8) = if timer_info.found {
				i32(timer_info.code)
			} else if synchronous && (fault_esr & 0x3f) >= 0x0c {
				2 // SEGV_ACCERR
			} else if synchronous {
				1 // SEGV_MAPERR (also the first positive code for other faults)
			} else {
				0
			}
			*&u64(info_base + 16) = fault_address
			if timer_info.found {
				*&i32(info_base + 20) = i32(timer_info.overrun)
				*&u64(info_base + 24) = timer_info.value
			}

			// musl AArch64 ucontext_t offsets. The signal mask begins at 40;
			// its 128 bytes are followed by eight bytes of alignment before
			// mcontext at 176. The reserved extension records are 16-byte
			// aligned after pstate.
			*&u64(uc_base + 40) = previous_mask
			*&u64(uc_base + 176) = fault_address
			C.memcpy(voidptr(uc_base + 184), context, 31 * sizeof(u64))
			*&u64(uc_base + 432) = context.sp
			*&u64(uc_base + 440) = context.pc
			*&u64(uc_base + 448) = context.pstate

			// fpsimd_context first, as Linux lays the records out: the
			// FPSR and FPCR, then the 32 vector registers.
			*&u32(uc_base + 464) = fpsimd_magic
			*&u32(uc_base + 468) = fpsimd_context_size
			*&u32(uc_base + 472) = *&u32(&fpsimd[512])
			*&u32(uc_base + 476) = *&u32(&fpsimd[516])
			C.memcpy(voidptr(uc_base + 480), &fpsimd[0], 512)
			// esr_context lets QEMU distinguish reads from writes without
			// decoding the faulting AArch64 instruction.
			*&u32(uc_base + 992) = 0x45535201
			*&u32(uc_base + 996) = 16
			*&u64(uc_base + 1000) = fault_esr
			// A zero header terminates the extension-record chain.
			*&u64(uc_base + 1008) = 0
		}

		pushed := usercopy.copy_to_user(signal_sp, frame.data, frame_size)
		unsafe { frame.free() }
		if !pushed {
			exit_with_fatal_signal(u8(sigsegv))
		}

		// Set up handler invocation
		t.gpr_state = *context
		t.gpr_state.sp = signal_sp
		t.gpr_state.pc = u64(handler)
		t.gpr_state.x30 = signal_restorer(t.process, &sigaction)
		t.gpr_state.x0 = u64(which)
		if wants_siginfo {
			t.gpr_state.x1 = signal_sp + info_offset
			t.gpr_state.x2 = signal_sp + ucontext_offset
		}

		enter_handler(mut t, context)
	}
	// else: no sigentry and no restorer — silently drop signal
}

// Deliver a fault raised by the current userspace instruction immediately.
// Unlike sendsig(), this must not enqueue the thread which is already running.
// The return value tells the exception path whether a usable handler replaced
// the faulting PC; otherwise the normal fatal handling still applies.
pub fn dispatch_sync_signal(context &cpulocal.GPRState, signal u8) bool {
	if signal == 0 || signal > 64 {
		return false
	}
	mut current_thread := proc.current_thread()
	// A CPU with no thread on it has nobody to signal. That should only reach
	// here through a kernel fault misread as a userspace one, but raising a
	// signal on a nil thread turns that mistake into a second fault inside the
	// report, which is how the first one stayed invisible.
	if current_thread == unsafe { nil } {
		return false
	}
	original_pc := context.pc
	katomic.bts(mut &current_thread.pending_signals, signal - 1)
	dispatch_a_signal_with_fault(context, true, context.pc, 0)
	return context.pc != original_pc
}

// Deliver a synchronous memory fault with the host address and ESR preserved
// for an SA_SIGINFO handler.
pub fn dispatch_sync_fault(context &cpulocal.GPRState, fault_address u64, fault_esr u64) bool {
	mut current_thread := proc.current_thread()
	if current_thread == unsafe { nil } {
		return false
	}
	original_pc := context.pc
	katomic.bts(mut &current_thread.pending_signals, u8(sigsegv - 1))
	dispatch_a_signal_with_fault(context, true, fault_address, fault_esr)
	return context.pc != original_pc
}

fn wants_altstack(t &proc.Thread, sigaction proc.SigAction) bool {
	// SA_ONSTACK is 1 << 1 for Vinix and 1 << 27 for Linux.
	if sigaction.sa_flags & sa_onstack == 0 && sigaction.sa_flags & int(0x08000000) == 0 {
		return false
	}
	// Nesting onto an alternate stack already in use would overwrite the frame
	// the outer handler is standing on.
	return t.sigaltstack_sp != 0 && t.sigaltstack_size != 0 && !t.on_sigaltstack
}

// Enter the handler by rewriting the exception frame that the syscall exit path
// is about to restore. Handing the thread to the scheduler instead only works
// while some other thread is runnable: a thread on its own would park in the
// idle loop still holding its run queue lock, where get_next_thread can never
// pick it back up, and the handler would never run.
fn enter_handler(mut t proc.Thread, context &cpulocal.GPRState) {
	mut frame := unsafe { &cpulocal.GPRState(context) }

	unsafe {
		*frame = t.gpr_state
	}
}

// Signal N lives in bit N-1 of the pending and blocked words, the same layout a
// userspace sigset_t uses. Keeping the two identical means masks can cross the
// syscall boundary untouched, and it leaves room for all 64 signals in a u64.
pub fn sendsig(_thread &proc.Thread, signal u8) {
	mut t := unsafe { _thread }

	if signal == 0 || signal > 64 {
		return
	}

	// An ignored signal is dropped, unless the thread blocks it: as on Linux,
	// a blocked signal is kept pending whatever its disposition, for
	// sigwait(2) and signalfd(2) to take. MariaDB's signal thread waits in
	// sigwait() for the one its shutdown sends it, and the bootstrap server
	// that creates its data directory never finished stopping.
	handler := t.sigactions[signal].sa_sigaction
	blocked := katomic.load(&t.masked_signals) & (u64(1) << (signal - 1)) != 0
	if !blocked && (handler == sig_ign
		|| (handler == sig_dfl && has_default_ignore_action(int(signal)))) {
		return
	}

	posixtimer.clear_signal_info(mut t, int(signal))
	katomic.bts(mut &t.pending_signals, signal - 1)
	if t.process != unsafe { nil } {
		notify_signalfds(t.process.pid, int(signal))
	}

	// Wake the thread when it can take the signal now, or waits for it in
	// sigtimedwait(). A signal it blocks otherwise just stays pending: waking
	// it for one ended whatever it was waiting in with EINTR for nothing.
	if !blocked || katomic.load(&t.sigwait_set) & (u64(1) << (signal - 1)) != 0 {
		sched.enqueue_thread(t, true)
	}
}

// Deliver a signal aimed at a whole process. Signal state is per-thread here,
// so there is no process-wide pending mask to raise; the signal goes to the
// first thread that does not block it, as Linux picks one, and only when every
// thread blocks it does it wait on the main thread. Always choosing the main
// thread lost signals for good in Go programs, whose main thread commonly sits
// with them blocked while other threads are the ones meant to take them.
//
// Linux keeps such a signal pending on the process, where any thread waiting
// for it in sigwait(2) takes it. The nearest here is to give it to a thread
// that waits for it now: MariaDB blocks SIGTERM in every thread, sends it to
// its own pid to stop the thread that sigwait()s for it, and that thread
// never saw it on the main thread, so the server never stopped.
fn signal_process(mut target proc.Process, signal int) bool {
	bit := u64(1) << (signal - 1)
	unblockable := signal == sigkill || signal == sigstop
	target.threads_lock.acquire()
	mut chosen := &proc.Thread(unsafe { nil })
	mut waiting := &proc.Thread(unsafe { nil })
	for t in target.threads {
		if katomic.load(&t.is_dead) {
			continue
		}
		if chosen == unsafe { nil } {
			chosen = t
		}
		if unblockable || t.masked_signals & bit == 0 {
			chosen = t
			waiting = unsafe { nil }
			break
		}
		if waiting == unsafe { nil } && katomic.load(&t.sigwait_set) & bit != 0 {
			waiting = t
		}
	}
	if waiting != unsafe { nil } {
		chosen = waiting
	}
	if chosen != unsafe { nil } {
		proc.pin_thread(chosen)
	}
	target.threads_lock.release()

	if chosen == unsafe { nil } {
		return false
	}

	sendsig(chosen, u8(signal))
	proc.unpin_thread(chosen)
	return true
}

// Send `signal` to process `pid` from inside the kernel: cgroup.kill, the death
// of a pid namespace's init, and PR_SET_PDEATHSIG all end up here.
pub fn signal_pid(pid int, signal int) {
	if pid <= 0 || pid >= proc.max_pid || signal <= 0 || signal > 64 {
		return
	}
	mut target := processes[pid]
	if target == unsafe { nil } || target.exiting {
		return
	}
	signal_process(mut target, signal)
}

// kill(2). Signal 0 raises nothing: it is the "does this pid exist?" probe that
// shells and daemons use, so it must never fail loudly.
// cgroup.kill: fs asks the signal layer to kill a member of a cgroup. Kept
// here because fs cannot reach the signal code, which sits above it.
pub fn cgroup_kill_process(pid int, signal int) {
	if pid <= 0 || pid >= proc.max_pid {
		return
	}
	mut target := processes[pid]
	if target == unsafe { nil } {
		return
	}
	signal_process(mut target, signal)
}

pub fn syscall_kill(_ voidptr, pid int, signal int) (u64, u64) {
	if signal < 0 || signal > 64 {
		return errno.err, errno.einval
	}

	mut current_process := proc.current_thread().process
	// Pids and groups are the caller's namespace's numbers.
	viewer := current_process.numbered_in

	if pid > 0 {
		if pid >= proc.max_pid {
			return errno.err, errno.esrch
		}
		global := proc.pid_from(viewer, pid)
		if global <= 0 {
			return errno.err, errno.esrch
		}
		mut target := processes[global]
		if target == unsafe { nil } {
			return errno.err, errno.esrch
		}
		if signal == 0 {
			return 0, 0
		}
		if !signal_process(mut target, signal) {
			// A zombie still owns its pid but has no thread left to signal.
			return 0, 0
		}
		return 0, 0
	}

	// 0 means our own process group, anything below -1 names a group directly,
	// and -1 means every process we are allowed to signal.
	mut pgid := 0
	if pid == 0 {
		pgid = current_process.pgid
	} else if pid < -1 {
		pgid = proc.group_from(viewer, -pid)
		if pgid == 0 {
			return errno.err, errno.esrch
		}
	}
	// A namespace's -1 reaches its own members only, and spares its init.
	init_pid := if proc.numbers_own(viewer) { viewer.init_pid } else { 1 }

	mut found := false
	for i := 1; i < proc.max_pid; i++ {
		mut target := processes[i]
		if target == unsafe { nil } {
			continue
		}
		if pgid != 0 && target.pgid != pgid {
			continue
		}
		if proc.numbers_own(viewer) && voidptr(target.numbered_in) != voidptr(viewer) {
			continue
		}
		if pid == -1 && (target.pid == init_pid || target.pid == current_process.pid) {
			continue
		}

		found = true
		if signal != 0 {
			signal_process(mut target, signal)
		}
	}

	if !found {
		return errno.err, errno.esrch
	}

	return 0, 0
}

// tkill(2): musl's raise() and pthread_kill() aim at one thread rather than at
// the process as a whole.
pub fn syscall_tkill(_ voidptr, tid int, signal int) (u64, u64) {
	return signal_thread(0, tid, signal)
}

// tgkill(2): the same, with the thread group checked so that a recycled tid
// cannot be signalled by mistake.
pub fn syscall_tgkill(_ voidptr, tgid int, tid int, signal int) (u64, u64) {
	return signal_thread(tgid, tid, signal)
}

fn signal_thread(tgid int, tid int, signal int) (u64, u64) {
	if signal < 0 || signal > 64 || tid <= 0 {
		return errno.err, errno.einval
	}

	// Go preempts its threads with tgkill(SIGURG) from every CPU, and those
	// threads come and go all the time; the pin keeps a target that exits in the
	// meantime from being freed and reused before the signal is on it.
	viewer := proc.current_pid_namespace()
	mut target := proc.thread_in(viewer, tid)
	if target == unsafe { nil } {
		return errno.err, errno.esrch
	}
	defer {
		proc.unpin_thread(target)
	}
	if katomic.load(&target.is_dead) {
		return errno.err, errno.esrch
	}
	if tgid > 0 && proc.pid_in(target.process, viewer) != tgid {
		return errno.err, errno.esrch
	}
	if signal == 0 {
		return 0, 0
	}

	sendsig(target, u8(signal))

	return 0, 0
}

pub fn syscall_execve(_ voidptr, _path charptr, _argv &charptr, _envp &charptr) (u64, u64) {
	// This first marker intentionally precedes the user-pointer copy. The
	// launcher has already named the program in its own last message, and this
	// distinguishes a syscall-entry failure from a later ELF-loader failure.
	println('exec: syscall handler entered; copying user path')
	path := fs.user_path(_path) or {
		println('exec: ERROR copying user path')
		return errno.err, errno.get()
	}
	trace_gpu := path == gpu_desktop_executable
	gpu_exec_trace(trace_gpu, 'user path copied')
	mut argv := []string{}
	gpu_exec_trace(trace_gpu, 'copying argument vector')
	for i := 0; true; i++ {
		unsafe {
			if _argv[i] == nil {
				break
			}
			argv << cstring_to_vstring(_argv[i])
		}
	}
	gpu_exec_trace(trace_gpu, 'argument vector copied')
	mut envp := []string{}
	gpu_exec_trace(trace_gpu, 'copying environment')
	for i := 0; true; i++ {
		unsafe {
			if _envp[i] == nil {
				break
			}
			envp << cstring_to_vstring(_envp[i])
		}
	}
	gpu_exec_trace(trace_gpu, 'environment copied; entering ELF loader')

	start_program(true, proc.current_directory_of(proc.current_thread().process), path, argv, envp,
		'', '', '') or { return errno.err, errno.get() }

	return errno.err, errno.get()
}

pub fn start_program(execve bool, dir &fs.VFSNode, _path string, argv []string, envp []string, stdin_path string, stdout_path string, stderr_path string) ?&proc.Process {
	// Chromium starts every child process by executing /proc/self/exe. The VFS
	// resolves that to this process's program, but the new process must record
	// where the program really is: keeping the literal path would make the
	// child's own /proc/self/exe point back at itself forever.
	path := fs.resolve_self_reference(_path)
	prog_node := fs.get_node(dir, path, true)?
	return start_program_node(execve, dir, prog_node, path, argv, envp, stdin_path,
		stdout_path, stderr_path)
}

// An image the loader turned down is not an executable, as Linux answers:
// ENOEXEC. The loader's errors carry no errno, and exec reported whatever
// an earlier call had left -- ENOENT once, EPERM after -- for a program it
// could not read. Only a segment that could not be mapped keeps the errno
// the mapping set.
fn exec_format_error(err IError) ?&proc.Process {
	if !err.msg().starts_with('elf: unable to map') {
		errno.set(errno.enoexec)
	}
	return none
}

// The part of exec that follows finding the program. execveat(2) on a
// descriptor comes here directly: a memfd has no name to be found by.
pub fn start_program_node(execve bool, dir &fs.VFSNode, prog_node &fs.VFSNode, path string, argv []string, envp []string, stdin_path string, stdout_path string, stderr_path string) ?&proc.Process {
	trace_gpu := execve && path == gpu_desktop_executable
	gpu_exec_trace(trace_gpu, 'resolved executable path')
	gpu_exec_trace(trace_gpu, 'opened executable node')
	// A program's interpreter is found from the root of the process that runs
	// it -- a container's, after pivot_root.
	caller := proc.current_thread().process
	root := fs.process_root(caller)
	program_path := fs.program_path(prog_node, path)
	if !stat.isreg(prog_node.resource.stat.mode)
		|| !fs.check_access(prog_node, fs.access_exec, true) {
		errno.set(errno.eacces)
		return none
	}
	gpu_exec_trace(trace_gpu, 'validated executable permissions')
	mut prog := prog_node.resource

	// Check for shebang before proceeding as if it was an ELF.
	mut shebang := [2]char{}
	prog.read(0, &shebang[0], 0, 2)?
	gpu_exec_trace(trace_gpu, 'read executable signature')
	if shebang[0] == char(`#`) && shebang[1] == char(`!`) {
		real_path, arg := parse_shebang(mut prog)?
		mut final_argv := [real_path]
		if arg != '' {
			final_argv << arg
		}
		final_argv << path
		final_argv << argv[1..]

		return start_program(execve, dir, real_path, final_argv, envp, stdin_path, stdout_path,
			stderr_path)
	}

	// ARM64 cannot enter an x86-64 ELF directly. Re-exec it through the native
	// QEMU user-mode translator and its private x86-64 musl root. Doing this in
	// the kernel exec path also catches helper programs that Wine starts itself,
	// rather than only binaries launched through the shell wrapper.
	architecture := elf.architecture(prog) or { return exec_format_error(err) }
	gpu_exec_trace(trace_gpu, 'validated ELF architecture')
	if architecture == elf.arch_x86_64 {
		translator := '/usr/bin/qemu-x86_64'
		guest_root := '/usr/libexec/vinix-x86_64/root'
		mut translated_argv := [translator, '-B', '0x100000000', '-L', guest_root,
			path]
		if argv.len > 1 {
			translated_argv << argv[1..]
		}

		mut translated_envp := envp.clone()
		mut has_library_path := false
		for environment_entry in translated_envp {
			if environment_entry.starts_with('LD_LIBRARY_PATH=') {
				has_library_path = true
				break
			}
		}
		if !has_library_path {
			translated_envp << 'LD_LIBRARY_PATH=${guest_root}/lib:${guest_root}/usr/lib'
		}

		return start_program(execve, root, translator, translated_argv, translated_envp,
			stdin_path, stdout_path, stderr_path)
	}

	gpu_exec_trace(trace_gpu, 'allocating replacement page map')
	mut new_pagemap := memory.new_pagemap()
	gpu_exec_trace(trace_gpu, 'allocated replacement page map')
	gpu_exec_trace(trace_gpu, 'loading program ELF segments')
	mut auxval := elf.Auxval{}
	mut ld_path := ''
	if trace_gpu {
		auxval, ld_path = elf.load_traced(new_pagemap, prog, 0, 'program') or {
			return exec_format_error(err)
		}
	} else {
		auxval, ld_path = elf.load(new_pagemap, prog, 0) or { return exec_format_error(err) }
	}
	gpu_exec_trace(trace_gpu, 'program ELF segments loaded')
	allow_wx := envp.contains('VINIX_ALLOW_WX=1')

	mut entry_point := unsafe { nil }

	if ld_path == '' {
		entry_point = voidptr(auxval.at_entry)
		gpu_exec_trace(trace_gpu, 'using program entry point (no interpreter)')
	} else {
		gpu_exec_trace(trace_gpu, 'opening ELF interpreter')
		ld_node := fs.get_node(root, ld_path, true)?
		if !stat.isreg(ld_node.resource.stat.mode)
			|| !fs.check_access(ld_node, fs.access_exec, true) {
			errno.set(errno.eacces)
			return none
		}
		ld := ld_node.resource

		gpu_exec_trace(trace_gpu, 'choosing ELF interpreter load base')
		interpreter_base := elf.interpreter_load_base()
		gpu_exec_trace(trace_gpu, 'loading ELF interpreter segments')
		mut ld_auxval := elf.Auxval{}
		mut interp := ''
		if trace_gpu {
			ld_auxval, interp = elf.load_traced(new_pagemap, ld, interpreter_base,
				'interpreter') or {
				return exec_format_error(err)
			}
		} else {
			ld_auxval, interp = elf.load(new_pagemap, ld, interpreter_base) or {
				return exec_format_error(err)
			}
		}
		gpu_exec_trace(trace_gpu, 'ELF interpreter segments loaded')

		if interp != '' {
			unsafe { interp.free() }
		}

		entry_point = voidptr(ld_auxval.at_entry)
		auxval.at_base = ld_auxval.at_base
		if trace_gpu {
			println('exec[gpu]: interpreter entry=0x${u64(entry_point):x} program entry=0x${auxval.at_entry:x}')
		}

		unsafe { ld_path.free() }
	}
	sigreturn_page := install_sigreturn_page(mut new_pagemap) or { return none }

	if execve == false {
		mut new_process := sched.new_process(unsafe { nil }, new_pagemap)?

		new_process.name = '${path}[${new_process.pid}]'
		new_process.executable_path = program_path
		new_process.exe_node = voidptr(prog_node)
		new_process.allow_wx = allow_wx
		new_process.sigreturn_page = sigreturn_page

		stdin_node := fs.get_node(vfs_root, stdin_path, true)?
		stdin_handle := &file.Handle{
			resource: stdin_node.resource
			node:     stdin_node
			refcount: 1
		}
		stdin_fd := &file.FD{
			handle: stdin_handle
		}
		new_process.fds[0] = voidptr(stdin_fd)

		stdout_node := fs.get_node(vfs_root, stdout_path, true)?
		stdout_handle := &file.Handle{
			resource: stdout_node.resource
			node:     stdout_node
			refcount: 1
			flags:    resource.o_wronly
		}
		stdout_fd := &file.FD{
			handle: stdout_handle
		}
		new_process.fds[1] = voidptr(stdout_fd)

		stderr_node := fs.get_node(vfs_root, stderr_path, true)?
		stderr_handle := &file.Handle{
			resource: stderr_node.resource
			node:     stderr_node
			refcount: 1
			flags:    resource.o_wronly
		}
		stderr_fd := &file.FD{
			handle: stderr_handle
		}
		new_process.fds[2] = voidptr(stderr_fd)

		sched.new_user_thread(new_process, true, entry_point, unsafe { nil }, 0, argv,
			envp, auxval, true)?

		return new_process
	} else {
		mut t := proc.current_thread()
		mut curr_process := t.process
		gpu_exec_trace(trace_gpu, 'beginning process image replacement')

		// Every other thread has to be gone before the address space they are
		// running in is replaced -- and before the close-on-exec descriptors
		// go, as on Linux: a sibling unwinding a syscall still reaches the
		// descriptor it was called on.
		gpu_exec_trace(trace_gpu, 'stopping sibling threads')
		kill_sibling_threads(mut curr_process, t)
		gpu_exec_trace(trace_gpu, 'sibling threads stopped')

		// Close O_CLOEXEC file descriptors before exec.
		// This is critical for pipe EOF detection: popen creates pipes
		// with O_CLOEXEC, and leaked FDs prevent pipe refcount from
		// reaching 1, blocking EOF on reads.
		gpu_exec_trace(trace_gpu, 'scanning close-on-exec descriptors')
		for i := 0; i < curr_process.fds.len; i++ {
			fd_ptr := unsafe { &file.FD(curr_process.fds[i]) }
			if fd_ptr == unsafe { nil } {
				continue
			}
			if fd_ptr.flags & resource.o_cloexec != 0 {
				file.fdnum_close(curr_process, i, true) or {}
			}
		}
		gpu_exec_trace(trace_gpu, 'closed close-on-exec descriptors')
		gpu_exec_trace(trace_gpu, 'removing process timers')
		posixtimer.remove_process_timers(curr_process)
		gpu_exec_trace(trace_gpu, 'process timers removed')

		// Swapped under the process table lock, which cgroup memory accounting
		// and /proc hold while they walk a process' page map: the old one is
		// freed below.
		proc.lock_table()
		mut old_pagemap := curr_process.pagemap
		curr_process.pagemap = new_pagemap
		proc.unlock_table()

		curr_process.name = '${path}[${curr_process.pid}]'
		curr_process.executable_path = program_path
		curr_process.exe_node = voidptr(prog_node)
		curr_process.allow_wx = allow_wx
		curr_process.sigreturn_page = sigreturn_page
		// execve recomputes the capability sets from the new credentials and
		// the bounding set, which is how a container's root ends up with only
		// the capabilities its runtime left it.
		proc.capabilities_after_exec(mut curr_process)
		gpu_exec_trace(trace_gpu, 'installed replacement process metadata')

		gpu_exec_trace(trace_gpu, 'switching CPU to kernel page map')
		kernel_pagemap.switch_to()
		gpu_exec_trace(trace_gpu, 'switched CPU to kernel page map')
		t.process = kernel_process
		gpu_exec_trace(trace_gpu, 'detached execve thread from old process')

		gpu_exec_trace(trace_gpu, 'deleting old process page map')
		if trace_gpu {
			mmap.delete_pagemap_traced(mut old_pagemap)?
		} else {
			mmap.delete_pagemap(mut old_pagemap)?
		}
		gpu_exec_trace(trace_gpu, 'old process page map deleted')

		curr_process.thread_stack_top = elf.initial_stack_top()
		curr_process.mmap_anon_non_fixed_base = elf.initial_mmap_base()
		// The new program has no break yet; its first brk() reserves the arena
		// in the address space it now has.
		curr_process.brk_base = 0
		curr_process.brk_current = 0

		curr_process.threads_lock.acquire()
		curr_process.threads = []&proc.Thread{}
		curr_process.threads_lock.release()
		gpu_exec_trace(trace_gpu, 'reset process thread metadata')

		// The program that comes out of exec has one thread and it is the group
		// leader, so it takes over the pid as its tid. Anything else this
		// thread was holding goes back to the namespace.
		if t.tid != curr_process.pid {
			proc.free_tid(t.tid)
		}

		// The program keeps the scheduling policy of the thread that execs it.
		// `chrt -f 50 ./program` is one process: it gives itself the priority
		// and then becomes the program that was meant to have it. Installed
		// before the thread is enqueued, so it is never picked up as an
		// ordinary thread first.
		inherited_sched := t.sched
		gpu_exec_trace(trace_gpu, 'building replacement user thread and stack')
		mut new_thread := sched.new_user_thread(curr_process, true, entry_point, unsafe { nil },
			0, argv, envp, auxval, false)?
		if trace_gpu {
			println('exec[gpu]: replacement thread built pc=0x${new_thread.gpr_state.pc:x} sp=0x${new_thread.gpr_state.sp:x} tid=${new_thread.tid}')
		}
		proc.set_thread_sched_params(new_thread.tid, inherited_sched)
		gpu_exec_trace(trace_gpu, 'inherited scheduler parameters')
		if trace_gpu {
			gpu_exec_trace(trace_gpu, 'disabling interrupts for atomic same-CPU handoff')
			cpu.interrupt_toggle(false)
			gpu_exec_trace(trace_gpu, 'handoff interrupts disabled')
		}
		enqueued := if trace_gpu {
			sched.enqueue_thread_traced(new_thread, false)
		} else {
			sched.enqueue_thread(new_thread, false)
		}
		if enqueued {
			gpu_exec_trace(trace_gpu, 'replacement thread enqueued')
		} else {
			gpu_exec_trace(trace_gpu, 'ERROR: replacement thread enqueue failed')
		}

		unsafe {
			argv.free()
			envp.free()
		}
		gpu_exec_trace(trace_gpu, 'retiring original execve thread')
		if trace_gpu {
			sched.dequeue_and_die_traced()
		}
		sched.dequeue_and_die()
	}
}

pub fn parse_shebang(mut res resource.Resource) ?(string, string) {
	// Parse the shebang that we already know is there.
	// Syntax: #![whitespace]interpreter [single arg]new line
	mut index := u64(2)
	mut build_path := strings.new_builder(512)
	mut build_arg := strings.new_builder(512)

	mut c := char(0)
	res.read(0, &c, index, 1)?
	if c == char(` `) {
		index++
	}

	for {
		res.read(0, &c, index, 1)?
		index++
		if c == char(` `) {
			break
		}
		if c == char(`\n`) {
			unsafe {
				goto ret
			}
		}
		build_path.write_rune(rune(c))
	}

	for {
		res.read(0, &c, index, 1)?
		index++
		if c == char(` `) || c == char(`\n`) {
			break
		}
		build_arg.write_rune(rune(c))
	}

	ret:
	final_path := build_path.str()
	final_arg := build_arg.str()
	unsafe {
		build_path.free()
		build_arg.free()
	}
	return final_path, final_arg
}

// execveat(dirfd, path, argv, envp, flags): execve relative to a directory
// descriptor. AT_EMPTY_PATH with an empty path runs the descriptor itself,
// which is what fexecve(3) is built from.
pub fn syscall_execveat(_ voidptr, dirfd int, _path charptr, _argv &charptr, _envp &charptr, flags int) (u64, u64) {
	mut process := proc.current_thread().process

	path := fs.user_path(_path) or { return errno.err, errno.get() }

	mut directory := &fs.VFSNode(unsafe { nil })
	mut target := path

	mut direct_node := &fs.VFSNode(unsafe { nil })
	if path.len == 0 {
		if flags & fs.at_empty_path == 0 {
			return errno.err, errno.enoent
		}
		// Run whatever the descriptor is open on. Its parent, when it has one,
		// is what a relative interpreter path then resolves against.
		mut fd := file.fd_from_fdnum(process, dirfd) or { return errno.err, errno.ebadf }
		node := unsafe { &fs.VFSNode(fd.handle.node) }
		fd.unref()
		if node == unsafe { nil } {
			return errno.err, errno.eacces
		}
		direct_node = node
		directory = if node.parent != unsafe { nil } {
			node.parent
		} else {
			unsafe { &fs.VFSNode(proc.current_directory_of(process)) }
		}
		target = '/proc/self/fd/${dirfd}'
	} else {
		directory = fs.parent_dir_for(dirfd, path) or { return errno.err, errno.get() }
	}

	mut argv := []string{}
	for i := 0; true; i++ {
		unsafe {
			if _argv[i] == nil {
				break
			}
			argv << cstring_to_vstring(_argv[i])
		}
	}
	mut envp := []string{}
	for i := 0; true; i++ {
		unsafe {
			if _envp[i] == nil {
				break
			}
			envp << cstring_to_vstring(_envp[i])
		}
	}

	if direct_node != unsafe { nil } {
		start_program_node(true, directory, direct_node, target, argv, envp, '', '', '') or {
			return errno.err, errno.get()
		}
		return errno.err, errno.get()
	}
	start_program(true, directory, target, argv, envp, '', '', '') or {
		return errno.err, errno.get()
	}

	return errno.err, errno.get()
}

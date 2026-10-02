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
import krandom
import posixtimer
import errno
import lib
import strings
import resource
import usercopy
import stat

const gpu_desktop_executable = '/usr/bin/vinix-desktop-gpu'

// V's print path reaches both the UART and framebuffer console in production
// kernels. C.printf is intentionally compiled to a no-op in PROD, so it must
// not be used for boot diagnostics that need to be visible on the M1 panel.
fn gpu_exec_trace(enabled bool, stage string) {
	if enabled {
		C.kprintf(c'exec[gpu]: %.*s\n', i32(stage.len), stage.str)
	}
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

pub fn syscall_sigentry(_ voidptr, sigentry u64) (u64, u64) {
	mut t := proc.current_thread()

	t.sigentry = sigentry

	return 0, 0
}

// A Linux signal frame begins with a header of Vinix's own that only
// rt_sigreturn reads: the mask to restore, the address of the public
// ucontext, the registers, and the cookie that signs the frame (see
// proc/sigcookie.v). siginfo_t and the ucontext follow.
fn linux_frame_cookie_offset() u64 {
	return 16 + sizeof(cpulocal.GPRState)
}

fn linux_frame_info_offset() u64 {
	return lib.align_up(linux_frame_cookie_offset() + sizeof(u64), 16)
}

fn linux_frame_ucontext_offset() u64 {
	return linux_frame_info_offset() + 128
}

// Whether the frame at `frame` was one the kernel built for this process, and
// if so spend its cookie, so that the frame cannot be returned through twice.
fn take_sigframe_cookie(frame u64, cookie_address u64) bool {
	mut cookie := u64(0)
	if !usercopy.copy_from_user(voidptr(&cookie), cookie_address, sizeof(u64)) {
		return false
	}
	if cookie != proc.sigframe_cookie(proc.current_thread().process, frame) {
		return false
	}
	spent := u64(0)
	return usercopy.copy_to_user(cookie_address, voidptr(&spent), sizeof(u64))
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
		// The cookie follows the registers; a context the kernel did not
		// build is an attack, not a mistake.
		if !take_sigframe_cookie(u64(context_arg), u64(context_arg) + sizeof(cpulocal.GPRState)) {
			exit_with_fatal_signal(u8(sigsegv))
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
		// Nothing in the frame is believed until its cookie is: a forged
		// frame is an attack, not a mistake.
		if !take_sigframe_cookie(user_sp, user_sp + linux_frame_cookie_offset()) {
			exit_with_fatal_signal(u8(sigsegv))
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
			// The kernel put the ucontext right after the header; a pointer
			// anywhere else would bring back registers the cookie never
			// covered.
			if public_context != user_sp + linux_frame_ucontext_offset() {
				exit_with_fatal_signal(u8(sigsegv))
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
// somewhere in the gigabyte above the highest place the stack can start, a
// different page for every program, as OpenBSD places its signal trampoline:
// a gadget at a fixed address is one an exploit needs no leak to find.
const sigreturn_page_base = u64(0x70000000000)
const sigreturn_page_span = u64(0x40000000)
const linux_sa_restorer = 0x04000000

fn sigreturn_page_address() u64 {
	mut random := u64(0)
	krandom.fill(voidptr(&random), sizeof(random), true)
	return sigreturn_page_base + (random % (sigreturn_page_span / page_size)) * page_size
}

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
	address := sigreturn_page_address()
	mmap.map_range(mut pagemap, address, u64(page), page_size, mmap.prot_read | mmap.prot_exec,
		mmap.map_private) or {
		memory.pmm_free(page, 1)
		return none
	}
	return address
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

// The scheduler can restore a selected thread without running the lower-EL
// interrupt exit. Redirect that return first, just as AMD64 interrupt_return
// does, so handler signals and must_exit cannot wait forever in two busy
// sibling loops. This only writes trusted kernel-owned context.
pub fn interrupt_return(context &cpulocal.GPRState) {
	mut t := proc.current_thread()
	if t == unsafe { nil } || context.pstate & 0xf != 0 { return }
	pending := katomic.load(&t.pending_signals)
	deliverable := ~t.masked_signals | unblockable_mask()
	if !katomic.load(&t.must_exit) && pending & deliverable == 0 { return }
	t.async_context = *context
	mut frame := unsafe { context }
	frame.pc = u64(voidptr(async_signal_entry))
	frame.sp = t.kernel_stack & ~u64(0xf)
	frame.x30 = 0
	frame.pstate = (cpu.read_currentel() << 2) | 1 | u64(0x3c0) | kernel_pstate_pan
	proc.cpu_enter_kernel()
}

fn C.sched_switch_context(voidptr, u64)

@[noreturn]
fn async_signal_entry() {
	cpu.interrupt_toggle(false)
	mut t := proc.current_thread()
	mut context := t.async_context
	exit_if_told_to()
	// The scheduler restored this thread's SIMD state before redirecting its
	// frame. Dispatch uses the existing fpsimd signal-frame save/restore path;
	// a no-op dispatch also leaves the live SIMD registers intact.
	if t.sigentry != 0 {
		// Native signal frames do not retain SIMD. Keep their custom handlers
		// at syscall boundaries, but deliver fatal signals on our owned stack.
		dispatch_fatal_signal(&context)
	} else {
		dispatch_a_signal(&context)
	}
	t.gpr_state = context
	proc.cpu_leave_kernel()
	C.sched_switch_context(voidptr(&t.gpr_state), t.kernel_stack)
	for {}
}

pub fn dispatch_a_signal(context &cpulocal.GPRState) {
	dispatch_a_signal_with_fault(context, false, 0, 0)
}

// Native signal frames lack SIMD state, so the asynchronous trampoline only
// dispatches fatal dispositions for that ABI. Custom native handlers stay at
// syscall boundaries. Linux handlers use the complete fpsimd frame above.
pub fn dispatch_fatal_signal(_ &cpulocal.GPRState) {
	mut t := proc.current_thread()
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
		if t.sigactions[signum].sa_sigaction == sig_dfl && is_stop_signal(signum) {
			katomic.btr(mut &t.pending_signals, i)
			stop_for_signal(signum)
			return
		}
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
	// Default stop dispositions park every sibling until SIGCONT arrives.
	if handler == sig_dfl {
		if is_stop_signal(which) {
			stop_for_signal(which)
		} else if !has_default_ignore_action(which) && which != sigcont {
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

		// The registers, then the cookie that signs them.
		signal_sp -= sizeof(cpulocal.GPRState) + sizeof(u64)
		signal_sp = lib.align_down(signal_sp, 16)
		return_context_addr := signal_sp
		cookie := proc.sigframe_cookie(t.process, return_context_addr)

		mut siginfo_sp := signal_sp - sizeof(SigInfo)
		siginfo_sp = lib.align_down(siginfo_sp, 16)

		mut siginfo := SigInfo{}
		siginfo.si_signo = i32(which)

		// The stack may be unmapped or too small for the frame, for instance a
		// preemption signal that arrives with the SP deep in a small stack.
		// Write it through the pagemap so that turns into a killed process, as
		// on Linux, rather than a kernel-mode fault that takes the machine down.
		if !usercopy.copy_to_user(return_context_addr, voidptr(context), sizeof(cpulocal.GPRState))
			|| !usercopy.copy_to_user(return_context_addr + sizeof(cpulocal.GPRState), voidptr(&cookie),
			sizeof(u64))
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
		info_offset := linux_frame_info_offset()
		ucontext_offset := linux_frame_ucontext_offset()
		ucontext_size := u64(4560)
		frame_size := ucontext_offset + ucontext_size
		mut signal_sp := lib.align_down(stack_top - frame_size, 16)
		uc_address := signal_sp + ucontext_offset

		// Build the whole frame in kernel memory, then push it to the user
		// stack with a single checked copy. A preemption signal can arrive
		// with the SP deep in a small goroutine stack, so the frame may not
		// fit; the checked copy turns that into a killed process (Linux
		// force_sigsegv) instead of a kernel-mode fault that kills the machine.
		mut frame := []u8{len: int(frame_size)} @[freed]
		base := u64(frame.data)
		unsafe {
			*&u64(base) = previous_mask
			// The private header points rt_sigreturn at the public context so
			// changes made by a three-argument handler are not discarded.
			*&u64(base + 8) = uc_address
			C.memcpy(voidptr(base + context_offset), context, sizeof(cpulocal.GPRState))
			*&u64(base + linux_frame_cookie_offset()) = proc.sigframe_cookie(t.process, signal_sp)
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

// Whether the thread is running on its alternate signal stack now, for
// sigaltstack(2) in signal.v.
fn thread_on_sigaltstack(t &proc.Thread) bool {
	return t.on_sigaltstack
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
	gpu_exec_trace(trace_gpu, 'copying argument vector')
	mut argv := exec_strings_from_user(u64(_argv), exec_total_max) or {
		unsafe { path.free() }
		return errno.err, errno.get()
	}
	gpu_exec_trace(trace_gpu, 'argument vector copied')
	gpu_exec_trace(trace_gpu, 'copying environment')
	envp := exec_strings_from_user(u64(_envp), exec_total_max - exec_strings_size(argv)) or {
		unsafe { path.free() }
		free_exec_strings(mut argv)
		return errno.err, errno.get()
	}
	gpu_exec_trace(trace_gpu, 'environment copied; entering ELF loader')

	// The path and both vectors are the exec's now, freed whether it works or
	// not. A failed exec is common: execvp() tries every directory in PATH.
	start_program(true, proc.current_directory_of(proc.current_thread().process), path, argv, envp,
		'', '', '') or { return errno.err, errno.get() }

	return errno.err, errno.get()
}

// With `execve` set, the exec owns `_path`, `argv` and `envp` and frees them
// whether it works or not; one that works never returns. The boot path that
// starts init passes `execve` unset and keeps them.
pub fn start_program(execve bool, dir &fs.VFSNode, _path string, argv []string, envp []string, stdin_path string, stdout_path string, stderr_path string) ?&proc.Process {
	mut mac_thread := proc.current_thread()
	mac_previous := mac_thread.mac_loading
	if execve { mac_thread.mac_loading = true }
	defer { mac_thread.mac_loading = mac_previous }
	// Chromium starts every child process by executing /proc/self/exe. The VFS
	// resolves that to this process's program, but the new process must record
	// where the program really is: keeping the literal path would make the
	// child's own /proc/self/exe point back at itself forever.
	prog_mount := unsafe { &lib.MountContext(C.vinix_stack_alloc(sizeof(lib.MountContext))) }
	parent := if execve {
		fs.parent_and_mount_for(fs.at_fdcwd, _path, prog_mount) or { free_exec_arguments(_path, argv, envp); return none }
	} else { unsafe { dir } }
	prog_node := if execve { fs.get_node_on_mount(parent, _path, true, prog_mount) }
		else { fs.get_node_and_mount(parent, _path, true, prog_mount) } or {
		if execve { free_exec_arguments(_path, argv, envp) }
		return none
	}
	path := fs.resolve_self_reference(_path)
	if execve && path.str != _path.str && !argv.any(it.str == _path.str) {
		unsafe { _path.free() }
	}
	return start_program_node(execve, dir, prog_node, prog_mount, path, argv, envp, stdin_path,
		stdout_path, stderr_path)
}

// What follows the first `prefix` bytes of an environment entry, as a view
// into it: nothing to free, and good only for as long as the entry is.
fn env_value(entry string, prefix int) string {
	return unsafe { tos(entry.str + prefix, entry.len - prefix) }
}

// Whether `entry` is `name` followed by `value`, without building that.
fn env_entry_is(entry string, name string, value string) bool {
	return entry.len == name.len + value.len && entry.starts_with(name)
		&& entry.ends_with(value)
}

// The part of exec that follows finding the program. execveat(2) on a
// descriptor comes here directly: a memfd has no name to be found by.
pub fn start_program_node(execve bool, dir &fs.VFSNode, prog_node &fs.VFSNode, prog_mount &lib.MountContext, path string, argv []string, envp []string, stdin_path string, stdout_path string, stderr_path string) ?&proc.Process {
	mut mac_thread := proc.current_thread()
	mac_previous := mac_thread.mac_loading
	if execve { mac_thread.mac_loading = true }
	defer { mac_thread.mac_loading = mac_previous }
	// What the caller names is subject to pledge(2) and unveil(2), a script's
	// interpreter included. What the kernel picks itself -- the ELF
	// interpreter, the x86 translator -- is not, as OpenBSD does not judge
	// ld.so.
	if execve && !fs.policy_check(prog_node, proc.policy_exec) {
		free_exec_arguments(path, argv, envp)
		return none
	}
	return load_program_node(execve, dir, prog_node, prog_mount, path, argv, envp, stdin_path, stdout_path,
		stderr_path)
}

// Frees what an exec was handed when it fails, unless load_program_image()
// has handed that on to an interpreter or translator's exec, which frees it.
fn load_program_node(execve bool, dir &fs.VFSNode, prog_node &fs.VFSNode, prog_mount &lib.MountContext, path string, argv []string, envp []string, stdin_path string, stdout_path string, stderr_path string) ?&proc.Process {
	handed_on := unsafe { &bool(C.vinix_stack_alloc(sizeof(bool))) }
	unsafe { *handed_on = false }
	process := load_program_image(execve, dir, prog_node, prog_mount, path, argv, envp, stdin_path,
		stdout_path, stderr_path, handed_on) or {
		if execve && !unsafe { *handed_on } {
			free_exec_arguments(path, argv, envp)
		}
		return none
	}
	return process
}

fn load_program_image(execve bool, dir &fs.VFSNode, prog_node &fs.VFSNode, prog_mount &lib.MountContext, path string, argv []string, envp []string, stdin_path string, stdout_path string, stderr_path string, handed_on &bool) ?&proc.Process {
	trace_gpu := execve && path == gpu_desktop_executable
	gpu_exec_trace(trace_gpu, 'resolved executable path')
	gpu_exec_trace(trace_gpu, 'opened executable node')
	// A program's interpreter is found from the root of the process that runs
	// it -- a container's, after pivot_root.
	caller := proc.current_thread().process
	root := fs.process_root(caller)
	if !stat.isreg(prog_node.resource.stat.mode)
		|| fs.mount_flags(prog_mount) & fs.ms_noexec != 0 {
		errno.set(errno.eacces)
		return none
	}
	fs.check_access(prog_node, fs.access_exec, true)?
	gpu_exec_trace(trace_gpu, 'validated executable permissions')
	mut prog := prog_node.resource
	allow_wx := envp.contains('VINIX_ALLOW_WX=1')
	if allow_wx && !fs.wx_exec_allowed(prog_mount) {
		errno.set(errno.eperm)
		return none
	}

	// Check for shebang before proceeding as if it was an ELF.
	mut shebang := [2]char{}
	prog.read(0, &shebang[0], 0, 2)?
	gpu_exec_trace(trace_gpu, 'read executable signature')
	if shebang[0] == char(`#`) && shebang[1] == char(`!`) {
		real_path, arg := parse_shebang(mut prog)?
		// Room for the interpreter, its argument and the script. `<<` copies
		// a string, so the list owns all of its strings.
		mut final_argv := []string{cap: argv.len + 2} @[freed]
		final_argv << real_path
		if arg != '' {
			final_argv << arg
		}
		final_argv << path
		for i := 1; i < argv.len; i++ {
			final_argv << argv[i]
		}
		unsafe {
			real_path.free()
			arg.free()
		}

		if execve {
			// The interpreter's exec frees final_argv and envp; the rest of
			// what this exec was handed goes now.
			unsafe {
				*handed_on = true
			}
			path_in_argv := argv.any(it.str == path.str)
			unsafe {
				if !path_in_argv {
					path.free()
				}
				argv.free()
			}
			return start_program(true, dir, final_argv[0], final_argv, envp, stdin_path,
				stdout_path, stderr_path)
		}
		// Starting init, which keeps what it gave.
		process := start_program(false, dir, final_argv[0], final_argv, envp, stdin_path,
			stdout_path, stderr_path) or {
			unsafe { final_argv.free() }
			return none
		}
		unsafe { final_argv.free() }
		return process
	}

	// ARM64 cannot enter an x86 ELF directly. Re-exec it through the native
	// QEMU user-mode translator of its word size and a private x86 root. Doing
	// this in the kernel exec path also catches the helper programs Wine and
	// Steam start themselves, rather than only binaries launched through a
	// shell wrapper.
	architecture := elf.architecture(prog) or { return exec_format_error(err) }
	gpu_exec_trace(trace_gpu, 'validated ELF architecture')
	if architecture == elf.arch_x86_64 || architecture == elf.arch_i386 {
		mut translator := '/usr/bin/qemu-x86_64'
		mut guest_root := '/usr/libexec/vinix-x86_64/root'
		mut root_variable := 'VINIX_X86_64_ROOT='
		if architecture == elf.arch_i386 {
			translator = '/usr/bin/qemu-i386'
			guest_root = '/usr/libexec/vinix-i386/root'
			root_variable = 'VINIX_I386_ROOT='
		}
		// Looked up first: past it nothing can fail, and what this exec was
		// handed is handed on or freed below.
		translator_mount := unsafe { &lib.MountContext(C.vinix_stack_alloc(sizeof(lib.MountContext))) }
		translator_node := fs.get_node_and_mount(root, translator, true, translator_mount)?
		// The environment can name another root, the way the shell launchers
		// let it: Steam runs in a glibc tree whose loader knows where its
		// libraries are. The default musl roots are told through
		// LD_LIBRARY_PATH. The values are views into envp's strings.
		mut own_root := false
		mut has_library_path := false
		mut library_path := ''
		mut i386_preload := ''
		mut x86_64_preload := ''
		for environment_entry in envp {
			if environment_entry.starts_with(root_variable)
				&& environment_entry.len > root_variable.len {
				guest_root = env_value(environment_entry, root_variable.len)
				own_root = true
			} else if environment_entry.starts_with('LD_LIBRARY_PATH=') {
				has_library_path = true
				library_path = env_value(environment_entry, 'LD_LIBRARY_PATH='.len)
			} else if environment_entry.starts_with('VINIX_I386_PRELOAD=') {
				i386_preload = env_value(environment_entry, 'VINIX_I386_PRELOAD='.len)
			} else if environment_entry.starts_with('VINIX_X86_64_PRELOAD=') {
				x86_64_preload = env_value(environment_entry, 'VINIX_X86_64_PRELOAD='.len)
			}
		}
		multiarch_root := own_root && envp.contains('VINIX_X86_MULTIARCH=1')
		guest_preload := if architecture == elf.arch_i386 { i386_preload } else { x86_64_preload }

		// Room for every option below, then the program's arguments. `<<`
		// copies a string, and the rest are literals or made here, so both
		// lists own all of their strings.
		mut translated_argv := []string{cap: argv.len + 14} @[freed]
		translated_argv << translator
		if architecture == elf.arch_x86_64 {
			translated_argv << '-B'
			translated_argv << '0x100000000'
		}
		translated_argv << '-L'
		translated_argv << guest_root
		if multiarch_root {
			// QEMU's -E edits the emulated process's environment without
			// making the native AArch64 translator load x86 libraries. A
			// multiarch root has both word sizes, so choose the right one
			// before the application or glibc can find native Vinix libs.
			mut multiarch := 'x86_64-linux-gnu'
			if architecture == elf.arch_i386 {
				multiarch = 'i386-linux-gnu'
			}
			mut library_text := lib.new_text(256)
			library_text.add('LD_LIBRARY_PATH=')
			library_text.add(guest_root)
			library_text.add('/usr/lib/')
			library_text.add(multiarch)
			library_text.add_byte(`:`)
			library_text.add(guest_root)
			library_text.add('/lib/')
			library_text.add(multiarch)
			if library_path != '' {
				library_text.add_byte(`:`)
				library_text.add(library_path)
			}
			translated_argv << '-E'
			translated_argv << library_text.str()
			// Mesa opens DRI drivers itself rather than through the ELF loader.
			// Give the guest the driver directory of its own word size, or an
			// inherited native path can make it dlopen an AArch64 driver.
			mut drivers_text := lib.new_text(128)
			drivers_text.add('LIBGL_DRIVERS_PATH=')
			drivers_text.add(guest_root)
			drivers_text.add('/usr/lib/')
			drivers_text.add(multiarch)
			drivers_text.add('/dri')
			translated_argv << '-E'
			translated_argv << drivers_text.str()
			if guest_preload != '' {
				// Each guest preload must match its word size and must never
				// reach the native translator.
				mut preload_text := lib.new_text(guest_preload.len + 16)
				preload_text.add('LD_PRELOAD=')
				preload_text.add(guest_preload)
				translated_argv << '-E'
				translated_argv << preload_text.str()
			}
		}
		// argv[0] is the caller's to choose, as it is for a native program:
		// a multicall binary or a script's `env bash` picks its behaviour by it.
		if argv.len > 0 && argv[0] != path {
			translated_argv << '-0'
			translated_argv << argv[0]
		}
		translated_argv << path
		for i := 1; i < argv.len; i++ {
			translated_argv << argv[i]
		}

		mut translated_envp := []string{cap: envp.len + 1} @[freed]
		for environment_entry in envp {
			if multiarch_root && (environment_entry.starts_with('LD_LIBRARY_PATH=')
				|| (guest_preload != '' && environment_entry.starts_with('LD_PRELOAD='))) {
				continue
			}
			translated_envp << environment_entry
		}
		if !own_root && !has_library_path {
			mut library_text := lib.new_text(2 * guest_root.len + 32)
			library_text.add('LD_LIBRARY_PATH=')
			library_text.add(guest_root)
			library_text.add('/lib:')
			library_text.add(guest_root)
			library_text.add('/usr/lib')
			translated_envp << library_text.str()
		}

		if execve {
			// The translator's exec frees both lists. What this exec was
			// handed goes now, and with envp the views into it.
			unsafe {
				*handed_on = true
			}
			free_exec_arguments(path, argv, envp)
			return load_program_node(true, root, translator_node, translator_mount, translator, translated_argv,
				translated_envp, stdin_path, stdout_path, stderr_path)
		}
		// Starting init, which keeps what it gave.
		process := load_program_node(false, root, translator_node, translator_mount, translator, translated_argv,
			translated_envp, stdin_path, stdout_path, stderr_path) or {
			unsafe {
				translated_argv.free()
				translated_envp.free()
			}
			return none
		}
		unsafe {
			translated_argv.free()
			translated_envp.free()
		}
		return process
	}
	// QEMU's -E preload belongs to the emulated x86 process. Its children may
	// exec a native helper (for example Steam's /bin/sh uname wrapper), passing
	// that LD_PRELOAD along. Do not make the AArch64 loader open an x86 library.
	// A later x86 exec will receive the matching preload from the handoff above.
	mut program_envp := envp
	mut foreign_preload := ''
	for entry in envp {
		if entry.starts_with('LD_PRELOAD=') {
			foreign_preload = env_value(entry, 'LD_PRELOAD='.len)
			break
		}
	}
	mut omit_foreign_preload := false
	if foreign_preload != '' {
		for entry in envp {
			if env_entry_is(entry, 'VINIX_I386_PRELOAD=', foreign_preload)
				|| env_entry_is(entry, 'VINIX_X86_64_PRELOAD=', foreign_preload) {
				omit_foreign_preload = true
				break
			}
		}
	}
	if omit_foreign_preload {
		// `<<` copies the strings; this frees them with the list.
		program_envp = []string{cap: envp.len} @[freed]
		for entry in envp {
			if !entry.starts_with('LD_PRELOAD=') {
				program_envp << entry
			}
		}
	}
	defer {
		if omit_foreign_preload {
			unsafe { program_envp.free() }
		}
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

	mut entry_point := unsafe { nil }

	if ld_path == '' {
		entry_point = voidptr(auxval.at_entry)
		gpu_exec_trace(trace_gpu, 'using program entry point (no interpreter)')
	} else {
		gpu_exec_trace(trace_gpu, 'opening ELF interpreter')
		ld_mount := unsafe { &lib.MountContext(C.vinix_stack_alloc(sizeof(lib.MountContext))) }
		ld_node := fs.get_node_and_mount(root, ld_path, true, ld_mount) or {
			failure := errno.get()
			unsafe { ld_path.free() }
			mmap.delete_pagemap(mut new_pagemap) or {}
			errno.set(failure)
			return none
		}
		if !stat.isreg(ld_node.resource.stat.mode)
			|| fs.mount_flags(ld_mount) & fs.ms_noexec != 0 {
			unsafe { ld_path.free() }
			mmap.delete_pagemap(mut new_pagemap) or {}
			errno.set(errno.eacces)
			return none
		}
		fs.check_access(ld_node, fs.access_exec, true) or {
			failure := errno.get()
			unsafe { ld_path.free() }
			mmap.delete_pagemap(mut new_pagemap) or {}
			errno.set(failure)
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
			C.kprintf(c'exec[gpu]: interpreter entry=0x%llx program entry=0x%llx\n', u64(entry_point),
				u64(auxval.at_entry))
		}

		unsafe { ld_path.free() }
	}
	sigreturn_page := install_sigreturn_page(mut new_pagemap) or { return none }

	if execve == false {
		mut new_process := sched.new_process(unsafe { nil }, new_pagemap)?

		new_process.name = proc.process_name(path, new_process.pid)
		new_process.executable_path = fs.program_path(prog_node, path)
		proc.set_executable_fs(mut new_process, voidptr(prog_node), prog_mount)
		new_process.allow_wx = allow_wx
		new_process.sigreturn_page = sigreturn_page
		new_process.sigcookie = proc.new_sigcookie()

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
		proc.set_command_line(mut new_process, argv)
		mut started := false
		defer { if !started { proc.clear_command_line(mut new_process) } }

		sched.new_user_thread(new_process, true, entry_point, unsafe { nil }, 0, argv,
			program_envp, auxval, true)?
		started = true

		return new_process
	} else {
		mut t := proc.current_thread()
		mut curr_process := t.process
		gpu_exec_trace(trace_gpu, 'beginning process image replacement')
		// Named before the close-on-exec descriptors go: fexecve() runs one.
		program_path := fs.program_path(prog_node, path)

		// Every other thread has to be gone before the address space they are
		// running in is replaced -- and before the close-on-exec descriptors
		// go, as on Linux: a sibling unwinding a syscall still reaches the
		// descriptor it was called on.
		gpu_exec_trace(trace_gpu, 'stopping sibling threads')
		kill_sibling_threads(mut curr_process, t)
		begin_exec_signals(mut curr_process, t)
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
		// This thread never returns to userspace to pay for what those closes
		// changed; the new program's thread starts there.
		flush_owed_sync()
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
		curr_process.dumpable = curr_process.uid == curr_process.euid && curr_process.gid == curr_process.egid
		proc.unlock_table()

		// The copies fork made are replaced, not kept alongside.
		unsafe {
			curr_process.name.free()
			curr_process.executable_path.free()
		}
		curr_process.name = proc.process_name(path, curr_process.pid)
		curr_process.executable_path = program_path
		proc.set_command_line(mut curr_process, argv)
		proc.set_executable_fs(mut curr_process, voidptr(prog_node), prog_mount)
		// The replacement mappings now own their inode references, and the
		// executable node is recorded before its final descriptor goes.
		release_exec_descriptor(mut t)
		curr_process.allow_wx = allow_wx
		curr_process.sigreturn_page = sigreturn_page
		// Frames the old program was given must not return into the new one.
		curr_process.sigcookie = proc.new_sigcookie()
		// execve recomputes the capability sets from the new credentials and
		// the bounding set, which is how a container's root ends up with only
		// the capabilities its runtime left it.
		proc.capabilities_after_exec(mut curr_process)
		proc.mac_after_exec(mut curr_process)
		// The new program runs under the execpromises, or unpledged.
		proc.pledge_after_exec(mut curr_process)
		gpu_exec_trace(trace_gpu, 'installed replacement process metadata')

		gpu_exec_trace(trace_gpu, 'switching CPU to kernel page map')
		kernel_pagemap.switch_to()
		gpu_exec_trace(trace_gpu, 'switched CPU to kernel page map')
		t.process = kernel_process
		gpu_exec_trace(trace_gpu, 'detached execve thread from old process')

		gpu_exec_trace(trace_gpu, 'deleting old process page map')
		if trace_gpu {
			mmap.delete_pagemap_traced(mut old_pagemap) or {
				if omit_foreign_preload { unsafe { program_envp.free() } }
				free_exec_arguments(path, argv, envp)
				abort_exec(mut curr_process, mut t)
			}
		} else {
			mmap.delete_pagemap(mut old_pagemap) or {
				if omit_foreign_preload { unsafe { program_envp.free() } }
				free_exec_arguments(path, argv, envp)
				abort_exec(mut curr_process, mut t)
			}
		}
		gpu_exec_trace(trace_gpu, 'old process page map deleted')

		curr_process.thread_stack_top = elf.initial_stack_top()
		curr_process.mmap_anon_non_fixed_base = elf.initial_mmap_base()
		// The new program has no break yet; its first brk() reserves the arena
		// in the address space it now has.
		curr_process.brk_base = 0
		curr_process.brk_current = 0

		curr_process.threads_lock.acquire()
		curr_process.threads.clear()
		curr_process.threads_lock.release()
		gpu_exec_trace(trace_gpu, 'reset process thread metadata')

		// The program that comes out of exec has one thread and it is the group
		// leader, so it takes over the pid as its tid. Anything else this
		// thread was holding goes back to the namespace.
		// The program keeps the scheduling policy of the thread that execs it.
		// `chrt -f 50 ./program` is one process: it gives itself the priority
		// and then becomes the program that was meant to have it. Installed
		// before the thread is enqueued, so it is never picked up as an
		// ordinary thread first.
		inherited_sched := t.sched
		gpu_exec_trace(trace_gpu, 'building replacement user thread and stack')
		mut new_thread := sched.new_user_thread(curr_process, true, entry_point, unsafe { nil },
			0, argv, program_envp, auxval, false) or {
			if omit_foreign_preload { unsafe { program_envp.free() } }
			free_exec_arguments(path, argv, envp)
			abort_exec(mut curr_process, mut t)
		}
		if t.tid != curr_process.pid {
			proc.free_tid(t.tid)
		}
		if trace_gpu {
			C.kprintf(c'exec[gpu]: replacement thread built pc=0x%llx sp=0x%llx tid=%lld\n',
				u64(new_thread.gpr_state.pc), u64(new_thread.gpr_state.sp), i64(new_thread.tid))
		}
		proc.set_thread_sched_params(new_thread.tid, inherited_sched)
		gpu_exec_trace(trace_gpu, 'inherited scheduler parameters')
		// exec keeps blocked and ignored signals, as the x86 handoff does.
		new_thread.masked_signals = t.masked_signals
		for i := 0; i < t.sigactions.len; i++ {
			if t.sigactions[i].sa_sigaction == sig_ign {
				new_thread.sigactions[i].sa_sigaction = sig_ign
			}
		}
		if trace_gpu {
			gpu_exec_trace(trace_gpu, 'disabling interrupts for atomic same-CPU handoff')
			cpu.interrupt_toggle(false)
			gpu_exec_trace(trace_gpu, 'handoff interrupts disabled')
		}
		enqueued := finish_exec_signals(mut curr_process, mut new_thread, t, trace_gpu)
		if enqueued {
			gpu_exec_trace(trace_gpu, 'replacement thread enqueued')
		} else {
			gpu_exec_trace(trace_gpu, 'ERROR: replacement thread enqueue failed')
		}

		// This never returns, so neither the caller nor the defer above frees
		// what the exec was handed.
		if omit_foreign_preload {
			unsafe { program_envp.free() }
		}
		free_exec_arguments(path, argv, envp)
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
	mut mac_thread := proc.current_thread()
	mac_previous := mac_thread.mac_loading
	mac_thread.mac_loading = true
	defer { mac_thread.mac_loading = mac_previous }
	defer { release_exec_descriptor(mut mac_thread) }
	mut process := proc.current_thread().process

	path := fs.user_path(_path) or { return errno.err, errno.get() }

	mut directory := &fs.VFSNode(unsafe { nil })
	mut target := path

	mut direct_node := &fs.VFSNode(unsafe { nil })
	direct_mount := unsafe { &lib.MountContext(C.vinix_stack_alloc(sizeof(lib.MountContext))) }
	lib.copy_mount_context(direct_mount, unsafe { nil })
	if path.len == 0 {
		// The descriptor's name below takes the empty path's place.
		unsafe { path.free() }
		if flags & fs.at_empty_path == 0 {
			return errno.err, errno.enoent
		}
		// Run the descriptor's image with its actual mount route. A relative
		// shebang interpreter is resolved from cwd, as for ordinary execve.
		mut fd := file.fd_from_fdnum(process, dirfd) or { return errno.err, errno.ebadf }
		mac_thread.exec_descriptor = voidptr(fd)
		fd.handle.mac_check(proc.mac_execute) or { return errno.err, errno.get() }
		node := unsafe { &fs.VFSNode(fd.handle.node) }
		lib.copy_mount_context(direct_mount, &fd.handle.mount)
		if node == unsafe { nil } {
			return errno.err, errno.eacces
		}
		direct_node = node
		directory = if node.parent != unsafe { nil } {
			node.parent
		} else {
			unsafe { &fs.VFSNode(proc.current_directory_of(process)) }
		}
		mut name := lib.new_text(32)
		name.add('/proc/self/fd/')
		name.add_decimal(i64(dirfd))
		target = name.str()
	} else {
		directory = fs.parent_and_mount_for(dirfd, path, direct_mount) or {
			unsafe { path.free() }
			return errno.err, errno.get()
		}
		direct_node = fs.get_node_on_mount(directory, path, flags & fs.at_symlink_nofollow == 0, direct_mount) or {
			unsafe { path.free() }
			return errno.err, errno.get()
		}
	}

	mut argv := exec_strings_from_user(u64(_argv), exec_total_max) or {
		unsafe { target.free() }
		return errno.err, errno.get()
	}
	envp := exec_strings_from_user(u64(_envp), exec_total_max - exec_strings_size(argv)) or {
		unsafe { target.free() }
		free_exec_strings(mut argv)
		return errno.err, errno.get()
	}

	// The path and both vectors are the exec's now, freed whether it works or
	// not.
	if direct_node != unsafe { nil } {
		start_program_node(true, directory, direct_node, direct_mount, target, argv, envp, '', '', '') or {
			return errno.err, errno.get()
		}
		return errno.err, errno.get()
	}
	start_program(true, directory, target, argv, envp, '', '', '') or {
		return errno.err, errno.get()
	}

	return errno.err, errno.get()
}

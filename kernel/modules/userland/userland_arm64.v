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
import errno
import lib
import strings
import resource
import usercopy

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

union SigVal {
	sival_int int
	sival_ptr voidptr
}

pub struct SigInfo {
pub mut:
	si_signo  int
	si_code   int
	si_errno  int
	si_pid    int
	si_uid    int
	si_addr   voidptr
	si_status int
	si_value  SigVal
}

pub fn syscall_getpid(_ voidptr) (u64, u64) {
	mut t := unsafe { proc.current_thread() }

	return u64(t.process.pid), 0
}

pub fn syscall_getppid(_ voidptr) (u64, u64) {
	mut t := unsafe { proc.current_thread() }

	return u64(t.process.ppid), 0
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
pub fn syscall_sigreturn(gpr_state_ptr voidptr, context_arg voidptr, old_mask_arg u64) (u64, u64) {
	mut t := unsafe { proc.current_thread() }

	cpu.interrupt_toggle(false)

	mut frame := unsafe { &cpulocal.GPRState(gpr_state_ptr) }

	if t.sigentry != 0 {
		// Vinix/mlibc mode: context and mask passed as args (user x0, x1)
		t.gpr_state = unsafe { *&cpulocal.GPRState(context_arg) }
		t.masked_signals = old_mask_arg
	} else {
		// Linux/musl mode: read from the signal frame at the user SP. musl's
		// __restore_rt enters here with SP pointing at the frame dispatch left.
		// Frame layout: [prev_mask(8)] [pad(8)] [GPRState(sizeof)]
		user_sp := frame.sp

		mut prev_mask := u64(0)
		if !usercopy.copy_from_user(voidptr(&prev_mask), user_sp, sizeof(u64)) {
			return errno.err, errno.efault
		}
		if !usercopy.copy_from_user(voidptr(&t.gpr_state), user_sp + 16, sizeof(cpulocal.GPRState)) {
			return errno.err, errno.efault
		}
		t.masked_signals = prev_mask
	}

	t.on_sigaltstack = false

	unsafe {
		*frame = t.gpr_state
	}

	return t.gpr_state.x0, 0
}

// Dispatch a signal to _self_, called from the scheduler at the
// end of syscalls, or from exception handlers.
pub fn dispatch_a_signal(context &cpulocal.GPRState) {
	mut t := unsafe { proc.current_thread() }

	mut which := -1

	for i := u8(0); i < 64; i++ {
		if t.masked_signals & (u64(1) << i) != 0 {
			continue
		}
		if katomic.btr(mut &t.pending_signals, i) == true {
			which = int(i) + 1
			break
		}
	}

	if which == -1 {
		return
	}

	sigaction := t.sigactions[which]
	handler := sigaction.sa_sigaction

	// SIG_IGN (1): ignore the signal
	if handler == sig_ign {
		return
	}
	// SIG_DFL (0): default action. For now, ignore instead of terminating.
	if handler == sig_dfl {
		return
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
		mut return_context := unsafe { &cpulocal.GPRState(signal_sp) }

		unsafe {
			*return_context = *context
		}
		t.gpr_state = *context
		t.gpr_state.sp = signal_sp

		t.gpr_state.sp -= sizeof(SigInfo)
		t.gpr_state.sp = lib.align_down(t.gpr_state.sp, 16)
		mut siginfo := unsafe { &SigInfo(t.gpr_state.sp) }

		unsafe { C.memset(voidptr(siginfo), 0, sizeof(SigInfo)) }
		siginfo.si_signo = which

		t.gpr_state.pc = t.sigentry
		t.gpr_state.x0 = u64(which)
		t.gpr_state.x1 = u64(siginfo)
		t.gpr_state.x2 = u64(handler)
		t.gpr_state.x3 = u64(return_context)
		t.gpr_state.x4 = previous_mask

		enter_handler(mut t, context)
	} else if sigaction.sa_restorer != unsafe { nil } {
		// ── Linux/musl mode: set up signal frame on user stack ──
		// Frame layout: [prev_mask(8)] [pad(8)] [GPRState(sizeof)]
		frame_size := u64(16) + sizeof(cpulocal.GPRState)
		mut signal_sp := lib.align_down(stack_top - frame_size, 16)

		// Store original context into frame on user stack
		unsafe {
			*&u64(signal_sp) = previous_mask
			*&u64(signal_sp + 8) = 0
			C.memcpy(voidptr(signal_sp + 16), context, sizeof(cpulocal.GPRState))
		}

		// Set up handler invocation
		t.gpr_state = *context
		t.gpr_state.sp = signal_sp
		t.gpr_state.pc = u64(handler)
		t.gpr_state.x30 = u64(sigaction.sa_restorer) // LR = __restore_rt
		t.gpr_state.x0 = u64(which)

		enter_handler(mut t, context)
	}
	// else: no sigentry and no restorer — silently drop signal
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

	katomic.bts(mut &t.pending_signals, signal - 1)

	// Try to stop an event_await()
	sched.enqueue_thread(t, true)
}

// Deliver to a process' main thread. Signal state is per-thread here, so there
// is no process-wide pending mask to raise instead.
fn signal_process(mut target proc.Process, signal int) bool {
	target.threads_lock.acquire()
	mut main_thread := &proc.Thread(unsafe { nil })
	if target.threads.len > 0 {
		main_thread = target.threads[0]
	}
	target.threads_lock.release()

	if main_thread == unsafe { nil } {
		return false
	}

	sendsig(main_thread, u8(signal))
	return true
}

// kill(2). Signal 0 raises nothing: it is the "does this pid exist?" probe that
// shells and daemons use, so it must never fail loudly.
pub fn syscall_kill(_ voidptr, pid int, signal int) (u64, u64) {
	if signal < 0 || signal > 64 {
		return errno.err, errno.einval
	}

	mut current_process := proc.current_thread().process

	if pid > 0 {
		if pid >= proc.max_pid {
			return errno.err, errno.esrch
		}
		mut target := processes[pid]
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
		pgid = -pid
	}

	mut found := false
	for i := 1; i < proc.max_pid; i++ {
		mut target := processes[i]
		if target == unsafe { nil } {
			continue
		}
		if pgid != 0 && target.pgid != pgid {
			continue
		}
		if pid == -1 && (target.pid == 1 || target.pid == current_process.pid) {
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

	mut target := proc.thread_by_tid(tid)
	if target == unsafe { nil } || target.is_dead {
		return errno.err, errno.esrch
	}
	if tgid > 0 && target.process.pid != tgid {
		return errno.err, errno.esrch
	}
	if signal == 0 {
		return 0, 0
	}

	sendsig(target, u8(signal))

	return 0, 0
}

pub fn syscall_execve(_ voidptr, _path charptr, _argv &charptr, _envp &charptr) (u64, u64) {
	path := unsafe { cstring_to_vstring(_path) }
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

	start_program(true, proc.current_thread().process.current_directory, path, argv, envp,
		'', '', '') or { return errno.err, errno.get() }

	return errno.err, errno.get()
}

pub fn start_program(execve bool, dir &fs.VFSNode, path string, argv []string, envp []string, stdin string, stdout string, stderr string) ?&proc.Process {
	prog_node := fs.get_node(dir, path, true)?
	mut prog := prog_node.resource

	mut new_pagemap := memory.new_pagemap()

	// Check for shebang before proceeding as if it was an ELF.
	mut shebang := [2]char{}
	prog.read(0, &shebang[0], 0, 2)?
	if shebang[0] == char(`#`) && shebang[1] == char(`!`) {
		real_path, arg := parse_shebang(mut prog)?
		mut final_argv := [real_path]
		if arg != '' {
			final_argv << arg
		}
		final_argv << path
		final_argv << argv[1..]

		return start_program(execve, dir, real_path, final_argv, envp, stdin, stdout,
			stderr)
	}

	mut auxval, ld_path := elf.load(new_pagemap, prog, 0) or { return none }

	mut entry_point := unsafe { nil }

	if ld_path == '' {
		entry_point = voidptr(auxval.at_entry)
	} else {
		ld_node := fs.get_node(vfs_root, ld_path, true)?
		ld := ld_node.resource

		ld_auxval, interp := elf.load(new_pagemap, ld, 0x40000000) or { return none }

		if interp != '' {
			unsafe { interp.free() }
		}

		entry_point = voidptr(ld_auxval.at_entry)
		auxval.at_base = ld_auxval.at_base

		unsafe { ld_path.free() }
	}

	if execve == false {
		mut new_process := sched.new_process(unsafe { nil }, new_pagemap)?

		new_process.name = '${path}[${new_process.pid}]'

		stdin_node := fs.get_node(vfs_root, stdin, true)?
		stdin_handle := &file.Handle{
			resource: stdin_node.resource
			node:     stdin_node
			refcount: 1
		}
		stdin_fd := &file.FD{
			handle: stdin_handle
		}
		new_process.fds[0] = voidptr(stdin_fd)

		stdout_node := fs.get_node(vfs_root, stdout, true)?
		stdout_handle := &file.Handle{
			resource: stdout_node.resource
			node:     stdout_node
			refcount: 1
		}
		stdout_fd := &file.FD{
			handle: stdout_handle
		}
		new_process.fds[1] = voidptr(stdout_fd)

		stderr_node := fs.get_node(vfs_root, stderr, true)?
		stderr_handle := &file.Handle{
			resource: stderr_node.resource
			node:     stderr_node
			refcount: 1
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

		// Close O_CLOEXEC file descriptors before exec.
		// This is critical for pipe EOF detection: popen creates pipes
		// with O_CLOEXEC, and leaked FDs prevent pipe refcount from
		// reaching 1, blocking EOF on reads.
		for i := 0; i < proc.max_fds; i++ {
			fd_ptr := unsafe { &file.FD(curr_process.fds[i]) }
			if fd_ptr == unsafe { nil } {
				continue
			}
			if fd_ptr.flags & resource.o_cloexec != 0 {
				file.fdnum_close(curr_process, i, true) or {}
			}
		}

		// Every other thread has to be off the CPUs before the address space
		// they are running in is replaced.
		kill_sibling_threads(mut curr_process, t)

		mut old_pagemap := curr_process.pagemap

		curr_process.pagemap = new_pagemap

		curr_process.name = '${path}[${curr_process.pid}]'

		kernel_pagemap.switch_to()
		t.process = kernel_process

		mmap.delete_pagemap(mut old_pagemap)?

		curr_process.thread_stack_top = u64(0x70000000000)
		curr_process.mmap_anon_non_fixed_base = u64(0x80000000000)

		curr_process.threads_lock.acquire()
		curr_process.threads = []&proc.Thread{}
		curr_process.threads_lock.release()

		// The program that comes out of exec has one thread and it is the group
		// leader, so it takes over the pid as its tid. Anything else this
		// thread was holding goes back to the namespace.
		if t.tid != curr_process.pid {
			proc.free_tid(t.tid)
		}

		sched.new_user_thread(curr_process, true, entry_point, unsafe { nil }, 0, argv, envp,
			auxval, true)?

		unsafe {
			argv.free()
			envp.free()
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

	path := unsafe { cstring_to_vstring(_path) }

	mut directory := &fs.VFSNode(unsafe { nil })
	mut target := path

	if path.len == 0 {
		if flags & fs.at_empty_path == 0 {
			return errno.err, errno.enoent
		}
		// Run whatever the descriptor is open on. Its own name and parent are
		// what a relative interpreter path then resolves against.
		mut fd := file.fd_from_fdnum(process, dirfd) or { return errno.err, errno.ebadf }
		node := unsafe { &fs.VFSNode(fd.handle.node) }
		if node == unsafe { nil } || node.parent == unsafe { nil } {
			fd.unref()
			return errno.err, errno.eacces
		}
		directory = node.parent
		target = node.name
		fd.unref()
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

	start_program(true, directory, target, argv, envp, '', '', '') or {
		return errno.err, errno.get()
	}

	return errno.err, errno.get()
}

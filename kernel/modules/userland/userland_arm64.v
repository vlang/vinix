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
import event
import event.eventstruct
import errno
import lib
import strings
import resource

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

pub fn syscall_getgroups(_ voidptr, size int, list &u32) (u64, u64) {
	return 0, 0
}

pub fn syscall_sigentry(_ voidptr, sigentry u64) (u64, u64) {
	mut t := proc.current_thread()

	t.sigentry = sigentry

	return 0, 0
}

@[noreturn]
pub fn syscall_sigreturn(gpr_state_ptr voidptr, context_arg voidptr, old_mask_arg u64) {
	mut t := unsafe { proc.current_thread() }

	cpu.interrupt_toggle(false)

	if t.sigentry != 0 {
		// Vinix/mlibc mode: context and mask passed as args (user x0, x1)
		t.gpr_state = unsafe { *&cpulocal.GPRState(context_arg) }
		t.masked_signals = old_mask_arg
	} else {
		// Linux/musl mode: read from signal frame at user SP.
		// musl's __restore_rt calls svc #139 with SP pointing to the
		// signal frame we placed during dispatch_a_signal.
		// Frame layout: [prev_mask(8)] [pad(8)] [GPRState(sizeof)]
		gpr := unsafe { &cpulocal.GPRState(gpr_state_ptr) }
		user_sp := gpr.sp

		prev_mask := unsafe { *&u64(user_sp) }
		unsafe { C.memcpy(voidptr(&t.gpr_state), voidptr(user_sp + 16), sizeof(cpulocal.GPRState)) }
		t.masked_signals = prev_mask
	}

	sched.yield(false)

	for {}
}

pub fn syscall_sigaction(_ voidptr, signum int, act &proc.SigAction, oldact &proc.SigAction) (u64, u64) {
	if signum < 0 || signum > 34 || signum == sigkill || signum == sigstop {
		return errno.err, errno.einval
	}

	mut t := proc.current_thread()

	if oldact != unsafe { nil } {
		unsafe {
			*oldact = t.sigactions[signum]
		}
	}

	if act != unsafe { nil } {
		t.sigactions[signum] = *act
	}

	return 0, 0
}

pub fn syscall_sigprocmask(_ voidptr, how int, set &u64, oldset &u64) (u64, u64) {
	mut t := proc.current_thread()

	if oldset != unsafe { nil } {
		unsafe {
			*oldset = t.masked_signals
		}
	}

	if set != unsafe { nil } {
		match how {
			sig_block {
				t.masked_signals |= *set
			}
			sig_unblock {
				t.masked_signals &= ~*set
			}
			sig_setmask {
				t.masked_signals = *set
			}
			else {}
		}
	}

	return 0, 0
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
			which = i
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

	previous_mask := t.masked_signals

	t.masked_signals |= sigaction.sa_mask
	// Check SA_NODEFER: Vinix value (0x40) OR Linux value (0x40000000)
	if sigaction.sa_flags & sa_nodefer == 0 && sigaction.sa_flags & int(0x40000000) == 0 {
		t.masked_signals |= u64(1) << which
	}

	if t.sigentry != 0 {
		// ── Vinix/mlibc mode: dispatch via sigentry trampoline ──
		// ARM64 has no redzone. Use context.sp (the CURRENT user SP from the
		// kernel stack frame), NOT t.gpr_state.sp which is stale from the last
		// timer preemption.
		mut signal_sp := lib.align_down(context.sp, 16)

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

		sched.yield(false)
	} else if sigaction.sa_restorer != unsafe { nil } {
		// ── Linux/musl mode: set up signal frame on user stack ──
		// Frame layout: [prev_mask(8)] [pad(8)] [GPRState(sizeof)]
		frame_size := u64(16) + sizeof(cpulocal.GPRState)
		mut signal_sp := lib.align_down(context.sp - frame_size, 16)

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

		sched.yield(false)
	}
	// else: no sigentry and no restorer — silently drop signal
}

pub fn sendsig(_thread &proc.Thread, signal u8) {
	mut t := unsafe { _thread }

	katomic.bts(mut &t.pending_signals, signal)

	// Try to stop an event_await()
	sched.enqueue_thread(t, true)
}

pub fn syscall_kill(_ voidptr, pid int, signal int) (u64, u64) {
	if signal > 0 {
		sendsig(processes[pid].threads[0], u8(signal))
	} else {
		panic('sendsig: Values of signal <= 0 not supported')
	}

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

pub fn syscall_waitpid(_ voidptr, pid int, _status &int, options int) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut current_process := current_thread.process

	mut status := unsafe { _status }

	mut events := []&eventstruct.Event{}
	defer {
		unsafe { events.free() }
	}
	mut child := &proc.Process(unsafe { nil })

	if pid == -1 {
		if current_process.children.len == 0 {
			return errno.err, errno.echild
		}
		for c in current_process.children {
			events << &c.event
		}
	} else if pid < -1 || pid == 0 {
		print('\nwaitpid: value of pid not supported\n')
		return errno.err, errno.einval
	} else {
		if current_process.children.len == 0 {
			return errno.err, errno.echild
		}
		child = processes[pid]
		if child == unsafe { nil } || child.ppid != current_process.pid {
			return errno.err, errno.echild
		}
		events << &child.event
	}

	block := options & wnohang == 0
	which := event.await(mut events, block) or { return errno.err, errno.eintr }

	if child == unsafe { nil } {
		child = current_process.children[which]
	}

	unsafe {
		*status = child.status
	}
	ret := child.pid

	proc.free_pid(ret)

	current_process.children.delete(current_process.children.index(child))

	return u64(ret), 0
}

@[noreturn]
pub fn syscall_exit(_ voidptr, status int) {
	mut current_thread := proc.current_thread()
	mut current_process := current_thread.process

	mut old_pagemap := current_process.pagemap

	kernel_pagemap.switch_to()
	current_thread.process = kernel_process

	// Close all FDs
	for i := 0; i < proc.max_fds; i++ {
		if current_process.fds[i] == unsafe { nil } {
			continue
		}

		file.fdnum_close(current_process, i, true) or {}
	}

	// PID 1 inherits children
	if current_process.pid != 1 {
		for child_proc in current_process.children {
			processes[1].children << child_proc
		}
	}

	mmap.delete_pagemap(mut old_pagemap) or {}

	katomic.store(mut &current_process.status, int(u32(status) << 8))
	event.trigger(mut &current_process.event, false)

	sched.dequeue_and_die()
}

pub fn syscall_fork(gpr_state &cpulocal.GPRState) (u64, u64) {
	old_thread := proc.current_thread()
	mut old_process := old_thread.process

	mut new_process := sched.new_process(old_process, unsafe { nil }) or {
		return errno.err, errno.get()
	}

	new_process.name = '${old_process.name}[${new_process.pid}]'

	// Dup all FDs, preserving O_CLOEXEC flags
	for i := 0; i < proc.max_fds; i++ {
		if old_process.fds[i] == unsafe { nil } {
			continue
		}
		old_fd := unsafe { &file.FD(old_process.fds[i]) }
		file.fdnum_dup(old_process, i, new_process, i, old_fd.flags, true, false) or {
			panic('')
		}
	}

	stack_size := u64(0x200000)

	mut stacks := []voidptr{}

	kernel_stack_phys := memory.pmm_alloc(stack_size / page_size)
	stacks << kernel_stack_phys
	kernel_stack := u64(kernel_stack_phys) + stack_size + higher_half

	mut new_thread := &proc.Thread{
		gpr_state:      gpr_state
		process:        new_process
		timeslice:      old_thread.timeslice
		tpidr_el0:      cpu.read_tpidr_el0()
		kernel_stack:   kernel_stack
		running_on:     u64(-1)
		ttbr0:          u64(new_process.pagemap.top_level)
		sigentry:       old_thread.sigentry
		sigactions:     old_thread.sigactions
		masked_signals: old_thread.masked_signals
		stacks:         stacks
		fpu_storage:    unsafe { malloc(fpu_storage_size) }
	}

	unsafe { stacks.free() }

	new_thread.self = voidptr(new_thread)

	unsafe { C.memcpy(new_thread.fpu_storage, old_thread.fpu_storage, fpu_storage_size) }

	// Child returns 0 from fork
	new_thread.gpr_state.x0 = u64(0)
	new_thread.gpr_state.x1 = u64(0)

	old_process.children << new_process
	new_process.threads << new_thread

	sched.enqueue_thread(new_thread, false)

	return u64(new_process.pid), u64(0)
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

		mut old_pagemap := curr_process.pagemap

		curr_process.pagemap = new_pagemap

		curr_process.name = '${path}[${curr_process.pid}]'

		kernel_pagemap.switch_to()
		t.process = kernel_process

		mmap.delete_pagemap(mut old_pagemap)?

		curr_process.thread_stack_top = u64(0x70000000000)
		curr_process.mmap_anon_non_fixed_base = u64(0x80000000000)

		// TODO: Kill old threads
		curr_process.threads = []&proc.Thread{}

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

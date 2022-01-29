// userland.v: Userland management (program starting, syscalls, etc).
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

module userland

import fs
import memory
import memory.mmap
import elf
import sched
import file
import proc
import x86.cpu.local as cpulocal
import katomic
import event
import event.eventstruct
import errno
import lib
import strings
import resource

pub const wnohang = 2

pub const sig_block = 1

pub const sig_unblock = 2

pub const sig_setmask = 3

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

pub const sig_dfl = voidptr(-2)

pub const sig_ign = voidptr(-3)

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
	C.printf(c'\n\e[32mstrace\e[m: getpid()\n')
	defer {
		C.printf(c'\e[32mstrace\e[m: returning\n')
	}

	mut thread := unsafe { proc.current_thread() }

	return u64(thread.process.pid), 0
}

pub fn syscall_getppid(_ voidptr) (u64, u64) {
	C.printf(c'\n\e[32mstrace\e[m: getppid()\n')
	defer {
		C.printf(c'\e[32mstrace\e[m: returning\n')
	}

	mut thread := unsafe { proc.current_thread() }

	return u64(thread.process.ppid), 0
}

pub fn syscall_getgroups(_ voidptr, size int, list &u32) (u64, u64) {
	C.printf(c'\n\e[32mstrace\e[m: getgroups(%d, 0x%llx)\n', size, voidptr(list))
	defer {
		C.printf(c'\e[32mstrace\e[m: returning\n')
	}

	return 0, 0
}

pub fn syscall_sigentry(_ voidptr, sigentry u64) (u64, u64) {
	C.printf(c'\n\e[32mstrace\e[m: sigentry(0x%llx)\n', sigentry)
	defer {
		C.printf(c'\e[32mstrace\e[m: returning\n')
	}

	mut thread := proc.current_thread()

	thread.sigentry = sigentry

	return 0, 0
}

[noreturn]
pub fn syscall_sigreturn(_ voidptr, context &cpulocal.GPRState, old_mask u64) {
	mut thread := unsafe { proc.current_thread() }

	asm volatile amd64 {
		cli
	}

	thread.gpr_state = unsafe { context[0] }
	thread.masked_signals = old_mask

	sched.yield(false)

	for {}
}

pub fn syscall_sigaction(_ voidptr, signum int, act &proc.SigAction, oldact &proc.SigAction) (u64, u64) {
	C.printf(c'\n\e[32mstrace\e[m: sigaction(%d, 0x%llx, 0x%llx)\n', signum, voidptr(act),
		voidptr(oldact))
	defer {
		C.printf(c'\e[32mstrace\e[m: returning\n')
	}

	if signum < 0 || signum > 34 || signum == userland.sigkill || signum == userland.sigstop {
		return -1, errno.einval
	}

	mut thread := proc.current_thread()

	if voidptr(oldact) != voidptr(0) {
		unsafe {
			oldact[0] = thread.sigactions[signum]
		}
	}

	if voidptr(act) != voidptr(0) {
		unsafe {
			thread.sigactions[signum] = act[0]
		}
	}

	return 0, 0
}

pub fn syscall_sigprocmask(_ voidptr, how int, set &u64, oldset &u64) (u64, u64) {
	C.printf(c'\n\e[32mstrace\e[m: sigprocmask(%d, 0x%llx, 0x%llx)\n', how, voidptr(set),
		voidptr(oldset))
	defer {
		C.printf(c'\e[32mstrace\e[m: returning\n')
	}

	mut thread := proc.current_thread()

	if voidptr(oldset) != voidptr(0) {
		unsafe {
			oldset[0] = thread.masked_signals
		}
	}

	if voidptr(set) != voidptr(0) {
		match how {
			userland.sig_block {
				thread.masked_signals |= unsafe { set[0] }
			}
			userland.sig_unblock {
				thread.masked_signals &= ~(unsafe { set[0] })
			}
			userland.sig_setmask {
				thread.masked_signals = unsafe { set[0] }
			}
			else {}
		}
	}

	return 0, 0
}

// Dispatch a signal to _self_, this is called from the scheduler, at the
// end of syscalls, or from exception handlers.
pub fn dispatch_a_signal(context &cpulocal.GPRState) {
	mut thread := unsafe { proc.current_thread() }

	if thread.sigentry == 0 {
		return
	}

	mut which := -1

	for i := byte(0); i < 64; i++ {
		if thread.masked_signals & (u64(1) << i) != 0 {
			continue
		}
		if katomic.btr(thread.pending_signals, i) == true {
			which = i
			break
		}
	}

	if which == -1 {
		return
	}

	sigaction := thread.sigactions[which]

	previous_mask := thread.masked_signals

	thread.masked_signals |= sigaction.sa_mask
	if sigaction.sa_flags & userland.sa_nodefer == 0 {
		thread.masked_signals |= u64(1) << which
	}

	// Respect the redzone
	thread.gpr_state.rsp -= 128
	thread.gpr_state.rsp = lib.align_down(thread.gpr_state.rsp, 16)

	// Return context
	thread.gpr_state.rsp -= sizeof(cpulocal.GPRState)
	thread.gpr_state.rsp = lib.align_down(thread.gpr_state.rsp, 16)
	mut return_context := &cpulocal.GPRState(thread.gpr_state.rsp)

	unsafe {
		return_context[0] = context[0]
		thread.gpr_state = context[0]
	}
	// Siginfo
	thread.gpr_state.rsp -= sizeof(SigInfo)
	thread.gpr_state.rsp = lib.align_down(thread.gpr_state.rsp, 16)
	mut siginfo := &SigInfo(thread.gpr_state.rsp)

	unsafe { C.memset(voidptr(siginfo), 0, sizeof(SigInfo)) }
	siginfo.si_signo = which

	// Alignment
	thread.gpr_state.rsp -= 8

	// Common handler will take (which, siginfo, sigaction, ret_context, prev_mask)
	thread.gpr_state.rip = thread.sigentry

	thread.gpr_state.rdi = u64(which)
	thread.gpr_state.rsi = u64(siginfo)
	thread.gpr_state.rdx = sigaction.sa_sigaction
	thread.gpr_state.rcx = u64(return_context)
	thread.gpr_state.r8 = previous_mask

	sched.yield(false)
}

pub fn sendsig(_thread &proc.Thread, signal byte) {
	mut thread := unsafe { _thread }

	katomic.bts(thread.pending_signals, signal)

	// Try to stop an event_await()
	sched.enqueue_thread(thread, true)
}

pub fn syscall_kill(_ voidptr, pid int, signal int) (u64, u64) {
	C.printf(c'\n\e[32mstrace\e[m: kill(%d, %d)\n', pid, signal)
	defer {
		C.printf(c'\e[32mstrace\e[m: returning\n')
	}

	if signal > 0 {
		sendsig(processes[pid].threads[0], byte(signal))
	} else {
		panic('sendsig: Values of signal <= 0 not supported')
	}

	return 0, 0
}

pub fn syscall_execve(_ voidptr, _path charptr, _argv &charptr, _envp &charptr) (u64, u64) {
	C.printf(c'\n\e[32mstrace\e[m: execve(%s, [omit], [omit])\n', _path)
	defer {
		C.printf(c'\e[32mstrace\e[m: returning\n')
	}

	path := unsafe { cstring_to_vstring(_path) }
	mut argv := []string{}
	for i := 0; true; i++ {
		unsafe {
			if voidptr(_argv[i]) == voidptr(0) {
				break
			}
			argv << cstring_to_vstring(_argv[i])
		}
	}
	mut envp := []string{}
	for i := 0; true; i++ {
		unsafe {
			if voidptr(_envp[i]) == voidptr(0) {
				break
			}
			envp << cstring_to_vstring(_envp[i])
		}
	}

	start_program(true, proc.current_thread().process.current_directory, path, argv, envp,
		'', '', '') or { return -1, errno.get() }

	return -1, errno.get()
}

pub fn syscall_waitpid(_ voidptr, pid int, _status &int, options int) (u64, u64) {
	C.printf(c'\n\e[32mstrace\e[m: waitpid(%d, 0x%llx, %d)\n', pid, _status, options)
	defer {
		C.printf(c'\e[32mstrace\e[m: returning\n')
	}

	mut status := unsafe { _status }
	mut current_thread := proc.current_thread()
	mut current_process := current_thread.process

	mut events := []&eventstruct.Event{}
	mut child := &proc.Process(0)

	if pid == -1 {
		if current_process.children.len == 0 {
			return -1, errno.echild
		}
		for c in current_process.children {
			events << &c.event
		}
	} else if pid < -1 || pid == 0 {
		print('\nwaitpid: value of pid not supported\n')
		return -1, errno.einval
	} else {
		if current_process.children.len == 0 {
			return -1, errno.echild
		}
		child = processes[pid]
		if voidptr(child) == voidptr(0) || child.ppid != current_process.pid {
			return -1, errno.echild
		}
		events << &child.event
	}

	block := options & userland.wnohang == 0
	which := event.await(mut events, block) or { return -1, errno.eintr }

	if voidptr(child) == voidptr(0) {
		child = current_process.children[which]
	}

	unsafe {
		status[0] = child.status
	}
	ret := child.pid

	proc.free_pid(ret)

	current_process.children.delete(current_process.children.index(child))

	return u64(ret), 0
}

[noreturn]
pub fn syscall_exit(_ voidptr, status int) {
	C.printf(c'\n\e[32mstrace\e[m: exit(%d)\n', status)
	defer {
		C.printf(c'\e[32mstrace\e[m: returning\n')
	}

	mut current_thread := proc.current_thread()
	mut current_process := current_thread.process

	mut old_pagemap := current_process.pagemap

	kernel_pagemap.switch_to()
	current_thread.process = kernel_process

	// Close all FDs
	for i := 0; i < proc.max_fds; i++ {
		if current_process.fds[i] == voidptr(0) {
			continue
		}

		file.fdnum_close(current_process, i) or {}
	}

	// PID 1 inherits children
	if current_process.pid != 1 {
		for child in current_process.children {
			processes[1].children << child
		}
	}

	mmap.delete_pagemap(old_pagemap) or {}

	katomic.store(current_process.status, status | 0x200)
	event.trigger(mut current_process.event, false)

	sched.dequeue_and_die()
}

pub fn syscall_fork(gpr_state &cpulocal.GPRState) (u64, u64) {
	C.printf(c'\n\e[32mstrace\e[m: fork()\n')
	defer {
		C.printf(c'\e[32mstrace\e[m: returning\n')
	}

	old_thread := proc.current_thread()
	mut old_process := old_thread.process

	mut new_process := sched.new_process(old_process, voidptr(0)) or { return -1, errno.get() }

	// Dup all FDs
	for i := 0; i < proc.max_fds; i++ {
		if old_process.fds[i] == voidptr(0) {
			continue
		}

		file.fdnum_dup(old_process, i, new_process, i, 0, true) or { panic('') }
	}

	stack_size := u64(0x200000)

	mut stacks := []voidptr{}

	kernel_stack_phys := memory.pmm_alloc(stack_size / page_size)
	stacks << kernel_stack_phys
	kernel_stack := u64(kernel_stack_phys) + stack_size + higher_half

	pf_stack_phys := memory.pmm_alloc(stack_size / page_size)
	stacks << pf_stack_phys
	pf_stack := u64(pf_stack_phys) + stack_size + higher_half

	mut new_thread := &proc.Thread{
		gpr_state: gpr_state
		process: new_process
		timeslice: old_thread.timeslice
		gs_base: old_thread.gs_base
		fs_base: old_thread.fs_base
		kernel_stack: kernel_stack
		pf_stack: pf_stack
		running_on: u64(-1)
		cr3: u64(new_process.pagemap.top_level)
		sigentry: old_thread.sigentry
		sigactions: old_thread.sigactions
		masked_signals: old_thread.masked_signals
		stacks: stacks
		fpu_storage: unsafe { C.malloc(fpu_storage_size) }
	}

	new_thread.self = voidptr(new_thread)

	unsafe { C.memcpy(new_thread.fpu_storage, old_thread.fpu_storage, fpu_storage_size) }

	new_thread.gpr_state.rax = u64(0)
	new_thread.gpr_state.rdx = u64(0)

	old_process.children << new_process
	new_process.threads << new_thread

	sched.enqueue_thread(new_thread, false)

	return u64(new_process.pid), u64(0)
}

pub fn start_program(execve bool, dir &fs.VFSNode, path string, argv []string, envp []string, stdin string, stdout string, stderr string) ?&proc.Process {
	prog_node := fs.get_node(dir, path, true) ?
	mut prog := prog_node.resource

	mut new_pagemap := memory.new_pagemap()

	// Check for shebang before proceeding as if it was an ELF.
	mut shebang := [2]char{}
	prog.read(0, &shebang[0], 0, 2) ?
	if shebang[0] == char(`#`) && shebang[1] == char(`!`) {
		real_path, arg := parse_shebang(mut prog) ?
		mut final_argv := [real_path]
		if arg != '' { final_argv << arg }
		final_argv << path
		final_argv << argv[1..]

		return start_program(
			execve,
			dir,
			real_path,
			final_argv,
			envp,
			stdin,
			stdout,
			stderr
		)
	}

	auxval, ld_path := elf.load(new_pagemap, prog, 0) ?

	mut entry_point := voidptr(0)

	if ld_path == '' {
		entry_point = voidptr(auxval.at_entry)
	} else {
		ld_node := fs.get_node(vfs_root, ld_path, true) ?
		ld := ld_node.resource

		ld_auxval, _ := elf.load(new_pagemap, ld, 0x40000000) ?

		entry_point = voidptr(ld_auxval.at_entry)
	}

	if execve == false {
		mut new_process := sched.new_process(voidptr(0), new_pagemap) ?

		stdin_node := fs.get_node(vfs_root, stdin, true) ?
		stdin_handle := &file.Handle{
			resource: stdin_node.resource
			node: stdin_node
			refcount: 1
		}
		stdin_fd := &file.FD{
			handle: stdin_handle
		}
		new_process.fds[0] = voidptr(stdin_fd)

		stdout_node := fs.get_node(vfs_root, stdout, true) ?
		stdout_handle := &file.Handle{
			resource: stdout_node.resource
			node: stdout_node
			refcount: 1
		}
		stdout_fd := &file.FD{
			handle: stdout_handle
		}
		new_process.fds[1] = voidptr(stdout_fd)

		stderr_node := fs.get_node(vfs_root, stderr, true) ?
		stderr_handle := &file.Handle{
			resource: stderr_node.resource
			node: stderr_node
			refcount: 1
		}
		stderr_fd := &file.FD{
			handle: stderr_handle
		}
		new_process.fds[2] = voidptr(stderr_fd)

		sched.new_user_thread(new_process, true, entry_point, voidptr(0), argv, envp,
			auxval, true) ?

		return new_process
	} else {
		mut thread := proc.current_thread()
		mut process := thread.process

		mut old_pagemap := process.pagemap

		process.pagemap = new_pagemap

		kernel_pagemap.switch_to()
		thread.process = kernel_process

		mmap.delete_pagemap(old_pagemap) ?

		process.thread_stack_top = u64(0x70000000000)
		process.mmap_anon_non_fixed_base = u64(0x80000000000)

		// TODO: Kill old threads
		// old_threads := process.threads
		process.threads = []&proc.Thread{}

		sched.new_user_thread(process, true, entry_point, voidptr(0), argv, envp, auxval,
			true) ?

		unsafe {
			for s in argv {
				s.free()
			}
			argv.free()

			for s in envp {
				s.free()
			}
			envp.free()
		}
		sched.dequeue_and_die()
	}
}

pub fn parse_shebang(mut res &resource.Resource) ?(string, string) {
	// Parse the shebang that we already know is there.
	// Syntax: #![whitespace]interpreter [single arg]new line
	mut index := u64(2)
	mut build_path := strings.new_builder(512)
	mut build_arg  := strings.new_builder(512)

	mut c := char(0)
	res.read(0, &c, index, 1) ?
	if c == char(` `) {
		index++
	}

	for {
		res.read(0, &c, index, 1) ?
		index++
		if c == char(` `) {
			break
		}
		if c == char(`\n`) {
			unsafe { goto ret }
		}
		build_path.write_rune(rune(c))
	}

	for {
		res.read(0, &c, index, 1) ?
		index++
		if c == char(` `) || c == char(`\n`) {
			break
		}
		build_arg.write_rune(rune(c))
	}

ret:
	final_path := build_path.str()
	final_arg  := build_arg.str()
	unsafe {
		build_path.free()
		build_arg.free()
	}
	return final_path, final_arg
}

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
import x86.cpu
import katomic
import event
import event.eventstruct
import errno
import lib
import strings
import resource

pub const wnohang = 1

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
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: getpid()\n', process.name.str)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	mut t := unsafe { proc.current_thread() }

	return u64(t.process.pid), 0
}

pub fn syscall_getppid(_ voidptr) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: getppid()\n', process.name.str)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	mut t := unsafe { proc.current_thread() }

	return u64(t.process.ppid), 0
}

pub fn syscall_getgroups(_ voidptr, size int, list &u32) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: getgroups(%d, 0x%llx)\n', process.name.str, size, voidptr(list))
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	return 0, 0
}

pub fn syscall_sigentry(_ voidptr, sigentry u64) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: sigentry(0x%llx)\n', process.name.str, sigentry)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	mut t := proc.current_thread()

	t.sigentry = sigentry

	return 0, 0
}

@[noreturn]
pub fn syscall_sigreturn(_ voidptr, context &cpulocal.GPRState, old_mask u64) {
	mut t := unsafe { proc.current_thread() }

	asm volatile amd64 {
		cli
	}

	t.gpr_state = *context
	t.masked_signals = old_mask

	sched.yield(false)

	for {}
}

pub fn syscall_sigaction(_ voidptr, signum int, act &proc.SigAction, oldact &proc.SigAction) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: sigaction(%d, 0x%llx, 0x%llx)\n', process.name.str, signum,
		voidptr(act), voidptr(oldact))
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	if signum < 0 || signum > 34 || signum == userland.sigkill || signum == userland.sigstop {
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
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: sigprocmask(%d, 0x%llx, 0x%llx)\n', process.name.str, how,
		voidptr(set), voidptr(oldset))
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	mut t := proc.current_thread()

	if oldset != unsafe { nil } {
		unsafe {
			*oldset = t.masked_signals
		}
	}

	if set != unsafe { nil } {
		match how {
			userland.sig_block {
				t.masked_signals |= *set
			}
			userland.sig_unblock {
				t.masked_signals &= ~*set
			}
			userland.sig_setmask {
				t.masked_signals = *set
			}
			else {}
		}
	}

	return 0, 0
}

// Dispatch a signal to _self_, this is called from the scheduler, at the
// end of syscalls, or from exception handlers.
pub fn dispatch_a_signal(context &cpulocal.GPRState) {
	mut t := unsafe { proc.current_thread() }

	if t.sigentry == 0 {
		return
	}

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

	previous_mask := t.masked_signals

	t.masked_signals |= sigaction.sa_mask
	if sigaction.sa_flags & userland.sa_nodefer == 0 {
		t.masked_signals |= u64(1) << which
	}

	// Respect the redzone
	t.gpr_state.rsp -= 128
	t.gpr_state.rsp = lib.align_down(t.gpr_state.rsp, 16)

	// Return context
	t.gpr_state.rsp -= sizeof(cpulocal.GPRState)
	t.gpr_state.rsp = lib.align_down(t.gpr_state.rsp, 16)
	mut return_context := &cpulocal.GPRState(t.gpr_state.rsp)

	unsafe {
		*return_context = *context
	}
	t.gpr_state = *context
	// Siginfo
	t.gpr_state.rsp -= sizeof(SigInfo)
	t.gpr_state.rsp = lib.align_down(t.gpr_state.rsp, 16)
	mut siginfo := &SigInfo(t.gpr_state.rsp)

	unsafe { C.memset(voidptr(siginfo), 0, sizeof(SigInfo)) }
	siginfo.si_signo = which

	// Alignment
	t.gpr_state.rsp -= 8

	// Common handler will take (which, siginfo, sigaction, ret_context, prev_mask)
	t.gpr_state.rip = t.sigentry

	t.gpr_state.rdi = u64(which)
	t.gpr_state.rsi = u64(siginfo)
	t.gpr_state.rdx = u64(sigaction.sa_sigaction)
	t.gpr_state.rcx = u64(return_context)
	t.gpr_state.r8 = previous_mask

	sched.yield(false)
}

pub fn sendsig(_thread &proc.Thread, signal u8) {
	mut t := unsafe { _thread }

	katomic.bts(mut &t.pending_signals, signal)

	// Try to stop an event_await()
	sched.enqueue_thread(t, true)
}

pub fn syscall_kill(_ voidptr, pid int, signal int) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: kill(%d, %d)\n', process.name.str, pid, signal)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	if signal > 0 {
		sendsig(processes[pid].threads[0], u8(signal))
	} else {
		panic('sendsig: Values of signal <= 0 not supported')
	}

	return 0, 0
}

pub fn syscall_execve(_ voidptr, _path charptr, _argv &charptr, _envp &charptr) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: execve(%s, [omit], [omit])\n', process.name.str, _path)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

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

	C.printf(c'\n\e[32m%s\e[m: waitpid(%d, 0x%llx, %d)\n', current_process.name.str, pid,
		_status, options)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', current_process.name.str)
	}

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

	block := options & userland.wnohang == 0
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

	C.printf(c'\n\e[32m%s\e[m: exit(%d)\n', current_process.name.str, status)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', current_process.name.str)
	}

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
		for child in current_process.children {
			processes[1].children << child
		}
	}

	mmap.delete_pagemap(mut old_pagemap) or {}

	katomic.store(mut &current_process.status, int(u32(status) << 8))
	event.trigger(mut &current_process.event, false)

	sched.dequeue_and_die()
}

pub fn syscall_fork(gpr_state &cpulocal.GPRState) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: fork()\n', process.name.str)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	old_thread := proc.current_thread()
	mut old_process := old_thread.process

	mut new_process := sched.new_process(old_process, unsafe { nil }) or {
		return errno.err, errno.get()
	}

	new_process.name = '${old_process.name}[${new_process.pid}]'

	// Dup all FDs
	for i := 0; i < proc.max_fds; i++ {
		if old_process.fds[i] == unsafe { nil } {
			continue
		}

		file.fdnum_dup(old_process, i, new_process, i, 0, true, false) or { panic('') }
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
		gs_base: cpu.get_kernel_gs_base()
		fs_base: cpu.get_fs_base()
		kernel_stack: kernel_stack
		pf_stack: pf_stack
		running_on: u64(-1)
		cr3: u64(new_process.pagemap.top_level)
		sigentry: old_thread.sigentry
		sigactions: old_thread.sigactions
		masked_signals: old_thread.masked_signals
		stacks: stacks
		fpu_storage: unsafe { malloc(fpu_storage_size) }
	}

	unsafe { stacks.free() }

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

	auxval, ld_path := elf.load(new_pagemap, prog, 0) or { return none }

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

		unsafe { ld_path.free() }
	}

	if execve == false {
		mut new_process := sched.new_process(unsafe { nil }, new_pagemap)?

		new_process.name = '${path}[${new_process.pid}]'

		stdin_node := fs.get_node(vfs_root, stdin, true)?
		stdin_handle := &file.Handle{
			resource: stdin_node.resource
			node: stdin_node
			refcount: 1
		}
		stdin_fd := &file.FD{
			handle: stdin_handle
		}
		new_process.fds[0] = voidptr(stdin_fd)

		stdout_node := fs.get_node(vfs_root, stdout, true)?
		stdout_handle := &file.Handle{
			resource: stdout_node.resource
			node: stdout_node
			refcount: 1
		}
		stdout_fd := &file.FD{
			handle: stdout_handle
		}
		new_process.fds[1] = voidptr(stdout_fd)

		stderr_node := fs.get_node(vfs_root, stderr, true)?
		stderr_handle := &file.Handle{
			resource: stderr_node.resource
			node: stderr_node
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
		mut process := t.process

		mut old_pagemap := process.pagemap

		process.pagemap = new_pagemap

		process.name = '${path}[${process.pid}]'

		kernel_pagemap.switch_to()
		t.process = kernel_process

		mmap.delete_pagemap(mut old_pagemap)?

		process.thread_stack_top = u64(0x70000000000)
		process.mmap_anon_non_fixed_base = u64(0x80000000000)

		// TODO: Kill old threads
		// old_threads := process.threads
		process.threads = []&proc.Thread{}

		sched.new_user_thread(process, true, entry_point, unsafe { nil }, 0, argv, envp,
			auxval, true)?

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

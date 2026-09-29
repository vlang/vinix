module userland

import fs
import memory
import memory.mmap
import elf
import sched
import file
import posixtimer
import proc
import x86.cpu.local as cpulocal
import x86.cpu
import x86.gdt
import katomic
import event
import event.eventstruct
import errno
import lib
import strings
import resource
import term
import usercopy
import stat

// Only condition/status bits that userspace can normally change may cross the
// sigreturn boundary. In particular, IOPL, NT, VM, VIF and VIP must never be
// restored from an untrusted signal frame. IF is forced on so a forged frame
// cannot pin a CPU with interrupts disabled.
const amd64_sigreturn_rflags_mask = cpu.rflags_cf | cpu.rflags_pf | cpu.rflags_af |
	cpu.rflags_zf | cpu.rflags_sf | cpu.rflags_tf | cpu.rflags_df | cpu.rflags_of |
	cpu.rflags_rf | cpu.rflags_id

const amd64_sigreturn_rflags_fixed = cpu.rflags_fixed | cpu.rflags_if

fn valid_sigreturn_context(context &cpulocal.GPRState) bool {
	user_limit := memory.user_address_limit()
	return context.rip != 0 && context.rip < user_limit && context.rsp != 0
		&& context.rsp < user_limit
}

fn sanitize_sigreturn_context(mut context cpulocal.GPRState) {
	context.cs = u64(gdt.user_code_selector)
	context.ss = u64(gdt.user_data_selector)
	context.ds = u64(gdt.user_data_selector)
	context.es = u64(gdt.user_data_selector)
	context.rflags = (context.rflags & amd64_sigreturn_rflags_mask) | amd64_sigreturn_rflags_fixed
}

@[noreturn]
fn resume_sigreturn(context cpulocal.GPRState, old_mask u64) {
	mut t := unsafe { proc.current_thread() }

	asm volatile amd64 {
		cli
	}

	t.gpr_state = context
	t.masked_signals = old_mask & ~unblockable_mask()

	// A signal the restored mask lets through runs now, as on arm64, whose
	// rt_sigreturn goes back through the syscall exit: one that had waited
	// for the handler to finish was otherwise left for the next syscall.
	mut resumed := context
	dispatch_signal(&resumed, 0, 0, 0)

	sched.resume_saved_context()

	for {}
}

// A syscall that a signal interrupted before it had done anything returns
// ERESTARTSYS. Rewind to the SYSCALL so that it runs again once the signal
// has been dealt with, as Linux and arm64 do: Go relies on SA_RESTART for
// calls it does not retry itself, while its runtime preempts goroutines with
// SIGURG. The signal dispatched next takes the rewind back if its handler was
// installed without SA_RESTART.
pub fn prepare_syscall_restart(context &cpulocal.GPRState) {
	mut ctx := unsafe { context }
	if ctx.rax != u64(-i64(proc.interrupted_errno)) {
		return
	}
	mut t := proc.current_thread()
	ctx.rax = t.restart_nr
	// SYSCALL is two bytes long, and SYSRET returns to rcx.
	ctx.rip -= 2
	ctx.rcx = ctx.rip
	t.restarting_syscall = true
}

// Whether `t` has a signal it does not block waiting for it, or has been told
// to exit: what an interrupt returning to userspace sends it into the kernel
// for.
fn owes_async_work(t &proc.Thread) bool {
	if katomic.load(&t.must_exit) {
		return true
	}
	pending := katomic.load(&t.pending_signals)
	return pending & ~t.masked_signals != 0 || pending & unblockable_mask() != 0
}

// An interrupt, the scheduler's included, is about to return to `frame`, the
// thread in userspace. A signal that is pending for it now, or an exit a
// sibling asked for, has to be dealt with there and then, as on arm64: a loop
// that makes no syscalls is otherwise never interrupted, and cannot even be
// killed. That cannot be done on the stack interrupts run on, which belongs
// to the CPU and must not block; so the frame is pointed at
// async_signal_entry() on the thread's own kernel stack, which is idle while
// the thread is in userspace, and the thread goes on from there.
pub fn interrupt_return(frame &cpulocal.GPRState) {
	mut t := proc.current_thread()
	if t == unsafe { nil } || t.process == unsafe { nil } || !owes_async_work(t) {
		return
	}
	mut f := unsafe { frame }
	t.async_context = *f
	f.rip = u64(voidptr(async_signal_entry))
	f.cs = u64(gdt.kernel_code_selector)
	f.ss = u64(gdt.kernel_data_selector)
	f.ds = u64(gdt.kernel_data_selector)
	f.es = u64(gdt.kernel_data_selector)
	// As if called: the return address slot a function expects to find.
	f.rsp = t.kernel_stack - 8
	f.rflags = cpu.rflags_fixed
}

// Where interrupt_return() sends a thread, in the kernel on its own stack,
// with what it interrupted in async_context.
@[noreturn]
fn async_signal_entry() {
	mut t := proc.current_thread()
	mut context := t.async_context
	exit_if_told_to()
	dispatch_signal(&context, 0, 0, 0)
	// Nothing was delivered after all: go back where the thread was.
	t.gpr_state = context
	sched.resume_saved_context()
	for {}
}

fn dispatch_signal(context &cpulocal.GPRState, info_signum int, info_code int, info_addr u64) {
	mut t := unsafe { proc.current_thread() }
	restarting := t.restarting_syscall
	t.restarting_syscall = false

	mut which := -1

	// Signal n is bit n-1, as in Linux's sigsets. SIGKILL and SIGSTOP get
	// through whatever the mask says, so that a wait that installed a full
	// temporary mask cannot keep the process alive against kill -9.
	for i := u8(0); i < 64; i++ {
		signum := int(i) + 1
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

	dispatch_linux_signal(context, which, info_signum, info_code, info_addr, restarting)
}

// Dispatch a signal to _self_, this is called from the scheduler or at the
// end of syscalls.
pub fn dispatch_a_signal(context &cpulocal.GPRState) {
	dispatch_signal(context, 0, 0, 0)
}

// Synchronous CPU faults carry information that Wine's exception dispatcher
// reads from siginfo and ucontext.
pub fn dispatch_a_signal_info(context &cpulocal.GPRState, signal int, code int, addr u64) {
	dispatch_signal(context, signal, code, addr)
}

pub fn syscall_execve(_ voidptr, _path charptr, _argv &charptr, _envp &charptr) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: execve(%s, [omit], [omit])\n', process.name.str, _path)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	path := unsafe { cstring_to_vstring(_path) }
	// Both vectors are only built here, so growing them can give back what
	// they outgrow.
	mut argv := []string{}
	argv.flags |= .noslices
	for i := 0; true; i++ {
		unsafe {
			if _argv[i] == nil {
				break
			}
			argv << cstring_to_vstring(_argv[i])
		}
	}
	mut envp := []string{}
	envp.flags |= .noslices
	for i := 0; true; i++ {
		unsafe {
			if _envp[i] == nil {
				break
			}
			envp << cstring_to_vstring(_envp[i])
		}
	}

	// The path and both vectors are the exec's now, freed whether it works or
	// not. A failed exec is common: execvp() tries every directory in PATH.
	start_program(true, proc.current_directory_of(proc.current_thread().process), path, argv,
		envp, '', '', '') or { return errno.err, errno.get() }

	return errno.err, errno.get()
}

// OpenBSD kills a process that breaks a pledge(2) promise with SIGABRT,
// which it cannot catch or ignore.
@[noreturn]
pub fn exit_on_pledge_violation() {
	exit_by_signal(6)
}

// End the calling process as one killed by `signal`, which is what wait()
// then reports instead of an exit status.
@[noreturn]
pub fn exit_by_signal(signal int) {
	exit_process(u32(signal) & 0x7f)
}

// `wait_status` is what wait() will report, encoded the way Linux does.
@[noreturn]
fn exit_process(wait_status u32) {
	mut current_thread := proc.current_thread()
	mut current_process := current_thread.process

	// One thread tears a process down. Another that gets here meanwhile -- a
	// sibling in exit_group() at the same moment, or one whose own exit raced
	// the teardown -- just goes.
	current_process.threads_lock.acquire()
	if current_process.exiting {
		current_process.threads_lock.release()
		kernel_pagemap.switch_to()
		sched.dequeue_and_die()
	}
	current_process.exiting = true
	current_process.threads_lock.release()

	// Every other thread is stopped before the address space and descriptors
	// they are using go away, and so are the POSIX timers aimed at them.
	kill_sibling_threads(mut current_process, current_thread)
	posixtimer.remove_process_timers(current_process)
	if current_thread.tid != current_process.pid {
		proc.free_tid(current_thread.tid)
	}

	// A framebuffer owner can exit without issuing a console ioctl. Restore
	// the saved text console before its address space and descriptors vanish.
	term.leave_graphics_mode_if_owner(current_process.pid)

	mut old_pagemap := current_process.pagemap

	kernel_pagemap.switch_to()
	current_thread.process = kernel_process
	// Detached under the process table lock, which cgroup memory accounting
	// and /proc hold while they walk a process' page map, so none is still
	// walking the one freed below.
	proc.lock_table()
	current_process.pagemap = unsafe { nil }
	proc.unlock_table()

	// Close all FDs
	for i := 0; i < current_process.fds.len; i++ {
		if current_process.fds[i] == unsafe { nil } {
			continue
		}

		file.fdnum_close(current_process, i, true) or {}
	}
	// What closing them changed -- the inode of an unlinked file, freed with
	// its last descriptor -- goes out before the parent can wait for the exit,
	// as it would on the way back from close(2).
	flush_owed_sync()

	// PID 1 inherits children
	if current_process.pid != 1 {
		for child in current_process.children {
			processes[1].children << child
		}
	}

	mmap.delete_pagemap(mut old_pagemap) or {}

	katomic.store(mut &current_process.status, int(wait_status))
	event.trigger(mut &current_process.event, false)

	// The parent hears of it through SIGCHLD as well as wait(): a shell such as
	// zsh reaps from its SIGCHLD handler, and sleeps in sigsuspend() until then.
	if current_process.ppid > 0 && current_process.ppid < proc.max_pid {
		mut parent := processes[current_process.ppid]
		if parent != unsafe { nil } {
			signal_process(mut parent, sigchld)
		}
	}

	sched.dequeue_and_die()
}

// With `execve` set, the exec owns `_path`, `argv` and `envp` and frees them
// whether it works or not; one that works never returns. The boot path that
// starts init passes `execve` unset and keeps them.
pub fn start_program(execve bool, dir &fs.VFSNode, _path string, argv []string, envp []string, stdin_path string, stdout_path string, stderr_path string) ?&proc.Process {
	// Chromium starts every child process by executing /proc/self/exe. The VFS
	// resolves that to this process's program, but the new process must record
	// where the program really is: keeping the literal path would make the
	// child's own /proc/self/exe point back at itself forever.
	path := fs.resolve_self_reference(_path)
	if execve && path.str != _path.str && !argv.any(it.str == _path.str) {
		unsafe { _path.free() }
	}
	prog_node := fs.get_node(dir, path, true) or {
		if execve {
			free_exec_arguments(path, argv, envp)
		}
		return none
	}
	return start_program_node(execve, dir, prog_node, path, argv, envp, stdin_path,
		stdout_path, stderr_path)
}

// Frees what an exec was handed, once it has failed or is about to leave for
// good. `path` can be one of the arguments too: a script's interpreter is put
// into argv as well.
fn free_exec_arguments(path string, argv []string, envp []string) {
	path_in_argv := argv.any(it.str == path.str)
	unsafe {
		if !path_in_argv {
			path.free()
		}
		argv.free()
		envp.free()
	}
}

// The part of exec that follows finding the program. execveat(2) on a
// descriptor comes here directly: a memfd has no name to be found by. What an
// exec was handed is freed here when it fails, unless load_program_image()
// has handed it on to a script interpreter's exec, which frees it.
pub fn start_program_node(execve bool, dir &fs.VFSNode, prog_node &fs.VFSNode, path string, argv []string, envp []string, stdin_path string, stdout_path string, stderr_path string) ?&proc.Process {
	mut handed_on := false
	process := load_program_image(execve, dir, prog_node, path, argv, envp, stdin_path,
		stdout_path, stderr_path, mut handed_on) or {
		if execve && !handed_on {
			free_exec_arguments(path, argv, envp)
		}
		return none
	}
	return process
}

fn load_program_image(execve bool, dir &fs.VFSNode, prog_node &fs.VFSNode, path string, argv []string, envp []string, stdin_path string, stdout_path string, stderr_path string, mut handed_on bool) ?&proc.Process {
	// The program, or a script's interpreter, is subject to pledge(2) and
	// unveil(2); the ELF interpreter the kernel loads for it is not.
	if execve && !fs.policy_check(prog_node, proc.policy_exec) {
		return none
	}
	if !stat.isreg(prog_node.resource.stat.mode)
		|| !fs.check_access(prog_node, fs.access_exec, true) {
		errno.set(errno.eacces)
		return none
	}
	mut prog := prog_node.resource

	// Check for shebang before proceeding as if it was an ELF.
	mut shebang := [2]char{}
	prog.read(0, &shebang[0], 0, 2)?
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
			handed_on = true
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

	// Made after the shebang check: a script never used it, and lost it.
	mut new_pagemap := memory.new_pagemap()

	mut auxval, ld_path := elf.load(new_pagemap, prog, 0) or { return none }
	allow_wx := envp.contains('VINIX_ALLOW_WX=1')

	mut entry_point := unsafe { nil }

	if ld_path == '' {
		entry_point = voidptr(auxval.at_entry)
	} else {
		ld_node := fs.get_node(vfs_root, ld_path, true)?
		if !stat.isreg(ld_node.resource.stat.mode)
			|| !fs.check_access(ld_node, fs.access_exec, true) {
			errno.set(errno.eacces)
			return none
		}
		ld := ld_node.resource

		ld_auxval, interp := elf.load(new_pagemap, ld, elf.interpreter_load_base()) or {
			return none
		}

		if interp != '' {
			unsafe { interp.free() }
		}

		entry_point = voidptr(ld_auxval.at_entry)
		auxval.at_base = ld_auxval.at_base

		unsafe { ld_path.free() }
	}

	if execve == false {
		mut new_process := sched.new_process(unsafe { nil }, new_pagemap)?

		new_process.name = proc.process_name(path, new_process.pid)
		new_process.executable_path = fs.program_path(prog_node, path)
		new_process.exe_node = voidptr(prog_node)
		new_process.allow_wx = allow_wx
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

		sched.new_user_thread(new_process, true, entry_point, unsafe { nil }, 0, argv,
			envp, auxval, true)?

		return new_process
	} else {
		mut t := proc.current_thread()
		mut process := t.process

		// Every other thread has to be gone before the address space it runs
		// in is replaced, and before the close-on-exec descriptors go. POSIX
		// timers do not survive an exec either.
		kill_sibling_threads(mut process, t)
		posixtimer.remove_process_timers(process)

		// Close the O_CLOEXEC descriptors, as execve(2) promises. A pipe end
		// that survived the exec would keep its reader from ever seeing end
		// of file: posix_spawn() and Python's subprocess learn that the
		// child's exec worked from exactly that end of file. The table stops
		// growing with the other threads gone.
		for i := 0; i < process.fds.len; i++ {
			fd_ptr := unsafe { &file.FD(process.fds[i]) }
			if fd_ptr == unsafe { nil } {
				continue
			}
			if fd_ptr.flags & resource.o_cloexec != 0 {
				file.fdnum_close(process, i, true) or {}
			}
		}

		// Swapped under the process table lock, which cgroup memory accounting
		// and /proc hold while they walk a process' page map: the old one is
		// freed below.
		proc.lock_table()
		mut old_pagemap := process.pagemap
		process.pagemap = new_pagemap
		proc.unlock_table()

		// The copies fork made are replaced, not kept alongside.
		unsafe {
			process.name.free()
			process.executable_path.free()
		}
		process.name = proc.process_name(path, process.pid)
		// /proc/self/exe leads to the program's node, as on arm64, so that it
		// names the file wherever the exec found it -- by a relative path, or
		// through a descriptor.
		process.executable_path = fs.program_path(prog_node, path)
		process.exe_node = voidptr(prog_node)
		process.allow_wx = allow_wx
		// The new program runs under the execpromises, or unpledged.
		proc.pledge_after_exec(mut process)
		// Frames the old program was given must not return into the new one.
		process.sigcookie = proc.new_sigcookie()

		kernel_pagemap.switch_to()
		t.process = kernel_process

		mmap.delete_pagemap(mut old_pagemap)?

		process.thread_stack_top = elf.initial_stack_top()
		process.mmap_anon_non_fixed_base = elf.initial_mmap_base()
		// The old program's break went with its page map; the new one
		// reserves its own arena on its first brk().
		process.brk_base = 0
		process.brk_current = 0

		// Same lock new_user_thread's append holds: without it, a concurrent
		// reader of process.threads (syscall_kill's broadcast path) could
		// observe this array mid-replacement.
		// Emptied, not replaced: a new empty list lost the old one's buffer.
		process.threads_lock.acquire()
		process.threads.clear()
		process.threads_lock.release()

		// The program that comes out of exec has one thread, the group leader,
		// which takes the pid as its tid. A thread other than the leader that
		// called execve gives its own number back.
		if t.tid != process.pid {
			proc.free_tid(t.tid)
		}

		mut new_thread := sched.new_user_thread(process, true, entry_point, unsafe { nil },
			0, argv, envp, auxval, false)?

		// execve keeps the signal mask and what was ignored; only handlers,
		// which pointed into the old program, go back to the default.
		new_thread.masked_signals = t.masked_signals
		for i := 0; i < t.sigactions.len; i++ {
			if u64(t.sigactions[i].sa_sigaction) == linux_sig_ign {
				new_thread.sigactions[i].sa_sigaction = voidptr(linux_sig_ign)
			}
		}
		sched.enqueue_thread(new_thread, false)

		// This never returns, so the caller cannot free what the exec was
		// handed; the path was lost with every exec.
		free_exec_arguments(path, argv, envp)
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
		// The descriptor's name below takes the empty path's place.
		unsafe { path.free() }
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
		mut name := lib.new_text(32)
		name.add('/proc/self/fd/')
		name.add_decimal(i64(dirfd))
		target = name.str()
	} else {
		directory = fs.parent_dir_for(dirfd, path) or {
			unsafe { path.free() }
			return errno.err, errno.get()
		}
	}

	mut argv := []string{}
	argv.flags |= .noslices
	for i := 0; true; i++ {
		unsafe {
			if _argv[i] == nil {
				break
			}
			argv << cstring_to_vstring(_argv[i])
		}
	}
	mut envp := []string{}
	envp.flags |= .noslices
	for i := 0; true; i++ {
		unsafe {
			if _envp[i] == nil {
				break
			}
			envp << cstring_to_vstring(_envp[i])
		}
	}

	// The path and both vectors are the exec's now, freed whether it works or
	// not.
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

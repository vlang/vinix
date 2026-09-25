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

// Only condition/status bits that userspace can normally change may cross the
// sigreturn boundary. In particular, IOPL, NT, VM, VIF and VIP must never be
// restored from an untrusted signal frame. IF is forced on so a forged frame
// cannot pin a CPU with interrupts disabled.
const amd64_sigreturn_rflags_mask = cpu.rflags_cf | cpu.rflags_pf | cpu.rflags_af |
	cpu.rflags_zf | cpu.rflags_sf | cpu.rflags_tf | cpu.rflags_df | cpu.rflags_of |
	cpu.rflags_rf | cpu.rflags_id

const amd64_sigreturn_rflags_fixed = cpu.rflags_fixed | cpu.rflags_if

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
	// Vinix's amd64 signal bitmap uses the signal number as its bit index.
	t.masked_signals = old_mask & ~((u64(1) << sigkill) | (u64(1) << sigstop))

	sched.resume_saved_context()

	for {}
}

pub fn syscall_sigreturn(_ voidptr, context_ptr u64, old_mask u64) (u64, u64) {
	// Signal frames live in userspace and are attacker-controlled. Resolve the
	// whole frame through the process pagemap before trusting any of it; a bad
	// pointer must not turn into a kernel-mode page fault.
	mut context := cpulocal.GPRState{}
	if !usercopy.copy_from_user(voidptr(&context), context_ptr, sizeof(cpulocal.GPRState)) {
		return errno.err, errno.efault
	}
	if !valid_sigreturn_context(&context) {
		return errno.err, errno.einval
	}
	sanitize_sigreturn_context(mut context)

	resume_sigreturn(context, old_mask)
}

pub fn syscall_sigaction(_ voidptr, signum int, act &proc.SigAction, oldact &proc.SigAction) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: sigaction(%d, 0x%llx, 0x%llx)\n', process.name.str, signum,
		voidptr(act), voidptr(oldact))
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

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
		// Dispositions belong to the process; masks and pending signals remain
		// per-thread. Keep existing helpers synchronized with the caller.
		mut target_process := t.process
		target_process.threads_lock.acquire()
		for mut target_thread in target_process.threads {
			target_thread.sigactions[signum] = *act
		}
		target_process.threads_lock.release()
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

fn dispatch_signal(context &cpulocal.GPRState, info_signum int, info_code int, info_addr u64) {
	mut t := unsafe { proc.current_thread() }
	linux := t.process.linux_abi

	if t.sigentry == 0 && !linux {
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

	if linux {
		dispatch_linux_signal(context, which, info_signum, info_code, info_addr)
		return
	}

	sigaction := t.sigactions[which]

	previous_mask := t.masked_signals

	t.masked_signals |= sigaction.sa_mask
	if sigaction.sa_flags & sa_nodefer == 0 {
		t.masked_signals |= u64(1) << which
	}

	// Work from the live syscall/interrupt frame. t.gpr_state is only updated
	// by the scheduler and can otherwise describe an older timeslice.
	t.gpr_state = *context

	// Respect the redzone
	t.gpr_state.rsp -= 128
	t.gpr_state.rsp = lib.align_down(t.gpr_state.rsp, 16)

	// Return context
	t.gpr_state.rsp -= sizeof(cpulocal.GPRState)
	t.gpr_state.rsp = lib.align_down(t.gpr_state.rsp, 16)
	mut return_context := unsafe { &cpulocal.GPRState(t.gpr_state.rsp) }

	unsafe {
		*return_context = *context
	}
	// Siginfo
	t.gpr_state.rsp -= sizeof(SigInfo)
	t.gpr_state.rsp = lib.align_down(t.gpr_state.rsp, 16)
	mut siginfo := unsafe { &SigInfo(t.gpr_state.rsp) }

	unsafe { C.memset(voidptr(siginfo), 0, sizeof(SigInfo)) }
	siginfo.si_signo = i32(which)
	if info_signum == which {
		siginfo.si_code = i32(info_code)
		siginfo.si_addr = voidptr(info_addr)
	}

	// Alignment
	t.gpr_state.rsp -= 8

	// Common handler will take (which, siginfo, sigaction, ret_context, prev_mask)
	t.gpr_state.rip = t.sigentry

	t.gpr_state.rdi = u64(which)
	t.gpr_state.rsi = u64(siginfo)
	t.gpr_state.rdx = u64(sigaction.sa_sigaction)
	t.gpr_state.rcx = u64(return_context)
	t.gpr_state.r8 = previous_mask

	sched.resume_saved_context()
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

pub fn sendsig(_thread &proc.Thread, signal u8) {
	mut t := unsafe { _thread }

	katomic.bts(mut &t.pending_signals, signal)
	// A signalfd of the process that reads this signal is readable now.
	if t.process != unsafe { nil } {
		notify_signalfds(t.process.pid, int(signal))
	}

	// Try to stop an event_await()
	sched.enqueue_thread(t, true)
}

// signalfd for the native Vinix ABI, which passes the mask itself, in this
// kernel's layout, rather than a pointer to a Linux sigset.
pub fn syscall_signalfd(_ voidptr, fdnum int, mask u64, flags int) (u64, u64) {
	if flags & ~(sfd_nonblock | sfd_cloexec) != 0 {
		return errno.err, errno.einval
	}
	return signalfd_set(fdnum, mask & ~unblockable_mask(), flags)
}

// signal_process safely delivers a signal to a process's first thread,
// synchronized against thread creation/replacement via the same lock
// new_user_thread's append and start_program()'s exec-time reset both
// hold. proc.allocate_pid()/new_process() can publish a process before
// its first thread is appended, and start_program() briefly empties
// process.threads mid-exec -- a bare process.threads[0] can land in
// either window. Returns false, rather than indexing an empty array,
// when there is currently no thread to signal.
fn signal_process(_process &proc.Process, signal u8) bool {
	mut process := unsafe { _process }
	process.threads_lock.acquire()
	defer {
		process.threads_lock.release()
	}
	if process.threads.len == 0 {
		return false
	}
	sendsig(process.threads[0], signal)
	return true
}

pub fn syscall_kill(_ voidptr, pid int, signal int) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: kill(%d, %d)\n', process.name.str, pid, signal)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	if signal < 0 {
		return errno.err, errno.einval
	}

	if pid == -1 {
		if signal == 0 {
			// The same existence/permission probe as kill(pid, 0), just
			// against "does any eligible target exist" instead of one
			// specific pid. Signal 0 is never actually sent, so it doesn't
			// need root's real system-wide broadcast (out of scope here) to
			// be implemented first -- the calling process itself is always
			// an eligible target, so this always succeeds.
			return 0, 0
		}
		// Broadcast. Root's true system-wide broadcast (including pid 1) is
		// out of scope here; a non-root caller gets the real POSIX/Linux
		// behavior, every process at its own uid, itself included.
		if process.euid != 0 {
			for i := 1; i < proc.max_pid; i++ {
				candidate := processes[i]
				if candidate != unsafe { nil } && candidate.uid == process.uid {
					signal_process(candidate, u8(signal))
				}
			}
			return 0, 0
		}
		return errno.err, errno.eperm
	}

	if pid < 0 || pid >= proc.max_pid || processes[pid] == unsafe { nil } {
		return errno.err, errno.esrch
	}

	// signal == 0 is the standard POSIX existence/permission probe: no signal
	// sent, the lookup above already did the check.
	if signal > 0 {
		if !signal_process(processes[pid], u8(signal)) {
			return errno.err, errno.esrch
		}
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

	start_program(true, proc.current_directory_of(proc.current_thread().process), path, argv,
		envp, '', '', '') or { return errno.err, errno.get() }

	return errno.err, errno.get()
}

pub fn syscall_waitpid(_ voidptr, pid int, _status &i32, options int) (u64, u64) {
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

	block := options & wnohang == 0
	which := event.await(mut events, block) or {
		// Under WNOHANG this means no child has exited yet, which Linux
		// reports as 0. EINTR sent libcs that retry interrupted calls -- musl,
		// and BusyBox's `wait` -- round a loop that never slept.
		if !block {
			return 0, 0
		}
		return errno.err, errno.eintr
	}

	if child == unsafe { nil } {
		child = current_process.children[which]
	}

	unsafe {
		*status = i32(child.status)
	}
	ret := child.pid

	proc.account_reaped_child(mut current_process, child)
	proc.free_pid(ret)

	current_process.children.delete(current_process.children.index(child))

	return u64(ret), 0
}

@[noreturn]
pub fn syscall_exit(_ voidptr, status int) {
	exit_process(u32(status) << 8)
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
		parent := processes[current_process.ppid]
		if parent != unsafe { nil } {
			signal_process(parent, sigchld)
		}
	}

	sched.dequeue_and_die()
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

// The part of exec that follows finding the program. execveat(2) on a
// descriptor comes here directly: a memfd has no name to be found by.
pub fn start_program_node(execve bool, dir &fs.VFSNode, prog_node &fs.VFSNode, path string, argv []string, envp []string, stdin_path string, stdout_path string, stderr_path string) ?&proc.Process {
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

		return start_program(execve, dir, real_path, final_argv, envp, stdin_path, stdout_path,
			stderr_path)
	}

	mut auxval, ld_path := elf.load(new_pagemap, prog, 0) or { return none }
	// Vinix's mlibc toolchain uses /usr/lib/ld.so. Everything else accepted by
	// the amd64 ELF loader follows the Linux syscall ABI; this includes Alpine's
	// /lib/ld-musl-x86_64.so.1 and static Linux executables.
	linux_abi := ld_path != '/usr/lib/ld.so'
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
		new_process.linux_abi = linux_abi
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

		was_linux := process.linux_abi
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
		process.linux_abi = linux_abi
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
		process.threads_lock.acquire()
		process.threads = []&proc.Thread{}
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
		if linux_abi && was_linux {
			for i := 0; i < t.sigactions.len; i++ {
				if u64(t.sigactions[i].sa_sigaction) == linux_sig_ign {
					new_thread.sigactions[i].sa_sigaction = voidptr(linux_sig_ign)
				}
			}
		}
		sched.enqueue_thread(new_thread, false)

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

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

pub const wnohang = 2

pub fn syscall_execve(_ voidptr, _path charptr, _argv &charptr, _envp &charptr) (u64, u64) {
	path := unsafe { cstring_to_vstring(_path) }
	mut argv := []string{}
	for i := 0; ; i++ {
		unsafe {
			if voidptr(_argv[i]) == voidptr(0) {
				break
			}
			argv << cstring_to_vstring(_argv[i])
		}
	}
	mut envp := []string{}
	for i := 0; ; i++ {
		unsafe {
			if voidptr(_envp[i]) == voidptr(0) {
				break
			}
			envp << cstring_to_vstring(_envp[i])
		}
	}

	start_program(true, path, argv, envp, '', '', '') or {
		return -1, errno.get()
	}

	return -1, errno.get()
}

pub fn syscall_waitpid(_ voidptr, pid int, _status &int, options int) (u64, u64) {
	mut status := unsafe { _status }
	mut current_thread := proc.current_thread()
	mut current_process := current_thread.process

	mut events := []&eventstruct.Event{}
	mut child := &proc.Process(0)

	if pid == -1 {
		for c in current_process.children {
			events << &c.event
		}
	} else if pid < -1 || pid == 0 {
		print('\nwaitpid: value of pid not supported\n')
		return -1, -1
	} else {
		child = processes[pid]
		if voidptr(child) == voidptr(0) || child.ppid != current_process.pid {
			return -1, errno.echild
		}
		events << &child.event
	}

	mut which := u64(0)
	block := options & wnohang != 0
	event.await(events, &which, block)

	unsafe { events.free() }

	if which == -1 {
		return 0, 0
	}

	if voidptr(child) == voidptr(0) {
		child = current_process.children[which]
	}

	unsafe { status[0] = child.status }

	ret := child.pid

	proc.free_pid(ret)

	current_process.children.delete(current_process.children.index(child))

	return u64(ret), 0
}

pub fn syscall_exit(_ voidptr, status int) {
	mut current_thread := proc.current_thread()
	mut current_process := current_thread.process

	kernel_pagemap.switch_to()

	// Close all FDs
	for i := 0; i < proc.max_fds; i++ {
		if current_process.fds[i] == voidptr(0) {
			continue
		}

		file.fdnum_close(current_process, i) or {
			panic('')
		}
	}

	// PID 1 inherits children
	if current_process.pid != 1 {
		for child in current_process.children {
			processes[1].children << child
		}
	}

	mut old_pagemap := current_process.pagemap

	kernel_pagemap.switch_to()
	current_thread.process = kernel_process

	mmap.delete_pagemap(old_pagemap) or {}

	katomic.store(current_process.status, status | 0x200)
	event.trigger(current_process.event)

	sched.dequeue_and_die()
}

pub fn syscall_fork(gpr_state &cpulocal.GPRState) (u64, u64) {
	old_thread := proc.current_thread()
	mut old_process := old_thread.process

	mut new_process := sched.new_process(old_process, voidptr(0)) or {
		panic('fork failure')
	}

	stack_size := u64(65536)

	mut new_thread := &proc.Thread{
		gpr_state: gpr_state
		process: new_process
		timeslice: old_thread.timeslice
		gs_base: old_thread.gs_base
		fs_base: old_thread.fs_base
		kernel_stack: u64(memory.pmm_alloc(stack_size / page_size)) + stack_size + higher_half
		pf_stack: u64(memory.pmm_alloc(stack_size / page_size)) + stack_size + higher_half
		running_on: u64(-1)
		cr3: u64(new_process.pagemap.top_level)
	}

	new_thread.gpr_state.rax = u64(0)
	new_thread.gpr_state.r8 = u64(0)

	old_process.children << new_process
	new_process.threads << new_thread

	sched.enqueue_thread(new_thread)

	return u64(new_process.pid), u64(0)
}

pub fn start_program(execve bool, path string, argv []string, envp []string,
					 stdin string, stdout string, stderr string) ?&proc.Process {
	prog_node := fs.get_node(vfs_root, path) or {
		return error('Program not found')
	}
	prog := prog_node.resource

	mut new_pagemap := memory.new_pagemap()

	auxval, ld_path := elf.load(new_pagemap, prog, 0) or {
		return error('elf load failed')
	}

	mut entry_point := voidptr(0)

	if ld_path == '' {
		entry_point = voidptr(auxval.at_entry)
	} else {
		ld_node := fs.get_node(vfs_root, ld_path) or {
			return error('Program interpreter not found')
		}
		ld := ld_node.resource

		ld_auxval, _ := elf.load(new_pagemap, ld, 0x40000000) or {
			return error('elf load (ld) failed')
		}

		entry_point = voidptr(ld_auxval.at_entry)
	}

	if execve == false {
		mut new_process := sched.new_process(voidptr(0), new_pagemap) or {
			return none
		}

		stdin_node := fs.get_node(vfs_root, stdin) or {
			return error('stdin not found')
		}
		stdin_handle := &file.Handle{resource: stdin_node.resource
									 node: stdin_node
									 refcount: 1}
		stdin_fd := &file.FD{handle: stdin_handle}
		new_process.fds[0] = voidptr(stdin_fd)

		stdout_node := fs.get_node(vfs_root, stdout) or {
			return error('stdout not found')
		}
		stdout_handle := &file.Handle{resource: stdout_node.resource
									  node: stdout_node
									  refcount: 1}
		stdout_fd := &file.FD{handle: stdout_handle}
		new_process.fds[1] = voidptr(stdout_fd)

		stderr_node := fs.get_node(vfs_root, stderr) or {
			return error('stderr not found')
		}
		stderr_handle := &file.Handle{resource: stderr_node.resource
									  node: stderr_node
									  refcount: 1}
		stderr_fd := &file.FD{handle: stderr_handle}
		new_process.fds[2] = voidptr(stderr_fd)

		sched.new_user_thread(new_process, true,
							  entry_point, voidptr(0),
							  argv, envp, auxval, true) or {
			return none
		}

		return new_process
	} else {
		mut thread := proc.current_thread()
		mut process := thread.process

		mut old_pagemap := process.pagemap

		process.pagemap = new_pagemap

		kernel_pagemap.switch_to()
		thread.process = kernel_process

		mmap.delete_pagemap(old_pagemap) or {
			return none
		}

		process.thread_stack_top = u64(0x70000000000)
		process.mmap_anon_non_fixed_base = u64(0x80000000000)

		old_threads := process.threads
		process.threads = []&proc.Thread{}

		unsafe { old_threads.free() }

		sched.new_user_thread(process, true, entry_point, voidptr(0),
							  argv, envp, auxval, true) or {
			return none
		}

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

		sched.dequeue_and_yield()

		return none
	}
}

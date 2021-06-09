module userland

import fs
import memory
import elf
import sched
import file
import proc

pub fn start_program(execve bool, path string, argv []string, envp []string,
					 stdin string, stdout string, stderr string) ?&proc.Process {
	prog := fs.get_node(voidptr(0), path).resource
	if prog == 0 {
		return error('File not found')
	}

	mut new_pagemap := memory.new_pagemap()

	auxval, ld_path := elf.load(new_pagemap, prog, 0) or {
		return error('elf load failed')
	}

	mut entry_point := voidptr(0)

	if ld_path == '' {
		entry_point = voidptr(auxval.at_entry)
	} else {
		ld := fs.get_node(voidptr(0), ld_path).resource

		ld_auxval, _ := elf.load(new_pagemap, ld, 0x40000000) or {
			return error('elf load (ld) failed')
		}

		entry_point = voidptr(ld_auxval.at_entry)
	}

	mut new_process := &proc.Process(0)

	if execve == false {
		new_process = sched.new_process(voidptr(0), new_pagemap)

		stdin_node := fs.get_node(voidptr(0), stdin)
		stdin_handle := &file.Handle{resource: stdin_node.resource
									 node: stdin_node}
		stdin_fd := &file.FD{handle: stdin_handle}
		new_process.fds << stdin_fd

		stdout_node := fs.get_node(voidptr(0), stdout)
		stdout_handle := &file.Handle{resource: stdout_node.resource
									  node: stdout_node}
		stdout_fd := &file.FD{handle: stdout_handle}
		new_process.fds << stdout_fd

		stderr_node := fs.get_node(voidptr(0), stderr)
		stderr_handle := &file.Handle{resource: stderr_node.resource
									  node: stderr_node}
		stderr_fd := &file.FD{handle: stderr_handle}
		new_process.fds << stderr_fd

		sched.new_user_thread(new_process, true,
							  entry_point, voidptr(0),
							  argv, envp, auxval, true)
	} else {
		panic('TODO: execve')
	}

	return new_process
}

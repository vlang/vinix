module userland

import fs
import memory
import elf
import sched
import file
import proc

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

	mut new_process := &proc.Process(0)

	if execve == false {
		new_process = sched.new_process(voidptr(0), new_pagemap)

		stdin_node := fs.get_node(vfs_root, stdin) or {
			return error('stdin not found')
		}
		stdin_handle := &file.Handle{resource: stdin_node.resource
									 node: stdin_node}
		stdin_fd := &file.FD{handle: stdin_handle}
		new_process.fds << stdin_fd

		stdout_node := fs.get_node(vfs_root, stdout) or {
			return error('stdout not found')
		}
		stdout_handle := &file.Handle{resource: stdout_node.resource
									  node: stdout_node}
		stdout_fd := &file.FD{handle: stdout_handle}
		new_process.fds << stdout_fd

		stderr_node := fs.get_node(vfs_root, stderr) or {
			return error('stderr not found')
		}
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

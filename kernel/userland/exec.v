// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module userland

// What exec does the same on both architectures.

import errno
import proc

// Frees what an exec was handed, once it has failed or is about to leave for
// good. `path` can be one of the arguments too: a script's interpreter and the
// x86 translator are put into argv as well.
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

// An image the loader turned down is not an executable, as Linux answers:
// ENOEXEC. The loader's errors carry no errno, and exec reported whatever
// an earlier call had left -- ENOENT once, EPERM after -- for a program it
// could not read. Only a segment that could not be mapped keeps the errno
// the mapping set.
fn exec_format_error(err IError) ?&proc.Process {
	if !err.msg().starts_with('elf: unable to map') {
		errno.set(errno.enoexec)
	}
	return none
}

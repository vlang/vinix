// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module userland

// What exec does the same on both architectures.

import errno
import kbudget
import proc
import resource

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

fn reserve_exec_scratch() ? {
	mut t := proc.current_thread()
	t.exec_scratch = proc.reserve_kernel(.scratch, 16384)?
}

fn release_exec_scratch() {
	mut t := proc.current_thread()
	kbudget.release(t.exec_scratch)
	t.exec_scratch = kbudget.Charge{}
}

fn grow_exec_scratch(bytes u64) bool {
	mut t := proc.current_thread()
	return proc.grow_kernel(mut t.exec_scratch, bytes)
}

fn shrink_exec_scratch(bytes u64) {
	mut t := proc.current_thread()
	kbudget.shrink(mut t.exec_scratch, bytes)
}

// A bounded script header, including EOF without a newline. Every returned
// string owns its storage; no builder can grow past the kernel's exec budget.
pub fn parse_shebang(mut res resource.Resource) ?(string, string) {
	buf := unsafe { &u8(C.vinix_stack_alloc(256)) }
	count := res.read(unsafe { nil }, buf, 0, 256)?
	if count <= 2 {
		errno.set(errno.enoexec)
		return none
	}
	mut end := int(count)
	mut newline := false
	for i in 2 .. int(count) {
		if unsafe { buf[i] } == `\n` {
			end = i
			newline = true
			break
		}
	}
	if count == 256 && !newline {
		errno.set(errno.enoexec)
		return none
	}
	mut start := 2
	for start < end && (unsafe { buf[start] } == ` ` || unsafe { buf[start] } == `\t`) { start++ }
	mut stop := start
	for stop < end && unsafe { buf[stop] } != ` ` && unsafe { buf[stop] } != `\t` { stop++ }
	if stop == start {
		errno.set(errno.enoexec)
		return none
	}
	path := unsafe { tos(&buf[start], stop - start) }.clone()
	for stop < end && (unsafe { buf[stop] } == ` ` || unsafe { buf[stop] } == `\t`) { stop++ }
	for end > stop && (unsafe { buf[end - 1] } == ` ` || unsafe { buf[end - 1] } == `\t`) { end-- }
	arg := unsafe { tos(&buf[stop], end - stop) }.clone()
	return path, arg
}

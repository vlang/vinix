// SPDX-License-Identifier: GPL-2.0-or-later
module userland

import file
import lib
import proc
import resource

// Only the first script in a directory-relative exec uses this name. Nested
// interpreters retain their own pathname and the same pinned directory FD.
fn exec_relative_script_name(path string) string {
	thr := proc.current_thread()
	mut name := unsafe { &lib.Text(C.vinix_stack_alloc(sizeof(lib.Text))) }
	unsafe { *name = lib.new_text(32 + path.len) }
	name.add('/proc/self/fd/')
	name.add_decimal(i64(thr.exec_descriptor_number))
	name.add('/')
	name.add(path)
	return lib.finish_text(*name)
}

// A script interpreter must reopen the synthesized /proc/self/fd/N[/path].
// The syscall already pins this FD; checking its flag adds no reference.
fn exec_descriptor_cloexec() bool {
	thr := proc.current_thread()
	if thr.exec_descriptor == unsafe { nil } { return false }
	fd := unsafe { &file.FD(thr.exec_descriptor) }
	return fd.flags & resource.o_cloexec != 0
}

// execveat keeps its image/directory FD through header, interpreter and image reads.
// Its successful loader never returns, so commit explicitly releases it;
// ordinary errors reach the syscall's defer. Recursive loaders share one slot.
fn release_exec_descriptor(mut thr proc.Thread) {
	if thr.exec_descriptor == unsafe { nil } { return }
	mut fd := unsafe { &file.FD(thr.exec_descriptor) }
	thr.exec_descriptor = unsafe { nil }
	thr.exec_descriptor_number = 0
	fd.unref()
}

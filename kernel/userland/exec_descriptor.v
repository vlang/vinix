// SPDX-License-Identifier: GPL-2.0-or-later
module userland

import file
import proc
import resource

// A script interpreter must reopen the synthesized /proc/self/fd/N name.
// The syscall already pins this FD; checking its flag adds no reference.
fn exec_descriptor_cloexec() bool {
	thr := proc.current_thread()
	if thr.exec_descriptor == unsafe { nil } { return false }
	fd := unsafe { &file.FD(thr.exec_descriptor) }
	return fd.flags & resource.o_cloexec != 0
}

// execveat keeps its descriptor through header, interpreter and image reads.
// Its successful loader never returns, so commit explicitly releases it;
// ordinary errors reach the syscall's defer. Recursive loaders share one slot.
fn release_exec_descriptor(mut thr proc.Thread) {
	if thr.exec_descriptor == unsafe { nil } { return }
	mut fd := unsafe { &file.FD(thr.exec_descriptor) }
	thr.exec_descriptor = unsafe { nil }
	fd.unref()
}

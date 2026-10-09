// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module proc

import errno

// Publish a fully numbered thread in its process. Process inspection takes
// the table lock before the thread-list lock, so attachment must use that
// same order. Taking the list lock first and then allocating or binding a
// tid deadlocked fork/exec against a concurrent /proc status reader.
pub fn attach_thread(mut process Process, mut t Thread) ?int {
	pid_lock.acquire()
	defer { pid_lock.release() }
	process.threads_lock.acquire()
	defer { process.threads_lock.release() }

	if process.exiting { errno.set(errno.esrch); return none }
	if process.threads.len == 0 && process.pid != 0 {
		t.tid = process.pid
		if !bind_tid_locked(t.tid, t) { errno.set(errno.eagain); return none }
		number_thread_locked(mut t, true)
	} else {
		t.tid = allocate_tid_locked(t) or { errno.set(errno.eagain); return none }
		number_thread_locked(mut t, false)
		// rt_sigaction updates every thread under this lock. Refresh the
		// caller's earlier copy before publishing the new thread so a signal
		// handler installed by another CPU cannot be lost during creation.
		t.sigactions = process.threads[0].sigactions
	}

	// Readers hold threads_lock and never retain slices of this owned buffer.
	// Free its previous capacity when the thread list grows.
	process.threads.flags |= .noslices
	process.threads << t
	process.constructing = false
	return t.tid
}

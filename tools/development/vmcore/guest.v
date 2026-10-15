// SPDX-License-Identifier: GPL-2.0-or-later
module vmcore

import os
import os.filelock
import qmpclient
import time

fn guest_lease(state string) !filelock.FileLock {
	path := state + '/agent.lock'
	// A persistent record-lock inode also works for states imported before
	// guest queries existed. Append creates it without replacing an inode
	// another process might already have locked.
	if !os.exists(path) && !os.is_link(path) {
		mut file := os.open_file(path, 'a', 0o600)!
		file.close()
	}
	st := os.lstat(path)!
	if st.get_filetype() != .regular || st.uid != u32(os.getuid()) || st.mode & 0o077 != 0 {
		return error('guest agent lock must be a private regular file owned by this user')
	}
	mut guard := filelock.new_file(path, mode: .exclusive)
	if !guard.try_acquire() { return error('VM startup or another guest agent query holds its lock') }
	return guard
}

pub fn guest(action string, path string) !string {
	command := match action {
		'guest-ping' { 'guest-ping' }
		'guest-info' { 'guest-info' }
		'guest-osinfo' { 'guest-get-osinfo' }
		'guest-network' { 'guest-network-get-interfaces' }
		else { return error('unknown guest query: ${action}') }
	}
	state, config := load(path)!
	if !config.guest_agent { return error('guest agent transport is disabled in this VM configuration') }
	mut guard := guest_lease(state)!
	defer { guard.release() }
	socket := state + '/agent.sock'
	st := os.lstat(socket)!
	if st.get_filetype() != .socket || st.uid != u32(os.getuid()) {
		return error('guest agent endpoint must be a socket owned by this user')
	}
	return qmpclient.guest_query(socket, command, time.sys_mono_now() + u64(5 * time.second), unsafe { nil })
}

// SPDX-License-Identifier: GPL-2.0-or-later
module wineadapter

import time

// Keep the fallible scalar result out of the polling frame: this compiler
// otherwise promotes the later ABI records and owned values to heap boxes.
fn (mut child ServerChild) check_startup_exec() ! {
	child.exec_ready()!
}

fn (mut child ServerChild) await_connection_linux(server &ServerDirectory, guard &LaunchGuard, data string, timeout_ms int) !ServerConnection {
	if timeout_ms < 1 || timeout_ms > 5000 { return error('Wine readiness wait must be between 1 and 5000 milliseconds') }
	deadline := time.sys_mono_now() + i64(timeout_ms) * time.millisecond
	for {
		if time.sys_mono_now() >= deadline { return error('Wine server readiness timed out') }
		child.check_startup_exec()!
		live_server_child(child.pid)!
		server.recheck(guard, data)!
		mut owner := C.vinix_wine_owner_lock{l_type: i16(C.F_WRLCK), l_whence: i16(C.SEEK_SET), l_len: 1}
		if C.vinix_wine_peer_fcntl(server.lock_fd, C.F_GETLK, unsafe { &owner }) != 0 {
			return error('cannot inspect Wine startup lock ownership')
		}
		// A foreign lock is an immediate refusal even before a socket appears.
		if owner.l_type != C.F_UNLCK { verify_server_owner(server.lock_fd, child.pid)! }
		mut info := C.stat{}
		if C.vinix_wine_directory_fstatat(server.directory, c'socket', unsafe { &info }, C.AT_SYMLINK_NOFOLLOW) == 0 {
			// Re-read ownership here: the child can legitimately acquire its lock
			// and bind between the initial F_GETLK and fstatat observations.
			verify_server_owner(server.lock_fd, child.pid)!
			if child.exec_complete {
				mut endpoint := server.capture_endpoint(guard, data)!
				defer { endpoint.close() }
				now := time.sys_mono_now()
				if now >= deadline { return error('Wine server readiness timed out') }
				remaining := int((deadline - now + time.millisecond - 1) / time.millisecond)
				mut connection := endpoint.connect(server, guard, data, child.pid, remaining)!
				if time.sys_mono_now() >= deadline {
					connection.close()
					return error('Wine server readiness timed out')
				}
				return connection
			}
		} else if C.errno != C.ENOENT { return error('cannot inspect Wine startup socket entry') }
		time.sleep(time.millisecond)
	}
	return error('unreachable Wine server readiness wait')
}

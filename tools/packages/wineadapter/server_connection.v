// SPDX-License-Identifier: GPL-2.0-or-later
module wineadapter

// One owner; do not copy or concurrently close. The caller still exclusively
// owns the direct unreaped server child and preserves default waitable SIGCHLD.
// This value owns a blocking connected CLOEXEC socket and endpoint metadata,
// not the child or its wait status. Close does not signal the server.
pub struct ServerConnection {
mut:
	fd i32 = -1
	child i32
	endpoint ServerEndpoint = ServerEndpoint{}
}

pub fn (mut connection ServerConnection) close() {
	if connection.fd >= 0 { C.close(connection.fd) }
	connection.endpoint.close()
	connection = ServerConnection{}
}

// Borrowed while this value lives. Do not close/reuse it independently. It
// stays CLOEXEC; a future child handoff must explicitly arrange inheritance.
pub fn (connection &ServerConnection) descriptor() i32 { return connection.fd }

// Requires authorized procfs descriptor magic-link access; there is no pathname
// fallback or process-wide cwd change. timeout_ms bounds socket retry/poll wait
// (1..5000 ms), not filesystem operations. No Wine protocol bytes are consumed.
pub fn (endpoint &ServerEndpoint) connect(server &ServerDirectory, guard &LaunchGuard, data string, child i32, timeout_ms int) !ServerConnection {
	$if linux {
		$if amd64 || arm64 { return endpoint.connect_linux(server, guard, data, child, timeout_ms) }
		$else { return error('Wine server connection requires Linux AMD64 or AArch64') }
	} $else { return error('Wine server connection requires Linux descriptor links and peer identities') }
}

pub fn (connection &ServerConnection) recheck(server &ServerDirectory, guard &LaunchGuard, data string) ! {
	if connection.fd < 3 { return error('Wine server connection is closed') }
	connection.endpoint.recheck(server, guard, data)!
	verify_server_identity(connection.fd, server.lock_fd, connection.child)!
	connection.endpoint.recheck(server, guard, data)!
}

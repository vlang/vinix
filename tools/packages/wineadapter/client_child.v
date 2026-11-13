// SPDX-License-Identifier: GPL-2.0-or-later
module wineadapter

// One owner on the spawning thread until exec_ready restores/checks its mask.
// Preserve default waitable SIGCHLD, exclude other waiters and asynchronous
// cancellation, and collect or explicitly terminate the direct client. This
// is not a descendant barrier or a generation lease holder.
pub struct ClientChild {
mut:
	process ServerChild = ServerChild{}
}

pub fn (client &ClientChild) process_id() i32 { return client.process.process_id() }
// Report EOF alone does not prove exec/liveness: a pre-exec signal can close it.
pub fn (mut client ClientChild) exec_ready() !bool { return client.process.exec_ready() }
pub fn (mut client ClientChild) collect() !ServerChildExit { return client.process.collect() }
pub fn (mut client ClientChild) terminate() !int { return client.process.terminate() }

// Borrow command/environment for this call. Admit their executable, loader,
// arguments and other environment values separately. Supply NAME=VALUE entries;
// inherited WINESERVERSOCKET entries are all replaced with the owned socket.
// Child starts in the captured prefix, inherits stdio and only this protocol
// FD above stdio (plus the CLOEXEC exec report). Only the child's socket loses
// CLOEXEC. Parent environment and cwd do not change; no protocol bytes are used.
//
// Errors before fork leave the connection intact. Successful fork consumes it,
// even if child setup/exec later fails: the returned client retains PID/status
// ownership. Call exec_ready immediately and handle failure by collection or
// termination. Keep exclusive ownership of the unreaped server child too.
pub fn (mut connection ServerConnection) start_client(server &ServerDirectory, guard &LaunchGuard, data string, command ServerCommand, environment []string) !ClientChild {
	$if linux {
		$if amd64 || arm64 { return connection.start_client_linux(server, guard, data, command, environment, guard.directory) }
		$else { return error('Wine client handoff requires Linux AMD64 or AArch64') }
	} $else { return error('Wine client handoff requires Linux descriptor and child identities') }
}

// Like start_client, but starts in the directory referenced by working_directory
// instead of the prefix. Borrow a caller-admitted directory descriptor for this
// call only; keep it open without concurrent replacement until return. The
// implementation captures its own CLOEXEC reference before fork and never
// resolves the directory by pathname. This admits descriptor type, not package
// identity, ownership or access policy; those remain the launcher's job.
// No working-directory descriptor survives client exec. Parent cwd is unchanged.
pub fn (mut connection ServerConnection) start_client_in(server &ServerDirectory, guard &LaunchGuard, data string, command ServerCommand, environment []string, working_directory i32) !ClientChild {
	$if linux {
		$if amd64 || arm64 { return connection.start_client_linux(server, guard, data, command, environment, working_directory) }
		$else { return error('Wine client handoff requires Linux AMD64 or AArch64') }
	} $else { return error('Wine client handoff requires Linux descriptor and child identities') }
}

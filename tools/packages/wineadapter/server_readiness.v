// SPDX-License-Identifier: GPL-2.0-or-later
module wineadapter

// Wait for exec acknowledgement and an owned lock/socket, then retain an
// authenticated connection. The caller continues to own this direct unreaped
// child on success, timeout and every error; collect/terminate it explicitly.
// Use on the spawning thread until caller signal-mask restoration is checked.
// timeout_ms (1..5000) bounds polling/connect waits, not filesystem latency.
// This admits neither the executable nor environment and performs no protocol
// reads/writes. It never attaches to or signals a foreign server.
pub fn (mut child ServerChild) await_connection(server &ServerDirectory, guard &LaunchGuard, data string, timeout_ms int) !ServerConnection {
	$if linux {
		$if amd64 || arm64 { return child.await_connection_linux(server, guard, data, timeout_ms) }
		$else { return error('Wine server readiness requires Linux AMD64 or AArch64') }
	} $else { return error('Wine server readiness requires Linux child and peer identities') }
}

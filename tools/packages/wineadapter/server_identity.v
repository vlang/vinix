// SPDX-License-Identifier: GPL-2.0-or-later
module wineadapter

// Verify borrowed descriptors without reading protocol bytes, changing locks,
// signalling processes or collecting child status. The caller must own child
// as a direct, unreaped child throughout, exclude other waiters, and preserve
// default waitable SIGCHLD and these descriptors throughout the call.
// This check does not capture a server directory or establish binary identity.
pub fn verify_server_identity(socket_fd i32, lock_fd i32, child i32) ! {
	$if linux {
		$if amd64 || arm64 { return verify_server_linux(socket_fd, lock_fd, child) }
		$else { return error('Wine server identity requires Linux AMD64 or AArch64') }
	} $else { return error('Wine server identity requires Linux peer and child identities') }
}

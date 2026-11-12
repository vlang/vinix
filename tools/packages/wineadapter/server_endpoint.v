// SPDX-License-Identifier: GPL-2.0-or-later
module wineadapter

// One owner; do not copy or concurrently close. These are metadata references,
// not a transport connection. Keep the ServerDirectory and LaunchGuard valid
// for capture/recheck calls. Capturing a socket does not prove a live or owned
// listener; startup must separately authenticate its child, lock and peer.
pub struct ServerEndpoint {
mut:
	node i32 = -1
	directory i32 = -1
}

pub fn (mut endpoint ServerEndpoint) close() {
	if endpoint.node >= 0 { C.close(endpoint.node) }
	if endpoint.directory >= 0 { C.close(endpoint.directory) }
	endpoint = ServerEndpoint{}
}

pub fn (server &ServerDirectory) capture_endpoint(guard &LaunchGuard, data string) !ServerEndpoint {
	$if linux { return server.capture_endpoint_linux(guard, data) }
	$else { return error('Wine endpoint capture requires Linux metadata-only descriptors') }
}

pub fn (endpoint &ServerEndpoint) recheck(server &ServerDirectory, guard &LaunchGuard, data string) ! {
	$if linux { return endpoint.recheck_linux(server, guard, data) }
	$else { return error('Wine endpoint recheck requires Linux metadata-only descriptors') }
}

// SPDX-License-Identifier: GPL-2.0-or-later
module sessioncore

import authclient
import authproto

// Both privileged login paths authenticate the service's kernel peer before
// any credential leaves this process. ask_root wipes the borrowed password on
// every exit, including connection and identity refusal.
pub fn verify_login(socket_path string, name string, password []u8) !authproto.Frame {
	identity := name.bytes()
	defer { unsafe { identity.free() } }
	return authclient.ask_root(socket_path, authproto.op_verify, identity, password)
}

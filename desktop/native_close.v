// SPDX-License-Identifier: GPL-2.0-or-later
// A normal close is a request. Destruction runs only after it is accepted.
module main

interface CloseGuardApp {
mut:
	prepare_close() bool
}

// Keep interface dispatch explicit: a smart-cast receiver creates temporary
// wrappers under the production compiler and -manualfree cannot release them.
fn native_app_prepare_close(mut app NativeApp) bool {
	if mut app is CloseGuardApp {
		mut guard := CloseGuardApp(app)
		return guard.prepare_close()
	}
	return true
}

fn native_close_reply_allows(reply AppReply) bool {
	return reply.ok && reply.payload.len == 1 && reply.payload[0] == 1
}

fn (mut a RemoteApp) prepare_close() bool {
	// Installed standalone clients can predate the appended command and
	// already implement their own close behavior. Dead clients have no draft
	// left to protect and their windows can still be removed normally.
	if a.standalone || a.closed || a.peer_features & app_feature_close_guard == 0 { return true }
	a.tree_stale = true
	a.poll_sampled = false
	reply := a.transact(.prepare_close, 0, 0, '') or { return a.closed }
	defer { if reply.payload.cap > 0 { unsafe { reply.payload.free() } } }
	// A denial, error reply or malformed boolean never closes this live client.
	return native_close_reply_allows(reply)
}

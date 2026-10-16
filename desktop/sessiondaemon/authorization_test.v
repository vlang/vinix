// SPDX-License-Identifier: GPL-2.0-or-later
module sessiondaemon

import desktop.sessionipc

fn test_broker_selector_filters_run_before_argument_decoding_or_side_effects() {
	mut daemon := &SessionDaemon{ compositor: int(C.getpid()) + 1 }
	defer { unsafe { free(daemon) } }
	peer := sessionipc.SessionCredentials{ pid: C.getpid(), uid: C.getuid(), gid: C.getgid() }
	// These have the right shape but invalid encoded arguments. Domain denial
	// must happen before unfield(), file access, queuing or a settings handler.
	for request in ['settings.set\tzz', 'policy.set\tzz', 'service.import\tzz\tzz\tzz',
		'exchange.grant\tzz', 'dialog.result\tzz\tzz\tzz'] {
		mut denied := false
		daemon.handle(peer, request) or {
			assert err.msg().starts_with('compositor/')
			denied = true
		}
		assert denied
		assert daemon.queue_count == 0 && !daemon.changed && !daemon.stop
	}
	assert daemon.handle(peer, 'ping')! == 'ok'
	daemon.policy.clipboard_apps = false
	for request in ['clipboard.offer\t0\t0\tzz', 'clipboard.read\tzz', 'clipboard.request',
		'exchange.take'] {
		mut denied := false
		daemon.handle(peer, request) or {
			assert err.msg().starts_with('application/')
			denied = true
		}
		assert denied && daemon.queue_count == 0
	}
	for request in ['sbp/selectors/register\tzz', 'clipboard.*\tzz', 'ping\tzz'] {
		if _ := daemon.handle(peer, request) {
			assert false, 'unknown or malformed operation reached a handler'
		}
	}
}

// SPDX-License-Identifier: GPL-2.0-or-later
module sessiondaemon

import desktop.sessionipc
import desktop.sessioncore

fn test_notification_cancellation_uses_kernel_peer_identity() {
	mut daemon := &SessionDaemon{}
	defer { unsafe { free(daemon) } }
	peer := sessionipc.SessionCredentials{pid: C.getpid(), uid: C.getuid(), gid: C.getgid()}
	other := sessionipc.SessionCredentials{pid: peer.pid + 1, uid: peer.uid, gid: peer.gid}
	// Encoded key/title/body/urgency/progress/action, using the real wire parser.
	post := 'notify\t616e64726f69643a3432\t54657374\t426f6479\t31\t2d31\t'
	assert daemon.handle(peer, post, false)! == 'ok'
	assert daemon.handle(other, post, false)! == 'ok'
	assert daemon.handle(peer, 'notify.cancel\t616e64726f69643a3432', false)! == 'ok'
	assert daemon.notifications.items[0].dismissed
	assert !daemon.notifications.items[1].dismissed
	assert daemon.handle(peer, 'notify.cancel\t616e64726f69643a3432', false)! == 'ok'
	assert !daemon.notifications.items[1].dismissed
}

fn test_every_authorized_operation_has_one_direct_handler() {
	assert session_routes.len == int(sessioncore.SessionOperation.shutdown) + 1
	for i, route in session_routes {
		assert int(route.operation) == i
		assert route.raw_payload == (route.operation == .clipboard_offer)
	}
	mut daemon := &SessionDaemon{}
	defer { unsafe { free(daemon) } }
	mut request := &SessionRequest{}
	defer { unsafe { free(request) } }
	if _ := session_routes[0].handler(mut daemon, mut request) {
		assert false, 'the invalid operation must never dispatch successfully'
	}
}

fn test_broker_selector_filters_run_before_argument_decoding_or_side_effects() {
	mut daemon := &SessionDaemon{}
	defer { unsafe { free(daemon) } }
	peer := sessionipc.SessionCredentials{ pid: C.getpid(), uid: C.getuid(), gid: C.getgid() }
	// These have the right shape but invalid encoded arguments. Domain denial
	// must happen before unfield(), file access, queuing or a settings handler.
	for request in ['settings.set\tzz', 'policy.set\tzz', 'service.import\tzz\tzz\tzz',
		'exchange.grant\tzz', 'dialog.result\tzz\tzz\tzz'] {
		mut denied := false
		daemon.handle(peer, request, false) or {
			assert err.msg().starts_with('compositor/')
			denied = true
		}
		assert denied
		assert daemon.queue_count == 0 && !daemon.changed && !daemon.stop
	}
	assert daemon.handle(peer, 'ping', false)! == 'ok'
	daemon.policy.clipboard_apps = false
	for request in ['clipboard.offer\t0\t0\tzz', 'clipboard.read\tzz', 'clipboard.request',
		'exchange.take'] {
		mut denied := false
		daemon.handle(peer, request, false) or {
			assert err.msg().starts_with('application/')
			denied = true
		}
		assert denied && daemon.queue_count == 0
	}
	for request in ['sbp/selectors/register\tzz', 'clipboard.*\tzz', 'ping\tzz'] {
		if _ := daemon.handle(peer, request, false) {
			assert false, 'unknown or malformed operation reached a handler'
		}
	}
}

fn test_pid_equality_never_grants_the_compositor_domain() {
	mut daemon := &SessionDaemon{}
	defer { unsafe { free(daemon) } }
	peer := sessionipc.SessionCredentials{ pid: C.getpid(), uid: C.getuid(), gid: C.getgid() }
	// Identical credentials on the public transport, including a reused PID,
	// must not gain authority before or after a trusted attach.
	for _ in 0 .. 2 {
		for request in ['attach', 'history', 'take', 'shutdown', 'policy.set\tzz'] {
			if _ := daemon.handle(peer, request, false) {
				assert false, 'public connection gained compositor authority'
			}
		}
		assert daemon.handle(peer, 'attach', true)! == 'ok'
		assert daemon.handle(peer, 'take', true)! == 'empty'
		assert !daemon.stop
	}
}

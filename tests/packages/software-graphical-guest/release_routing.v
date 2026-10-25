// SPDX-License-Identifier: GPL-2.0-or-later
module main

import desktop.sessionipc
import json2
import os
import time

fn release_routing_enabled() bool {
	return os.exists('/etc/software-graphical-release-routing')
}

fn check_release_routing_declaration(document map[string]json2.Any, architecture string) ! {
	if document.len != 4 || document['format']! != json2.Any(f64(2)) ||
		document['architecture']!.str() != architecture ||
		document['packages']!.as_array().map(it.str()) != ['org.vinix.counter'] ||
		document['locked']!.as_array().len != 1 {
		return error('release routing requires exactly the locked non-Neovim Counter set')
	}
	pin := document['locked']!.as_array()[0].as_map()
	if pin.len != 7 || pin['id']!.str() != 'org.vinix.counter' ||
		pin['architecture']!.str() != architecture || pin['version']!.str() != '1.0.0' ||
		pin['repository']!.str() != 'native' || pin['public_key']!.str().len != 64 ||
		pin['minimum_sequence']!.f64() < 1 || pin['metadata_sha256']!.str().len != 64 {
		return error('release routing Counter lock is incomplete')
	}
}

fn release_routing_request() ! {
	require_uninstalled()!
	check_first_run_decision()!
	// Connect as a real ordinary account, without the compositor capability.
	mut child := os.new_process('/usr/sbin/vinix-session')
	defer { child.close() }
	child.set_args(['run', '--isolated', 'alex', '/sbin/init', '--release-routing-client'])
	child.set_redirect_stdio()
	child.run()
	C.close(child.stdio_fd[0])
	child.stdio_fd[0] = -1
	for fd in child.stdio_fd[1..] {
		if C.fcntl(fd, C.F_SETFL, C.O_NONBLOCK) != 0 {
			return error('cannot make routing diagnostics nonblocking')
		}
	}
	deadline := time.sys_mono_now() + 90 * time.second
	mut bytes := []u8{len: 4096}
	mut total := 0
	for {
		alive := child.is_alive()
		for fd in child.stdio_fd[1..] {
			count := C.read(fd, bytes.data, usize(bytes.len))
			if count > 0 {
				total += int(count)
				if total > 64 * 1024 { return error('routing diagnostics exceed bound') }
				print(bytes[..int(count)].bytestr())
			} else if count < 0 && C.errno !in [C.EAGAIN, C.EINTR] {
				return error('cannot read routing diagnostics')
			}
		}
		if !alive { break }
		if time.sys_mono_now() >= deadline {
			stop_child(mut child, 'release routing client')!
			return error('ordinary release routing client timed out')
		}
		time.sleep(20 * time.millisecond)
	}
	child.wait()
	if child.code != 0 { return error('ordinary release routing client failed status=' + child.code.str()) }
	require_uninstalled()!
}

fn enqueue_release_route(arguments []string) ! {
	reply := sessionipc.session_call('action', arguments)!
	if reply != 'ok' { return error('release action was not queued by the account broker') }
}

fn release_route_barrier(key string) ! {
	if !sessionipc.dialog_open(key, 1, 'Release routing queue barrier', '/home/alex', '', '') {
		return error('cannot queue compositor dialog barrier')
	}
	deadline := time.sys_mono_now() + 30 * time.second
	mut pending := false
	for time.sys_mono_now() < deadline {
		reply := sessionipc.session_call('dialog.take', [key])!
		if reply == 'cancelled' && pending { return }
		if reply != 'pending' { return error('dialog barrier did not complete with exact cancellation') }
		pending = true
		time.sleep(100 * time.millisecond)
	}
	return error('compositor dialog barrier was not cancelled')
}

fn release_routing_client() ! {
	if !release_routing_enabled() || os.geteuid() != 1000 || os.getuid() != 1000 ||
		os.getenv('HOME') != '/home/alex' || os.getenv('XDG_RUNTIME_DIR') != '/run/user/1000' ||
		os.getenv('VINIX_SESSION_FD') != '' {
		return error('release route client did not become the ordinary isolated account')
	}
	println('SOFTWARE RELEASE ROUTING ordinary client uid=1000 home=/home/alex PASS')
	for control in ['extra-token', 'action'] {
		enqueue_release_route(if control == 'extra-token' {
			['software.release-review', 'org.vinix.counter']
		} else { ['software.release-review.invalid'] })!
		println('SOFTWARE RELEASE ROUTING malformed ' + control + ' enqueued PASS')
		// FIFO and the compositor-only dialog.result completion prove the prior
		// action was consumed. ACK alone proves queueing, never refusal.
		release_route_barrier(if control == 'extra-token' { 'route-extra' } else { 'route-action' })!
		println('SOFTWARE RELEASE ROUTING malformed ' + control + ' drained PASS')
		time.sleep(10 * time.second)
	}
	enqueue_release_route(['software.release-review'])!
	println('SOFTWARE RELEASE ROUTING exact software.release-review acknowledged PASS')
}

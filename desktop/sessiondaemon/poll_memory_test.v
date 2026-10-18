// SPDX-License-Identifier: GPL-2.0-or-later
module sessiondaemon

import desktop.sessionipc

#include "@VMODROOT/tools/tests/heap_tracker.h"

fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64
fn C.socketpair(i32, i32, i32, &i32) i32
fn C.dup(i32) i32
fn C.dup2(i32, i32) i32

fn broker_poll_kept(_ string) u64 { return C.vinix_heap_end() }

fn test_broker_denied_socket_requests_and_logging_keep_no_allocations() {
	mut daemon := &SessionDaemon{}
	defer { unsafe { free(daemon) } }
	daemon.policy.clipboard_apps = false
	// Suppress only the flood's diagnostics; the production logger still runs.
	saved_stderr := C.dup(2)
	sink := C.open(c'/dev/null', C.O_WRONLY | C.O_CLOEXEC, 0)
	assert saved_stderr >= 0 && sink >= 0
	assert C.dup2(i32(sink), 2) >= 0
	defer {
		C.dup2(saved_stderr, 2)
		C.close(saved_stderr)
		C.close(sink)
	}
	C.vinix_heap_begin()
	for _ in 0 .. 200 {
		for request in ['shutdown', 'settings.set\tzz', 'clipboard.read\tzz',
			'sbp/selectors/register\tzz', 'ping\tzz', 'action\tzz']! {
			mut pair := [i32(-1), -1]!
			assert C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, unsafe { &pair[0] }) == 0
			assert sessionipc.desktop_set_cloexec(int(pair[1]), true)
			assert sessionipc.desktop_set_nonblocking(int(pair[1]), true)
			assert sessionipc.session_send_message(int(pair[0]), request)
			daemon.serve_client(int(pair[1]))
			reply := sessionipc.session_receive(int(pair[0])) or { panic(err) }
			assert reply == 'error\tdenied'
			unsafe { reply.free() }
			C.close(pair[0])
		}
	}
	// Unlike registry denials, ordinary handler errors own their text and box.
	for _ in 0 .. 200 {
		session_log_error('vinix-session: request rejected: ', error('owned diagnostic'.clone()))
	}
	kept := C.vinix_heap_end()
	C.dup2(saved_stderr, 2)
	assert kept == 0, 'broker rejection receive/authorize/decode/log/reply retained ${kept} bytes'
}

fn test_private_control_reuses_frames_and_releases_transport_errors() {
	mut daemon := &SessionDaemon{}
	defer { unsafe { free(daemon) } }
	peer := sessionipc.SessionCredentials{ pid: C.getpid(), uid: C.getuid(), gid: C.getgid() }
	mut pair := [i32(-1), -1]!
	assert C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, unsafe { &pair[0] }) == 0
	defer {
		C.close(pair[0])
		C.close(pair[1])
	}
	assert sessionipc.desktop_set_nonblocking(pair[1], true)
	C.vinix_heap_begin()
	for _ in 0 .. 200 {
		for request in ['attach', 'ping', 'history', 'take']! {
			assert sessionipc.session_send_message(pair[0], request)
			assert daemon.serve_request(pair[1], peer, true)
			reply := sessionipc.session_receive(pair[0])!
			assert reply != 'error\tdenied'
			unsafe { reply.free() }
		}
	}
	// A malformed length retires this stream rather than becoming a request.
	header := [4]u8{}
	assert sessionipc.session_send(pair[0], unsafe { tos(&header[0], 4) })
	assert !daemon.serve_request(pair[1], peer, true)
	assert C.vinix_heap_end() == 0
}

fn test_broker_idle_replies_keep_no_request_allocations() {
	mut daemon := &SessionDaemon{}
	peer := sessionipc.SessionCredentials{ pid: i32(C.getpid()), uid: C.getuid() }
	daemon.notifications.post('clock', 'timer', 'Tea', 'Ready', .normal, -1, '', 100) or { panic(err) }
	daemon.notifications.schedule('clock', 'alarm', 'Wake', 200, 0, 0) or { panic(err) }
	daemon.policy.bind('\x1b[110;9u', 'notifications') or { panic(err) }
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		assert !daemon.notifications.tick(100, 0)
		for command in ['ping', 'policy', 'history', 'take']! {
			reply := daemon.handle(peer, command, true) or { panic(err) }
			if reply != 'ok' && reply != 'empty' { unsafe { reply.free() } }
		}
	}
	live := broker_poll_kept('broker idle replies')
	assert live == 0, 'broker idle replies retained ${live} bytes'
}

fn test_broker_queues_copy_request_text_before_request_storage_is_freed() {
	mut daemon := &SessionDaemon{}
	peer := sessionipc.SessionCredentials{ pid: i32(C.getpid()), uid: C.getuid() }
	assert daemon.handle(peer, 'action\t68656c70', false) or { panic(err) } == 'ok'
	assert daemon.handle(peer, 'action\t7368656c6c', false) or { panic(err) } == 'ok'
	assert daemon.queue_count == 2
	assert daemon.queue[0].fields[1].str() == 'help'
	assert daemon.queue[1].fields[1].str() == 'shell'
	assert daemon.handle(peer, 'clipboard.request', false) or { panic(err) } == 'ok'
	assert daemon.queue[2].fields[1].str() == 'clipboard.request'
	assert daemon.handle(peer, 'dialog.open\t66696c65\t30\t4f70656e\t2f746d70\t\t746578742f706c61696e', false) or { panic(err) } == 'ok'
	assert daemon.queue_count == 4
	assert daemon.queue[3].fields[1].str() == 'dialog'
	assert daemon.queue[3].fields[2].str() == 'file'
	assert daemon.queue[0].fields[1].str() == 'help'
	C.vinix_heap_begin()
	for expected in ['68656c70', '7368656c6c', '636c6970626f6172642e72657175657374',
		'746578742f706c61696e']! {
		reply := daemon.handle(peer, 'take', true) or { panic(err) }
		assert reply.ends_with(expected)
		unsafe { reply.free() }
	}
	assert daemon.queue_count == 0
	assert broker_poll_kept('broker queued replies') == 0
}

// SPDX-License-Identifier: GPL-2.0-or-later
module sessiondaemon

import desktop.sessionipc

#include "@VMODROOT/tools/tests/heap_tracker.h"

fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

fn broker_poll_kept(_ string) u64 { return C.vinix_heap_end() }

fn test_broker_idle_replies_keep_no_request_allocations() {
	mut daemon := &SessionDaemon{ compositor: C.getpid() }
	peer := sessionipc.SessionCredentials{ pid: i32(C.getpid()), uid: C.getuid() }
	daemon.notifications.post('clock', 'timer', 'Tea', 'Ready', .normal, -1, '', 100) or { panic(err) }
	daemon.notifications.schedule('clock', 'alarm', 'Wake', 200, 0, 0) or { panic(err) }
	daemon.policy.bind('\x1b[110;9u', 'notifications') or { panic(err) }
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		assert !daemon.notifications.tick(100, 0)
		for command in ['ping', 'policy', 'history', 'take']! {
			reply := daemon.handle(peer, command) or { panic(err) }
			if reply != 'ok' && reply != 'empty' { unsafe { reply.free() } }
		}
	}
	live := broker_poll_kept('broker idle replies')
	assert live == 0, 'broker idle replies retained ${live} bytes'
}

fn test_broker_queues_copy_request_text_before_request_storage_is_freed() {
	mut daemon := &SessionDaemon{ compositor: C.getpid() }
	peer := sessionipc.SessionCredentials{ pid: i32(C.getpid()), uid: C.getuid() }
	assert daemon.handle(peer, 'action\t68656c70') or { panic(err) } == 'ok'
	assert daemon.handle(peer, 'action\t7368656c6c') or { panic(err) } == 'ok'
	assert daemon.queue_count == 2
	assert daemon.queue[0].fields[1].str() == 'help'
	assert daemon.queue[1].fields[1].str() == 'shell'
	assert daemon.handle(peer, 'clipboard.request') or { panic(err) } == 'ok'
	assert daemon.queue[2].fields[1].str() == 'clipboard.request'
	assert daemon.handle(peer, 'dialog.open\t66696c65\t30\t4f70656e\t2f746d70\t\t746578742f706c61696e') or { panic(err) } == 'ok'
	assert daemon.queue_count == 4
	assert daemon.queue[3].fields[1].str() == 'dialog'
	assert daemon.queue[3].fields[2].str() == 'file'
	assert daemon.queue[0].fields[1].str() == 'help'
	C.vinix_heap_begin()
	for expected in ['68656c70', '7368656c6c', '636c6970626f6172642e72657175657374',
		'746578742f706c61696e']! {
		reply := daemon.handle(peer, 'take') or { panic(err) }
		assert reply.ends_with(expected)
		unsafe { reply.free() }
	}
	assert daemon.queue_count == 0
	assert broker_poll_kept('broker queued replies') == 0
}

// SPDX-License-Identifier: GPL-2.0-or-later
module main

import desktop.sessioncore
import os
import time

#include "@VMODROOT/heap_tracker.h"

fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64
fn C.vinix_heap_count() u32
fn C.vinix_heap_size_at(index u32) u64

fn session_poll_kept(label string) u64 {
	live := C.vinix_heap_end()
	if live > 0 {
		mut sizes := map[u64]int{}
		for i in u32(0) .. C.vinix_heap_count() { sizes[C.vinix_heap_size_at(i)]++ }
		eprintln('${label}: ${sizes}')
	}
	return live
}

fn test_notification_and_policy_snapshots_keep_no_poll_allocations() {
	mut notices := sessioncore.Notifications{}
	notices.post('clock', 'timer', 'Tea', 'Ready', .normal, -1, '', 100) or { panic(err) }
	notices.schedule('clock', 'alarm', 'Wake', 200, 0, 0) or { panic(err) }
	notices.schedule('clock', 'second', 'Later', 300, 0, 60) or { panic(err) }
	notices.alarms[0].active = false
	history := notices.encode()
	mut policy := sessioncore.Policy{}
	policy.bind('\x1b[110;9u', 'notifications') or { panic(err) }
	record := policy.encode()
	defer {
		unsafe {
			history.free()
			record.free()
		}
	}
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		decoded := sessioncore.decode_notifications(history) or { panic(err) }
		assert decoded.count == 1 && decoded.alarm_count == 2
		assert !decoded.alarms[0].active && decoded.alarms[1].active
		assert decoded.items[0].title.str() == 'Tea'
		parsed := sessioncore.decode_policy(record) or { panic(err) }
		assert parsed.count == 1
	}
	live := session_poll_kept('session snapshot parsing')
	assert live == 0, 'session snapshots retained ${live} bytes'
}

fn test_session_request_encoding_keeps_no_temporary_allocations() {
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		mut writer := sessioncore.Writer{}
		writer.add('take')
		request := writer.finish()
		unsafe { request.free() }
	}
	live := session_poll_kept('session request encoding')
	assert live == 0, 'session requests retained ${live} bytes'
}

fn test_unchanged_shell_session_saves_keep_no_allocations() {
	mut desktop := Desktop{}
	desktop.session.saving = true
	desktop.session.saved = desktop.session.state
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		desktop.session.last_save_ms = 0
		desktop.save_shell_session(false)
	}
	live := session_poll_kept('unchanged shell session save')
	assert live == 0, 'unchanged shell session saves retained ${live} bytes'
}

fn test_idle_shell_service_ipc_keeps_no_poll_allocations() {
	base := '/tmp/vinix-session-heap-${C.getpid()}'
	os.mkdir(base, mode: 0o700) or { panic(err) }
	previous := os.getenv_opt('VINIX_SESSION_RUNTIME')
	os.setenv('VINIX_SESSION_RUNTIME', base, true)
	defer {
		if value := previous {
			os.setenv('VINIX_SESSION_RUNTIME', value, true)
		} else {
			os.unsetenv('VINIX_SESSION_RUNTIME')
		}
		os.rmdir_all(base) or {}
		unsafe { base.free() }
	}
	mut process := os.new_process(os.real_path('build/session-runtime/vinix-session'))
	process.set_args(['--session-home=' + base, '--session-owner=' + C.getpid().str()])
	process.run()
	broker := process.pid
	defer {
		C.kill(broker, C.SIGKILL)
		mut status := 0
		C.waitpid(broker, &status, 0)
		process.close()
	}
	mut ready := false
	for _ in 0 .. 100 {
		if session_call_ok('ping', []) {
			ready = true
			break
		}
		time.sleep(10 * time.millisecond)
	}
	assert ready
	mut desktop := Desktop{ home: base }
	desktop.poll_shell_services()
	assert desktop.hub.attached && desktop.hub.available
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		desktop.hub.polled_at = 0
		desktop.poll_shell_services()
		assert desktop.hub.attached && desktop.hub.available
	}
	live := session_poll_kept('idle shell service IPC')
	assert live == 0, 'idle shell service IPC retained ${live} bytes'
}

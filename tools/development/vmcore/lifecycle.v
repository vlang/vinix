// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module vmcore

import devcore
import json2
import os
import os.filelock
import qmpclient
import sourcecommand
import sync.stdatomic
import time

#include <errno.h>

__global stopping = u64(0)

pub fn request_stop(_signal os.Signal) {
	stdatomic.store_u64(&stopping, 1)
}

fn cancelled() bool {
	return stdatomic.load_u64(&stopping) != 0
}

struct StartContext {
	state string
	guest_agent bool
mut:
	agent_guard filelock.FileLock
}

fn monitor_child(pid int, raw voidptr) ! {
	mut context := unsafe { &StartContext(raw) }
	deadline := time.sys_mono_now() + u64(30 * time.second)
	mut ready := false
	for !sourcecommand.child_exited(pid)! {
		if cancelled() { return error('VM start interrupted') }
		if os.exists(context.state + '/qmp.sock') {
			mut monitor := qmpclient.connect_checked(context.state + '/qmp.sock',
				time.sys_mono_now() + u64(2 * time.second), unsafe { nil }) or {
				if time.sys_mono_now() > deadline { return err }
				time.sleep(20 * time.millisecond)
				continue
			}
			monitor.request('query-status', {}) or {
				monitor.close()
				return err
			}
			monitor.close()
			ready = true
			break
		}
		if time.sys_mono_now() > deadline { return error('QEMU startup deadline expired') }
		time.sleep(20 * time.millisecond)
	}
	if !ready { return error('QEMU exited before its monitor was ready') }
	if context.guest_agent {
		st := os.lstat(context.state + '/agent.sock')!
		if st.get_filetype() != .socket || st.uid != u32(os.getuid()) {
			return error('QEMU guest agent channel is not a socket owned by this user')
		}
	}
	// Start owns channel replacement until QEMU has initialized its endpoints.
	// Release only this startup lease; run.lock still protects the live VM.
	context.agent_guard.release()
	println('VM started; control it with vinix-vm status|pause|resume|shutdown|stop ${context.state}')
	for !sourcecommand.child_exited(pid)! {
		if cancelled() {
			control('shutdown', context.state) or {}
			grace := time.sys_mono_now() + u64(5 * time.second)
			for !sourcecommand.child_exited(pid)! && time.sys_mono_now() < grace {
				time.sleep(20 * time.millisecond)
			}
			if !sourcecommand.child_exited(pid)! { control('stop', context.state) or {} }
			return
		}
		time.sleep(20 * time.millisecond)
	}
}

pub fn start(path string) !int {
	state, config := load(path)!
	devcore.verify(config.qemu)!
	devcore.verify(devcore.Pin{state + '/code.fd', config.firmware_code.sha256})!
	mut guard := lease(state)!
	defer { guard.release() }
	mut context := StartContext{state: state, guest_agent: config.guest_agent,
		agent_guard: guest_lease(state)!}
	// Also releases the lease after spawn failure, cancellation or an invalid
	// startup channel. The monitor clears it on successful startup.
	defer { context.agent_guard.release() }
	ensure_stopped(state)!
	if os.exists(state + '/snapshot.pending.json') {
		return error('incomplete snapshot operation; recover it before starting')
	}
	// A dead owner's socket cannot be used for PID-based signaling. Only the
	// current QEMU's private monitor controls it; no saved PID is ever killed.
	for name in ['qmp.sock', 'agent.sock'] {
		if os.exists(state + '/' + name) { os.rm(state + '/' + name)! }
	}
	mut env := devcore.environment(0)
	if config.jit { env['VINIX_ALLOW_WX'] = '1' }
	result := sourcecommand.run_logged_owned(arguments(config, state)!, env,
		cancelled, state + '/qemu.log', false, state, monitor_child, unsafe { &context }, 2) or {
		os.write_file(state + '/exit.json', json2.encode({
			'error': err.msg()
		}) + '\n')!
		return err
	}
	os.write_file(state + '/exit.json', json2.encode({
		'exit_code': result.status
	}) + '\n')!
	return result.status
}

// A manager can be killed while QEMU survives. Keep that live monitor usable
// and refuse a replacement even after the dead manager's record lock vanishes.
fn ensure_stopped(state string) ! {
	ensure_channel_stopped(state + '/qmp.sock', 'monitor')!
	ensure_channel_stopped(state + '/agent.sock', 'guest agent channel')!
}

fn ensure_channel_stopped(path string, label string) ! {
	st := os.lstat(path) or {
		if err.code() == C.ENOENT { return }
		return err
	}
	if st.get_filetype() != .socket {
		return error('VM ${label} path is not a socket; inspect it before restarting')
	}
	// A failed greeting says nothing about whether the listener is alive.
	// Preserve it even when QEMU is hung or its protocol is unavailable.
	if qmpclient.socket_in_use(path, time.sys_mono_now() + u64(time.second), unsafe { nil })! {
		return error('QEMU is still running or its ${label} is occupied; inspect the existing VM before restarting')
	}
}

pub fn control(action string, path string) !json2.Any {
	state, _ := load(path)!
	command := match action {
		'status' { 'query-status' }
		'pause' { 'stop' }
		'resume' { 'cont' }
		'reset' { 'system_reset' }
		'shutdown' { 'system_powerdown' }
		'stop' { 'quit' }
		else { return error('unknown VM action: ${action}') }
	}
	mut monitor := qmpclient.connect_checked(state + '/qmp.sock',
		time.sys_mono_now() + u64(5 * time.second), unsafe { nil })!
	defer { monitor.close() }
	return monitor.request(command, {})!
}

// SPDX-License-Identifier: GPL-2.0-or-later
module main

import desktop.sessionipc
import os
import time

#include <signal.h>
#include <sys/wait.h>
#include <unistd.h>

fn C.waitpid(int, &int, int) int

fn control_start_wait() {
	for _ in 0 .. 100 {
		if session_call_ok('attach', []) { return }
		time.sleep(20 * time.millisecond)
	}
	assert false, 'private session connection did not become ready'
}

fn control_start_replace(previous int, home string) {
	for _ in 0 .. 200 {
		assert session_start(home)
		if session_child_pid != previous {
			control_start_wait()
			return
		}
		time.sleep(20 * time.millisecond)
	}
	assert false, 'compositor did not replace its disconnected broker'
}

fn test_compositor_startup_reuses_only_its_private_connection_and_recovers() {
	base := '${os.temp_dir()}/vinix-control-start-${C.getpid()}'
	os.mkdir(base, mode: 0o700)!
	os.setenv('VINIX_SESSION_RUNTIME', base, true)
	defer {
		if session_child_pid > 0 {
			C.kill(session_child_pid, C.SIGKILL)
			mut status := 0
			C.waitpid(session_child_pid, &status, 0)
		}
		session_child_pid = 0
		sessionipc.session_close_control()
		os.rmdir_all(base) or {}
		unsafe { base.free() }
	}
	assert session_start(base)
	control_start_wait()
	first := session_child_pid
	assert first > 0 && sessionipc.session_has_control()
	assert session_start(base)
	assert session_child_pid == first
	C.kill(first, C.SIGKILL)
	control_start_replace(first, base)
	second := session_child_pid
	assert second != first && sessionipc.session_has_control()
	// Connection loss without a process signal also retires the old broker.
	sessionipc.session_close_control()
	control_start_replace(second, base)
	assert session_child_pid != second && sessionipc.session_has_control()
}

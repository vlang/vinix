// SPDX-License-Identifier: GPL-2.0-or-later
// Standalone session startup diagnostic; deliberately imports no desktop app.
module main

import os
import time
import desktop.sessionipc

#include <signal.h>
#include <sys/wait.h>
#include <errno.h>

fn C.waitpid(int, &int, int) int

fn main() {
	if os.args.len != 2 { panic('usage: setup-broker-check /absolute/path/to/session-broker') }
	check_broker(os.args[1]) or {
		eprintln(err.msg())
		exit(1)
	}
}

fn check_broker(path string) ! {
	root := os.real_path(os.temp_dir()) + '/vinix-setup-broker-check-${os.getpid()}'
	os.mkdir(root, mode: 0o700)!
	defer { os.rmdir_all(root) or {} }
	os.mkdir(root + '/runtime', mode: 0o700)!
	os.setenv('VINIX_SESSION_RUNTIME', root + '/runtime', true)
	defer { os.unsetenv('VINIX_SESSION_RUNTIME') }
	broker := sessionipc.session_start_broker_at(root, path) or { return error('broker launch refused') }
	mut reaped := false
	mut ready := false
	mut failure := ''
	defer { sessionipc.session_close_control() }
	// Do not panic or return after launch until the child has been reaped.
	for _ in 0 .. 400 {
		if sessionipc.session_call_ok('ping', []) {
			ready = sessionipc.session_call_ok('attach', [])
			if !ready { failure = 'broker ping succeeded but attach refused' }
			break
		}
		mut status := 0
		if C.waitpid(broker, &status, C.WNOHANG) == broker {
			reaped = true
			failure = 'broker exited before readiness: wait status ${status}, exit ${status >> 8}, signal ${status & 127}'
			break
		}
		time.sleep(10 * time.millisecond)
	}
	if !ready && failure == '' { failure = 'broker remained alive without a ready private connection' }
	if !reaped {
		if C.kill(broker, C.SIGKILL) != 0 && C.errno != C.ESRCH {
			failure = 'broker cleanup could not stop child'
		}
		for {
			mut status := 0
			if C.waitpid(broker, &status, 0) == broker {
				reaped = true
				break
			}
			if C.errno == C.EINTR { continue }
			failure = 'broker cleanup could not reap child'
			break
		}
	}
	if failure != '' { return error(failure) }
	if !reaped { return error('broker cleanup left a child') }
	println('standalone broker startup PASS')
}

// SPDX-License-Identifier: GPL-2.0-or-later
module linuxcheck

import os
import time

fn testsuite_begin() {
	mode := os.getenv('VINIX_IOS_GUARD_HELPER')
	if mode == '' { return }
	match mode {
		'success' {
			C.write(1, c'guard-success\n', 14)
			C._exit(0)
		}
		'nonzero' {
			C.write(2, c'guard-known-exit\n', 17)
			C._exit(37)
		}
		'timeout' {
			time.sleep(10 * time.second)
			C._exit(0)
		}
		'ignore-term' {
			C.signal(C.SIGTERM, C.SIG_IGN)
			time.sleep(10 * time.second)
			C._exit(0)
		}
		'orphan' {
			pid := C.fork()
			if pid < 0 { C._exit(125) }
			if pid == 0 {
				time.sleep(10 * time.second)
				C._exit(0)
			}
			println('ORPHAN=${pid}')
			C.fflush(unsafe { nil })
			C._exit(0)
		}
		'output' {
			buffer := []u8{len: 65536, init: `x`}
			for _ in 0 .. 320 { C.write(1, buffer.data, buffer.len) }
			C._exit(0)
		}
		'interrupt' {
			C.kill(C.getppid(), C.SIGTERM)
			time.sleep(10 * time.second)
			C._exit(0)
		}
		else { C._exit(98) }
	}
}

fn guard_test_directory(label string) string {
	path := os.join_path(os.temp_dir(), 'vinix-ios-guard-${os.getpid()}-${time.sys_mono_now()}-${label}')
	os.mkdir(path) or { panic(err) }
	return path
}

fn guard_test_run(path string, label string, mode string, seconds int) !(int, string) {
	mut env := os.environ()
	env['VINIX_IOS_GUARD_HELPER'] = mode
	return guarded_command(path, label, [os.real_path(os.args[0])], path, env, seconds)
}

fn test_guard_preserves_output_and_normal_nonzero_status() {
	path := guard_test_directory('exit')
	defer { os.rmdir_all(path) or { panic(err) } }
	code, output := guard_test_run(path, 'success', 'success', 3) or { panic(err) }
	assert code == 0 && output == 'guard-success\n'
	failed, diagnostic := guard_test_run(path, 'nonzero', 'nonzero', 3) or { panic(err) }
	assert failed == 37 && diagnostic == 'guard-known-exit\n'
	assert os.read_file(path + '/nonzero.status.txt') or { panic(err) } == '37\n'
	if _, _ := guard_test_run(path, 'success', 'success', 3) {
		assert false
	}
	assert os.read_file(path + '/success.log') or { panic(err) } == 'guard-success\n'
}

fn test_guard_retires_orphan_that_keeps_stdout_open() {
	path := guard_test_directory('orphan')
	defer { os.rmdir_all(path) or { panic(err) } }
	start := time.sys_mono_now()
	mut rejected := false
	guard_test_run(path, 'orphan', 'orphan', 3) or {
		rejected = err.msg().contains('descendants')
	}
	assert rejected && time.sys_mono_now() - start < 3 * u64(time.second)
	log := os.read_file(path + '/orphan.log') or { panic(err) }
	pid := log.all_after('ORPHAN=').trim_space().int()
	assert pid > 0 && C.kill(pid, 0) == -1 && C.errno == C.ESRCH
	assert (os.read_file(path + '/orphan.guard.txt') or { panic(err) }).contains('reaped=true')
}

fn test_guard_handles_closed_standard_input() {
	path := guard_test_directory('closed-stdin')
	defer { os.rmdir_all(path) or { panic(err) } }
	saved := C.dup(0)
	assert saved >= 0
	C.close(0)
	defer {
		C.dup2(saved, 0)
		C.close(saved)
	}
	code, output := guard_test_run(path, 'closed-stdin', 'success', 3) or { panic(err) }
	assert code == 0 && output == 'guard-success\n'
}

fn test_guard_enforces_deadline_and_output_cap() {
	path := guard_test_directory('bounds')
	defer { os.rmdir_all(path) or { panic(err) } }
	start := time.sys_mono_now()
	mut timed_out := false
	guard_test_run(path, 'timeout', 'timeout', 1) or { timed_out = err.code() == 124 }
	assert timed_out && time.sys_mono_now() - start < 4 * u64(time.second)
	mut capped := false
	guard_test_run(path, 'output', 'output', 3) or { capped = err.msg().contains('16 MiB') }
	assert capped
	mut killed := false
	guard_test_run(path, 'ignore-term', 'ignore-term', 1) or { killed = err.code() == 124 }
	assert killed
	assert (os.read_file(path + '/ignore-term.status.txt') or { panic(err) }) == '137\n'
	assert (os.read_file(path + '/ignore-term.guard.txt') or { panic(err) }).contains('cleanup_complete=true')
}

fn test_guard_cleans_up_on_parent_signal_and_restores_handler() {
	path := guard_test_directory('signal')
	defer { os.rmdir_all(path) or { panic(err) } }
	mut interrupted := false
	guard_test_run(path, 'interrupt', 'interrupt', 3) or { interrupted = err.code() == 143 }
	assert interrupted
	code, output := guard_test_run(path, 'after-signal', 'success', 3) or { panic(err) }
	assert code == 0 && output == 'guard-success\n'
}

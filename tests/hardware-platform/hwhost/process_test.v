// SPDX-License-Identifier: GPL-2.0-or-later
module hwhost

import os
import time

fn log_file(name string) string {
	return os.join_path(os.vtmp_dir(), 'hwhost-${name}-${os.getpid()}.log')
}

fn test_a_stopped_child_is_gone_and_collected() {
	log := log_file('stop')
	defer {
		os.rm(log) or {}
	}
	mut child := start_child(['sleep', '60'], map[string]string{}, log)!
	assert process_exists(child.pid)
	assert !child.poll()
	assert child.outcome() == 'still running'
	child.stop()
	assert child.poll()
	// Collected: the number no longer names a process, not even a zombie.
	assert !process_exists(child.pid)
	assert child.outcome() == 'killed by signal 15'
	assert child.exit_code() == -1
	// Stopping what has ended is nothing.
	child.stop()
}

fn test_a_child_that_ignores_being_asked_is_killed() {
	log := log_file('kill')
	defer {
		os.rm(log) or {}
	}
	mut child := start_child(['sh', '-c', 'trap "" TERM; echo ready; while :; do sleep 1; done'],
		map[string]string{}, log)!
	// Not before the trap is set: until then the shell dies of the first signal.
	for !os.read_file(log)!.contains('ready') {
		time.sleep(10 * time.millisecond)
	}
	started := now_ms()
	child.stop()
	assert !process_exists(child.pid)
	assert child.outcome() == 'killed by signal 9'
	assert now_ms() - started >= 5000
}

fn test_a_tool_gets_its_environment_and_its_output_is_kept() {
	log := log_file('tool')
	defer {
		os.rm(log) or {}
	}
	run_tool(['sh', '-c', 'echo "value=\$HWHOST_TEST_VALUE"; echo warning >&2'], {
		'HWHOST_TEST_VALUE': 'from the controller'
	}, log, 30)!
	assert os.read_file(log)! == 'value=from the controller\nwarning\n'
}

fn test_a_failing_tool_is_quoted() {
	log := log_file('fail')
	defer {
		os.rm(log) or {}
	}
	run_tool(['sh', '-c', 'echo "no such sysroot" >&2; exit 3'], map[string]string{},
		log, 30) or {
		assert err.msg().contains('exit status 3')
		assert err.msg().contains('no such sysroot')
		run_tool(['hwhost-no-such-tool'], map[string]string{}, log, 30) or {
			assert err.msg().contains('is not on PATH')
			return
		}
		assert false, 'a missing tool ran'
		return
	}
	assert false, 'a failing tool passed'
}

fn test_a_tool_that_does_not_finish_is_stopped() {
	log := log_file('slow')
	defer {
		os.rm(log) or {}
	}
	run_tool(['sleep', '60'], map[string]string{}, log, 1) or {
		assert err.msg().contains('did not finish in 1 s')
		return
	}
	assert false, 'a tool ran past its time'
}

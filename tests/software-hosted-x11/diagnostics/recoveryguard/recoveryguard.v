module recoveryguard

import os
import json2
import time

#include <errno.h>
#include <signal.h>

fn C.getpgid(pid i32) i32

// Complete subprocess output belongs in its separate retained log.
pub fn bounded_message(text string) string {
	return if text.len > 2048 { text[..2048] } else { text }
}

pub fn invoke(args []string, log string) ! {
	os.write_file(log + '.argv.json', json2.encode(args))!
	mut p := os.new_process(args[0])
	defer { p.close() }
	p.set_args(args[1..]); p.set_redirect_stdio_merged(); p.run()
	C.close(p.stdio_fd[0]); p.stdio_fd[0] = -1
	text := p.stdout_slurp(); p.wait()
	os.write_file(log, text)!
	os.write_file(log + '.exit.json', json2.encode({'exit_code': p.code}))!
	if p.code != 0 { return error(bounded_message('archive step failed; full output retained: ' + log)) }
}

pub fn deadline_expired(start_ns i64, limit_ms int) bool {
	return time.sys_mono_now() - start_ns >= i64(limit_ms) * 1_000_000
}

pub fn group_present(pid int) !bool {
	if pid <= 1 { return error('invalid process group') }
	if C.kill(-pid, 0) == 0 { return true }
	saved_errno := int(C.errno)
	if saved_errno == C.ESRCH { return false }
	if saved_errno == C.EPERM { return true }
	return error('process-group probe failed, errno=' + saved_errno.str())
}

fn raw_kill(pid int) ! {
	if C.kill(pid, C.SIGKILL) == 0 { return }
	saved_errno := int(C.errno)
	if saved_errno != C.ESRCH { return error('raw process kill failed, errno=' + saved_errno.str()) }
}

// is_alive() can reap the leader. Negative-PGID operations remain effective.
pub fn terminate_group(mut p os.Process, timeout_ms int) ! {
	if p.pid <= 1 || p.pid == C.getpgid(0) || timeout_ms <= 0 { return error('invalid group cleanup scope') }
	start := time.sys_mono_now()
	mut last_error := ''
	for {
		present_before := group_present(p.pid)!
		if present_before { raw_kill(-p.pid) or { last_error = err.msg() } }
		// A reaped PID may have been reused. Never signal that positive PID.
		known_finished := p.status in [.exited, .aborted] && p.code >= 0
		if !known_finished { raw_kill(p.pid) or { last_error = err.msg() } }
		alive := p.is_alive()
		present := group_present(p.pid) or { return err }
		mut reaped := false
		if !alive && p.status in [.exited, .aborted] && p.code >= 0 {
			mut status := 0
			waited := C.waitpid(p.pid, &status, C.WNOHANG)
			saved_errno := int(C.errno)
			reaped = waited == -1 && saved_errno == C.ECHILD
		}
		if reaped && !present { p.wait(); return }
		if deadline_expired(start, timeout_ms) {
			return error('bounded group cleanup failed: leader_reaped=' + reaped.str() +
				', group_present=' + present.str() + ', ' + last_error)
		}
		time.sleep(20 * time.millisecond)
	}
}

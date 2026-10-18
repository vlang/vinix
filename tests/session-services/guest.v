// SPDX-License-Identifier: GPL-2.0-or-later
// Boot this as PID 1 with the three static service executables in /usr/bin.
module main

import desktop.sessioncore
import desktop.sessionipc
import os
import time

fn wait_ready() {
	for _ in 0 .. 100 {
		if sessionipc.session_call_ok('ping', []) { return }
		time.sleep(50 * time.millisecond)
	}
	panic('session broker did not become ready')
}

fn command_line(pid int) string {
	return (os.read_file('/proc/${pid}/cmdline') or { '' }).replace('\x00', ' ')
}

fn wait_identity(pid int, name string) {
	for _ in 0 .. 100 {
		if command_line(pid).contains('/usr/bin/' + name) { return }
		time.sleep(50 * time.millisecond)
	}
	panic('wrong service process identity: ${pid}: ${command_line(pid)}')
}

fn clock_runner() int {
	for _ in 0 .. 100 {
		record := sessionipc.session_call('services', []) or { '' }
		for line in record.split_into_lines() {
			f := sessioncore.fields(line) or { continue }
			if f.count == 8 && f.values[0] == 'service' {
				pid := int(sessioncore.number(f.values[4], 1, 2147483647) or { continue })
				return pid
			}
		}
		time.sleep(50 * time.millisecond)
	}
	panic('clock service did not start')
}

fn clock_child(guardian int) int {
	for _ in 0 .. 100 {
		for entry in os.ls('/proc') or { []string{} } {
			pid := entry.int()
			if pid <= 1 { continue }
			stat := os.read_file('/proc/${pid}/stat') or { continue }
			end := stat.last_index(') ') or { continue }
			fields := stat[end + 2..].split(' ')
			if fields.len > 1 && fields[1].int() == guardian && command_line(pid).contains('vinix-timesync') {
				return pid
			}
		}
		time.sleep(50 * time.millisecond)
	}
	panic('clock worker was not a separate executable below its runner')
}

fn wait_gone(pids []int) {
	for _ in 0 .. 100 {
		mut status := i32(0)
		for C.waitpid(-1, &status, C.WNOHANG) > 0 {
		}
		if pids.all(C.kill(it, 0) != 0) { return }
		time.sleep(50 * time.millisecond)
	}
	panic('service processes survived shutdown: ${pids}')
}

fn main() {
	$if amd64 {
		serial := C.open(c'/dev/com1', C.O_WRONLY, 0)
		assert serial >= 0
		assert C.dup2(serial, 1) == 1 && C.dup2(serial, 2) == 2
		if serial > 2 { C.close(serial) }
	}
	println('SERVICE CHECK: guest init started')
	for path in ['/run', '/root/services-smoke', '/tmp'] { os.mkdir_all(path)! }
	for legacy in [false, true] {
		if legacy && !os.is_executable('/usr/bin/vinix-desktop') { break }
		program := if legacy { '/usr/bin/vinix-desktop' } else { '/usr/bin/vinix-session' }
		broker := sessionipc.session_start_broker_at('/root/services-smoke', program) or { panic('cannot launch broker') }
		wait_ready()
		wait_identity(broker, 'vinix-session')
		assert sessionipc.session_call_ok('attach', [])
		runner := clock_runner()
		wait_identity(runner, 'vinix-service-runner')
		clock := clock_child(runner)
		wait_identity(clock, 'vinix-timesync')
		println('SERVICE CHECK: independent session, runner and timesync identities PASS (legacy=${legacy})')
		assert sessionipc.session_call_ok('shutdown', [])
		mut status := 0
		assert C.waitpid(broker, &status, 0) == broker && status == 0
		sessionipc.session_close_control()
		wait_gone([runner, clock])
		println('SERVICE CHECK: graceful shutdown retires runner and clock PASS')
	}
	broker := sessionipc.session_start_broker('/root/services-smoke') or { panic('cannot launch broker') }
	wait_ready()
	runner := clock_runner()
	clock := clock_child(runner)
	C.kill(broker, C.SIGKILL)
	mut status := 0
	assert C.waitpid(broker, &status, 0) == broker
	sessionipc.session_close_control()
	wait_gone([runner, clock])
	println('SERVICE CHECK: broker crash closes the lease and retires the group PASS')
	println('SESSION SERVICES PASS')
	for { time.sleep(time.second) }
}

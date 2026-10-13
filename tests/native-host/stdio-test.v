// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import json2
import nativequery
import os
import sourcecommand

fn C.raise(i32) i32
fn C.fstat(i32, &C.stat) i32

fn descriptors() nativequery.Value {
	mut rows := []nativequery.Value{}
	for fd in 0 .. 3 {
		mut state := C.stat{}
		if C.fstat(fd, &state) != 0 {
			rows << nativequery.Value([nativequery.Value(fd), nativequery.Value(json2.Null{})])
			continue
		}
		rows << nativequery.Value([nativequery.Value(fd),
			nativequery.Value(u64(state.st_mode) & 0o170000), nativequery.Value(u64(state.st_dev)),
			nativequery.Value(u64(state.st_ino)), nativequery.Value(int(C.fcntl(fd, C.F_GETFD)))])
	}
	return nativequery.Value(rows)
}

fn same_descriptors(first nativequery.Value, second nativequery.Value) bool {
	left := first.as_array()
	right := second.as_array()
	if left.len != right.len { return false }
	for index, row in left {
		a := row.as_array()
		b := right[index].as_array()
		if a.len != b.len { return false }
		for at, value in a {
			if value is json2.Null {
				if b[at] !is json2.Null { return false }
			} else if b[at] is json2.Null || value.u64() != b[at].u64() {
				return false
			}
		}
	}
	return true
}

struct ProbeFailure {
	token int
}

fn (error ProbeFailure) msg() string { return 'actual callback error' }

fn (error ProbeFailure) code() int { return 61 }

fn (error &ProbeFailure) identity() voidptr { return unsafe { voidptr(error) } }

struct Probe {
	controller nativequery.Controller
	expected   nativequery.Value
	depth      int
	fail       bool
	interrupt  bool
	failure    &ProbeFailure = unsafe { nil }
mut:
	reached int
	pid     int
}

fn started(pid int, context voidptr) {
	mut probe := unsafe { &Probe(context) }
	probe.pid = pid
}

fn retired(pid int) ! {
	if pid <= 0 { return error('missing real query PID') }
	if C.kill(i32(pid), 0) == 0 || C.errno != C.ESRCH {
		return error('native query process retained after its owner retired')
	}
}

fn callback(name string, row map[string]nativequery.Value, context voidptr) !nativequery.Value {
	mut probe := unsafe { &Probe(context) }
	if name != 'probe' || row.len != 0 { return error('unexpected native callback') }
	probe.reached++
	actual := descriptors()
	if !same_descriptors(actual, probe.expected) {
		return error('callback changed caller standard descriptors')
	}
	if probe.depth > 0 {
		nested := call(probe.controller, probe.depth - 1, false, false)!
		if !same_descriptors(nested, probe.expected) {
			return error('nested callback changed descriptors')
		}
	}
	if probe.fail { return probe.failure }
	if probe.interrupt { C.raise(C.SIGINT) }
	return actual
}

fn call(controller nativequery.Controller, depth int, fail bool, interrupt bool) !nativequery.Value {
	expected := descriptors()
	failure := if fail { &ProbeFailure{92371} } else { &ProbeFailure(unsafe { nil }) }
	mut probe := Probe{ controller: controller, expected: expected, depth: depth, fail: fail, interrupt: interrupt, failure: failure }
	value := controller.call({}, callback, &probe) or {
		if probe.pid > 0 { retired(probe.pid)! }
		if fail {
			if err is ProbeFailure {
				if err.identity() != unsafe { voidptr(failure) } {
					return error('callback error object identity changed')
				}
			}
		}
		return err
	}
	retired(probe.pid)!
	if probe.reached != 1 || !same_descriptors(value, expected) || !same_descriptors(descriptors(), expected) {
		return error('native callback response/descriptor mismatch: ' + json2.encode(value) + ' / ' + json2.encode(expected))
	}
	return value
}

fn states(controller nativequery.Controller) ! {
	mut owners := [i32(-1), -1, -1]!
	mut flags := [i32(0), 0, 0]!
	defer {
		for fd in 0 .. 3 {
			if owners[fd] >= 0 {
				C.dup2(owners[fd], fd)
				C.fcntl(fd, C.F_SETFD, flags[fd])
				C.close(owners[fd])
			}
		}
	}
	for fd in 0 .. 3 {
		flags[fd] = C.fcntl(fd, C.F_GETFD)
		if flags[fd] < 0 { return os.error_posix() }
		owners[fd] = C.fcntl(fd, C.F_DUPFD_CLOEXEC, 30)
		if owners[fd] < 0 { return os.error_posix() }
	}
	for first in 0 .. 3 {
		for second in 0 .. 3 {
			for third in 0 .. 3 {
				for fd, state in [first, second, third] {
					if C.dup2(owners[fd], fd) < 0 || C.fcntl(fd, C.F_SETFD, flags[fd]) < 0 {
						return os.error_posix()
					}
					if state == 1 {
						C.close(fd)
					} else if state == 2 {
						C.fcntl(fd, C.F_SETFD, flags[fd] | C.FD_CLOEXEC)
					}
				}
				call(controller, 1, false, false)!
				expected := descriptors()
				mut callback_error := false
				call(controller, 0, true, false) or {
					if err is ProbeFailure {
						callback_error = err.token == 92371 && err.code() == 61
					}
					json2.Null{}
				}
				if !callback_error { return error('callback error identity was lost') }
				mut eof := false
				mut context := Probe{ controller: controller, expected: expected, fail: true }
				controller.call({
					'mode': nativequery.Value('eof')
				}, callback, &context) or {
					eof = err.msg() == controller.eof_message
					json2.Null{}
				}
				retired(context.pid)!
				if !eof || context.reached != 0 || !same_descriptors(descriptors(), expected) {
					return error('EOF or post-error descriptor state mismatch')
				}
			}
		}
	}
}

fn repeated(controller nativequery.Controller) string {
	for _ in 0 .. 100 { call(controller, 0, false, false) or { return err.msg() } }
	return ''
}

fn run() ! {
	guard := cachecli.own_commands()
	defer { guard.close() }
	if os.args.len == 2 && os.args[1] in ['--help', '-h'] {
		println('Usage: stdio-test [NATIVE_QUERY EVIDENCE]')
		return
	}
	if os.args.len !in [1, 3] { return error('Usage: stdio-test [NATIVE_QUERY EVIDENCE]') }
	mut private := ''
	defer { if private != '' { os.rmdir_all(private) or {} } }
	mut executable := ''
	mut work := ''
	if os.args.len == 1 {
		private = sourcecommand.temporary('vinix-native-stdio')!
		executable = private + '/query'
		work = private + '/evidence'
		if override := os.getenv_opt('VINIX_NATIVE_STDIO_QUERY') {
			executable = override
		} else {
			root := os.real_path(os.dir(@FILE) + '/../..')
			result := sourcecommand.capture_full([
				root + '/build-support/run-v-tool.sh',
				root + '/tests/native-host/stdio-query.v',
				'--install-query',
				executable,
			], os.environ(), -1, 64 * 1024 * 1024, cachecli.cancelled)!
			if result.status != 0 || ['retrying with', 'V panic:'].any((result.stdout + result.stderr).contains(it)) {
				return error('native stdio query build failed: ' + result.stdout + result.stderr)
			}
		}
	} else {
		executable = os.args[1]
		work = os.args[2]
	}
	controller := nativequery.Controller{ executable: executable, started: started }
	os.mkdir_all(work)!
	call(controller, 0, false, false)!
	states(controller)!
	println('PASS 27 actual descriptor states, nested callbacks, saved native errors and EOF')
	flush_stdout()
	mut before := os.ls('/dev/fd')!
	before.sort()
	for _ in 0 .. 100 {
		mut failed := false
		call(nativequery.Controller{ executable: '/missing/native-stdio-query', started: started }, 0, false, false) or {
			failed = true
			json2.Null{}
		}
		if !failed { return error('missing native spawn failure') }
		mut current := os.ls('/dev/fd')!
		current.sort()
		if before != current { return error('failed native query spawn retained descriptors') }
	}
	for _ in 0 .. 500 { call(controller, 0, false, false)! }
	mut jobs := []thread string{}
	for _ in 0 .. 4 { jobs << spawn repeated(controller) }
	for job in jobs {
		message := job.wait()
		if message != '' { return error(message) }
	}
	mut after := os.ls('/dev/fd')!
	after.sort()
	if before != after {
		return error('descriptor growth after repeated/threaded native callbacks')
	}
	println('PASS 500 actual callbacks and 4x100 concurrent calls with flat descriptors')
	flush_stdout()
	mut interrupted := false
	call(controller, 0, false, true) or {
		interrupted = cachecli.cancelled()
		json2.Null{}
	}
	if !interrupted { return error('missing real SIGINT') }
	after = os.ls('/dev/fd')!
	after.sort()
	if before != after { return error('SIGINT retained query descriptors') }
	os.write_file(work + '/passed', 'PASS\n')!
	println('PASS actual SIGINT and query retirement')
}

fn main() {
	run() or {
		eprintln(err)
		exit(1)
	}
}

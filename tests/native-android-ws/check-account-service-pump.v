// SPDX-License-Identifier: GPL-2.0-or-later
// Production-extracted pump/exception ownership checks; no ART/sign-in claim.
module main

import crypto.sha256
import json2
import os

struct Receipt {
	argv []string
	exit_code int
	output string
}

fn function(source string, name string) string {
	start := source.index('fn ' + name + '(') or { panic('missing ' + name) }
	end := source[start..].index('\n}') or { panic('unclosed ' + name) }
	return source[start..start + end + 2]
}

fn once(source string, before string, after string) string {
	assert source.count(before) == 1, 'production decision changed: ' + before
	return source.replace(before, after)
}

fn command(work string, label string, argv []string) Receipt {
	result := os.exec(argv)
	receipt := Receipt{argv, result.exit_code, result.output}
	os.write_file(work + '/' + label + '.json', json2.encode(receipt, prettify: true)) or { panic(err) }
	return receipt
}

fn main() {
	assert os.args.len == 2, 'usage: check-account-service-pump NEW_EXTERNAL_OUTPUT_DIR'
	repo := os.real_path(os.getwd())
	work := os.abs_path(os.args[1])
	assert !os.exists(work) && !os.is_link(work) && work != repo
		&& !work.starts_with(repo + '/'), 'use a new external evidence directory'
	os.mkdir_all(work)!
	source := os.read_file('build-support/android/nativews/account_service.v')!
	runtime := os.read_file('build-support/android/nativews/runtime.v')!
	checker := os.read_file(@FILE)!
	os.write_file(work + '/account_service.v.input', source)!
	os.write_file(work + '/runtime.v.input', runtime)!
	os.write_file(work + '/checker.v.input', checker)!
	production := function(source, 'ws_auth_pump_failure') + '\n' + function(source, 'ws_account_service_pump')
	mut code := production + '\n' + function(runtime, 'ws_failure')
	mutants := [
		once(production, 'if status < 0 { return ws_auth_pump_failure(e,1,status) }', 'if status < 0 { return false }'),
		once(production, 'ws_auth_pump_failure(e,2,status)\n\t\t\t\t\tws_auth_launch_failed(e,id)',
			'ws_auth_launch_failed(e,id)\n\t\t\t\t\tws_auth_pump_failure(e,2,status)'),
		once(production, 'ws_auth_command_free(command)', '// lost command ownership'),
		once(production, 'WsApplicationThrow(slot(e,13))(e,failure)', '// lost original exception'),
		once(production, 'stage,status,i32(exception)', 'stage,status,i32(0)'),
		once(production, 'ws_auth_pump_failure(e,4,status)', 'ws_auth_pump_failure(e,3,status)'),
		once(production, "ws_failure(e,c'ANDROID-SERVICE-FAIL account pump')", '// lost exception report'),
	]
	mut dispatch := 'fn main() {\n mut pump := Pump(ws_account_service_pump)\n'
	for i, mutant in mutants {
		name := 'pump_mutant_' + i.str()
		code += '\n' + mutant.replace('ws_auth_pump_failure(', name + '_failure(')
			.replace('ws_account_service_pump(', name + '(')
		dispatch += ' if os.args.len == 2 && os.args[1] == "${i}" { pump = ${name} }\n'
	}
	dispatch += ' suite(pump)\n println("ACCOUNT-SERVICE-PUMP-PASS terminal=4 exception-preserved launch-before-cleanup bounded=8")\n}\n'
	code = code.replace('C.pthread_mutex_lock(', 'probe_lock(')
		.replace('C.pthread_mutex_unlock(', 'probe_unlock(')
		.replace('C.write(', 'probe_write(').replace('C.puts(', 'probe_puts(')
	os.write_file(work + '/main.v', model + code + cases + dispatch)!
	compiler := os.real_path(os.getenv_opt('VINIX_V_COMPILER') or { os.find_abs_path_of_executable('v')! })
	build := command(work, 'build', [compiler, '-new-compiler', '-gc', 'boehm', '-nocache', '-cc', 'cc',
		'-enable-globals', '-o', work + '/probe', work + '/main.v'])
	assert build.exit_code == 0, build.output
	run := command(work, 'run', [work + '/probe'])
	assert run.exit_code == 0 && run.output == 'ACCOUNT-SERVICE-PUMP-PASS terminal=4 exception-preserved launch-before-cleanup bounded=8\n', run.output
	for i in 0 .. mutants.len {
		negative := command(work, 'mutant-' + i.str(), [work + '/probe', i.str()])
		assert negative.exit_code != 0 && negative.output.contains('assert'), 'mutation survived: ${i}\n' + negative.output
	}
	revision := command(work, 'source-revision', ['git', 'rev-parse', 'HEAD'])
	assert revision.exit_code == 0
	os.write_file(work + '/evidence.json', json2.encode({
		'scope': 'Production-extracted pump and failure reporting, instrumented JNI/transport boundaries. Four terminal stages, original Throwable identity/lifetime, launch ordering, success/cancel/budget checks; seven compiled negative mutations. No ART or authentication claim.'
		'source_revision': revision.output.trim_space()
		'source_sha256': sha256.hexhash(source)
		'runtime_sha256': sha256.hexhash(runtime)
		'checker_sha256': sha256.hexhash(checker)
		'compiler': compiler
		'compiler_sha256': sha256.sum(os.read_bytes(compiler)!).hex()
	}, prettify: true))!
	mut inventory := map[string]string{}
	for path in os.walk_ext(work, '') {
		if os.is_file(path) { inventory[path[work.len + 1..]] = sha256.sum(os.read_bytes(path)!).hex() }
	}
	os.write_file(work + '/sha256.json', json2.encode(inventory, prettify: true))!
	println('ACCOUNT-SERVICE-PUMP-CHECK-PASS production and ${mutants.len} negative mutations')
}

const model = '
@[translated]
module main
import os
#include <stdio.h>
#include <alloca.h>
fn C.alloca(usize) voidptr
fn C.snprintf(&char, usize, &char, ...) i32
type Pump = fn (voidptr, voidptr) bool
type WsApplicationException = fn (voidptr) voidptr
type WsApplicationThrow = fn (voidptr, voidptr) i32
type Drop = fn (voidptr, voidptr)
type Check = fn (voidptr)
struct WsAuthCommand { id u64 }
struct Probe {
mut:
 statuses []i32 = [i32(0)]
 cursor int
 locked bool
 copy_ok bool = true
 dispatch_ok bool = true
 launch_ok bool = true
 dispatch_exception bool
 launch_exception bool
 capture_nil bool
 write_bad bool
 exception voidptr
 writes []string
 markers []string
 events []string
 copied int
 dispatched int
 freed int
 launched int
 cleaned int
 cancelled int
 captured int
 described int
 restored int
 dropped int
}
__global probe = Probe{}
__global ws_auth_ready = true
__global ws_auth_handle = voidptr(1)
__global ws_auth_mutex = 0
__global test_command = WsAuthCommand{726492}
fn pending(e voidptr) bool { assert !probe.locked; return probe.exception != unsafe { nil } }
fn probe_lock(m &int) i32 { assert !probe.locked; probe.locked = true; return 0 }
fn probe_unlock(m &int) i32 { assert probe.locked; probe.locked = false; return 0 }
fn ws_auth_read(h voidptr, id &u64, timeout i32) i32 {
 assert probe.locked && h == voidptr(1) && timeout == 0
 unsafe { *id = 726492 }
 status := probe.statuses[probe.cursor]; probe.cursor++; return status
}
fn ws_auth_copy(id u64) &WsAuthCommand {
 assert probe.locked && id == 726492
 probe.copied++
 return if probe.copy_ok { &test_command } else { unsafe { nil } }
}
fn ws_auth_dispatch(e voidptr, b voidptr, c &WsAuthCommand) bool {
 assert !probe.locked && c == &test_command
 probe.dispatched++
 if probe.dispatch_exception { probe.exception = voidptr(77) }
 return probe.dispatch_ok
}
fn ws_auth_command_free(c &WsAuthCommand) {
 assert !probe.locked && c == &test_command
 probe.freed++; probe.events << "free"
}
fn ws_auth_cancel(e voidptr, id u64) { assert !probe.locked && id == 726492; probe.cancelled++ }
fn ws_auth_launch(e voidptr, id u64) bool {
 assert !probe.locked && id == 726492
 probe.launched++
 if probe.launch_exception { probe.exception = voidptr(77) }
 return probe.launch_ok
}
fn ws_auth_launch_failed(e voidptr, id u64) {
 assert !probe.locked && id == 726492 && probe.writes.len == 1
 if probe.launch_exception { assert probe.exception == voidptr(77) }
 probe.cleaned++; probe.events << "cleanup"; probe.exception = unsafe { nil }
}
fn probe_write(fd int, data &char, length usize) i64 {
 assert !probe.locked && fd == 2 && length > 0 && length < 128
 probe.writes << unsafe { data.vstring_with_len(int(length)).clone() }
 probe.events << "write"
 return if probe.write_bad { i64(-1) } else { i64(length) }
}
fn probe_puts(text &char) i32 {
 assert !probe.locked
 probe.markers << unsafe { text.vstring() }
 probe.events << "marker"; return 0
}
fn probe_capture(e voidptr) voidptr {
 assert !probe.locked && probe.exception == voidptr(77)
 probe.captured++; probe.events << "capture"
 return if probe.capture_nil { unsafe { nil } } else { voidptr(77) }
}
fn probe_describe(e voidptr) {
 assert !probe.locked && probe.exception == voidptr(77) && probe.markers.len == 1
 probe.described++; probe.events << "describe"; probe.exception = unsafe { nil }
}
fn probe_throw(e voidptr, original voidptr) i32 {
 assert !probe.locked && probe.exception == unsafe { nil } && original == voidptr(77)
 probe.restored++; probe.events << "restore"; probe.exception = original; return 0
}
fn probe_drop(e voidptr, original voidptr) {
 assert !probe.locked && probe.exception == voidptr(77) && original == voidptr(77)
 probe.dropped++; probe.events << "drop"
}
fn slot(e voidptr, index int) voidptr {
 return match index {
  13 { voidptr(probe_throw) }
  15 { voidptr(probe_capture) }
  16 { voidptr(probe_describe) }
  23 { voidptr(probe_drop) }
  else { panic("unexpected JNI slot") }
 }
}
'

const cases = '
fn reset(config Probe) {
 probe = config; ws_auth_ready = true; ws_auth_handle = voidptr(1)
}
fn check_failure(pump Pump, stage int, status i32, exception bool, capture_nil bool) {
 assert !pump(unsafe { nil }, unsafe { nil })
 expected := "ANDROID-AUTH-PUMP-FAIL stage=" + stage.str() + " status=" + status.str() + " pending=" + int(exception).str() + "\\n"
 assert !probe.locked && probe.writes == [expected], probe.writes.str() + " expected=" + expected
 assert probe.captured == int(exception)
 reporting := exception && !capture_nil
 assert probe.described == int(reporting) && probe.restored == int(reporting) && probe.dropped == int(reporting)
 assert probe.markers == if reporting { ["ANDROID-SERVICE-FAIL account pump"] } else { []string{} }
 if stage == 2 {
  assert probe.cleaned == 1 && probe.exception == unsafe { nil }
  assert probe.events.last() == "cleanup"
 } else {
  assert probe.exception == if exception { voidptr(77) } else { unsafe { nil } }
 }
 if stage == 4 {
  assert probe.copied == 1 && probe.dispatched == 1 && probe.freed == 1
  assert probe.events[0] == "free"
 }
}
fn silent(pump Pump) {
 assert pump(unsafe { nil }, unsafe { nil })
 assert !probe.locked && probe.writes.len == 0 && probe.markers.len == 0
 assert probe.captured == 0 && probe.described == 0 && probe.restored == 0 && probe.dropped == 0
}
fn suite(pump Pump) {
 reset(Probe{}); ws_auth_ready = false; silent(pump); assert probe.cursor == 0
 reset(Probe{}); silent(pump); assert probe.cursor == 1
 reset(Probe{}); ws_auth_handle = unsafe { nil }; check_failure(pump, 1, -1, false, false); assert probe.cursor == 0
 for exception in [false, true] {
  original := if exception { voidptr(77) } else { unsafe { nil } }
  reset(Probe{statuses: [i32(-2147483647 - 1)], exception: original})
  check_failure(pump, 1, -2147483647 - 1, exception, false)
  reset(Probe{statuses: [i32(1)], copy_ok: false, exception: original})
  check_failure(pump, 3, 1, exception, false)
  assert probe.copied == 1 && probe.dispatched == 0 && probe.freed == 0
  reset(Probe{statuses: [i32(1)], dispatch_ok: false, dispatch_exception: exception})
  check_failure(pump, 4, 1, exception, false)
  reset(Probe{statuses: [i32(3)], launch_ok: false, launch_exception: exception})
  check_failure(pump, 2, 3, exception, false)
 }
 reset(Probe{statuses: [i32(4)]}); check_failure(pump, 3, 4, false, false)
 reset(Probe{statuses: [i32(-1)], exception: voidptr(77), write_bad: true})
 check_failure(pump, 1, -1, true, false)
 reset(Probe{statuses: [i32(-1)], exception: voidptr(77), capture_nil: true})
 check_failure(pump, 1, -1, true, true)
 reset(Probe{statuses: [i32(2), 0]}); silent(pump); assert probe.cancelled == 1 && probe.cursor == 2
 reset(Probe{statuses: [i32(3), 0]}); silent(pump); assert probe.launched == 1 && probe.cleaned == 0
 reset(Probe{statuses: [i32(1), 0]}); silent(pump)
 assert probe.copied == 1 && probe.dispatched == 1 && probe.freed == 1
 reset(Probe{statuses: [i32(1), 1, 1, 1, 1, 1, 1, 1, -1]}); silent(pump)
 assert probe.cursor == 8 && probe.copied == 8 && probe.dispatched == 8 && probe.freed == 8
}
'

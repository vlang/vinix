// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import fixturehost
import hosttest
import os
import policyhost
import time

#include <signal.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/wait.h>
fn C.write(i32, voidptr, usize) isize
fn C.close(i32) i32
fn C.kill(i32, i32) i32
fn C.getppid() i32
fn C.signal(i32, voidptr) voidptr
fn C.waitpid(i32, &i32, i32) i32
fn C.fcntl(i32, i32, ...) i32
fn C.__atomic_store_n(&i32, i32, i32)
fn C.__atomic_load_n(&i32, i32) i32
__global checker_cancelled i32

fn cancel(_signal i32) { unsafe { C.__atomic_store_n(&checker_cancelled, i32(1), C.__ATOMIC_RELAXED) } }
fn cancelled() bool { return unsafe { C.__atomic_load_n(&checker_cancelled, C.__ATOMIC_RELAXED) } != 0 }

fn child(mode string) ! {
	if os.getenv('HOST_CHILD_PID') != '' { os.write_file(os.getenv('HOST_CHILD_PID'), os.getpid().str())! }
	if mode in ['sleep', 'closed', 'interrupt'] {
		if mode == 'closed' { C.close(1); C.close(2) }
		if mode == 'interrupt' { C.kill(C.getppid(), C.SIGINT) }
		for { time.sleep(10 * time.millisecond) }
	} else if mode == 'large' {
		mut buffer := [8192]u8{}
		for i in 0 .. buffer.len { buffer[i] = u8(i) }
		for _ in 0 .. 96 {
			assert C.write(1, &buffer[0], usize(buffer.len)) == buffer.len
			assert C.write(2, &buffer[0], usize(buffer.len)) == buffer.len
		}
	} else if mode == 'signal' { C.kill(os.getpid(), C.SIGTERM) }
	else if mode == 'exit' { print('stdout'); eprint('stderr'); exit(7) }
	else if mode == 'cwd' { print(os.getwd()) }
}

fn fd_count() int {
	return (os.ls('/dev/fd') or { os.ls('/proc/self/fd') or { panic(err) } }).filter(it.int() >= 3 && C.fcntl(it.int(), C.F_GETFD) >= 0).len
}

fn frozen_literal(source string, prefix string, end_marker string) !string {
	first := prefix.len + (source.index(prefix) or { return error('Missing frozen literal') })
	last := first + (source[first..].index(end_marker) or { return error('Missing frozen literal end') })
	return source[first..last]
}

fn template_checks() ! {
	root := hosttest.root()
	for pair in [['tests/mounted-disk-policy/host.py', 'tests/mounted-disk-policy/hosttemplates/host.h'],
		['tests/securelevel-boot/dispatch.py', 'tests/securelevel-boot/hosttemplates/dispatch/main.v'],
		['tests/securelevel-boot/attribute_faults.py', 'tests/securelevel-boot/hosttemplates/ext2/model.v']] {
		original := fixturehost.capture_in_preferred(['git', 'show', 'd22c958f6d5f71b1174b80cc284a814ed2a6cef3:' + pair[0]], '', policyhost.environment(), false, root, true, policyhost.caller_arch())!
		mut actual := os.read_file(root + '/' + pair[1])!
		prefix := if pair[0].ends_with('/host.py') { 'HEADER = r"""' } else if pair[0].ends_with('/dispatch.py') { "model = '''" } else { "(work/'ext2/model.v').write_text('''" }
		if pair[0].ends_with('/attribute_faults.py') { actual = actual.replace(' read_only bool\n journal &Journal = unsafe { nil }\n', '') }
		assert actual == frozen_literal(original, prefix, if pair[0].ends_with('/host.py') { '"""' } else { "'''" })!
	}
	println('Frozen C header and V model bytes match; only declared filesystem stub fields differ PASS')
}

fn capture_checks(work string) ! {
	mut env := policyhost.environment()
	env['HOST_CHILD_PID'] = work + '/pid'
	mut status := i32(0)
	before := fd_count()
	large := fixturehost.capture_bounded([os.executable(), '--child', 'large'], env, policyhost.caller_arch(), '', 30, unsafe { nil })!
	assert large.status == 0 && large.stdout.len == 96 * 8192 && large.stderr == large.stdout
	for i, byte in large.stdout.bytes() { assert byte == u8(i) }
	for _ in 0 .. 12 {
		for deadline in [-1, 30] {
			result := fixturehost.capture_bounded([os.executable(), '--child', 'exit'], env, policyhost.caller_arch(), '', deadline, unsafe { nil })!
			assert result.status == 7 && result.stdout == 'stdout' && result.stderr == 'stderr'
		}
		result := fixturehost.capture_both_preferred([os.executable(), '--child', 'signal'], env, policyhost.caller_arch())!
		assert result.status == -15
		assert fixturehost.capture_bounded([os.executable(), '--child', 'cwd'], env, policyhost.caller_arch(), work, 30, unsafe { nil })!.stdout == work
		mut rejected := false
		fixturehost.capture_bounded([work + '/missing'], env, policyhost.caller_arch(), '', 30, unsafe { nil }) or { rejected = true }
		assert rejected
		assert fd_count() == before
		assert C.waitpid(os.read_file(work + '/pid')!.int(), &status, C.WNOHANG) == -1
	}
	for mode in ['sleep', 'closed'] {
		started := time.sys_mono_now()
		mut timed_out := false
		fixturehost.capture_bounded([os.executable(), '--child', mode], env, policyhost.caller_arch(), '', 1, unsafe { nil }) or {
			assert err.msg().contains('timed out'); timed_out = true
		}
		assert timed_out && time.sys_mono_now() - started < 5 * u64(time.second)
		assert C.kill(os.read_file(work + '/pid')!.int(), 0) == -1
		assert fd_count() == before && C.waitpid(os.read_file(work + '/pid')!.int(), &status, C.WNOHANG) == -1
	}
	unsafe { C.__atomic_store_n(&checker_cancelled, i32(0), C.__ATOMIC_RELAXED) }
	previous := unsafe { C.signal(C.SIGINT, voidptr(cancel)) }
	defer { unsafe { C.signal(C.SIGINT, previous) } }
	mut interrupted := false
	fixturehost.capture_bounded([os.executable(), '--child', 'interrupt'], env, policyhost.caller_arch(), '', 30, cancelled) or {
		assert err.code() == 130; interrupted = true
	}
	assert interrupted && C.kill(os.read_file(work + '/pid')!.int(), 0) == -1
	assert fd_count() == before && C.waitpid(os.read_file(work + '/pid')!.int(), &status, C.WNOHANG) == -1
	println('Bounded/unbounded capture, binary pipes, timeout, EOF, signal and 60 FD/PID retirement cases PASS')
}

fn native_arch(path string) !string {
	bytes := os.read_bytes(path)!
	assert bytes.len > 8 && bytes[..4] == [u8(0xcf), 0xfa, 0xed, 0xfe]
	return if bytes[4..8] == [u8(12), 0, 0, 1] { 'arm64' } else if bytes[4..8] == [u8(7), 0, 0, 1] { 'amd64' } else { error('Unknown native executable architecture') }
}

fn controller_checks(controller string, work string) ! {
	arch := policyhost.caller_arch()
	assert native_arch(controller)! == arch
	mut env := policyhost.environment()
	for pair in [['hypervisor-host', 'hypervisor'], ['mounted-disk-host', 'mounted'], ['securelevel-host', 'parse'], ['securelevel-dispatch', 'dispatch'], ['securelevel-attributes', 'attributes']] {
		state := work + '/' + pair[1]
		result := hosttest.command([controller, pair[0], '--state-dir', state], work + '/' + pair[1] + '.log', 180, env)!
		assert !result.stderr.contains('AddressSanitizer') && !result.stderr.contains('runtime error:')
		if pair[1] == 'hypervisor' {
			for name in ['original', 'ported', 'model.o', 'ioctl.o'] { assert native_arch(state + '/' + name)! == arch }
			receipt := hosttest.decode_json(os.read_file(state + '/result.json')!)!.as_map()
			assert receipt['status']!.str() == 'PASS' && receipt['cases']!.as_array().len == 19
			assert receipt['assertion_lines']!.as_array().map(it.int()) == [22, 29, 31, 34, 39, 41, 43, 44, 45, 48, 49, 50, 51, 52, 59]
			failures := {-3: 22, 1: 34, 2: 49, 3: 44, 4: 29, 5: 29, 6: 52, 7: 59, 8: 50, 9: 45, 10: 41, 11: 31, 12: 39, 13: 48, 14: 43, 15: 51}
			for item in receipt['cases']!.as_array() {
				row := item.as_map(); value := row['case']!.int()
				expected := if value in [-2, -1] { 'HYPERVISOR UNAVAILABLE: device absent; VM entry was not exercised\nHYPERVISOR GUEST PASS\n' }
					else if value == 0 { 'HYPERVISOR EXECUTION PASS: five guests, IO/HLT exits and all GPRs\nHYPERVISOR GUEST PASS\n' }
					else { (if value == 7 { 'HYPERVISOR EXECUTION PASS: five guests, IO/HLT exits and all GPRs\n' } else { '' })
						+ 'HYPERVISOR FAIL: line ' + failures[value].str() + ' errno ' + (if value == -3 { '13' } else { '99' }) + '\n' }
				assert row['stdout']!.str() == expected
			}
		} else if pair[1] == 'mounted' {
			assert native_arch(state + '/test')! == arch
			for source in ['resource/block_identity.v', 'security/device_policy.v'] {
				assert os.read_bytes(state + '/' + source)! == os.read_bytes(hosttest.root() + '/kernel/' + source)!
			}
		} else if pair[1] == 'parse' {
			assert os.read_file(state + '/securelevel_parse.v')! == os.read_file(hosttest.root() + '/kernel/security/securelevel_parse.v')!.replace_once('module security', 'module main')
			assert os.read_bytes(state + '/parse_test.v')! == os.read_bytes(hosttest.root() + '/tests/securelevel-boot/parse_test.v')!
		} else if pair[1] == 'attributes' {
			assert os.read_bytes(state + '/ext2/attribute_fault_test.v')! == os.read_bytes(hosttest.root() + '/tests/securelevel-boot/attribute_fault_test.v')!
		}
		println(pair[1] + ' native host workflow PASS')
	}
	// Instrument the actual production parser and attribute models as well as
	// the controller. Original assertions remain byte-identical above.
	compiler := os.getenv('V')
	env['ASAN_OPTIONS'] = 'detect_leaks=0:halt_on_error=1'
	env['UBSAN_OPTIONS'] = 'halt_on_error=1'
	for target in [work + '/parse', work + '/attributes/ext2'] {
		hosttest.command([compiler, '-gc', 'none', '-arch', arch, '-cflags', '-fsanitize=address,undefined', '-cflags', '-fno-omit-frame-pointer', '-ldflags', '-fsanitize=address,undefined', 'test', target],
			work + '/' + os.base(target) + '-sanitized.log', 180, env)!
	}
	println('Production parser/attribute models ASan/UBSan PASS')
	owner_checks(controller, work, env)!
}

fn owner_checks(controller string, work string, environment map[string]string) ! {
	scratch := work + '/scratch'; os.mkdir(scratch)!
	mut env := environment.clone(); env['TMPDIR'] = scratch; env['V'] = ''; env['VINIX_BLOCK_POLICY_GENERATOR'] = work + '/missing-generator'
	for _ in 0 .. 3 {
		for family in ['mounted-disk-host', 'securelevel-host', 'securelevel-dispatch', 'securelevel-attributes'] {
			assert hosttest.capture([controller, family], '', 30, env)!.code == 1
			assert os.ls(scratch)!.len == 0
		}
	}
	for argv in [[controller, 'hypervisor-host'], [controller, 'securelevel-host', '--invalid'], [controller, 'mounted-disk-host', '--state-dir', scratch]] {
		assert hosttest.capture(argv, '', 30, env)!.code != 0
		assert os.ls(scratch)!.len == 0
	}
	env = environment.clone(); env['TMPDIR'] = scratch; env['VINIX_BLOCK_POLICY_GENERATOR'] = os.executable(); env['HOST_GENERATOR_SLEEP'] = '1'; env['HOST_CHILD_PID'] = work + '/generator-pid'
	mut process := os.new_process(controller); process.set_args(['mounted-disk-host']); process.set_environment(env); process.set_redirect_stdio()
	defer { process.close() }
	process.run()
	started := time.sys_mono_now()
	for !os.exists(work + '/generator-pid') { if time.sys_mono_now() - started > 10 * u64(time.second) { panic('Generator did not start') }; time.sleep(10 * time.millisecond) }
	C.kill(process.pid, C.SIGINT)
	for process.is_alive() { if time.sys_mono_now() - started > 15 * u64(time.second) { C.kill(process.pid, C.SIGKILL); process.wait(); panic('Controller did not retire on SIGINT') }; time.sleep(10 * time.millisecond) }
	assert process.code == 130
	assert C.kill(os.read_file(work + '/generator-pid')!.int(), 0) == -1
	assert os.ls(scratch)!.len == 0
	println('12 default workspace failures, CLI/fresh-directory guards and real controller SIGINT cleanup PASS')
}

fn main() {
	if os.getenv('HOST_GENERATOR_SLEEP') == '1' { child('sleep') or { panic(err) }; return }
	if os.args.len == 3 && os.args[1] == '--child' { child(os.args[2]) or { panic(err) }; return }
	if os.args.len == 2 && os.args[1] == '--templates' { template_checks() or { panic(err) }; return }
	if os.args.len == 4 && os.args[1] == '--owners' {
		work := hosttest.work_dir(os.args[3], 'vinix-host-suite-owner-') or { panic(err) }
		owner_checks(os.args[2], work, policyhost.environment()) or { panic(err) }
		return
	}
	if os.args.len != 3 { eprintln('Usage: check-host-suite CONTROLLER FRESH-STATE'); exit(2) }
	work := hosttest.work_dir(os.args[2], 'vinix-host-suite-check-') or { panic(err) }
	template_checks() or { panic(err) }
	capture_checks(work) or { panic(err) }
	controller_checks(os.args[1], work) or { panic(err) }
}

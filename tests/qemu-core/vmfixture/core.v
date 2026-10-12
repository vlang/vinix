// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module vmfixture

import corevm
import crypto.sha256
import hosttest
import json2
import os
import term.termios
import time

#flag -I @DIR
#include "abi.h"

fn C.cfmakeraw(voidptr)
fn C.fcntl(i32, i32, ...int) i32
fn C.kill(i32, i32) i32
fn C.signal(i32, voidptr) voidptr

fn section(source string, name string) []string {
	text := source.all_after(name + ' = (').all_before('\n)')
	return text.split_into_lines().filter(it.trim_space().starts_with('b"')).map(it.trim_space().all_after('b"').all_before_last('"'))
}

fn marker_check(original string) ![]string {
	text := os.read_file(original)!
	assert sha256.sum(text.bytes()).hex() in [
		'6c06a7a52b13a2b99533d77d76c43c13f283b32421feabc79c0515001cd8c5ff',
		'b93ec82e33d443697036c9fdd4c5c724959a265e6db19ca192f0d67386fe4447',
		'1257e6a3b20c6aa21dd77a8d27ecc6ff665249325120721fd270ad903a64e840',
	]
	features := section(text, 'FEATURE_MARKERS')
	x86 := section(text, 'AMD64_FEATURE_MARKERS')
	assert features.len == 47 && x86.len == 2
	assert corevm.required(false, false) == [...features, 'VINIX QEMU CORE: PASS']
	assert corevm.required(false, true) == [...features, ...x86, 'VINIX QEMU CORE: PASS']
	assert corevm.required(true, false) == ['VINIX QEMU CORE PERSIST: PASS']
	return [...features, ...x86, 'VINIX QEMU CORE: PASS']
}

fn check_policy() {
	for verification in [false, true] {
		for amd64 in [false, true] {
			markers := corevm.required(verification, amd64)
			good := markers.join('\n') + '\n'
			missing, failures := corevm.results(corevm.Run{ output: good, has_status: true, status: 0, finished: true }, verification, amd64)
			assert missing.len == 0 && failures.len == 0
			for marker in markers {
				for text in [good.replace(marker, ''), good + marker] {
					absent, bad := corevm.results(corevm.Run{ output: text, finished: true }, verification, amd64)
					assert absent == [marker] && bad.len == 0
				}
			}
			for marker in ['VINIX QEMU CORE: FAIL', 'QEMU CORE FAIL line', 'FATAL EXCEPTION',
				'KERNEL PANIC'] {
				_, bad := corevm.results(corevm.Run{ output: good + marker, finished: true }, verification, amd64)
				assert bad == [marker]
			}
			_, bad_exit := corevm.results(corevm.Run{ output: good, has_status: true, status: 7, finished: true }, verification, amd64)
			assert bad_exit == if amd64 { []string{} } else { ['VM runner exit status 7'] }
			_, forced := corevm.results(corevm.Run{ output: good, forced: true, finished: false }, verification, amd64)
			assert forced == if amd64 {
				['the test did not finish before the timeout']
			} else {
				['VM did not exit after the test']
			}
		}
	}
}

fn descriptors() int {
	mut count := 0
	for fd in 0 .. 1024 { if C.fcntl(fd, C.F_GETFD) >= 0 { count++ } }
	return count
}

fn alive(pid int) bool { return C.kill(pid, 0) == 0 }

fn no_process(path string) ! {
	if !os.exists(path) { return }
	pid := os.read_file(path)!.trim_space().int()
	deadline := time.sys_mono_now() + u64(3 * time.second)
	for alive(pid) && time.sys_mono_now() < deadline { time.sleep(10 * time.millisecond) }
	assert !alive(pid), path
}

pub fn guest(arguments []string) ! {
	mode := arguments[0]
	case_name := os.getenv('VINIX_CORE_FIXTURE_CASE')
	work := os.getenv('VINIX_CORE_FIXTURE_WORK')
	if mode == 'descendant' {
		os.write_file(work + '/descendant.pid', os.getpid().str())!
		for { time.sleep(10 * time.millisecond) }
	}
	if case_name in ['descendant', 'hang', 'resist'] {
		os.write_file(work + '/leader.pid', os.getpid().str())!
		mut child := os.new_process(os.executable())
		child.set_args(['--guest', 'descendant'])
		child.run()
		// Keep the process wrapper alive; the parent owns the whole group.
		for !os.exists(work + '/descendant.pid') { time.sleep(time.millisecond) }
		if case_name != 'descendant' {
			if case_name == 'resist' { unsafe { C.signal(C.SIGTERM, C.SIG_IGN) } }
			for { time.sleep(10 * time.millisecond) }
		}
	}
	if mode == 'arm' {
		mut entries := []json2.Any{}
		if os.exists(work + '/boots.json') {
			entries = json2.decode[[]json2.Any](os.read_file(work + '/boots.json')!)!
		}
		entries << json2.Any({
			'argv':        json2.Any(os.args[3..].map(json2.Any(it)))
			'environment': json2.Any(hosttest.string_map(os.environ()))
			'cwd':         json2.Any(os.getwd())
		})
		os.write_file(work + '/boots.json', json2.encode(entries))!
		if entries.len == 2 && case_name == 'persist-fail' {
			print('VINIX QEMU CORE: FAIL\n')
			flush_stdout()
			time.sleep(100 * time.millisecond)
			return
		}
	}
	if mode == 'amd64' { os.write_file(work + '/argv.json', json2.encode(os.args[3..]))! }
	mut terminal := termios.Termios{}
	assert termios.tcgetattr(0, mut terminal) == 0
	C.cfmakeraw(unsafe { &terminal })
	assert termios.tcsetattr(0, C.TCSANOW, mut terminal) == 0
	mut text := os.read_file(os.getenv('VINIX_CORE_FIXTURE_MARKERS'))!
	if mode == 'arm' {
		boots := json2.decode[[]json2.Any](os.read_file(work + '/boots.json')!)!
		if boots.len == 2 { text = 'VINIX QEMU CORE PERSIST: PASS\n' }
	}
	if case_name == 'missing' { text = text.replace('QEMU CORE PASS: secure getrandom\n', '') }
	if case_name == 'duplicate' { text += 'QEMU CORE PASS: secure getrandom\n' }
	if case_name == 'failure' { text += 'FATAL EXCEPTION\n' }
	if case_name == 'large' { text = 'A'.repeat(262144) + '\n' + text }
	// Split every marker, so detection must span arbitrary PTY reads.
	mut out := os.stdout()
	for index := 0; index < text.len; index += 11 {
		out.write(text[index..if index + 11 < text.len { index + 11 } else { text.len }].bytes())!
	}
	out.flush()
	if mode == 'arm' {
		mut controls := [2]u8{}
		mut read := 0
		for read < 2 {
			count := C.read(0, &controls[read], usize(2 - read))
			if count <= 0 { return error('missing QEMU shutdown control') }
			read += int(count)
		}
		assert controls == [u8(1), u8(`x`)]!
		os.write_file(work + '/shutdown.txt', 'control-a x\n')!
		if case_name == 'nonzero' { exit(7) }
		return
	}
	if case_name in ['nonzero', 'early'] {
		time.sleep(200 * time.millisecond)
		exit(if case_name == 'nonzero' { 7 } else { 0 })
	}
	for { time.sleep(10 * time.millisecond) }
}

fn tests(work string, original string, runner string) ! {
	os.mkdir_all(work)!
	markers := marker_check(original)!
	os.write_file(work + '/markers', markers.join('\n') + '\n')!
	check_policy()
	base := corevm.Options{ root: work + '/root', state_dir: work + '/state', guest_init: '/guest init', initramfs: '/base.tar' }
	assert corevm.arm_command(base, false, '') == [
		base.root + '/scripts/run-aarch64.sh',
		'--serial',
		'--mem=2048',
		'--guest-init=/guest init',
	]
	assert corevm.arm_command(base, true, '')[1] == '--no-build'
	assert corevm.arm_command(base, false, '1')[1] == '--no-build'
	env := corevm.arm_environment(base, {
		'VINIX_QEMU_PERSIST':            'old'
		'VINIX_QEMU_PACKAGE_STORE_PORT': ''
		'USE_TCG':                       '0'
		'ordinary':                      'kept'
	}, 'Linux')!
	assert 'VINIX_QEMU_PERSIST' !in env && env['USE_TCG'] == '0' && env['VINIX_QEMU_PACKAGE_STORE_PORT'] == '' && env['ordinary'] == 'kept'
	assert env['VINIX_QEMU_PERSIST_SIZE_MB'] == '64' && env['VINIX_BOOT_DISK'] == base.state_dir + '/boot.img'
	linux := corevm.arm_environment(base, map[string]string{}, 'Linux')!
	assert linux['USE_TCG'] == '1' && linux['VINIX_QEMU_PACKAGE_STORE_PORT'].int() > 0
	darwin := corevm.arm_environment(base, map[string]string{}, 'Darwin')!
	assert 'USE_TCG' !in darwin
	for cpu in ['max', 'max,-la57'] {
		opt := corevm.parse(['--arch=amd64', '--iso=', '--cpus=64', '--timeout=1'], '/', cpu)!
		assert opt.iso == os.getwd() && opt.cpus == 64 && opt.cpu == cpu
		command := corevm.amd64_command(opt, {
			'VINIX_QEMU_ACCEL': 'hvf'
		})
		assert command[4] == 'hvf' && command[6] == cpu
	}
	for args in [['--cpus=0'], ['--cpus=65'], ['--timeout=0'], ['--timeout=-1'], ['--timeout=no'],
		['--arch=alien'], ['--unknown'], ['--iso'], []string{}] {
		if _ := corevm.parse(args, '/', 'max') { return error('accepted invalid arguments') }
	}
	os.mkdir_all(base.root + '/scripts')!
	os.write_file(base.root + '/scripts/run-aarch64.sh', '#!/bin/sh\nexec ' + hosttest.shell_quote(os.executable()) + ' --guest arm "$@"\n')!
	os.chmod(base.root + '/scripts/run-aarch64.sh', 0o755)!
	mut environment := os.environ()
	environment['VINIX_CORE_FIXTURE_MARKERS'] = work + '/markers'
	for case_name in ['success', 'missing', 'duplicate', 'failure', 'nonzero', 'large', 'descendant'] {
		here := work + '/' + case_name
		os.mkdir_all(here)!
		environment['VINIX_CORE_FIXTURE_WORK'] = here
		environment['VINIX_CORE_FIXTURE_CASE'] = case_name
		result := corevm.capture([os.executable(), '--guest', 'arm'], environment, '', 5, false, false, false)!
		missing, failures := corevm.results(result, false, false)
		assert (missing.len + failures.len == 0) == (case_name in ['success', 'large', 'descendant'])
		assert result.has_status && !result.forced
		assert os.read_file(here + '/shutdown.txt')! == 'control-a x\n'
		no_process(here + '/leader.pid')!
		no_process(here + '/descendant.pid')!
	}
	before := descriptors()
	for _ in 0 .. 100 {
		result := corevm.capture(['/usr/bin/true'], os.environ(), '/', 5, false, false, false)!
		assert result.has_status && result.status == 0
	}
	assert descriptors() == before
	// A guest that ignores control-a and SIGTERM must still retire on timeout.
	for amd64 in [false, true] {
		here := work + '/timeout-' + amd64.str()
		os.mkdir_all(here)!
		environment['VINIX_CORE_FIXTURE_WORK'] = here
		environment['VINIX_CORE_FIXTURE_CASE'] = 'resist'
		started := time.sys_mono_now()
		result := corevm.capture([os.executable(), '--guest', if amd64 { 'amd64' } else { 'arm' }], environment, '', 0.2, false, amd64, false)!
		assert !result.has_status && result.forced && !result.finished
		assert time.sys_mono_now() - started < u64(12 * time.second)
		no_process(here + '/leader.pid')!
		no_process(here + '/descendant.pid')!
	}
	println('PASS independent frozen markers, result and environment policies, real PTY controls, large output and 100 descriptor lifetimes')
	flush_stdout()
	for case_name in ['success', 'persist-fail'] {
		here := work + '/vm-' + case_name
		os.mkdir_all(here)!
		environment['VINIX_CORE_FIXTURE_WORK'] = here
		environment['VINIX_CORE_FIXTURE_CASE'] = case_name
		args := [runner, '--root', base.root, '--init', '/guest init', '--initramfs', '/base.tar',
			'--state-dir', here + '/state', '--timeout', '5']
		result := hosttest.capture(args, here + '/run.log', 30, environment)!
		assert result.code == if case_name == 'success' { 0 } else { 1 }
		boots := json2.decode[[]json2.Any](os.read_file(here + '/boots.json')!)!
		assert boots.len == 2
		for index, item in boots {
			row := item.as_map()
			assert row['cwd']!.str() == base.root
			argv := row['argv']!.as_array().map(it.str())
			assert ('--no-build' in argv) == (index == 1 || os.getenv('VINIX_QEMU_CORE_NO_BUILD') == '1')
			guest_env := row['environment']!.as_map()
			assert guest_env['VINIX_QEMU_PERSIST_DISK']!.str() == here + '/state/root.ext2'
		}
	}
	println('PASS two-boot persistence sequence and first/second boot environments')
	flush_stdout()
	// Native executable PATH lookup and the amd64 two-second final-marker window.
	os.write_file(work + '/qemu-fixture', '#!/bin/sh\nexec ' + hosttest.shell_quote(os.executable()) + ' --guest amd64 "$@"\n')!
	os.chmod(work + '/qemu-fixture', 0o755)!
	environment['PATH'] = work + ':' + environment['PATH']
	for case_name in ['success', 'missing', 'nonzero', 'early'] {
		here := work + '/amd64-' + case_name
		os.mkdir_all(here)!
		environment['VINIX_CORE_FIXTURE_WORK'] = here
		environment['VINIX_CORE_FIXTURE_CASE'] = case_name
		started := time.sys_mono_now()
		result := hosttest.capture([runner, '--arch', 'amd64', '--iso', '/core.iso', '--qemu',
			'qemu-fixture', '--firmware', '/firmware', '--timeout', '5', '--cpus', '2'], here + '/run.log', 20, environment)!
		assert result.code == if case_name == 'missing' { 1 } else { 0 }
		argv := json2.decode[[]string](os.read_file(here + '/argv.json')!)!
		assert argv[5] == 'max' && argv[9] == '2'
		if case_name == 'success' {
			assert time.sys_mono_now() - started >= u64(2 * time.second)
		}
	}
	for signal in [2, 15] {
		here := work + '/signal-' + signal.str()
		os.mkdir_all(here)!
		environment['VINIX_CORE_FIXTURE_WORK'] = here
		environment['VINIX_CORE_FIXTURE_CASE'] = 'hang'
		mut child := os.new_process(runner)
		child.set_args(['--root', base.root, '--init', '/init', '--initramfs', '/initramfs',
			'--state-dir', here + '/state', '--timeout', '30'])
		child.set_environment(environment)
		child.set_redirect_stdio()
		defer { child.close() }
		child.run()
		deadline := time.sys_mono_now() + u64(20 * time.second)
		for !os.exists(here + '/descendant.pid') && time.sys_mono_now() < deadline {
			time.sleep(10 * time.millisecond)
		}
		assert os.exists(here + '/descendant.pid')
		assert C.kill(child.pid, signal) == 0
		mut diagnostic := ''
		for child.is_alive() && time.sys_mono_now() < deadline {
			diagnostic += child.stdout_read()
			diagnostic += child.stderr_read()
			time.sleep(10 * time.millisecond)
		}
		os.write_file(here + '/signal.log', diagnostic + '\nalive=' + child.is_alive().str() + '\n')!
		assert !child.is_alive()
		child.wait()
		assert child.code == 128 + signal
		no_process(here + '/leader.pid')!
		no_process(here + '/descendant.pid')!
	}
	println('PASS core marker/argument/environment policies, real PTY flows, reboot sequencing, signals and 100 descriptor lifetimes')
}

pub fn cli(arguments []string) int {
	guard := corevm.own_commands()
	defer { guard.close() }
	if arguments.len > 0 && arguments[0] == '--guest' {
		guest(arguments[1..]) or {
			eprintln(err.msg())
			return 1
		}
		return 0
	}
	if arguments.len != 3 {
		eprintln('usage: test-vm WORK FROZEN_RUNNER NATIVE_RUNNER')
		return 2
	}
	tests(arguments[0], arguments[1], arguments[2]) or {
		eprintln(err.msg())
		return 1
	}
	return 0
}

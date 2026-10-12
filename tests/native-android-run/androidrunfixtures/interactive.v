// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module androidrunfixtures

import androidhost as ah
import androidrun
import androidtools
import cachecli
import encoding.hex
import hosttest
import json2
import os
import time

#include <termios.h>
#include <unistd.h>
#include <signal.h>
struct C.termios {}

fn C.tcgetattr(int, &C.termios) int
fn C.tcsetattr(int, int, &C.termios) int
fn C.cfmakeraw(&C.termios)
fn C.kill(int, int) int
fn C.getpid() int
fn C.read(int, voidptr, usize) isize

pub fn mock_vm() ! {
	mut attributes := C.termios{}
	if C.tcgetattr(0, &attributes) != 0 { return os.error_posix() }
	C.cfmakeraw(&attributes)
	if C.tcsetattr(0, C.TCSANOW, &attributes) != 0 { return os.error_posix() }
	if os.getenv('VINIX_FIXTURE_QMP') != '' { start_qmp_fixture()! }
	transcript := hex.decode(os.getenv('VINIX_FIXTURE_TRANSCRIPT'))!
	mut output := os.stdout()
	unsafe { output.write_full_buffer(transcript.data, usize(transcript.len))! }
	output.flush()
	mut byte := u8(0)
	mut escaped := false
	for C.read(0, &byte, 1) == 1 {
		if escaped && byte == `x` { return }
		escaped = byte == 1
	}
}

fn mock_plan(args map[string]ah.Value, _ ah.Value) !androidrun.Plan {
	mut environment := os.environ()
	environment['VINIX_FIXTURE_TRANSCRIPT'] = ah.field(args, 'fixture_transcript').text().bytes().hex()
	return androidrun.Plan{ command: [os.executable(), '--mock-vm'], environment: environment, directory: ah.field(args, 'repo').text() }
}

fn interrupt_after(milliseconds int) {
	time.sleep(milliseconds * time.millisecond)
	C.kill(C.getpid(), C.SIGINT)
}

fn prepare_noop(mut _ androidrun.Context) !ah.Value { return ah.Value(json2.Null{}) }

fn inputs(root string, directory string) !map[string]ah.Value {
	os.mkdir_all(directory + '/kernel/bin')!
	os.mkdir_all(directory + '/runtime/usr/bin')!
	os.write_file(directory + '/kernel/bin/vinix', 'test kernel snapshot')!
	os.write_file(directory + '/application.apk', 'test APK identity')!
	os.write_file(directory + '/initramfs.tar', 'test boot payload')!
	os.write_file(directory + '/runtime/usr/bin/run-android', '#!/bin/sh\n')!
	os.mkdir(directory + '/session')!
	mut args := androidrun.defaults(root)
	for key, value in {
		'state_dir':    directory + '/session'
		'kernel_dir':   directory + '/kernel'
		'initramfs':    directory + '/initramfs.tar'
		'desktop':      directory + '/application.apk'
		'apk':          directory + '/application.apk'
		'runtime':      directory + '/runtime'
		'runtime_arch': 'aarch64'
		'screenshot':   directory + '/session/application.png'
		'input':        'qmp'
	} {
		args[key] = ah.Value(value)
	}
	args['interactive'] = ah.Value(true)
	args['observe'] = ah.Value(true)
	args['timeout'] = ah.Value(0)
	args['cpus'] = ah.Value(2)
	return args
}

const cases = ['test_ready_waits_for_ctrl_c_without_capturing',
	'test_ctrl_c_before_ready_remains_unchecked',
	'test_optional_autofill_requires_its_verified_preflight',
	'test_optional_autofill_preserves_unchecked_gameplay',
	'test_optional_location_requires_its_verified_preflight',
	'test_optional_location_preserves_unchecked_gameplay',
	'test_egl_queue_pass_text_requires_verified_child_completion',
	'test_egl_queue_verified_retains_fixture_identity_and_unchecked_gameplay',
	'test_interactive_launch_requests_visible_cocoa',
	'test_interactive_state_is_private_even_when_reused']

fn qualify_case(name string, root string, directory string) ! {
	mut args := inputs(root, directory)!
	mut context := androidrun.Context{ root: root, args: args, plan_hook: mock_plan, prepare_hook: prepare_noop }
	defer { context.close() }
	if name == 'test_interactive_launch_requests_visible_cocoa' {
		plan := context.call('vm_plan', {
			'args':    ah.Value(args)
			'overlay': ah.Value(json2.Null{})
		})!.object()
		assert '--serial' !in ah.field(plan, 'command').items().map(it.text())
		environment := ah.field(plan, 'environment').object()
		if os.user_os() == 'macos' {
			assert ah.field(environment, 'QEMU_DISPLAY_BACKEND').text() == 'cocoa'
		}
		assert ah.field(environment, 'VINIX_QEMU_EXTRA').text().contains('-qmp unix:')
		assert os.read_file(directory + '/session/kernel/bin/vinix')! == 'test kernel snapshot'
		return
	}
	if name == 'test_interactive_state_is_private_even_when_reused' {
		context.args['prepare_only'] = ah.Value(true)
		context.args['screenshot'] = ah.Value(json2.Null{})
		os.chmod(directory + '/session', 0o755)!
		assert ah.encode(context.call('main', context.args)!) == '0'
		assert os.stat(directory + '/session')!.mode & 0o777 == 0o700
		return
	}
	mut transcript := 'ANDROID-READY\nANDROID-OBSERVED seconds=30 functionality=unchecked\nANDROID-PASS\n'
	mut expected_status := 0
	mut probe := ''
	mut expected_probe := false
	match name {
		'test_ctrl_c_before_ready_remains_unchecked' {
			transcript = 'ANDROID-START\n'
			expected_status = 1
		}
		'test_optional_autofill_requires_its_verified_preflight' {
			probe = 'autofill_probe'
			transcript = 'ANDROID-READY\nANDROID-OBSERVED seconds=30 functionality=unchecked\ndiagnostic ANDROID-AUTOFILL-VERIFIED was not reached\n'
			expected_status = 1
		}
		'test_optional_autofill_preserves_unchecked_gameplay' {
			probe = 'autofill_probe'
			transcript = 'ANDROID-AUTOFILL-VERIFIED\r\r\nANDROID-READY\n'
			expected_probe = true
		}
		'test_optional_location_requires_its_verified_preflight' {
			probe = 'location_probe'
			transcript = 'ANDROID-READY\nANDROID-OBSERVED seconds=30 functionality=unchecked\ndiagnostic ANDROID-LOCATION-VERIFIED was not reached\n'
			expected_status = 1
		}
		'test_optional_location_preserves_unchecked_gameplay' {
			probe = 'location_probe'
			transcript = 'ANDROID-LOCATION-VERIFIED\r\r\nANDROID-READY\n'
			expected_probe = true
		}
		'test_egl_queue_pass_text_requires_verified_child_completion' {
			probe = 'egl_queue_probe'
			transcript = 'ANDROID-EGL-QUEUE-PASS surface=production\nANDROID-EGL-QUEUE-CHILD status=139\ndiagnostic ANDROID-EGL-QUEUE-VERIFIED was not reached\nANDROID-READY\n'
			expected_status = 1
		}
		'test_egl_queue_verified_retains_fixture_identity_and_unchecked_gameplay' {
			probe = 'egl_queue_probe'
			transcript = 'ANDROID-EGL-QUEUE-CHILD status=0\nANDROID-EGL-QUEUE-VERIFIED\r\r\nANDROID-READY\n'
			expected_probe = true
		}
		else {}
	}
	context.args['fixture_transcript'] = ah.Value(transcript)
	if probe != '' {
		context.args[probe] = ah.field(args, 'apk')
		context.args[probe + '_sha256'] = ah.Value('fixture identity')
	}
	guard := cachecli.own_commands()
	mut interrupt := spawn interrupt_after(450)
	status := context.run_session(ah.Value(json2.Null{}))!
	interrupt.wait()
	guard.close()
	assert status == expected_status
	result := json2.decode[ah.Value](os.read_file(directory + '/session/result.json')!,
		strict: true
	)!.object()
	assert ah.field(result, 'passed') is json2.Null
	assert ah.field(result, 'screenshot') is json2.Null
	assert ah.field(result, 'check').text() == 'interactive-observation'
	assert ah.field(result, 'functionality').text() == 'unchecked'
	assert !os.exists(directory + '/session/application.png') && !os.exists(directory + '/session/ready.png')
	assert !os.exists(directory + '/session/qmp.sock')
	assert os.read_file(directory + '/session/serial.log')! == transcript
	assert ah.field(result, 'observed') == ah.Value(expected_status == 0)
	if probe != '' {
		assert ah.field(result, probe + '_passed') == ah.Value(expected_probe)
		assert ah.field(result, probe + '_sha256').text() == 'fixture identity'
		if !expected_probe {
			assert ah.field(result, 'failure').text().contains('probe did not pass')
		}
		if probe == 'egl_queue_probe' {
			assert ah.encode(ah.field(result, 'egl_queue_probe_exit_status')) == if expected_probe {
				'0'
			} else {
				'139'
			}
		}
	} else if expected_status == 1 {
		assert ah.field(result, 'failure').text().contains('before observing a window')
	}
}

pub fn interactive_cli(root string, argv []string) !int {
	normalized := argv.map(if it == '-k' {
		'--filter'
	} else if it == '-v' {
		'--verbose'
	} else if it == '-q' {
		'--quiet'
	} else {
		it
	})
	args := cachecli.arguments(normalized, ['--filter', '--state-dir'], [], [
		'--verbose',
		'--quiet',
	], 0, -1, 'Native interactive Android supervisor fixtures.\nUsage: interactive-test [-v|-q] [-k FILTER] [InteractiveTest.test_NAME] [--state-dir NEW_DIRECTORY]') or { return androidtools.InputError{err.msg()} }
	for target in args.positional {
		if target != 'InteractiveTest' && target !in cases && target !in cases.map('InteractiveTest.' + it) {
			return error('unknown InteractiveTest selector: ' + target)
		}
	}
	directory := hosttest.work_dir(args.value('--state-dir', ''), 'vinix-android-interactive-')!
	defer { if '--state-dir' !in args.options { hosttest.remove_work_dir(directory) or {} } }
	mut selected := 0
	for name in cases {
		if args.value('--filter', '') != '' && !name.contains(args.value('--filter', '')) {
			continue
		}
		if args.positional.len > 0 && !args.positional.any(it in ['InteractiveTest', name,
			'InteractiveTest.' + name]) {
			continue
		}
		selected++
		qualify_case(name, root, directory + '/' + name)!
		if '--quiet' !in args.options { eprintln(name + ' ... ok') }
	}
	os.write_file(directory + '/passed', 'PASS ' + selected.str() + '\n')!
	eprintln('Ran ' + selected.str() + ' native interactive Android tests\nOK')
	return 0
}

// SPDX-License-Identifier: GPL-2.0-or-later
module main

import campaignhost
import hosttest
import os
import sourcecommand
import time

#include <poll.h>
#include <signal.h>
#include <unistd.h>
#include <termios.h>
struct C.termios {}
fn C.tcgetattr(i32, &C.termios) i32
fn C.cfmakeraw(&C.termios)
fn C.tcsetattr(i32, i32, &C.termios) i32
fn C.kill(i32, i32) i32

struct Signal {
	ready string
	number int
}

fn interrupt_ready(pid int, pointer voidptr) ! {
	context := unsafe { &Signal(pointer) }
	deadline := time.sys_mono_now() + u64(10 * time.second)
	for !os.is_file(context.ready) {
		if sourcecommand.child_exited(pid)! || time.sys_mono_now() > deadline { return error('console child did not become ready') }
		time.sleep(10 * time.millisecond)
	}
	if C.kill(pid, context.number) != 0 { return os.error_posix() }
}

fn child(mode string, ready string) ! {
	if ready != '' { os.write_file(ready, os.getpid().str())! }
	match mode {
		'success' { print('UALLOC-ARM-DONE\n'); flush_stdout() }
		'split' { print('UALLOC-ARM-'); flush_stdout(); time.sleep(20 * time.millisecond); print('DONE\n'); flush_stdout() }
		'bigpass' { print('UALLOC-ARM-DONE\n' + 'x'.repeat(8192)); flush_stdout() }
		'probe-drain' { print('Booting\nSOCKET-OPS-DONE result=0 completed=5\n'); flush_stdout() }
		'probe-bad' { print('SOCKET-OPS-DONE result=1 completed=5\n'); flush_stdout() }
		'probe-no-newline' { print('SOCKET-OPS-DONE result=0 completed=5'); flush_stdout() }
		'panic' { print('KERNEL PANIC\n'); flush_stdout() }
		'exit' { print('natural exit without a marker\n'); flush_stdout(); time.sleep(100 * time.millisecond); return }
		'timeout', 'signal' {}
		else { return error('unknown controlled console mode') }
	}
	// Consume the real PTY escape so ordinary test shutdown does not rely on
	// sleeps or signals. The owner still tests interruption separately.
	mut buffer := [128]u8{}
	mut settings := C.termios{}
	if C.tcgetattr(0, &settings) != 0 { return os.error_posix() }
	C.cfmakeraw(&settings)
	if C.tcsetattr(0, C.TCSANOW, &settings) != 0 { return os.error_posix() }
	for {
		count := C.read(0, &buffer[0], buffer.len)
		if count <= 0 { return }
		if buffer[..int(count)].bytestr().contains('\x01x') {
			if mode == 'probe-drain' { print('SOCKET-OPS shutdown-tail\n'); flush_stdout() }
			return
		}
	}
}

fn cases(tool string, work string) ! {
	os.mkdir(work)!
	for mode in ['success', 'split', 'bigpass', 'panic', 'exit', 'timeout'] {
		state := work + '/' + mode
		os.mkdir(state)!
		command := [tool, state + '/serial.log', state + '/result.json', state, if mode == 'timeout' { '0.2' } else { '10' }, 'UALLOC-ARM-DONE', '--', os.executable(), '--emit', mode, '']
		output := sourcecommand.capture(command, os.environ(), 20, 4 * 1024 * 1024, unsafe { nil })!
		assert output.status == 0, output.str()
		result := campaignhost.read_json(state + '/result.json')!
		assert result['finished']!.bool() == (mode in ['success', 'split', 'bigpass', 'panic'])
		assert result['has_status']!.bool() == (mode == 'exit')
		if mode == 'exit' { assert result['status']!.int() == 0 }
		bytes := os.read_bytes(state + '/serial.log')!
		if mode in ['success', 'split', 'bigpass'] { assert bytes.bytestr().contains('UALLOC-ARM-DONE') }
		if mode == 'panic' { assert bytes.bytestr().contains('KERNEL PANIC') }
	}
	for mode in ['probe-drain', 'probe-bad', 'probe-no-newline'] {
		state := work + '/' + mode
		os.mkdir(state)!
		child_path := state + '/qemu-system-aarch64'
		os.cp(os.executable(), child_path)!
		os.chmod(child_path, 0o755)!
		mut env := os.environ()
		env['VINIX_BOOT_DISK'] = state + '/boot.img'
		command := [tool, '--probe', state + '/serial.log', state + '/result.json', state, if mode == 'probe-no-newline' { '0.2' } else { '10' }, campaignhost.socket_footer('settlement'), '--', child_path, '--emit', mode, '', state + '/boot.img']
		output := sourcecommand.capture(command, env, 20, 4 * 1024 * 1024, unsafe { nil })!
		assert output.status == 0, output.str()
		result := campaignhost.read_json(state + '/result.json')!
		assert result['finished']!.bool() == (mode != 'probe-no-newline')
		raw := os.read_bytes(state + '/serial.log')!
		verdict := campaignhost.socket_probe_verdict(raw, result['finished']!.bool(), 'settlement')
		assert verdict['passed']!.bool() == (mode == 'probe-drain')
		if mode == 'probe-drain' {
			assert raw.bytestr().contains('SOCKET-OPS shutdown-tail')
			assert result['actual_qemu_ps']!.as_array().len == 1
			assert result['actual_qemu_ps']!.as_array()[0].str().contains(child_path) && result['actual_qemu_ps']!.as_array()[0].str().contains(state + '/boot.img')
		}
	}
	for signal in [2, 15] {
		state := work + '/signal-' + signal.str()
		os.mkdir(state)!
		ready := state + '/ready'
		context := Signal{ready, signal}
		command := [tool, state + '/serial.log', state + '/result.json', state, '10', 'UALLOC-ARM-DONE', '--', os.executable(), '--emit', 'signal', ready]
		output := sourcecommand.capture_owned(command, os.environ(), 20, 4 * 1024 * 1024, unsafe { nil }, unsafe { nil }, interrupt_ready, unsafe { &context }, 10)!
		assert output.status == 128 + signal, output.str()
		assert !os.exists(state + '/result.json')
		pid := os.read_file(ready)!.int()
		assert C.kill(pid, 0) != 0, 'PTY child survived interruption'
	}
	root := hosttest.root() + '/tests/alloc-bench/results'
	for path, socket in {'2026-10-02-userspace/validation/allocator-arm-v4': false, '2026-10-03-userspace-v5/validation/allocator-aarch64': false, '2026-10-02-userspace/validation/socket-arm-baseline': true} {
		raw := os.read_bytes(root + '/' + path + '/serial.log')!
		expected := campaignhost.read_json(root + '/' + path + '/run.json')!
		actual := campaignhost.arm_verdict(raw, true, socket)
		for key, value in actual { assert value == expected[key]!, path + ' ' + key }
		assert !campaignhost.arm_verdict(raw, false, socket)['passed']!.bool()
		assert !campaignhost.arm_verdict((raw.bytestr() + '\nKERNEL PANIC\n').bytes(), true, socket)['passed']!.bool()
	}
	println('RECORDED CONSOLE / real PTY / split and large-chunk pass / panic / natural exit / original timeout / complete-line probe / shutdown drain / live process evidence / SIGINT and SIGTERM / child retirement / all three immutable ARM verdicts: PASS')
	flush_stdout()
	os.write_file(work + '/passed', 'PASS\n')!
}

fn main() {
	if os.args.len == 5 && os.args[1] == '--emit' { child(os.args[2], os.args[3]) or { eprintln(err); exit(1) }; return }
	if os.args.len == 4 && os.args[1] == '--emit' { child(os.args[2], os.args[3]) or { eprintln(err); exit(1) }; return }
	if os.args.len != 3 { eprintln('usage: test-recorded-console TOOL NEW_STATE'); exit(2) }
	cases(os.args[1], os.args[2]) or { eprintln(err); exit(1) }
}

// SPDX-License-Identifier: GPL-2.0-or-later
module main

import guesthost
import hosttest
import net.unix
import os
import policyhost
import time

#include <signal.h>
#include <sys/wait.h>
#include <fcntl.h>

fn C.kill(i32, i32) i32
fn C.getppid() i32

fn child(mode string, state string) {
	match mode {
		'one' { println('ONE: PASS') }
		'both' { println('ONE: PASS\nTWO: PASS') }
		'failure' { println('ONE: PASS\nFAIL: late') }
		'nonzero' {
			println('ONE: PASS')
			exit(7)
		}
		'large' { print('x'.repeat(200000) + 'ONE: PASS\nTWO: PASS\n') }
		'silent' { time.sleep(30 * time.second) }
		'reason' { println('policy rejected') }
		'panic' { println('KERNEL PANIC') }
		'userspace', 'init', 'entering' {
			println('KERNEL PANIC\npolicy rejected\n' + match mode {
				'userspace' { 'USERSPACE ENTERED' }
				'init' { 'INIT ENTERED' }
				else { 'Entering userspace' }
			})
		}
		'late' {
			println('KERNEL PANIC\npolicy rejected')
			flush_stdout()
			time.sleep(300 * time.millisecond)
			println('FAIL: late')
		}
		'unsettled' {
			println('KERNEL PANIC\npolicy rejected')
			flush_stdout()
			time.sleep(30 * time.second)
		}
		'panic-exit' {
			println('KERNEL PANIC\npolicy rejected')
			exit(7)
		}
		'signal' {
			C.kill(C.getppid(), C.SIGINT)
			time.sleep(30 * time.second)
		}
		'qmp' {
			mut server := unix.listen_stream(state + '/qmp.sock') or { panic(err) }
			defer { server.close() or {} }
			println('ONE: PASS')
			flush_stdout()
			mut connection := server.accept() or { panic(err) }
			defer { connection.close() or {} }
			connection.write_string('{"QMP":{}}\n') or { panic(err) }
			mut bytes := []u8{len: 4096}
			first := connection.read(mut bytes) or { panic(err) }
			assert bytes[..first].bytestr() == '{"execute":"qmp_capabilities"}\n'
			connection.write_string('{"return":{}}\n') or { panic(err) }
			second := connection.read(mut bytes) or { panic(err) }
			assert bytes[..second].bytestr() == '{"execute":"quit"}\n'
			os.write_file(state + '/qmp-receipt', 'capabilities\nquit\n') or { panic(err) }
		}
		else { panic('Unknown child mode') }
	}
}

fn descriptors() int {
	mut count := 0
	for descriptor in 0 .. 4096 { if C.fcntl(descriptor, C.F_GETFD) >= 0 { count++ } }
	return count
}

fn check(work string, mode string, expected []string, failures []string, timeout int, verdict int) {
	state := work + '/' + mode
	os.mkdir_all(state) or { panic(err) }
	result := guesthost.boot([os.executable(), '--child', mode, state], policyhost.environment(), state,
		expected, failures, timeout, false) or { panic(err) }
	assert result == verdict, mode
	if mode == 'large' {
		log := os.read_bytes(state + '/serial.log') or { panic(err) }
		assert log.len >= 200000 && log.bytestr().contains('TWO: PASS')
	}
}

fn main() {
	if os.args.len > 1 && os.args[1] == '--child' {
		child(os.args[2], os.args[3])
		return
	}
	assert guesthost.replacement_text([u8(0xc3), 0xa9, 0xf0, 0x9f, 0x98, 0x80]) == 'é😀'
	assert guesthost.replacement_text([u8(0xe2), 0x82, `A`]) == '�A'
	assert guesthost.replacement_text([u8(0xe2), 0x82]) == '�'
	assert guesthost.replacement_text([u8(0xed), 0xa0, 0x80]) == '���'
	assert guesthost.replacement_text([u8(0xf4), 0x90, 0x80, 0x80]) == '����'
	assert guesthost.replacement_text([u8(0xc0), 0xaf, 0xff]) == '���'
	work := hosttest.work_dir('', 'vinix-native-guest-verdict-') or { panic(err) }
	defer { hosttest.remove_work_dir(work) or { panic(err) } }
	baseline := descriptors()
	check(work, 'one', ['ONE: PASS', 'TWO: PASS'], ['FAIL:'], 3, 1)
	check(work, 'failure', ['ONE: PASS'], ['FAIL:'], 3, 1)
	check(work, 'nonzero', ['ONE: PASS'], ['FAIL:'], 3, 1)
	check(work, 'large', ['ONE: PASS', 'TWO: PASS'], ['FAIL:'], 3, 0)
	check(work, 'silent', ['ONE: PASS'], ['FAIL:'], 1, 1)
	positive, negative := guesthost.verdict_policy(['ONE: PASS'], []string{}, false)
	check(work, 'panic', positive, negative, 3, 1)
	panic_expected, panic_failures := guesthost.verdict_policy(['policy rejected'], []string{}, true)
	for mode in ['reason', 'panic', 'userspace', 'init', 'entering', 'late', 'panic-exit'] {
		check(work, mode, panic_expected, panic_failures, 3, 1)
	}
	check(work, 'unsettled', panic_expected, panic_failures, 1, 1)
	check(work, 'qmp', ['ONE: PASS'], ['FAIL:'], 6, 0)
	assert os.read_file(work + '/qmp/qmp-receipt') or { panic(err) } == 'capabilities\nquit\n'
	state := work + '/signal'
	os.mkdir_all(state) or { panic(err) }
	guesthost.boot([os.executable(), '--child', 'signal', state], policyhost.environment(), state,
		['ONE: PASS'], ['FAIL:'], 3, false) or { assert err.msg() == 'Guest run interrupted' }
	assert os.is_file(state + '/serial.log')
	missing_state := work + '/missing-executable'
	os.mkdir_all(missing_state) or { panic(err) }
	missing_result := guesthost.boot(['/vinix-no-such-guest-executable'], policyhost.environment(),
		missing_state, ['ONE: PASS'], ['FAIL:'], 3, false) or { panic(err) }
	assert missing_result == 1
	assert (os.read_file(missing_state + '/serial.log') or { panic(err) }).contains('Cannot execute guest runner')
	for index in 0 .. 100 {
		check(work + '/repeat-' + index.str(), 'both', ['ONE: PASS', 'TWO: PASS'], ['FAIL:'], 3, 0)
		assert descriptors() == baseline
	}
	mut status := i32(0)
	assert C.waitpid(-1, &status, C.WNOHANG) == -1 && C.errno == C.ECHILD
	assert descriptors() == baseline
	println('Native guest supervisor: original verdict cases, QMP, SIGINT, failed exec, UTF-8, 100 FD/PID owner retirements: PASS')
}

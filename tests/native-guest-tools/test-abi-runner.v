// SPDX-License-Identifier: GPL-2.0-or-later
module main

import guesthost
import hosttest
import os
import policyhost
import time

#include <termios.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/wait.h>

struct C.termios {}

fn C.tcgetattr(i32, &C.termios) i32
fn C.tcsetattr(i32, i32, &C.termios) i32
fn C.cfmakeraw(&C.termios)
fn C.getppid() i32

fn child(mode string) {
	mut settings := C.termios{}
	assert C.tcgetattr(0, &settings) == 0
	C.cfmakeraw(&settings)
	assert C.tcsetattr(0, C.TCSANOW, &settings) == 0
	if mode == 'signal' { C.kill(C.getppid(), C.SIGINT) }
	if mode == 'silent' || mode == 'signal' {
		for { time.sleep(50 * time.millisecond) }
	}
	if mode != 'missing' { println('ONE: PASS') }
	if mode == 'duplicate' { println('ONE: PASS') }
	if mode == 'invalid' {
		flush_stdout()
		bytes := [u8(0xff), 0, 0xc0]!
		assert C.write(1, &bytes[0], bytes.len) == 3
	}
	if mode == 'large' {
		print('x'.repeat(200000))
		println('TWO: PASS')
	}
	println('GUEST: PASS')
	flush_stdout()
	if mode == 'nonzero' {
		time.sleep(300 * time.millisecond)
		exit(7)
	}
	if mode == 'late' {
		time.sleep(300 * time.millisecond)
		println('FAIL: late')
		flush_stdout()
	}
	mut bytes := [2]u8{}
	mut count := 0
	for count < 2 {
		n := unsafe { C.read(0, &bytes[0] + count, usize(2 - count)) }
		if n <= 0 { exit(1) }
		count += int(n)
	}
	assert bytes == [u8(1), `x`]!
}

fn descriptors() int {
	mut count := 0
	for fd in 0 .. 4096 { if C.fcntl(fd, C.F_GETFD) >= 0 { count++ } }
	return count
}

fn check(work string, mode string, arch string, verdict int) {
	state := work + '/' + arch + '-' + mode
	os.mkdir_all(state) or { panic(err) }
	expected := if mode == 'large' {
		['ONE: PASS', 'TWO: PASS', 'GUEST: PASS']
	} else {
		['ONE: PASS', 'GUEST: PASS']
	}
	result := guesthost.boot_abi([os.executable(), '--child', mode], policyhost.environment(), state, arch,
		expected, 'GUEST: PASS', ['FAIL:'], if mode == 'silent' { 1 } else { 6 }, mode == 'invalid') or { panic(err) }
	assert result == verdict, mode + ' ' + arch
	if mode == 'invalid' {
		bytes := os.read_bytes(state + '/serial.log') or { panic(err) }
		assert bytes.contains(u8(0xff)) && bytes.contains(u8(0)) && bytes.contains(u8(0xc0))
	}
	if mode == 'large' {
		assert (os.read_bytes(state + '/serial.log') or { panic(err) }).len > 200000
	}
}

fn main() {
	if os.args.len > 1 && os.args[1] == '--child' {
		child(os.args[2])
		return
	}
	for arch in ['aarch64', 'x86_64'] {
		assert guesthost.abi_verdict('ONE: PASS GUEST: PASS', arch, ['ONE: PASS', 'GUEST: PASS'], ['FAIL:'], true, false, 0) == 0
		assert guesthost.abi_verdict('ONE: PASS ONE: PASS GUEST: PASS', arch, [
			'ONE: PASS',
			'GUEST: PASS',
		], ['FAIL:'], true, false, 0) == 1
		assert guesthost.abi_verdict('GUEST: PASS', arch, ['ONE: PASS', 'GUEST: PASS'], ['FAIL:'], true, false, 0) == 1
		assert guesthost.abi_verdict('ONE: PASS GUEST: PASS FAIL:', arch, ['ONE: PASS', 'GUEST: PASS'], ['FAIL:'], true, false, 0) == 1
	}
	assert guesthost.abi_verdict('ONE: PASS', 'aarch64', ['ONE: PASS'], []string{}, true, true, 0) == 1
	assert guesthost.abi_verdict('ONE: PASS', 'aarch64', ['ONE: PASS'], []string{}, true, false, 7) == 1
	assert guesthost.abi_verdict('ONE: PASS', 'x86_64', ['ONE: PASS'], []string{}, true, true, 7) == 0
	assert guesthost.abi_verdict('ONE: PASS', 'x86_64', ['ONE: PASS'], []string{}, false, false, 0) == 1
	work := hosttest.work_dir('', 'vinix-abi-verdict-check-') or { panic(err) }
	defer { hosttest.remove_work_dir(work) or { panic(err) } }
	baseline := descriptors()
	for arch in ['aarch64', 'x86_64'] {
		check(work, 'one', arch, 0)
		check(work, 'missing', arch, 1)
		check(work, 'duplicate', arch, 1)
		check(work, 'nonzero', arch, if arch == 'aarch64' { 1 } else { 0 })
		check(work, 'silent', arch, 1)
		check(work, 'large', arch, 0)
	}
	check(work, 'late', 'x86_64', 1)
	check(work, 'invalid', 'aarch64', 0)
	state := work + '/signal'
	os.mkdir(state) or { panic(err) }
	guesthost.boot_abi([os.executable(), '--child', 'signal'], policyhost.environment(), state, 'aarch64',
		['ONE: PASS'], 'ONE: PASS', []string{}, 3, false) or { assert err.msg() == 'Guest run interrupted' }
	assert os.is_file(state + '/serial.log')
	for index in 0 .. 100 {
		check(work + '/repeat-' + index.str(), 'one', 'aarch64', 0)
		assert descriptors() == baseline
	}
	mut status := i32(0)
	assert C.waitpid(-1, &status, C.WNOHANG) == -1 && C.errno == C.ECHILD
	assert descriptors() == baseline
	println('ABI exact counts, architecture-specific exits, deadlines, late failure, large PTY, SIGINT and 100 FD/PID retirements: PASS')
}

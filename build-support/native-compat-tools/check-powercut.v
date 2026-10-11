// SPDX-License-Identifier: GPL-2.0-or-later
module main

import guesthost
import hosttest
import os
import policyhost
import time

#include <termios.h>
#include <signal.h>
#include <fcntl.h>
#include <sys/wait.h>
struct C.termios {}
fn C.tcgetattr(i32, &C.termios) i32
fn C.tcsetattr(i32, i32, &C.termios) i32
fn C.cfmakeraw(&C.termios)
fn C.getppid() i32

fn graceful(_signal i32) { C.write(1, c'GRACEFUL SHUTDOWN\n', 18); C._exit(0) }

fn child(mode string) {
	mut settings := C.termios{}
	assert C.tcgetattr(0, &settings) == 0
	C.cfmakeraw(&settings)
	assert C.tcsetattr(0, C.TCSANOW, &settings) == 0
	unsafe { C.signal(C.SIGTERM, voidptr(graceful)) }
	if mode == 'signal' { C.kill(C.getppid(), C.SIGINT) }
	if mode in ['silent', 'signal'] { for { time.sleep(50 * time.millisecond) } }
	if mode != 'missing' { println('EPOCH START') }
	if mode == 'large' { print('x'.repeat(200000)) }
	if mode == 'invalid' {
		bytes := [u8(0xff), 0, 0xc0]!
		assert C.write(1, &bytes[0], 3) == 3
	}
	if mode == 'failure' { println('FAIL END') }
	if mode == 'wrong' { println('EPOCH DONE wrong ino=0') }
	print('EPOCH DONE full ino=184467440737095516160')
	flush_stdout()
	if mode == 'partial' { for { time.sleep(50 * time.millisecond) } }
	time.sleep(50 * time.millisecond)
	println('\r\r')
	flush_stdout()
	mut byte := u8(0)
	if C.read(0, &byte, 1) > 0 { println('GRACEFUL SHUTDOWN'); flush_stdout() }
	for { time.sleep(50 * time.millisecond) }
}

fn descriptors() int {
	mut count := 0
	for fd in 0 .. 4096 { if C.fcntl(fd, C.F_GETFD) >= 0 { count++ } }
	return count
}

fn policy(arm bool) guesthost.PowercutPolicy {
	return guesthost.PowercutPolicy{ start: 'EPOCH START', done: 'EPOCH DONE', phase: 'full',
		failures: ['FAIL END', 'KERNEL PANIC'], lookback: if arm { 8192 } else { 0 }, failure_newline: !arm }
}

fn check(work string, mode string, arm bool, verdict int) {
	state := work + '/' + mode + '-' + arm.str()
	os.mkdir_all(state) or { panic(err) }
	result := guesthost.boot_powercut([os.executable(), '--child', mode], policyhost.environment(), state,
		policy(arm), if mode in ['silent', 'partial'] { 1 } else { 4 }, !arm, mode == 'invalid') or { panic(err) }
	assert result == verdict, mode
	bytes := os.read_bytes(state + '/serial.log') or { panic(err) }
	assert !bytes.bytestr().contains('GRACEFUL SHUTDOWN')
	if mode == 'invalid' { assert bytes.contains(u8(0xff)) && bytes.contains(u8(0)) && bytes.contains(u8(0xc0)) }
	if mode == 'large' { assert bytes.len > 200000 }
}

fn main() {
	if os.args.len > 1 && os.args[1] == '--child' { child(os.args[2]); return }
	work := hosttest.work_dir('', 'vinix-powercut-check-') or { panic(err) }
	defer { hosttest.remove_work_dir(work) or { panic(err) } }
	baseline := descriptors()
	for arm in [true, false] {
		for mode in ['one', 'large', 'invalid'] { check(work, mode, arm, 0) }
		for mode in ['missing', 'wrong', 'failure', 'partial', 'silent'] { check(work, mode, arm, 1) }
		state := work + '/signal-' + arm.str()
		os.mkdir(state) or { panic(err) }
		mut saw_interrupt := false
		guesthost.boot_powercut([os.executable(), '--child', 'signal'], policyhost.environment(), state, policy(arm), 4, !arm, false) or {
			assert err.msg() == 'Guest run interrupted'
			saw_interrupt = true
		}
		assert saw_interrupt
		for index in 0 .. 30 { check(work + '/repeat-' + index.str(), 'one', arm, 0); assert descriptors() == baseline }
	}
	mut status := i32(0)
	assert C.waitpid(-1, &status, C.WNOHANG) == -1 && C.errno == C.ECHILD
	assert descriptors() == baseline
	println('Power-cut raw bytes, complete regex, two capture policies, SIGKILL, deadlines, SIGINT and 60 FD/PID retirements PASS')
}

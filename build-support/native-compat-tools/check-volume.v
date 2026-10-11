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

fn graceful(_signal i32) {
	C.write(1, c'GRACEFUL SHUTDOWN\n', 18)
	C._exit(0)
}

fn child(mode string) {
	mut settings := C.termios{}
	assert C.tcgetattr(0, &settings) == 0
	C.cfmakeraw(&settings)
	assert C.tcsetattr(0, C.TCSANOW, &settings) == 0
	unsafe { C.signal(C.SIGTERM, voidptr(graceful)) }
	if mode == 'signal' { C.kill(C.getppid(), C.SIGINT) }
	if mode in ['silent', 'signal'] {
		for { time.sleep(50 * time.millisecond) }
	}
	if mode != 'missing' { println('VOLUME START') }
	if mode == 'large' { print('x'.repeat(200000)) }
	if mode == 'invalid' {
		bytes := [u8(0xff), 0, 0xc0]!
		assert C.write(1, &bytes[0], 3) == 3
	}
	if mode == 'failure' { println('FAIL END') }
	if mode == 'wrong' { println('VOLUME DONE wrong ino=0') }
	print('VOLUME DONE full ino=184467440737095516160')
	flush_stdout()
	if mode == 'partial' {
		for { time.sleep(50 * time.millisecond) }
	}
	time.sleep(50 * time.millisecond)
	println('\r\r')
	flush_stdout()
	// A monitor quit or SIGTERM would leave proof; only SIGKILL passes.
	mut byte := u8(0)
	if C.read(0, &byte, 1) > 0 {
		println('GRACEFUL SHUTDOWN')
		flush_stdout()
	}
	for { time.sleep(50 * time.millisecond) }
}

fn descriptors() int {
	mut count := 0
	for fd in 0 .. 4096 { if C.fcntl(fd, C.F_GETFD) >= 0 { count++ } }
	return count
}

fn check(work string, mode string, verdict int) {
	state := work + '/' + mode
	os.mkdir_all(state) or { panic(err) }
	result := guesthost.boot_volume([os.executable(), '--child', mode], policyhost.environment(), state,
		if mode in ['silent', 'partial'] { 1 } else { 4 }, mode == 'invalid') or { panic(err) }
	assert result == verdict, mode
	bytes := os.read_bytes(state + '/serial.log') or { panic(err) }
	assert !bytes.bytestr().contains('GRACEFUL SHUTDOWN')
	if mode == 'invalid' {
		assert bytes.contains(u8(0xff)) && bytes.contains(u8(0)) && bytes.contains(u8(0xc0))
	}
	if mode == 'large' {
		assert bytes.len > 200000
	}
}

fn main() {
	if os.args.len > 1 && os.args[1] == '--child' {
		child(os.args[2])
		return
	}
	for text in ['VOLUME DONE full ino=\n', 'VOLUME DONE full ino=1', 'VOLUME DONE full ino=1\r',
		'VOLUME DONE f-ull ino=1\n', 'VOLUME DONE full ino=-1\n'] {
		if _ := guesthost.volume_done(text) { panic('Malformed completion accepted') }
	}
	assert guesthost.volume_done('xVOLUME DONE f_01 ino=000\r\r\n') or { panic('regex') } == 'f_01'
	assert guesthost.volume_done('VOLUME DONE full ino=0\nVOLUME DONE other ino=1\n') or { panic('first') } == 'full'
	assert guesthost.volume_verdict('VOLUME START\nVOLUME DONE full ino=0\r\n') == 0
	assert guesthost.volume_verdict('VOLUME START\nVOLUME DONE other ino=0\nVOLUME DONE full ino=1\n') == 1
	assert guesthost.volume_verdict('VOLUME START\nVOLUME DONE full ino=0\nKERNEL PANIC') == 1
	work := hosttest.work_dir('', 'vinix-volume-supervisor-check-') or { panic(err) }
	defer { hosttest.remove_work_dir(work) or { panic(err) } }
	baseline := descriptors()
	for mode in ['one', 'large', 'invalid'] { check(work, mode, 0) }
	for mode in ['missing', 'wrong', 'failure', 'partial', 'silent'] { check(work, mode, 1) }
	os.mkdir(work + '/signal') or { panic(err) }
	mut saw_interrupt := false
	guesthost.boot_volume([os.executable(), '--child', 'signal'], policyhost.environment(), work + '/signal', 4, false) or {
		assert err.msg() == 'Guest run interrupted'
		saw_interrupt = true
	}
	assert saw_interrupt
	for index in 0 .. 100 {
		check(work + '/repeat-' + index.str(), 'one', 0)
		assert descriptors() == baseline
	}
	mut status := i32(0)
	assert C.waitpid(-1, &status, C.WNOHANG) == -1 && C.errno == C.ECHILD
	assert descriptors() == baseline
	println('Volume complete-line regex, raw bytes, power cuts, deadlines, SIGINT and 100 FD/PID retirements PASS')
}

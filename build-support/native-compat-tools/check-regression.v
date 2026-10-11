// SPDX-License-Identifier: GPL-2.0-or-later
module main

import fixturehost
import guesthost
import hosttest
import os
import policyhost
import time

#include <sys/wait.h>
#include <errno.h>
fn C.waitpid(i32, &i32, i32) i32
fn C.getppid() i32
fn C.kill(i32, i32) i32

fn main() {
	if os.args.len > 1 && os.args[1] == '--child' {
		mode := os.args[2]
		if mode == 'zero' { println('CPU-CHECK DONE failures=0'); exit(73) }
		if mode == 'late-fail' { println('CPU-CHECK DONE failures=0'); println('CPU-CHECK FAIL late'); flush_stdout() }
		if mode == 'partial' { println('CPU-CHECK DONE'); flush_stdout() }
		if mode == 'live' || mode == 'interrupt' {
			println('REGRESSION LIVE LOG'); flush_stdout()
			time.sleep(300 * time.millisecond)
			if !(os.read_file(os.args[3]) or { panic(err) }).contains('REGRESSION LIVE LOG') { exit(91) }
			if mode == 'interrupt' { C.kill(C.getppid(), C.SIGINT) } else { println('CPU-CHECK DONE failures=0'); exit(73) }
		}
		if mode == 'ignore-term' { unsafe { C.signal(C.SIGTERM, C.SIG_IGN) } }
		for { time.sleep(time.second) }
	}
	work := hosttest.work_dir('', 'vinix-regression-check-') or { panic(err) }
	defer { hosttest.remove_work_dir(work) or { eprintln(err.msg()) } }
	for mode in ['zero', 'late-fail', 'partial', 'timeout'] {
		os.mkdir(work + '/' + mode) or { panic(err) }
		start := time.sys_mono_now()
		data := guesthost.boot_check([os.executable(), '--child', mode], policyhost.environment(), work + '/' + mode,
			'CPU-CHECK DONE', 0.3) or { panic(err) }
		elapsed := f64(time.sys_mono_now() - start) / 1e9
		if mode == 'zero' { assert data.bytestr().contains('CPU-CHECK DONE failures=0') }
		if mode == 'late-fail' { assert data.bytestr().contains('CPU-CHECK FAIL late') }
		if mode == 'partial' { assert !data.bytestr().contains('failures=0') }
		if mode == 'timeout' { assert elapsed >= 0.3 && elapsed < 2 }
		assert os.read_bytes(work + '/' + mode + '/serial.log') or { panic(err) } == data
	}
	os.mkdir(work + '/ignore-term') or { panic(err) }
	start := time.sys_mono_now()
	guesthost.boot_check([os.executable(), '--child', 'ignore-term'], policyhost.environment(), work + '/ignore-term',
		'CPU-CHECK DONE', 0.3) or { panic(err) }
	assert f64(time.sys_mono_now() - start) / 1e9 >= 10.3
	fd_before := os.ls('/dev/fd') or { panic(err) }
	for index in 0 .. 30 {
		state := work + '/repeat-' + index.str()
		os.mkdir(state) or { panic(err) }
		guesthost.boot_check([os.executable(), '--child', 'zero'], policyhost.environment(), state,
			'CPU-CHECK DONE', 1.0) or { panic(err) }
		mut status := i32(0)
		assert C.waitpid(-1, &status, C.WNOHANG) == -1 && C.errno == C.ECHILD
	}
	assert (os.ls('/dev/fd') or { panic(err) }).len == fd_before.len
	for mode in ['live', 'interrupt'] {
		state := work + '/' + mode
		os.mkdir(state) or { panic(err) }
		log := work + '/' + mode + '.log'
		if data := guesthost.boot_check_log([os.executable(), '--child', mode, log], policyhost.environment(), state,
			'CPU-CHECK DONE', 2.0, log) {
			assert mode == 'live' && data.bytestr().contains('CPU-CHECK DONE failures=0')
		} else { assert mode == 'interrupt' && err.msg().contains('interrupted') }
		assert (os.read_file(log) or { panic(err) }).contains('REGRESSION LIVE LOG')
	}
	if os.args.len == 2 {
		for family in ['kernel-cpu', 'kernel-job-control', 'kernel-sysvmsg', 'kernel-retention', 'stack-protector', 'elf-text', 'elf-text-host', 'userland-demo', 'uname'] {
			for pair in [['--help', '0'], ['--unknown', '2']] {
				result := fixturehost.capture_both_preferred([os.args[1], family, pair[0]], policyhost.environment(), policyhost.caller_arch()) or { panic(err) }
				assert result.status.str() == pair[1]
			}
		}
	}
	println('Regression fractional deadlines, raw logs, nonzero child exit, partial/late verdicts and TERM/KILL retirement PASS')
}

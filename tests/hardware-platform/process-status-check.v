// SPDX-License-Identifier: GPL-2.0-or-later
// Explicit checks remain active under -prod. No VM or shell is started.
module main

import hwhost
import os
import time

#include <errno.h>
#include <signal.h>
#include <sys/wait.h>

// Match tools/packages/audiopcm/native.c.v. This declaration deliberately
// excludes the retained compiler's implicit builtin &int output bridge.
fn C.waitpid(int, &i32, int) int

struct StatusSlot {
mut:
	before [8]u8
	status i32
	after [8]u8
}

fn status_require(ok bool, message string) ! {
	if !ok { return error(message) }
}

fn status_slot() StatusSlot {
	return StatusSlot{before: [u8(0xa7), 0x32, 0x90, 0x15, 0x4c, 0xe2, 0x61, 0x8b]!,
		status: i32(-991), after: [u8(0xd8), 0x43, 0x16, 0xa9, 0x70, 0x2f, 0xbc, 0x05]!}
}

fn status_guards(slot &StatusSlot) ! {
	expected := status_slot()
	status_require(sizeof(i32) == 4 && usize(unsafe { &slot.after[0] }) - usize(unsafe { &slot.status }) == 4,
		'status slot has no adjacent four-byte boundary')!
	status_require(slot.before == expected.before && slot.after == expected.after,
		'waitpid changed adjacent canaries')!
}

fn status_wait(pid int, mut slot StatusSlot) int {
	for {
		C.errno = 0
		got := C.waitpid(pid, &slot.status, C.WNOHANG)
		if got >= 0 || C.errno != C.EINTR { return got }
	}
	return -1
}

fn status_echild(pid int) ! {
	mut slot := status_slot()
	got := status_wait(pid, mut slot)
	saved_errno := int(C.errno)
	status_require(got == -1 && saved_errno == C.ECHILD && slot.status == -991,
		'completed child is not reaped with an unchanged ECHILD slot')!
	status_guards(&slot)!
}

fn status_collect(mut child hwhost.Child) ! {
	started := time.sys_mono_now()
	for !child.poll() {
		status_require(time.sys_mono_now() - started < 5 * time.second, 'poll completion deadline')!
		time.sleep(time.millisecond)
	}
}

fn status_one(root string, name string, code int, signal int, external bool) ! {
	ready := root + '/' + name + '.ready'
	release := root + '/' + name + '.release'
	mut child := hwhost.start_child([os.executable(), '--child', ready, release, code.str()],
		map[string]string{}, root + '/' + name + '.child.log')!
	mut completed := false
	defer {
		// This fixture owns the direct self-child. Its readiness/release
		// deadline also bounds it; the outer runner owns its inherited group.
		if !completed { child.stop() }
	}
	started := time.sys_mono_now()
	for !os.exists(ready) {
		status_require(!child.poll(), 'child ended before its readiness barrier')!
		status_require(time.sys_mono_now() - started < 5 * time.second, 'readiness deadline')!
		time.sleep(time.millisecond)
	}
	status_require(os.read_file(ready)! == 'ready\n', 'wrong child readiness token')!
	status_require(!child.poll() && child.outcome() == 'still running' && child.exit_code() == -1,
		'live poll was interpreted as completion')!
	mut pending := status_slot()
	status_require(status_wait(child.pid, mut pending) == 0 && pending.status == -991,
		'raw WNOHANG did not preserve live status')!
	status_guards(&pending)!
	if signal != 0 {
		status_require(C.kill(child.pid, signal) == 0, 'owned child signal failed')!
	} else {
		os.write_file(release, 'release\n')!
	}
	if external {
		mut slot := status_slot()
		mut waited := 0
		external_started := time.sys_mono_now()
		for {
			waited = status_wait(child.pid, mut slot)
			if waited != 0 { break }
			status_require(time.sys_mono_now() - external_started < 5 * time.second, 'external reap deadline')!
			time.sleep(time.millisecond)
		}
		status_require(waited == child.pid && slot.status == i32(code << 8), 'external wait result differs')!
		status_guards(&slot)!
	}
	status_collect(mut child)!
	completed = true
	expected_outcome := if external { 'lost' } else if signal != 0 {
		'killed by signal ' + signal.str()
	} else { 'exit status ' + code.str() }
	expected_code := if external || signal != 0 { -1 } else { code }
	status_require(child.outcome() == expected_outcome && child.exit_code() == expected_code,
		'public child outcome differs for ' + name + ': ' + child.outcome())!
	status_echild(child.pid)!
	for _ in 0 .. 3 {
		status_require(child.poll() && child.outcome() == expected_outcome && child.exit_code() == expected_code,
			'cached completion changed for ' + name)!
		status_echild(child.pid)!
	}
	println('PASS ' + name + ' live/WNOHANG/outcome/repeat/ECHILD/canaries')
}

fn status_check(root string) ! {
	status_require(sizeof(int) == 8 && sizeof(i32) == 4, 'selected compiler does not reproduce int width')!
	status_require(os.is_dir(root) && os.ls(root)!.len == 0, 'requires a new empty result directory')!
	for code in [0, 37, 255] { status_one(root, 'exit-' + code.str(), code, 0, false)! }
	status_one(root, 'sigterm', 0, int(C.SIGTERM), false)!
	status_one(root, 'sigkill', 0, int(C.SIGKILL), false)!
	status_one(root, 'externally-reaped', 23, 0, true)!
	println('HWHOST status explicit-i32 normal/255/signal/live/repeat/lost/ECHILD PASS')
}

fn main() {
	if os.args.len == 5 && os.args[1] == '--child' {
		pending := os.args[2] + '.pending'
		os.write_file(pending, 'ready\n') or { C._exit(91) }
		os.rename(pending, os.args[2]) or { C._exit(91) }
		started := time.sys_mono_now()
		for !os.exists(os.args[3]) {
			if time.sys_mono_now() - started >= 5 * time.second { C._exit(92) }
			time.sleep(time.millisecond)
		}
		C._exit(os.args[4].int())
	}
	if os.args.len != 2 { eprintln('requires an empty output directory'); exit(2) }
	status_check(os.args[1]) or { eprintln(err); exit(1) }
}

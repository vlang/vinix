// SPDX-License-Identifier: GPL-2.0-only
module applehost

import hosttest
import os

fn test_native_cli_guards_precede_owner_creation() {
	for arguments in [['--arch', 'aarch64'], ['--host-arch', 'bad'], ['--timeout', 'bad'],
		['--timeout', '-1'], ['--vm'], ['--vm', '--arch', 'x86_64', '--kernel-dir', '/tmp']] {
		if _ := runtime('wifi-control', arguments) { assert false } else { assert err.code() == 2 }
	}
	if _ := runtime('spi', ['--arch', 'aarch64', '--kernel-dir', '/tmp', '--guest-state-dir', '/tmp']) {
		assert false
	} else { assert err.code() == 2 }
}

fn test_fixed_private_owner_and_retained_literal_state() {
	work := hosttest.work_dir('', 'vinix-apple-owner-test-')!
	defer { hosttest.remove_work_dir(work) or { panic(err) } }
	previous := os.getenv_opt('TMPDIR')
	os.setenv('TMPDIR', work, true)
	defer {
		if value := previous { os.setenv('TMPDIR', value, true) } else { os.unsetenv('TMPDIR') }
	}
	for _ in 0 .. 20 {
		r := runtime('wifi-control', [])!
		assert r.owned && r.work.starts_with('/tmp/vinix-wifi-control-')
		assert os.stat(r.work)!.mode & 0o777 == 0o700
		r.close()!
		assert !os.exists(r.work) && os.ls(work)!.len == 0
	}
	state := work + '/literal\\component\nretained'
	r := runtime('wifi-control', ['--state-dir', state])!
	assert !r.owned && r.work.ends_with('/literal\\component\nretained')
	r.close()!
	assert os.is_dir(state)
	if _ := runtime('wifi-control', ['--state-dir', state]) { assert false } else {
		assert err.msg().contains('already exists')
	}
	if _ := runtime('wifi-control', ['--state-dir', '']) { assert false } else {
		assert err.msg().contains('already exists')
		assert err !is FrontendError
	}
}

fn owner_signal(_signal i32) {}

fn test_interrupt_scope_restores_previous_handler() {
	old := C.signal(C.SIGINT, voidptr(owner_signal))
	defer { C.signal(C.SIGINT, old) }
	r := runtime('wifi-control', [])!
	assert !apple_suite_cancelled()
	apple_suite_signal(C.SIGINT)
	assert apple_suite_cancelled()
	r.close()!
	assert C.signal(C.SIGINT, voidptr(owner_signal)) == voidptr(owner_signal)
	assert !os.exists(r.work)
}

// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

fn qualify_package_keygen(mut t Test) ! {
	package_disk_mount()!
	path := package_disk + '/publisher-recovery.seed'
	if !os.exists(path) && !os.is_link(path) {
		key := package_success(['keygen', path])!.trim_space()
		assert key.len == 64 && key.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
		t.say('PACKAGE KEYGEN PUBLIC ${key}')
		// No extra sync, metadata write or orderly shutdown follows keygen.
		package_crash_checkpoint('keygen')
		return error('key generation cut did not stop the guest')
	}
	before := os.read_file(path)!
	info := os.lstat(path)!
	assert info.mode & 0o777 == 0o600 && info.uid == 0 && before.len == 65
	key := package_success(['key-public', path])!.trim_space()
	assert key.len == 64
	refused := run(['/usr/bin/vinix-package', 'keygen', path], '', none, none)
	assert refused.status == 1 && refused.output.contains('already exists')
	assert os.read_file(path)! == before
	assert !os.ls(package_disk)!.any(it.starts_with('.package-key-'))
	t.say('PACKAGE KEYGEN RECOVERY ${key} private-file existing-refusal unchanged-content PASS')
}

fn scenario_package_keygen(mut t Test) {
	qualify_package_keygen(mut t) or { t.check(false, err.msg()) }
}

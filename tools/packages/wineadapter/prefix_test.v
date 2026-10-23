// SPDX-License-Identifier: GPL-2.0-or-later
module wineadapter

import os

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
}

fn refused(data string, builtins string) bool {
	mut prefix := prepare_prefix(data, builtins) or { unsafe { err.free() }; return true }
	prefix.close()
	return false
}

fn test_private_prefix_links_policy_and_identity() {
	if C.geteuid() == 0 || os.getegid() == 0 { panic('run Wine prefix tests under an ordinary host account') }
	temporary := os.real_path(os.temp_dir()) + '/vinix-wine-prefix-' + os.getpid().str()
	defer { os.rmdir_all(temporary) or {}; unsafe { temporary.free() } }
	os.mkdir_all(temporary)!
	data := temporary + '/data'
	builtins := temporary + '/builtins'
	defer { unsafe { data.free(); builtins.free() } }
	os.mkdir(data)!
	os.chown(data, int(C.geteuid()), os.getegid())!
	os.chmod(data, 0o700)!
	os.mkdir(builtins)!
	os.write_file(builtins + '/kernel32.dll', 'signed builtin')!
	mut prefix := prepare_prefix(data, builtins)!
	prefix.recheck(data)!
	assert os.read_file(data + '/wine/.update-timestamp')! == 'disable\n'
	assert os.readlink(data + '/wine/dosdevices/c:')! == '../drive_c'
	assert os.readlink(data + '/wine/drive_c/windows/system32/kernel32.dll')! == builtins + '/kernel32.dll'
	prefix.close(); prefix.close()
	mut repeated := prepare_prefix(data, builtins)!
	repeated.close()
	// Exercise the real capture/mkdir/link/read/recheck path repeatedly. No
	// descriptor or parent V allocation may survive a closed prefix.
	baseline_fd := C.open(c'/dev/null', C.O_RDONLY | C.O_CLOEXEC)
	assert baseline_fd >= 0
	C.close(baseline_fd)
	$if track_heap ? { C.vinix_heap_begin() }
	for _ in 0 .. 1000 {
		mut value := prepare_prefix(data, builtins)!
		value.recheck(data)!
		value.close()
		value.close()
	}
	$if track_heap ? {
		assert C.vinix_heap_end() == 0
	}
	final_fd := C.open(c'/dev/null', C.O_RDONLY | C.O_CLOEXEC)
	assert final_fd == baseline_fd
	C.close(final_fd)
	// Exercise every additional format shipped by the pinned Wine inventory.
	// Keep these outside the measured single-builtin allocation control.
	for suffix in ['exe', 'sys', 'cpl', 'drv', 'ocx', 'ax', 'tlb', 'ds', 'com', 'acm', 'msstyles']! {
		name := 'builtin.' + suffix
		path := builtins + '/' + name
		os.write_file(path, 'signed builtin')!
		mut allowed := prepare_prefix(data, builtins)!
		allowed.close()
		assert os.readlink(data + '/wine/drive_c/windows/system32/' + name)! == path
		os.rm(path)!
		unsafe { name.free(); path.free() }
	}
	os.write_file(builtins + '/unexpected.txt', 'not a Windows builtin')!
	assert refused(data, builtins)
	os.rm(builtins + '/unexpected.txt')!
	os.chmod(data + '/wine', 0o755)!
	assert refused(data, builtins)
	os.chmod(data + '/wine', 0o700)!
	os.write_file(data + '/wine/.update-timestamp', 'enable!\n')!
	assert refused(data, builtins)
	os.write_file(data + '/wine/.update-timestamp', 'disable\n')!
	os.rm(data + '/wine/dosdevices/c:')!
	os.symlink('/tmp', data + '/wine/dosdevices/c:')!
	assert refused(data, builtins)
	os.rm(data + '/wine/dosdevices/c:')!
	os.symlink('../drive_c', data + '/wine/dosdevices/c:')!
	mut captured := prepare_prefix(data, builtins)!
	os.mv(data + '/wine', data + '/old-wine')!
	os.mkdir(data + '/wine')!
	os.chmod(data + '/wine', 0o700)!
	mut rejected := false
	captured.recheck(data) or { unsafe { err.free() }; rejected = true }
	assert rejected
	captured.close()
	os.rmdir_all(data + '/wine')!
	os.symlink(data + '/old-wine', data + '/wine')!
	assert refused(data, builtins)
	os.rm(data + '/wine')!
	os.mv(data + '/old-wine', data + '/wine')!
	os.chmod(data, 0o755)!
	assert refused(data, builtins)
	os.chmod(data, 0o700)!
	assert refused(data + '/../data', builtins)
	assert refused(data, temporary + '/missing')
}

fn test_patch_refuses_unpinned_or_duplicate_formats() {
	for input in ['', '/tmp/.wine-%u\x00', '/tmp/.wine-%u\x00/tmp/.wine-%u\x00']! {
		mut rejected := false
		private_server_patch(input, false) or { unsafe { err.free() }; rejected = true; '' }
		assert rejected
	}
}

// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import encoding.binary

fn C.socketpair(i32, i32, i32, &i32) i32
fn C.pipe(&i32) i32

fn fixture_profile(label string) !string {
	path := os.real_path(os.temp_dir()) + '/vinix-webview-${os.getpid()}-${label}'
	os.mkdir(path)!
	os.chmod(path, 0o700)!
	return path
}

fn rejected_profile(path string) bool {
	profile(path) or { return true }
	return false
}

fn test_profile_rejects_public_and_linked_storage() {
	path := fixture_profile('permissions')!
	defer { os.rmdir_all(path) or {} }
	assert profile(path)! == path
	for name in ['data', 'cache'] {
		assert os.lstat(path + '/' + name)!.mode & 0o7777 == 0o700
	}
	os.chmod(path, 0o755)!
	assert rejected_profile(path)
	os.chmod(path, 0o700)!
	os.rmdir(path + '/cache')!
	os.symlink(path + '/data', path + '/cache')!
	assert rejected_profile(path)
	assert rejected_profile(path + '/..')
}

fn test_profile_lock_excludes_second_engine_and_rejects_aliases() {
	path := fixture_profile('lock')!
	defer { os.rmdir_all(path) or {} }
	profile(path)!
	fd := lock_profile(path)!
	mut rejected := false
	other := lock_profile(path) or {
		rejected = true
		-1
	}
	assert rejected
	assert other == -1
	C.close(i32(fd))
	second := lock_profile(path)!
	C.close(i32(second))
	os.rm(path + '/engine.lock')!
	os.symlink(path + '/data', path + '/engine.lock')!
	mut refused := false
	lock_profile(path) or { refused = true }
	assert refused
}

fn test_private_cookie_files_reject_public_permissions_and_links() {
	path := fixture_profile('cookie-files')!
	defer { os.rmdir_all(path) or {} }
	jar := path + '/cookies.sqlite'
	private_file(jar)!
	os.write_file(jar, '')!
	os.chmod(jar, 0o600)!
	private_file(jar)!
	os.chmod(jar, 0o644)!
	mut rejected := false
	private_file(jar) or { rejected = true }
	assert rejected
	os.rm(jar)!
	os.symlink(path + '/missing', jar)!
	rejected = false
	private_file(jar) or { rejected = true }
	assert rejected
}

fn test_control_authenticates_stream_and_sets_descriptor_flags() {
	mut sockets := [2]i32{}
	assert C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &sockets[0]) == 0
	defer {
		C.close(sockets[0])
		C.close(sockets[1])
	}
	control(int(sockets[0]))!
	assert C.fcntl(sockets[0], C.F_GETFD) & C.FD_CLOEXEC != 0
	assert C.fcntl(sockets[0], C.F_GETFL) & C.O_NONBLOCK != 0
	mut pipes := [2]i32{}
	assert C.pipe(&pipes[0]) == 0
	defer {
		C.close(pipes[0])
		C.close(pipes[1])
	}
	mut refused := false
	control(int(pipes[0])) or { refused = true }
	assert refused
}

fn test_scroll_validates_both_axes_before_injection() {
	mut bytes := []u8{len: 8}
	binary.little_endian_put_u32(mut bytes[..4], u32(i32(-32)))
	binary.little_endian_put_u32(mut bytes[4..], 32)
	assert scroll_steps(bytes)! == [i32(-32), i32(32)]!
	binary.little_endian_put_u32(mut bytes[4..], 33)
	mut rejected := false
	scroll_steps(bytes) or { rejected = true }
	assert rejected
}

fn wide_type_fixture() u64 {
	return u64(0x123456780000)
}

fn wide_constructor_fixture(kind u64, _ &char, _ voidptr, _ voidptr) voidptr {
	return voidptr(kind)
}

fn test_gobject_type_keeps_pointer_width_across_resolved_api() {
	// The real APIs are cast from dlsym pointers. Exercise that same call
	// boundary with a GType whose high word is nonzero.
	getter := unsafe { Type(voidptr(wide_type_fixture)) }
	constructor := unsafe { NewView(voidptr(wide_constructor_fixture)) }
	kind := getter()
	assert kind == u64(0x123456780000)
	assert u64(constructor(kind, c'network-session', unsafe { nil }, unsafe { nil })) == kind
}

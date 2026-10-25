// SPDX-License-Identifier: GPL-2.0-or-later
module audiopcm

import os

pub const protocol = 1
pub const sample_rate = 48000
pub const channels = 2
pub const chunk_limit = 4096

// This is one exact Unix socket, never a directory or an arbitrary descriptor.
// dev/inode bind the admission to the newly created endpoint across transport.
pub struct Capability {
pub:
	path string
	device u64
	inode u64
	worker int
	generation u64
	manifest string
}

pub fn (mut capability Capability) close() {
	unsafe { capability.path.free(); capability.manifest.free() }
	capability = Capability{}
}

pub fn valid_shape(path string, uid u32) bool {
	number := uid.str()
	prefix := '/run/user/' + number + '/vinix-audio-'
	defer { unsafe { number.free(); prefix.free() } }
	if uid == 0 || !path.starts_with(prefix) || path.len != prefix.len + 32 + 5 || !path.ends_with('.sock') { return false }
	for index in prefix.len .. prefix.len + 32 {
		byte := path[index]
		if !((byte >= `0` && byte <= `9`) || (byte >= `a` && byte <= `f`)) { return false }
	}
	return true
}

pub fn path_owner(path string) !u32 {
	if !path.starts_with('/run/user/') { return error('invalid private audio endpoint') }
	mut at := 10
	start := at
	for at < path.len && path[at] >= `0` && path[at] <= `9` { at++ }
	text := path[start..at]
	defer { unsafe { text.free() } }
	value := decimal(text)!
	if value == 0 || value > 0xffff_ffff || !valid_shape(path, u32(value)) { return error('invalid private audio endpoint') }
	return u32(value)
}

fn directory(parent int, name &char, uid u32, private bool) !int {
	fd := C.openat(parent, name, C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC)
	if fd < 0 { return error('private audio runtime directory unavailable') }
	mut opened := C.stat{}
	mut named := C.stat{}
	if C.fstat(fd, &opened) != 0 || C.fstatat(parent, name, &named, C.AT_SYMLINK_NOFOLLOW) != 0
		|| opened.st_dev != named.st_dev || opened.st_ino != named.st_ino
		|| opened.st_uid != uid || opened.st_mode & 0o170000 != 0o040000
		|| (if private { opened.st_mode & 0o777 != 0o700 } else { opened.st_mode & 0o022 != 0 }) {
		C.close(fd)
		return error('unsafe private audio runtime directory')
	}
	return fd
}

// root/system_owner are explicit filesystem-test inputs. Production always
// uses "/" and owner 0; neither can be selected through an environment value.
pub fn open_runtime(root string, uid u32, system_owner u32) !int {
	fd := C.open(root.str, C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC)
	if fd < 0 { return error('audio runtime root unavailable') }
	defer { C.close(fd) }
	run := directory(fd, c'run', system_owner, false)!
	defer { C.close(run) }
	users := directory(run, c'user', system_owner, false)!
	defer { C.close(users) }
	number := uid.str()
	defer { unsafe { number.free() } }
	return directory(users, number.str, uid, true)
}

pub fn admit(root string, capability Capability, uid u32, system_owner u32) bool {
	if !valid_shape(capability.path, uid) || !capability.valid_binding() { return false }
	runtime := open_runtime(root, uid, system_owner) or { unsafe { err.free() }; return false }
	defer { C.close(runtime) }
	name := capability.path.all_after_last('/')
	defer { unsafe { name.free() } }
	mut info := C.stat{}
	return C.fstatat(runtime, name.str, &info, C.AT_SYMLINK_NOFOLLOW) == 0
		&& info.st_mode & 0o170000 == 0o140000 && info.st_mode & 0o777 == 0o600
		&& info.st_uid == uid && info.st_nlink == 1
		&& u64(info.st_dev) == capability.device && u64(info.st_ino) == capability.inode
}

// Sandboxed clients can inspect only their already unveiled endpoint. Parent
// directory admission belongs to the unsandboxed launcher/account handoff.
fn exact_endpoint(capability Capability, uid u32) bool {
	if !valid_shape(capability.path, uid) || !capability.valid_binding() { return false }
	mut info := C.stat{}
	return C.fstatat(C.AT_FDCWD, capability.path.str, &info, C.AT_SYMLINK_NOFOLLOW) == 0
		&& info.st_mode & 0o170000 == 0o140000 && info.st_mode & 0o777 == 0o600
		&& info.st_uid == uid && info.st_nlink == 1
		&& u64(info.st_dev) == capability.device && u64(info.st_ino) == capability.inode
}

pub fn (capability Capability) valid_binding() bool {
	if capability.worker <= 0 || capability.inode == 0 || capability.generation == 0 || capability.manifest.len != 64 { return false }
	for byte in capability.manifest { if !((byte >= `0` && byte <= `9`) || (byte >= `a` && byte <= `f`)) { return false } }
	return true
}

fn decimal(value string) !u64 {
	if value.len == 0 || value.len > 20 || (value.len > 1 && value[0] == `0`) { return error('invalid audio endpoint identity') }
	mut result := u64(0)
	for byte in value {
		if byte < `0` || byte > `9` || result > (u64(-1) - u64(byte - `0`)) / 10 { return error('invalid audio endpoint identity') }
		result = result * 10 + u64(byte - `0`)
	}
	return result
}

pub fn environment() !Capability {
	path := os.getenv('VINIX_AUDIO_SOCKET')
	device := os.getenv('VINIX_AUDIO_DEVICE')
	inode := os.getenv('VINIX_AUDIO_INODE')
	worker := os.getenv('VINIX_AUDIO_WORKER')
	version := os.getenv('VINIX_AUDIO_PROTOCOL')
	generation := os.getenv('VINIX_AUDIO_GENERATION')
	manifest := os.getenv('VINIX_AUDIO_MANIFEST')
	defer { unsafe { device.free(); inode.free(); worker.free(); version.free(); generation.free() } }
	mut accepted := false
	defer { if !accepted { unsafe { path.free(); manifest.free() } } }
	if path == '' && device == '' && inode == '' && worker == '' && version == '' && generation == '' && manifest == '' { accepted = true; return Capability{ path: path, manifest: manifest } }
	if version != '1' { return error('unsupported audio endpoint protocol') }
	pid := decimal(worker)!
	if pid == 0 || pid > 0x7fff_ffff { return error('invalid audio worker identity') }
	value := Capability{ path: path, device: decimal(device)!, inode: decimal(inode)!, worker: int(pid), generation: decimal(generation)!, manifest: manifest }
	if !exact_endpoint(value, u32(C.geteuid())) { return error('private audio endpoint identity changed') }
	accepted = true
	return value
}

pub fn clear_environment() {
	for name in ['VINIX_AUDIO_SOCKET', 'VINIX_AUDIO_DEVICE', 'VINIX_AUDIO_INODE', 'VINIX_AUDIO_WORKER', 'VINIX_AUDIO_PROTOCOL', 'VINIX_AUDIO_GENERATION', 'VINIX_AUDIO_MANIFEST', 'VINIX_AUDIO_BOOTSTRAP_FD']! { os.unsetenv(name) }
}

pub fn (capability Capability) export_environment() {
	clear_environment()
	if capability.path == '' { return }
	os.setenv('VINIX_AUDIO_SOCKET', capability.path, true)
	device := capability.device.str()
	inode := capability.inode.str()
	pid := capability.worker.str()
	generation := capability.generation.str()
	defer { unsafe { device.free(); inode.free(); pid.free(); generation.free() } }
	os.setenv('VINIX_AUDIO_DEVICE', device, true)
	os.setenv('VINIX_AUDIO_INODE', inode, true)
	os.setenv('VINIX_AUDIO_WORKER', pid, true)
	os.setenv('VINIX_AUDIO_GENERATION', generation, true)
	os.setenv('VINIX_AUDIO_MANIFEST', capability.manifest, true)
	os.setenv('VINIX_AUDIO_PROTOCOL', '1', true)
}

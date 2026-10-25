// SPDX-License-Identifier: GPL-2.0-or-later
module audiopcm

import crypto.rand
import time

pub struct Portal {
pub:
	capability Capability
mut:
	guard int = -1
	runtime int = -1
}

// Called only by the admitted ordinary launcher, before account isolation.
// fork preserves its immutable login-session/seat label. Never set the seat.
pub fn start(id string, generation u64, manifest string) !Portal {
	uid := u32(C.geteuid())
	if uid == 0 || id.len == 0 || id.len > 128 || generation == 0 || manifest.len != 64 { return error('audio portal requires an admitted ordinary application') }
	runtime := open_runtime('/', uid, 0)!
	mut accepted := false
	defer { if !accepted { C.close(runtime) } }
	mut random := rand.bytes(16)!
	defer { unsafe { random.free() } }
	nonce := random.hex()
	number := uid.str()
	path := '/run/user/' + number + '/vinix-audio-' + nonce + '.sock'
	name := path.all_after_last('/')
	defer { unsafe { nonce.free(); number.free(); name.free() }; if !accepted { unsafe { path.free() } } }
	mut lease := [2]i32{}
	if C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &lease[0]) != 0 { return error('cannot create audio launch lease') }
	defer { if !accepted { C.close(lease[0]) }; C.close(lease[1]) }
	nonblocking(lease[0])!
	nonblocking(lease[1])!
	pid := C.fork()
	if pid < 0 { return error('cannot start audio output worker') }
	if pid == 0 {
		C.close(lease[0])
		worker_owner(runtime, path, name, lease[1], uid, id, generation, manifest) or { C._exit(126) }
		C._exit(0)
	}
	mut started := u8(1)
	read_exact(lease[0], &started, 1, -1) or { stop_worker(pid, C.SIGKILL); return err }
	if started != 0 { stop_worker(pid, C.SIGKILL); return error('audio output worker refused startup') }
	mut info := C.stat{}
	if C.fstatat(runtime, name.str, &info, C.AT_SYMLINK_NOFOLLOW) != 0 || info.st_mode & 0o170000 != 0o140000 || info.st_uid != uid {
		stop_worker(pid, C.SIGKILL)
		return error('private audio endpoint changed')
	}
	accepted = true
	return Portal{ capability: Capability{ path: path, device: u64(info.st_dev), inode: u64(info.st_ino), worker: pid, generation: generation, manifest: manifest.clone() }, guard: lease[0], runtime: runtime }
}

fn worker_owner(runtime int, path string, name string, guard int, uid u32, id string, generation u64, manifest string) ! {
	location := address(path)!
	listener := C.socket(C.AF_UNIX, C.SOCK_STREAM, 0)
	if listener < 0 { return error('cannot create private audio output') }
	defer { C.close(listener) }
	nonblocking(listener)!
	// The worker creates the listener: SO_PEERCRED names this process, rather
	// than the parent which passed the socket through fork.
	if C.bind(listener, &location, u32(sizeof(C.vinix_pcm_address))) != 0 { return error('cannot bind fresh private audio output') }
	mut info := C.stat{}
	if C.fstatat(runtime, name.str, &info, C.AT_SYMLINK_NOFOLLOW) != 0 { return error('private audio endpoint unavailable') }
	defer {
		mut remaining := C.stat{}
		if C.fstatat(runtime, name.str, &remaining, C.AT_SYMLINK_NOFOLLOW) == 0
			&& remaining.st_dev == info.st_dev && remaining.st_ino == info.st_ino { C.unlinkat(runtime, name.str, 0) }
	}
	if C.fchmodat(runtime, name.str, 0o600, 0) != 0 || C.listen(listener, 1) != 0 { return error('cannot protect private audio output') }
	worker_isolation(listener, guard, runtime, path)!
	answer(guard, -1, true)!
	worker(listener, guard, uid, id, generation, manifest)
}

fn output() !int {
	fd := C.open(c'/dev/dsp', C.O_WRONLY | C.O_CLOEXEC | C.O_NONBLOCK)
	if fd < 0 { return error('no active-seat audio output') }
	mut accepted := false
	defer { if !accepted { C.close(fd) } }
	mut format := i32(0x10) // AFMT_S16_LE
	mut stereo := i32(channels)
	mut rate := i32(sample_rate)
	if C.ioctl(fd, u64(0xc0045005), &format) != 0 || format != 0x10
		|| C.ioctl(fd, u64(0xc0045006), &stereo) != 0 || stereo != channels
		|| C.ioctl(fd, u64(0xc0045002), &rate) != 0 || rate != sample_rate { return error('audio output does not support S16LE stereo 48000Hz') }
	accepted = true
	return fd
}

fn worker(listener int, guard int, uid u32, id string, generation u64, manifest string) {
	for {
		ready(listener, 1, guard, -1) or { unsafe { err.free() }; return }
		fd := C.accept(listener, unsafe { nil }, unsafe { nil })
		if fd < 0 { continue }
		nonblocking(fd) or { C.close(fd); unsafe { err.free() }; continue }
		identity := peer(fd) or { C.close(fd); unsafe { err.free() }; continue }
		if identity.uid == uid { stream(fd, guard, id, generation, manifest) or { unsafe { err.free() } } }
		C.close(fd)
	}
}

fn answer(fd int, guard int, success bool) ! {
	value := if success { u8(0) } else { u8(1) }
	write_exact(fd, &value, 1, guard)!
}

fn stream(fd int, guard int, id string, generation u64, manifest string) ! {
	mut magic := [8]u8{}
	read_exact(fd, &magic[0], 8, guard)!
	for index, byte in 'VPCM0001' { if magic[index] != byte { return error('unsupported audio protocol') } }
	mut size := u8(0)
	read_exact(fd, &size, 1, guard)!
	if int(size) != id.len { answer(fd, guard, false)!; return error('audio application identity changed') }
	mut selected := [128]u8{}
	read_exact(fd, &selected[0], int(size), guard)!
	for index, byte in id { if selected[index] != byte { answer(fd, guard, false)!; return error('audio application identity changed') } }
	mut number := [8]u8{}
	read_exact(fd, &number[0], 8, guard)!
	mut admitted_generation := u64(0)
	for index, byte in number { admitted_generation |= u64(byte) << (index * 8) }
	mut digest := [64]u8{}
	read_exact(fd, &digest[0], 64, guard)!
	mut matches := admitted_generation == generation
	for index, byte in manifest { if digest[index] != byte { matches = false } }
	if !matches { answer(fd, guard, false)!; return error('audio signed selection changed') }
	dsp := output() or { answer(fd, guard, false)!; return err }
	defer { C.close(dsp) }
	answer(fd, guard, true)!
	mut bytes := [chunk_limit]u8{}
	for {
		mut header := [4]u8{}
		read_exact(fd, &header[0], 4, guard)!
		length := u32(header[0]) | u32(header[1]) << 8 | u32(header[2]) << 16 | u32(header[3]) << 24
		if length > chunk_limit || length % 4 != 0 { answer(fd, guard, false)!; return error('invalid audio frame length') }
		if length == 0 {
			if C.ioctl(dsp, u64(0x5001), unsafe { nil }) != 0 { answer(fd, guard, false)!; return error('audio output drain refused') }
			answer(fd, guard, true)!
			continue
		}
		read_exact(fd, &bytes[0], int(length), guard)!
		mut at := 0
		deadline := time.sys_mono_now() + 5_000_000_000
		for at < int(length) {
			remaining_ms(deadline)!
			lease_alive(guard, 0)!
			n := C.write(dsp, unsafe { &bytes[0] + at }, usize(int(length) - at))
			if n < 0 && C.errno == C.EINTR { continue }
			if n < 0 && C.errno == C.EAGAIN { lease_alive(guard, 5)!; continue }
			if n <= 0 { answer(fd, guard, false)!; return error('audio output write refused') }
			at += int(n)
		}
		answer(fd, guard, true)!
	}
}

fn stop_worker(pid int, signal int) {
	C.kill(pid, signal)
	mut status := i32(0)
	for C.waitpid(pid, &status, 0) < 0 { if C.errno != C.EINTR { break } }
}

pub fn (mut portal Portal) close() {
	if portal.guard >= 0 { C.close(portal.guard) }
	if portal.capability.worker > 0 {
		// Socket waits and nonblocking write retries observe the caller lease.
		// Driver drain/close retains the device's own interruption semantics.
		stop_worker(portal.capability.worker, C.SIGTERM)
	}
	if portal.runtime >= 0 {
		name := portal.capability.path.all_after_last('/')
		// Remove only the endpoint inode this owner created, never a replacement.
		mut info := C.stat{}
		if C.fstatat(portal.runtime, name.str, &info, C.AT_SYMLINK_NOFOLLOW) == 0
			&& u64(info.st_dev) == portal.capability.device && u64(info.st_ino) == portal.capability.inode { C.unlinkat(portal.runtime, name.str, 0) }
		unsafe { name.free() }
		C.close(portal.runtime)
	}
	portal.capability.close()
	portal = Portal{}
}

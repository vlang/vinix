// SPDX-License-Identifier: GPL-2.0-or-later
module audiopcm

import os

$if track_heap ? {
	#include "heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
}

// Explicit checks also execute in -prod, unlike V assertions.
fn pcm_check(ok bool, message string) { if !ok { panic(message) } }
fn pcm_error(err IError) { message := err.msg(); unsafe { message.free(); err.free() } }

fn test_audio_capability_shape_and_checked_unsigned_identity() {
	path := '/run/user/1000/vinix-audio-0123456789abcdef0123456789abcdef.sock'
	pcm_check(valid_shape(path, 1000) && path_owner(path)! == 1000, 'canonical endpoint')
	for value in ['', '/tmp/audio.sock', path.replace('/1000/', '/01000/'), path.replace('abcdef.sock', 'abcdeF.sock'), path + '/child', path + '\x00'] {
		if _ := path_owner(value) { panic('accepted unsafe audio path') } else { pcm_error(err) }
	}
	for value in ['', '00', '01', '-1', '+1', '18446744073709551616', '123456789012345678901', '1x'] {
		if _ := decimal(value) { panic('accepted noncanonical unsigned identity') } else { pcm_error(err) }
	}
	pcm_check(decimal('18446744073709551615')! == u64(-1), 'maximum u64')
	base := Capability{ path: path, inode: 1, worker: 2, generation: 3, manifest: 'a'.repeat(64) }
	pcm_check(base.valid_binding(), 'complete signed binding')
	for value in [Capability{ ...base, worker: 0 }, Capability{ ...base, inode: 0 }, Capability{ ...base, generation: 0 }, Capability{ ...base, manifest: 'A'.repeat(64) }, Capability{ ...base, manifest: 'a'.repeat(63) }] {
		pcm_check(!value.valid_binding(), 'invalid signed binding')
	}
}

fn test_audio_runtime_admission_uses_descriptor_identity_and_private_modes() {
	uid := u32(C.geteuid())
	if uid == 0 { panic('host fixture requires an ordinary owner') }
	root := '/tmp/vpcm-' + os.getpid().str()
	os.mkdir(root)!
	defer { os.rmdir_all(root) or {} }
	os.mkdir(root + '/run', mode: 0o755)!
	os.mkdir(root + '/run/user', mode: 0o755)!
	runtime := root + '/run/user/' + uid.str()
	os.mkdir(runtime, mode: 0o700)!
	name := 'vinix-audio-0123456789abcdef0123456789abcdef.sock'
	actual := runtime + '/' + name
	location := address(actual)!
	fd := C.socket(C.AF_UNIX, C.SOCK_STREAM, 0)
	pcm_check(fd >= 0, 'fixture socket')
	defer { C.close(fd) }
	pcm_check(C.vinix_pcm_bind(fd, &location, u32(sizeof(C.vinix_pcm_address))) == 0, 'fixture bind')
	pcm_check(C.listen(fd, 1) == 0, 'fixture listen')
	client := C.socket(C.AF_UNIX, C.SOCK_STREAM, 0)
	pcm_check(client >= 0, 'fixture client socket')
	defer { C.close(client) }
	pcm_check(C.vinix_pcm_connect(client, &location, u32(sizeof(C.vinix_pcm_address))) == 0, 'real pathname audio connection')
	accepted := C.accept(fd, unsafe { nil }, unsafe { nil })
	pcm_check(accepted >= 0, 'fixture accepted connection')
	C.close(accepted)
	os.chmod(actual, 0o600)!
	mut info := C.stat{}
	pcm_check(C.fstatat(C.AT_FDCWD, actual.str, &info, C.AT_SYMLINK_NOFOLLOW) == 0, 'fixture inode')
	capability := Capability{ path: '/run/user/' + uid.str() + '/' + name, device: u64(info.st_dev), inode: u64(info.st_ino), worker: os.getpid(), generation: 42, manifest: 'b'.repeat(64) }
	pcm_check(admit(root, capability, uid, uid), 'private exact socket admission')
	pcm_check(!admit(root, Capability{ ...capability, inode: capability.inode + 1 }, uid, uid), 'replacement inode refusal')
	pcm_check(!admit(root, capability, uid + 1, uid), 'other account refusal')
	os.chmod(actual, 0o660)!
	pcm_check(!admit(root, capability, uid, uid), 'shared socket refusal')
	os.chmod(actual, 0o600)!
	os.chmod(runtime, 0o750)!
	pcm_check(!admit(root, capability, uid, uid), 'shared runtime refusal')
	os.chmod(runtime, 0o700)!
	os.rm(actual)!
	os.symlink('/dev/null', actual)!
	pcm_check(!admit(root, capability, uid, uid), 'symlink endpoint refusal')
	os.rm(actual)!
	os.rename(runtime, runtime + '-old')!
	os.symlink(runtime + '-old', runtime)!
	pcm_check(!admit(root, capability, uid, uid), 'symlink runtime refusal')
}

fn test_audio_socket_acknowledgements_frame_bounds_and_caller_lease() {
	mut pair := [2]i32{}
	pcm_check(C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &pair[0]) == 0, 'fixture socketpair')
	nonblocking(pair[0])!
	nonblocking(pair[1])!
	pid := C.fork()
	pcm_check(pid >= 0, 'fixture fork')
	if pid == 0 {
		C.close(pair[0])
		mut header := [4]u8{}
		read_exact(pair[1], &header[0], 4, -1) or { C._exit(10) }
		if header != [u8(4), 0, 0, 0]! { C._exit(11) }
		mut payload := [4]u8{}
		read_exact(pair[1], &payload[0], 4, -1) or { C._exit(12) }
		if payload != [u8(1), 2, 3, 4]! { C._exit(13) }
		answer(pair[1], -1, true) or { C._exit(14) }
		read_exact(pair[1], &header[0], 4, -1) or { C._exit(15) }
		if header != [u8(0), 0, 0, 0]! { C._exit(16) }
		answer(pair[1], -1, false) or { C._exit(17) }
		C.close(pair[1]); C._exit(0)
	}
	C.close(pair[1])
	mut client := Client{ fd: pair[0] }
	defer { client.close() }
	for bytes in [ []u8{}, [u8(1)], []u8{len: chunk_limit + 4} ] {
		if _ := client.write(bytes) { panic('accepted invalid local PCM frame') } else { pcm_error(err) }
		pcm_check(client.fd >= 0, 'local refusal preserves usable connection')
	}
	client.write([u8(1), 2, 3, 4])!
	if _ := client.drain() { panic('accepted negative output acknowledgement') } else { pcm_error(err) }
	pcm_check(client.fd == -1, 'server refusal closes client')
	mut status := i32(0)
	pcm_check(C.waitpid(pid, &status, 0) == pid && status == 0, 'fixture child completed and reaped')
	mut lease := [2]i32{}
	pcm_check(C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &lease[0]) == 0, 'lease pair')
	defer { C.close(lease[0]) }
	lease_alive(lease[0], 0)!
	C.close(lease[1])
	if _ := lease_alive(lease[0], 0) { panic('accepted dead caller lease') } else { pcm_error(err) }
}

fn test_audio_bootstrap_proof_binds_every_selection_field_and_ambient_refusal() {
	base := Capability{ path: '/run/user/1000/vinix-audio-0123456789abcdef0123456789abcdef.sock', device: 1, inode: 2, worker: 3, generation: 4, manifest: 'c'.repeat(64) }
	proof := base.proof('org.tone')
	for value in [Capability{ ...base, path: base.path.replace('0123', '1123') }, Capability{ ...base, device: 2 }, Capability{ ...base, inode: 3 }, Capability{ ...base, worker: 4 }, Capability{ ...base, generation: 5 }, Capability{ ...base, manifest: 'd'.repeat(64) }] {
		candidate := value.proof('org.tone')
		pcm_check(candidate != proof, 'bootstrap proof omitted capability field')
		unsafe { candidate.free() }
	}
	changed := base.proof('org.other')
	pcm_check(changed != proof, 'bootstrap proof omitted package ID')
	unsafe { changed.free(); proof.free() }
	clear_environment()
	defer { clear_environment() }
	mut absent := environment()!
	pcm_check(absent.path == '', 'absent ambient audio')
	absent.close()
	os.setenv('VINIX_AUDIO_PROTOCOL', '1', true)
	if mut value := environment() { value.close(); panic('accepted incomplete audio environment') } else { pcm_error(err) }
	clear_environment()
	os.setenv('VINIX_SESSION_FD', 'sentinel', true)
	if _ := consume_bootstrap(base, 'org.tone') { panic('accepted ambient audio without root descriptor') } else { pcm_error(err) }
	pcm_check(os.getenv('VINIX_SESSION_FD') == '', 'bootstrap clears control marker on refusal')
	if _ := account_admission(base, 1000, -1) { panic('accepted missing authenticated launcher') } else { pcm_error(err) }
}

fn test_audio_kernel_identity_reader_rejects_overflow_truncation_and_links() {
	path := '/tmp/vpcm-number-' + os.getpid().str()
	defer { os.rm(path) or {}; os.rm(path + '-link') or {} }
	os.write_file(path, '1000\n')!
	pcm_check(login_number(path)! == 1000, 'bounded kernel decimal reader')
	for value in ['0\n', '01000\n', '4294967296\n', '1', '1\nx', '123456789012345\n'] {
		os.write_file(path, value)!
		if _ := login_number(path) { panic('accepted invalid immutable login identity') } else { pcm_error(err) }
	}
	os.write_file(path, '1000\n')!
	os.symlink(path, path + '-link')!
	if _ := login_number(path + '-link') { panic('followed login identity symlink') } else { pcm_error(err) }
	pcm_check(sizeof(LoginIdentity) == 8 && sizeof(Credentials) == 12 && sizeof(i32) == 4, 'kernel credential scalar ABI')
	pcm_check(active_login(LoginIdentity{ uid: 1000, session: 42 }, 1000, 42), 'cached active login positive control')
	for identity in [LoginIdentity{}, LoginIdentity{ uid: 1000 }, LoginIdentity{ uid: 1001, session: 42 }, LoginIdentity{ uid: 1000, session: 43 }, LoginIdentity{ uid: 0xffff_ffff, session: 42 }] {
		pcm_check(!active_login(identity, 1000, 42), 'inactive or unset cached login refused')
	}
	pcm_check(!active_login(LoginIdentity{ uid: 1000, session: 42 }, 1000, 0), 'missing seat refused')
	if _ := peer_login(-1) { panic('accepted missing immutable kernel peer identity') } else { pcm_error(err) }
}

fn test_audio_bootstrap_proof_retires_repeated_hash_storage() {
	base := Capability{ path: '/run/user/1000/vinix-audio-0123456789abcdef0123456789abcdef.sock', device: 1, inode: 2, worker: 3, generation: 4, manifest: 'c'.repeat(64) }
	warm := base.proof('org.tone')
	defer { unsafe { warm.free() } }
	$if track_heap ? { C.vinix_heap_begin() }
	for _ in 0 .. 1000 {
		proof := base.proof('org.tone')
		pcm_check(proof == warm && proof.len == 64, 'stable complete bootstrap proof')
		unsafe { proof.free() }
	}
	$if track_heap ? { pcm_check(C.vinix_heap_end() == 0, 'bootstrap hash retains V storage') }
}

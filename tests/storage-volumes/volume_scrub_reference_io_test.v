// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

import os
import crypto.sha256

fn C.dup(i32) i32
fn C.dup2(i32, i32) i32
fn C.fork() i32
fn C._exit(i32)
fn C.waitpid(i32, &i32, i32) i32
$if macos { fn C.mkfifo(const_name &char, mode u16) i32 } $else { fn C.mkfifo(const_name &char, mode u32) i32 }

struct CipherBindIO {
mut:
	active bool
	mode int
	opened int
	closed int
	reads int
	stats int
}
__global cipher_bind_io CipherBindIO

fn cipher_bind_open(path &char, flags i32) i32 {
	if cipher_bind_io.active { assert flags == C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC }
	fd := C.open(path, flags); if cipher_bind_io.active && fd >= 0 { cipher_bind_io.opened++ }; return fd
}
fn cipher_bind_openat(directory i32, path &char, flags i32) i32 {
	if cipher_bind_io.active { assert flags == C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK }
	fd := C.openat(directory, path, flags); if cipher_bind_io.active && fd >= 0 { cipher_bind_io.opened++ }; return fd
}
fn cipher_bind_close(fd i32) i32 { if cipher_bind_io.active { cipher_bind_io.closed++; assert cipher_bind_io.closed <= cipher_bind_io.opened }; return C.close(fd) }
fn cipher_bind_flock(fd i32, flags i32) i32 { assert !cipher_bind_io.active; return C.flock(fd, flags) }
fn cipher_bind_stat(fd i32, info &C.stat) i32 {
	cipher_bind_io.stats++
	if cipher_bind_io.mode == 10 || (cipher_bind_io.mode == 13 && cipher_bind_io.stats == 3) { return -1 }
	if cipher_bind_io.mode == 20 && cipher_bind_io.stats == 4 { return -1 }
	result := C.fstat(fd, info);
	unsafe {
		if cipher_bind_io.mode == 15 || (cipher_bind_io.mode == 19 && cipher_bind_io.stats == 2) { info.st_uid = C.geteuid() + 1 }
		if cipher_bind_io.mode == 16 || (cipher_bind_io.mode == 18 && cipher_bind_io.stats == 2) { info.st_mode |= 0o044 }
		if cipher_bind_io.mode == 17 && cipher_bind_io.stats == 2 { info.st_size++ }
	}
 if cipher_bind_io.mode == 6 { unsafe { info.st_size++ } }; return result
}
fn cipher_bind_read(fd i32, bytes voidptr, size usize) i64 {
	cipher_bind_io.reads++
	match cipher_bind_io.mode {
		1 { if cipher_bind_io.reads == 1 { unsafe { C.errno = C.EINTR }; return -1 }; return C.read(fd, bytes, if size > 3 { usize(3) } else { size }) }
		2 { return 0 }
		3 { unsafe { C.errno = C.EIO }; return -1 }
		4 { return i64(size + 1) }
		5 { result := C.read(fd, bytes, size); return if result == 0 { i64(1) } else { result } }
		11 { result := C.read(fd, bytes, size); if result == 0 && cipher_bind_io.reads == 2 { unsafe { C.errno = C.EINTR }; return -1 }; return result }
		12 { if cipher_bind_io.reads == 3 { unsafe { C.errno = C.EIO }; return -1 }; return C.read(fd, bytes, size) }
		else { return C.read(fd, bytes, size) }
	}
}
fn cipher_bind_mock_encode(reference &u8, report &u8, output &char) int {
	assert cipher_bind_io.active && cipher_bind_io.opened == 4 && cipher_bind_io.closed == 0
	if cipher_bind_io.mode == 7 { return 0 }; return encode_volume_scrub_reference(reference, report, output)
}
fn cipher_bind_print(text &char) i32 {
	assert cipher_bind_io.active && cipher_bind_io.opened == 4 && cipher_bind_io.closed == 0
	if cipher_bind_io.mode == 14 { return -1 }; return C.printf(c'%s', text)
}
fn cipher_bind_flush(stream voidptr) i32 { if cipher_bind_io.active { assert cipher_bind_io.opened == 4 && cipher_bind_io.closed == 0 }; if cipher_bind_io.active && cipher_bind_io.mode == 8 { return -1 }; return C.fflush(stream) }
fn cipher_bind_ferror(stream voidptr) i32 { if cipher_bind_io.active { assert cipher_bind_io.opened == 4 && cipher_bind_io.closed == 0 }; if cipher_bind_io.active && cipher_bind_io.mode == 9 { return 1 }; return C.ferror(stream) }

fn cipher_bind_manifest() []u8 {
	mut disk := DiskKey{bytes: 1048576, sector: 512, kind: 1}; disk.id[0] = 1
	row := Request{slot: 63, offset: 8192, length: 73728, flags: 1}; digest := [32]u8{}; mut bytes := [128]u8{}
	assert encode_volume_ciphertext(&disk, &row, &digest[0], &bytes[0]); return bytes[..].clone()
}
fn cipher_bind_input(state int) []u8 {
	reference := cipher_bind_manifest(); mut observed := [32]u8{}; if state != 0 { observed[31] = u8(state) }
	mut report := [224]u8{}; assert encode_volume_ciphertext_scrub(reference.data, &observed[0], &report[0]); return report[..].clone()
}
fn cipher_bind_expected(state int) string {
	zero := '0'.repeat(64)
	return 'format=VINIXCS1 operation=verified-ciphertext-scrub-reference mappings=1 matched=${int(state == 0)} changed=${int(state != 0)} algorithm=sha256 reference_sha256=' + sha256.hexhash(cipher_bind_manifest().bytestr()) + ' report_sha256=' + sha256.hexhash(cipher_bind_input(state).bytestr()) + '\n' +
		'disk_bytes=1048576 sector=512 identity=mbr:00000001 slot=63 offset=8192 bytes=73728 readonly=1 result=${if state == 0 { 'match' } else { 'changed' }} expected_sha256=${zero} actual_sha256=${if state == 0 { zero } else { '0'.repeat(63) + state.str() }}\n'
}

fn cipher_bind_check(first string, second string, mode int, expected i32) string {
	capture := os.dir(first) + '/history-capture'; assert C.fflush(C.stdout) == 0
	saved := C.dup(1); fd := C.open(capture.str, C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600)); assert saved >= 0 && fd >= 0 && C.dup2(fd, 1) == 1 && C.close(fd) == 0
	cipher_bind_io = CipherBindIO{active: true, mode: mode}
	unsafe { args := [&char(c'vinix-volume'), &char(c'verify-volume-scrub-reference'), first.str, second.str, &char(nil)]!; assert run(4, &args[0]) == expected }
	assert cipher_bind_io.opened == cipher_bind_io.closed; cipher_bind_io.active = false
	assert C.fflush(C.stdout) == 0 && C.dup2(saved, 1) == 1 && C.close(saved) == 0
	text := os.read_file(capture) or { panic(err) }; os.rm(capture) or { panic(err) }
	if expected == 1 && mode !in [8, 9] { assert !text.contains('format=VINIXCS1') && !text.contains('disk_bytes=') }; return text
}
fn test_cipher_binding_real_private_cli_complete_binding_read_output_faults_and_pinned_owners() {
	work := os.join_path(os.temp_dir(), 'vinix-cipher-binding-${os.getpid()}'); os.mkdir(work)!; defer { os.rmdir_all(work) or {} }; first := work + '/first'; second := work + '/second'; left := cipher_bind_manifest()
	for state in 0 .. 3 {
		right := cipher_bind_input(state); os.write_file_array(first, left)!; os.write_file_array(second, right)!; os.chmod(first, 0o600)!; os.chmod(second, 0o600)!
		for mode in 0 .. 21 {
			text := cipher_bind_check(first, second, mode, if mode in [0, 1, 11] { if state == 0 { 0 } else { 2 } } else { 1 })
			if mode in [0, 1, 11] { assert text == cipher_bind_expected(state) }; assert os.read_bytes(first)! == left && os.read_bytes(second)! == right
		}
		child := C.fork(); assert child >= 0
		if child == 0 { fd := C.open(c'/dev/null', C.O_RDONLY); if fd < 0 || C.dup2(fd, 1) != 1 { C._exit(3) }; C.close(fd); cipher_bind_io = CipherBindIO{active: true}; result := verify_volume_scrub_reference_files(first.str, second.str); C._exit(if result == 1 && cipher_bind_io.opened == cipher_bind_io.closed { 0 } else { 5 }) }
		mut code := i32(-1); assert C.waitpid(child, &code, 0) == child && code == 0
	}
	os.write_file_array(second, cipher_bind_input(1))!; cipher_bind_check(first, first, 0, 1)
	for path in [first, second] { os.link(path, path + '.alias')! }
	assert cipher_bind_check(first + '.alias', second + '.alias', 0, 2) == cipher_bind_expected(1)
	mut owner := PlanEdit{}; assert open_plan_edit(first.str, mut owner, true); assert cipher_bind_check(first, second, 0, 2) == cipher_bind_expected(1); close_plan_edit(mut owner)
	for path in [first, second] {
		bytes := os.read_bytes(path)!
		for size in 0 .. bytes.len { os.write_file_array(path, bytes[..size])!; cipher_bind_check(first, second, 0, 1) }
		mut nul := bytes.clone(); nul << u8(0); os.write_file_array(path, nul)!; cipher_bind_check(first, second, 0, 1)
		for byte in 0 .. bytes.len { mut bad := bytes.clone(); bad[byte] ^= 1; os.write_file_array(path, bad)!; cipher_bind_check(first, second, 0, 1) }
		os.write_file_array(path, bytes)!; os.chmod(path, 0o644)!; cipher_bind_check(first, second, 0, 1); os.chmod(path, 0o600)!
		os.mv(path, path + '.saved')!; os.symlink(path + '.saved', path)!; cipher_bind_check(first, second, 0, 1); os.rm(path)!
		os.mkdir(path)!; cipher_bind_check(first, second, 0, 1); os.rmdir(path)!; assert C.mkfifo(path.str, 0o600) == 0; cipher_bind_check(first, second, 0, 1); os.rm(path)!; cipher_bind_check(first, second, 0, 1); os.mv(path + '.saved', path)!
	}
	// Structurally valid unrelated reference metadata/expectations refuse findings.
	for byte in [16, 36, 40, 48, 56, 64, 80, 111] {
		mut wrong := left.clone(); wrong[byte] ^= if byte in [16, 40, 48] { u8(0) } else if byte == 64 { u8(2) } else { u8(1) }
		if byte == 16 { put_le(wrong.data, 16, 8, 2097152) } else if byte == 40 { put_le(wrong.data, 40, 8, 12288) } else if byte == 48 { put_le(wrong.data, 48, 8, 81920) }
		put_le(wrong.data, 124, 4, crc32(wrong.data, 128, 124)); mut disk := DiskKey{}; mut row := Request{}; assert volume_ciphertext_reference_geometry(wrong.data, mut disk, mut row)
		os.write_file_array(first, wrong)!; cipher_bind_check(first, second, 0, 1)
		os.write_file_array(first, left)!; observed := [32]u8{init: 0xff}; mut report := [224]u8{}; assert encode_volume_ciphertext_scrub(wrong.data, &observed[0], &report[0]); os.write_file_array(second, report[..])!; cipher_bind_check(first, second, 0, 1); os.write_file_array(second, cipher_bind_input(1))!
	}
}

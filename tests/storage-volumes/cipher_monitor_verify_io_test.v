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
	fd := C.openat(directory, path, flags); if cipher_bind_io.active && cipher_bind_io.opened == 3 { cipher_verify_io_fd = fd }; if cipher_bind_io.active && fd >= 0 { cipher_bind_io.opened++ }; return fd
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

__global cipher_verify_io_fd i32 = -1
__global cipher_verify_io_reads int
__global cipher_verify_io_eof bool
__global cipher_verify_io_recovery bool
fn cipher_verify_io_stat(fd i32, info &C.stat) i32 {
	result := cipher_bind_stat(fd, info)
	if cipher_bind_io.stats == 4 { unsafe { if cipher_bind_io.mode == 21 { info.st_size++ }; if cipher_bind_io.mode == 22 { info.st_mode = (info.st_mode & ~C.S_IFMT) | C.S_IFDIR } } }; return result
}
fn cipher_verify_io_read(fd i32, data voidptr, size usize) i64 {
	assert cipher_bind_io.active && cipher_bind_io.opened == 4 && cipher_bind_io.closed == 0 && fd == cipher_verify_io_fd; cipher_verify_io_reads++
	if cipher_bind_io.mode == 23 && cipher_verify_io_reads == 2 { unsafe { C.errno = C.EIO }; return -1 }
	n := cipher_bind_read(fd, data, size)
	if cipher_bind_io.mode == 24 && n == 0 && !cipher_verify_io_eof { cipher_verify_io_eof = true; unsafe { C.errno = C.EINTR }; return -1 }; return n
}
fn cipher_verify_io_accept(reference &u8, data &u8, size int, prefix int, mut history CipherMonitorHistory) bool {
	assert cipher_bind_io.active && cipher_bind_io.opened == 4 && cipher_bind_io.closed == 0; return accept_ciphertext_monitor(reference, data, size, prefix, mut history)
}
fn cipher_verify_io_encode(reference &u8, history &CipherMonitorHistory, digest &[32]u8, output &char) int {
	assert cipher_bind_io.active && cipher_bind_io.opened == 4 && cipher_bind_io.closed == 0; if cipher_bind_io.mode == 7 { return 0 }; return encode_ciphertext_monitor_history(reference, history, digest, output)
}
fn cipher_verify_io_input(states []int) string {
	zero := '0'.repeat(64); mut text := ''; mut changed := 0
	for i, state in states { if state != 0 { changed++ }; actual := if state == 0 { zero } else { '0'.repeat(63) + state.str() }
		text += 'format=VINIXCM1 operation=monitored-ciphertext source=${if cipher_verify_io_recovery { 'recovery' } else { 'volume' }} sample=${i + 1} changed_samples=${changed} session_changed=${int(changed != 0)}\nformat=VINIXCS1 operation=scrubbed-ciphertext mappings=1 matched=${int(state == 0)} changed=${int(state != 0)} algorithm=sha256 reference_sha256=' + sha256.hexhash(cipher_bind_manifest().bytestr()) + '\ndisk_bytes=1048576 sector=512 identity=mbr:00000001 slot=63 offset=8192 bytes=73728 readonly=1 result=${if state == 0 { 'match' } else { 'changed' }} expected_sha256=${zero} actual_sha256=${actual}\n'
	}; return text
}
fn cipher_verify_io_wanted(states []int) string {
	zero := '0'.repeat(64); mut changed := 0; mut classes := [4]int{}; table := [[0, 1, 1]!, [2, 0, 3]!, [2, 3, 0]!]!
	for i, state in states { if state != 0 { changed++ }; if i != 0 { classes[table[states[i - 1]][state]]++ } }; final := states.last(); actual := if final == 0 { zero } else { '0'.repeat(63) + final.str() }
	return 'format=VINIXCM1 operation=verified-ciphertext-monitor source=${if cipher_verify_io_recovery { 'recovery' } else { 'volume' }} mappings=1 samples=${states.len} changed_samples=${changed} session_changed=${int(changed != 0)} final_changed=${int(final != 0)} stable=${classes[0]} new_changes=${classes[1]} restored=${classes[2]} changed_again=${classes[3]} algorithm=sha256 reference_sha256=' + sha256.hexhash(cipher_bind_manifest().bytestr()) + ' transcript_sha256=' + sha256.hexhash(cipher_verify_io_input(states)) + '\ndisk_bytes=1048576 sector=512 identity=mbr:00000001 slot=63 offset=8192 bytes=73728 readonly=1 result=${if final == 0 { 'match' } else { 'changed' }} expected_sha256=${zero} final_sha256=${actual}\n'
}
fn cipher_verify_io_check(first string, second string, mode int, expected i32) string {
	capture := os.dir(first) + '/capture'; assert C.fflush(C.stdout) == 0; saved := C.dup(1); fd := C.open(capture.str, C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600)); assert saved >= 0 && fd >= 0 && C.dup2(fd, 1) == 1 && C.close(fd) == 0
	cipher_bind_io = CipherBindIO{active: true, mode: mode}; cipher_verify_io_fd = -1; cipher_verify_io_reads = 0; cipher_verify_io_eof = false
	unsafe { args := [&char(c'vinix-volume'), &char(c'verify-volume-monitor'), first.str, second.str, &char(nil)]!; assert run(4, &args[0]) == expected }
	assert cipher_bind_io.opened == cipher_bind_io.closed; cipher_bind_io.active = false; assert C.fflush(C.stdout) == 0 && C.dup2(saved, 1) == 1 && C.close(saved) == 0
	text := os.read_file(capture) or { panic(err) }; os.rm(capture) or { panic(err) }; if expected == 1 && mode !in [8, 9] { assert !text.contains('operation=verified-ciphertext-monitor') && !text.contains('disk_bytes=') }; return text
}
fn test_cipher_verify_real_cli_buffering_private_reference_full_frames_owners_faults_and_no_partial_findings() {
	work := os.join_path(os.temp_dir(), 'vinix-cipher-verify-${os.getpid()}'); os.mkdir(work)!; defer { os.rmdir_all(work) or {} }; first := work + '/reference'; second := work + '/transcript'; manifest := cipher_bind_manifest(); os.write_file_array(first, manifest)!; os.chmod(first, 0o600)!
	for recovery in [false, true] { cipher_verify_io_recovery = recovery
		for sequence in 0 .. 27 { states := [sequence % 3, (sequence / 3) % 3, sequence / 9]; transcript := cipher_verify_io_input(states); os.write_file(second, transcript)!; os.chmod(second, 0o644)!
			for mode in 0 .. 23 { result := if mode in [0, 1, 11] { if states.all(it == 0) { 0 } else { 2 } } else { 1 }; actual := cipher_verify_io_check(first, second, mode, result); if result != 1 { assert actual == cipher_verify_io_wanted(states) }; assert os.read_bytes(first)! == manifest && os.read_file(second)! == transcript }
			assert cipher_verify_io_check(first, second, 24, if states.all(it == 0) { 0 } else { 2 }) == cipher_verify_io_wanted(states) && cipher_verify_io_eof
		}
	}
	states := [1, 2, 0]; transcript := cipher_verify_io_input(states); os.write_file(second, transcript)!; cipher_verify_io_check(first, first, 0, 1)
	for path in [first, second] { os.link(path, path + '.alias')! }; assert cipher_verify_io_check(first + '.alias', second + '.alias', 0, 2) == cipher_verify_io_wanted(states)
	mut writer := PlanEdit{}; assert open_plan_edit(first.str, mut writer, true); assert cipher_verify_io_check(first, second, 0, 2) == cipher_verify_io_wanted(states); close_plan_edit(mut writer)
	mut boundaries := map[int]int{}; for i in 1 .. states.len + 1 { boundaries[cipher_verify_io_input(states[..i]).len] = i }
	for size in 0 .. transcript.len { os.write_file(second, transcript[..size])!; count := boundaries[size]; actual := cipher_verify_io_check(first, second, 0, if count > 0 { 2 } else { 1 }); if count > 0 { assert actual == cipher_verify_io_wanted(states[..count]) } }; os.write_file(second, transcript)!
	for pair in [['sample=2', 'sample=3'], ['sample=2', 'sample=02'], ['changed_samples=2', 'changed_samples=1'], ['session_changed=1', 'session_changed=0'], ['slot=63', 'slot=62'], ['readonly=1', 'readonly=0'], ['identity=mbr:00000001', 'identity=mbr:00000002'], ['sector=512', 'sector=4096']] { os.write_file(second, transcript.replace(pair[0], pair[1]))!; cipher_verify_io_check(first, second, 0, 1) }
	mixed := cipher_verify_io_input([1]) + transcript.all_after(cipher_verify_io_input([1])).replace('source=recovery', 'source=volume'); os.write_file(second, mixed)!; cipher_verify_io_check(first, second, 0, 1)
	for suffix in ['\x00', 'vinix-volume: late physical error\n', '\n', 'format=VINIXCM1 operation=monitored-ciphertext source=recovery sample=4'] { os.write_file(second, transcript + suffix)!; cipher_verify_io_check(first, second, 0, 1) }
	for at in 0 .. manifest.len { mut bad := manifest.clone(); bad[at] ^= 1; os.write_file_array(first, bad)!; os.write_file(second, transcript)!; cipher_verify_io_check(first, second, 0, 1) }; os.write_file_array(first, manifest)!
	os.chmod(first, 0o644)!; cipher_verify_io_check(first, second, 0, 1); os.chmod(first, 0o600)!
	for path in [first, second] { bytes := os.read_bytes(path)!; os.mv(path, path + '.saved')!; os.symlink(path + '.saved', path)!; cipher_verify_io_check(first, second, 0, 1); os.rm(path)!; os.mkdir(path)!; cipher_verify_io_check(first, second, 0, 1); os.rmdir(path)!; assert C.mkfifo(path.str, 0o600) == 0; cipher_verify_io_check(first, second, 0, 1); os.rm(path)!; cipher_verify_io_check(first, second, 0, 1); os.mv(path + '.saved', path)!; assert os.read_bytes(path)! == bytes }
	long_states := []int{len: 512, init: index % 3}; os.write_file(second, cipher_verify_io_input(long_states))!; assert cipher_verify_io_check(first, second, 0, 2) == cipher_verify_io_wanted(long_states) && cipher_verify_io_reads < 16; cipher_verify_io_check(first, second, 23, 1)
	os.truncate(second, 67108865)!; cipher_verify_io_check(first, second, 0, 1); assert cipher_verify_io_reads == 0; os.write_file(second, transcript)!
	child := C.fork(); assert child >= 0; if child == 0 { fd := C.open(c'/dev/null', C.O_RDONLY); if fd < 0 || C.dup2(fd, 1) != 1 { C._exit(3) }; C.close(fd); cipher_bind_io = CipherBindIO{active: true}; result := verify_volume_monitor_files(first.str, second.str); C._exit(if result == 1 && cipher_bind_io.opened == cipher_bind_io.closed { 0 } else { 5 }) }; mut code := i32(-1); assert C.waitpid(child, &code, 0) == child && code == 0
}

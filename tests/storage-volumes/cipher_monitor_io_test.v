// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module volumecli
import os
import crypto.sha256
import encoding.hex
fn C.dup(i32) i32
fn C.dup2(i32, i32) i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C._exit(i32)
$if macos { fn C.mkfifo(const_name &char, mode u16) i32 } $else { fn C.mkfifo(const_name &char, mode u32) i32 }

struct CipherMonitorIO {
mut:
	active bool
	work &VolumeSealFiles = unsafe { nil }
	recovery bool
	opens int
	closes int
	wipes int
	derives int
	discoveries int
	physical bool
	source i32 = -1
	statuses int
	prints int
	sleeps int
	mode int
	reader int
	read_calls int
	stats int
	data_mode int
	data_reads int
	delivered u64
	interrupted bool
	sleep_interrupted bool
	sector u64 = 512
	kind u32 = 1
	flags u64
	masks [3]int
	input string
	credential string
	reference string
}
__global cipher_monitor_io CipherMonitorIO
fn cipher_monitor_record(work &VolumeSealFiles) { assert cipher_monitor_io.active; cipher_monitor_io.work = unsafe { work } }
fn cipher_monitor_erased() {
	assert cipher_monitor_io.active && cipher_monitor_io.work != unsafe { nil } && cipher_monitor_io.derives == if cipher_monitor_io.recovery { 0 } else { 1 }
	unsafe { work := cipher_monitor_io.work; for byte in work.password { assert byte == 0 }; for byte in work.wrapping { assert byte == 0 }; for byte in work.request.key { assert byte == 0 } }
}
fn cipher_monitor_owners() { cipher_monitor_erased(); assert cipher_monitor_io.opens - cipher_monitor_io.closes == 2 && cipher_monitor_io.source >= 0 && cipher_monitor_io.physical && cipher_monitor_io.discoveries == 1 }
fn cipher_monitor_erase(output voidptr, size usize) {
	erase_key(output, size)
	if size == sizeof(VolumeSealFiles) { assert !cipher_monitor_io.physical && cipher_monitor_io.opens == cipher_monitor_io.closes; unsafe { for i in 0 .. int(size) { assert (&u8(output))[i] == 0 } }; cipher_monitor_io.wipes++; cipher_monitor_io.work = unsafe { nil } }
}
fn cipher_monitor_derive(password &u8, size int, salt &u8, output &u8) bool {
	assert cipher_monitor_io.derives == 0 && cipher_monitor_io.discoveries == 0 && size == 6; cipher_monitor_io.derives++
	unsafe { assert password[0] == 0 && password[1] == 10 && password[2] == 0xe2 && password[5] == 0xff; for i in 6 .. 1024 { assert password[i] == 0 }; for i in 0 .. 64 { assert output[i] == 0 } }
	if cipher_monitor_io.mode == 100 { return false }; unsafe { for i in 0 .. 64 { output[i] = u8(i * 29 + 41) }; if cipher_monitor_io.mode == 101 { output[0] ^= 1 } }; return true
}
fn cipher_monitor_file_open(path &char, flags i32) i32 {
	assert flags & (C.O_CLOEXEC | C.O_NOFOLLOW) == C.O_CLOEXEC | C.O_NOFOLLOW && flags & (C.O_WRONLY | C.O_RDWR | C.O_CREAT) == 0 && C.strcmp(path, c'/dev/urandom') != 0
	if flags & C.O_DIRECTORY != 0 { cipher_monitor_erased() }
	fd := C.open(path, flags); if fd >= 0 { cipher_monitor_io.opens++ }; return fd
}
fn cipher_monitor_file_openat(parent i32, path &char, flags i32) i32 {
	cipher_monitor_erased(); assert flags == C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK
	fd := C.openat(parent, path, flags); if fd >= 0 { cipher_monitor_io.opens++; cipher_monitor_io.source = fd }; return fd
}
fn cipher_monitor_file_close(fd i32) i32 {
	if fd == 900 { assert cipher_monitor_io.physical; cipher_monitor_io.physical = false; return 0 }
	cipher_monitor_io.closes++; assert cipher_monitor_io.closes <= cipher_monitor_io.opens; if fd == cipher_monitor_io.source { cipher_monitor_io.source = -1 }; return C.close(fd)
}
fn cipher_monitor_file_flock(fd i32, flags i32) i32 { assert !cipher_monitor_io.active; return C.flock(fd, flags) }
fn cipher_monitor_file_fstat(fd i32, info &C.stat) i32 {
	if fd == cipher_monitor_io.source { cipher_monitor_erased(); cipher_monitor_io.stats++; if cipher_monitor_io.reader == 7 { return -1 } }
	result := C.fstat(fd, info)
	if result == 0 && fd == cipher_monitor_io.source { unsafe { match cipher_monitor_io.reader { 6 { info.st_size++ } 8 { info.st_mode |= 0o004 } 9 { info.st_uid++ } 10 { if cipher_monitor_io.stats == 2 { info.st_mode |= 0o004 } } else {} } } }; return result
}
fn cipher_monitor_file_read(fd i32, output voidptr, size usize) i64 {
	if fd != cipher_monitor_io.source { return C.read(fd, output, size) }; cipher_monitor_erased(); cipher_monitor_io.read_calls++
	match cipher_monitor_io.reader {
		1 { if cipher_monitor_io.read_calls == 1 { unsafe { C.errno = C.EINTR }; return -1 }; return C.read(fd, output, if size > 3 { usize(3) } else { size }) }
		2 { return 0 } 3 { unsafe { C.errno = C.EIO }; return -1 } 4 { return i64(size + 1) } 5 { n := C.read(fd, output, size); return if n == 0 { i64(1) } else { n } } else { return C.read(fd, output, size) }
	}
}
fn cipher_monitor_discover(key &DiskKey, directory &char, writing bool, name &char, mut status Status) i32 {
	cipher_monitor_erased(); assert cipher_monitor_io.opens - cipher_monitor_io.closes == 2 && cipher_monitor_io.source >= 0 && !writing && C.strcmp(directory, c'/dev') == 0 && cipher_monitor_io.discoveries == 0
	cipher_monitor_io.discoveries++; if cipher_monitor_io.mode == 1 { return -1 }; cipher_monitor_io.physical = true; mut observed := DiskKey{}
	if !probe_disk(900, mut observed, mut status) || !key_matches(key, &observed) { cipher_monitor_file_close(900); return -1 }; C.snprintf(name, 256, c'/monitor-original-pin'); return 900
}
fn cipher_monitor_ioctl(fd i32, request u64, output voidptr) i32 {
	cipher_monitor_owners(); assert fd == 900 && request == 0x56560004; cipher_monitor_io.statuses++
	mut status := Status{version: 1, bytes: 16777216, sector: cipher_monitor_io.sector, disk_id: 70, slot: u64(-1), flags: 1 - cipher_monitor_io.flags}
	if cipher_monitor_io.prints > 0 { match cipher_monitor_io.mode { 20 { status.disk_id++ } 21 { status.flags ^= 1 } 22 { status.bytes += status.sector } 23 { status.sector = if status.sector == 512 { u64(4096) } else { u64(512) } } 25 { status.flags |= 2 } else {} } }
	if cipher_monitor_io.mode == 27 && cipher_monitor_io.statuses == 4 { status.disk_id++ }; unsafe { *(&Status(output)) = status }; return 0
}
fn cipher_monitor_pattern(offset u64) u8 { return u8(offset * 13 + (offset >> 7)) }
fn cipher_monitor_pread(fd i32, output voidptr, size usize, offset i64) i64 {
	cipher_monitor_owners(); assert fd == 900
	if offset == 0 {
		sector := if cipher_monitor_io.mode == 23 && cipher_monitor_io.prints > 0 { if cipher_monitor_io.sector == 512 { u64(4096) } else { u64(512) } } else { cipher_monitor_io.sector }; assert size == usize(sector * 2)
		unsafe { for i in 0 .. int(size) { (&u8(output))[i] = 0 } }; put_le(&u8(output), 440, 4, 1); put_le(&u8(output), 510, 2, 0xaa55)
		if cipher_monitor_io.kind == 2 { put_le(&u8(output), 450, 1, 0xee); header := unsafe { &u8(output) + int(sector) }; put_le(header, 0, 8, 0x5452415020494645); put_le(header, 8, 4, 0x10000); put_le(header, 12, 4, 92); put_le(header, 24, 8, 1); put_le(header, 56, 1, 1); put_le(header, 71, 1, 0x83); if cipher_monitor_io.mode == 24 && cipher_monitor_io.prints > 0 { put_le(header, 56, 1, 3) }; put_le(header, 16, 4, crc32(header, 92, 16)) }
		else if cipher_monitor_io.mode == 24 && cipher_monitor_io.prints > 0 { put_le(&u8(output), 440, 4, 3) }; return i64(size)
	}
	assert offset >= 8192 && size > 0 && size <= 65536 && u64(offset) % cipher_monitor_io.sector == 0 && u64(size) % cipher_monitor_io.sector == 0; cipher_monitor_io.data_reads++
	if cipher_monitor_io.mode == 26 && cipher_monitor_io.prints > 0 { unsafe { C.errno = C.EIO }; return -1 }
	match cipher_monitor_io.data_mode { 1 { if !cipher_monitor_io.interrupted { cipher_monitor_io.interrupted = true; unsafe { C.errno = C.EINTR }; return -1 } } 2 { return 0 } 3 { unsafe { C.errno = C.EIO }; return -1 } 4 { return i64(size + 1) } 5 { return i64(size - 1) } else {} }
	delivered := if cipher_monitor_io.data_mode == 1 && size > usize(cipher_monitor_io.sector) { usize(cipher_monitor_io.sector) } else { size }; unsafe { for i in 0 .. int(delivered) { (&u8(output))[i] = cipher_monitor_pattern(u64(offset) + u64(i)) } }
	if offset in [i64(8192), i64(73728)] && cipher_monitor_io.masks[if cipher_monitor_io.prints < 3 { cipher_monitor_io.prints } else { 2 }] != 0 { unsafe { (&u8(output))[0] ^= 1 } }; cipher_monitor_io.delivered += u64(delivered); return i64(delivered)
}
fn cipher_monitor_encode(reference &u8, observed &u8, recovery bool, sample u64, changed_samples u64, output &char) int { cipher_monitor_owners(); if cipher_monitor_io.mode == 7 { return 0 }; return encode_ciphertext_monitor(reference, observed, recovery, sample, changed_samples, output) }
fn cipher_monitor_print(text &char) i32 { cipher_monitor_owners(); if cipher_monitor_io.mode == 8 { return -1 }; cipher_monitor_io.prints++; return C.printf(c'%s', text) }
fn cipher_monitor_flush(stream voidptr) i32 { if cipher_monitor_io.active { cipher_monitor_owners(); if cipher_monitor_io.mode == 9 { return -1 } }; return C.fflush(stream) }
fn cipher_monitor_ferror(stream voidptr) i32 { if cipher_monitor_io.active { cipher_monitor_owners(); if cipher_monitor_io.mode == 10 { return 1 } }; return C.ferror(stream) }
fn cipher_monitor_sleep(remaining u32) u32 {
	cipher_monitor_owners(); assert remaining > 0; cipher_monitor_io.sleeps++
	if cipher_monitor_io.mode == 11 && cipher_monitor_io.sleeps == 1 { for path in [cipher_monitor_io.reference, cipher_monitor_io.input, cipher_monitor_io.credential] { replacement := path + '.replacement'; os.write_file(replacement, 'invalid replaced session input') or { panic(err) }; os.mv(replacement, path) or { panic(err) } } }
	if cipher_monitor_io.mode == 12 && !cipher_monitor_io.sleep_interrupted { cipher_monitor_io.sleep_interrupted = true; return remaining - 1 }; return 0
}
fn cipher_monitor_expected(reference []u8, recovery bool, sector u64, kind u32, flags u64, masks []int) string {
	mut text := ''; mut changed_samples := 0; original := []u8{len: 73728, init: cipher_monitor_pattern(u64(index) + 8192)}; sum := sha256.sum(original); identity := if kind == 1 { 'mbr:00000001' } else { 'gpt:00000001-0000-0000-0000-000000000083' }
	for at, mask in masks { mut data := original.clone(); if mask != 0 { data[0] ^= 1; data[65536] ^= 1; changed_samples++ }; digest := sha256.sum(data)
		text += 'format=VINIXCM1 operation=monitored-ciphertext source=${if recovery { 'recovery' } else { 'volume' }} sample=${at + 1} changed_samples=${changed_samples} session_changed=${int(changed_samples != 0)}\nformat=VINIXCS1 operation=scrubbed-ciphertext mappings=1 matched=${int(mask == 0)} changed=${int(mask != 0)} algorithm=sha256 reference_sha256=' + hex.encode(sha256.sum(reference)) + '\n' + 'disk_bytes=16777216 sector=${sector} identity=${identity} slot=63 offset=8192 bytes=73728 readonly=${flags} result=${if mask == 0 { 'match' } else { 'changed' }} expected_sha256=' + hex.encode(sum[..]) + ' actual_sha256=' + hex.encode(digest[..]) + '\n'
	}; return text
}
fn cipher_monitor_check(input string, credential string, reference string, recovery bool, sector u64, kind u32, flags u64, masks [3]int, mode int, reader int, data_mode int, count u64, expected i32) string {
	capture := os.dir(input) + '/capture'; assert C.fflush(C.stdout) == 0; saved := C.dup(1); fd := C.open(capture.str, C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600)); assert saved >= 0 && fd >= 0 && C.dup2(fd, 1) == 1 && C.close(fd) == 0
	cipher_monitor_io = CipherMonitorIO{active: true, recovery: recovery, sector: sector, kind: kind, flags: flags, masks: masks, mode: mode, reader: reader, data_mode: data_mode, input: input, credential: credential, reference: reference}; number := count.str()
	unsafe { args := [&char(c'vinix-volume'), if recovery { &char(c'monitor-recovery-volume-auto') } else { &char(c'monitor-volume-auto') }, input.str, credential.str, reference.str, &char(c'2'), number.str, &char(nil)]!; assert run(7, &args[0]) == expected }
	assert cipher_monitor_io.work == unsafe { nil } && cipher_monitor_io.opens == cipher_monitor_io.closes && !cipher_monitor_io.physical && cipher_monitor_io.wipes == 1 && cipher_monitor_io.discoveries <= 1 && cipher_monitor_io.derives <= if recovery { 0 } else { 1 }
	cipher_monitor_io.active = false; assert C.fflush(C.stdout) == 0 && C.dup2(saved, 1) == 1 && C.close(saved) == 0; result := os.read_file(capture) or { panic(err) }; os.rm(capture) or { panic(err) }; return result
}
fn test_cipher_monitor_authentication_once_erasure_private_reference_owners_and_complete_streams() {
	work := os.join_path(os.temp_dir(), 'vinix-cipher-monitor-${os.getpid()}'); os.mkdir(work)!; os.chmod(work, 0o700)!; defer { os.rmdir_all(work) or {} }; input := work + '/input'; credential := work + '/credential'; reference := work + '/reference'
	wrapping := [64]u8{init: u8(index * 29 + 41)}; random := [28]u8{init: u8(index * 11 + 3)}; mut source := [320]u8{}; original := []u8{len: 73728, init: cipher_monitor_pattern(u64(index) + 8192)}; digest := sha256.sum(original)
	for recovery in [false, true] { for sector in [u64(512), u64(4096)] { for kind in [u32(1), u32(2)] { for flags in [u64(0), u64(1)] {
		mut disk := DiskKey{bytes: 16777216, sector: sector, kind: kind}; disk.id[0] = 1; if kind == 2 { disk.id[15] = 0x83 }; request := EncryptedRequest{data: Request{slot: 63, offset: 8192, length: 73728, flags: flags}, key: [64]u8{init: u8(index * 13 + 7)}}
		assert if recovery { encode_volume_recovery(&disk, &request, &wrapping[0], &random[0], &source[0]) } else { encode_volume_seal(&disk, &request, &wrapping[0], &random[0], &source[0]) }; keys := if recovery { wrapping[..] } else { [u8(0), 10, 0xe2, 0x82, 0xac, 0xff] }; mut record := [128]u8{}; assert encode_volume_ciphertext(&disk, &request.data, &digest[0], &record[0])
		os.write_file_array(input, source[..])!; os.write_file_array(credential, keys)!; os.write_file_array(reference, record[..])!; for path in [input, credential, reference] { os.chmod(path, 0o600)! }
		for history in 0 .. 8 { masks := [history & 1, (history >> 1) & 1, (history >> 2) & 1]!; for retry in [0, 1] { result := cipher_monitor_check(input, credential, reference, recovery, sector, kind, flags, masks, 0, retry, retry, 3, if history == 0 { i32(0) } else { i32(2) }); assert result == cipher_monitor_expected(record[..], recovery, sector, kind, flags, masks[..]) && cipher_monitor_io.discoveries == 1 && cipher_monitor_io.derives == if recovery { 0 } else { 1 }; assert cipher_monitor_io.statuses == 10 && cipher_monitor_io.delivered == 73728 * 3 && cipher_monitor_io.sleeps == 2 } }
		masks := [0, 1, 0]!; assert cipher_monitor_check(input, credential, reference, recovery, sector, kind, flags, masks, 12, 0, 0, 3, 2) == cipher_monitor_expected(record[..], recovery, sector, kind, flags, masks[..]) && cipher_monitor_io.sleeps == 3
		assert cipher_monitor_check(input, credential, reference, recovery, sector, kind, flags, masks, 11, 0, 0, 3, 2) == cipher_monitor_expected(record[..], recovery, sector, kind, flags, masks[..]); for path in [input, credential, reference] { assert os.read_file(path)! == 'invalid replaced session input' }; os.write_file_array(input, source[..])!; os.write_file_array(credential, keys)!; os.write_file_array(reference, record[..])!; for path in [input, credential, reference] { os.chmod(path, 0o600)! }
		for mode in [1, 7, 8, 9, 10, 27] { result := cipher_monitor_check(input, credential, reference, recovery, sector, kind, flags, [1, 0, 0]!, mode, 0, 0, 3, 1); if mode !in [9, 10] { assert !result.contains('format=VINIXCM1') } }
		for mode in 20 .. 27 { result := cipher_monitor_check(input, credential, reference, recovery, sector, kind, flags, [1, 0, 0]!, mode, 0, 0, if mode == 26 { u64(0) } else { u64(3) }, 1); assert result.starts_with(cipher_monitor_expected(record[..], recovery, sector, kind, flags, [1])) && result.count('format=VINIXCM1') == 1 }
		for reader in 2 .. 11 { result := cipher_monitor_check(input, credential, reference, recovery, sector, kind, flags, [0, 0, 0]!, 0, reader, 0, 3, 1); assert !result.contains('format=VINIXCM1') && cipher_monitor_io.discoveries == 0 }
		for data_mode in 2 .. 6 { assert !cipher_monitor_check(input, credential, reference, recovery, sector, kind, flags, [1, 0, 0]!, 0, 0, data_mode, 3, 1).contains('format=VINIXCM1') }
		for path in [input, credential, reference] { os.chmod(path, 0o644)!; assert !cipher_monitor_check(input, credential, reference, recovery, sector, kind, flags, [0, 0, 0]!, 0, 0, 0, 3, 1).contains('format=VINIXCM1') && cipher_monitor_io.discoveries == 0; os.chmod(path, 0o600)! }
		for at in 0 .. 128 { mut bad := record; bad[at] ^= 1; os.write_file_array(reference, bad[..])!; cipher_monitor_check(input, credential, reference, recovery, sector, kind, flags, [0, 0, 0]!, 0, 0, 0, 3, 1); assert cipher_monitor_io.discoveries == 0 }; os.write_file_array(reference, record[..])!
		mut wrong := request.data; wrong.flags ^= 1; mut bad := [128]u8{}; assert encode_volume_ciphertext(&disk, &wrong, &digest[0], &bad[0]); os.write_file_array(reference, bad[..])!; cipher_monitor_check(input, credential, reference, recovery, sector, kind, flags, [0, 0, 0]!, 0, 0, 0, 3, 1); assert cipher_monitor_io.discoveries == 0; os.write_file_array(reference, record[..])!
		if !recovery { for mode in [100, 101] { cipher_monitor_check(input, credential, reference, recovery, sector, kind, flags, [0, 0, 0]!, mode, 0, 0, 3, 1); assert cipher_monitor_io.discoveries == 0 } }; mut corrupt := source; corrupt[192] ^= 1; os.write_file_array(input, corrupt[..])!; cipher_monitor_check(input, credential, reference, recovery, sector, kind, flags, [0, 0, 0]!, 0, 0, 0, 3, 1); assert cipher_monitor_io.discoveries == 0; os.write_file_array(input, source[..])!
		if recovery && sector == 512 && kind == 1 && flags == 0 {
			long := cipher_monitor_check(input, credential, reference, recovery, sector, kind, flags, [0, 0, 0]!, 0, 0, 0, 512, 0); assert long.count('format=VINIXCM1') == 512 && cipher_monitor_io.discoveries == 1 && cipher_monitor_io.derives == 0
			for path in [work + '/missing', work] { cipher_monitor_check(input, credential, path, recovery, sector, kind, flags, [0, 0, 0]!, 0, 0, 0, 3, 1); assert cipher_monitor_io.discoveries == 0 }; os.symlink(reference, work + '/link')!; assert C.mkfifo((work + '/fifo').str, 0o600) == 0; for path in [work + '/link', work + '/fifo'] { cipher_monitor_check(input, credential, path, recovery, sector, kind, flags, [0, 0, 0]!, 0, 0, 0, 3, 1); assert cipher_monitor_io.discoveries == 0 }
			directory_fd := C.open(work.str, C.O_RDONLY | C.O_DIRECTORY); assert directory_fd >= 0 && C.flock(directory_fd, C.LOCK_EX | C.LOCK_NB) == 0; assert cipher_monitor_check(input, credential, reference, recovery, sector, kind, flags, masks, 0, 0, 0, 3, 2) == cipher_monitor_expected(record[..], recovery, sector, kind, flags, masks[..]); assert C.close(directory_fd) == 0
			child := C.fork(); assert child >= 0; if child == 0 { fd := C.open(c'/dev/null', C.O_RDONLY); if fd < 0 || C.dup2(fd, 1) != 1 { C._exit(3) }; C.close(fd); cipher_monitor_io = CipherMonitorIO{active: true, recovery: true, masks: [1, 0, 0]!, input: input, credential: credential, reference: reference}; result := monitor_volume_ciphertext(input.str, credential.str, reference.str, 0, 3, true); C._exit(if result == 1 && cipher_monitor_io.opens == cipher_monitor_io.closes && cipher_monitor_io.wipes == 1 && !cipher_monitor_io.physical { 0 } else { 5 }) }; mut code := i32(-1); assert C.waitpid(child, &code, 0) == child && code == 0
		}
		assert os.read_bytes(input)! == source[..] && os.read_bytes(credential)! == keys && os.read_bytes(reference)! == record[..]
	} } } }
}

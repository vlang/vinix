// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module volumecli

import os
import crypto.sha256
import encoding.hex

fn C.fork() i32
fn C.dup2(i32, i32) i32
fn C.waitpid(i32, &i32, i32) i32
fn C._exit(i32)
fn C.setvbuf(voidptr, &char, i32, usize) i32
$if macos {
	fn C.mkfifo(const_name &char, mode u16) i32
} $else {
	fn C.mkfifo(const_name &char, mode u32) i32
}

struct DataIO {
mut:
	mode int
	publish_mode int
	opened int
	closed int
	statuses [2]int
	identity_reads [2]int
	data_reads [2]int
	delivered [2]u64
	interrupted bool
	writes int
	flushes int
	publish_closes int
	renames int
}

__global data_io DataIO

fn data_mock_open(path &char, flags i32) i32 {
	disk := if C.strcmp(path, c'/hash-disk-0') == 0 { 0 } else if C.strcmp(path, c'/hash-disk-1') == 0 { 1 } else { -1 }
	if disk < 0 { return C.open(path, flags) }
	assert flags == C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK
	if data_io.mode == 4 && disk == 0 { unsafe { C.errno = C.ENODEV }; return -1 }
	data_io.opened++; return i32(900001 + disk)
}

fn data_mock_close(fd i32) i32 {
	if fd < 900001 || fd > 900002 { return C.close(fd) }
	data_io.closed++; assert data_io.closed <= data_io.opened; return 0
}

fn data_mock_ioctl(fd i32, request u64, output voidptr) i32 {
	if fd < 900001 || fd > 900002 { return C.ioctl(fd, request, output) }
	assert request == 0x56560004; disk := int(fd - 900001); data_io.statuses[disk]++
	if data_io.mode == 5 { unsafe { C.errno = C.ENOTTY }; return -1 }
	sector := if disk == 0 { u64(512) } else { u64(4096) }
	mut status := Status{version: 1, bytes: 262144, sector: sector, flags: u64(disk), disk_id: u64(70 + disk), slot: u64(-1)}
	match data_io.mode {
		6 { status.flags |= 2 }
		7 { status.flags |= 8 }
		8 { status.flags |= 16; status.start = 512 }
		9 { status.reserved = 1 }
		10 { if disk == 1 { status.disk_id = 70 } }
		11 { if disk == 0 && data_io.statuses[0] == 2 { status.bytes += sector } }
		12 { if disk == 0 && data_io.statuses[0] == 3 { status.disk_id++ } }
		13 { if disk == 1 && data_io.statuses[1] == 3 { status.sector = 512 } }
		else {}
	}
	unsafe { *(&Status(output)) = status }; return 0
}

fn data_pattern(disk int, offset u64) u8 { return u8(u64(disk * 71) + offset * 13 + (offset >> 7)) }

fn data_mock_pread(fd i32, output voidptr, size usize, offset i64) i64 {
	if fd < 900001 || fd > 900002 { return C.pread(fd, output, size, offset) }
	disk := int(fd - 900001); sector := if disk == 0 { u64(512) } else { u64(4096) }
	if offset == 0 {
		assert size == usize(sector * 2) || (data_io.mode == 13 && disk == 1 && size == 1024); data_io.identity_reads[disk]++
		unsafe { for i in 0 .. int(size) { (&u8(output))[i] = 0 } }
		put_le(&u8(output), 440, 4, u64(disk + 1)); put_le(&u8(output), 510, 2, 0xaa55)
		if disk == 1 && size >= usize(sector * 2) {
			put_le(&u8(output), 450, 1, 0xee); header := unsafe { &u8(output) + int(sector) }
			put_le(header, 0, 8, 0x5452415020494645); put_le(header, 8, 4, 0x10000); put_le(header, 12, 4, 92)
			put_le(header, 24, 8, 1); put_le(header, 56, 1, 2); put_le(header, 71, 1, 0x83); put_le(header, 16, 4, crc32(header, 92, 16))
		}
		if data_io.mode == 14 && disk == 1 { return i64(size - 1) }
		if data_io.mode == 15 && disk == 0 && data_io.identity_reads[0] == 3 { put_le(&u8(output), 440, 4, 3) }
		return i64(size)
	}
	assert offset >= 8192 && size > 0 && size <= 65536 && u64(offset) % sector == 0 && u64(size) % sector == 0
	data_io.data_reads[disk]++
	if data_io.mode == 1 && !data_io.interrupted { data_io.interrupted = true; unsafe { C.errno = C.EINTR }; return -1 }
	if disk == 1 {
		if data_io.mode == 2 { return 0 }
		if data_io.mode in [3, 20] { unsafe { C.errno = C.EIO }; return -1 }
		if data_io.mode == 16 { return i64(size + 1) }
		if data_io.mode == 17 { return i64(size - 1) }
	}
	delivered := if data_io.mode == 1 && size > usize(sector) { usize(sector) } else { size }
	unsafe { for i in 0 .. int(delivered) { (&u8(output))[i] = data_pattern(disk, u64(offset) + u64(i)) } }
	if (data_io.mode == 18 && disk == 1) || data_io.mode in [19, 20] { unsafe { (&u8(output))[0] ^= 1 } }
	data_io.delivered[disk] += u64(delivered); return i64(delivered)
}

fn data_publish_write(fd i32, bytes voidptr, size usize) i64 {
	data_io.writes++
	if data_io.publish_mode == 1 && data_io.writes == 1 { unsafe { C.errno = C.EINTR }; return -1 }
	if data_io.publish_mode == 2 { unsafe { C.errno = C.EIO }; return -1 }
	return C.write(fd, bytes, if data_io.publish_mode == 1 && size > 3 { usize(3) } else { size })
}

fn data_publish_fsync(fd i32) i32 {
	data_io.flushes++
	if (data_io.publish_mode == 3 && data_io.flushes == 1) || (data_io.publish_mode == 4 && data_io.flushes == 2) { unsafe { C.errno = C.EIO }; return -1 }
	return C.fsync(fd)
}

fn data_publish_close(fd i32) i32 {
	data_io.publish_closes++; closed := C.close(fd)
	if data_io.publish_mode == 5 && data_io.publish_closes == 1 { unsafe { C.errno = C.EIO }; return -1 }; return closed
}

fn data_publish_renameat(from i32, source &char, to i32, destination &char) i32 {
	data_io.renames++
	if data_io.publish_mode == 6 { unsafe { C.errno = C.EIO }; return -1 }; return C.renameat(from, source, to, destination)
}

fn data_io_fixture(mut manifest DataManifest, mut devices DataDevices) {
	for disk in 0 .. 2 {
		mut plan := Plan{count: 1, key: DiskKey{bytes: 262144, sector: if disk == 0 { u64(512) } else { u64(4096) }, kind: u32(disk + 1)}}
		plan.key.id[0] = u8(disk + 1); if disk == 1 { plan.key.id[15] = 0x83 }
		plan.rows[0] = Request{slot: u32(20 + disk), offset: 8192, length: 73728, flags: u64(disk)}; assert append_plan(mut manifest.set, &plan)
		manifest.digests.disks[disk] = u32(disk); manifest.digests.slots[disk] = u32(20 + disk); manifest.digests.count++
		bytes := []u8{len: 73728, init: data_pattern(disk, u64(index) + 8192)}; sum := sha256.sum(bytes)
		for byte in 0 .. 32 { manifest.digests.values[disk][byte] = sum[byte] }
	}
	devices.count = 2; devices.disks[0] = 1; devices.disks[1] = 0; devices.paths[0] = unsafe { &char(c'/hash-disk-1') }; devices.paths[1] = unsafe { &char(c'/hash-disk-0') }
}


fn C.dup(i32) i32
fn scrub_io_expected(manifest &DataManifest, mask int) string {
	changed := int(mask & 1 != 0) + int(mask & 2 != 0)
	mut bytes := [11392]u8{}; size := encode_data_manifest(manifest, &bytes[0]); fingerprint := hex.encode(sha256.sum(bytes[..size]))
	mut report := 'format=VINIXSR1 operation=scrubbed-data disks=2 mappings=2 matched=${2 - changed} changed=${changed} algorithm=sha256 reference_sha256=${fingerprint}\n'
	for disk in 0 .. 2 {
		mut data := []u8{len: 73728, init: data_pattern(disk, u64(index) + 8192)}
		if mask & (1 << disk) != 0 { data[0] ^= 1; data[65536] ^= 1 }
		actual := sha256.sum(data); result := if mask & (1 << disk) != 0 { 'changed' } else { 'match' }
		report += 'disk=${disk} slot=${20 + disk} offset=8192 bytes=73728 readonly=${disk} result=${result} expected_sha256=' + hex.encode(manifest.digests.values[disk][..]) + ' actual_sha256=' + hex.encode(actual) + '\n'
	}
	return report
}

struct DataMonitorIO {
mut:
	active bool
	files_opened int
	files_closed int
	source i32 = -1
	discoveries int
	prints int
	sleeps int
	mode int
	reader_mode int
	reads int
	sleep_interrupted bool
	masks [4]int
	path string
}
__global data_monitor_io DataMonitorIO
fn monitor_file_open(path &char, flags i32) i32 { if data_monitor_io.active { assert flags == C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC }; fd := C.open(path, flags); if data_monitor_io.active && fd >= 0 { data_monitor_io.files_opened++ }; return fd }
fn monitor_file_openat(parent i32, path &char, flags i32) i32 { if data_monitor_io.active { assert flags == C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK }; fd := C.openat(parent, path, flags); if data_monitor_io.active && fd >= 0 { data_monitor_io.files_opened++; data_monitor_io.source = fd }; return fd }
fn monitor_file_close(fd i32) i32 { if data_monitor_io.active { data_monitor_io.files_closed++; assert data_monitor_io.files_closed <= data_monitor_io.files_opened }; return C.close(fd) }
fn monitor_file_flock(fd i32, flags i32) i32 { assert !data_monitor_io.active; return C.flock(fd, flags) }
fn monitor_file_stat(fd i32, info &C.stat) i32 { if data_monitor_io.reader_mode == 7 { return -1 }; result := C.fstat(fd, info); if data_monitor_io.reader_mode == 6 { unsafe { info.st_size++ } }; if data_monitor_io.reader_mode == 8 { unsafe { info.st_mode = (info.st_mode & ~C.S_IFMT) | C.S_IFDIR } }; return result }
fn monitor_file_read(fd i32, output voidptr, size usize) i64 {
	data_monitor_io.reads++
	match data_monitor_io.reader_mode {
		1 { if data_monitor_io.reads == 1 { unsafe { C.errno = C.EINTR }; return -1 }; return C.read(fd, output, if size > 3 { usize(3) } else { size }) }
		2 { return 0 } 3 { unsafe { C.errno = C.EIO }; return -1 } 4 { return i64(size + 1) }
		5 { n := C.read(fd, output, size); return if n == 0 { i64(1) } else { n } }
		else { return C.read(fd, output, size) }
	}
}
fn monitor_mock_discover(key &DiskKey, directory &char, writing bool, output &char, mut status Status) i32 {
	assert data_monitor_io.active && !writing && C.strcmp(directory, c'/dev') == 0 && data_monitor_io.files_opened == 2 && data_monitor_io.files_closed == 0
	data_monitor_io.discoveries++; disk := int(key.id[0]) - 1; assert disk in [0, 1]
	fd := data_mock_open(if disk == 0 { &char(c'/hash-disk-0') } else { &char(c'/hash-disk-1') }, C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK)
	if fd < 0 { return -1 }; mut observed := DiskKey{}
	if !probe_disk(fd, mut observed, mut status) || !key_matches(key, &observed) { data_mock_close(fd); return -1 }; C.snprintf(output, 256, c'/hash-disk-%d', disk); return fd
}
fn monitor_mock_ioctl(fd i32, request u64, output voidptr) i32 {
	result := data_mock_ioctl(fd, request, output)
	if fd in [i32(900001), i32(900002)] && result == 0 { unsafe { status := &Status(output)
		if data_monitor_io.prints > 0 && fd == 900002 {
			match data_monitor_io.mode { 22 { status.flags ^= 1 } 23 { status.disk_id++ } 24 { status.bytes += status.sector } 25 { status.sector = 512 } 27 { status.flags |= 2 } else {} }
		}
		if data_monitor_io.mode == 28 && data_io.statuses[int(fd - 900001)] == 4 { status.disk_id++ }
	} }
	return result
}
fn monitor_mock_pread(fd i32, output voidptr, size usize, offset i64) i64 {
	if data_monitor_io.mode == 29 && data_monitor_io.prints > 0 && fd == 900002 && offset != 0 { unsafe { C.errno = C.EIO }; return -1 }
	if data_monitor_io.mode == 25 && data_monitor_io.prints > 0 && fd == 900002 && offset == 0 {
		assert size == 1024; unsafe { for i in 0 .. int(size) { (&u8(output))[i] = 0 } }; put_le(&u8(output), 440, 4, 2); put_le(&u8(output), 510, 2, 0xaa55); return i64(size)
	}
	n := data_mock_pread(fd, output, size, offset)
	if fd in [i32(900001), i32(900002)] && n > 0 {
		if offset == 0 { if data_monitor_io.mode == 26 && data_monitor_io.prints > 0 && fd == 900001 { put_le(&u8(output), 440, 4, 3) } }
		else if offset in [i64(8192), i64(73728)] && data_monitor_io.masks[if data_monitor_io.prints < 4 { data_monitor_io.prints } else { 3 }] & (1 << int(fd - 900001)) != 0 { unsafe { (&u8(output))[0] ^= 1 } }
	}
	return n
}
fn monitor_owners() { assert data_monitor_io.active && data_monitor_io.files_opened == 2 && data_monitor_io.files_closed == 0 && data_io.opened == 2 && data_io.closed == 0 }
fn monitor_mock_encode(manifest &DataManifest, observed &DataDigests, sample u64, changed_samples u64, output &char) int { monitor_owners(); if data_monitor_io.mode == 7 { return 0 }; return encode_data_monitor(manifest, observed, sample, changed_samples, output) }
fn monitor_mock_print(text &char) i32 { monitor_owners(); if data_monitor_io.mode == 14 { return -1 }; data_monitor_io.prints++; return C.printf(c'%s', text) }
fn monitor_mock_flush(stream voidptr) i32 { if data_monitor_io.active { monitor_owners(); if data_monitor_io.mode == 8 { return -1 } }; return C.fflush(stream) }
fn monitor_mock_ferror(stream voidptr) i32 { if data_monitor_io.active { monitor_owners(); if data_monitor_io.mode == 9 { return 1 } }; return C.ferror(stream) }
fn monitor_mock_sleep(remaining u32) u32 {
	monitor_owners(); assert remaining > 0; data_monitor_io.sleeps++
	if data_monitor_io.mode == 21 && data_monitor_io.sleeps == 1 { replacement := data_monitor_io.path + '.replacement'; os.write_file(replacement, 'invalid replacement reference') or { panic(err) }; os.mv(replacement, data_monitor_io.path) or { panic(err) } }
	if data_monitor_io.mode == 30 && !data_monitor_io.sleep_interrupted { data_monitor_io.sleep_interrupted = true; return remaining - 1 }
	return 0
}
fn monitor_io_expected(manifest &DataManifest, masks []int) string {
	mut result := ''; mut changed_samples := 0
	for sample, mask in masks { if mask != 0 { changed_samples++ }; result += 'format=VINIXDM1 operation=monitored-data sample=${sample + 1} changed_samples=${changed_samples} session_changed=${int(changed_samples != 0)}\n' + scrub_io_expected(manifest, mask) }
	return result
}
fn monitor_io_check(path string, masks [4]int, mode int, physical_mode int, reader_mode int, count u64, expected i32) string {
	capture := path + '.capture'; assert C.fflush(C.stdout) == 0; saved := C.dup(1); fd := C.open(capture.str, C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600)); assert saved >= 0 && fd >= 0 && C.dup2(fd, 1) == 1 && C.close(fd) == 0
	data_io = DataIO{mode: physical_mode}; data_monitor_io = DataMonitorIO{active: true, mode: mode, reader_mode: reader_mode, masks: masks, path: path}
	assert monitor_manifest_data(path.str, 2, count) == expected
	assert data_io.opened == data_io.closed && data_monitor_io.files_opened == data_monitor_io.files_closed && data_monitor_io.discoveries <= 2
	data_monitor_io.active = false; assert C.fflush(C.stdout) == 0 && C.dup2(saved, 1) == 1 && C.close(saved) == 0
	text := os.read_file(capture) or { panic(err) }; os.rm(capture) or { panic(err) }; return text
}
fn test_monitor_real_stream_complete_histories_retries_source_replacement_and_session_owners() {
	work := os.join_path(os.temp_dir(), 'vinix-data-monitor-${os.getpid()}'); os.mkdir(work)!; defer { os.rmdir_all(work) or {} }; path := work + '/reference'
	mut manifest := DataManifest{}; mut devices := DataDevices{}; data_io_fixture(mut manifest, mut devices); mut bytes := [11392]u8{}; size := encode_data_manifest(&manifest, &bytes[0]); os.write_file_array(path, bytes[..size])!; os.chmod(path, 0o644)!
	for history in 0 .. 64 { masks := [history & 3, (history >> 2) & 3, (history >> 4) & 3, 0]!; expected := if history == 0 { i32(0) } else { i32(2) }
		for retry in [0, 1] { text := monitor_io_check(path, masks, 0, retry, retry, 3, expected); assert text == monitor_io_expected(&manifest, masks[..3]) && data_io.opened == 2 && data_io.closed == 2 && data_monitor_io.discoveries == 2 && data_io.statuses == [10, 10]! && data_monitor_io.sleeps == 2 && data_io.delivered == [u64(73728 * 3), u64(73728 * 3)]! }
	}
	masks := [0, 3, 0, 0]!; assert monitor_io_check(path, masks, 30, 0, 0, 3, 2) == monitor_io_expected(&manifest, masks[..3]) && data_monitor_io.sleeps == 3
	assert monitor_io_check(path, masks, 21, 0, 0, 3, 2) == monitor_io_expected(&manifest, masks[..3]) && os.read_file(path)! == 'invalid replacement reference'; os.write_file_array(path, bytes[..size])!
	mut owner := PlanEdit{}; assert open_plan_edit(path.str, mut owner, true); assert monitor_io_check(path, masks, 0, 0, 0, 3, 2) == monitor_io_expected(&manifest, masks[..3]); close_plan_edit(mut owner)
	for mode in [7, 8, 9, 14, 28] { text := monitor_io_check(path, [3, 0, 0, 0]!, mode, 0, 0, 3, 1); if mode !in [8, 9] { assert !text.contains('format=VINIXDM1') }; assert os.read_bytes(path)! == bytes[..size] }
	for physical_mode in [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 20] { text := monitor_io_check(path, [0, 0, 0, 0]!, 0, physical_mode, 0, 3, 1); assert !text.contains('format=VINIXDM1') }
	for mode in 22 .. 30 { if mode == 28 { continue }; text := monitor_io_check(path, [3, 0, 0, 0]!, mode, 0, 0, if mode == 29 { u64(0) } else { u64(3) }, 1); assert text.starts_with(monitor_io_expected(&manifest, [3])) && text.count('format=VINIXDM1') == 1 }
	for mode in 2 .. 9 { text := monitor_io_check(path, [0, 0, 0, 0]!, 0, 0, mode, 3, 1); assert data_monitor_io.discoveries == 0 && data_io.opened == 0 && !text.contains('format=VINIXDM1') }
	for input in [work, work + '/missing'] { monitor_io_check(input, [0, 0, 0, 0]!, 0, 0, 0, 3, 1); assert data_monitor_io.discoveries == 0 }
	os.symlink(path, work + '/link')!; assert C.mkfifo((work + '/fifo').str, 0o600) == 0; for input in [work + '/link', work + '/fifo'] { monitor_io_check(input, [0, 0, 0, 0]!, 0, 0, 0, 3, 1); assert data_monitor_io.discoveries == 0 }
	for at in 0 .. size { mut bad := bytes; bad[at] ^= 1; os.write_file_array(path, bad[..size])!; monitor_io_check(path, [0, 0, 0, 0]!, 0, 0, 0, 3, 1); assert data_monitor_io.discoveries == 0 }; os.write_file_array(path, bytes[..size])!
	text := monitor_io_check(path, [0, 0, 0, 0]!, 0, 0, 0, 512, 0); assert text.count('format=VINIXDM1') == 512 && data_monitor_io.discoveries == 2 && data_io.opened == 2
	child := C.fork(); assert child >= 0; if child == 0 { fd := C.open(c'/dev/null', C.O_RDONLY); if fd < 0 || C.dup2(fd, 1) != 1 { C._exit(3) }; C.close(fd); data_io = DataIO{}; data_monitor_io = DataMonitorIO{active: true, masks: [3, 0, 0, 0]!}; result := monitor_manifest_data(path.str, 0, 3); C._exit(if result == 1 && data_io.opened == data_io.closed && data_monitor_io.files_opened == data_monitor_io.files_closed { 0 } else { 5 }) }; mut code := i32(-1); assert C.waitpid(child, &code, 0) == child && code == 0
}

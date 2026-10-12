// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module volumecli

import os
import crypto.sha256

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
		if data_io.mode == 3 { unsafe { C.errno = C.EIO }; return -1 }
		if data_io.mode == 16 { return i64(size + 1) }
		if data_io.mode == 17 { return i64(size - 1) }
	}
	delivered := if data_io.mode == 1 && size > usize(sector) { usize(sector) } else { size }
	unsafe { for i in 0 .. int(delivered) { (&u8(output))[i] = data_pattern(disk, u64(offset) + u64(i)) } }
	if data_io.mode == 18 && disk == 1 { unsafe { (&u8(output))[0] ^= 1 } }
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

fn test_data_hash_verify_all_readonly_pin_rechecks_short_reads_corruption_and_later_failures() {
	work := os.join_path(os.temp_dir(), 'vinix-data-io-${os.getpid()}'); os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	bundle := work + '/saved.vset'; path := work + '/data.vhash'; mut expected := DataManifest{}; mut devices := DataDevices{}
	data_io_fixture(mut expected, mut devices); assert publish_bundle(bundle.str, &expected.set)
	mut bytes := [11392]u8{}; size := encode_data_manifest(&expected, &bytes[0]); original := os.read_bytes(bundle)!
	data_io = DataIO{}; assert hash_bundle_data(bundle.str, path.str, &devices) == 0 && os.read_bytes(path)! == bytes[..size] && os.read_bytes(bundle)! == original
	assert data_io.opened == 2 && data_io.closed == 2 && data_io.statuses == [3, 3]! && data_io.delivered == [u64(73728), 73728]!
	for mode in 0 .. 19 {
		data_io = DataIO{mode: mode}; expected_status := if mode in [0, 1, 18] { 0 } else { 1 }
		assert hash_bundle_data(bundle.str, path.str, &devices) == expected_status
		assert data_io.closed == data_io.opened && os.read_bytes(bundle)! == original
		if mode != 18 { assert os.read_bytes(path)! == bytes[..size] }
		if mode == 18 { assert os.read_bytes(path)! != bytes[..size]; os.write_file_array(path, bytes[..size])! }
		data_io = DataIO{mode: mode}
		assert verify_manifest_data(path.str, &devices, false) == if mode in [0, 1] { 0 } else { 1 }
		assert data_io.closed == data_io.opened && os.read_bytes(path)! == bytes[..size]
	}
	// Complete participant checks precede all physical opens; offline show has
	// no participant/publisher dependency, including under a writer lock.
	for bad in 0 .. 4 {
		mut wrong := devices; if bad == 0 { wrong.count = 1 } else if bad == 1 { wrong.disks[1] = 1 } else if bad == 2 { wrong.disks[1] = 2 } else { wrong.paths[1] = unsafe { &char(c'') } }
		data_io = DataIO{}; assert verify_manifest_data(path.str, &wrong, false) == 1 && data_io.opened == 0
	}
	mut edit := PlanEdit{}; assert open_plan_edit(path.str, mut edit, true); data_io = DataIO{}
	assert hash_bundle_data(bundle.str, path.str, &devices) == 1 && data_io.opened == 0
	assert verify_manifest_data(path.str, &devices, false) == 0 && verify_manifest_data(path.str, unsafe { nil }, true) == 0
	close_plan_edit(mut edit)
	for input in [work, work + '/missing'] { data_io = DataIO{}; assert verify_manifest_data(input.str, &devices, false) == 1 && data_io.opened == 0 }
	os.symlink(path, work + '/link')!; data_io = DataIO{}; assert verify_manifest_data((work + '/link').str, &devices, false) == 1 && data_io.opened == 0
	assert C.mkfifo((work + '/fifo').str, 0o600) == 0
	for destination in [work, work + '/link', work + '/fifo'] {
		data_io = DataIO{}; assert hash_bundle_data(bundle.str, destination.str, &devices) == 1 && data_io.opened == 0 && os.read_bytes(bundle)! == original && os.read_bytes(path)! == bytes[..size]
	}
	mut corrupted := os.read_bytes(path)!; corrupted[corrupted.len - 1] ^= 1; os.write_file_array(path, corrupted)!; data_io = DataIO{}
	assert verify_manifest_data(path.str, &devices, false) == 1 && data_io.opened == 0
	data_io = DataIO{}; assert hash_bundle_data(bundle.str, bundle.str, &devices) == 1 && data_io.opened == 0 && os.read_bytes(bundle)! == original
	assert hash_bundle_data(bundle.str, (work + '/./saved.vset').str, &devices) == 1 && data_io.opened == 0 && os.read_bytes(bundle)! == original
}

fn test_data_manifest_changed_and_equal_publication_faults_and_retry_both_flushes() {
	work := os.join_path(os.temp_dir(), 'vinix-data-publish-${os.getpid()}'); os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	bundle := work + '/saved.vset'; path := work + '/data.vhash'; mut expected := DataManifest{}; mut devices := DataDevices{}
	data_io_fixture(mut expected, mut devices); data_io = DataIO{}; assert publish_bundle(bundle.str, &expected.set)
	mut bytes := [11392]u8{}; size := encode_data_manifest(&expected, &bytes[0])
	for equal in [false, true] { for mode in 1 .. 7 {
		os.write_file_array(path, if equal { bytes[..size] } else { [u8(91), 42] })!; original := os.read_bytes(path)!
		data_io = DataIO{publish_mode: mode}; assert hash_bundle_data(bundle.str, path.str, &devices) == if mode == 1 { 0 } else { 1 }
		assert data_io.closed == 2 && data_io.opened == 2 && data_io.publish_closes == 2 && data_io.writes > 0
		assert os.ls(work)!.len == 2; current := os.read_bytes(path)!
		if mode in [1, 4] { assert current == bytes[..size] && data_io.flushes == 2 && data_io.renames == 1 } else { assert current == original }
		data_io = DataIO{}; assert hash_bundle_data(bundle.str, path.str, &devices) == 0 && os.read_bytes(path)! == bytes[..size]
		assert data_io.flushes == 2 && data_io.renames == 1 && data_io.writes > 0 && data_io.closed == 2
		data_io = DataIO{publish_mode: mode}; assert verify_manifest_data(path.str, &devices, false) == 0 && data_io.flushes == 0 && data_io.writes == 0 && data_io.renames == 0
	} }
}

fn test_data_checksum_reports_detect_buffered_stdout_failure_and_drain_all_descriptors() {
	work := os.join_path(os.temp_dir(), 'vinix-data-output-${os.getpid()}'); os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	bundle := work + '/saved.vset'; path := work + '/data.vhash'; mut expected := DataManifest{}; mut devices := DataDevices{}
	data_io_fixture(mut expected, mut devices); data_io = DataIO{}; assert publish_bundle(bundle.str, &expected.set)
	assert hash_bundle_data(bundle.str, path.str, &devices) == 0 && C.fflush(C.stdout) == 0; original := os.read_bytes(path)!
	for action in 0 .. 3 {
		child := C.fork(); assert child >= 0
		if child == 0 {
			fd := C.open(c'/dev/null', C.O_RDONLY); if fd < 0 || C.dup2(fd, 1) != 1 { C._exit(2) }; C.close(fd)
			mut buffer := [4096]char{}; if C.setvbuf(C.stdout, &buffer[0], C._IOFBF, 4096) != 0 { C._exit(3) }; data_io = DataIO{}
			result := if action == 0 { hash_bundle_data(bundle.str, path.str, &devices) } else { verify_manifest_data(path.str, &devices, action == 2) }
			C._exit(if result == 1 && data_io.opened == data_io.closed { 0 } else { 4 })
		}
		mut code := i32(-1); assert C.waitpid(child, &code, 0) == child && code == 0 && os.read_bytes(path)! == original
	}
}

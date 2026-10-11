// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module volumecli

import os

fn C.fork() i32
fn C.dup2(i32, i32) i32
fn C.waitpid(i32, &i32, i32) i32
fn C._exit(i32)
fn C.setvbuf(voidptr, &char, i32, usize) i32

struct CapacityIO {
mut:
	mode           int
	sector         u64 = 512
	kind           u32 = 1
	readonly       bool
	statuses       int
	reads          int
	opened         int
	closed         int
	publish_mode   int
	writes         int
	flushes        int
	publish_closes int
	renames        int
}

__global capacity_io CapacityIO

fn capacity_mock_open(path &char, flags i32) i32 {
	if C.strcmp(path, c'/capacity-device') != 0 { return C.open(path, flags) }
	assert flags == C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK
	if capacity_io.mode == 12 {
		unsafe { C.errno = C.ENODEV }
		return -1
	}
	capacity_io.opened++
	return 999991
}

fn capacity_mock_close(fd i32) i32 {
	if fd != 999991 { return C.close(fd) }
	capacity_io.closed++
	assert capacity_io.closed == capacity_io.opened
	return 0
}

fn capacity_mock_ioctl(fd i32, request u64, output voidptr) i32 {
	assert fd == 999991 && request == 0x56560004 // No mutation request is allowed.
	capacity_io.statuses++
	if capacity_io.mode == 3 {
		unsafe { C.errno = C.EIO }
		return -1
	}
	mut result := Status{
		version: 1
		bytes:   25165824
		sector:  capacity_io.sector
		flags:   4 | u64(capacity_io.readonly)
		disk_id: 7
		slot:    u64(-1)
	}
	match capacity_io.mode {
		4 { result.flags |= 2 }
		5 { result.flags |= 8 }
		6 {
			result.flags |= 16
			result.start = 512
		}
		7 { result.sector = 4096 }
		10 {
			if capacity_io.statuses == 2 { result.bytes += 512 }
		}
		11 {
			if capacity_io.statuses == 2 { result.disk_id++ }
		}
		17 { result.reserved = 1 }
		else {}
	}
	unsafe { *(&Status(output)) = result }
	return 0
}

fn capacity_mock_pread(fd i32, output voidptr, size usize, offset i64) i64 {
	assert fd == 999991 && offset == 0 && size >= 1024 && size <= 8192
	capacity_io.reads++
	if capacity_io.mode == 1 && capacity_io.reads == 1 {
		unsafe { C.errno = C.EINTR }
		return -1
	}
	if capacity_io.mode == 2 || (capacity_io.mode == 14 && capacity_io.reads == 2) {
		return i64(size - 1)
	}
	if capacity_io.mode == 15 && capacity_io.reads == 2 {
		unsafe { C.errno = C.EIO }
		return -1
	}
	unsafe {
		for i in 0 .. int(size) { (&u8(output))[i] = 0 }
	}
	identity := if capacity_io.mode == 8 || (capacity_io.mode == 9 && capacity_io.reads == 2) {
		u64(2)
	} else {
		u64(1)
	}
	put_le(&u8(output), 440, 4, identity)
	put_le(&u8(output), 510, 2, 0xaa55)
	if capacity_io.kind == 2 {
		put_le(&u8(output), 450, 1, 0xee)
		header := unsafe { &u8(output) + int(size / 2) }
		put_le(header, 0, 8, 0x5452415020494645)
		put_le(header, 8, 4, 0x10000)
		put_le(header, 12, 4, 92)
		put_le(header, 24, 8, 1)
		put_le(header, 56, 1, identity)
		put_le(header, 71, 1, 0x83)
		put_le(header, 16, 4, crc32(header, 92, 16))
		if capacity_io.mode == 13 { put_le(header, 16, 4, 0) }
	}
	return i64(size)
}

fn capacity_publish_write(fd i32, data voidptr, size usize) i64 {
	capacity_io.writes++
	if capacity_io.publish_mode == 1 && capacity_io.writes == 1 {
		unsafe { C.errno = C.EINTR }
		return -1
	}
	if capacity_io.publish_mode == 2 {
		unsafe { C.errno = C.EIO }
		return -1
	}
	return C.write(fd, data, if capacity_io.publish_mode == 1 && size > 3 { usize(3) } else { size })
}

fn capacity_publish_fsync(fd i32) i32 {
	capacity_io.flushes++
	if (capacity_io.publish_mode == 3 && capacity_io.flushes == 1)
		|| (capacity_io.publish_mode == 4 && capacity_io.flushes == 2) {
		unsafe { C.errno = C.EIO }
		return -1
	}
	return C.fsync(fd)
}

fn capacity_publish_close(fd i32) i32 {
	capacity_io.publish_closes++
	result := C.close(fd)
	if capacity_io.publish_mode == 5 && capacity_io.publish_closes == 1 {
		unsafe { C.errno = C.EIO }
		return -1
	}
	return result
}

fn capacity_publish_renameat(from_fd i32, from &char, to_fd i32, to &char) i32 {
	capacity_io.renames++
	if capacity_io.publish_mode == 6 {
		unsafe { C.errno = C.EIO }
		return -1
	}
	return C.renameat(from_fd, from, to_fd, to)
}

fn capacity_io_fixture(path string, sector u64, kind u32) PlanSet {
	capacity_io = CapacityIO{ sector: sector, kind: kind }
	mut set := PlanSet{}
	mut first := Plan{ count: 2, key: DiskKey{ bytes: 16777216, sector: sector, kind: kind } }
	first.key.id[0] = 1
	if kind == 2 { first.key.id[15] = 0x83 }
	first.rows[0] = Request{ slot: 2, offset: 1048576, length: 8192 }
	first.rows[1] = Request{ slot: 5, offset: 4194304, length: 4096, flags: 1 }
	mut second := first
	second.key.id[0] = 2
	second.count = 1
	second.rows[0].slot = 9
	second.rows[1] = Request{}
	assert append_plan(mut set, &first) && append_plan(mut set, &second)
	assert publish_bundle(path.str, &set)
	capacity_io = CapacityIO{ sector: sector, kind: kind }
	return set
}

fn test_capacity_probe_success_retries_interruptions_and_noop_preserves_desired_state() {
	work := os.join_path(os.temp_dir(), 'vinix-capacity-probe-${os.getpid()}')
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'
	for sector in [u64(512), 4096] {
		for kind in [u32(1), 2] {
			for mode in [0, 1] {
				before := capacity_io_fixture(path, sector, kind)
				capacity_io.mode = mode
				capacity_io.readonly = true // Adoption needs no writable device access.
				assert capacity_bundle_plan(path.str, 0, c'/capacity-device', 25165824) == 0
				assert capacity_io.opened == 1 && capacity_io.closed == 1 && capacity_io.statuses == 2
				assert capacity_io.reads == if mode == 1 { 3 } else { 2 }
				data := os.read_bytes(path)!
				mut decoded := PlanSet{}
				assert decode_bundle(data.data, data.len, mut decoded)
				assert decoded.plans[0].key.bytes == 25165824
				decoded.plans[0].key.bytes = before.plans[0].key.bytes
				assert decoded == before
				// Unchanged adoption must also complete the durability protocol.
				capacity_io = CapacityIO{ sector: sector, kind: kind, publish_mode: 2 }
				assert capacity_bundle_plan(path.str, 0, c'/capacity-device', 25165824) == 1
				assert capacity_io.writes == 1 && capacity_io.renames == 0
				assert os.read_bytes(path)! == data
				capacity_io = CapacityIO{ sector: sector, kind: kind }
				assert capacity_bundle_plan(path.str, 0, c'/capacity-device', 25165824) == 0
				assert capacity_io.renames == 1 && capacity_io.flushes == 2
				assert os.read_bytes(path)! == data && os.ls(work)!.len == 1
			}
		}
	}
}

fn test_bad_probes_geometry_identity_and_input_files_never_publish_and_close_the_disk() {
	work := os.join_path(os.temp_dir(), 'vinix-capacity-refuse-${os.getpid()}')
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'
	for kind in [u32(1), 2] {
		for mode in [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 17] {
			if mode == 13 && kind == 1 { continue }
			capacity_io_fixture(path, 512, kind)
			original := os.read_bytes(path)!
			capacity_io.mode = mode
			assert capacity_bundle_plan(path.str, 0, c'/capacity-device', 25165824) == 1
			assert capacity_io.opened == capacity_io.closed && capacity_io.writes == 0
			assert os.read_bytes(path)! == original && os.ls(work)!.len == 1
		}
	}
	capacity_io_fixture(path, 512, 1)
	original := os.read_bytes(path)!
	for disk in [-1, 2, 64] {
		assert capacity_bundle_plan(path.str, disk, c'/capacity-device', 25165824) == 1
	}
	for expected in [u64(0), 8388608, 25165825] {
		assert capacity_bundle_plan(path.str, 0, c'/capacity-device', expected) == 1
	}
	assert capacity_io.opened == 0 && os.read_bytes(path)! == original
	assert capacity_bundle_plan(path.str, 0, c'/capacity-device', 33554432) == 1
	assert capacity_io.closed == 1 && os.read_bytes(path)! == original
	os.symlink(path, work + '/link')!
	assert capacity_bundle_plan((work + '/link').str, 0, c'/capacity-device', 25165824) == 1
	assert capacity_bundle_plan(work.str, 0, c'/capacity-device', 25165824) == 1
	assert capacity_bundle_plan((work + '/missing').str, 0, c'/capacity-device', 25165824) == 1
	mut damaged := original.clone()
	damaged[80] ^= 1
	os.write_file_array(path, damaged)!
	assert capacity_bundle_plan(path.str, 0, c'/capacity-device', 25165824) == 1
	assert capacity_io.opened == 1 && os.read_bytes(path)! == damaged
}

fn test_capacity_publication_faults_preserve_old_or_complete_new_bundle_and_drain_descriptors() {
	work := os.join_path(os.temp_dir(), 'vinix-capacity-publish-${os.getpid()}')
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'
	for mode in 1 .. 7 {
		before := capacity_io_fixture(path, 512, 1)
		original := os.read_bytes(path)!
		capacity_io.publish_mode = mode
		assert capacity_bundle_plan(path.str, 0, c'/capacity-device', 25165824) == if mode == 1 {
			0
		} else {
			1
		}
		assert capacity_io.opened == 1 && capacity_io.closed == 1 && capacity_io.publish_closes == 2
		assert os.ls(work)!.len == 1
		current := os.read_bytes(path)!
		mut decoded := PlanSet{}
		assert decode_bundle(current.data, current.len, mut decoded)
		if mode == 1 || mode == 4 {
			assert current != original && decoded.plans[0].key.bytes == 25165824
			decoded.plans[0].key.bytes = 16777216
			assert decoded == before && capacity_io.renames == 1 && capacity_io.flushes == 2
		} else {
			assert current == original && decoded == before
		}
	}
}

fn test_capacity_report_flush_failure_is_reported_after_publication_with_no_open_device() {
	work := os.join_path(os.temp_dir(), 'vinix-capacity-output-${os.getpid()}')
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'
	capacity_io_fixture(path, 512, 1)
	assert C.fflush(C.stdout) == 0
	child := C.fork()
	assert child >= 0
	if child == 0 {
		fd := C.open(c'/dev/null', C.O_RDONLY)
		if fd < 0 || C.dup2(fd, 1) != 1 { C._exit(2) }
		C.close(fd)
		mut buffer := [4096]char{}
		if C.setvbuf(C.stdout, &buffer[0], C._IOFBF, 4096) != 0 { C._exit(3) }
		result := capacity_bundle_plan(path.str, 0, c'/capacity-device', 25165824)
		C._exit(if result == 1 && capacity_io.opened == 1 && capacity_io.closed == 1 {
			0
		} else {
			4
		})
	}
	mut result := i32(-1)
	assert C.waitpid(child, &result, 0) == child && result == 0
	data := os.read_bytes(path)!
	mut decoded := PlanSet{}
	assert decode_bundle(data.data, data.len, mut decoded) && decoded.plans[0].key.bytes == 25165824
}

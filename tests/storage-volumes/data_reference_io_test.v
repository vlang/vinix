// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

import os

struct DataReferenceIO {
mut:
	active bool
	mode int
	opened int
	closed int
	reads int
	stats int
}
__global data_reference_io DataReferenceIO

fn data_reference_open(path &char, flags i32) i32 {
	if data_reference_io.active { assert flags == C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC }
	fd := C.open(path, flags); if data_reference_io.active && fd >= 0 { data_reference_io.opened++ }; return fd
}
fn data_reference_openat(directory i32, path &char, flags i32) i32 {
	if data_reference_io.active { assert flags == C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK }
	fd := C.openat(directory, path, flags); if data_reference_io.active && fd >= 0 { data_reference_io.opened++ }; return fd
}
fn data_reference_close(fd i32) i32 {
	if data_reference_io.active { data_reference_io.closed++; assert data_reference_io.closed <= data_reference_io.opened }
	return C.close(fd)
}
fn data_reference_flock(fd i32, flags i32) i32 { assert !data_reference_io.active; return C.flock(fd, flags) }
fn data_reference_stat(fd i32, info &C.stat) i32 {
	if !data_reference_io.active { return C.fstat(fd, info) }
	data_reference_io.stats++; result := C.fstat(fd, info)
	if data_reference_io.mode == 6 { unsafe { info.st_size++ } }
	return result
}
fn data_reference_read(fd i32, bytes voidptr, size usize) i64 {
	if !data_reference_io.active { return C.read(fd, bytes, size) }
	data_reference_io.reads++
	match data_reference_io.mode {
		1 { if data_reference_io.reads == 1 { unsafe { C.errno = C.EINTR }; return -1 }; return C.read(fd, bytes, if size > 3 { usize(3) } else { size }) }
		2 { return 0 }
		3 { unsafe { C.errno = C.EIO }; return -1 }
		4 { return i64(size + 1) }
		5 { result := C.read(fd, bytes, size); return if result == 0 { i64(1) } else { result } }
		else { return C.read(fd, bytes, size) }
	}
}
fn data_reference_mock_encode(before &DataManifest, after &DataManifest, output &char) int {
	assert data_reference_io.active && data_reference_io.opened == 4 && data_reference_io.closed == 0
	assert data_io.opened == 0 && data_io.writes == 0 && data_io.renames == 0 && data_io.statuses == [0, 0]! && data_auto_calls == 0
	if data_reference_io.mode == 7 { return 0 }
	return encode_data_reference_comparison(before, after, output)
}
fn data_reference_flush(stream voidptr) i32 {
	if data_reference_io.active { assert data_reference_io.opened == 4 && data_reference_io.closed == 0 }
	if data_reference_io.active && data_reference_io.mode == 8 { return -1 }; return C.fflush(stream)
}
fn data_reference_ferror(stream voidptr) i32 {
	if data_reference_io.active { assert data_reference_io.opened == 4 && data_reference_io.closed == 0 }
	if data_reference_io.active && data_reference_io.mode == 9 { return 1 }; return C.ferror(stream)
}

fn data_reference_expected(before &DataManifest, after &DataManifest) string {
	mut left := [11392]u8{}; mut right := [11392]u8{}
	ln := encode_data_manifest(before, &left[0]); rn := encode_data_manifest(after, &right[0])
	changed := int(before.digests.values[0] != after.digests.values[0]) + int(before.digests.values[1] != after.digests.values[1])
	mut text := 'format=VINIXDH1 operation=compared-data-references disks=2 mappings=2 stable=${2 - changed} changed=${changed} algorithm=sha256 before_reference_sha256=' + hex.encode(sha256.sum(left[..ln])) + ' after_reference_sha256=' + hex.encode(sha256.sum(right[..rn])) + '\n'
	for disk in 0 .. 2 {
		key := before.set.plans[disk].key; row := before.set.plans[disk].rows[0]
		identity := if key.kind == 1 { 'mbr:00000001' } else { 'gpt:00000002-0000-0000-0000-000000000083' }
		text += 'disk=${disk} disk_bytes=${key.bytes} sector=${key.sector} identity=${identity}\n'
		text += 'disk=${disk} slot=${row.slot} offset=${row.offset} bytes=${row.length} readonly=${row.flags} result=${if before.digests.values[disk] == after.digests.values[disk] { 'stable' } else { 'changed' }} before_sha256=' + hex.encode(before.digests.values[disk][..]) + ' after_sha256=' + hex.encode(after.digests.values[disk][..]) + '\n'
	}
	return text
}

fn data_reference_check(first string, second string, mode int, expected i32) string {
	capture := os.dir(first) + '/compare-capture'; assert C.fflush(C.stdout) == 0
	saved := C.dup(1); fd := C.open(capture.str, C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600)); assert saved >= 0 && fd >= 0 && C.dup2(fd, 1) == 1 && C.close(fd) == 0
	data_io = DataIO{}; data_auto_calls = 0; data_reference_io = DataReferenceIO{active: true, mode: mode}
	unsafe { args := [&char(c'vinix-volume'), &char(c'compare-data-references'), first.str, second.str, &char(nil)]!; assert run(4, &args[0]) == expected }
	assert data_reference_io.opened == data_reference_io.closed && data_io.opened == 0 && data_io.writes == 0 && data_auto_calls == 0
	data_reference_io.active = false; assert C.fflush(C.stdout) == 0 && C.dup2(saved, 1) == 1 && C.close(saved) == 0
	text := os.read_file(capture) or { panic(err) }; os.rm(capture) or { panic(err) }
	if expected == 1 && mode !in [8, 9] { assert !text.contains('operation=') }; return text
}

fn test_offline_plain_reference_exact_reports_complete_readers_no_physical_io_and_error_precedence() {
	work := os.join_path(os.temp_dir(), 'vinix-data-reference-${os.getpid()}'); os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	first := work + '/first'; second := work + '/second'; mut before := DataManifest{}; mut devices := DataDevices{}; data_io_fixture(mut before, mut devices)
	mut left := [11392]u8{}; ln := encode_data_manifest(unsafe { &before }, &left[0]); os.write_file_array(first, left[..ln])!
	for mask in 0 .. 4 {
		mut after := before; for disk in 0 .. 2 { if mask & (1 << disk) != 0 { after.digests.values[disk][31] ^= 1 } }
		mut right := [11392]u8{}; rn := encode_data_manifest(unsafe { &after }, &right[0]); os.write_file_array(second, right[..rn])!; os.chmod(second, 0o644)!
		for mode in 0 .. 10 {
			text := data_reference_check(first, second, mode, if mode <= 1 { if mask == 0 { 0 } else { 2 } } else { 1 })
			if mode <= 1 { assert text == data_reference_expected(unsafe { &before }, unsafe { &after }) }
			assert os.read_bytes(first)! == left[..ln] && os.read_bytes(second)! == right[..rn]
		}
		assert data_reference_check(second, first, 0, if mask == 0 { 0 } else { 2 }) == data_reference_expected(unsafe { &after }, unsafe { &before })
	}
	assert data_reference_check(first, first, 0, 0) == data_reference_expected(unsafe { &before }, unsafe { &before })
	os.link(first, work + '/alias')!; assert data_reference_check(first, work + '/alias', 0, 0).contains('stable=2 changed=0'); os.rm(work + '/alias')!
	mut owner := PlanEdit{}; assert open_plan_edit(first.str, mut owner, true)
	assert data_reference_check(first, first, 0, 0).contains('stable=2 changed=0'); close_plan_edit(mut owner)
	for side in 0 .. 2 {
		path := if side == 0 { first } else { second }; os.write_file_array(first, left[..ln])!; os.write_file_array(second, left[..ln])!
		for at in 0 .. ln { mut broken := left; broken[at] ^= 1; os.write_file_array(path, broken[..ln])!; data_reference_check(first, second, 0, 1) }; os.write_file_array(path, left[..ln])!
		os.mv(path, path + '.saved')!; os.symlink(path + '.saved', path)!; data_reference_check(first, second, 0, 1); os.rm(path)!
		os.mkdir(path)!; data_reference_check(first, second, 0, 1); os.rmdir(path)!
		assert C.mkfifo(path.str, 0o600) == 0; data_reference_check(first, second, 0, 1); os.rm(path)!
		data_reference_check(first, second, 0, 1); os.mv(path + '.saved', path)!
	}
	// Operational output failure wins over stable and changed findings.
	for changed in [false, true] {
		mut after := before; if changed { after.digests.values[1][0] ^= 1 }; mut right := [11392]u8{}; rn := encode_data_manifest(unsafe { &after }, &right[0]); os.write_file_array(second, right[..rn])!
		child := C.fork(); assert child >= 0
		if child == 0 {
			fd := C.open(c'/dev/null', C.O_RDONLY); if fd < 0 || C.dup2(fd, 1) != 1 { C._exit(3) }; C.close(fd)
			mut buffer := [4096]char{}; if C.setvbuf(C.stdout, &buffer[0], C._IOFBF, 4096) != 0 { C._exit(4) }
			data_reference_io = DataReferenceIO{active: true}; result := data_reference_files(first.str, second.str)
			C._exit(if result == 1 && data_reference_io.opened == data_reference_io.closed && data_io.opened == 0 { 0 } else { 5 })
		}
		mut code := i32(-1); assert C.waitpid(child, &code, 0) == child && code == 0
	}
}

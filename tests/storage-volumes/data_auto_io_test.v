// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

import os

__global data_auto_calls int
__global data_auto_fault int
__global data_auto_late_stage int

fn data_auto_mock_probe(fd i32, mut key DiskKey, mut status Status) bool {
	if !probe_disk(fd, mut key, mut status) { return false }
	if fd == 900002 && data_io.statuses[1] == data_auto_late_stage {
		if data_auto_fault == 5 { status.flags ^= 1 }
		if data_auto_fault == 6 { status.disk_id += 100 }
		if data_auto_fault == 7 { status.bytes += status.sector; key.bytes += status.sector }
	}
	return true
}

fn data_auto_mock_discover(expected &DiskKey, directory &char, writable bool, name &char, mut selected Status) i32 {
	assert C.strcmp(directory, c'/dev') == 0 && !writable; data_auto_calls++
	disk := if expected.kind == 1 { 0 } else { 1 }
	if data_auto_fault == 1 && disk == 1 { return -1 }
	fd := data_mock_open(if disk == 0 { &char(c'/hash-disk-0') } else { &char(c'/hash-disk-1') }, C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK)
	if fd < 0 { return -1 }
	mut key := DiskKey{}
	if !probe_disk(fd, mut key, mut selected) || !key_matches(expected, unsafe { &key }) { data_mock_close(fd); return -1 }
	if data_auto_fault == 2 && disk == 1 { selected.disk_id = 70 }
	if data_auto_fault == 3 && disk == 0 { selected.disk_id += 100 }
	if data_auto_fault == 4 && disk == 1 { selected.flags ^= 1 }
	C.snprintf(name, 256, c'data%d', disk); return fd
}

fn data_auto_check(input string, output string, operation int, physical int, publication int, fault int, expected i32) string {
	data_io = DataIO{mode: physical, publish_mode: publication}; data_auto_calls = 0; data_auto_fault = fault; data_auto_late_stage = if operation == 1 { 3 } else { 4 }
	capture := os.dir(input) + '/capture'; assert C.fflush(C.stdout) == 0
	saved := C.dup(1); fd := C.open(capture.str, C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600))
	assert saved >= 0 && fd >= 0 && C.dup2(fd, 1) == 1 && C.close(fd) == 0
	unsafe {
		args := [&char(c'vinix-volume'), if operation == 0 { &char(c'hash-bundle-auto') } else if operation == 1 { &char(c'verify-data-auto') } else { &char(c'scrub-data-auto') }, input.str, output.str, &char(nil)]!
		assert run(if operation == 1 { 3 } else { 4 }, &args[0]) == expected
	}
	assert C.fflush(C.stdout) == 0 && C.dup2(saved, 1) == 1 && C.close(saved) == 0 && data_io.opened == data_io.closed
	text := os.read_file(capture) or { panic(err) }; os.rm(capture) or { panic(err) }
	if expected == 1 && publication != 4 { assert !text.contains('operation=') }; return text
}

fn test_automatic_data_pin_transfer_mode_identity_order_complete_scrubs_and_publication_faults() {
	work := os.join_path(os.temp_dir(), 'vinix-data-auto-${os.getpid()}'); os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	bundle := work + '/source'; reference := work + '/reference'; report := work + '/report'
	mut manifest := DataManifest{}; mut devices := DataDevices{}; data_io_fixture(mut manifest, mut devices)
	data_io = DataIO{}; assert publish_bundle(bundle.str, unsafe { &manifest.set })
	mut bytes := [11392]u8{}; size := encode_data_manifest(unsafe { &manifest }, &bytes[0]); original := os.read_bytes(bundle)!
	defer { data_auto_fault = 0 }
	for operation in 0 .. 3 {
		os.write_file_array(reference, bytes[..size])!
		input := if operation == 0 { bundle } else { reference }; output := if operation == 2 { report } else { reference }
		text := data_auto_check(input, output, operation, 0, 0, 0, 0)
		assert data_auto_calls == 2 && data_io.opened == 2 && data_io.delivered == [u64(73728), 73728]!
		assert data_io.statuses == if operation == 1 { [3, 3]! } else { [4, 4]! }
		if operation == 2 { assert text == scrub_io_expected(unsafe { &manifest }, 0) && os.read_file(report)! == text }
		else { assert text.contains(if operation == 0 { 'operation=recorded-data disks=2 mappings=2' } else { 'operation=verified-data disks=2 mappings=2' }) && os.read_bytes(reference)! == bytes[..size] }
		for physical in 0 .. 21 {
			os.write_file_array(reference, bytes[..size])!; os.write_file(report, 'previous report\n')!
			code := if physical in [0, 1] || (operation == 0 && physical in [18, 19]) { 0 } else if operation == 2 && physical in [18, 19] { 2 } else { 1 }
			result := data_auto_check(input, output, operation, physical, 0, 0, code)
			if operation == 2 && code != 1 { assert result == scrub_io_expected(unsafe { &manifest }, if physical == 18 { 2 } else if physical == 19 { 3 } else { 0 }) }
			if operation == 2 && code == 1 { assert os.read_file(report)! == 'previous report\n' }
			if operation != 0 || physical !in [18, 19] { assert os.read_bytes(reference)! == bytes[..size] }
			if operation == 2 && physical in [18, 19, 20] { assert data_io.delivered[0] == 73728; if physical != 20 { assert data_io.delivered[1] == 73728 } }
		}
		for fault in 1 .. 8 {
			os.write_file_array(reference, bytes[..size])!; os.write_file(report, 'previous report\n')!
			data_auto_check(input, output, operation, 0, 0, fault, 1)
			assert data_auto_calls == 2 && data_io.opened == if fault == 1 { 1 } else { 2 }
			if fault >= 5 {
				assert data_io.delivered == [u64(73728), 73728]! && data_io.statuses == if operation == 1 { [3, 3]! } else { [4, 4]! }
				assert data_io.writes == 0 && data_io.renames == 0
			}
			assert os.read_bytes(reference)! == bytes[..size] && os.read_file(report)! == 'previous report\n'
		}
		if operation != 1 { for publication in 1 .. 7 {
			os.write_file_array(reference, bytes[..size])!; os.write_file(report, 'previous report\n')!
			data_auto_check(input, output, operation, 0, publication, 0, if publication == 1 { 0 } else { 1 })
			assert data_auto_calls == 2 && os.read_bytes(bundle)! == original
			if operation == 2 && publication !in [1, 4] { assert os.read_file(report)! == 'previous report\n' }
		} }
		for destination in [input, work, work + '/fifo', work + '/link'] {
			if destination.ends_with('fifo') { assert C.mkfifo(destination.str, 0o600) == 0 }
			if destination.ends_with('link') { os.symlink(input, destination)! }
			if operation != 1 { data_auto_check(input, destination, operation, 0, 0, 0, 1); assert data_auto_calls == 0 }
			if destination.ends_with('fifo') || destination.ends_with('link') { os.rm(destination)! }
		}
		os.write_file_array(reference, bytes[..size])!; saved := os.read_bytes(input)!; mut damaged := saved.clone(); damaged[damaged.len - 1] ^= 1; os.write_file_array(input, damaged)!
		data_auto_check(input, output, operation, 0, 0, 0, 1); assert data_auto_calls == 0; os.write_file_array(input, saved)!
	}
	assert os.read_bytes(bundle)! == original
}

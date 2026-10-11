// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

import os

fn C.fork() i32
fn C.dup2(i32, i32) i32
fn C.waitpid(i32, &i32, i32) i32
fn C._exit(i32)
fn C.setvbuf(voidptr, &char, i32, usize) i32

fn check_sample(mut set PlanSet) {
	mut plan := Plan{
		count: 2
		key:   DiskKey{
			bytes:  16777216
			sector: 512
			kind:   1
		}
	}
	put_le(&plan.key.id[0], 0, 4, 0x12345678)
	plan.rows[0] = Request{
		slot:   2
		offset: 1048576
		length: 4096
	}
	plan.rows[1] = Request{
		slot:   5
		offset: 2097152
		length: 8192
		flags:  1
	}
	assert append_plan(mut set, &plan)
	put_le(&plan.key.id[0], 0, 4, 0x12345679)
	plan.count = 1
	plan.rows[0].slot = 9
	assert append_plan(mut set, &plan)
}

fn test_bundle_identity_output_uses_mbr_value_and_canonical_gpt_byte_order_with_canaries() {
	mut key := DiskKey{
		kind: 1
	}
	put_le(&key.id[0], 0, 4, 0x12345678)
	mut output := [43]char{init: char(0x5a)}
	disk_identity(&key, &output[1])
	assert C.strcmp(&output[1], c'mbr:12345678') == 0
	assert output[0] == char(0x5a) && output[42] == char(0x5a)
	key.kind = 2
	for i in 0 .. 16 {
		key.id[i] = u8(i)
	}
	disk_identity(&key, &output[1])
	assert C.strcmp(&output[1], c'gpt:03020100-0504-0706-0809-0a0b0c0d0e0f') == 0
	assert output[0] == char(0x5a) && output[42] == char(0x5a)
}

fn test_offline_bundle_show_validates_and_preserves_contents_without_devices() {
	work := os.join_path(os.temp_dir(), 'vinix-plan-show-${os.getpid()}')
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'
	mut set := PlanSet{}
	check_sample(mut set)
	assert publish_bundle(path.str, &set)
	original := os.read_bytes(path)!
	assert inspect_bundle(path.str, false, false) == 0 && os.read_bytes(path)! == original
	os.symlink(path, work + '/link')!
	assert inspect_bundle((work + '/link').str, false, false) == 1
	mut damaged := original.clone()
	damaged[272] ^= 1
	os.write_file_array(path, damaged)!
	assert inspect_bundle(path.str, false, false) == 1 && os.read_bytes(path)! == damaged
}

fn test_bundle_inspection_cli_rejects_extra_arguments_and_invalid_growth_mode() {
	unsafe {
		mut arguments := [&char(c'vinix-volume'), &char(c'show-bundle'), &char(c'/unused'),
			&char(c'grow'), &char(nil)]!
		assert run(4, &arguments[0]) == 2
		arguments[1] = &char(c'check-bundle')
		arguments[3] = &char(c'force')
		assert run(4, &arguments[0]) == 2
		assert run(2, &arguments[0]) == 2
		assert run(5, &arguments[0]) == 2
	}
}

fn test_offline_report_rejects_immediate_write_and_buffered_flush_failures() {
	work := os.join_path(os.temp_dir(), 'vinix-plan-output-${os.getpid()}')
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'
	mut set := PlanSet{}
	check_sample(mut set)
	assert publish_bundle(path.str, &set)
	assert C.fflush(C.stdout) == 0
	for buffered in [false, true] {
		child := C.fork()
		assert child >= 0
		if child == 0 {
			fd := C.open(c'/dev/null', C.O_RDONLY)
			if fd < 0 || C.dup2(fd, 1) != 1 { C._exit(2) }
			C.close(fd)
			mut buffer := [4096]char{}
			mode := if buffered { C._IOFBF } else { C._IONBF }
			if C.setvbuf(C.stdout, &buffer[0], mode, 4096) != 0 { C._exit(3) }
			result := inspect_bundle(path.str, false, false)
			C._exit(if result == 1 { 0 } else { 4 })
		}
		mut status := i32(-1)
		assert C.waitpid(child, &status, 0) == child && status == 0
	}
}

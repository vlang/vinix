// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

import os

fn test_key_import_requires_private_owned_regular_exact_distinct_binary_key() {
	work := os.join_path(os.temp_dir(), 'vinix-crypt-key-${os.getpid()}')
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	path := work + '/key'
	mut key := []u8{len: 64}
	for i in 0 .. 64 { key[i] = u8(i * 13 + 7) }
	os.write_file_array(path, key)!
	os.chmod(path, 0o600)!
	mut output := [66]u8{init: 0x81}
	assert read_volume_key(path.str, &output[1])
	for i in 0 .. 64 { assert output[i + 1] == key[i] }
	assert output[0] == 0x81 && output[65] == 0x81
	for mode in [0o644, 0o620, 0o601] {
		os.chmod(path, mode)!
		assert !read_volume_key(path.str, &output[1])
	}
	os.chmod(path, 0o600)!
	os.symlink(path, work + '/link')!
	assert !read_volume_key((work + '/link').str, &output[1])
	assert !read_volume_key(work.str, &output[1])
	assert os.exec(['mkfifo', work + '/fifo']).exit_code == 0
	assert !read_volume_key((work + '/fifo').str, &output[1])
	for size in [0, 63, 65] {
		os.write_file_array(path, []u8{len: size, init: 7})!
		assert !read_volume_key(path.str, &output[1])
	}
	os.write_file_array(path, []u8{len: 64, init: 7})!
	assert !read_volume_key(path.str, &output[1])
}

fn test_encrypted_cli_rejects_invalid_syntax_before_key_or_device_io() {
	unsafe {
		mut args := [&char(c'vinix-volume'), &char(c'open-crypt'), &char(c'/unused'),
			&char(c'0'), &char(c'0'), &char(c'512'), &char(c'/unused-key'), &char(c'ro'), &char(nil)]!
		assert run(6, &args[0]) == 2
		assert run(9, &args[0]) == 2
		args[3] = &char(c'64'); assert run(7, &args[0]) == 2
		args[3] = &char(c'-1'); assert run(7, &args[0]) == 2
		args[3] = &char(c'0'); args[4] = &char(c'18446744073709551616'); assert run(7, &args[0]) == 2
		args[4] = &char(c'0'); args[5] = &char(c'0'); assert run(7, &args[0]) == 2
		args[5] = &char(c'512'); args[7] = &char(c'rw'); assert run(8, &args[0]) == 2
	}
}

fn test_plain_plan_matching_and_growth_refuse_encrypted_views() {
	parent := Status{bytes: 8192, sector: 512, disk_id: 7}
	row := Request{slot: 3, offset: 1024, length: 4096}
	mut view := Status{bytes: 4096, sector: 512, disk_id: 7, slot: 3, start: 1024, flags: 12, generation: 9}
	assert mapping_matches(&view, &parent, &row)
	view.flags |= 64
	assert !mapping_matches(&view, &parent, &row)
	view.bytes = 2048
	assert !mapping_growable(&view, &parent, &row)
	view.flags &= ~u64(64)
	assert mapping_growable(&view, &parent, &row)
}

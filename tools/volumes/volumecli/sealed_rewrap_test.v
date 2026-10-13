// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

import os

fn test_rewrap_preserves_volume_key_source_credentials_and_destination_entries() {
	work := os.join_path(os.temp_dir(), 'vinix-rewrap-${os.getpid()}')
	os.mkdir(work)!; os.chmod(work, 0o700)!; defer { os.rmdir_all(work) or {} }
	key := []u8{len: 64, init: u8(index * 13 + 7)}
	old := []u8{len: 1024, init: u8(index * 11 + 1)}
	// Includes NUL and a newline; short new input must not retain an old suffix.
	next := [u8(0), u8(10), u8(0xe2), u8(0x82), u8(0xac), u8(0xff)]
	for pair in ['key', 'old', 'next'] {
		os.write_file_array(work + '/' + pair, if pair == 'key' { key } else if pair == 'old' { old } else { next })!
		os.chmod(work + '/' + pair, 0o600)!
	}
	assert sealed_key_file((work + '/key').str, (work + '/old').str, (work + '/source').str, true) == 0
	source := os.read_bytes(work + '/source')!
	os.rm(work + '/key')!
	assert rewrap_sealed_key((work + '/source').str, (work + '/next').str, (work + '/missing').str, (work + '/absent').str) == 1
	assert !os.exists(work + '/absent')
	assert rewrap_sealed_key((work + '/source').str, (work + '/old').str, (work + '/next').str, (work + '/result').str) == 0
	result := os.read_bytes(work + '/result')!
	assert result.len == 192 && result != source && result[40..56] != source[40..56] && result[56..68] != source[56..68]
	mut info := C.stat{}
	assert unsafe { C.stat((work + '/result').str, &info) } == 0 && info.st_mode & 0o777 == 0o600
	assert !os.exists(work + '/key')
	assert sealed_key_file((work + '/result').str, (work + '/old').str, (work + '/absent').str, false) == 1
	assert !os.exists(work + '/absent')
	assert sealed_key_file((work + '/result').str, (work + '/next').str, (work + '/restored').str, false) == 0
	assert os.read_bytes(work + '/restored')! == key
	assert sealed_key_file((work + '/source').str, (work + '/old').str, (work + '/original').str, false) == 0
	assert os.read_bytes(work + '/original')! == key
	// Same credentials intentionally produce a fresh independent envelope too.
	assert rewrap_sealed_key((work + '/result').str, (work + '/next').str, (work + '/next').str, (work + '/refresh').str) == 0
	assert os.read_bytes(work + '/refresh')! != result
	assert sealed_key_file((work + '/refresh').str, (work + '/next').str, (work + '/refreshed').str, false) == 0
	assert os.read_bytes(work + '/refreshed')! == key
	os.symlink(work + '/absent', work + '/link')!
	assert os.exec(['mkfifo', work + '/fifo']).exit_code == 0
	os.mkdir(work + '/dir')!
	os.link(work + '/source', work + '/alias')!
	for name in ['source', 'old', 'next', 'result', 'alias', 'link', 'fifo', 'dir'] {
		assert rewrap_sealed_key((work + '/source').str, (work + '/old').str, (work + '/next').str, (work + '/' + name).str) == 1
	}
	assert os.read_bytes(work + '/source')! == source && os.read_bytes(work + '/alias')! == source
	assert os.read_bytes(work + '/result')! == result && os.read_bytes(work + '/old')! == old && os.read_bytes(work + '/next')! == next
	assert os.ls(work)!.all(!it.starts_with('.vinix-key-'))
}

fn test_rewrap_cli_rejects_bad_arity_and_empty_paths_before_io() {
	unsafe {
		mut args := [&char(c'vinix-volume'), &char(c'rewrap-key'), &char(c'/unused'), &char(c'/unused'), &char(c'/unused'), &char(c'/unused'), &char(nil)]!
		for count in [2, 3, 4, 5, 7] { assert run(count, &args[0]) == 2 }
		for at in 2 .. 6 { args[at] = &char(c''); assert run(6, &args[0]) == 2; args[at] = &char(c'/unused') }
	}
}

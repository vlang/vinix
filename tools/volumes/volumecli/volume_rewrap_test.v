// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

import os

fn test_volume_rewrap_preserves_authenticated_metadata_and_key_with_binary_credentials() {
	work := os.join_path(os.temp_dir(), 'vinix-volume-rewrap-${os.getpid()}')
	os.mkdir(work)!; os.chmod(work, 0o700)!; defer { os.rmdir_all(work) or {} }
	old := []u8{len: 1024, init: u8(index * 11 + 1)}
	next := [u8(0), u8(10), u8(0xe2), u8(0x82), u8(0xac), u8(0xff)]
	os.write_file_array(work + '/old', old)!; os.chmod(work + '/old', 0o600)!
	os.write_file_array(work + '/next', next)!; os.chmod(work + '/next', 0o600)!
	mut random := [28]u8{init: u8(index * 11 + 3)}; mut wrapping := [64]u8{}
	assert sealed_derive(&old[0], old.len, &random[0], &wrapping[0])
	mut source := [320]u8{}; mut request := EncryptedRequest{data: Request{slot: 60, offset: 1048576, length: 8192}}
	for i in 0 .. 64 { request.key[i] = u8(i * 13 + 7) }
	for kind in [u32(1), u32(2)] {
		for sector in [u64(512), u64(4096)] {
			for mode in [u64(0), u64(1)] {
				mut disk := DiskKey{bytes: 16777216, sector: sector, kind: kind}; disk.id[0] = 0x78
				if kind == 2 { disk.id[15] = 0x83 }; request.data.flags = mode
				assert encode_volume_seal(&disk, &request, &wrapping[0], &random[0], &source[0])
				os.write_file_array(work + '/source', source[..])!; os.chmod(work + '/source', 0o600)!
				assert rewrap_volume_seal((work + '/source').str, (work + '/old').str, (work + '/next').str, (work + '/result').str) == 0
				result := os.read_bytes(work + '/result')!
				assert result.len == 320 && result[40..56] != source[40..56] && result[56..68] != source[56..68]
				assert result[80..192] == source[80..192] && result[256..288] == source[256..288]
				mut info := C.stat{}
				assert unsafe { C.stat((work + '/result').str, &info) } == 0 && info.st_mode & 0o777 == 0o600
				mut fresh := [64]u8{}; mut decoded_disk := DiskKey{}; mut decoded := EncryptedRequest{}
				assert sealed_derive(&next[0], next.len, &result[40], &fresh[0])
				assert decode_volume_seal(&result[0], 320, &fresh[0], mut decoded_disk, mut decoded)
				assert decoded_disk == disk && decoded == request
				// The source wrapping key cannot authenticate the new configuration.
				assert !decode_volume_seal(&result[0], 320, &wrapping[0], mut decoded_disk, mut decoded)
				assert decoded_disk == disk && decoded == request
				assert os.read_bytes(work + '/source')! == source[..]
				os.rm(work + '/result')!
			}
		}
	}
	assert rewrap_volume_seal((work + '/source').str, (work + '/next').str, (work + '/missing').str, (work + '/absent').str) == 1
	assert !os.exists(work + '/absent')
	assert rewrap_volume_seal((work + '/source').str, (work + '/old').str, (work + '/next').str, (work + '/result').str) == 0
	result := os.read_bytes(work + '/result')!
	assert unseal_volume_key((work + '/result').str, (work + '/old').str, (work + '/absent').str) == 1 && !os.exists(work + '/absent')
	assert unseal_volume_key((work + '/result').str, (work + '/next').str, (work + '/recovered').str) == 0
	assert os.read_bytes(work + '/recovered')! == request.key[..]
	assert unseal_volume_key((work + '/source').str, (work + '/old').str, (work + '/original').str) == 0
	assert os.read_bytes(work + '/original')! == request.key[..]
	assert rewrap_volume_seal((work + '/result').str, (work + '/next').str, (work + '/next').str, (work + '/refresh').str) == 0
	assert os.read_bytes(work + '/refresh')! != result
	assert unseal_volume_key((work + '/refresh').str, (work + '/next').str, (work + '/refreshed').str) == 0
	assert os.read_bytes(work + '/refreshed')! == request.key[..]
	os.symlink(work + '/absent', work + '/link')!; os.link(work + '/source', work + '/alias')!
	assert os.exec(['mkfifo', work + '/fifo']).exit_code == 0; os.mkdir(work + '/dir')!
	for name in ['source', 'old', 'next', 'result', 'alias', 'link', 'fifo', 'dir'] {
		assert rewrap_volume_seal((work + '/source').str, (work + '/old').str, (work + '/next').str, (work + '/' + name).str) == 1
	}
	assert os.read_bytes(work + '/source')! == source[..] && os.read_bytes(work + '/alias')! == source[..]
	assert os.read_bytes(work + '/result')! == result && os.read_bytes(work + '/old')! == old && os.read_bytes(work + '/next')! == next
	assert os.ls(work)!.all(!it.starts_with('.vinix-key-'))
}

fn test_volume_rewrap_cli_rejects_bad_arity_and_empty_paths_before_io() {
	unsafe {
		mut args := [&char(c'vinix-volume'), &char(c'rewrap-volume'), &char(c'/unused'), &char(c'/unused'), &char(c'/unused'), &char(c'/unused'), &char(nil)]!
		for count in [2, 3, 4, 5, 7] { assert run(count, &args[0]) == 2 }
		for at in 2 .. 6 { args[at] = &char(c''); assert run(6, &args[0]) == 2; args[at] = &char(c'/unused') }
	}
}

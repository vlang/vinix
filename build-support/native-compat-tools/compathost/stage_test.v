module compathost

import hosttest
import os

fn test_atomic_stage_permissions_bytes_and_failed_publish_cleanup() {
	work := hosttest.work_dir('', 'vinix-stage-atomic-check-') or { panic(err) }
	defer { retire(work) }
	data := []u8{len: 200003, init: u8(index % 256)}
	os.write_file_array(work + '/source', data) or { panic(err) }
	os.write_file(work + '/destination', 'old') or { panic(err) }
	install(work + '/source', work + '/destination', 0o751, '.stage-check-') or { panic(err) }
	assert os.read_bytes(work + '/destination') or { panic(err) } == data
	assert (os.stat(work + '/destination') or { panic(err) }).mode & 0o7777 == 0o751
	os.mkdir(work + '/directory') or { panic(err) }
	os.write_file(work + '/directory/sentinel', 'keep') or { panic(err) }
	mut failed := false
	install(work + '/source', work + '/directory', 0o755, '.stage-check-') or { failed = true }
	assert failed
	assert os.read_file(work + '/directory/sentinel') or { panic(err) } == 'keep'
	failed = false
	install(work + '/missing', work + '/destination', 0o755, '.stage-check-') or { failed = true }
	assert failed
	assert os.read_bytes(work + '/destination') or { panic(err) } == data
	assert (os.ls(work) or { panic(err) }).filter(it.starts_with('.stage-check-')).len == 0
}

fn test_disposable_volume_disk_mbr_bounds_and_physical_sentinels() {
	work := hosttest.work_dir('', 'vinix-stage-disk-check-') or { panic(err) }
	defer { retire(work) }
	for arch in ['aarch64', 'x86_64'] {
		path := work + '/' + arch
		volume_disk(path, arch) or { panic(err) }
		mut bytes := os.read_bytes(path) or { panic(err) }
		assert bytes.len == 16 * 1024 * 1024
		assert bytes[1024 * 1024 - 512..1024 * 1024] == []u8{len: 512, init: u8(0xa1)}
		assert bytes[1536 * 1024..1536 * 1024 + 512] == []u8{len: 512, init: u8(0xa2)}
		if arch == 'x86_64' {
			assert bytes[446..462] == [u8(0), 0, 0, 0, 0x83, 0, 0, 0, 0, 0x60, 0, 0, 0, 8, 0, 0]
			assert bytes[510..512] == [u8(0x55), 0xaa]
		} else {
			assert bytes[..512] == []u8{len: 512}
		}
		mut rejected := false
		volume_disk_check(path) or { rejected = true }
		assert rejected
		for offset, size in {
			1024 * 1024:            512
			4 * 1024 * 1024:        4096
			4 * 1024 * 1024 + 8192: 4096
		} {
			for i in offset .. offset + size {
				bytes[i] = if size == 512 { u8(0x73) } else { u8(0x95) }
			}
		}
		os.write_file_array(path, bytes) or { panic(err) }
		volume_disk_check(path) or { panic(err) }
		bytes[4 * 1024 * 1024 + 8192] = 0
		os.write_file_array(path, bytes) or { panic(err) }
		rejected = false
		volume_disk_check(path) or { rejected = true }
		assert rejected
	}
}

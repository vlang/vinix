module nativeapk

import compress.szip
import os
import rand

fn test_native_library_paths_and_atomic_install() {
	for entry in ['lib/arm64-v8a/../libbad.so', 'lib/arm64-v8a/sub/libbad.so',
		'lib/arm64-v8a/libbad\\name.so', 'lib/arm64-v8a/libbad\n.so'] {
		mut rejected := false
		library_name(entry, 'arm64-v8a') or { rejected = true }
		assert rejected
	}
	assert library_name('lib/x86_64/libother.so', 'arm64-v8a')! == ''
	assert library_name('lib/arm64-v8a/libhello.so', 'arm64-v8a')! == 'libhello.so'
	root := os.join_path(os.temp_dir(), 'vinix-native-apk-' + rand.uuid_v4())
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {} }
	mut elf := []u8{len: 32}
	copy(mut elf, [u8(0x7f), `E`, `L`, `F`, 2, 1])
	elf[18] = 183
	apk := root + '/app.apk'
	mut archive := szip.open(apk, .no_compression, .write)!
	for entry in ['lib/arm64-v8a/libhello.so', 'lib/x86_64/libother.so', 'assets/data'] {
		archive.open_entry(entry)!
		archive.write_entry(elf)!
		archive.close_entry()
	}
	archive.close()
	destination := install(apk, root + '/data', 'arm64-v8a')!
	assert os.read_bytes(destination + '/libhello.so')! == elf
	assert os.ls(destination)!.len == 1
	assert install(apk, root + '/data', 'arm64-v8a')! == destination
	os.chmod(destination + '/libhello.so', 0o600)!
	os.write_file(destination + '/libhello.so', 'changed')!
	mut rejected := false
	install(apk, root + '/data', 'arm64-v8a') or { rejected = true }
	assert rejected
	assert os.ls(root + '/data/native-libraries')!.len == 1
	bad := root + '/bad.apk'
	mut invalid := szip.open(bad, .no_compression, .write)!
	invalid.open_entry('lib/arm64-v8a/libbad.so')!
	invalid.write_entry('wrong ABI'.bytes())!
	invalid.close_entry()
	invalid.close()
	rejected = false
	install(bad, root + '/invalid-data', 'arm64-v8a') or { rejected = true }
	assert rejected
	assert os.ls(root + '/invalid-data/native-libraries')!.len == 0
}

fn test_unused_entry_payload_corruption_is_rejected_before_publication() {
	root := os.join_path(os.temp_dir(), 'vinix-native-apk-crc-' + rand.uuid_v4())
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {} }
	apk := root + '/bad.apk'
	mut archive := szip.open(apk, .no_compression, .write)!
	archive.open_entry('assets/unused')!
	archive.write_entry('unused-data-sentinel'.bytes())!
	archive.close_entry()
	archive.close()
	mut data := os.read_bytes(apk)!
	text := data.bytestr()
	position := text.index('unused-data-sentinel') or { panic('missing stored fixture payload') }
	data[position] = `X`
	os.write_file_array(apk, data)!
	mut rejected := false
	install(apk, root + '/data', 'arm64-v8a') or { rejected = true }
	assert rejected
	assert os.ls(root + '/data/native-libraries')!.len == 0
}

fn test_directory_payload_is_rejected_before_publication() {
	root := os.join_path(os.temp_dir(), 'vinix-native-apk-dir-' + rand.uuid_v4())
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {} }
	apk := root + '/bad.apk'
	mut archive := szip.open(apk, .no_compression, .write)!
	archive.open_entry('assets/')!
	archive.write_entry('directory entries cannot contain data'.bytes())!
	archive.close_entry()
	archive.close()
	mut rejected := false
	install(apk, root + '/data', 'arm64-v8a') or { rejected = true }
	assert rejected
	assert os.ls(root + '/data/native-libraries')!.len == 0
}

// SPDX-License-Identifier: GPL-2.0-or-later
module iosbuild

import os
import tarcore

fn test_gnu_source_extraction_is_bounded_and_rejects_unsafe_members() {
	work := private_directory(os.temp_dir()) or { panic(err) }
	defer { os.rmdir_all(work) or { panic(err) } }
	mut writer := tarcore.create(work + '/safe.tar') or { panic(err) }
	writer.add(tarcore.Member{ name: 'release/include/header', kind: `0`, size: 6 }, 'header'.bytes()) or { panic(err) }
	writer.add(tarcore.Member{ name: 'release/test/unused', kind: `0`, size: 4 }, 'test'.bytes()) or { panic(err) }
	writer.add(tarcore.Member{ name: 'release/src/empty', kind: `5` }, []u8{}) or { panic(err) }
	writer.finish() or { panic(err) }
	writer.close()
	gnu_unpack(work + '/safe.tar', work + '/safe') or { panic(err) }
	assert os.read_file(work + '/safe/include/header')! == 'header'
	assert !os.exists(work + '/safe/test')
	for index, name in ['release/../escape', '/release/include/absolute', 'release/include/link'] {
		path := work + '/unsafe-' + index.str() + '.tar'
		mut bad := tarcore.create(path) or { panic(err) }
		bad.add(tarcore.Member{ name: name, kind: if index == 2 { `2` } else { `0` }, linkname: '/outside', size: 0 }, []u8{}) or { panic(err) }
		bad.finish() or { panic(err) }
		bad.close()
		mut rejected := false
		gnu_unpack(path, work + '/bad-' + index.str()) or { rejected = true }
		assert rejected
	}
	mut duplicate := tarcore.create(work + '/duplicate.tar') or { panic(err) }
	for _ in 0 .. 2 {
		duplicate.add(tarcore.Member{ name: 'release/include/header', kind: `0`, size: 0 }, []u8{}) or { panic(err) }
	}
	duplicate.finish() or { panic(err) }
	duplicate.close()
	mut rejected := false
	gnu_unpack(work + '/duplicate.tar', work + '/duplicate') or { rejected = true }
	assert rejected
}

fn test_gnu_rejects_missing_or_non_glibc_sysroot_before_output() {
	work := private_directory(os.temp_dir()) or { panic(err) }
	defer { os.rmdir_all(work) or { panic(err) } }
	mut rejected := false
	build_gnu_cxx(Tools{}, GnuCxxOptions{
		output:   work + '/output'
		sysroot:  work + '/missing'
		compiler: '/bin/true'
		archiver: '/bin/true'
	}) or { rejected = true }
	assert rejected && !os.exists(work + '/output')
	for invalid in ['', 'contains\nnewline', 'contains"quote', 'contains\\backslash', 'contains\x00null'] {
		rejected = false
		gnu_safe_path(invalid) or { rejected = true }
		assert rejected
	}
}

fn test_gnu_object_validation_requires_arm64_relocatable_elf() {
	work := private_directory(os.temp_dir()) or { panic(err) }
	defer { os.rmdir_all(work) or { panic(err) } }
	mut good := []u8{len: 20}
	good[0] = 0x7f
	good[1] = `E`
	good[2] = `L`
	good[3] = `F`
	good[4] = 2
	good[5] = 1
	good[16] = 1
	good[18] = 183
	os.write_file_array(work + '/object', good) or { panic(err) }
	gnu_object_valid(work + '/object') or { panic(err) }
	for byte in [0, 4, 5, 16, 18, 19] {
		mut bad := good.clone()
		bad[byte] ^= 1
		os.write_file_array(work + '/object', bad) or { panic(err) }
		mut rejected := false
		gnu_object_valid(work + '/object') or { rejected = true }
		assert rejected
	}
	os.write_file(work + '/object', 'short') or { panic(err) }
	mut rejected := false
	gnu_object_valid(work + '/object') or { rejected = true }
	assert rejected
}

fn test_gnu_extracted_source_reuse_rejects_edited_files() {
	work := private_directory(os.temp_dir()) or { panic(err) }
	defer { os.rmdir_all(work) or { panic(err) } }
	archive := work + '/source.tar'
	mut writer := tarcore.create(archive) or { panic(err) }
	writer.add(tarcore.Member{ name: 'release/src/source.cpp', kind: `0`, size: 8 }, 'original'.bytes()) or { panic(err) }
	writer.finish() or { panic(err) }
	writer.close()
	artifact := Artifact{'source.tar', 'https://fixture.invalid/source.tar', digest(archive)!}
	destination := work + '/source'
	key := gnu_qualified_source(archive, destination, artifact) or { panic(err) }
	assert gnu_qualified_source(archive, destination, artifact)! == key
	os.write_file(destination + '/src/source.cpp', 'edited') or { panic(err) }
	mut rejected := false
	gnu_qualified_source(archive, destination, artifact) or { rejected = true }
	assert rejected
	// Missing legacy metadata must trigger comparison with the pinned archive,
	// rather than blessing the current bytes as an original source tree.
	os.rm(destination + '/.source-tree-key') or { panic(err) }
	rejected = false
	gnu_qualified_source(archive, destination, artifact) or { rejected = true }
	assert rejected && !os.exists(destination + '/.source-tree-key')
	os.write_file(destination + '/src/source.cpp', 'original') or { panic(err) }
	assert gnu_qualified_source(archive, destination, artifact)! == key
	assert os.read_file(destination + '/.source-tree-key')! == key
}

fn test_gnu_header_inventory_includes_hidden_files_and_rejects_links() {
	work := private_directory(os.temp_dir()) or { panic(err) }
	defer { os.rmdir_all(work) or { panic(err) } }
	os.mkdir(work + '/nested') or { panic(err) }
	os.write_file(work + '/.hidden', 'hidden input') or { panic(err) }
	os.write_file(work + '/nested/header.h', 'original header') or { panic(err) }
	before := gnu_header_hashes(work) or { panic(err) }
	assert before.len == 2
	assert before['.hidden'] == digest(work + '/.hidden')!
	assert before['nested/header.h'] == digest(work + '/nested/header.h')!
	os.write_file(work + '/nested/header.h', 'changed header') or { panic(err) }
	assert gnu_header_hashes(work)! != before
	os.write_file(work + '/extra.h', 'extra') or { panic(err) }
	assert gnu_header_hashes(work)!.len == 3
	os.rm(work + '/.hidden') or { panic(err) }
	assert '.hidden' !in gnu_header_hashes(work)!
	os.symlink(work + '/nested/header.h', work + '/alias.h') or { panic(err) }
	mut rejected := false
	gnu_header_hashes(work) or { rejected = true }
	assert rejected
	os.rm(work + '/alias.h') or { panic(err) }
	os.mkdir(work + '/empty') or { panic(err) }
	rejected = false
	gnu_header_hashes(work + '/empty') or { rejected = true }
	assert rejected
	rejected = false
	gnu_header_hashes(work + '/missing') or { rejected = true }
	assert rejected
}

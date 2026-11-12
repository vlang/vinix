// SPDX-License-Identifier: GPL-2.0-or-later
module companionstage

import compress.szip
import crypto.sha256
import os

#include <unistd.h>

fn C.link(&char, &char) int

struct CompanionTestObject {
	dev u64
	inode u64
	uid u32
	gid u32
	mode u32
	nlink u64
	size u64
	kind os.FileType
}

struct CompanionTestRoot {
	dev u64
	inode u64
	uid u32
	gid u32
	mode u32
	kind os.FileType
}

fn companion_test_object(path string) !CompanionTestObject {
	st := os.lstat(path)!
	return CompanionTestObject{st.dev, st.inode, st.uid, st.gid,
		st.mode & 0o7777, st.nlink, st.size, st.get_filetype()}
}

fn companion_test_root_identity(path string) !CompanionTestRoot {
	st := os.lstat(path)!
	return CompanionTestRoot{st.dev, st.inode, st.uid, st.gid,
		st.mode & 0o7777, st.get_filetype()}
}

fn companion_test_digest(path string) !string {
	bytes := os.read_bytes(path)!
	defer { unsafe { bytes.free() } }
	return sha256.sum(bytes).hex()
}

fn companion_test_elf(tag u8) []u8 {
	mut elf := []u8{len: 64, init: tag}
	copy(mut elf, [u8(0x7f), `E`, `L`, `F`, 2, 1])
	elf[18], elf[19] = 183, 0
	return elf
}

fn companion_test_apk(path string, kind string) ! {
	if kind == 'not-zip' {
		os.write_file(path, 'not a ZIP archive')!
		return
	}
	one := companion_test_elf(17)
	two := companion_test_elf(29)
	defer { unsafe { one.free(); two.free() } }
	mut archive := szip.open(path, .no_compression, .write)!
	defer { archive.close() }
	if kind != 'empty-arm' {
		archive.open_entry('lib/arm64-v8a/libdemo-one.so')!
		if kind == 'bad-elf' {
			archive.write_entry('not an ELF library'.bytes())!
		} else if kind == 'wrong-machine' {
			mut wrong := one.clone()
			wrong[18] = 62
			archive.write_entry(wrong)!
			unsafe { wrong.free() }
		} else {
			archive.write_entry(one)!
		}
		archive.close_entry()
		if kind == 'duplicate' {
			archive.open_entry('lib/arm64-v8a/libdemo-one.so')!
			archive.write_entry(two)!
			archive.close_entry()
		} else if kind == 'traversal' {
			archive.open_entry('lib/arm64-v8a/../libescape.so')!
			archive.write_entry(two)!
			archive.close_entry()
		} else if kind == 'valid' {
			archive.open_entry('lib/arm64-v8a/libdemo+two.so')!
			archive.write_entry(two)!
			archive.close_entry()
		} else if kind == 'too-many' {
			for index in 0 .. 256 {
				archive.open_entry('lib/arm64-v8a/libextra' + index.str() + '.so')!
				archive.write_entry(two)!
				archive.close_entry()
			}
		}
	}
	// Other architectures and APK assets never become companion libraries.
	archive.open_entry('lib/x86_64/libforeign.so')!
	archive.write_entry('irrelevant foreign ABI payload'.bytes())!
	archive.close_entry()
	archive.open_entry('assets/private-asset')!
	archive.write_entry('not a native library'.bytes())!
	archive.close_entry()
}

fn companion_test_fixture(name string, kind string) !Config {
	parent := os.getenv('VINIX_COMPANION_STAGE_TEST_ROOT')
	assert parent != '' && os.is_abs_path(parent) && os.is_dir(parent)
	root := parent + '/' + name
	assert !os.exists(root) && !os.is_link(root)
	os.mkdir(root, mode: 0o700)!
	os.mkdir(root + '/apks', mode: 0o700)!
	os.mkdir(root + '/data', mode: 0o700)!
	// This belongs to the later unprivileged primary APK installer. Companion
	// extraction must neither reuse it as a root cache nor alter its contents.
	os.mkdir(root + '/data/native-libraries', mode: 0o700)!
	os.write_file(root + '/data/native-libraries/primary-sentinel', 'preserved primary native cache')!
	os.chmod(root + '/data/native-libraries/primary-sentinel', 0o400)!
	source := root + '/apks/gms.apk'
	companion_test_apk(source, kind)!
	os.chmod(source, 0o400)!
	return Config{
		source: source
		sha256: companion_test_digest(source)!
		data: root + '/data'
		scratch: root + '/scratch'
		source_owner: u32(os.getuid())
		source_group: u32(os.getgid())
		target_uid: u32(os.getuid())
		target_gid: u32(os.getgid())
	}
}

fn companion_assert_primary_cache(config Config) ! {
	assert os.ls(config.data + '/native-libraries')! == ['primary-sentinel']
	assert os.read_file(config.data + '/native-libraries/primary-sentinel')! == 'preserved primary native cache'
	st := os.lstat(config.data + '/native-libraries')!
	assert st.uid == config.target_uid && st.gid == config.target_gid
	assert st.mode & 0o7777 == 0o700
}

fn companion_assert_no_publication(config Config) ! {
	for suffix in ['/_installed_apks_', '/com.google.android.gms_', '/.com.google.android.gms_.pending'] {
		assert !os.exists(config.data + suffix) && !os.is_link(config.data + suffix)
	}
	assert !os.exists(config.scratch) && !os.is_link(config.scratch)
	companion_assert_primary_cache(config)!
}

fn test_companion_exact_publication_preserves_source_and_primary_data() ! {
	config := companion_test_fixture('exact-publication', 'valid')!
	source := companion_test_object(config.source)!
	data := companion_test_root_identity(config.data)!
	cache := companion_test_object(config.data + '/native-libraries/primary-sentinel')!
	result := stage(config)!
	assert result.package_name == 'com.google.android.gms'
	assert result.source_sha256 == config.sha256 && result.apk_sha256 == config.sha256
	assert result.target_uid == config.target_uid && result.target_gid == config.target_gid
	assert result.dir_mode == 0o700 && result.apk_mode == 0o400 && result.lib_mode == 0o500
	assert companion_test_object(config.source)! == source
	assert companion_test_digest(config.source)! == config.sha256
	assert source.nlink == 1
	assert companion_test_root_identity(config.data)! == data
	assert companion_test_object(config.data + '/native-libraries/primary-sentinel')! == cache
	assert !os.exists(config.scratch) && !os.is_link(config.scratch)
	mut entries := os.ls(config.data)!
	entries.sort()
	assert entries == ['_installed_apks_', 'com.google.android.gms_', 'native-libraries']
	for path in [config.data + '/_installed_apks_', config.data + '/com.google.android.gms_',
		config.data + '/com.google.android.gms_/lib'] {
		st := companion_test_object(path)!
		assert st.kind == .directory && st.uid == config.target_uid && st.gid == config.target_gid
		assert st.mode == 0o700
	}
	apk := config.data + '/_installed_apks_/com.google.android.gms.apk'
	published := companion_test_object(apk)!
	assert published.kind == .regular && published.nlink == 1 && published.mode == 0o400
	assert published.uid == config.target_uid && published.gid == config.target_gid
	assert published.dev != source.dev || published.inode != source.inode
	assert companion_test_digest(apk)! == config.sha256
	assert os.ls(config.data + '/_installed_apks_')! == ['com.google.android.gms.apk']
	mut libraries := os.ls(config.data + '/com.google.android.gms_/lib')!
	libraries.sort()
	assert libraries == ['libdemo+two.so', 'libdemo-one.so']
	assert result.native_libraries.len == 2
	for name, tag in {'libdemo-one.so': u8(17), 'libdemo+two.so': u8(29)} {
		library := config.data + '/com.google.android.gms_/lib/' + name
		st := companion_test_object(library)!
		assert st.kind == .regular && st.nlink == 1 && st.mode == 0o500
		assert st.uid == config.target_uid && st.gid == config.target_gid
		expected := companion_test_elf(tag)
		actual := os.read_bytes(library)!
		assert actual == expected
		assert result.native_libraries[name]! == sha256.sum(expected).hex()
		unsafe { expected.free(); actual.free() }
	}
	companion_assert_primary_cache(config)!
}

fn test_companion_bad_native_archives_leave_no_partial_publication() ! {
	for kind in ['bad-elf', 'wrong-machine', 'empty-arm', 'duplicate', 'traversal', 'not-zip', 'too-many'] {
		config := companion_test_fixture('invalid-archive-' + kind, kind)!
		source := companion_test_object(config.source)!
		data := companion_test_root_identity(config.data)!
		mut rejected := false
		stage(config) or { rejected = true }
		assert rejected, kind
		assert companion_test_object(config.source)! == source
		assert companion_test_digest(config.source)! == config.sha256
		assert companion_test_root_identity(config.data)! == data
		companion_assert_no_publication(config)!
		assert !os.exists(os.dir(config.data) + '/libescape.so')
	}
}

fn companion_expect_rejected(config Config) ! {
	mut rejected := false
	stage(config) or { rejected = true }
	assert rejected
}

fn test_companion_source_identity_and_target_ownership_preflights() ! {
	for kind in ['wrong-pin', 'source-owner', 'source-group', 'source-writable',
		'source-hardlink', 'source-symlink', 'source-directory', 'source-empty',
		'source-parent-mode', 'source-parent-symlink', 'target-owner', 'target-group',
		'target-mode', 'target-symlink'] {
		config := companion_test_fixture('preflight-' + kind, 'valid')!
		root := os.dir(config.data)
		mut selected := config
		mut watched := ''
		match kind {
			'wrong-pin' { selected = Config{...config, sha256: '0'.repeat(64)} }
			'source-owner' { selected = Config{...config, source_owner: config.source_owner + 1} }
			'source-group' { selected = Config{...config, source_group: config.source_group + 1} }
			'source-writable' { os.chmod(config.source, 0o600)! }
			'source-hardlink' {
				watched = root + '/source-hardlink.apk'
				assert unsafe { C.link(&char(config.source.str), &char(watched.str)) } == 0
				assert os.lstat(config.source)!.nlink == 2
			}
			'source-symlink' {
				watched = root + '/source-symlink.apk'
				os.symlink(config.source, watched)!
				selected = Config{...config, source: watched}
			}
			'source-directory' {
				watched = root + '/not-an-apk'
				os.mkdir(watched, mode: 0o700)!
				selected = Config{...config, source: watched}
			}
			'source-empty' {
				os.chmod(config.source, 0o600)!
				os.truncate(config.source, 0)!
				os.chmod(config.source, 0o400)!
				selected = Config{...config, sha256: companion_test_digest(config.source)!}
			}
			'source-parent-mode' {
				watched = os.dir(config.source)
				os.chmod(watched, 0o777)!
			}
			'source-parent-symlink' {
				watched = root + '/linked-apks'
				os.symlink(os.dir(config.source), watched)!
				selected = Config{...config, source: watched + '/gms.apk'}
			}
			'target-owner' { selected = Config{...config, target_uid: config.target_uid + 1} }
			'target-group' { selected = Config{...config, target_gid: config.target_gid + 1} }
			'target-mode' { os.chmod(config.data, 0o755)! }
			else {
				watched = root + '/linked-data'
				os.symlink(config.data, watched)!
				selected = Config{...config, data: watched}
			}
		}
		source := companion_test_object(config.source)!
		data := companion_test_root_identity(config.data)!
		original_hash := companion_test_digest(config.source)!
		before := if watched != '' { companion_test_object(watched)! } else { CompanionTestObject{} }
		companion_expect_rejected(selected)!
		assert companion_test_object(config.source)! == source
		assert companion_test_digest(config.source)! == original_hash
		assert companion_test_root_identity(config.data)! == data
		if watched != '' { assert companion_test_object(watched)! == before }
		companion_assert_no_publication(config)!
	}
}

fn test_companion_rejects_unsafe_paths_and_cache_inside_primary_data() ! {
	for kind in ['source-noncanonical', 'source-relative', 'source-control',
		'data-noncanonical', 'scratch-relative', 'scratch-parent', 'cache-inside-data',
		'scratch-parent-symlink'] {
		config := companion_test_fixture('unsafe-' + kind, 'valid')!
		root := os.dir(config.data)
		mut selected := config
		match kind {
			'source-noncanonical' { selected = Config{...config, source: os.dir(config.source) + '//gms.apk'} }
			'source-relative' { selected = Config{...config, source: 'gms.apk'} }
			'source-control' { selected = Config{...config, source: config.source + '\x00unexpected'} }
			'data-noncanonical' { selected = Config{...config, data: config.data + '/.'} }
			'scratch-relative' { selected = Config{...config, scratch: 'scratch'} }
			'scratch-parent' { selected = Config{...config, scratch: root + '/../scratch'} }
			'cache-inside-data' { selected = Config{...config, scratch: config.data + '/root-cache'} }
			else {
				os.mkdir(root + '/real-work', mode: 0o700)!
				os.symlink(root + '/real-work', root + '/linked-work')!
				selected = Config{...config, scratch: root + '/linked-work/cache'}
			}
		}
		source := companion_test_object(config.source)!
		data := companion_test_root_identity(config.data)!
		companion_expect_rejected(selected)!
		assert companion_test_object(config.source)! == source
		assert companion_test_digest(config.source)! == config.sha256
		assert companion_test_root_identity(config.data)! == data
		companion_assert_no_publication(config)!
		assert !os.exists(config.data + '/root-cache')
		if kind == 'scratch-parent-symlink' {
			assert os.is_link(root + '/linked-work')
			assert os.ls(root + '/real-work')!.len == 0
		}
	}
}

fn test_companion_existing_targets_are_preserved_without_partial_work() ! {
	for kind in ['catalog-directory', 'catalog-file', 'package-directory',
		'package-symlink', 'pending-directory', 'scratch-directory'] {
		config := companion_test_fixture('occupied-' + kind, 'valid')!
		root := os.dir(config.data)
		mut occupied := ''
		mut sentinel := ''
		match kind {
			'catalog-directory' {
				occupied = config.data + '/_installed_apks_'
				os.mkdir(occupied, mode: 0o700)!
				sentinel = occupied + '/.com.google.android.gms.apk.pending'
				os.write_file(sentinel, 'existing APK temporary must survive')!
			}
			'catalog-file' {
				occupied = config.data + '/_installed_apks_'
				os.write_file(occupied, 'catalog is already a regular file')!
				sentinel = occupied
			}
			'package-directory' {
				occupied = config.data + '/com.google.android.gms_'
				os.mkdir(occupied, mode: 0o700)!
				sentinel = occupied + '/existing-package'
				os.write_file(sentinel, 'existing package must survive')!
			}
			'package-symlink' {
				occupied = config.data + '/com.google.android.gms_'
				os.mkdir(root + '/existing-package-target', mode: 0o700)!
				sentinel = root + '/existing-package-target/keep'
				os.write_file(sentinel, 'existing symlink target must survive')!
				os.symlink(root + '/existing-package-target', occupied)!
			}
			'pending-directory' {
				occupied = config.data + '/.com.google.android.gms_.pending'
				os.mkdir(occupied, mode: 0o700)!
				sentinel = occupied + '/existing-work'
				os.write_file(sentinel, 'existing pending work must survive')!
			}
			else {
				occupied = config.scratch
				os.mkdir(occupied, mode: 0o700)!
				sentinel = occupied + '/existing-cache'
				os.write_file(sentinel, 'existing scratch cache must survive')!
			}
		}
		before := companion_test_object(occupied)!
		sentinel_before := companion_test_object(sentinel)!
		content := os.read_file(sentinel)!
		source := companion_test_object(config.source)!
		data := companion_test_root_identity(config.data)!
		companion_expect_rejected(config)!
		assert companion_test_object(occupied)! == before
		assert companion_test_object(sentinel)! == sentinel_before
		assert os.read_file(sentinel)! == content
		assert companion_test_object(config.source)! == source
		assert companion_test_digest(config.source)! == config.sha256
		assert companion_test_root_identity(config.data)! == data
		companion_assert_primary_cache(config)!
		for suffix in ['/_installed_apks_', '/com.google.android.gms_', '/.com.google.android.gms_.pending'] {
			path := config.data + suffix
			if path != occupied { assert !os.exists(path) && !os.is_link(path) }
		}
		if kind != 'scratch-directory' { assert !os.exists(config.scratch) && !os.is_link(config.scratch) }
	}
}

fn companion_pair_fixture(name string, second_kind string) !(Config, Config) {
	gms := companion_test_fixture(name, 'valid')!
	root := os.dir(gms.data)
	source := root + '/apks/vending.apk'
	companion_test_apk(source, second_kind)!
	if second_kind != 'not-zip' {
		mut archive := szip.open(source, .no_compression, .append)!
		archive.open_entry('assets/vending-identity')!
		archive.write_entry('distinct Vending APK bytes'.bytes())!
		archive.close_entry()
		if second_kind == 'valid' {
			vending_elf := companion_test_elf(41)
			archive.open_entry('lib/arm64-v8a/libvending-only.so')!
			archive.write_entry(vending_elf)!
			archive.close_entry()
			unsafe { vending_elf.free() }
		}
		archive.close()
	}
	os.chmod(source, 0o400)!
	vending := Config{...gms, source: source, sha256: companion_test_digest(source)!,
		scratch: root + '/vending-scratch'}
	return gms, vending
}

fn companion_assert_pair_no_publication(gms Config, vending Config) ! {
	companion_assert_no_publication(gms)!
	for suffix in ['/com.android.vending_', '/.com.android.vending_.pending'] {
		assert !os.exists(gms.data + suffix) && !os.is_link(gms.data + suffix)
	}
	assert !os.exists(vending.scratch) && !os.is_link(vending.scratch)
}

fn companion_expect_pair_rejected(gms Config, vending Config) ! {
	mut rejected := false
	stage_pair(gms, vending) or { rejected = true }
	assert rejected
}

fn companion_assert_pair_package(record Record, config Config, package_name string,
	expected map[string]u8) ! {
	assert record.package_name == package_name
	assert record.source_sha256 == config.sha256 && record.apk_sha256 == config.sha256
	assert record.target_uid == config.target_uid && record.target_gid == config.target_gid
	assert record.dir_mode == 0o700 && record.apk_mode == 0o400 && record.lib_mode == 0o500
	for directory in [config.data + '/' + package_name + '_',
		config.data + '/' + package_name + '_/lib'] {
		st := companion_test_object(directory)!
		assert st.kind == .directory && st.mode == 0o700
		assert st.uid == config.target_uid && st.gid == config.target_gid
	}
	copy_path := config.data + '/_installed_apks_/' + package_name + '.apk'
	copy_object := companion_test_object(copy_path)!
	source_object := companion_test_object(config.source)!
	assert copy_object.kind == .regular && copy_object.nlink == 1 && copy_object.mode == 0o400
	assert copy_object.uid == config.target_uid && copy_object.gid == config.target_gid
	assert copy_object.dev != source_object.dev || copy_object.inode != source_object.inode
	assert companion_test_digest(copy_path)! == config.sha256
	mut names := os.ls(config.data + '/' + package_name + '_/lib')!
	names.sort()
	mut expected_names := expected.keys()
	expected_names.sort()
	assert names == expected_names
	assert record.native_libraries.len == expected.len
	for name, tag in expected {
		path := config.data + '/' + package_name + '_/lib/' + name
		st := companion_test_object(path)!
		assert st.kind == .regular && st.nlink == 1 && st.mode == 0o500
		assert st.uid == config.target_uid && st.gid == config.target_gid
		payload := companion_test_elf(tag)
		actual := os.read_bytes(path)!
		assert actual == payload
		assert record.native_libraries[name]! == sha256.sum(payload).hex()
		unsafe { payload.free(); actual.free() }
	}
}

fn test_companion_pair_exact_shared_catalog_and_independent_packages() ! {
	gms, vending := companion_pair_fixture('pair-exact-publication', 'valid')!
	gms_before := companion_test_object(gms.source)!
	vending_before := companion_test_object(vending.source)!
	assert gms_before.nlink == 1 && vending_before.nlink == 1
	assert gms_before.dev != vending_before.dev || gms_before.inode != vending_before.inode
	assert gms.sha256 != vending.sha256
	data := companion_test_root_identity(gms.data)!
	cache := companion_test_object(gms.data + '/native-libraries/primary-sentinel')!
	records := stage_pair(gms, vending)!
	assert records.len == 2
	companion_assert_pair_package(records[0], gms, 'com.google.android.gms',
		{'libdemo-one.so': u8(17), 'libdemo+two.so': u8(29)})!
	companion_assert_pair_package(records[1], vending, 'com.android.vending',
		{'libdemo-one.so': u8(17), 'libdemo+two.so': u8(29), 'libvending-only.so': u8(41)})!
	assert companion_test_object(gms.source)! == gms_before
	assert companion_test_object(vending.source)! == vending_before
	assert companion_test_digest(gms.source)! == gms.sha256
	assert companion_test_digest(vending.source)! == vending.sha256
	assert companion_test_root_identity(gms.data)! == data
	assert companion_test_object(gms.data + '/native-libraries/primary-sentinel')! == cache
	assert !os.exists(gms.scratch) && !os.is_link(gms.scratch)
	assert !os.exists(vending.scratch) && !os.is_link(vending.scratch)
	mut entries := os.ls(gms.data)!
	entries.sort()
	assert entries == ['_installed_apks_', 'com.android.vending_', 'com.google.android.gms_', 'native-libraries']
	mut catalog := os.ls(gms.data + '/_installed_apks_')!
	catalog.sort()
	assert catalog == ['com.android.vending.apk', 'com.google.android.gms.apk']
	catalog_identity := companion_test_object(gms.data + '/_installed_apks_')!
	assert catalog_identity.kind == .directory && catalog_identity.mode == 0o700
	assert catalog_identity.uid == gms.target_uid && catalog_identity.gid == gms.target_gid
	companion_assert_primary_cache(gms)!
}

fn test_pruned_ledger_preserves_catalog_identity_and_path_ownership() ! {
	root := os.join_path(os.temp_dir(), 'vinix-companion-ledger-' + os.getpid().str())
	assert !os.exists(root)
	os.mkdir(root, mode: 0o700)!
	defer { os.rmdir_all(root) or {} }
	catalog := root + '/_installed_apks_'
	os.mkdir(catalog, mode: 0o700)!
	os.chown(catalog, os.getuid(), os.getgid())!
	mut work := Work{objects: []Owned{cap: 1024}}
	remember(mut work, catalog)!
	remember(mut work, root)!
	work.objects[1].active = false
	old_storage := unsafe { usize(work.objects[0].path.str) }
	prune_removed(mut work)
	defer {
		for item in work.objects { unsafe { item.path.free() } }
		unsafe { work.objects.free() }
	}
	assert work.objects.len == 1
	// Compare addresses only: dereferencing the old string would itself be
	// a use-after-free. Independent storage must precede its release.
	assert unsafe { usize(work.objects[0].path.str) } != old_storage
	assert work.objects[0].path == catalog
	ensure_owned_catalog(mut work, catalog, u32(os.getuid()), u32(os.getgid()))!
	assert rollback(mut work, catalog)
	assert !os.exists(catalog)
}

fn test_companion_pair_second_pin_is_checked_before_first_mutation() ! {
	gms, vending := companion_pair_fixture('pair-second-pin-preflight', 'valid')!
	root := os.dir(gms.data)
	gms_before := companion_test_object(gms.source)!
	vending_before := companion_test_object(vending.source)!
	data := companion_test_root_identity(gms.data)!
	// A historical mtime makes even create-then-rollback work observable.
	// The bad second pin must prevent both first-scratch and DATA writes.
	os.utime(root, 946684800, 946684800)!
	os.utime(gms.data, 946684800, 946684800)!
	assert os.lstat(root)!.mtime == 946684800
	assert os.lstat(gms.data)!.mtime == 946684800
	companion_expect_pair_rejected(gms, Config{...vending, sha256: '0'.repeat(64)})!
	assert os.lstat(root)!.mtime == 946684800
	assert os.lstat(gms.data)!.mtime == 946684800
	assert companion_test_object(gms.source)! == gms_before
	assert companion_test_object(vending.source)! == vending_before
	assert companion_test_root_identity(gms.data)! == data
	companion_assert_pair_no_publication(gms, vending)!
}

fn test_companion_pair_second_native_failure_rolls_back_first_package() ! {
	for kind in ['bad-elf', 'wrong-machine', 'empty-arm', 'duplicate', 'traversal', 'not-zip', 'too-many'] {
		gms, vending := companion_pair_fixture('pair-second-native-' + kind, kind)!
		gms_before := companion_test_object(gms.source)!
		vending_before := companion_test_object(vending.source)!
		data := companion_test_root_identity(gms.data)!
		cache := companion_test_object(gms.data + '/native-libraries/primary-sentinel')!
		// Both byte pins are correct, so failure comes from the second APK's
		// native contents after the first package can already be published.
		assert companion_test_digest(gms.source)! == gms.sha256
		assert companion_test_digest(vending.source)! == vending.sha256
		companion_expect_pair_rejected(gms, vending)!
		assert companion_test_object(gms.source)! == gms_before
		assert companion_test_object(vending.source)! == vending_before
		assert companion_test_root_identity(gms.data)! == data
		assert companion_test_object(gms.data + '/native-libraries/primary-sentinel')! == cache
		companion_assert_pair_no_publication(gms, vending)!
		assert !os.exists(os.dir(gms.data) + '/libescape.so')
	}
}

fn companion_pair_many_apk(path string, prefix string, count int) !map[string]u8 {
	mut archive := szip.open(path, .no_compression, .write)!
	defer { archive.close() }
	mut expected := map[string]u8{}
	for index in 0 .. count {
		name := 'lib' + prefix + index.str() + '.so'
		tag := u8(index % 251 + 1)
		payload := companion_test_elf(tag)
		archive.open_entry('lib/arm64-v8a/' + name)!
		archive.write_entry(payload)!
		archive.close_entry()
		expected[name] = tag
		unsafe { payload.free() }
	}
	return expected
}

fn companion_pair_with_library_count(config Config, prefix string, count int) !(Config, map[string]u8) {
	os.chmod(config.source, 0o600)!
	expected := companion_pair_many_apk(config.source, prefix, count)!
	os.chmod(config.source, 0o400)!
	return Config{...config, sha256: companion_test_digest(config.source)!}, expected
}

fn test_companion_pair_library_boundary_and_oversized_second_rollback() ! {
	for second_count in [256, 257] {
		initial_gms, initial_vending := companion_pair_fixture('pair-library-boundary-' + second_count.str(), 'valid')!
		gms, gms_libraries := companion_pair_with_library_count(initial_gms, 'gms', 256)!
		vending, vending_libraries := companion_pair_with_library_count(initial_vending, 'vending', second_count)!
		gms_before := companion_test_object(gms.source)!
		vending_before := companion_test_object(vending.source)!
		data := companion_test_root_identity(gms.data)!
		cache := companion_test_object(gms.data + '/native-libraries/primary-sentinel')!
		if second_count == 256 {
			records := stage_pair(gms, vending)!
			assert records.len == 2
			companion_assert_pair_package(records[0], gms, 'com.google.android.gms', gms_libraries)!
			companion_assert_pair_package(records[1], vending, 'com.android.vending', vending_libraries)!
			assert !os.exists(gms.scratch) && !os.is_link(gms.scratch)
			assert !os.exists(vending.scratch) && !os.is_link(vending.scratch)
		} else {
			companion_expect_pair_rejected(gms, vending)!
			companion_assert_pair_no_publication(gms, vending)!
		}
		assert companion_test_object(gms.source)! == gms_before
		assert companion_test_object(vending.source)! == vending_before
		assert companion_test_digest(gms.source)! == gms.sha256
		assert companion_test_digest(vending.source)! == vending.sha256
		assert companion_test_root_identity(gms.data)! == data
		assert companion_test_object(gms.data + '/native-libraries/primary-sentinel')! == cache
		companion_assert_primary_cache(gms)!
	}
}

fn test_companion_pair_refuses_unowned_targets_and_aliased_configuration() ! {
	for kind in ['vending-package', 'vending-package-symlink', 'vending-pending',
		'catalog', 'empty-catalog', 'catalog-symlink', 'target-owner', 'target-group',
		'source-owner', 'source-group', 'source-writable', 'different-data',
		'scratch-alias', 'scratch-child', 'scratch-parent', 'same-source',
		'hardlinked-source', 'source-symlink'] {
		gms, vending := companion_pair_fixture('pair-refusal-' + kind, 'valid')!
		root := os.dir(gms.data)
		mut first := gms
		mut second := vending
		mut occupied := ''
		mut watched := ''
		mut sentinel := ''
		match kind {
			'vending-package' {
				occupied = gms.data + '/com.android.vending_'
				os.mkdir(occupied, mode: 0o700)!
				sentinel = occupied + '/existing-package'
				os.write_file(sentinel, 'existing Vending package must survive')!
			}
			'vending-package-symlink' {
				occupied = gms.data + '/com.android.vending_'
				watched = root + '/existing-vending'
				os.mkdir(watched, mode: 0o700)!
				sentinel = watched + '/keep'
				os.write_file(sentinel, 'existing Vending symlink target must survive')!
				os.symlink(watched, occupied)!
			}
			'vending-pending' {
				occupied = gms.data + '/.com.android.vending_.pending'
				os.mkdir(occupied, mode: 0o700)!
				sentinel = occupied + '/existing-work'
				os.write_file(sentinel, 'existing Vending pending work must survive')!
			}
			'catalog', 'empty-catalog' {
				occupied = gms.data + '/_installed_apks_'
				os.mkdir(occupied, mode: 0o700)!
				if kind == 'catalog' {
					sentinel = occupied + '/com.android.vending.apk'
					os.write_file(sentinel, 'existing catalog APK must survive')!
				}
			}
			'catalog-symlink' {
				occupied = gms.data + '/_installed_apks_'
				watched = root + '/existing-catalog'
				os.mkdir(watched, mode: 0o700)!
				sentinel = watched + '/com.android.vending.apk'
				os.write_file(sentinel, 'existing catalog symlink target must survive')!
				os.symlink(watched, occupied)!
			}
			'target-owner' { second = Config{...vending, target_uid: vending.target_uid + 1} }
			'target-group' { second = Config{...vending, target_gid: vending.target_gid + 1} }
			'source-owner' { second = Config{...vending, source_owner: vending.source_owner + 1} }
			'source-group' { second = Config{...vending, source_group: vending.source_group + 1} }
			'source-writable' { os.chmod(vending.source, 0o600)! }
			'different-data' {
				watched = root + '/different-data'
				os.mkdir(watched, mode: 0o700)!
				second = Config{...vending, data: watched}
			}
			'scratch-alias' { second = Config{...vending, scratch: gms.scratch} }
			'scratch-child' { second = Config{...vending, scratch: gms.scratch + '/vending'} }
			'scratch-parent' { first = Config{...gms, scratch: vending.scratch + '/gms'} }
			'same-source' { second = Config{...vending, source: gms.source, sha256: gms.sha256} }
			'hardlinked-source' {
				watched = root + '/apks/gms-alias.apk'
				assert unsafe { C.link(&char(gms.source.str), &char(watched.str)) } == 0
				second = Config{...vending, source: watched, sha256: gms.sha256}
			}
			else {
				watched = root + '/apks/vending-symlink.apk'
				os.symlink(vending.source, watched)!
				second = Config{...vending, source: watched}
			}
		}
		gms_before := companion_test_object(gms.source)!
		vending_before := companion_test_object(vending.source)!
		data := companion_test_root_identity(gms.data)!
		occupied_before := if occupied != '' { companion_test_object(occupied)! } else { CompanionTestObject{} }
		watched_before := if watched != '' { companion_test_object(watched)! } else { CompanionTestObject{} }
		sentinel_before := if sentinel != '' { companion_test_object(sentinel)! } else { CompanionTestObject{} }
		content := if sentinel != '' { os.read_file(sentinel)! } else { '' }
		companion_expect_pair_rejected(first, second)!
		assert companion_test_object(gms.source)! == gms_before
		assert companion_test_object(vending.source)! == vending_before
		assert companion_test_digest(gms.source)! == gms.sha256
		assert companion_test_digest(vending.source)! == vending.sha256
		assert companion_test_root_identity(gms.data)! == data
		if occupied != '' { assert companion_test_object(occupied)! == occupied_before }
		if watched != '' { assert companion_test_object(watched)! == watched_before }
		if sentinel != '' {
			assert companion_test_object(sentinel)! == sentinel_before
			assert os.read_file(sentinel)! == content
		}
		for suffix in ['/_installed_apks_', '/com.google.android.gms_', '/.com.google.android.gms_.pending',
			'/com.android.vending_', '/.com.android.vending_.pending'] {
			path := gms.data + suffix
			if path != occupied { assert !os.exists(path) && !os.is_link(path) }
		}
		assert !os.exists(gms.scratch) && !os.is_link(gms.scratch)
		assert !os.exists(vending.scratch) && !os.is_link(vending.scratch)
		companion_assert_primary_cache(gms)!
	}
}

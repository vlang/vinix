module runtimefixture

import json2
import os

fn verified_native_payload_and_jar_install_without_mutating_old_alias(mut c Context) ! {
	c.payload('usr/lib/java/dex/art/core-oj-hostdex.jar', 'PK\x03\x04test-dex'.bytes(), 0o644)!
	target := c.runtime + '/' + text(c.constants, 'LIBART')
	os.mkdir_all(os.dir(target))!
	os.write_file(target, 'original 4 KiB ART')!
	alias := c.runtime + '/unchanged-art-alias.so'
	link(target, alias)!
	verified := c.read()!
	assert equivalent(c.apply(verified)!, verified)
	assert os.read_bytes(target)! == elf(183, 0)
	assert os.read_file(alias)! == 'original 4 KiB ART'
	assert os.stat(target)!.inode != os.stat(alias)!.inode
	jar := c.runtime + '/usr/lib/java/dex/art/core-oj-hostdex.jar'
	assert os.read_bytes(jar)! == 'PK\x03\x04test-dex'.bytes()
	assert os.stat(jar)!.mode & 0o777 == 0o644
	assert no_temporaries(c.runtime)
}

fn rejects_legacy_page_size_architecture_source_or_patch(mut c Context) ! {
	changes := map[string]json2.Any{
		'page_size':     json2.Any(4096)
		'architecture':  json2.Any('x86_64')
		'source_commit': json2.Any('b'.repeat(40))
		'source_sha512': json2.Any('b'.repeat(128))
		'source_sha256': json2.Any('b'.repeat(64))
		'patch_sha256':  json2.Any('b'.repeat(64))
		'build_flags':   json2.Any([]json2.Any{})
	}
	for key, value in changes {
		previous := map_field(c.manifest, key)
		c.manifest[key] = value
		c.reject()!
		c.manifest[key] = previous
	}
}

fn rejects_hash_and_size_mismatch(mut c Context) ! {
	mut records := map_field(c.manifest, 'files').as_array()
	original := records[0].as_map().clone()
	for key, value in {
		'sha256': json2.Any('b'.repeat(64))
		'size':   json2.Any(map_field(original, 'size').int() + 1)
	} {
		mut changed := record_copy(original)
		changed[key] = value
		records[0] = json2.Any(changed)
		c.manifest['files'] = json2.Any(records)
		c.reject()!
	}
	mut changed := record_copy(original)
	changed['size'] = json2.Any(true)
	records[0] = json2.Any(changed)
	c.manifest['files'] = json2.Any(records)
	c.reject()!
}

fn rejects_foreign_or_incongruent_elf_with_valid_file_hash(mut c Context) ! {
	for contents in [elf(62, 0), elf(183, 4096), '\x7fELF\x02\x01\x01'.bytes(), 'not an ELF'.bytes()] {
		c.payload(text(c.constants, 'LIBART'), contents, 0o755)!
		c.reject()!
	}
}

fn requires_every_native_output_before_replacing_existing_runtime(mut c Context) ! {
	original := map_field(c.manifest, 'files').as_array().clone()
	old := c.runtime + '/' + text(c.constants, 'LIBART')
	os.mkdir_all(os.dir(old))!
	os.write_file(old, 'existing 4 KiB package runtime')!
	mut names := strings(c.constants, 'ART_ELFS')
	names << strings(c.constants, 'ART_HEADERS')
	names.sort()
	for name in names {
		c.manifest['files'] = json2.Any(original.filter(text(it.as_map(), 'path') != name))
		c.write_manifest()!
		c.reject_apply(json2.Any(c.manifest), 'missing required native outputs')!
		assert os.read_file(old)! == 'existing 4 KiB package runtime'
	}
	c.manifest['files'] = json2.Any(original)
	c.write_manifest()!
	assert equivalent(c.read()!, json2.Any(c.manifest))
}

fn requires_native_elf_for_runtime_tools_and_support_libraries(mut c Context) ! {
	for name in ['usr/bin/dalvikvm', 'usr/lib/art/libartbase.so',
		'usr/lib/java/dex/art/natives/libjavacore.so'] {
		for contents in ['not an ELF'.bytes(), elf(62, 0), elf(183, 4096)] {
			c.payload(name, contents, 0o755)!
			c.reject()!
			c.payload(name, elf(183, 0), 0o755)!
		}
	}
}

fn rejects_outputs_outside_the_native_builder_and_optional_boot_jars(mut c Context) ! {
	c.payload('usr/lib/art/unverified-extra.so', elf(183, 0), 0o755)!
	failure('read_manifest', [c.overlay], []json2.Any{}, ['RuntimeError'], 'unexpected outputs')!
}

fn requires_libart_and_unique_relative_usr_paths(mut c Context) ! {
	original := map_field(c.manifest, 'files').as_array()[0].as_map().clone()
	for name in ['../usr/lib/art/libart.so', '/usr/lib/art/libart.so', 'usr/../lib.so',
		'usr//lib/art/libart.so', 'usr/./lib/art/libart.so', 'opt/libart.so'] {
		mut changed := record_copy(original)
		changed['path'] = json2.Any(name)
		c.manifest['files'] = json2.Any([json2.Any(changed)])
		c.reject()!
	}
	c.manifest['files'] = json2.Any([json2.Any(original), json2.Any(original.clone())])
	c.reject()!
	c.manifest['files'] = json2.Any([]json2.Any{})
	c.reject()!
	c.payload('usr/lib/art/libartbase.so', elf(183, 0), 0o755)!
	c.reject()!
}

fn rejects_overlay_symlink_file_or_parent(mut c Context) ! {
	path := c.overlay + '/' + text(c.constants, 'LIBART')
	os.rm(path)!
	outside := c.root + '/outside.so'
	os.write_file_array(outside, elf(183, 0))!
	symlink(outside, path)!
	c.reject()!
	os.rm(path)!
	parent := os.dir(path)
	directory := c.root + '/outside'
	os.mv(parent, directory)!
	os.write_file_array(directory + '/libart.so', elf(183, 0))!
	symlink(directory, parent)!
	c.reject()!
}

fn rejects_manifest_or_source_changed_before_apply(mut c Context) ! {
	verified := c.read()!
	c.manifest['page_size'] = json2.Any(4096)
	c.write_manifest()!
	c.reject_apply(verified, '')!
	assert !os.exists(c.runtime)
	c.manifest['page_size'] = json2.Any(16384)
	c.write_manifest()!
	os.write_file(c.overlay + '/' + text(c.constants, 'LIBART'), 'changed')!
	c.reject_apply(verified, '')!
	assert !os.exists(c.runtime)
}

fn checks_all_destination_parents_before_any_replacement(mut c Context) ! {
	c.payload('usr/bin/dalvikvm', elf(183, 0), 0o755)!
	old := c.runtime + '/' + text(c.constants, 'LIBART')
	os.mkdir_all(os.dir(old))!
	os.write_file(old, 'untouched')!
	outside := c.root + '/outside'
	os.mkdir(outside)!
	symlink(outside, c.runtime + '/usr/bin')!
	c.reject_apply(c.read()!, '')!
	assert os.read_file(old)! == 'untouched'
	assert os.ls(outside)!.len == 0
}

fn replaces_every_soname_alias_without_overwriting_package_hardlinks(mut c Context) ! {
	old := c.root + '/old-library.so'
	os.write_file(old, 'old 4 KiB bionic loader')!
	for name in strings(c.constants, 'BIONIC_LIBRARIES') {
		target := c.runtime + '/' + name
		os.mkdir_all(os.dir(target))!
		link(old, target)!
	}
	verified := c.read()!
	assert equivalent(c.apply(verified)!, verified)
	for name in strings(c.constants, 'BIONIC_LIBRARIES') {
		target := c.runtime + '/' + name
		assert os.read_bytes(target)! == elf(183, 0)
		assert os.stat(target)!.inode != os.stat(old)!.inode
	}
	assert os.read_file(old)! == 'old 4 KiB bionic loader'
}

fn rejects_legacy_or_other_source_patch_flags(mut c Context) ! {
	changes := map[string]json2.Any{
		'page_size':     json2.Any(4096)
		'architecture':  json2.Any('x86_64')
		'source_commit': map_field(c.constants, 'SOURCE_COMMIT')
		'source_sha256': json2.Any('b'.repeat(64))
		'source_sha512': json2.Any('b'.repeat(128))
		'patch_sha256':  json2.Any('b'.repeat(64))
		'build_flags':   json2.Any([json2.Any('-DART_PAGE_SIZE=16384')])
	}
	for key, value in changes {
		previous := map_field(c.manifest, key)
		c.manifest[key] = value
		c.reject()!
		c.manifest[key] = previous
	}
}

fn requires_all_aliases_and_rejects_unexpected_nonelf_payloads(mut c Context) ! {
	original := map_field(c.manifest, 'files').as_array().clone()
	c.manifest['files'] = json2.Any(original[..original.len - 1])
	c.reject()!
	c.manifest['files'] = json2.Any(original)
	c.payload('usr/lib/additional.so', elf(183, 0), 0o755)!
	c.reject()!
	c.manifest['files'] = json2.Any(original)
	c.payload('usr/lib/libc_bio.so', 'PK\x03\x04not-an-ELF'.bytes(), 0o755)!
	c.reject()!
}

fn rejects_foreign_incongruent_or_stale_alias_elf(mut c Context) ! {
	for contents in [elf(62, 0), elf(183, 4096), stale_elf()] {
		c.payload('usr/lib/libdl_bio.so.0', contents, 0o755)!
		c.reject()!
	}
}

fn rejects_checksum_changes_and_symlink_escape_before_installing(mut c Context) ! {
	verified := c.read()!
	path := c.overlay + '/usr/lib/libc_bio.so'
	os.write_file(path, 'changed after verification')!
	c.reject_apply(verified, '')!
	assert !os.exists(c.runtime)
	os.rm(path)!
	outside := c.root + '/outside.so'
	os.write_file_array(outside, elf(183, 0))!
	symlink(outside, path)!
	c.reject()!
}

fn rejects_duplicate_or_escaping_paths(mut c Context) ! {
	original := map_field(c.manifest, 'files').as_array().clone()
	mut duplicate := original.clone()
	duplicate << json2.Any(original[0].as_map().clone())
	c.manifest['files'] = json2.Any(duplicate)
	c.reject()!
	for name in ['../usr/lib/libc_bio.so', '/usr/lib/libc_bio.so', 'usr/../libc_bio.so'] {
		mut changed := original[0].as_map().clone()
		changed['path'] = json2.Any(name)
		mut records := [json2.Any(changed)]
		records << original[1..]
		c.manifest['files'] = json2.Any(records)
		c.reject()!
	}
}

pub fn run(selection string) ! {
	verify_original_builders()!
	cases := map[string]fn (mut Context) !{
		'RuntimeTests.test_verified_native_payload_and_jar_install_without_mutating_old_alias': verified_native_payload_and_jar_install_without_mutating_old_alias
		'RuntimeTests.test_rejects_legacy_page_size_architecture_source_or_patch':              rejects_legacy_page_size_architecture_source_or_patch
		'RuntimeTests.test_rejects_hash_and_size_mismatch':                                     rejects_hash_and_size_mismatch
		'RuntimeTests.test_rejects_foreign_or_incongruent_elf_with_valid_file_hash':            rejects_foreign_or_incongruent_elf_with_valid_file_hash
		'RuntimeTests.test_requires_every_native_output_before_replacing_existing_runtime':     requires_every_native_output_before_replacing_existing_runtime
		'RuntimeTests.test_requires_native_elf_for_runtime_tools_and_support_libraries':        requires_native_elf_for_runtime_tools_and_support_libraries
		'RuntimeTests.test_rejects_outputs_outside_the_native_builder_and_optional_boot_jars':  rejects_outputs_outside_the_native_builder_and_optional_boot_jars
		'RuntimeTests.test_requires_libart_and_unique_relative_usr_paths':                      requires_libart_and_unique_relative_usr_paths
		'RuntimeTests.test_rejects_overlay_symlink_file_or_parent':                             rejects_overlay_symlink_file_or_parent
		'RuntimeTests.test_rejects_manifest_or_source_changed_before_apply':                    rejects_manifest_or_source_changed_before_apply
		'RuntimeTests.test_checks_all_destination_parents_before_any_replacement':              checks_all_destination_parents_before_any_replacement
		'BionicTests.test_replaces_every_soname_alias_without_overwriting_package_hardlinks':   replaces_every_soname_alias_without_overwriting_package_hardlinks
		'BionicTests.test_rejects_legacy_or_other_source_patch_flags':                          rejects_legacy_or_other_source_patch_flags
		'BionicTests.test_requires_all_aliases_and_rejects_unexpected_nonelf_payloads':         requires_all_aliases_and_rejects_unexpected_nonelf_payloads
		'BionicTests.test_rejects_foreign_incongruent_or_stale_alias_elf':                      rejects_foreign_incongruent_or_stale_alias_elf
		'BionicTests.test_rejects_checksum_changes_and_symlink_escape_before_installing':       rejects_checksum_changes_and_symlink_escape_before_installing
		'BionicTests.test_rejects_duplicate_or_escaping_paths':                                 rejects_duplicate_or_escaping_paths
	}
	assert selection == '' || selection in cases, 'Unknown native fixture ' + selection
	for name, test in cases {
		if selection != '' && selection != name { continue }
		run_case(name, test)!
		println('PASS ' + name)
	}
}

fn run_case(name string, test fn (mut Context) !) ! {
	mut c := context(name.starts_with('BionicTests.'))!
	defer { os.rmdir_all(c.root) or { panic(err) } }
	test(mut c)!
}

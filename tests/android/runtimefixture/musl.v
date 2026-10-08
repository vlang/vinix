module runtimefixture

import crypto.sha256
import json2
import os

const musl_original_source = 'b02ac26ff056e6e30131bde1ea0284de6c709cb41695391fb848c53c95b7e1b5'

struct MuslContext {
	root      string
	runtime   string
	constants map[string]json2.Any
mut:
	manifest  map[string]json2.Any
	overrides map[string]json2.Any
}

fn musl_call(operation string, paths []string, values []json2.Any, overrides map[string]json2.Any) !map[string]json2.Any {
	return call({
		'module':    json2.Any('musl')
		'operation': json2.Any(operation)
		'paths':     json2.Any(paths.map(json2.Any(it)))
		'values':    json2.Any(values)
		'overrides': json2.Any(overrides)
	})!
}

fn musl_context() !MuslContext {
	constants := map_field(call({
		'module':     json2.Any('musl')
		'attributes': json2.Any(['MUSL', 'MANIFEST', 'PATCH', 'SOURCE_SHA256', 'LIBRARIES'].map(json2.Any(it)))
	})!, 'result').as_map()
	patches := musl_call('source_patches', []string{}, []json2.Any{}, map[string]json2.Any{})!
	assert 'result' in patches, json2.encode(patches)
	root := temporary()!
	mut transferred := false
	defer { if !transferred { os.rmdir_all(root) or { panic(err) } } }
	runtime := root + '/runtime'
	os.mkdir(runtime)!
	mut c := MuslContext{
		root:      root
		runtime:   runtime
		constants: constants
		manifest:  {
			'version':         json2.Any('1.2.6')
			'arch':            json2.Any('aarch64')
			'source_sha256':   map_field(constants, 'SOURCE_SHA256')
			'source_url':      json2.Any('https://musl.libc.org/releases/musl-1.2.6.tar.gz')
			'patches':         map_field(patches, 'result')
			'retention':       json2.Any(1)
			'cflags':          json2.Any('-fstack-protector-strong -DVINIX_MALLOC_RETAIN=1')
			'ldflags':         json2.Any('-Wl,-soname,libc.musl-aarch64.so.1 -Wl,-z,max-page-size=65536')
			'compiler_target': json2.Any('aarch64-linux-musl')
		}
	}
	c.install_libraries(musl_elf(183, 0))!
	c.write_manifest()!
	transferred = true
	return c
}

fn musl_elf(machine u16, offset int) []u8 {
	mut data := elf(machine, offset)
	put64(mut data, 112, 65536)
	return data
}

fn (mut c MuslContext) install_libraries(contents []u8) ! {
	for name in strings(c.constants, 'LIBRARIES') {
		path := c.runtime + '/' + name
		os.mkdir_all(os.dir(path))!
		if os.exists(path) || os.is_link(path) { os.rm(path)! }
		os.write_file_array(path, contents)!
	}
	c.manifest['libc_so_sha256'] = json2.Any(sha256.sum(contents).hex())
}

fn (c MuslContext) write_manifest() !string {
	receipt := c.runtime + '/' + text(c.constants, 'MANIFEST')
	os.mkdir_all(os.dir(receipt))!
	os.write_file(receipt, json2.encode(c.manifest))!
	return receipt
}

fn (c MuslContext) response() !map[string]json2.Any {
	return musl_call('read_manifest', [c.runtime], []json2.Any{}, c.overrides)!
}

fn (c MuslContext) read() !json2.Any {
	row := c.response()!
	assert 'result' in row, json2.encode(row)
	return map_field(row, 'result')
}

// Concrete subclasses correspond to the original RuntimeError/OSError/ValueError tuple.
fn (c MuslContext) reject_response(kinds []string, contains string) ! {
	row := c.response()!
	assert text(row, 'kind') in kinds, json2.encode(row)
	assert text(row, 'message').contains(contains), json2.encode(row)
}

fn (c MuslContext) reject() ! {
	c.write_manifest()!
	c.reject_response(['RuntimeError', 'OSError', 'FileNotFoundError', 'ValueError', 'JSONDecodeError'], '')!
}

fn musl_accepts_verified_private_runtime_with_materialized_loader_alias(mut c MuslContext) ! {
	names := strings(c.constants, 'LIBRARIES')
	loader := c.runtime + '/' + names[0]
	alias := c.runtime + '/' + names[1]
	os.rm(alias)!
	link(loader, alias)!
	assert equivalent(c.read()!, json2.Any(c.manifest))
	assert os.stat(loader)!.inode == os.stat(alias)!.inode
}

fn musl_rejects_loader_or_libc_tampering(mut c MuslContext) ! {
	for name in strings(c.constants, 'LIBRARIES') {
		c.install_libraries(musl_elf(183, 0))!
		path := c.runtime + '/' + name
		mut contents := os.read_bytes(path)!
		contents << 'changed'.bytes()
		os.write_file_array(path, contents)!
		c.reject()!
	}
}

fn musl_rejects_wrong_architecture_or_page_layout_even_with_matching_hash(mut c MuslContext) ! {
	for contents in [musl_elf(62, 0), musl_elf(183, 4096), 'not an ELF'.bytes(),
		'\x7fELF\x02\x01\x01'.bytes()] {
		c.install_libraries(contents)!
		c.reject()!
	}
}

fn musl_rejects_missing_libraries_and_unmaterialized_symlinks(mut c MuslContext) ! {
	for name in strings(c.constants, 'LIBRARIES') {
		for use_symlink in [false, true] {
			c.install_libraries(musl_elf(183, 0))!
			path := c.runtime + '/' + name
			os.rm(path)!
			if use_symlink {
				target := c.root + '/outside-libc.so'
				os.write_file_array(target, musl_elf(183, 0))!
				symlink(target, path)!
			}
			c.reject()!
		}
	}
}

fn musl_rejects_missing_or_symlinked_build_receipt(mut c MuslContext) ! {
	receipt := c.write_manifest()!
	os.rm(receipt)!
	c.reject_response(['FileNotFoundError'], '')!
	external := c.root + '/external-receipt.json'
	os.write_file(external, json2.encode(c.manifest))!
	symlink(external, receipt)!
	c.reject_response(['RuntimeError'], 'receipt must be a regular file')!
}

fn musl_rejects_an_ordinary_source_built_libc_without_statistics_patch(mut c MuslContext) ! {
	c.manifest['patches'] = json2.Any(map_field(c.manifest, 'patches').as_array().filter(text(it.as_map(), 'name') != os.file_name(text(c.constants, 'PATCH'))))
	c.reject()!
}

fn musl_rejects_source_and_build_settings_outside_private_android_recipe(mut c MuslContext) ! {
	changes := {
		'version':         json2.Any('1.2.5')
		'arch':            json2.Any('x86_64')
		'source_sha256':   json2.Any('0'.repeat(64))
		'source_url':      json2.Any('https://example.org/musl.tar.gz')
		'retention':       json2.Any(0)
		'cflags':          json2.Any('-O2')
		'ldflags':         json2.Any('-Wl,-soname,libc.musl-aarch64.so.1')
		'compiler_target': json2.Any('x86_64-linux-musl')
	}
	for key, value in changes {
		previous := map_field(c.manifest, key)
		c.manifest[key] = value
		c.reject()!
		c.manifest[key] = previous
	}
}

fn musl_rejects_stale_reordered_or_incomplete_patch_receipts(mut c MuslContext) ! {
	original := map_field(c.manifest, 'patches').as_array().map(json2.Any(record_copy(it.as_map())))
	mut stale := []json2.Any{}
	for item in original { stale << json2.Any(record_copy(item.as_map())) }
	mut last := record_copy(stale[stale.len - 1].as_map())
	last['sha256'] = json2.Any('0'.repeat(64))
	stale[stale.len - 1] = json2.Any(last)
	mut duplicate := original.clone()
	duplicate << original[original.len - 1]
	for records in [original[..original.len - 1], original[1..], original.reverse(), duplicate,
		stale] {
		c.manifest['patches'] = json2.Any(records)
		c.reject()!
	}
	c.manifest['patches'] = json2.Any(original)
}

fn musl_copy(operation string, source string, destination string) ! {
	row := call({
		'module':    json2.Any('shutil')
		'operation': json2.Any(operation)
		'paths':     json2.Any([json2.Any(source), json2.Any(destination)])
	})!
	assert 'result' in row, json2.encode(row)
}

fn musl_source_patch_changes_invalidate_an_existing_receipt(mut c MuslContext) ! {
	sources := c.root + '/source-patches'
	musl := text(c.constants, 'MUSL')
	musl_copy('copytree', musl + '/alpine-1.2.6', sources + '/alpine-1.2.6')!
	musl_copy('copy2', musl + '/malloc-retain.patch', sources)!
	private := sources + '/' + os.file_name(text(c.constants, 'PATCH'))
	musl_copy('copy2', text(c.constants, 'PATCH'), private)!
	c.overrides = {
		'MUSL':  json2.Any(sources)
		'PATCH': json2.Any(private)
	}
	assert equivalent(c.read()!, json2.Any(c.manifest))
	for target in [private, sources + '/malloc-retain.patch'] {
		original := os.read_bytes(target)!
		mut changed := original.clone()
		changed << '\nchanged input\n'.bytes()
		os.write_file_array(target, changed)!
		c.reject()!
		os.write_file_array(target, original)!
	}
	assert equivalent(c.read()!, json2.Any(c.manifest))
}

fn musl_rejects_invalid_receipt_format(mut c MuslContext) ! {
	receipt := c.write_manifest()!
	for contents in ['{', '[]', 'null', '1'] {
		os.write_file(receipt, contents)!
		c.reject_response(['RuntimeError', 'ValueError', 'JSONDecodeError'], '')!
	}
}

pub fn musl_source_identity() string { return musl_original_source }

// Assertions terminate the child. The waiting parent owns and retires the
// complete scratch tree on successful checks and failed assertions alike.
pub fn run_musl_guarded(selection string) ! {
	guarded(selection, '--child-musl')!
}

pub fn run_musl(selection string) ! {
	gold := json2.decode[map[string]json2.Any](os.read_file(os.dir(@FILE) + '/musl-elf.json')!)!
	assert text(gold, 'original_source_sha256') == musl_original_source
	images := map_field(gold, 'elf').as_map()
	assert musl_elf(183, 0).hex() == text(images, 'native')
	assert musl_elf(62, 0).hex() == text(images, 'foreign')
	assert musl_elf(183, 4096).hex() == text(images, 'incongruent')
	cases := map[string]fn (mut MuslContext) !{
		'MuslRuntimeTests.test_accepts_verified_private_runtime_with_materialized_loader_alias':   musl_accepts_verified_private_runtime_with_materialized_loader_alias
		'MuslRuntimeTests.test_rejects_loader_or_libc_tampering':                                  musl_rejects_loader_or_libc_tampering
		'MuslRuntimeTests.test_rejects_wrong_architecture_or_page_layout_even_with_matching_hash': musl_rejects_wrong_architecture_or_page_layout_even_with_matching_hash
		'MuslRuntimeTests.test_rejects_missing_libraries_and_unmaterialized_symlinks':             musl_rejects_missing_libraries_and_unmaterialized_symlinks
		'MuslRuntimeTests.test_rejects_missing_or_symlinked_build_receipt':                        musl_rejects_missing_or_symlinked_build_receipt
		'MuslRuntimeTests.test_rejects_an_ordinary_source_built_libc_without_statistics_patch':    musl_rejects_an_ordinary_source_built_libc_without_statistics_patch
		'MuslRuntimeTests.test_rejects_source_and_build_settings_outside_private_android_recipe':  musl_rejects_source_and_build_settings_outside_private_android_recipe
		'MuslRuntimeTests.test_rejects_stale_reordered_or_incomplete_patch_receipts':              musl_rejects_stale_reordered_or_incomplete_patch_receipts
		'MuslRuntimeTests.test_source_patch_changes_invalidate_an_existing_receipt':               musl_source_patch_changes_invalidate_an_existing_receipt
		'MuslRuntimeTests.test_rejects_invalid_receipt_format':                                    musl_rejects_invalid_receipt_format
	}
	assert selection == '' || selection in cases, 'Unknown native fixture ' + selection
	for name, test in cases {
		if selection != '' && selection != name { continue }
		musl_run_case(test)!
		println('PASS ' + name)
	}
}

fn musl_run_case(test fn (mut MuslContext) !) ! {
	mut c := musl_context()!
	defer { os.rmdir_all(c.root) or { panic(err) } }
	test(mut c)!
}

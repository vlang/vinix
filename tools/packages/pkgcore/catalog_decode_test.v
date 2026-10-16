// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os
import strings
import time

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
}

fn catalog_decode_selected(selection string) bool {
	return os.args.len != 3 || os.args[1] != '--catalog-decode-case' || os.args[2] == selection
}

fn catalog_decode_package(architecture string) Package {
	return Package{ id: 'data', name: 'Data é🚀', version: '1.0.0', architecture: architecture,
		description: 'Quoted "packages":[] and braces {}', homepage: 'https://example.invalid',
		kind: 'data', license: 'MIT', arguments: ['--title="Data"'], permissions: ['files'],
		associations: ['text/plain'], dependencies: [Dependency{ id: 'base', minimum: '1.0.0', before: '2.0.0' }],
		files: [Payload{ path: 'share/0', sha256: 'a'.repeat(64), bytes: 1 }] }
}

// Stream complete records. Generic fixture encoders would dominate the guest's
// heap at the full import/payload bounds; only small results are re-encoded.
fn catalog_decode_document(count int, selectors int, files int, architecture string) string {
	p := catalog_decode_package(architecture); defer { close_decoded_package(p) }
	text := json2.encode(p); defer { unsafe { text.free() } }
	start := text.index('"files":[') or { panic('fixture files missing') } + '"files":['.len
	end := text.index('],"sdk":') or { panic('fixture sdk missing') }
	mut item := strings.new_builder(files * 160 + selectors * 64 + 1024)
	defer { unsafe { item.free() } }
	item.write_string('{"source":"'); item.write_string(architecture)
	item.write_string('","recipe":{"format":1,"manifest":')
	item.write_string(unsafe { tos(text.str, start) })
	for i in 0 .. files {
		if i > 0 { item.write_u8(`,`) }
		digits := i.str(); defer { unsafe { digits.free() } }
		item.write_string('{"path":"share/'); item.write_string(digits)
		item.write_string('","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","bytes":1,"executable":false}')
	}
	item.write_string(unsafe { tos(text.str + end, text.len - end) })
	item.write_string(',"entries":[')
	for i in 0 .. selectors {
		if i > 0 { item.write_u8(`,`) }
		digits := i.str(); defer { unsafe { digits.free() } }
		item.write_string('{"source":"source/'); item.write_string(digits)
		item.write_string('","path":"share/'); item.write_string(digits); item.write_string('"}')
	}
	item.write_string(']}}')
	part := item.str(); defer { unsafe { part.free() } }
	mut out := strings.new_builder(part.len * count + 128); defer { unsafe { out.free() } }
	out.write_string('{"format":1,"architectures":["'); out.write_string(architecture)
	out.write_string('"],"packages":[')
	for i in 0 .. count { if i > 0 { out.write_u8(`,`) }; out.write_string(part) }
	out.write_string(']}')
	return out.str()
}

fn catalog_decode_refusal(text string) {
	if value := decode_catalog_recipe(text) { close_decoded_catalog(value); assert false }
	else { message := err.msg(); assert message != ''; unsafe { message.free(); err.free() } }
}

fn test_catalog_decode_owns_complete_and_growing_imports() {
	if os.args.len == 3 && os.args[1] == '--catalog-decode-case' && !os.args[2].starts_with('owned-') { return }
	for architecture in ['aarch64', 'x86_64']! {
		for count in [1, 64, 4096]! {
			if !catalog_decode_selected('owned-' + architecture + '-' + count.str()) { continue }
			text := catalog_decode_document(count, 1, 1, architecture); defer { unsafe { text.free() } }
			tracked := count != 4096
			cycles := if tracked { $if track_heap ? { 1000 } $else { 64 } } else { 1 }
			$if track_heap ? { if tracked { C.vinix_heap_begin() } }
			for _ in 0 .. cycles {
				value := decode_catalog_recipe(text)!
				assert value.format == 1 && value.architectures.len == 1 && value.architectures[0] == architecture && value.packages.len == count
				last := value.packages[count - 1]
				assert last.source == architecture && last.recipe.manifest.name == 'Data é🚀'
				assert last.recipe.manifest.arguments[0] == '--title="Data"' && last.recipe.manifest.dependencies[0].before == '2.0.0'
				assert last.recipe.entries[0].path == 'share/0' && last.recipe.manifest.files[0].bytes == 1
				close_decoded_catalog(value)
			}
			$if track_heap ? { if tracked {
				kept := C.vinix_heap_end(); assert kept == 0
				println('CATALOG DECODE ' + architecture + ' ' + count.str() + ' imports: 1000 cycles retained ' + kept.str() + ' bytes')
			} }
			if !tracked { continue }
			source := text.clone()
			first := decode_catalog_recipe(source)!; second := decode_catalog_recipe(source)!
			assert first == second && first.packages.data != second.packages.data && first.packages[0].source.str != second.packages[0].source.str
			close_decoded_catalog(first); unsafe { source.free() }
			assert second.packages[count - 1].recipe.manifest.name == 'Data é🚀' && json2.encode(second) == text
			close_decoded_catalog(second)
		}
	}
	println('CATALOG DECODE both architectures, independent owned complete records, exact writer bytes and full 4096 import bounds PASS')
}

fn test_catalog_decode_preserves_legacy_protocol_and_template_separation() {
	if !catalog_decode_selected('legacy') { return }
	text := catalog_decode_document(1, 1, 1, 'aarch64')
	inputs := [text, ' \n' + text + '\t', text.replace('"recipe":', '"rec\\u0069pe":'), text.replace('"sdk":1', '"sdk":1,"window_protocol":0')]
	cycles := $if track_heap ? { 1000 } $else { 64 }
	for input in inputs {
		$if track_heap ? { C.vinix_heap_begin() }
		for _ in 0 .. cycles {
			value := decode_catalog_recipe(input)!
			assert value.packages[0].recipe.manifest.sdk == 1 && value.packages[0].recipe.manifest.window_protocol == 0
			close_decoded_catalog(value)
		}
		$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0 }
		value := decode_catalog_recipe(input)!; assert json2.encode(value) == text; close_decoded_catalog(value)
	}
	template := '{"manifest":{"dependencies":[{}],"files":[{}]},"entries":[{"source":"COPYING","path":"COPYING"}]}'
	locked_template := '{"format":1,"architectures":["aarch64"],"packages":[{"source":"shared","recipe":' + template + '}]}'
	$if track_heap ? { C.vinix_heap_begin() }
	for _ in 0 .. cycles {
		root := decode_root_recipe(template)!; assert root.format == 1 && root.manifest.sdk == 1
		close_decoded_root_recipe(root)
		catalog_decode_refusal(locked_template)
	}
	$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0 }
	println('CATALOG DECODE whitespace, escaped keys and legacy window protocol preserve writer bytes; source defaults cannot enter complete catalog locks PASS')
}

fn test_catalog_decode_partial_schema_and_typed_refusals_retire_storage() {
	if !catalog_decode_selected('refusals') { return }
	text := catalog_decode_document(2, 1, 1, 'aarch64')
	invalid_utf8 := [u8(0xc0), 0xaf].bytestr()
	inputs := [text + 'true', text.replace('"packages":', '"unknown":false,"packages":'),
		text.replace('"source":"aarch64"', '"source":"aarch64","sour\\u0063e":"aarch64"'),
		text.replace('"recipe":{"format":1,', '"recipe":{'),
		text.replace(',"sdk":1', ''), text.replace('"minimum":"1.0.0",', ''), text.replace('"executable":false', '"executable":null'),
		text.replace('"entries":[', '"entries":[null,'), text.replace('"permissions":["files"]', '"permissions":null'),
		text.replace('"source":"source/0",', ''), text.replace('"files":[', '"files":[null,'),
		text.replace('"format":1', '"format":2147483648'), text.replace('"format":1', '"format":1.0'),
		text.replace('"format":1', '"format":01'), text.replace('Data é🚀', invalid_utf8), text.replace('Data é🚀', '\\uD800'),
		text.replace('"bytes":1', '"bytes":18446744073709551616'), text.replace('"bytes":1', '"bytes":1e0'),
		text.replace('"architectures":["aarch64"]', '"architectures":null'), text.replace('"architectures":["aarch64"]', '"architectures":[null]'),
		text.replace('"packages":[', '"packages":[null,'), text.replace('"recipe":{"format":1,', '"recipe":{"format":1,"unknown":{},'),
		text.replace('"source":"aarch64","recipe":', '"source":"aarch64","recipe":null,"ignored":'),
		text.replace_once('},{"source":"aarch64"', '},{"source":"' + invalid_utf8 + '"'),
		text.replace('"path":"share/0"}', '"path":"\\uD800"}'), '{}']
	$if track_heap ? { C.vinix_heap_begin() }
	for end in 0 .. text.len { catalog_decode_refusal(unsafe { tos(text.str, end) }) }
	$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0 }
	cycles := $if track_heap ? { 1000 } $else { 64 }
	for number, input in inputs {
		assert input != text
		$if track_heap ? { C.vinix_heap_begin() }
		for _ in 0 .. cycles { catalog_decode_refusal(input) }
		$if track_heap ? {
			kept := C.vinix_heap_end(); assert kept == 0
			println('CATALOG DECODE refusal ' + number.str() + ': 1000 cycles retained ' + kept.str() + ' bytes')
		}
	}
	println('CATALOG DECODE every truncated prefix and schema/UTF8/number/late import and selector refusal cycles retire scratch PASS')
}

fn test_catalog_decode_metadata_architecture_and_nested_bounds() {
	if !catalog_decode_selected('bounds') { return }
	text := catalog_decode_document(1, 1, 1, 'x86_64')
	for size in [max_metadata - 1, max_metadata]! {
		padding := ' '.repeat(size - text.len); padded := text + padding
		value := decode_catalog_recipe(padded)!; close_decoded_catalog(value)
		unsafe { padded.free(); padding.free() }
	}
	padding := ' '.repeat(max_metadata + 1 - text.len); oversized := text + padding
	catalog_decode_refusal(oversized); unsafe { oversized.free(); padding.free() }
	catalog_decode_refusal(catalog_decode_document(4097, 1, 1, 'x86_64'))
	catalog_decode_refusal(catalog_decode_document(1, 1025, 1, 'x86_64'))
	catalog_decode_refusal(catalog_decode_document(1, 1, max_files + 1, 'x86_64'))
	for invalid in [text.replace('"architectures":["x86_64"]', '"architectures":["aarch64","x86_64","aarch64"]'),
		text.replace('"source":"x86_64"', '"source":"' + 'x'.repeat(1025) + '"'),
		text.replace('"arguments":["--title=\\"Data\\""]', '"arguments":[' + '"a",'.repeat(64) + '"a"]'),
		text.replace('"permissions":["files"]', '"permissions":["audio","display","files","network","process","files"]')] { catalog_decode_refusal(invalid) }
	println('CATALOG DECODE exact 8 MiB accepted; metadata/import/architecture/source/selector/payload/argument/permission overflow refused PASS')
}

fn test_catalog_decode_full_selector_and_payload_bounds() {
	if !catalog_decode_selected('nested') { return }
	for architecture in ['aarch64', 'x86_64']! {
		text := catalog_decode_document(1, 1024, 1, architecture)
		$if track_heap ? { C.vinix_heap_begin() }
		value := decode_catalog_recipe(text)!
		assert value.packages[0].recipe.entries.len == 1024 && value.packages[0].recipe.entries.last().path == 'share/1023'
		close_decoded_catalog(value)
		$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0 }
		unsafe { text.free() }
		payload_text := catalog_decode_document(1, 1, max_files, architecture)
		full := decode_catalog_recipe(payload_text)!
		assert full.packages[0].recipe.manifest.files.len == max_files && full.packages[0].recipe.manifest.files.last().path == 'share/16383'
		close_decoded_catalog(full); unsafe { payload_text.free() }
	}
	println('CATALOG DECODE full 1024 selectors retire tracked storage; 16384 payloads preserve complete fields and retire their single live owner PASS')
}

fn test_catalog_decode_refusal_preserves_publisher_workspaces_and_restored_retry_publishes() {
	if !catalog_decode_selected('pack') { return }
	work := os.temp_dir() + '/vinix-catalog-decode-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir_all(work + '/roots/shared')!; defer { os.rmdir_all(work) or {} }
	os.write_file(work + '/roots/shared/COPYING', 'redistribution terms')!
	p := Package{ id: 'notice', version: '1.0.0', architecture: 'all', name: 'Notice', kind: 'data', license: 'MIT',
		files: [Payload{ path: 'COPYING', sha256: hash_file(work + '/roots/shared/COPYING')!, bytes: 20 }] }
	valid := json2.encode(CatalogRecipe{ format: 1, architectures: ['x86_64', 'aarch64'], packages: [CatalogImport{ source: 'shared',
		recipe: RootRecipe{ manifest: p, entries: [RootEntry{ source: 'COPYING', path: 'COPYING' }] } }] })
	os.mkdir_all(work + '/existing')!; os.write_file(work + '/existing/keep', 'existing workspace')!
	for invalid in [valid[..valid.len - 1], valid.replace(',"sdk":1', ''), valid.replace('"entries":[', '"entries":[{},')] {
		assert invalid != valid
		os.write_file(work + '/catalog.json', invalid)!
		for destination in [work + '/absent', work + '/existing'] {
			if _ := pack_catalog(work + '/catalog.json', work + '/roots', destination) { assert false } else { assert err.msg() != '' }
		}
		if _ := compose_catalog([CatalogSource{ id: 'notice', catalog: work + '/catalog.json' }], work + '/composed') { assert false } else { assert err.msg() != '' }
		assert !os.exists(work + '/absent') && !os.exists(work + '/composed') && os.ls(work + '/existing')! == ['keep']
		assert os.read_file(work + '/roots/shared/COPYING')! == 'redistribution terms' && os.read_file(work + '/existing/keep')! == 'existing workspace'
	}
	os.write_file(work + '/catalog.json', valid)!
	first := pack_catalog(work + '/catalog.json', work + '/roots', work + '/first')!
	os.write_file(work + '/catalog.json', valid.replace('"sdk":1', '"sdk":1,"window_protocol":0'))!
	second := pack_catalog(work + '/catalog.json', work + '/roots', work + '/second')!
	assert first.catalog_sha256 == second.catalog_sha256 && first.architectures == ['aarch64', 'x86_64']
	assert os.read_file(work + '/first/catalog.json')! == os.read_file(work + '/second/catalog.json')!
	println('CATALOG DECODE invalid catalog preserves sources and existing/absent pack/composition destinations; restored complete and legacy locks publish unchanged canonical bytes PASS')
}

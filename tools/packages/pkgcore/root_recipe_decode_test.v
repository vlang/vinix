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

fn root_recipe_selected(selection string) bool {
	return os.args.len != 3 || os.args[1] != '--root-recipe-case' || os.args[2] == selection
}

fn root_recipe_sample(architecture string) Package {
	return Package{ id: 'data', name: 'Data é🚀', version: '1.0.0', architecture: architecture,
		description: 'Quoted "entries":[] and braces {}', homepage: 'https://example.invalid',
		license: 'MIT', kind: 'data', arguments: ['--title="Data"'], permissions: ['files'],
		associations: ['text/plain'], dependencies: [Dependency{ id: 'base', minimum: '1.0.0' }],
		files: [Payload{ path: 'share/0', sha256: 'a'.repeat(64), bytes: 1 }] }
}

// Stream inventories, so fixture encoding does not dominate a guest's live heap.
fn root_recipe_document(count int, files int, architecture string) string {
	p := root_recipe_sample(architecture); defer { close_decoded_package(p) }
	text := json2.encode(p); defer { unsafe { text.free() } }
	start := text.index('"files":[') or { panic('fixture files missing') } + '"files":['.len
	end := text.index('],"sdk":') or { panic('fixture sdk missing') }
	mut out := strings.new_builder(files * 160 + count * 64 + 1024)
	defer { unsafe { out.free() } }
	out.write_string('{"format":1,"manifest":')
	out.write_string(unsafe { tos(text.str, start) })
	for i in 0 .. files {
		if i > 0 { out.write_u8(`,`) }
		digits := i.str(); defer { unsafe { digits.free() } }
		out.write_string('{"path":"share/'); out.write_string(digits)
		out.write_string('","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","bytes":1,"executable":false}')
	}
	out.write_string(unsafe { tos(text.str + end, text.len - end) })
	out.write_string(',"entries":[')
	for i in 0 .. count {
		if i > 0 { out.write_u8(`,`) }
		digits := i.str(); defer { unsafe { digits.free() } }
		out.write_string('{"source":"source/'); out.write_string(digits)
		out.write_string('","path":"share/'); out.write_string(digits); out.write_string('"}')
	}
	out.write_string(']}')
	return out.str()
}

fn root_recipe_refusal(text string) {
	if value := decode_root_recipe(text) { close_decoded_root_recipe(value); assert false }
	else { message := err.msg(); assert message != ''; unsafe { message.free(); err.free() } }
}

fn test_root_recipe_decoder_owns_templates_and_growing_selectors() {
	if os.args.len == 3 && os.args[1] == '--root-recipe-case' && !os.args[2].starts_with('owned-') { return }
	for architecture in ['aarch64', 'x86_64']! {
		for count in [1, 64, 1024]! {
			if !root_recipe_selected('owned-' + architecture + '-' + count.str()) { continue }
			text := root_recipe_document(count, 1, architecture)
			defer { unsafe { text.free() } }
			last := 'share/' + (count - 1).str()
			cycles := if count == 1024 { 1 } else { $if track_heap ? { 1000 } $else { 64 } }
			$if track_heap ? { C.vinix_heap_begin() }
			for _ in 0 .. cycles {
				value := decode_root_recipe(text)!
				assert value.format == 1 && value.entries.len == count && value.entries[count - 1].path == last
				assert value.manifest.architecture == architecture && value.manifest.name == 'Data é🚀'
				assert value.manifest.arguments[0] == '--title="Data"' && value.manifest.files[0].bytes == 1
				close_decoded_root_recipe(value)
			}
			$if track_heap ? {
				kept := C.vinix_heap_end(); assert kept == 0
				println('ROOT RECIPE ' + architecture + ' ' + count.str() + ' selectors: ' + cycles.str() + ' cycles retained ' + kept.str() + ' bytes')
			}
			source := text.clone()
			first := decode_root_recipe(source)!; second := decode_root_recipe(source)!
			assert first == second && first.entries.data != second.entries.data && first.manifest.name.str != second.manifest.name.str
			close_decoded_root_recipe(first); unsafe { source.free() }
			assert second.entries[count - 1].path == last && json2.encode(second) == text
			close_decoded_root_recipe(second)
		}
	}
	println('ROOT RECIPE both architectures, independent owned templates, exact canonical bytes and full 1024 selector bounds PASS')
}

fn test_root_recipe_defaults_and_complete_selector_requirements() {
	if !root_recipe_selected('defaults') { return }
	inputs := ['{"manifest":{},"entries":[{"source":"COPYING","path":"COPYING"}]}',
		'{"entries":[{"path":"COPYING","source":"COPYING"}],"manifest":{"dependencies":[{}],"files":[{}]}}',
		'{"manifest":{"sdk":1,"window_protocol":0,"files":[{"bytes":18446744073709551615}]},"entries":[{"source":"COPYING","path":"COPYING"}]}']
	cycles := $if track_heap ? { 1000 } $else { 64 }
	for text in inputs {
		$if track_heap ? { C.vinix_heap_begin() }
		for _ in 0 .. cycles {
			value := decode_root_recipe(text)!
			assert value.format == 1 && value.manifest.sdk == 1 && value.manifest.window_protocol == 0
			assert !value.manifest.proprietary && !value.manifest.firmware && value.manifest.permissions.len == 0
			if value.manifest.dependencies.len > 0 { assert value.manifest.dependencies[0] == Dependency{} && value.manifest.files[0] == Payload{} }
			if text.contains('184467') { assert value.manifest.files[0].bytes == ~u64(0) }
			close_decoded_root_recipe(value)
		}
		$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0 }
	}
	println('ROOT RECIPE omitted format and nested manifest defaults, full payload integers and reordered fields preserve admission and retire scratch PASS')
}

fn test_root_recipe_partial_schema_and_semantic_refusals_retire_storage() {
	if !root_recipe_selected('refusals') { return }
	text := root_recipe_document(2, 1, 'aarch64')
	invalid_utf8 := [u8(0xc0), 0xaf].bytestr()
	inputs := [text + 'true', text.replace('"entries":', '"unknown":false,"entries":'),
		text.replace('"source":"source/0"', '"source":"source/0","sour\\u0063e":"other"'),
		text.replace('"source":"source/0",', ''), text.replace('"path":"share/0"}', '}'),
		text.replace('"entries":[', '"entries":[null,'), text.replace('"permissions":["files"]', '"permissions":null'),
		text.replace('"entries":[', '"entries":null,"unused":['), text.replace('"source/0"', '"../escape"'),
		text.replace('"path":"share/1"', '"path":"share/0/child"'), text.replace('"path":"share/1"', '"path":"share/0"'),
		text.replace('"format":1', '"format":0'), text.replace('"format":1', '"format":2147483648'),
		text.replace('"format":1', '"format":1.0'), text.replace('"format":1', '"format":01'),
		text.replace('Data é🚀', invalid_utf8), text.replace('Data é🚀', '\\uD800'),
		text.replace('"bytes":1', '"bytes":18446744073709551616'), text.replace('"bytes":1', '"bytes":1e0'),
		'{"manifest":{}}', '{"entries":[]}', '{"manifest":{},"entries":[]}',
		'{"manifest":{},"entries":[{}]}', '{"manifest":null,"entries":[{"source":"a","path":"b"}]}']
	$if track_heap ? { C.vinix_heap_begin() }
	for end in 0 .. text.len { root_recipe_refusal(unsafe { tos(text.str, end) }) }
	$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0 }
	cycles := $if track_heap ? { 1000 } $else { 64 }
	for number, input in inputs {
		assert input != text
		$if track_heap ? { C.vinix_heap_begin() }
		for _ in 0 .. cycles { root_recipe_refusal(input) }
		$if track_heap ? {
			kept := C.vinix_heap_end(); assert kept == 0
			println('ROOT RECIPE refusal ' + number.str() + ': 1000 cycles retained ' + kept.str() + ' bytes')
		}
	}
	println('ROOT RECIPE every truncated prefix and schema/UTF8/number/selector/overlap refusal cycles retire scratch PASS')
}

fn test_root_recipe_metadata_and_nested_bounds() {
	if !root_recipe_selected('bounds') { return }
	text := root_recipe_document(1, 1, 'x86_64')
	for size in [max_metadata - 1, max_metadata]! {
		padding := ' '.repeat(size - text.len); padded := text + padding
		value := decode_root_recipe(padded)!; close_decoded_root_recipe(value)
		unsafe { padded.free(); padding.free() }
	}
	padding := ' '.repeat(max_metadata + 1 - text.len); oversized := text + padding
	root_recipe_refusal(oversized); unsafe { oversized.free(); padding.free() }
	root_recipe_refusal(root_recipe_document(1025, 1, 'x86_64'))
	root_recipe_refusal(root_recipe_document(1, max_files + 1, 'x86_64'))
	for key in ['source', 'path']! {
		prefix := '"' + key + '":"'; suffix := if key == 'source' { 'source/0' } else { 'share/0' }
		valid := text.replace(prefix + suffix + '"', prefix + 'x'.repeat(1024) + '"')
		value := decode_root_recipe(valid)!; close_decoded_root_recipe(value)
		root_recipe_refusal(text.replace(prefix + suffix + '"', prefix + 'x'.repeat(1025) + '"'))
	}
	root_recipe_refusal(text.replace('"arguments":["--title=\\"Data\\""]', '"arguments":[' + '"a",'.repeat(64) + '"a"]'))
	root_recipe_refusal(text.replace('"permissions":["files"]', '"permissions":["audio","display","files","network","process","files"]'))
	root_recipe_refusal(text.replace(json2.encode('Quoted "entries":[] and braces {}'), json2.encode('d'.repeat(4097))))
	println('ROOT RECIPE exact 8 MiB and 1024-byte selectors accepted; metadata, selector and nested manifest overflow refused PASS')
}

fn test_root_recipe_full_payload_bound() {
	if !root_recipe_selected('payloads') { return }
	for architecture in ['aarch64', 'x86_64']! {
		text := root_recipe_document(1, max_files, architecture)
		value := decode_root_recipe(text)!
		assert value.entries.len == 1 && value.manifest.files.len == max_files && value.manifest.files.last().path == 'share/16383'
		close_decoded_root_recipe(value); unsafe { text.free() }
	}
	println('ROOT RECIPE full 16384 payload template inventories preserve fields and retire their single live owner PASS')
}

fn test_root_recipe_overlap_validation_is_allocation_free_and_keeps_path_boundaries() {
	if !root_recipe_selected('overlap') { return }
	for pair in [['a', 'a'], ['a', 'a/b'], ['a/b', 'a'], ['é', 'é/文件'], ['é/文件', 'é'],
		['a', 'ab'], ['a/b', 'a/bc'], ['a/b', 'a/c'], ['a', 'b/a']] {
		entries := [RootEntry{source: 'source/a', path: pair[0]}, RootEntry{source: 'source/b', path: pair[1]}]
		recipe := RootRecipe{ entries: entries }
		refuse := pair[0] == pair[1] || (pair[0] + '/').starts_with(pair[1] + '/') || (pair[1] + '/').starts_with(pair[0] + '/')
		$if track_heap ? { C.vinix_heap_begin() }
		for _ in 0 .. 1000 {
			if _ := validate_root_recipe(recipe) { assert !refuse }
			else { message := err.msg(); assert refuse && message == 'overlapping prepared-root destinations'; unsafe { message.free(); err.free() } }
		}
		$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0 }
	}
	println('ROOT RECIPE 1000 borrowed selector validation cycles preserve equal/parent/child/Unicode/component boundaries and retire scratch PASS')
}

fn test_root_recipe_refusal_preserves_import_source_and_workspace_then_restored_retry_packs() {
	if !root_recipe_selected('pack') { return }
	root := os.temp_dir() + '/vinix-root-recipe-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir_all(root + '/source')!; defer { os.rmdir_all(root) or {} }
	os.write_file(root + '/source/COPYING', 'redistribution terms')!
	valid := '{"manifest":{"id":"data","name":"Data","version":"1.0.0","architecture":"all","kind":"data","license":"MIT","files":[{}]},"entries":[{"source":"COPYING","path":"COPYING"}]}'
	os.mkdir_all(root + '/existing')!; os.write_file(root + '/existing/keep', 'existing workspace')!
	for invalid in [valid[..valid.len - 1], valid.replace('"path":"COPYING"', '"path":"../escape"'), valid.replace('"entries":[', '"entries":[{},')] {
		os.write_file(root + '/recipe.json', invalid)!
		for destination in [root + '/absent', root + '/existing'] {
			if _ := pack_root(root + '/recipe.json', root + '/source', destination) { assert false } else { assert err.msg() != '' }
		}
		assert !os.exists(root + '/absent') && os.ls(root + '/existing')! == ['keep']
		assert os.read_file(root + '/existing/keep')! == 'existing workspace' && os.read_file(root + '/source/COPYING')! == 'redistribution terms'
	}
	os.write_file(root + '/recipe.json', valid)!
	value := pack_root(root + '/recipe.json', root + '/source', root + '/absent')!
	assert value.sdk == 1 && value.files.len == 1 && value.files[0].path == 'COPYING'
	assert os.read_file(root + '/absent/manifests/data-all-1.0.0.json')! == json2.encode(value) + '\n'
	println('ROOT RECIPE invalid import preserves sources and existing/absent workspace; restored template captures payload and unchanged canonical publication PASS')
}

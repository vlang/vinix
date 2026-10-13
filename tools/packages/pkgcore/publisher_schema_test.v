// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os
import time

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
}

fn publisher_recipe_fixture() RootRecipe {
	return RootRecipe{manifest: Package{id: 'notice', version: '1.0.0', architecture: 'all',
		name: 'Redistribution notice', license: 'MIT', kind: 'data',
		dependencies: [Dependency{id: 'notice'}],
		files: [Payload{path: 'COPYING', sha256: 'a'.repeat(64), bytes: 1}]},
		entries: [RootEntry{source: 'COPYING', path: 'COPYING'}]}
}

fn publisher_catalog_fixture() string {
	return json2.encode(CatalogRecipe{format: 1, architectures: ['aarch64', 'x86_64'],
		packages: [CatalogImport{source: 'shared', recipe: publisher_recipe_fixture()}]})
}

fn test_catalog_refuses_coercion_before_it_can_become_a_canonical_lock() {
	valid := publisher_catalog_fixture()
	for invalid in [valid.replace('"proprietary":false', '"proprietary":null'),
		valid.replace('"firmware":false', '"firmware":"false"'),
		valid.replace('"arguments":[]', '"arguments":[1]'),
		valid.replace('"permissions":[]', '"permissions":null'),
		valid.replace('"sdk":1', '"sdk":"1"'),
		valid.replace('"bytes":1', '"bytes":"1"'),
		valid.replace('"executable":false', '"executable":0')] {
		assert invalid != valid
		mut refused := false
		catalog_recipe(invalid) or { refused = true }
		assert refused, 'accepted ambiguous publisher catalog: ' + invalid
	}
}

fn publisher_without(text string, key string) string {
	prefix := '"' + key + '":'
	start := text.index(prefix) or { panic('missing fixture field: ' + key) }
	mut end := start + prefix.len
	mut depth := 0
	mut quoted := false
	for end < text.len {
		byte := text[end]
		if quoted {
			if byte == `\\` { end++ } else if byte == `"` { quoted = false }
		} else if byte == `"` { quoted = true
		} else if byte in [u8(`{`), `[`]! { depth++
		} else if byte in [u8(`}`), `]`]! {
			if depth == 0 { break }
			depth--
		} else if byte == `,` && depth == 0 { break }
		end++
	}
	if text[end] == `,` { return text[..start] + text[end + 1..] }
	assert text[start - 1] == `,`
	return text[..start - 1] + text[end..]
}

fn publisher_catalog_refused(text string) {
	mut refused := false
	catalog_recipe(text) or { refused = true }
	assert refused, text
}

fn test_catalog_requires_every_pinned_record_field_without_defaulting_disclosures() {
	text := publisher_catalog_fixture()
	root := publisher_recipe_fixture()
	item := CatalogImport{source: 'shared', recipe: root}
	for object, fields in {
		text: ['format', 'architectures', 'packages']
		json2.encode(item): ['source', 'recipe']
		json2.encode(root): ['format', 'manifest', 'entries']
		json2.encode(root.manifest): ['id', 'version', 'architecture', 'name', 'description', 'homepage',
			'license', 'proprietary', 'firmware', 'kind', 'runtime', 'entrypoint', 'arguments',
			'permissions', 'associations', 'dependencies', 'files', 'sdk']
		json2.encode(root.manifest.dependencies[0]): ['id', 'minimum', 'before']
		json2.encode(root.manifest.files[0]): ['path', 'sha256', 'bytes', 'executable']
		json2.encode(root.entries[0]): ['source', 'path']
	} {
		assert text.contains(object)
		for key in fields { publisher_catalog_refused(text.replace_once(object, publisher_without(object, key))) }
	}
	for invalid in [text.replace('"arguments":[]', '"arguments":null'),
		text.replace('"associations":[]', '"associations":null'),
		text.replace('"dependencies":[{"id":"notice","minimum":"","before":""}]', '"dependencies":null'),
		text.replace('"source":"shared"', '"source":"shared","sour\\u0063e":"shared"'),
		text.replace('"manifest":', '"future":{},"manifest":'),
		text.replace('"bytes":1', '"bytes":1.5'),
		text.replace('"bytes":1', '"bytes":18446744073709551616'),
		text.replace('"bytes":1', '"bytes":-1')] {
		assert invalid != text
		publisher_catalog_refused(invalid)
	}
	publisher_catalog_refused(' '.repeat(max_metadata + 1))
}

fn test_publisher_recipes_preserve_canonical_bytes_escapes_and_template_defaults() {
	text := publisher_catalog_fixture()
	expected := json2.encode(catalog_recipe(text)!)
	for valid in [text, ' \n' + text + '\t',
		text.replace('"manifest":', '"manif\\u0065st":'),
		text.replace('"firmware":', '"firm\\u0077are":'),
		text.replace('"sdk":1', '"window_protocol":0,"sdk":1')] {
		assert json2.encode(catalog_recipe(valid)!) == expected
	}
	minimal := '{"manifest":{"id":"notice","version":"1.0.0","architecture":"all","name":"Notice","license":"MIT","kind":"data"},"entries":[{"source":"COPYING","path":"COPYING"}]}'
	value := decode_root_recipe(minimal)!
	assert value.format == 1 && value.manifest.sdk == 1 && value.manifest.window_protocol == 0
	assert !value.manifest.proprietary && !value.manifest.firmware && value.manifest.permissions.len == 0
	close_decoded_root_recipe(value)
}

fn test_prepared_root_refuses_ambiguous_templates_before_creating_a_workspace() {
	work := os.real_path(os.temp_dir()) + '/vinix-root-schema-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir_all(work + '/root')!
	defer { os.rmdir_all(work) or {} }
	os.write_file(work + '/root/COPYING', 'redistribution terms')!
	valid := json2.encode(publisher_recipe_fixture())
	for invalid in [valid.replace('"firmware":false', '"firmware":true,"firmware":false'),
		valid.replace('"proprietary":false', '"proprietary":null'),
		valid.replace('"permissions":[]', '"permissions":null'),
		valid.replace('"entries":', '"entriess":'),
		valid.replace('"manifest":', '"manifest":{},"manif\\u0065st":'),
		valid.replace('"source":"COPYING"', '"source":"COPYING","sour\\u0063e":"COPYING"'),
		valid.replace('"path":"COPYING"', '"path":"COPYING","unknown":false'),
		valid.replace('"entries":[', '"entries":[null,'),
		valid.replace('"arguments":[]', '"arguments":[1]'),
		publisher_without(valid, 'manifest'), publisher_without(valid, 'entries')] {
		assert invalid != valid
		os.write_file(work + '/recipe.json', invalid)!
		mut refused := false
		pack_root(work + '/recipe.json', work + '/root', work + '/workspace') or { refused = true }
		assert refused && !os.exists(work + '/workspace'), invalid
		assert os.read_file(work + '/root/COPYING')! == 'redistribution terms'
	}
	os.write_file(work + '/recipe.json', valid)!
	packed := pack_root(work + '/recipe.json', work + '/root', work + '/workspace')!
	assert packed.files.len == 1 && packed.files[0].sha256 == hash_file(work + '/root/COPYING')!
}

fn test_catalog_schema_failure_preserves_existing_workspaces_and_composition_destination() {
	work := os.real_path(os.temp_dir()) + '/vinix-catalog-schema-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir_all(work + '/existing')!
	defer { os.rmdir_all(work) or {} }
	os.write_file(work + '/existing/keep', 'retained publisher workspace')!
	invalid := publisher_catalog_fixture().replace('"permissions":[]', '"permissions":null')
	os.write_file(work + '/catalog.json', invalid)!
	mut packed := false
	pack_catalog(work + '/catalog.json', work + '/missing-roots', work + '/existing') or { packed = true }
	assert packed && os.read_file(work + '/existing/keep')! == 'retained publisher workspace'
	assert os.ls(work + '/existing')! == ['keep']
	mut composed := false
	compose_catalog([CatalogSource{id: 'notices', catalog: work + '/catalog.json'}], work + '/new-lock') or { composed = true }
	assert composed && !os.exists(work + '/new-lock')
	assert os.ls(work)!.all(!it.starts_with('.vinix-'))
}

fn test_publisher_schema_scanners_retire_owned_keys_and_required_field_lists() {
	$if track_heap ? {
		valid := publisher_catalog_fixture()
		inputs := [valid, valid.replace('"permissions":[]', '"permissions":null'),
			valid.replace('"firmware":false,', ''),
			valid.replace('"manifest":', '"unknown":false,"manifest":'),
			valid.replace('"sdk":1', '"sdk":1,"s\\u0064k":1')]
		root := json2.encode(publisher_recipe_fixture())
		roots := [root, root.replace('"permissions":[]', '"permissions":null'),
			publisher_without(root, 'entries'), root.replace('"manifest":', '"unknown":false,"manifest":'),
			root.replace('"sdk":1', '"sdk":1,"s\\u0064k":1')]
		for warmup in 0 .. 2 {
			if warmup == 1 { C.vinix_heap_begin() }
			for _ in 0 .. 1000 {
				for i, input in inputs {
					mut accepted := true
					document_keys_schema(input, catalog_key, catalog_required_fields, catalog_value_type) or {
						accepted = false
						message := err.msg(); unsafe { message.free(); err.free() }
					}
					assert accepted == (i == 0)
				}
				for i, input in roots {
					mut accepted := true
					document_keys_schema(input, root_recipe_field, root_recipe_required_fields, root_recipe_value_type) or {
						accepted = false
						message := err.msg(); unsafe { message.free(); err.free() }
					}
					assert accepted == (i == 0)
				}
			}
		}
		kept := C.vinix_heap_end()
		assert kept == 0, 'publisher recipe scanners retained ${kept} bytes'
		println('Publisher recipe scanners: 1000 valid/null/missing/unknown/duplicate cycles retain zero tracked bytes')
	}
}

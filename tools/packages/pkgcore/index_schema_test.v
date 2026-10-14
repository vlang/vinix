// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import tools.packages.signing as ed25519
import json2
import encoding.hex
import os
import time

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
}

fn schema_fixture() string {
	p := Package{id: 'data', name: 'Data é🚀', description: 'Quotes "firmware":false and brackets [] {}',
		version: '1.0.0', architecture: 'all', kind: 'data', license: 'MIT',
		dependencies: [Dependency{id: 'runtime', minimum: '1.0.0', before: '2.0.0'}],
		files: [Payload{path: 'share/data', sha256: 'a'.repeat(64), bytes: 1}]}
	return json2.encode(Index{repository: 'fixture', sequence: 1, expires: 2000000000, packages: [p]})
}

fn schema_sign(text string, private_key ed25519.PrivateKey) !string {
	bytes := text.bytes()
	defer { unsafe { bytes.free() } }
	signature := ed25519.sign(private_key, bytes)!
	defer { unsafe { signature.free() } }
	return signature.hex()
}

fn test_signed_index_rejects_ambiguous_or_coerced_metadata() {
	public_key, private_key := ed25519.generate_key()!
	repository := Repository{id: 'fixture', public_key: public_key.hex()}
	text := schema_fixture()
	for invalid in [
		text.replace('"arguments":[]', '"arguments":[null]'),
		text.replace('"permissions":[]', '"permissions":null'),
		text.replace('"permissions":[]', '"permissions":["files","files"]'),
		text.replace('"permissions":[]', '"permissions":["audio","display","files","network","process","files"]'),
		text.replace('"associations":[]', '"associations":null'),
		text.replace('"dependencies":[{"id":"runtime","minimum":"1.0.0","before":"2.0.0"}]', '"dependencies":null'),
		text.replace('"sequence":1', '"sequence":1,"sequ\\u0065nce":1'),
		text.replace('"sequence":1', '"sequence":"1"'),
		text.replace('"firmware":false', '"firmware":null'),
		text.replace('"proprietary":false', '"proprietary":true,"proprietary":false'),
		text.replace('"files":', '"future":{},"files":'),
		text.replace('"bytes":1', '"bytes":1,"bytes":1'),
		text.replace('"dependencies":', '"permission":[],"dependencies":'),
		text.replace('"sequence":1', '"sequence":1.5'),
		text.replace('"sequence":1', '"sequence":-1'),
		text.replace('"sequence":1', '"sequence":18446744073709551616'),
		text.replace('"executable":false', '"executable":null'),
		text.replace('"bytes":1', '"bytes":"1"'),
		text.replace('"sdk":1', '"sdk":null'),
		text.replace('"arguments":[]', '"arguments":null'),
		text.replace('"id":"runtime"', '"id":"runtime","i\\u0064":"runtime"'),
		text.replace('"minimum":"1.0.0"', '"minimum":"1.0.0","minimun":"1.0.0"'),
		text.replace('"path":"share/data"', '"path":"share/data","path":"share/data"'),
	] {
		signature := schema_sign(invalid, private_key)!
		mut refused := false
		verify_index(repository, invalid, signature, 1900000000) or {
			refused = true
			message := err.msg()
			unsafe { message.free(); err.free() }
		}
		assert refused, 'accepted signed ambiguous metadata: ' + invalid
	}
}

fn schema_without(text string, key string, value json2.Any) string {
	if value is []json2.Any {
		prefix := '"' + key + '":'
		start := text.index(prefix) or { panic('fixture field not found') }
		mut end := start + prefix.len
		mut depth := 0
		mut quoted := false
		for end < text.len {
			byte := text[end]
			if quoted {
				if byte == `\\` { end++ } else if byte == `"` { quoted = false }
			} else if byte == `"` { quoted = true
			} else if byte in [u8(`[`), `{`]! { depth++
			} else if byte in [u8(`]`), `}`]! { depth--; if depth == 0 { end++; break } }
			end++
		}
		if text[end] == `,` { return text[..start] + text[end + 1..] }
		assert text[start - 1] == `,`
		return text[..start - 1] + text[end..]
	}
	encoded := if value is f64 { i64(value).str() } else { json2.encode(value) }
	field := '"' + key + '":' + encoded
	if text.contains(field + ',') { return text.replace(field + ',', '') }
	assert text.contains(',' + field), field
	return text.replace(',' + field, '')
}

fn schema_refusal(text string, diagnostic string) {
	if value := decode_signed_index('fixture', text, 1900000000) {
		close_decoded_index(value)
		assert false, text
	} else {
		message := err.msg()
		assert message.contains(diagnostic), message
		unsafe { message.free(); err.free() }
	}
}

fn test_signed_index_requires_complete_envelopes_and_each_record_declaration() {
	text := schema_fixture()
	root := json2.decode[map[string]json2.Any](text)!
	for key, value in root {
		schema_refusal(schema_without(text, key, value), 'missing required signed index field: ' + key)
	}
	package := root['packages']!.as_array()[0].as_map()
	for key, value in package {
		schema_refusal(schema_without(text, key, value), 'missing required signed package field: ' + key)
	}
	for key, value in package['dependencies']!.as_array()[0].as_map() {
		schema_refusal(schema_without(text, key, value), 'missing required signed dependency field: ' + key)
	}
	for key, value in package['files']!.as_array()[0].as_map() {
		schema_refusal(schema_without(text, key, value), 'missing required signed payload field: ' + key)
	}
}

fn test_signed_index_preserves_legacy_window_defaults_escapes_and_full_ranges() {
	text := schema_fixture()
	for valid in [text, ' \n' + text + '\t\n',
		text.replace('"sequence":1', '"sequ\\u0065nce":1'),
		text.replace('"sdk":1', '"sdk":1,"window_protocol":0'),
		text.replace('"sequence":1', '"sequence":18446744073709551615')] {
		value := decode_signed_index('fixture', valid, 1900000000)!
		assert value.packages.len == 1 && value.packages[0].window_protocol == 0 && value.packages[0].sdk == 1
		assert value.packages[0].description == 'Quotes "firmware":false and brackets [] {}'
		close_decoded_index(value)
	}
	for architecture in ['aarch64', 'x86_64'] {
		for protocol in [1, 2] {
			app := Package{id: 'app', version: '1.0.0', architecture: architecture, name: 'Application',
				license: 'MIT', kind: 'native', entrypoint: 'bin/app', permissions: ['display'], window_protocol: protocol,
				files: [Payload{path: 'bin/app', sha256: 'a'.repeat(64), bytes: 1, executable: true}]}
			index := Index{repository: 'fixture', sequence: 1, expires: 2000000000, packages: [app]}
			encoded := canonical_index(index)!
			value := decode_signed_index('fixture', encoded, 1900000000)!
			assert canonical_index(value)! == encoded
			close_decoded_index(value)
		}
	}
	empty := decode_signed_index('fixture', json2.encode(Index{repository: 'fixture', sequence: 1, expires: 2000000000}), 1900000000)!
	assert empty.packages.len == 0
	close_decoded_index(empty)
}

fn test_signature_verification_precedes_metadata_admission() {
	public_key, private_key := ed25519.generate_key()!
	repository := Repository{id: 'fixture', public_key: public_key.hex()}
	text := schema_fixture()
	signature := schema_sign(text, private_key)!
	for invalid in ['not JSON', text.replace('"firmware":false', '"firmware":null')] {
		if _ := verify_index(repository, invalid, signature, 1900000000) { assert false } else {
			assert err.msg().contains('signature verification failed'), err.msg()
		}
	}
	for broken in [text.replace('"repository":"fixture"', '"repository":"other"'),
		text.replace('"expires":2000000000', '"expires":1900000000'),
		text.replace('"sequence":1', '"sequence":0')] {
		schema_refusal(broken, 'expired, incompatible or misidentified')
	}
}

fn test_signed_index_shape_checks_retire_owned_key_sets() {
	$if track_heap ? {
		text := schema_fixture()
		inputs := [text, text.replace('"firmware":false', '"firmware":false,"firm\\u0077are":false'),
			text.replace('"firmware":false,', ''), text.replace('"files":', '"unknown":{},"files":')]
		for warmup in 0 .. 2 {
			if warmup == 1 { C.vinix_heap_begin() }
			for _ in 0 .. 1000 {
				for i, input in inputs {
					mut accepted := true
					document_keys_schema(input, index_document_field, index_required_fields, index_value_type) or {
						accepted = false
						message := err.msg()
						unsafe { message.free(); err.free() }
					}
					assert accepted == (i == 0)
				}
			}
		}
		kept := C.vinix_heap_end()
		assert kept == 0, 'signed index key/required-field scanner retained ${kept} bytes'
		println('Signed index shape scanner: 1000 valid/duplicate/missing/unknown cycles retain zero tracked bytes')
	}
}

fn test_publisher_templates_preserve_defaults_but_refuse_ambiguous_declarations() {
	minimal := '{"id":"data","name":"Data","version":"1.0.0","architecture":"all","kind":"data","license":"MIT"}'
	value := decode_manifest(minimal, false)!
	assert value.sdk == 1 && !value.firmware && !value.proprietary && value.permissions.len == 0
	close_decoded_package(value)
	for invalid in [minimal.replace('"license":"MIT"', '"license":"MIT","license":"MIT"'),
		minimal.replace('"kind":"data"', '"kind":"data","permissions":null'),
		minimal.replace('"kind":"data"', '"kind":"data","firmware":null'),
		minimal.replace('"kind":"data"', '"kind":"data","permission":[]')] {
		if p := decode_manifest(invalid, false) { close_decoded_package(p); assert false } else {
			message := err.msg(); unsafe { message.free(); err.free() }
		}
	}
	if p := decode_manifest(minimal, true) { close_decoded_package(p); assert false } else {
		assert err.msg().contains('missing required signed package field')
	}
}

fn test_invalid_signed_refresh_and_enrollment_preserve_catalog_history_and_state() {
	root := os.real_path(os.temp_dir()) + '/vinix-index-schema-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir_all(root + '/etc/vinix-packages')!
	defer { os.rmdir_all(root) or {} }
	os.write_file(root + '/etc/vinix-packages/config.json', json2.encode(Config{architecture: 'aarch64', policy: Policy{offline: true, reserve_bytes: 0}}))!
	os.chmod(root + '/etc/vinix-packages/config.json', 0o644)!
	os.mkdir_all(root + '/source/share')!
	os.write_file(root + '/source/share/data', 'authenticated original payload')!
	manifest := root + '/source.json'
	os.write_file(manifest, '{"id":"data","name":"Data","version":"1.0.0","architecture":"all","kind":"data","license":"MIT"}')!
	workspace := root + '/repository'
	pack(manifest, root + '/source', workspace)!
	public_key := keygen(root + '/seed')!
	expires := time.now().unix() + 3600
	publish(workspace, 'fixture', root + '/seed', 1, expires)!
	repository := Repository{id: 'fixture', public_key: public_key, url: 'file://' + workspace}
	enroll_repository(root, repository, false)!
	service := Service{root: root}
	service.refresh()!
	service.transact('install', ['data'], TransactionOptions{})!
	directory := state_directory(root)
	configuration := os.read_file(root + '/etc/vinix-packages/config.json')!
	catalog := os.read_file(directory + '/catalog.json')!
	history := os.read_file(directory + '/trust-history.json')!
	state := service.state()!
	valid := os.read_file(workspace + '/index.json')!
	seed := hex.decode(os.read_file(root + '/seed')!.trim_space())!
	private_key := ed25519.new_key_from_seed(seed)
	for broken in [valid.replace('"sequence":1', '"sequence":2,"sequence":2'),
		valid.replace('"sequence":1', '"sequence":2').replace('"firmware":false,', ''),
		valid.replace('"sequence":1', '"sequence":2').replace('"permissions":[]', '"permissions":null'),
		valid.replace('"sequence":1', '"sequence":2').replace('"permissions":[]', '"permissions":["files","files"]'),
		valid.replace('"sequence":1', '"sequence":2').replace('"permissions":[]', '"permissions":["audio","display","files","network","process","files"]')] {
		os.write_file(workspace + '/index.json', broken)!
		os.write_file(workspace + '/index.sig', schema_sign(broken, private_key)!)!
		mut refresh_refused := false
		service.refresh() or { refresh_refused = true }
		assert refresh_refused
		mut enrollment_refused := false
		enroll_repository(root, repository, false) or { enrollment_refused = true }
		assert enrollment_refused
		assert os.read_file(directory + '/catalog.json')! == catalog && os.read_file(directory + '/trust-history.json')! == history
		assert os.read_file(root + '/etc/vinix-packages/config.json')! == configuration && service.state()! == state
		assert !os.exists(directory + '/refresh') && !os.exists(directory + '/enrollment')
		mut review := service.review('upgrade', [])!
		assert review.rows.len == 1 && review.rows[0].action == 'keep'
		review.close()
	}
	inventory := workspace + '/manifests/data-all-1.0.0.json'
	packed := os.read_file(inventory)!
	current_source := os.read_file(workspace + '/index.json')!
	for broken in [packed.replace('"firmware":false,', ''),
		packed.replace('"permissions":[]', '"permissions":null'),
		packed.replace('"permissions":[]', '"permissions":["files","files"]'),
		packed.replace('"license":"MIT"', '"license":"MIT","license":"MIT"')] {
		os.write_file(inventory, broken)!
		mut refused := false
		publish(workspace, 'fixture', root + '/seed', 1, expires) or { refused = true }
		assert refused && os.read_file(workspace + '/index.json')! == current_source
	}
	os.write_file(inventory, packed)!
	// Canonical source bytes still publish and reproduce exactly.
	index, text, _, _ := publication(workspace, 'fixture', root + '/seed', 1, expires)!
	assert index.packages.len == 1 && text == valid
}

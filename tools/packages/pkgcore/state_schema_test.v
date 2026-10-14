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

fn stored_schema_fixture(architecture string) State {
	runtime := Package{ id: 'runtime', version: '1.0.0', architecture: architecture, name: 'Runtime', license: 'MIT', kind: 'runtime',
		files: [Payload{ path: 'bin/runner', sha256: 'c'.repeat(64), bytes: 1, executable: true }] }
	app := Package{ id: 'app', version: '1.0.0', architecture: architecture, name: 'Application', license: 'MIT',
		kind: 'linux', runtime: 'runtime', entrypoint: 'bin/runner',
		dependencies: [Dependency{ id: 'runtime', minimum: '', before: '' }],
		files: [Payload{ path: 'app', sha256: 'a'.repeat(64), bytes: 1 }] }
	return State{ generation: 1, architecture: architecture, requested: ['app'],
		packages: [Installed{ package: app, repository: 'publisher', public_key: 'b'.repeat(64), sequence: 1 },
			Installed{ package: runtime, repository: 'publisher', public_key: 'b'.repeat(64), sequence: 1 }] }
}

fn test_stored_state_refuses_missing_disclosures_and_coerced_manifest_values() {
	mut accepted := 0
	for architecture in ['aarch64', 'x86_64'] {
		text := json2.encode(stored_schema_fixture(architecture))
		for label, invalid in {
			'missing firmware': text.replace('"firmware":false,', '')
			'missing proprietary': text.replace('"proprietary":false,', '')
			'null permissions': text.replace('"permissions":[]', '"permissions":null')
			'missing sdk': text.replace(',"sdk":1', '')
		} {
			assert invalid != text
			mut admitted := false
			if state := decode_persistent_state(invalid, architecture) { close_decoded_state(state); admitted = true; accepted++ }
			println('Stored state probe: ' + architecture + ' ' + label + ' accepted=' + admitted.str())
		}
	}
	assert accepted == 0
}

fn stored_without(text string, key string) string {
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

fn stored_refused(text string, architecture string) {
	if state := decode_persistent_state(text, architecture) { close_decoded_state(state); assert false, text }
}

fn test_stored_state_requires_complete_nested_records_and_explicit_value_kinds() {
	for architecture in ['aarch64', 'x86_64'] {
		original := stored_schema_fixture(architecture)
		text := json2.encode(original)
		app := original.packages[0]
		for object, fields in {
			text: ['format', 'generation', 'previous', 'architecture', 'requested', 'packages']
			json2.encode(app): ['package', 'repository', 'public_key', 'sequence']
			json2.encode(app.package): ['id', 'version', 'architecture', 'name', 'description', 'homepage', 'license',
				'proprietary', 'firmware', 'kind', 'runtime', 'entrypoint', 'arguments', 'permissions', 'associations', 'dependencies', 'files', 'sdk']
			json2.encode(app.package.dependencies[0]): ['id', 'minimum', 'before']
			json2.encode(app.package.files[0]): ['path', 'sha256', 'bytes', 'executable']
		} {
			assert text.contains(object)
			for key in fields { stored_refused(text.replace_once(object, stored_without(object, key)), architecture) }
		}
		for invalid in ['null', '[]', '{}', ' '.repeat(max_metadata + 1),
			text.replace('"requested":["app"]', '"requested":null'),
			text.replace('"packages":[', '"packages":[null,'),
			text.replace('"package":{', '"package":null,"unused":{'),
			text.replace('"firmware":false', '"firmware":null'),
			text.replace('"proprietary":false', '"proprietary":"false"'),
			text.replace('"sdk":1', '"sdk":"1"'),
			text.replace('"sdk":1', '"window_protocol":null,"sdk":1'),
			text.replace('"arguments":[]', '"arguments":[1]'),
			text.replace('"associations":[]', '"associations":null'),
			text.replace('"dependencies":[', '"dependencies":[null,'),
			text.replace('"minimum":""', '"minimum":null'),
			text.replace('"executable":false', '"executable":null'),
			text.replace('"bytes":1', '"bytes":1.5'),
			text.replace('"bytes":1', '"bytes":18446744073709551616'),
			text.replace('"sequence":1', '"sequence":"1"'),
			text.replace('"previous":0', '"previous":null'),
			text.replace('"firmware":false', '"firmware":false,"firm\\u0077are":false'),
			text.replace('"package":{', '"package":{"extra":false,'),
			text.replace('"name":"Application"', '"name":"\\ud800"')] {
			assert invalid != text
			stored_refused(invalid, architecture)
		}
		for valid in [text, ' \n' + text + '\t', text.replace('"firmware":', '"firm\\u0077are":'),
			text.replace('"sdk":1', '"window_protocol":0,"sdk":1')] {
			state := decode_persistent_state(valid, architecture)!
			assert state == original && json2.encode(state) == text
			close_decoded_state(state)
		}
		maximum := State{ ...original, generation: ~u64(0), previous: ~u64(0) - 1,
			packages: original.packages.map(Installed{ ...it, sequence: ~u64(0) }) }
		state := decode_persistent_state(json2.encode(maximum), architecture)!
		assert state == maximum
		close_decoded_state(state)
	}
	println('Stored state: complete nested declarations, explicit types, ambiguity refusal and legacy window compatibility passed on both architectures')
}

fn stored_inventory(path string) ![]string {
	mut result := []string{}
	mut names := os.ls(path)!; names.sort()
	for name in names {
		child := path + '/' + name
		if os.is_link(child) { result << child + ' -> ' + os.readlink(child)!
		} else if os.is_dir(child) { result << child + '/'; result << stored_inventory(child)!
		} else { result << child + ' ' + hash_file(child)! }
	}
	return result
}

fn test_malformed_stored_declarations_preserve_current_previous_cache_and_recovery_before_retry() {
	work := os.real_path(os.temp_dir()) + '/vinix-stored-schema-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir_all(work + '/root/etc/vinix-packages')!
	defer { os.rmdir_all(work) or {} }
	os.mkdir_all(work + '/source/bin')!
	os.write_file(work + '/source/bin/app', 'signed payload')!
	os.chmod(work + '/source/bin/app', 0o755)!
	key := keygen(work + '/seed')!
	config := Config{ architecture: 'aarch64', repositories: [Repository{ id: 'publisher', public_key: key,
		url: 'file://' + work + '/repository' }], policy: Policy{ offline: true, reserve_bytes: 0 } }
	os.write_file(work + '/root/etc/vinix-packages/config.json', json2.encode(config))!
	service := Service{ root: work + '/root' }
	for i, version in ['1.0.0', '2.0.0'] {
		os.write_file(work + '/manifest.json', json2.encode(Package{ id: 'app', version: version, architecture: 'aarch64',
			name: 'Application', license: 'MIT', kind: 'native', entrypoint: 'bin/app' }))!
		pack(work + '/manifest.json', work + '/source', work + '/repository')!
		publish(work + '/repository', 'publisher', work + '/seed', u64(i + 1), time.now().unix() + 3600)!
		service.refresh()!
		service.transact(if i == 0 { 'install' } else { 'upgrade' }, if i == 0 { ['app'] } else { []string{} }, TransactionOptions{})!
	}
	directory := state_directory(service.root)
	os.mkdir(directory + '/generations/3')!
	os.write_file(directory + '/generations/3/lease', '')!
	os.mkdir(directory + '/generations/.stage-sentinel')!
	os.write_file(directory + '/objects/' + 'd'.repeat(64) + '.part', 'interrupted download')!
	mut review := service.review('remove', ['app'])!
	defer { review.close() }
	for generation in ['2', '1'] {
		path := directory + '/generations/' + generation + '/state.json'
		original := os.read_file(path)!
		for invalid in [original.replace('"firmware":false,', ''), original.replace('"permissions":[]', '"permissions":null'),
			original.replace('"sdk":1', '"sdk":"1"')] {
			assert invalid != original
			os.write_file(path, invalid)!
			before := stored_inventory(work + '/root')!
			mut refusals := 0
			service.rollback('') or { refusals += 1 }
			service.collect() or { refusals += 1 }
			service.review('rollback', []) or { refusals += 1 }
			if generation == '2' {
				service.state() or { refusals += 1 }
				service.verify() or { refusals += 1 }
				service.plan('remove', ['app']) or { refusals += 1 }
				service.review('remove', ['app']) or { refusals += 1 }
				service.transact('remove', ['app'], TransactionOptions{ expected_review: review.fingerprint }) or { refusals += 1 }
				assert refusals == 8
				if os.geteuid() != 0 {
					service.prepare_launch('app') or { refusals += 1 }
					assert refusals == 9
				}
			} else { assert refusals == 3 }
			assert stored_inventory(work + '/root')! == before
		}
		os.write_file(path, original)!
	}
	assert service.verify()!.generation == 2
	service.transact('remove', ['app'], TransactionOptions{ expected_review: review.fingerprint })!
	assert service.state()!.packages.len == 0
	assert service.rollback('')!.packages.len == 1
	service.collect()!
	assert !os.exists(directory + '/generations/3') && !os.exists(directory + '/generations/.stage-sentinel')
	println('Stored state: malformed active/previous metadata preserves activation, trust, payloads, cache and recovery; restoration permits reviewed removal, rollback and collection')
}

fn test_stored_state_schema_scanning_retires_owned_keys() {
	$if track_heap ? {
		valid := json2.encode(stored_schema_fixture('aarch64'))
		inputs := [valid, valid.replace('"firmware":false,', ''), valid.replace('"permissions":[]', '"permissions":null'),
			valid.replace('"sdk":1', '"sdk":1,"s\\u0064k":1'), valid.replace('"package":{', '"package":{"unknown":0,'),
			valid.replace('"previous":0,', ''), valid.replace(',"sequence":1', '')]
		for warmup in 0 .. 2 {
			if warmup == 1 { C.vinix_heap_begin() }
			for _ in 0 .. 1000 {
				for i, input in inputs {
					mut accepted := true
					document_keys_schema(input, state_document_field, state_required_fields, state_value_type) or {
						accepted = false
						message := err.msg(); unsafe { message.free(); err.free() }
					}
					assert accepted == (i == 0)
				}
			}
			if warmup == 1 { kept := C.vinix_heap_end(); println('Stored state scanner: retained ' + kept.str() + ' tracked bytes in 1000 cycles'); assert kept == 0 }
		}
	}
}

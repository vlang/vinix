// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
}

fn stored_decode_fixture() (string, string) {
	config := Config{ architecture: 'aarch64', repositories: [Repository{ id: 'publisher', url: 'file:///srv/packages', public_key: 'b'.repeat(64) }],
		policy: Policy{ offline: true, allowed: ['app'], licenses: ['MIT'], permissions: ['files'], reserve_bytes: 0 } }
	p := Package{ id: 'app', name: 'Application', architecture: 'all', version: '1.0.0', kind: 'data', license: 'MIT', permissions: ['files'],
		files: [Payload{ path: 'data/file', sha256: 'a'.repeat(64), bytes: 7 }] }
	state := State{ architecture: 'aarch64', generation: 7, requested: ['app'], packages: [Installed{ package: p, repository: 'publisher', public_key: 'b'.repeat(64), sequence: 7 }] }
	return json2.encode(config), encode_generation_state(state) or { panic(err) }
}

fn test_stored_decoders_retire_complete_owned_values() {
	$if track_heap ? {
		config_text, state_text := stored_decode_fixture()
		C.vinix_heap_begin()
		for _ in 0 .. 1000 { config := decode_configuration(config_text)!; close_decoded_configuration(config) }
		config_bytes := C.vinix_heap_end()
		C.vinix_heap_begin()
		for _ in 0 .. 1000 { state := decode_persistent_state(state_text, 'aarch64')!; close_decoded_state(state) }
		state_bytes := C.vinix_heap_end()
		println('Stored decode: 1000 configuration decode/close cycles retained ${config_bytes} bytes; 1000 persistent-state cycles retained ${state_bytes} bytes')
		assert config_bytes == 0 && state_bytes == 0
	}
}

fn stored_config_failure(text string) {
	if value := decode_configuration(text) { close_decoded_configuration(value); assert false, 'accepted malformed configuration' } else {
		message := err.msg(); assert message != ''; unsafe { message.free(); err.free() }
	}
}

fn stored_state_failure(text string) {
	if value := decode_persistent_state(text, 'aarch64') { close_decoded_state(value); assert false, 'accepted malformed state' } else {
		message := err.msg(); assert message != ''; unsafe { message.free(); err.free() }
	}
}

fn test_stored_decoders_retire_partial_values_for_every_truncated_prefix_and_late_refusals() {
	config_text, state_text := stored_decode_fixture()
	bad_configs := [config_text + '{}', config_text.replace('"url":', '"url":null,"unused":'),
		config_text.replace('"allowed":["app"]', '"allowed":["app",null]'),
		config_text.replace('"permissions":["files"]', '"permissions":["files","files"]'),
		config_text.replace('"public_key":', '"public_key":"bad","public_\\u006bey":'),
		config_text.replace('"reserve_bytes":0', '"reserve_bytes":00'),
		config_text.replace('"reserve_bytes":0', '"reserve_bytes":1e0'),
		config_text.replace('"architecture":"aarch64"', '"architecture":"\\ud800"')]
	bad_states := [state_text + '{}', state_text.replace('"path":"data/file"', '"path":"../escape"'),
		state_text.replace('"sha256":', '"sha256":false,"unused":'),
		state_text.replace('"packages":[', '"packages":[null,'),
		state_text.replace('"generation":7', '"generation":18446744073709551616'),
		state_text.replace('"previous":0', '"previous":-0'),
		state_text.replace('"bytes":7', '"bytes":7.0'),
		state_text.replace('"requested":["app"]', '"requested":["absent"]'),
		state_text.replace('"firmware":false', '"firmware":false,"firm\\u0077are":false')]
	$if track_heap ? { C.vinix_heap_begin() }
	for end in 0 .. config_text.len { stored_config_failure(unsafe { tos(config_text.str, end) }) }
	for end in 0 .. state_text.len { stored_state_failure(unsafe { tos(state_text.str, end) }) }
	for _ in 0 .. 1000 {
		for text in bad_configs { stored_config_failure(text) }
		for text in bad_states { stored_state_failure(text) }
	}
	$if track_heap ? { kept := C.vinix_heap_end(); println('Stored decode: all truncated prefixes and 1000 late-refusal cycles retained ${kept} bytes'); assert kept == 0 }
	println('Stored decode: partial nested cleanup, escaped duplicate keys, canonical integers and late semantic refusal PASS')
}

fn test_stored_decoders_preserve_owned_unicode_legacy_defaults_and_full_counters() {
	config_text, state_text := stored_decode_fixture()
	for architecture in ['aarch64', 'x86_64']! {
		for text in ['{"architecture":"${architecture}"}', '{"architecture":"${architecture}","policy":{}}'] {
			config := decode_configuration(text)!
			assert config.policy == Policy{} && config.repositories.len == 0 && config.format == 1
			close_decoded_configuration(config)
		}
		input := state_text.replace('aarch64', architecture).replace('"name":"Application"', '"na\\u006de":"\\u00e9 \\ud83c\\udfb5"')
		state := decode_persistent_state(input, architecture)!
		assert state.packages[0].package.name == 'é 🎵' && state.packages[0].package.window_protocol == 0
		assert encode_generation_state(state)!.contains('"name":"é 🎵"')
		close_decoded_state(state)
	}
	independent := config_text.clone()
	config := decode_configuration(independent)!
	unsafe { independent.free() }
	assert config.repositories[0].id == 'publisher' && config.policy.allowed == ['app']
	close_decoded_configuration(config)
	state_input := state_text.clone()
	owned_state := decode_persistent_state(state_input, 'aarch64')!
	unsafe { state_input.free() }
	assert owned_state.packages[0].package.files[0].path == 'data/file' && owned_state.requested == ['app']
	close_decoded_state(owned_state)
	input := state_text.replace('"generation":7', '"generation":18446744073709551615').replace('"previous":0', '"previous":18446744073709551614').replace('"sequence":7', '"sequence":18446744073709551615')
	state := decode_persistent_state(input, 'aarch64')!
	assert state.generation == ~u64(0) && state.previous == ~u64(0) - 1 && state.packages[0].sequence == ~u64(0)
	close_decoded_state(state)
	println('Stored decode: both architectures, owned Unicode/escaped keys, legacy policy/window defaults and full u64 counters PASS')
}

fn test_stored_decoders_bound_growth_and_keep_nested_declared_values() {
	config_text, state_text := stored_decode_fixture()
	mut repositories := []Repository{cap: 4096}
	for index in 0 .. 4096 { repositories << Repository{ id: 'repo-' + index.str(), url: 'file:///srv/packages', public_key: 'b'.repeat(64) } }
	large_config := json2.encode(Config{ architecture: 'aarch64', repositories: repositories })
	config := decode_configuration(large_config)!
	assert config.repositories.len == 4096 && config.repositories[4095].id == 'repo-4095'
	close_decoded_configuration(config)
	too_many := large_config.replace_once('"repositories":[', '"repositories":[' + json2.encode(repositories[0]) + ',')
	stored_config_failure(too_many)
	base := decode_persistent_state(state_text, 'aarch64')!
	defer { close_decoded_state(base) }
	mut packages := []Installed{cap: 4096}; mut roots := []string{cap: 4096}
	for index in 0 .. 4096 {
		id := 'app-' + index.str(); roots << id
		packages << Installed{ ...base.packages[0], package: Package{ ...base.packages[0].package, id: id } }
	}
	encoded := encode_generation_state(State{ ...base, requested: roots, packages: packages })!
	state := decode_persistent_state(encoded, 'aarch64')!
	assert state.requested.len == 4096 && state.packages.len == 4096 && state.packages[4095].package.id == 'app-4095'
	close_decoded_state(state)
	stored_state_failure(encoded.replace_once('"packages":[', '"packages":[' + json2.encode(packages[0]) + ','))
	// A self dependency is a valid closed cycle. This also exercises bounded
	// nested requirements and payload-array growth without expanding the graph.
	mut files := []Payload{cap: 32}
	for index in 0 .. 32 { files << Payload{ path: 'data/' + index.str(), sha256: 'a'.repeat(64), bytes: 7 } }
	nested := State{ ...base, packages: [Installed{ ...base.packages[0], package: Package{ ...base.packages[0].package,
		dependencies: [Dependency{ id: 'app', minimum: '1.0.0', before: '2.0.0' }], files: files, arguments: ['--literal', 'a "quoted" value'] } }] }
	nested_text := encode_generation_state(nested)!
	$if track_heap ? { C.vinix_heap_begin() }
	for _ in 0 .. 1000 {
		value := decode_persistent_state(nested_text, 'aarch64')!
		assert value.packages[0].package.files.len == 32 && value.packages[0].package.dependencies[0].before == '2.0.0'
		close_decoded_state(value)
	}
	$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0 }
	assert config_text.contains('publisher')
	println('Stored decode: 4096-repository/package limits, excess refusal, nested dependency/argument declarations and growing payload arrays PASS')
}

fn test_stored_decoders_enforce_inclusive_metadata_and_payload_limits() {
	config_text, state_text := stored_decode_fixture()
	full := config_text + ' '.repeat(max_metadata - config_text.len)
	config := decode_configuration(full)!
	close_decoded_configuration(config)
	stored_config_failure(full + ' ')
	base := decode_persistent_state(state_text, 'aarch64')!
	defer { close_decoded_state(base) }
	mut files := []Payload{cap: max_files}
	for index in 0 .. max_files { files << Payload{ path: 'data/' + index.str(), sha256: 'a'.repeat(64), bytes: 1 } }
	large := State{ ...base, packages: [Installed{ ...base.packages[0], package: Package{ ...base.packages[0].package, files: files } }] }
	text := encode_generation_state(large)!
	value := decode_persistent_state(text, 'aarch64')!
	assert value.packages[0].package.files.len == max_files
	close_decoded_state(value)
	stored_state_failure(text.replace_once('"files":[', '"files":[' + json2.encode(files[0]) + ','))
	println('Stored decode: inclusive 8-MiB metadata and 16384-payload bounds with overflow refusal PASS')
}

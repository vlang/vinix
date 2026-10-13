// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
}

fn configuration_fixture() string {
	return json2.encode(Config{architecture: 'aarch64', launch_user: 'alex',
		repositories: [Repository{id: 'first', url: 'https://example.invalid/first', public_key: 'a'.repeat(64)},
			Repository{id: 'second', url: 'file:///media/repository', public_key: 'b'.repeat(64)}],
		policy: Policy{offline: true, allowed: ['app'], permissions: ['files'],
			pins: [Dependency{id: 'app', minimum: '1.0.0', before: '2.0.0'}, Dependency{id: 'runtime'}],
			licenses: ['Vendor-EULA'], allow_firmware: true, reserve_bytes: 1234}})
}

fn configuration_refused(text string) {
	mut refused := false
	decode_configuration(text) or { refused = true }
	assert refused, 'accepted ambiguous package configuration: ' + text
}

fn test_configuration_preserves_explicit_policy_values_and_legacy_defaults() {
	text := configuration_fixture()
	for architecture in ['aarch64', 'x86_64'] {
		for input in [text.replace('aarch64', architecture),
			' \n' + text.replace('aarch64', architecture) + '\t',
			text.replace('aarch64', architecture).replace('"policy":', '"pol\\u0069cy":')
				.replace('"offline":', '"off\\u006cine":').replace('"public_key":', '"public_\\u006bey":')] {
			config := decode_configuration(input)!
			assert config.architecture == architecture && config.format == 1 && config.launch_user == 'alex'
			assert config.repositories.len == 2 && config.repositories[1].url == 'file:///media/repository'
			assert config.policy.offline && config.policy.allow_firmware && config.policy.reserve_bytes == 1234
			assert config.policy.permissions == ['files'] && config.policy.allowed == ['app']
			assert config.policy.pins.len == 2 && config.policy.licenses == ['Vendor-EULA']
			close_decoded_configuration(config)
		}
		for input in ['{"architecture":"' + architecture + '"}',
			'{"architecture":"' + architecture + '","policy":{}}'] {
			config := decode_configuration(input)!
			assert config.format == 1 && config.architecture == architecture && config.launch_user == ''
			assert config.repositories.len == 0 && config.policy == Policy{}
			close_decoded_configuration(config)
		}
	}
	config := decode_configuration('{"architecture":"aarch64","policy":{"permissions":[],"reserve_bytes":0,"pins":[{"id":"app"}]}}')!
	assert config.policy.permissions.len == 0 && config.policy.reserve_bytes == 0
	assert config.policy.pins == [Dependency{id: 'app'}] && !config.policy.offline
	close_decoded_configuration(config)
}

fn test_configuration_rejects_unknown_and_duplicate_fields_at_each_level() {
	text := configuration_fixture()
	for invalid in [text.replace('"policy":', '"polciy":'),
		text.replace('"permissions":', '"permissons":'),
		text.replace('"allowed":', '"allowd":'),
		text.replace('"public_key":', '"publickey":'),
		text.replace('"minimum":', '"minimun":'),
		text.replace('"architecture":', '"format":1,"architecture":'),
		text.replace('"policy":', '"policy":{},"pol\\u0069cy":'),
		text.replace('"offline":true', '"offline":false,"off\\u006cine":true'),
		text.replace('"url":', '"url":"https://example.invalid","u\\u0072l":'),
		text.replace('"before":', '"before":"","befo\\u0072e":'),
		text.replace('"launch_user":', '"future":{},"launch_user":')] {
		assert invalid != text
		configuration_refused(invalid)
	}
}

fn test_configuration_rejects_null_and_coerced_values_without_defaulting_policy() {
	text := configuration_fixture()
	for invalid in ['{"architecture":"aarch64","policy":null}',
		'{"architecture":"aarch64","repositories":null}',
		text.replace('"allowed":["app"]', '"allowed":null'),
		text.replace('"permissions":["files"]', '"permissions":null'),
		text.replace('"licenses":["Vendor-EULA"]', '"licenses":null'),
		'{"architecture":"aarch64","policy":{"pins":null}}',
		text.replace('"offline":true', '"offline":null'),
		text.replace('"allow_firmware":true', '"allow_firmware":"true"'),
		text.replace('"allowed":["app"]', '"allowed":[1]'),
		text.replace('"permissions":["files"]', '"permissions":[false]'),
		text.replace('"launch_user":"alex"', '"launch_user":null'),
		text.replace('"format":1', '"format":"1"'),
		text.replace('"reserve_bytes":1234', '"reserve_bytes":"1234"'),
		text.replace('"reserve_bytes":1234', '"reserve_bytes":1.5'),
		text.replace('"reserve_bytes":1234', '"reserve_bytes":-1'),
		text.replace('"reserve_bytes":1234', '"reserve_bytes":18446744073709551616'),
		text.replace('"pins":[', '"pins":[null,'),
		text.replace('"repositories":[', '"repositories":[null,'),
		text.replace('"minimum":"1.0.0"', '"minimum":null')] {
		assert invalid != text
		configuration_refused(invalid)
	}
	for invalid in ['{}', 'null', '[]', '{broken', ' '.repeat(max_metadata + 1),
		text.replace('"architecture":"aarch64"', '"architecture":"arm64"'),
		text.replace('"public_key":"' + 'a'.repeat(64) + '"', '"public_key":"invalid"'),
		text.replace('"permissions":["files"]', '"permissions":["unknown"]'),
		text.replace('"launch_user":"alex"', '"launch_user":"root"')] {
		configuration_refused(invalid)
	}
}

fn test_configuration_schema_scanning_retires_owned_keys() {
	$if track_heap ? {
		text := configuration_fixture()
		inputs := [text, text.replace('"permissions":["files"]', '"permissions":null'),
			text.replace('"policy":', '"polciy":'),
			text.replace('"offline":true', '"offline":true,"off\\u006cine":false')]
		for warmup in 0 .. 2 {
			if warmup == 1 { C.vinix_heap_begin() }
			for _ in 0 .. 1000 {
				for i, input in inputs {
					mut accepted := true
					document_keys_schema(input, configuration_field, document_optional_fields, configuration_value_type) or {
						accepted = false
						message := err.msg(); unsafe { message.free(); err.free() }
					}
					assert accepted == (i == 0)
				}
			}
			if warmup == 1 {
				kept := C.vinix_heap_end()
				println('Configuration schema: retained ' + kept.str() + ' tracked bytes in 1000 cycles')
				assert kept == 0
			}
		}
	}
}

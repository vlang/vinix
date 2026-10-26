// SPDX-License-Identifier: GPL-2.0-or-later
module pkgprotocol

import json2

struct RegistrationFixturePackage { package RegisteredPackage }
struct RegistrationFixture {
	format int = 1
	generation u64 = 7
	architecture string = 'aarch64'
	packages []RegistrationFixturePackage
}

fn registration_fixture() string {
	return json2.encode(RegistrationFixture{packages: [RegistrationFixturePackage{package: RegisteredPackage{
		id: 'editor', name: 'Editor é🚀', description: 'Write text', architecture: 'aarch64', kind: 'native',
		permissions: ['files', 'display'], associations: ['text/plain'] }}]})
}

fn registration_refused(text string) bool {
	mut snapshot := decode_registration(text) or {
		message := err.msg(); unsafe { message.free(); err.free() }
		return true
	}
	snapshot.close()
	return false
}

fn test_registration_preserves_both_targets_unicode_empty_arrays_and_service_fields() {
	text := registration_fixture()
	for architecture in ['aarch64', 'x86_64'] {
		for input in [text.replace('aarch64', architecture),
			text.replace('aarch64', architecture).replace('Editor é🚀', 'Editor \\u00e9\\ud83d\\ude80')
				.replace('"packages":', '"packa\\u0067es":').replace('"package":', '"packa\\u0067e":')] {
			mut snapshot := decode_registration(input)!
			assert snapshot.format == 1 && snapshot.generation == 7 && snapshot.architecture == architecture
			assert snapshot.packages.len == 1 && snapshot.packages[0].name == 'Editor é🚀'
			assert snapshot.packages[0].permissions == ['files', 'display'] && snapshot.packages[0].associations == ['text/plain']
			snapshot.close(); assert snapshot.packages.len == 0 && snapshot.generation == 0
		}
	}
	mut empty := decode_registration('{"format":1,"generation":1,"architecture":"x86_64","packages":[] }')!
	assert empty.packages.len == 0; empty.close()
	// The projection validates syntax for the service's other state fields,
	// without copying inventories, dependencies or provenance into the desktop.
	extra := '"extension":{"text":"é\\ud83d\\ude80","array":[null,true,false,-1.25e+2,{"later":[]}],"large":1e9999},'
	mut complete := decode_registration(' \n' + text.replace('"format":1,', '"format":1,"previous":0,"requested":["editor"],' + extra)
		.replace('"package":', '"repository":"fixture","public_key":"presentation only","sequence":1,' + extra + '"package":')
		.replace('"id":"editor",', '"id":"editor","version":"1.0.0","files":[{"path":"bin/editor","bytes":123,"executable":true}],'
			+ '"dependencies":[],"sdk":1,' + extra) + '\t')!
	assert complete.packages[0].id == 'editor'; complete.close()
}

fn test_registration_requires_all_presentation_fields_and_refuses_null_coercion_and_duplicates() {
	text := registration_fixture()
	for field in ['"format":1,', '"generation":7,', '"architecture":"aarch64",', '"id":"editor",',
		'"name":"Editor é🚀",', '"description":"Write text",', '"kind":"native",',
		'"permissions":["files","display"],', ',"associations":["text/plain"]'] {
		assert text.contains(field)
		assert registration_refused(text.replace(field, ''))
	}
	for invalid in [text.replace('"packages":', '"other":'), text.replace('"package":', '"other":'),
		text.replace('"packages":[', '"packages":null,"other":['), text.replace('"package":{', '"package":null,"other":{'),
		text.replace('"permissions":["files","display"]', '"permissions":null'),
		text.replace('"associations":["text/plain"]', '"associations":null'),
		text.replace('"description":"Write text"', '"description":null'),
		text.replace('"format":1', '"format":true'), text.replace('"generation":7', '"generation":"7"'),
		text.replace('"permissions":["files","display"]', '"permissions":[false]'),
		text.replace('"generation":7', '"generation":7,"genera\\u0074ion":7'),
		text.replace('"name":"Editor é🚀"', '"name":"Editor é🚀","na\\u006de":"Other"'),
		text.replace('"package":{', '"package":{},"packa\\u0067e":{'),
		text.replace('Editor é🚀', '\\ud800'), text.replace('Editor é🚀', '\\udc00'), text.replace('Editor é🚀', '\xff'),
		text + ' false', text[..text.len - 1], text.replace('"format":1,', '"format":1,,') ] {
		assert registration_refused(invalid), invalid
	}
}

fn test_registration_refuses_bad_identities_permissions_mime_targets_and_integer_aliases() {
	text := registration_fixture()
	for value in ['0', '-1', '07', '7.0', '7e0', '18446744073709551616'] {
		assert registration_refused(text.replace('"generation":7', '"generation":' + value))
	}
	for invalid in [text.replace('"format":1', '"format":2'), text.replace('"id":"editor"', '"id":"../editor"'),
		text.replace('Editor é🚀', ''), text.replace('Editor é🚀', 'Line\\nBreak'),
		text.replace('"kind":"native"', '"kind":"unknown"'), text.replace('aarch64', 'arm64'),
		text.replace('"kind":"native"', '"kind":"data"').replace('"architecture":"aarch64","kind":', '"architecture":"unknown","kind":'),
		text.replace('"permissions":["files","display"]', '"permissions":["root"]'),
		text.replace('"permissions":["files","display"]', '"permissions":["files","files"]'),
		text.replace('"associations":["text/plain"]', '"associations":["text/plain;application/x-other"]'),
		text.replace('"associations":["text/plain"]', '"associations":["text=plain/other"]'),
		text.replace('"associations":["text/plain"]', '"associations":["plain"]')] {
		assert registration_refused(invalid), invalid
	}
	mut maximum := decode_registration(text.replace('"generation":7', '"generation":18446744073709551615'))!
	assert maximum.generation == ~u64(0); maximum.close()
	mut shared := decode_registration(text.replace('"architecture":"aarch64","kind":', '"architecture":"all","kind":').replace('"kind":"native"', '"kind":"data"'))!
	assert shared.packages[0].architecture == 'all'; shared.close()
	assert registration_refused(text.replace('"architecture":"aarch64","kind":', '"architecture":"all","kind":'))
}

fn test_registration_syntax_checks_unused_fields_with_bounded_nesting() {
	text := registration_fixture()
	for value in ['n ull', '01', '-', '1.', '1e+', '[true,]', '{"later":}', '{"later":false,}', '"\\ud800"', '{"a" true}'] {
		assert registration_refused(text.replace('"format":1,', '"format":1,"extra":' + value + ','))
	}
	assert registration_refused(text.replace('"format":1,', '"format":1,"extra":' + '['.repeat(34) + 'null' + ']'.repeat(34) + ','))
	mut bounded := decode_registration(text.replace('"format":1,', '"format":1,"extra":' + '['.repeat(32) + 'null' + ']'.repeat(32) + ','))!
	bounded.close()
}

fn test_registration_applies_bare_mime_rules_after_json_decoding() {
	text := registration_fixture()
	for value in ['/', 'text/', '/plain', 'text/plain/extra', 'text/ plain', 'text/plain ',
		'text/pl\\ain', 'text/é', 'text/*', 'text/.plain', 'text/plain;charset=utf-8'] {
		encoded := json2.encode(value)
		input := text.replace('"text/plain"', encoded)
		if !registration_refused(input) { panic('registration admitted malformed MIME association') }
	}
	for value in ['application/vnd.example.editor+json', 'x-scheme-handler/https', 'Text/Plain'] {
		input := text.replace('"text/plain"', json2.encode(value))
		mut snapshot := decode_registration(input)!
		if snapshot.packages[0].associations != [value] { panic('registration changed literal MIME identity') }
		snapshot.close()
	}
}

fn test_registration_bounds_packages_fields_collections_and_reply_size() {
	text := registration_fixture()
	for invalid in [text.replace('Write text', 'x'.repeat(4097)), text.replace('Editor é🚀', 'x'.repeat(257)),
		text.replace('"permissions":["files","display"]', '"permissions":["files","network","audio","display","process","files"]'),
		text.replace('"associations":["text/plain"]', '"associations":["text/plain"' + ',"text/plain"'.repeat(128) + ']'),
		text + ' '.repeat(8 * 1024 * 1024)] { assert registration_refused(invalid) }
	mut rows := []RegistrationFixturePackage{cap: 4097}
	for index in 0 .. 4097 { rows << RegistrationFixturePackage{package: RegisteredPackage{ id: 'app-' + index.str(),
		name: 'Application', description: '', architecture: 'x86_64', kind: 'native' }} }
	assert registration_refused(json2.encode(RegistrationFixture{architecture: 'x86_64', packages: rows}))
	rows.delete_last()
	mut bounded := decode_registration(json2.encode(RegistrationFixture{architecture: 'x86_64', packages: rows}))!
	assert bounded.packages.len == 4096; bounded.close()
	rows[1] = rows[0]
	assert registration_refused(json2.encode(RegistrationFixture{architecture: 'x86_64', packages: rows}))
}

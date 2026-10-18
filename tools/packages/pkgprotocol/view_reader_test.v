// SPDX-License-Identifier: GPL-2.0-or-later
module pkgprotocol

import json2

fn fixture_software_row() SoftwareRow {
	return SoftwareRow{ id: 'editor', name: 'Editor é🚀', description: 'Read complete metadata', version: '2.0.0',
		installed_version: '1.0.0', installed_name: 'Installed editor', installed_kind: 'native', installed_permissions: ['display'], installed_window_protocol: 2,
		architecture: 'aarch64', kind: 'linux', runtime: 'runtime', repository: 'trusted', public_key: 'a'.repeat(64), license: 'MIT',
		permissions: ['files', 'network'], requested: true, updatable: true, update_action: 'update' }
}

fn fixture_software_view() SoftwareView {
	return SoftwareView{format: 1, generation: 7, architecture: 'aarch64', launch_user: 'alex', rows: [fixture_software_row()]}
}

fn refuses_software_view(text string) bool {
	mut view := decode_software_view(text) or { unsafe { err.free() }; return true }
	view.close()
	return false
}

fn test_view_reader_preserves_complete_installed_and_planned_fields_and_unicode() {
	expected := fixture_software_view()
	mut view := decode_software_view(json2.encode(expected))!
	assert view == expected
	assert view.rows[0].installed_permissions == ['display'] && view.rows[0].permissions == ['files', 'network']
	view.close(); assert view.rows.len == 0
	mut escaped := decode_software_view(json2.encode(expected).replace('Editor é🚀', 'Editor \\u00e9\\ud83d\\ude80'))!
	assert escaped.rows[0].name == expected.rows[0].name
	escaped.close()
	mut fresh := decode_software_view(json2.encode(SoftwareView{ format: 1, architecture: 'x86_64', offline: true, catalog_error: 'No enrolled publisher' }))!
	assert fresh.offline && fresh.generation == 0 && fresh.rows.len == 0
	fresh.close()
}

fn test_view_reader_admits_only_complete_bounded_installed_dependency_facts() {
	dependency := SoftwareDependency{id: 'old-runtime', minimum: '1.0.0', before: '2.0.0'}
	row := SoftwareRow{ ...fixture_software_row(), installed_dependencies_known: true, installed_dependencies: [dependency] }
	text := json2.encode(SoftwareView{ ...fixture_software_view(), rows: [row] })
	mut view := decode_software_view(text)!
	assert view.rows[0].installed_dependencies_known && view.rows[0].installed_dependencies == [dependency]
	assert view.rows[0].runtime == 'runtime' // displayed candidate remains independent
	view.close(); view.close()
	group := '"installed_dependencies":' + json2.encode([dependency]) + ','
	assert text.contains(group)
	for field in ['"installed_dependencies_known":true,', group] { assert refuses_software_view(text.replace(field, '')) }
	legacy := text.replace('"installed_dependencies_known":true,', '').replace(group, '')
	mut old := decode_software_view(legacy)!
	assert !old.rows[0].installed_dependencies_known && old.rows[0].installed_dependencies.len == 0
	old.close()
	for bad in [text.replace('"installed_dependencies_known":true', '"installed_dependencies_known":false'),
		text.replace('"installed_dependencies_known":true', '"installed_dependencies_known":1'),
		text.replace('"installed_dependencies_known":true', '"installed_dependencies_known":true,"installed_dependencies_kn\\u006fwn":true'),
		text.replace(group, group + group), text.replace(group, '"installed_dependencies":null,'),
		text.replace('old-runtime', '../runtime'), text.replace('old-runtime', 'x'.repeat(129)),
		text.replace('"minimum":"1.0.0",', ''), text.replace('"before":"2.0.0"', '"before":null'),
		text.replace('"minimum":"1.0.0"', '"minimum":"01.0.0"'),
		text.replace('"before":"2.0.0"', '"before":"1.0.0"'),
		text.replace('"before":"2.0.0"', '"before":"0.9.0"'),
		text.replace('"minimum":"1.0.0"', '"minimum":"1.0.0","min\\u0069mum":"1.0.0"'),
		text.replace(group, '"installed_dependencies":' + json2.encode([dependency, dependency]) + ',')] {
		assert refuses_software_view(bad)
	}
	mut many := []SoftwareDependency{cap: 129}
	for i in 0 .. 129 { many << SoftwareDependency{id: 'dependency-' + i.str()} }
	mut bounded := decode_software_view(text.replace(group, '"installed_dependencies":' + json2.encode(many[..128]) + ','))!
	assert bounded.rows[0].installed_dependencies.len == 128
	bounded.close()
	assert refuses_software_view(text.replace(group, '"installed_dependencies":' + json2.encode(many) + ','))
	assert refuses_software_view(json2.encode(SoftwareView{ ...fixture_software_view(), rows: [SoftwareRow{ ...row,
		installed_version: '', installed_name: '', installed_kind: '', installed_permissions: [], installed_window_protocol: 0,
		requested: false, updatable: false, update_action: '' }] }))
	mut empty := decode_software_view(text.replace(group, '"installed_dependencies":[],'))!
	assert empty.rows[0].installed_dependencies_known && empty.rows[0].installed_dependencies.len == 0
	empty.close()
	println('SOFTWARE DEPENDENCIES protocol preserves installed bounds, explicit empty/legacy facts and refuses partial/duplicate/coerced/oversized requirements PASS')
}

fn test_view_reader_requires_every_header_and_base_package_field() {
	text := json2.encode(fixture_software_view())
	for field in ['"format":1,', '"generation":7,', '"architecture":"aarch64",', '"offline":false,',
		'"catalog_error":"",', '"update_error":"",', ',"launch_user":"alex"'] {
		assert text.contains(field)
		assert refuses_software_view(text.replace(field, ''))
	}
	assert refuses_software_view(text.replace('"rows":[', '"extension":['))
	for field in ['"id":"editor",', '"name":"Editor é🚀",', '"description":"Read complete metadata",',
		'"version":"2.0.0",', '"installed_version":"1.0.0",', '"architecture":"aarch64",', '"kind":"linux",',
		'"runtime":"runtime",', '"repository":"trusted",', '"public_key":"' + 'a'.repeat(64) + '",', '"license":"MIT",',
		'"proprietary":false,', '"firmware":false,', '"permissions":["files","network"],', '"requested":true,',
		'"updatable":true,', '"update_action":"update",', ',"diagnostic":""'] {
		assert text.contains(field)
		assert refuses_software_view(text.replace(field, ''))
	}
}

fn test_view_reader_refuses_duplicate_coerced_and_invalid_unicode_fields() {
	text := json2.encode(fixture_software_view())
	for bad in [text.replace('"firmware":false', '"firmware":false,"firm\\u0077are":true'),
		text.replace('"offline":false', '"offline":false,"off\\u006cine":false'),
		text.replace('"installed_window_protocol":2', '"installed_window_protocol":2,"installed_window_protocol":1'),
		text.replace('"firmware":false', '"firmware":null'), text.replace('"requested":true', '"requested":"true"'),
		text.replace('"offline":false', '"offline":0'), text.replace('"permissions":["files","network"]', '"permissions":null'),
		text.replace('"generation":7', '"generation":18446744073709551616'), text.replace('"generation":7', '"generation":07'),
		text.replace('"generation":7', '"generation":7.0'), text.replace('"generation":7', '"generation":-1'),
		text.replace('"format":1', '"format":2'), text.replace('"format":1', '"format":true'),
		text.replace('Editor é🚀', '\\ud800'), text.replace('Editor é🚀', '\\udc00'), text.replace('Editor é🚀', '\xff'),
		text + ' false', text[..text.len - 1], text.replace('"firmware":false,', '"firmware":false,,')] {
		assert refuses_software_view(bad)
	}
}

fn test_view_reader_supports_only_complete_legacy_installed_field_groups() {
	text := json2.encode(fixture_software_view())
	without_protocol := text.replace('"installed_window_protocol":2,', '')
	mut older := decode_software_view(without_protocol)!
	assert older.rows[0].installed_kind == 'native' && older.rows[0].installed_window_protocol == 0
	older.close()
	legacy := without_protocol.replace('"installed_name":"Installed editor",', '').replace('"installed_kind":"native",', '').replace('"installed_permissions":["display"],', '')
	mut original := decode_software_view(legacy)!
	assert original.rows[0].installed_version == '1.0.0' && original.rows[0].installed_kind == '' && original.rows[0].installed_permissions.len == 0
	original.close()
	for field in ['"installed_name":"Installed editor",', '"installed_kind":"native",', '"installed_permissions":["display"],'] {
		assert refuses_software_view(text.replace(field, ''))
		assert refuses_software_view(without_protocol.replace(field, ''))
	}
}

fn test_view_reader_keeps_installed_provenance_independent_of_catalog_and_legacy_launch_shapes() {
	row := SoftwareRow{ ...fixture_software_row(), installed_repository: 'original-publisher', installed_public_key: 'b'.repeat(64) }
	text := json2.encode(SoftwareView{ ...fixture_software_view(), rows: [row] })
	for legacy_launch in [false, true]! {
		input := if legacy_launch { text.replace('"installed_name":"Installed editor",', '').replace('"installed_kind":"native",', '')
			.replace('"installed_permissions":["display"],', '').replace('"installed_window_protocol":2,', '') } else { text }
		mut view := decode_software_view(input)!
		assert view.rows[0].installed_repository == 'original-publisher' && view.rows[0].installed_public_key == 'b'.repeat(64)
		assert view.rows[0].repository == 'trusted' && view.rows[0].public_key == 'a'.repeat(64)
		view.close(); view.close()
		for field in ['"installed_repository":"original-publisher",', '"installed_public_key":"' + 'b'.repeat(64) + '",'] {
			assert refuses_software_view(input.replace(field, ''))
		}
		without := input.replace('"installed_repository":"original-publisher",', '').replace('"installed_public_key":"' + 'b'.repeat(64) + '",', '')
		mut older := decode_software_view(without)!
		assert older.rows[0].installed_repository == '' && older.rows[0].installed_public_key == ''
		older.close()
	}
	for bad in [text.replace('"installed_repository":"original-publisher"', '"installed_repository":"original-publisher","installed_repos\\u0069tory":"other"'),
		text.replace('"installed_public_key":"' + 'b'.repeat(64) + '"', '"installed_public_key":"' + 'b'.repeat(64) + '","installed_public_key":"' + 'c'.repeat(64) + '"'),
		text.replace('"installed_repository":"original-publisher"', '"installed_repository":null'),
		text.replace('"installed_public_key":"' + 'b'.repeat(64) + '"', '"installed_public_key":false'),
		text.replace('original-publisher', ''), text.replace('b'.repeat(64), ''), text.replace('original-publisher', '../outside'),
		text.replace('original-publisher', 'x'.repeat(129)), text.replace('original-publisher', '\\ud800'),
		text.replace('b'.repeat(64), 'B'.repeat(64)), text.replace('b'.repeat(64), 'b'.repeat(65))] { assert refuses_software_view(bad) }
	uninstalled := SoftwareRow{ ...fixture_software_row(), installed_version: '', installed_name: '', installed_kind: '', installed_permissions: [],
		installed_window_protocol: 0, requested: false, updatable: false, update_action: '', installed_repository: row.installed_repository, installed_public_key: row.installed_public_key }
	assert refuses_software_view(json2.encode(SoftwareView{ ...fixture_software_view(), rows: [uninstalled] }))
	println('SOFTWARE PROVENANCE protocol keeps installed and displayed publishers distinct; legacy groups, duplicate/partial/invalid identity and uninstalled rows PASS')
}

fn test_view_reader_ignores_valid_additive_values_without_accepting_broken_json() {
	text := json2.encode(fixture_software_view())
	extension := '"extension":{"text":"é\\ud83d\\ude80","array":[null,true,false,-1.25e+2,{"later":[]}],"large":1e9999},'
	mut view := decode_software_view(text.replace('"format":1,', '"format":1,' + extension).replace('"id":"editor",', '"id":"editor",' + extension))!
	assert view == fixture_software_view()
	view.close()
	for value in ['n ull', 'n u l l', '01', '-', '1.', '1e', '1e+', '[true,]', '{"later":}', '{"later":false,}', '"\\ud800"', '"\xff"', '{"a" true}'] {
		assert refuses_software_view(text.replace('"format":1,', '"format":1,"extra":' + value + ','))
	}
	assert refuses_software_view(text.replace('"format":1,', '"format":1,"extra":' + '['.repeat(34) + 'null' + ']'.repeat(34) + ','))
	mut bounded := decode_software_view(text.replace('"format":1,', '"format":1,"extra":' + '['.repeat(32) + 'null' + ']'.repeat(32) + ','))!
	bounded.close()
}

fn test_view_reader_refuses_incoherent_updates_permissions_architectures_and_launches() {
	text := json2.encode(fixture_software_view())
	for bad in [text.replace('"updatable":true', '"updatable":false'), text.replace('"update_action":"update"', '"update_action":""'),
		text.replace('"update_action":"update"', '"update_action":"remove"'), text.replace('"update_action":"update"', '"update_action":"install"'),
		text.replace('"update_error":""', '"update_error":"Resolution failed"'), text.replace('"catalog_error":""', '"catalog_error":"Expired"'),
		text.replace('"generation":7', '"generation":0'), text.replace('"architecture":"aarch64"', '"architecture":"unknown"'),
		text.replace('"kind":"linux"', '"kind":"unknown"'), text.replace('"runtime":"runtime"', '"runtime":""'),
		text.replace('"installed_kind":"native"', '"installed_kind":"linux"'), text.replace('"installed_permissions":["display"]', '"installed_permissions":[]'),
		text.replace('"installed_kind":"native"', '"installed_kind":""'), text.replace('"installed_window_protocol":2', '"installed_window_protocol":3'),
		text.replace('"permissions":["files","network"]', '"permissions":["root"]'), text.replace('"installed_version":"1.0.0"', '"installed_version":""'),
		text.replace('"permissions":["files","network"]', '"permissions":["files","files"]'),
		text.replace('"installed_permissions":["display"]', '"installed_permissions":["display","display"]'),
		text.replace('"launch_user":"alex"', '"launch_user":"root"'), text.replace('"launch_user":"alex"', '"launch_user":"$(shell)"'),
		text.replace('"id":"editor"', '"id":"../editor"'), text.replace('"name":"Editor é🚀"', '"name":""'),
		text.replace('"name":"Editor é🚀"', '"name":"Line\\nBreak"'), text.replace('"public_key":"' + 'a'.repeat(64) + '"', '"public_key":"bad"')] {
		assert refuses_software_view(bad)
	}
	assert refuses_software_view(json2.encode(SoftwareView{ ...fixture_software_view(), rows: [fixture_software_row(), fixture_software_row()] }))
}

fn test_view_reader_applies_text_row_reply_and_integer_boundaries() {
	text := json2.encode(fixture_software_view())
	for bad in [text.replace('Read complete metadata', 'x'.repeat(4097)), text.replace('"diagnostic":""', '"diagnostic":"' + 'x'.repeat(4097) + '"'),
		text.replace('"name":"Editor é🚀"', '"name":"' + 'x'.repeat(257) + '"'), text.replace('"launch_user":"alex"', '"launch_user":"' + 'a'.repeat(33) + '"'),
		text.replace('"permissions":["files","network"]', '"permissions":["files","network","audio","display","process","files"]'),
		text + ' '.repeat(8 * 1024 * 1024)] { assert refuses_software_view(bad) }
	mut largest := decode_software_view(text.replace('Read complete metadata', 'x'.repeat(4096)).replace('"generation":7', '"generation":18446744073709551615'))!
	assert largest.rows[0].description.len == 4096 && largest.generation == ~u64(0)
	largest.close()
	mut rows := []SoftwareRow{cap: 4097}
	for index in 0 .. 4097 { rows << SoftwareRow{ ...fixture_software_row(), id: 'app-' + index.str() } }
	assert refuses_software_view(json2.encode(SoftwareView{ ...fixture_software_view(), rows: rows }))
	rows.delete_last()
	mut bounded := decode_software_view(json2.encode(SoftwareView{ ...fixture_software_view(), rows: rows }))!
	assert bounded.rows.len == 4096
	bounded.close()
}

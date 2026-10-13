// SPDX-License-Identifier: GPL-2.0-or-later
module pkgprotocol

import json2

fn test_personal_data_status_rejects_unsupported_ambiguous_and_unbounded_rows() {
	for text in ['{}', '{"format":2,"rows":[]}', '{"format":1,"rows":[{"id":"../other","installed":false,"diagnostic":""}]}',
		'{"format":1,"rows":[{"id":"app","installed":false,"diagnostic":""},{"id":"app","installed":false,"diagnostic":""}]}',
		'{"format":1,"rows":[{"id":"app","installed":false,"diagnostic":"bad\\nline"}]}',
		'{"format":1,"rows":[{"id":"app","installed":"true","diagnostic":""}]}',
		'{"format":1,"rows":[],"rows":[]}', '{"format":1,"rows":[],"unknown":0}',
		'{"format":1,"rows":[{"id":"app","installed":false,"diagnostic":"","id":"other"}]}',
		'{"format":1,"rows":[]} trailing', '{"format":1,"rows":[null]}', '{"format":1,"rows":null}',
		'{"format":1,"rows":[{"id":"app","installed":false,"diagnostic":"\\ud800"}]}',
		'{"format":1,"rows":[{"id":"app","installed":false,"diagnostic":"\xff"}]}'] {
		mut refused := false
		mut status := decode_personal_data(text) or { refused = true; PersonalDataStatus{} }
		status.close()
		assert refused, text
	}
	mut too_many := PersonalDataStatus{ format: 1, rows: []PersonalData{len: 4097} }
	mut refused := false
	too_many.validate() or { refused = true }
	assert refused
	too_many.close()
	mut long := PersonalDataStatus{ format: 1, rows: [PersonalData{ id: 'app', diagnostic: 'x'.repeat(513) }] }
	long.validate() or { long.close(); return }
	long.close()
	assert false, 'overlong diagnostic accepted'
}

fn test_personal_data_string_escapes_key_order_and_array_growth() {
	mut decoded := decode_personal_data('{"rows":[{"diagnostic":"Érase \\u00e9 \\ud83d\\ude80","installed":false,"\\u0069d":"app"}],"format":1}')!
	assert decoded.rows[0].id == 'app' && decoded.rows[0].diagnostic == 'Érase é 🚀'
	decoded.close()
	mut rows := []PersonalData{cap: 32}
	for index in 0 .. 32 { rows << PersonalData{ id: 'app-' + index.str() } }
	text := json2.encode(PersonalDataStatus{ format: 1, rows: rows })
	mut wide := decode_personal_data(text)!
	assert wide.rows.len == 32 && wide.rows[31].id == 'app-31'
	wide.close()
	mut owned := PersonalDataStatus{ rows: rows }; owned.close()
	unsafe { text.free() }
}

fn test_personal_data_status_owns_rows_and_resets_after_close() {
	text := json2.encode(PersonalDataStatus{ format: 1, rows: [
		PersonalData{ id: 'installed-app', installed: true },
		PersonalData{ id: 'removed-app', diagnostic: 'Application data is on another filesystem.' }] })
	mut status := decode_personal_data(text)!
	assert status.rows.len == 2 && status.rows[0].installed && !status.rows[1].installed
	assert status.rows[1].diagnostic.contains('another filesystem')
	status.close()
	assert status.rows.len == 0 && status.format == 0
	status.close()
	unsafe { text.free() }
}

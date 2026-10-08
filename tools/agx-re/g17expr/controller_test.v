module g17expr

import os
import encoding.hex
import json2
import traceanalysis as j

fn test_controller_preserves_uuid_parse_and_validation_error_order() {
	rows := j.decode(os.read_file(os.join_path(os.dir(@FILE), 'fixtures/controller-boundaries.json')) or { panic(err) }) or { panic(err) }
	for row in rows.arr() {
		record := row.as_map()
		request := at(record, 'request').as_map()
		data := hex.decode(text(request, 'image')) or { panic(err) }
		before := data.clone()
		_ := query(data, 'recover_g17_report', request) or {
			expected := text(record, 'error')
			kind := text(record, 'exception')
			assert err.msg() == if kind == 'error' {
				'struct.error: ' + expected
			} else if kind in ['struct.error', 'TypeError', 'KeyError', 'IndexError'] {
				kind + ': ' + expected
			} else {
				expected
			}, text(record, 'label')
			assert data == before
			continue
		}
		assert false, text(record, 'label')
	}
}

fn test_controller_nested_updates_own_their_maps() {
	shared := expr({
		'dispatch': expr({
			'role': j.Value(0)
		})
		'rows':     j.Value([j.Value(1), j.Value(2)])
	})
	mut original := shared
	mut changed := shared
	controller_put(mut changed, ['dispatch', 'ring'], expr({
		'bytes': j.Value(64)
	}))
	assert at(at(original.as_map(), 'dispatch').as_map(), 'ring') is json2.Null
	assert controller_item(controller_item(changed, j.Value('dispatch')), j.Value('ring')) == expr({
		'bytes': j.Value(64)
	})
	controller_put(mut original, ['dispatch', 'role'], j.Value(1))
	assert controller_item(controller_item(changed, j.Value('dispatch')), j.Value('role')) == j.Value(0)
	assert at(original.as_map(), 'rows') == at(changed.as_map(), 'rows')
}

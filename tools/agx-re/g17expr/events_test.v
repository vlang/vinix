module g17expr

import os
import encoding.hex
import traceanalysis as j

// Complete original outcomes are shared by structural fixture patches. The
// patch preserves every omitted provider key and byte field of each input.
fn event_fixture_patch(base j.Value, patch j.Value) j.Value {
	fields := patch.as_map()
	if 'set' in fields { return at(fields, 'set') }
	mut result := base.as_map().clone()
	for key in at(fields, 'remove').arr() { result.delete(j.string_value(key)) }
	for key, value in at(fields, 'children').as_map() {
		result[key] = event_fixture_patch(at(result, key), value)
	}
	return expr(result)
}

fn verify_original_event(name string) {
	fixture := j.decode(os.read_file(os.join_path(os.dir(@FILE), 'fixtures/original-events.json')) or { panic(err) }) or { panic(err) }
	fields := fixture.as_map()
	for value in at(at(fields, 'tests').as_map(), name).arr() {
		row := value.as_map()
		operation := text(row, 'operation')
		request := event_fixture_patch(at(at(fields, 'bases').as_map(), operation), at(row, 'patch')).as_map()
		before := j.encode(expr(request), false)
		data := hex.decode(if 'driver' in request { text(request, 'driver') } else { '' }) or { panic(err) }
		original := data.clone()
		result := query(data, operation, request) or {
			assert 'error' in row
			assert err.msg() == text(row, 'error')
			assert j.encode(expr(request), false) == before
			assert data == original
			continue
		}
		assert 'result' in row
		assert j.decode(j.encode(result, false)) or { panic(err) } == at(row, 'result')
		assert j.encode(expr(request), false) == before
		assert data == original
	}
}

fn test_selects_t6050_callback_interrupt() {
	verify_original_event('test_selects_t6050_callback_interrupt')
}

fn test_classifies_g17_noop_and_advisory_events() {
	verify_original_event('test_classifies_g17_noop_and_advisory_events')
}

fn test_rejects_non_noop_g17_controller_event_handler() {
	verify_original_event('test_rejects_non_noop_g17_controller_event_handler')
}

fn test_rejects_non_noop_g17_uma_allocation_worker() {
	verify_original_event('test_rejects_non_noop_g17_uma_allocation_worker')
}

fn test_rejects_wrong_g17_clpc_notification_target() {
	verify_original_event('test_rejects_wrong_g17_clpc_notification_target')
}

fn test_rejects_wrong_g17_restart_target() {
	verify_original_event('test_rejects_wrong_g17_restart_target')
}

fn test_rejects_wrong_g17_channel_error_stamp_target() {
	verify_original_event('test_rejects_wrong_g17_channel_error_stamp_target')
}

fn test_rejects_wrong_g17_shared_event_completion_target() {
	verify_original_event('test_rejects_wrong_g17_shared_event_completion_target')
}

fn test_rejects_wrong_g17_process_exit_namespace_target() {
	verify_original_event('test_rejects_wrong_g17_process_exit_namespace_target')
}

fn test_rejects_changed_g17_event_validator_identity() {
	verify_original_event('test_rejects_changed_g17_event_validator_identity')
}

fn test_rejects_wrong_g17_reliability_service() {
	verify_original_event('test_rejects_wrong_g17_reliability_service')
}

fn test_checked_driver_event_contracts_match_complete_original_outputs() {
	root := os.join_path(os.dir(@FILE), '..', 'build', 'kext', 'g17c')
	if !os.exists(os.join_path(root, 'AGXG17X.macho')) { return }
	data := os.read_bytes(os.join_path(root, 'AGXG17X.macho')) or { panic(err) }
	original := data.clone()
	rows := j.decode(os.read_file(os.join_path(os.dir(@FILE), 'fixtures/event-driver-contracts.json')) or { panic(err) }) or { panic(err) }
	for value in rows.arr() {
		row := value.as_map()
		operation := text(row, 'operation')
		mut request := map[string]j.Value{}
		for key, name in {
			'kernel':    'kernel.macho'
			'iogpu':     'iokit.IOGPUFamily.macho'
			'iosurface': 'iokit.IOSurface.macho'
		} {
			if (operation == 'recover_g17_akf_callback' && key != 'kernel') || (operation == 'recover_g17_firmware_event_ring' && key == 'kernel') {
				continue
			}
			request[key] = j.Value(hex.encode(os.read_bytes(os.join_path(root, name)) or { panic(err) }))
		}
		result := query(data, operation, request) or { panic(err) }
		assert j.decode(j.encode(result, false)) or { panic(err) } == at(row, 'result')
		assert data == original
	}
}

fn test_callback_selection_preserves_full_integer_and_floating_types() {
	rows := j.decode(os.read_file(os.join_path(os.dir(@FILE), 'fixtures/event-selector-widths.json')) or { panic(err) }) or { panic(err) }
	for value in rows.arr() {
		row := value.as_map()
		request := at(row, 'request').as_map()
		before := j.encode(expr(request), false)
		result := query([]u8{}, 'g17_callback_interrupt_index', request) or {
			assert 'error' in row
			prefix := if text(row, 'exception') == 'TypeError' { 'TypeError: ' } else { '' }
			assert err.msg() == prefix + text(row, 'error')
			assert j.encode(expr(request), false) == before
			continue
		}
		assert 'result' in row
		assert j.decode(j.encode(result, false)) or { panic(err) } == at(row, 'result')
		assert j.encode(expr(request), false) == before
	}
}

fn test_event_boundaries_preserve_rounding_provider_types_and_index_errors() {
	fixture := j.decode(os.read_file(os.join_path(os.dir(@FILE), 'fixtures/original-events.json')) or { panic(err) }) or { panic(err) }
	base := at(at(fixture.as_map(), 'bases').as_map(), 'recover_g17_firmware_event_actions')
	base_row := at(at(fixture.as_map(), 'tests').as_map(), 'test_classifies_g17_noop_and_advisory_events').arr()[0].as_map()
	base_result := at(base_row, 'result')
	rows := j.decode(os.read_file(os.join_path(os.dir(@FILE), 'fixtures/event-boundaries.json')) or { panic(err) }) or { panic(err) }
	for value in rows.arr() {
		row := value.as_map()
		request := event_fixture_patch(base, at(row, 'request_patch')).as_map()
		before := j.encode(expr(request), false)
		result := query([]u8{}, text(request, 'operation'), request) or {
			assert 'error' in row
			kind := text(row, 'exception')
			prefix := if kind in ['TypeError', 'IndexError', 'OverflowError'] {
				kind + ': '
			} else {
				''
			}
			expected := text(row, 'error')
			assert err.msg() == if kind == 'KeyError' { 'KeyError: ' + expected[1..expected.len - 1] } else { prefix + expected }
			assert j.encode(expr(request), false) == before
			continue
		}
		assert 'result_patch' in row
		assert j.decode(j.encode(result, false)) or { panic(err) } == event_fixture_patch(base_result, at(row, 'result_patch'))
		assert j.encode(expr(request), false) == before
	}
}

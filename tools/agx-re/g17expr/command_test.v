module g17expr

import os
import traceanalysis as j
import math.big

// Complete outputs and byte fixtures come from 35 unchanged independent
// pre-port test bodies, frozen before the native routines were written.
fn verify_original_command(name string) {
	records := j.decode(os.read_file(os.join_path(os.dir(@FILE), 'fixtures/original-commands.json')) or { panic(err) }) or { panic(err) }
	for row_value in at(records.as_map(), name).arr() {
		row := row_value.as_map()
		request := at(row, 'request').as_map()
		before := j.encode(expr(request), false)
		result := query([]u8{}, text(request, 'operation'), request) or {
			assert 'error' in row
			assert err.msg() == text(row, 'error')
			assert j.encode(expr(request), false) == before
			continue
		}
		assert 'result' in row
		assert j.decode(j.encode(result, false)) or { panic(err) } == at(row, 'result')
		assert j.encode(expr(request), false) == before
	}
}

fn test_recovers_g17_dual_role_boot_transport() {
	verify_original_command('test_recovers_g17_dual_role_boot_transport')
}

fn test_rejects_single_role_g17_boot_transport() {
	verify_original_command('test_rejects_single_role_g17_boot_transport')
}

fn test_recovers_g17_rtbuddy_endpoints() {
	verify_original_command('test_recovers_g17_rtbuddy_endpoints')
}

fn test_recovers_g17_handoff_layout() {
	verify_original_command('test_recovers_g17_handoff_layout')
}

fn test_recovers_g17_command_stream_format() {
	verify_original_command('test_recovers_g17_command_stream_format')
}

fn test_recovers_g17_render_payload_format() {
	verify_original_command('test_recovers_g17_render_payload_format')
}

fn test_recovers_g17_normalized_render_descriptor_fields() {
	verify_original_command('test_recovers_g17_normalized_render_descriptor_fields')
}

fn test_recovers_g17_3d_common_passthrough() {
	verify_original_command('test_recovers_g17_3d_common_passthrough')
}

fn test_rejects_g17_3d_passthrough_call_retarget() {
	verify_original_command('test_rejects_g17_3d_passthrough_call_retarget')
}

fn test_recovers_g17_ta_render_passthrough() {
	verify_original_command('test_recovers_g17_ta_render_passthrough')
}

fn test_recovers_g17_3d_descriptor_initialization() {
	verify_original_command('test_recovers_g17_3d_descriptor_initialization')
}

fn test_rejects_g17_ta_descriptor_base_init_retarget() {
	verify_original_command('test_rejects_g17_ta_descriptor_base_init_retarget')
}

fn test_recovers_g17_channel_command_common_fields() {
	verify_original_command('test_recovers_g17_channel_command_common_fields')
}

fn test_rejects_changed_g17_channel_command_common_field() {
	verify_original_command('test_rejects_changed_g17_channel_command_common_field')
}

fn test_recovers_g17_register_entry_codec() {
	verify_original_command('test_recovers_g17_register_entry_codec')
}

fn test_collapses_g17_register_emission_cfg() {
	verify_original_command('test_collapses_g17_register_emission_cfg')
}

fn test_recovers_g17_3d_register_lists() {
	verify_original_command('test_recovers_g17_3d_register_lists')
}

fn test_rejects_changed_g17_3d_register_entry_stride() {
	verify_original_command('test_rejects_changed_g17_3d_register_entry_stride')
}

fn test_recovers_g17_channel_command_pools() {
	verify_original_command('test_recovers_g17_channel_command_pools')
}

fn test_rejects_short_g17_pool_size_producer() {
	verify_original_command('test_rejects_short_g17_pool_size_producer')
}

fn test_recovers_g17_command_pool_backing() {
	verify_original_command('test_recovers_g17_command_pool_backing')
}

fn test_rejects_changed_g17_command_pool_backing() {
	verify_original_command('test_rejects_changed_g17_command_pool_backing')
}

fn test_recovers_g17_3d_command_reclamation() {
	verify_original_command('test_recovers_g17_3d_command_reclamation')
}

fn test_rejects_changed_g17_3d_command_reclamation() {
	verify_original_command('test_rejects_changed_g17_3d_command_reclamation')
}

fn test_recovers_g17_queue_device_inputs() {
	verify_original_command('test_recovers_g17_queue_device_inputs')
}

fn test_rejects_split_g17_device_process_id_producers() {
	verify_original_command('test_rejects_split_g17_device_process_id_producers')
}

fn test_recovers_g17_channel_runtime_resources() {
	verify_original_command('test_recovers_g17_channel_runtime_resources')
}

fn test_rejects_changed_g17_channel_runtime_resources() {
	verify_original_command('test_rejects_changed_g17_channel_runtime_resources')
}

fn test_recovers_g17_scheduler_state() {
	verify_original_command('test_recovers_g17_scheduler_state')
}

fn test_rejects_changed_g17_scheduler_state_element_size() {
	verify_original_command('test_rejects_changed_g17_scheduler_state_element_size')
}

fn test_recovers_g17_channel_state_sources() {
	verify_original_command('test_recovers_g17_channel_state_sources')
}

fn test_recovers_g17_channel_data_master_types() {
	verify_original_command('test_recovers_g17_channel_data_master_types')
}

fn test_rejects_changed_g17_channel_data_master_type() {
	verify_original_command('test_rejects_changed_g17_channel_data_master_type')
}

fn test_recovers_g17_channel_identity() {
	verify_original_command('test_recovers_g17_channel_identity')
}

fn test_rejects_changed_g17_channel_identity() {
	verify_original_command('test_rejects_changed_g17_channel_identity')
}

fn test_command_integer_preserves_decimal_widths() {
	assert command_integer(j.Value('  +١_٢٣٤  ')) or { panic(err) } == big.integer_from_int(1234)
	value := big.integer_from_string('1267650600228229401496703205376') or { panic(err) }
	assert command_integer(scalar(value)) or { panic(err) } == value
	assert command_integer(j.Value(true)) or { panic(err) } == big.integer_from_int(1)
}

fn test_command_graph_big_addresses_and_back_edges() {
	base := big.integer_from_string('1267650600228229401496703205376') or { panic(err) }
	instructions := [Instruction{ offset: base, word: 0xd503201f },
		Instruction{ offset: base + big.integer_from_int(4), word: 0x54ffffe1 },
		Instruction{ offset: base + big.integer_from_int(8), word: 0xd65f03c0 }]
	graph := emission_cfg(instructions, [base]) or { panic(err) }
	assert number(graph, 'loop_edge_count') == 1
	assert number(graph, 'semantic_decision_count') == 1
	assert number(graph, 'event_count') == 1
	assert at(graph, 'entry').arr() == [scalar(base)]
}

fn test_command_binary_offset_boundaries() {
	bytes := []u8{len: 64}
	assert unpack_offset(bytes, big.integer_from_int(-16), 16) or { panic(err) } == 48
	assert unpack_offset(bytes, big.integer_from_int(-64), 16) or { panic(err) } == 0
	unpack_offset(bytes, big.integer_from_int(-1), 16) or { assert err.msg() == 'struct.error: not enough data to unpack 16 bytes at offset -1' }
	huge := big.integer_from_string('1267650600228229401496703205376') or { panic(err) }
	unpack_offset(bytes, huge, 16) or { assert err.msg() == 'OverflowError: Python int too large to convert to C ssize_t' }
	assert string_offset(bytes, huge.neg()) == 0
	assert string_offset(bytes, huge) == 64
}

fn test_command_utf8_error_retains_input_and_span() {
	bytes := [u8(0x61), 0xe1, 0x80]
	strict_utf8(bytes) or {
		assert err.msg().starts_with('UnicodeDecodeError: ')
		details := j.decode(err.msg().all_after('UnicodeDecodeError: ')) or { panic(err) }
		node := details.as_map()
		assert text(node, 'bytes') == '61e180'
		assert number(node, 'start') == 1
		assert number(node, 'end') == 3
		assert text(node, 'reason') == 'unexpected end of data'
	}
}

fn test_command_nonfinite_metadata_keeps_exception_category() {
	records := j.decode(os.read_file(os.join_path(os.dir(@FILE), 'fixtures/original-commands.json')) or { panic(err) }) or { panic(err) }
	row := at(records.as_map(), 'test_recovers_g17_normalized_render_descriptor_fields').arr()[0].as_map()
	mut request := at(row, 'request').as_map().clone()
	text_payload := j.encode(at(request, 'render_payload'), false).replace('"command_member":520', '"command_member":Infinity')
	assert text_payload.contains('Infinity')
	request['render_payload_text'] = j.Value(text_payload)
	query([]u8{}, 'recover_g17_render_descriptor_fields', request) or {
		assert err.msg() == 'OverflowError: cannot convert float infinity to integer'
		return
	}
	assert false
}

module g17expr

import os
import encoding.hex
import traceanalysis as j

// Inputs and complete outcomes are frozen from the original independent
// methods. Optional real-driver checks never embed extracted Apple bytes.
fn verify_original_config(name string) {
	records := j.decode(os.read_file(os.join_path(os.dir(@FILE), 'fixtures/original-config.json')) or { panic(err) }) or { panic(err) }
	for row_value in at(records.as_map(), name).arr() {
		row := row_value.as_map()
		request := at(row, 'request').as_map()
		mut data := []u8{}
		if 'native_source' in request {
			path := os.getenv_opt('VINIX_AGX_G17_TEST_DRIVER') or { os.join_path(os.dir(@FILE), '..', 'build', 'kext', 'g17c', text(request, 'native_source')) }
			if !os.exists(path) { continue }
			data = os.read_bytes(path) or { panic(err) }
		}
		before := j.encode(expr(request), false)
		original := data.clone()
		result := query(data, text(request, 'operation'), request) or {
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

fn test_computed_config_stores_keep_original_random_stream_results() {
	rows := j.decode(os.read_file(os.join_path(os.dir(@FILE), 'fixtures/config-stores.json')) or { panic(err) }) or { panic(err) }
	for value in rows.arr() {
		row := value.as_map()
		request := at(row, 'request').as_map()
		before := j.encode(expr(request), false)
		result := query([]u8{}, 'config_pointer_stores', request) or { panic(err) }
		assert j.decode(j.encode(result, false)) or { panic(err) } == at(row, 'result')
		assert j.encode(expr(request), false) == before
	}
}

fn test_executable_segment_span_keeps_unsigned_64_bit_file_sizes() {
	rows := j.decode(os.read_file(os.join_path(os.dir(@FILE), 'fixtures/config-segments.json')) or { panic(err) }) or { panic(err) }
	for value in rows.arr() {
		row := value.as_map()
		data := hex.decode(text(row, 'image')) or { panic(err) }
		before := data.clone()
		image := CommandImage{ provider: FixtureImage{}, bytes: data }
		result := config_exec_codes(image, map[string]j.Value{}) or { panic(err) }
		assert result.map(j.Value(hex.encode(it))) == at(row, 'expected').arr()
		assert data == before
	}
}

fn test_recovers_g17_data_master_ring_matrix() {
	verify_original_config('test_recovers_g17_data_master_ring_matrix')
}

fn test_rejects_wrong_g17_data_master_ring_backing() {
	verify_original_config('test_rejects_wrong_g17_data_master_ring_backing')
}

fn test_recovers_g17_data_master_doorbells() {
	verify_original_config('test_recovers_g17_data_master_doorbells')
}

fn test_recovers_g17_channel_priority_profiles() {
	verify_original_config('test_recovers_g17_channel_priority_profiles')
}

fn test_rejects_modified_g17_channel_priority_profile() {
	verify_original_config('test_rejects_modified_g17_channel_priority_profile')
}

fn test_recovers_g17_channel_submit_info() {
	verify_original_config('test_recovers_g17_channel_submit_info')
}

fn test_rejects_modified_g17_channel_submit_info() {
	verify_original_config('test_rejects_modified_g17_channel_submit_info')
}

fn test_recovers_g17_channel_submission_flag() {
	verify_original_config('test_recovers_g17_channel_submission_flag')
}

fn test_rejects_modified_g17_channel_submission_flag() {
	verify_original_config('test_rejects_modified_g17_channel_submission_flag')
}

fn test_recovers_g17_channel_pool_geometry() {
	verify_original_config('test_recovers_g17_channel_pool_geometry')
}

fn test_recovers_g17_channel_layout() { verify_original_config('test_recovers_g17_channel_layout') }

fn test_rejects_incomplete_g17_channel_layout() {
	verify_original_config('test_rejects_incomplete_g17_channel_layout')
}

fn test_recovers_g17_relative_boost_frequency_table() {
	verify_original_config('test_recovers_g17_relative_boost_frequency_table')
}

fn test_recovers_g17_sram_power_scale_table() {
	verify_original_config('test_recovers_g17_sram_power_scale_table')
}

fn test_recovers_zero_g17_static_power_scale_table() {
	verify_original_config('test_recovers_zero_g17_static_power_scale_table')
}

fn test_recovers_g17_secondary_performance_block() {
	verify_original_config('test_recovers_g17_secondary_performance_block')
}

fn test_recovers_g17_final_late_controls() {
	verify_original_config('test_recovers_g17_final_late_controls')
}

fn test_recovers_g17_remaining_late_controls() {
	verify_original_config('test_recovers_g17_remaining_late_controls')
}

fn test_ones_run_stops_before_the_next_field() {
	verify_original_config('test_ones_run_stops_before_the_next_field')
}

fn test_recovers_g17_cleared_accelerator_inputs() {
	verify_original_config('test_recovers_g17_cleared_accelerator_inputs')
}

fn test_recovers_g17_unit_mask_field() {
	verify_original_config('test_recovers_g17_unit_mask_field')
}

fn test_recovers_g17_core_count_gate() {
	verify_original_config('test_recovers_g17_core_count_gate')
}

fn test_scaled_core_count_is_not_the_core_count_field_source() {
	verify_original_config('test_scaled_core_count_is_not_the_core_count_field_source')
}

fn test_recovers_g17_chip_info_decode() {
	verify_original_config('test_recovers_g17_chip_info_decode')
}

fn test_chip_info_power_dimensions_match_their_consumers() {
	verify_original_config('test_chip_info_power_dimensions_match_their_consumers')
}

fn test_recovers_g17_chip_info_registers() {
	verify_original_config('test_recovers_g17_chip_info_registers')
}

fn test_chip_variant_reaches_the_power_model_field() {
	verify_original_config('test_chip_variant_reaches_the_power_model_field')
}

fn test_cleared_hardware_config_gaps_are_supported() {
	verify_original_config('test_cleared_hardware_config_gaps_are_supported')
}

fn test_recovers_g17_late_controls_from_the_real_producer() {
	verify_original_config('test_recovers_g17_late_controls_from_the_real_producer')
}

fn test_config_pointer_stores_ignores_foreign_bases() {
	verify_original_config('test_config_pointer_stores_ignores_foreign_bases')
}

fn test_config_pointer_stores_follows_computed_bases() {
	verify_original_config('test_config_pointer_stores_follows_computed_bases')
}

fn test_recovers_g17_afr_relative_boost_frequency_table() {
	verify_original_config('test_recovers_g17_afr_relative_boost_frequency_table')
}

fn test_recovers_g17_performance_state_map_block() {
	verify_original_config('test_recovers_g17_performance_state_map_block')
}

fn test_recovers_g17_auxiliary_performance_layout() {
	verify_original_config('test_recovers_g17_auxiliary_performance_layout')
}

fn test_configuration_feature_mask_keeps_high_word_bits() {
	assert config_feature_mask() == u64(0x0001000018020000)
	assert config_feature_mask() >> 48 == 1
	assert config_feature_mask() & (u64(1) << 17) != 0
}

fn test_config_offsets_and_negative_shift_lanes_keep_original_integer_widths() {
	rows := j.decode(os.read_file(os.join_path(os.dir(@FILE), 'fixtures/config-widths.json')) or { panic(err) }) or { panic(err) }
	for value in rows.arr() {
		row := value.as_map()
		request := at(row, 'request').as_map()
		before := j.encode(expr(request), false)
		result := query([]u8{}, text(request, 'operation'), request) or { panic(err) }
		assert j.decode(j.encode(result, false)) or { panic(err) } == at(row, 'result')
		assert j.encode(expr(request), false) == before
	}
}

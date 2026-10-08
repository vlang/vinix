module g17expr

import os
import encoding.hex
import traceanalysis as j
import math.big

// Full byte inputs, image-provider boundaries and outputs were frozen from
// the independent original test bodies before the runtime port.
fn verify_original_runtime(name string) {
	records := j.decode(os.read_file(os.join_path(os.dir(@FILE), 'fixtures/original-runtime.json')) or { panic(err) }) or { panic(err) }
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

fn test_runtime_allocation_numeric_equality_is_exact() {
	assert runtime_equal(j.Number{'896.0'}, 896)
	assert !runtime_equal(j.Number{'896.5'}, 896)
	assert !runtime_equal(j.Value('896'), 896)
	assert !runtime_equal(j.Number{'NaN'}, 0)
	assert !runtime_equal(j.Number{'Infinity'}, 0)
}

fn test_runtime_caller_target_keeps_binary64_integer_value() {
	maximum := big.integer_from_u64(~u64(0))
	assert runtime_target_equal(maximum, j.Number{'18446744073709551615'})
	assert !runtime_target_equal(maximum, j.Number{'1.8446744073709552e19'})
	assert runtime_target_equal(big.integer_from_u64(u64(1) << 63), j.Number{'9.223372036854776e18'})
	assert runtime_target_equal(big.zero_int, j.Number{'-0.0'})
	assert !runtime_target_equal(big.zero_int, j.Value('0'))
}

fn test_recovers_bootstrap_region() { verify_original_runtime('test_recovers_bootstrap_region') }

fn test_rejects_incomplete_bootstrap_region() {
	verify_original_runtime('test_rejects_incomplete_bootstrap_region')
}

fn test_recovers_bootstrap_root_mappings() {
	verify_original_runtime('test_recovers_bootstrap_root_mappings')
}

fn test_rejects_incomplete_bootstrap_root_mappings() {
	verify_original_runtime('test_rejects_incomplete_bootstrap_root_mappings')
}

fn test_recovers_small_shared_data() { verify_original_runtime('test_recovers_small_shared_data') }

fn test_rejects_incomplete_small_shared_data() {
	verify_original_runtime('test_rejects_incomplete_small_shared_data')
}

fn test_recovers_runtime_controls() { verify_original_runtime('test_recovers_runtime_controls') }

fn test_rejects_incomplete_runtime_controls() {
	verify_original_runtime('test_rejects_incomplete_runtime_controls')
}

fn test_recovers_runtime_initialization() {
	verify_original_runtime('test_recovers_runtime_initialization')
}

fn test_rejects_incomplete_runtime_initialization() {
	verify_original_runtime('test_rejects_incomplete_runtime_initialization')
}

fn test_recovers_zeroed_runtime_power_policy() {
	verify_original_runtime('test_recovers_zeroed_runtime_power_policy')
}

fn test_rejects_nonzero_runtime_power_policy_producer() {
	verify_original_runtime('test_rejects_nonzero_runtime_power_policy_producer')
}

fn test_recovers_zeroed_runtime_performance_policy() {
	verify_original_runtime('test_recovers_zeroed_runtime_performance_policy')
}

fn test_rejects_incomplete_runtime_performance_policy_clear() {
	verify_original_runtime('test_rejects_incomplete_runtime_performance_policy_clear')
}

fn test_recovers_runtime_platform_policy() {
	verify_original_runtime('test_recovers_runtime_platform_policy')
}

fn test_rejects_wrong_runtime_platform_policy_vtable() {
	verify_original_runtime('test_rejects_wrong_runtime_platform_policy_vtable')
}

fn test_recovers_zero_initialized_allocations() {
	verify_original_runtime('test_recovers_zero_initialized_allocations')
}

fn test_rejects_incomplete_zero_initialized_allocations() {
	verify_original_runtime('test_rejects_incomplete_zero_initialized_allocations')
}

fn test_recovers_role0_bootstrap_regions() {
	verify_original_runtime('test_recovers_role0_bootstrap_regions')
}

fn test_rejects_incomplete_role0_bootstrap_regions() {
	verify_original_runtime('test_rejects_incomplete_role0_bootstrap_regions')
}

fn test_recovers_g17_shared_platform_values() {
	verify_original_runtime('test_recovers_g17_shared_platform_values')
}

fn test_rejects_wrong_shared_platform_value_vtable() {
	verify_original_runtime('test_rejects_wrong_shared_platform_value_vtable')
}

fn test_recovers_g17_address_space_layout() {
	verify_original_runtime('test_recovers_g17_address_space_layout')
}

fn test_rejects_g17_address_space_layout_with_legacy_csc_provider() {
	verify_original_runtime('test_rejects_g17_address_space_layout_with_legacy_csc_provider')
}

fn test_recovers_g17_color_matrices() {
	verify_original_runtime('test_recovers_g17_color_matrices')
}

fn test_recovers_g17_hardware_config_constants() {
	verify_original_runtime('test_recovers_g17_hardware_config_constants')
}

fn test_recovers_g17_chip_info() { verify_original_runtime('test_recovers_g17_chip_info') }

fn test_recovers_g17_power_sample_period() {
	verify_original_runtime('test_recovers_g17_power_sample_period')
}

fn test_recovers_g17_default_mcache_writes() {
	verify_original_runtime('test_recovers_g17_default_mcache_writes')
}

fn test_recovers_g17_enabled_usc_config() {
	verify_original_runtime('test_recovers_g17_enabled_usc_config')
}

fn test_recovers_g17_setup_config_constants() {
	verify_original_runtime('test_recovers_g17_setup_config_constants')
}

fn test_recovers_g17_uat_config_flag() {
	verify_original_runtime('test_recovers_g17_uat_config_flag')
}

fn test_recovers_g17_gptbat_base() { verify_original_runtime('test_recovers_g17_gptbat_base') }

fn test_recovers_g17_gpu_identity_config() {
	verify_original_runtime('test_recovers_g17_gpu_identity_config')
}

fn test_recovers_g17_feature_defaults() {
	verify_original_runtime('test_recovers_g17_feature_defaults')
}

fn test_recovers_g17_constant_virtual_returns() {
	verify_original_runtime('test_recovers_g17_constant_virtual_returns')
}

fn test_rejects_changed_g17_constant_virtual_return() {
	verify_original_runtime('test_rejects_changed_g17_constant_virtual_return')
}

fn test_recovers_g17_memory_map_virtual_address() {
	verify_original_runtime('test_recovers_g17_memory_map_virtual_address')
}

fn test_recovers_g17_pio_mappings() { verify_original_runtime('test_recovers_g17_pio_mappings') }

fn test_rejects_modified_g17_pio_source_producer() {
	verify_original_runtime('test_rejects_modified_g17_pio_source_producer')
}

fn test_recovers_g17_pio_uat_mapping() {
	verify_original_runtime('test_recovers_g17_pio_uat_mapping')
}

fn test_rejects_modified_g17_pio_uat_range() {
	verify_original_runtime('test_rejects_modified_g17_pio_uat_range')
}

fn test_direct_callers_keep_symbol_ownership_and_typed_targets() {
	records := j.decode(os.read_file(os.join_path(os.dir(@FILE), 'fixtures/caller-boundaries.json')) or { panic(err) }) or { panic(err) }
	for entry in records.arr() {
		row := entry.as_map()
		request := at(row, 'request').as_map()
		image := hex.decode(text(request, 'image')) or { panic(err) }
		before := image.clone()
		result := query(image, 'find_direct_symbol_callers', request) or { panic(err) }
		assert j.decode(j.encode(result, false)) or { panic(err) } == at(row, 'result')
		assert image == before
	}
}

fn test_direct_callers_clip_unsigned_segment_spans_without_narrowing() {
	rows := j.decode(os.read_file(os.join_path(os.dir(@FILE), 'fixtures/caller-segment-boundaries.json')) or { panic(err) }) or { panic(err) }
	for value in rows.arr() {
		row := value.as_map()
		request := at(row, 'request').as_map()
		data := hex.decode(text(request, 'image')) or { panic(err) }
		before := data.clone()
		result := runtime_direct_callers(data, at(request, 'target')) or { panic(err) }
		assert result == at(row, 'result').arr().map(j.string_value(it))
		assert data == before
	}
}

module g17expr

import encoding.hex
import g17decode as arm
import g17power as power
import traceanalysis as j

// All images remain borrowed for this synchronous composition. Nested outputs
// own their maps and arrays and never retain reader/provider storage.
struct ControllerImages {
	inputs  map[string][]u8
	encoded map[string]string
}

fn (context ControllerImages) input(value j.Value) []u8 {
	return context.inputs[j.string_value(value)]
}

fn (context ControllerImages) hex_value(value j.Value) string {
	return context.encoded[j.string_value(value)]
}

fn (context ControllerImages) code(image j.Value, name j.Value) !j.Value {
	address, code := DriverImage{context.input(image)}.code(j.string_value(name))!
	return j.Value([j.Value(address), j.Value(hex.encode(code))])
}

fn (context ControllerImages) uuid(image j.Value) !j.Value {
	return arm.macho_uuid(context.input(image))
}

fn (context ControllerImages) runtime_codes(image j.Value) !j.Value {
	mut result := map[string]j.Value{}
	for _, entry in runtime_accessors().as_map() {
		name := entry.arr()[0]
		code := context.code(image, name)!
		result[j.string_value(name)] = code.arr()[1]
	}
	override_name := controller_value('G17_ADD_REGISTER_OVERRIDE')
	override_code := context.code(image, override_name)!
	result[j.string_value(override_name)] = override_code.arr()[1]
	return expr(result)
}

fn (context ControllerImages) dpe_symbol(image j.Value, target j.Value) !j.Value {
	name := controller_value('POPULATE_DPE_PPT_CONFIG')
	symbols := arm.macho_symbols(context.input(image))!
	if symbols[j.string_value(name)] or { return error('could not resolve the G17 DPE/PPT producer symbol') } != target.u64() {
		return error('could not resolve the G17 DPE/PPT producer symbol')
	}
	return name
}

fn controller_item(value j.Value, key j.Value) j.Value {
	if value is []j.Value { return value[key.int()] }
	return at(value.as_map(), j.string_value(key))
}

fn controller_put(mut target j.Value, keys []string, value j.Value) {
	mut result := target.as_map().clone()
	if keys.len == 1 {
		result[keys[0]] = value
	} else {
		mut child := at(result, keys[0])
		controller_put(mut child, keys[1..], value)
		result[keys[0]] = child
	}
	target = expr(result)
}

fn (context ControllerImages) invoke(operation string, values map[string]j.Value) !j.Value {
	match operation {
		'explain_g17_3d_common_boolean_accounting' {
			return query([]u8{}, operation, {
				'render_payload':     at(values, 'render_payload')
				'common_passthrough': at(values, 'common_passthrough')
			})
		}
		'recover_device_control_ring_bindings' {
			return query([]u8{}, operation, {
				'allocations': at(values, 'allocations')
				'code':        at(values, 'code')
			})
		}
		'recover_driver_accelerator_layouts' {
			return query(context.input(at(values, 'image')), operation, map[string]j.Value{})
		}
		'recover_driver_hardware_config_layout' {
			return query([]u8{}, operation, {
				'base_init_code':  at(values, 'base_init_code')
				'base_power_code': at(values, 'base_power_code')
				'arm_power_code':  at(values, 'arm_power_code')
			})
		}
		'recover_driver_root' {
			return query([]u8{}, operation, {
				'code': at(values, 'code')
			})
		}
		'recover_firmware_allocations' {
			return query(context.input(at(values, 'image')), operation, {
				'address': at(values, 'address')
				'code':    at(values, 'code')
			})
		}
		'recover_firmware_root' {
			return query([]u8{}, operation, {
				'code': at(values, 'code')
			})
		}
		'recover_firmware_shared_data_layout' {
			return query([]u8{}, operation, {
				'allocations': at(values, 'allocations')
				'shared_code': at(values, 'shared_code')
				'base_code':   at(values, 'base_code')
			})
		}
		'recover_firmware_shared_platform_fields' {
			return query([]u8{}, operation, {
				'code': at(values, 'code')
			})
		}
		'recover_g17_3d_command_reclamation' {
			return query(context.input(at(values, 'image')), operation, map[string]j.Value{})
		}
		'recover_g17_3d_common_passthrough' {
			return query(context.input(at(values, 'image')), operation, map[string]j.Value{})
		}
		'recover_g17_3d_descriptor_initialization' {
			return query(context.input(at(values, 'image')), operation, map[string]j.Value{})
		}
		'recover_g17_3d_register_lists' {
			return query(context.input(at(values, 'image')), operation, map[string]j.Value{})
		}
		'recover_g17_accelerator_channel_inputs' {
			return query(context.input(at(values, 'image')), operation, {
				'kernel_image':     j.Value(context.hex_value(at(values, 'kernel_image')))
				'iogpu_image':      j.Value(context.hex_value(at(values, 'iogpu_image')))
				'chip_info_decode': at(values, 'chip_info_decode')
			})
		}
		'recover_g17_address_space_layout' {
			return query(context.input(at(values, 'image')), operation, {
				'base_init_code': at(values, 'base_init_code')
			})
		}
		'recover_g17_afr_relative_boost_frequency_table' {
			return query(context.input(at(values, 'image')), operation, {
				'arm_power_code': at(values, 'arm_power_code')
			})
		}
		'recover_g17_akf_callback' {
			return query(context.input(at(values, 'driver')), operation, {
				'kernel': j.Value(context.hex_value(at(values, 'kernel')))
			})
		}
		'recover_g17_aux_performance_layout' {
			return query(context.input(at(values, 'image')), operation, {
				'arm_power_code': at(values, 'arm_power_code')
			})
		}
		'recover_g17_boot_transport' {
			return query([]u8{}, operation, {
				'notify_code':  at(values, 'notify_code')
				'receive_code': at(values, 'receive_code')
				'boot_code':    at(values, 'boot_code')
			})
		}
		'recover_g17_bootstrap_region' {
			return query([]u8{}, operation, {
				'allocation_code': at(values, 'allocation_code')
				'prepare_code':    at(values, 'prepare_code')
				'page_shift_code': at(values, 'page_shift_code')
				'set_64_pa_code':  at(values, 'set_64_pa_code')
				'set_64_code':     at(values, 'set_64_code')
				'set_32_code':     at(values, 'set_32_code')
			})
		}
		'recover_g17_bootstrap_roots' {
			return query([]u8{}, operation, {
				'allocation_code': at(values, 'allocation_code')
				'init_code':       at(values, 'init_code')
				'prepare_code':    at(values, 'prepare_code')
				'complete_code':   at(values, 'complete_code')
				'page_shift_code': at(values, 'page_shift_code')
			})
		}
		'recover_g17_brn_workaround_table' {
			return query(context.input(at(values, 'image')), operation, {
				'allocation_code': at(values, 'allocation_code')
			})
		}
		'recover_g17_channel_command_common_fields' {
			return query(context.input(at(values, 'image')), operation, map[string]j.Value{})
		}
		'recover_g17_channel_command_pools' {
			return query(context.input(at(values, 'image')), operation, map[string]j.Value{})
		}
		'recover_g17_channel_data_master_types' {
			return query(context.input(at(values, 'image')), operation, map[string]j.Value{})
		}
		'recover_g17_channel_identity' {
			return query(context.input(at(values, 'driver')), operation, {
				'iogpu': j.Value(context.hex_value(at(values, 'iogpu')))
			})
		}
		'recover_g17_channel_layout' {
			return query([]u8{}, operation, {
				'reset_code': at(values, 'reset_code')
				'write_code': at(values, 'write_code')
			})
		}
		'recover_g17_channel_pool_geometry' {
			return query([]u8{}, operation, {
				'code': at(values, 'code')
			})
		}
		'recover_g17_channel_priority' {
			return query(context.input(at(values, 'image')), operation, map[string]j.Value{})
		}
		'recover_g17_channel_runtime_resources' {
			return query(context.input(at(values, 'driver')), operation, {
				'iogpu': j.Value(context.hex_value(at(values, 'iogpu')))
			})
		}
		'recover_g17_channel_state_sources' {
			return query(context.input(at(values, 'image')), operation, {
				'reset_code': at(values, 'reset_code')
			})
		}
		'recover_g17_channel_submission_flag' {
			return query(context.input(at(values, 'image')), operation, map[string]j.Value{})
		}
		'recover_g17_channel_submit_info' {
			return query(context.input(at(values, 'image')), operation, map[string]j.Value{})
		}
		'recover_g17_chip_info' {
			return query(context.input(at(values, 'image')), operation, {
				'arm_init_code': at(values, 'arm_init_code')
			})
		}
		'recover_g17_chip_info_decode' {
			return query(context.input(at(values, 'image')), operation, map[string]j.Value{})
		}
		'recover_g17_chip_info_registers' {
			return query(context.input(at(values, 'image')), operation, map[string]j.Value{})
		}
		'recover_g17_color_matrices' {
			return query(context.input(at(values, 'image')), operation, map[string]j.Value{})
		}
		'recover_g17_command_pool_backing' {
			return query(context.input(at(values, 'image')), operation, map[string]j.Value{})
		}
		'recover_g17_command_stream_format' {
			return query(context.input(at(values, 'image')), operation, map[string]j.Value{})
		}
		'recover_g17_constant_virtual_returns' {
			return query(context.input(at(values, 'image')), operation, map[string]j.Value{})
		}
		'recover_g17_core_count_gate' {
			return query(context.input(at(values, 'image')), operation, map[string]j.Value{})
		}
		'recover_g17_data_master_doorbells' {
			return query(context.input(at(values, 'image')), operation, map[string]j.Value{})
		}
		'recover_g17_data_master_ring_bindings' {
			return query([]u8{}, operation, {
				'allocations_text': j.Value(j.encode(at(values, 'allocations'), false))
				'init_code':        at(values, 'init_code')
			})
		}
		'recover_g17_default_mcache_writes' {
			return query(context.input(at(values, 'image')), operation, {
				'arm_init_code': at(values, 'arm_init_code')
			})
		}
		'recover_g17_enabled_usc_config' {
			return query(context.input(at(values, 'image')), operation, {
				'arm_init_code': at(values, 'arm_init_code')
			})
		}
		'recover_g17_firmware_event_ring' {
			return query(context.input(at(values, 'driver')), operation, {
				'iogpu':     j.Value(context.hex_value(at(values, 'iogpu')))
				'iosurface': j.Value(context.hex_value(at(values, 'iosurface')))
			})
		}
		'recover_g17_gptbat_base' {
			return query(context.input(at(values, 'image')), operation, {
				'arm_init_code': at(values, 'arm_init_code')
			})
		}
		'recover_g17_gpu_identity_config' {
			return query(context.input(at(values, 'image')), operation, {
				'base_init_code': at(values, 'base_init_code')
			})
		}
		'recover_g17_handoff' {
			return query(hex.decode(j.string_value(at(values, 'code')))!, operation, map[string]j.Value{})
		}
		'recover_g17_hardware_config_constants' {
			return query(context.input(at(values, 'image')), operation, {
				'base_init_code': at(values, 'base_init_code')
				'arm_init_code':  at(values, 'arm_init_code')
			})
		}
		'recover_g17_init_sequence_provider' {
			return query(context.input(at(values, 'image')), operation, map[string]j.Value{})
		}
		'recover_g17_inline_register_records' {
			return query(context.input(at(values, 'image')), operation, map[string]j.Value{})
		}
		'recover_g17_late_controls' {
			return query(context.input(at(values, 'image')), operation, map[string]j.Value{})
		}
		'recover_g17_linear_power_transfer_tables' {
			return expr(power.recover_linear_power_transfer_tables(context.input(at(values, 'image')), hex.decode(j.string_value(at(values, 'arm_power_code')))!)!)
		}
		'recover_g17_memory_map_virtual_address' {
			return query(context.input(at(values, 'driver')), operation, {
				'iogpu': j.Value(context.hex_value(at(values, 'iogpu')))
			})
		}
		'recover_g17_perf_state_map_block' {
			return query(context.input(at(values, 'image')), operation, {
				'arm_power_code': at(values, 'arm_power_code')
			})
		}
		'recover_g17_pio_mappings' {
			return query(context.input(at(values, 'image')), operation, map[string]j.Value{})
		}
		'recover_g17_pio_uat_mapping' {
			return query(context.input(at(values, 'image')), operation, map[string]j.Value{})
		}
		'recover_g17_platform_config' {
			return query(context.input(at(values, 'image')), operation, {
				'page_shift_code': at(values, 'page_shift_code')
			})
		}
		'recover_g17_power_sample_period' {
			return query(context.input(at(values, 'image')), operation, {
				'arm_init_code': at(values, 'arm_init_code')
			})
		}
		'recover_g17_queue_device_inputs' {
			return query(context.input(at(values, 'driver')), operation, {
				'iogpu': j.Value(context.hex_value(at(values, 'iogpu')))
			})
		}
		'recover_g17_random_provider' {
			return query(context.input(at(values, 'driver')), operation, {
				'kernel': j.Value(context.hex_value(at(values, 'kernel')))
			})
		}
		'recover_g17_register_emission_cfg' {
			return query(context.input(at(values, 'image')), operation, {
				'selectors':      at(values, 'selectors')
				'inline_records': at(values, 'inline_records')
			})
		}
		'recover_g17_register_entry_codec' {
			return query(context.input(at(values, 'image')), operation, map[string]j.Value{})
		}
		'recover_g17_register_selectors' {
			return query(context.input(at(values, 'image')), operation, map[string]j.Value{})
		}
		'recover_g17_relative_boost_frequency_table' {
			return query(context.input(at(values, 'image')), operation, {
				'arm_power_code': at(values, 'arm_power_code')
			})
		}
		'recover_g17_render_descriptor_fields' {
			return query(context.input(at(values, 'image')), operation, {
				'iogpu':               j.Value(context.hex_value(at(values, 'iogpu')))
				'render_payload_text': j.Value(j.encode(at(values, 'render_payload'), false))
			})
		}
		'recover_g17_render_payload_format' {
			return query(context.input(at(values, 'image')), operation, map[string]j.Value{})
		}
		'recover_g17_role0_bootstrap_regions' {
			return query([]u8{}, operation, {
				'code': at(values, 'code')
			})
		}
		'recover_g17_rtbuddy_endpoints' {
			return query([]u8{}, operation, {
				'read_code':     at(values, 'read_code')
				'send_code':     at(values, 'send_code')
				'matched_code':  at(values, 'matched_code')
				'enable_code':   at(values, 'enable_code')
				'received_code': at(values, 'received_code')
			})
		}
		'recover_g17_runtime_controls' {
			return query([]u8{}, operation, {
				'allocations_text': j.Value(j.encode(at(values, 'allocations'), false))
				'accessor_code':    at(values, 'accessor_code')
			})
		}
		'recover_g17_runtime_initialization' {
			return query([]u8{}, operation, {
				'allocations_text': j.Value(j.encode(at(values, 'allocations'), false))
				'base_init_code':   at(values, 'base_init_code')
				'arm_init_code':    at(values, 'arm_init_code')
				'base_power_code':  at(values, 'base_power_code')
				'arm_power_code':   at(values, 'arm_power_code')
			})
		}
		'recover_g17_runtime_performance_policy' {
			return query([]u8{}, operation, {
				'setup_code':     at(values, 'setup_code')
				'arm_power_code': at(values, 'arm_power_code')
			})
		}
		'recover_g17_runtime_platform_policy' {
			return query(context.input(at(values, 'image')), operation, map[string]j.Value{})
		}
		'recover_g17_runtime_power_policy' {
			return query(context.input(at(values, 'image')), operation, {
				'arm_power_code': at(values, 'arm_power_code')
				'populate_code':  at(values, 'populate_code')
			})
		}
		'recover_g17_scheduler_state' {
			return query(context.input(at(values, 'image')), operation, map[string]j.Value{})
		}
		'recover_g17_secondary_performance_block' {
			return query(context.input(at(values, 'image')), operation, map[string]j.Value{})
		}
		'recover_g17_setup_config_constants' {
			return query([]u8{}, operation, {
				'configure_code': at(values, 'configure_code')
				'arm_setup_code': at(values, 'arm_setup_code')
			})
		}
		'recover_g17_shared_platform_values' {
			return query(context.input(at(values, 'image')), operation, map[string]j.Value{})
		}
		'recover_g17_small_shared_data' {
			return query([]u8{}, operation, {
				'allocations_text':         j.Value(j.encode(at(values, 'allocations'), false))
				'shared_init_code':         at(values, 'shared_init_code')
				'base_init_code':           at(values, 'base_init_code')
				'ktrace_code':              at(values, 'ktrace_code')
				'wait_power_off_code':      at(values, 'wait_power_off_code')
				'wait_generation_code':     at(values, 'wait_generation_code')
				'snapshot_generation_code': at(values, 'snapshot_generation_code')
				'get_sleep_code':           at(values, 'get_sleep_code')
				'set_sleep_code':           at(values, 'set_sleep_code')
			})
		}
		'recover_g17_sram_power_scale_table' {
			return query(context.input(at(values, 'image')), operation, {
				'base_power_code': at(values, 'base_power_code')
				'arm_power_code':  at(values, 'arm_power_code')
			})
		}
		'recover_g17_static_power_scale_table' {
			return query(context.input(at(values, 'image')), operation, {
				'kernel_image':   j.Value(context.hex_value(at(values, 'kernel_image')))
				'arm_power_code': at(values, 'arm_power_code')
			})
		}
		'recover_g17_ta_render_passthrough' {
			return query(context.input(at(values, 'image')), operation, map[string]j.Value{})
		}
		'recover_g17_uat_config_flag' {
			return query(context.input(at(values, 'image')), operation, {
				'arm_init_code': at(values, 'arm_init_code')
			})
		}
		'recover_g17_unit_mask_field' {
			return query(context.input(at(values, 'image')), operation, map[string]j.Value{})
		}
		'recover_g17_zero_initialized_allocations' {
			return query([]u8{}, operation, {
				'code': at(values, 'code')
			})
		}
		'recover_hardware_config' {
			return query([]u8{}, operation, {
				'allocations': at(values, 'allocations')
				'shared_code': at(values, 'shared_code')
				'firmware':    j.Value(context.hex_value(at(values, 'firmware')))
			})
		}
		'recover_root_allocation_sizes' {
			return query([]u8{}, operation, {
				'allocations': at(values, 'allocations')
			})
		}
		'recover_vtable_target' {
			return arm.query(context.input(at(values, 'image')), operation, {
				'vtable_name': at(values, 'vtable_name')
				'slot':        at(values, 'slot')
			})
		}
		else { return error('unknown G17 controller operation ' + operation) }
	}
}

fn controller_uuid_text(value j.Value) string {
	if census_type(value) == 'NoneType' { return 'None' }
	return j.string_value(value)
}

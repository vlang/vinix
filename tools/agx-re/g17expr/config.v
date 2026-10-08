module g17expr

import g17decode as arm
import g17power as power
import math.big
import traceanalysis as j

fn config_handles(operation string) bool {
	return operation in ['recover_g17_relative_boost_frequency_table',
		'recover_g17_sram_power_scale_table', 'recover_g17_static_power_scale_table',
		'recover_g17_afr_relative_boost_frequency_table', 'recover_g17_perf_state_map_block',
		'recover_g17_aux_performance_layout', 'recover_g17_data_master_ring_bindings',
		'recover_g17_data_master_doorbells', 'recover_g17_channel_pool_geometry',
		'recover_g17_channel_priority', 'recover_g17_channel_submit_info',
		'recover_g17_channel_submission_flag', 'recover_g17_channel_layout',
		'recover_g17_secondary_performance_block', 'config_pointer_stores',
		'recover_g17_chip_info_registers', 'recover_g17_final_late_controls',
		'recover_g17_remaining_late_controls', 'recover_g17_cleared_accelerator_inputs',
		'recover_g17_unit_mask_field', 'recover_g17_core_count_gate', 'recover_g17_chip_info_decode',
		'recover_g17_core_mask_relay', 'recover_g17_late_controls']
}

fn config_check(code []u8, label string) ! {
	arm.require_instruction_words_at(code, label, config_words(label))!
}

fn config_seq(code []u8, label string) ! {
	arm.require_instruction_sequence(code, label, config_sequence(label))!
}

fn config_names(names []string) []string { return names.map(config_symbol(it)) }

fn config_required(image CommandImage, names []string) !map[string]big.Integer {
	symbols := image.symbols()!
	for name in config_names(names) {
		if name !in symbols { return error('Mach-O has no ' + name + ' symbol') }
	}
	return symbols
}

fn config_code(image CommandImage, name string, label string) ![]u8 {
	_, code := image.code(config_symbol(name))!
	config_check(code, label)!
	return code
}

fn config_provider(image CommandImage, symbols map[string]big.Integer, vtable string, slot int,
	name string, message string) !big.Integer {
	target := image.vtable(config_symbol(vtable), slot)!
	if target != symbols[config_symbol(name)] { return error(message + command_hex(target)) }
	return target
}

fn config_noop(image CommandImage, name string, message string) ! {
	_, code := image.code(config_symbol(name))!
	if code != encoded_words([u32(0xd503245f), 0xd65f03c0]) { return error(message) }
}

fn config_query(data []u8, operation string, request map[string]j.Value) !j.Value {
	if operation == 'config_pointer_stores' {
		limits := if 'bounds_text' in request {
			power.decode_device_json(text(request, 'bounds_text'))!.arr()
		} else {
			[at(request, 'low'), at(request, 'high')]
		}
		return j.Value(config_pointer_stores(runtime_bytes(request, 'code')!, limits[0], limits[1])!)
	}
	if operation == 'recover_g17_channel_pool_geometry' {
		return expr(channel_pool_geometry(runtime_bytes(request, 'code')!)!)
	}
	if operation == 'recover_g17_channel_layout' {
		return expr(channel_layout(runtime_bytes(request, 'reset_code')!, runtime_bytes(request, 'write_code')!)!)
	}
	if operation == 'recover_g17_data_master_ring_bindings' {
		return expr(data_master_ring_bindings(request)!)
	}
	image_key := if 'driver_fixture' in request { 'driver' } else { 'image' }
	image := command_image(data, request, image_key)!
	if operation in ['recover_g17_relative_boost_frequency_table', 'recover_g17_sram_power_scale_table',
		'recover_g17_static_power_scale_table', 'recover_g17_afr_relative_boost_frequency_table',
		'recover_g17_perf_state_map_block', 'recover_g17_aux_performance_layout',
		'recover_g17_secondary_performance_block'] {
		return expr(config_performance(image, operation, request, image_key)!)
	}
	if operation in ['recover_g17_data_master_doorbells', 'recover_g17_channel_priority',
		'recover_g17_channel_submit_info', 'recover_g17_channel_submission_flag'] {
		return expr(config_channel_contract(image, operation)!)
	}
	return expr(config_late(image, operation, request)!)
}

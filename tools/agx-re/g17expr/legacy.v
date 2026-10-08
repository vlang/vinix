module g17expr

import g17power as power
import traceanalysis as j

fn legacy_handles(operation string) bool {
	return operation in ['require_zeroed_accelerator_allocation',
		'recover_g17_accelerator_channel_inputs', 'recover_device_control_ring_bindings',
		'recover_ring_accessor', 'recover_entry_stride', 'recover_accelerator_command_fields',
		'recover_accelerator_command_contract', 'recover_data_master_submission_sequence',
		'recover_data_master_submission_protocol', 'recover_vector_copy_size',
		'recover_driver_accelerator_layouts', 'explain_g17_3d_common_boolean_accounting',
		'recover_g17_random_provider', 'feature_flag_set_bits']
}

fn legacy_source(data []u8, request map[string]j.Value, key string) !CommandImage {
	bytes := if data.len > 0 {
		data
	} else if key in request {
		runtime_bytes(request, key)!
	} else {
		[]u8{}
	}
	return command_image(bytes, request, key)
}

fn legacy_secondary(request map[string]j.Value, key string) !CommandImage {
	return legacy_source([]u8{}, request, key)
}

fn legacy_truth(value j.Value) bool {
	return match value {
		bool { value }
		string { value.len != 0 }
		[]j.Value { value.len != 0 }
		map[string]j.Value { value.len != 0 }
		else { census_type(value) != 'NoneType' && !event_values_equal(value, j.Value(0)) }
	}
}

fn legacy_query(data []u8, operation string, request map[string]j.Value) !j.Value {
	if 'legacy_options_text' in request {
		return legacy_query(data, operation, power.decode_device_json(text(request, 'legacy_options_text'))!.as_map())
	}
	match operation {
		'recover_ring_accessor' { return ring_accessor(runtime_bytes(request, 'code')!) }
		'recover_entry_stride' { return j.Value(entry_stride(runtime_bytes(request, 'code')!)!) }
		'recover_accelerator_command_fields' {
			return accelerator_command_fields(runtime_bytes(request, 'code')!)
		}
		'recover_accelerator_command_contract' {
			return accelerator_command_contract(runtime_bytes(request, 'code')!)
		}
		'recover_data_master_submission_sequence' {
			return data_master_sequence(runtime_bytes(request, 'code')!, at(request, 'command_type'))
		}
		'recover_vector_copy_size' {
			return j.Value(vector_copy_size(runtime_bytes(request, 'code')!)!)
		}
		'recover_device_control_ring_bindings' {
			return device_control_bindings(runtime_allocations(request)!, runtime_bytes(request, 'code')!)
		}
		'explain_g17_3d_common_boolean_accounting' {
			return common_boolean_accounting(at(request, 'render_payload'), at(request, 'common_passthrough'))
		}
		'feature_flag_set_bits' {
			return j.Value(feature_flag_bits(runtime_bytes(request, 'code')!, at(request, 'recipe').arr())!)
		}
		'recover_driver_accelerator_layouts' {
			return driver_accelerator_layouts(legacy_source(data, request, 'image')!)
		}
		'recover_data_master_submission_protocol' {
			return data_master_protocol(legacy_source(data, request, 'image')!, at(request, 'next_entry_address'))
		}
		'require_zeroed_accelerator_allocation' {
			return zeroed_accelerator(legacy_source(data, request, 'image')!, legacy_secondary(request, 'kernel_image')!)
		}
		'recover_g17_accelerator_channel_inputs' {
			return channel_inputs(legacy_source(data, request, 'image')!, legacy_secondary(request, 'kernel_image')!, legacy_secondary(request, 'iogpu_image')!, at(request, 'chip_info_decode'), request)
		}
		'recover_g17_random_provider' {
			return random_provider(legacy_source(data, request, 'driver')!, legacy_secondary(request, 'kernel')!)
		}
		else { return error('unknown G17 legacy operation ' + operation) }
	}
}

fn legacy_values_equal(left j.Value, right j.Value) bool {
	if left is map[string]j.Value {
		if right is map[string]j.Value {
			if left.len != right.len { return false }
			for key, value in left {
				if key !in right || !legacy_values_equal(value, right[key]) { return false }
			}
			return true
		}
	}
	if left is []j.Value {
		if right is []j.Value {
			if left.len != right.len { return false }
			for index, value in left {
				if !legacy_values_equal(value, right[index]) { return false }
			}
			return true
		}
	}
	return event_values_equal(left, right)
}

fn legacy_iterable(value j.Value) ![]j.Value {
	return match value {
		[]j.Value { value }
		map[string]j.Value { mut keys := []j.Value{}; for key, _ in value { keys << j.Value(key) }; keys }
		string { value.runes().map(j.Value(it.str())) }
		else { return error("TypeError: '" + census_type(value) + "' object is not iterable") }
	}
}

fn legacy_length(value j.Value) !int {
	return match value {
		[]j.Value { value.len }
		map[string]j.Value { value.len }
		string { value.runes().len }
		else { return error("TypeError: object of type '" + census_type(value) + "' has no len()") }
	}
}

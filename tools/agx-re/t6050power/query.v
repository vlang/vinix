module t6050power

import traceanalysis as j

fn functions_from_json(value j.Value) !map[string]Function {
	mut functions := map[string]Function{}
	for name, encoded in value.as_map() {
		tuple := encoded.arr()
		if tuple.len != 2 { return error('function ${name} must contain an address and code') }
		functions[name] = Function{tuple[0], j.bytes_fromhex(j.string_value(j.value(tuple[1].as_map(), '$bytes')))!}
	}
	return functions
}

pub fn query(operation string, request map[string]j.Value) !j.Value {
	functions := functions_from_json(j.value(request, 'functions'))!
	result := match operation {
		'recover_apple_ptd_code_contract' {
			recover_apple_ptd_code_contract(functions, j.value(request, 'symbols').as_map())!
		}
		'recover_rtbuddy_segment_flag_contract' {
			recover_rtbuddy_segment_flag_contract(functions, j.value(request, 'symbols').as_map())!
		}
		'recover_iodart_family_code_contract' {
			recover_iodart_family_code_contract(functions, j.value(request, 'vtable_targets').as_map(), j.value(request, 'direction_lookup').arr())!
		}
		'recover_apple_t8110_dart_code_contract' {
			recover_apple_t8110_dart_code_contract(functions, j.value(request, 'bypass_property_prefix'), j.value(request, 'sid_property_format'))!
		}
		'recover_t8110_kernel_code_contract' {
			recover_t8110_kernel_code_contract(functions, j.value(request, 'index_masks').arr(), j.value(request, 'index_shifts').arr())!
		}
		else { return error('unknown T6050 recovery operation ${operation}') }
	}
	return j.Value(result)
}

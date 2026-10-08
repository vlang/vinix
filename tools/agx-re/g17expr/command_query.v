module g17expr

import encoding.hex
import traceanalysis as j
import g17power as power

fn command_handles(operation string) bool {
	return operation in ['recover_g17_command_stream_format', 'recover_g17_render_payload_format',
		'recover_g17_3d_common_passthrough', 'recover_g17_render_descriptor_fields',
		'recover_g17_ta_render_passthrough', 'recover_g17_3d_descriptor_initialization',
		'recover_g17_channel_command_common_fields', 'recover_g17_register_entry_codec',
		'build_g17_emission_cfg', 'recover_g17_register_emission_cfg', 'recover_g17_3d_register_lists',
		'recover_g17_channel_command_pools', 'recover_g17_command_pool_backing',
		'recover_g17_3d_command_reclamation', 'recover_g17_queue_device_inputs',
		'recover_g17_channel_runtime_resources', 'recover_g17_scheduler_state',
		'recover_g17_channel_state_sources', 'recover_g17_channel_data_master_types',
		'recover_g17_channel_identity', 'recover_g17_handoff', 'recover_g17_boot_transport',
		'recover_g17_rtbuddy_endpoints']
}

fn command_query(data []u8, operation string, request map[string]j.Value) !j.Value {
	if operation == 'build_g17_emission_cfg' {
		return expr(emission_cfg(request_instructions(request)!, event_offsets(at(request, 'event_offsets').arr())!)!)
	}
	if operation in ['recover_g17_boot_transport', 'recover_g17_rtbuddy_endpoints'] {
		return expr(transport_contract(operation, request)!)
	}
	if operation == 'recover_g17_handoff' {
		return expr(handoff_contract(if 'code' in request {
			hex.decode(text(request, 'code'))!
		} else {
			data
		})!)
	}
	primary := if 'driver_fixture' in request { 'driver' } else { 'image' }
	image := command_image(data, request, primary)!
	iogpu_data := if 'iogpu' in request { hex.decode(text(request, 'iogpu'))! } else { []u8{} }
	iogpu := command_image(iogpu_data, request, 'iogpu')!
	result := match operation {
		'recover_g17_3d_descriptor_initialization' { descriptor_defaults(image)! }
		'recover_g17_3d_common_passthrough' { common_passthrough(image)! }
		'recover_g17_ta_render_passthrough' { ta_passthrough(image)! }
		'recover_g17_render_descriptor_fields' {
			render_descriptor(image, iogpu, (if 'render_payload_text' in request {
				power.decode_device_json(text(request, 'render_payload_text'))!
			} else {
				at(request, 'render_payload')
			}).as_map())!
		}
		'recover_g17_command_pool_backing' { pool_backing(image)! }
		'recover_g17_channel_command_pools' { command_pools(image)! }
		'recover_g17_queue_device_inputs' { queue_device_inputs(image, iogpu)! }
		'recover_g17_scheduler_state' { scheduler_contract(image)! }
		'recover_g17_channel_data_master_types' { channel_master_types(image)! }
		'recover_g17_register_emission_cfg' {
			register_emission_cfg(image, at(request, 'selectors').as_map(), at(request, 'inline_records').as_map())!
		}
		else { simple_command_contract(image, iogpu, operation, request)! }
	}
	return expr(result)
}

module g17expr

import encoding.hex
import traceanalysis as j

fn controller_report(data []u8, request map[string]j.Value) !j.Value {
	mut inputs := map[string][]u8{}
	mut encoded := map[string]string{}
	inputs['driver'] = data
	encoded['driver'] = hex.encode(data)
	for name in ['kernel', 'firmware', 'iogpu', 'iosurface', 'rtbuddy'] {
		inputs[name] = runtime_bytes(request, name)!
		encoded[name] = text(request, name)
	}
	context := ControllerImages{inputs, encoded}
	mut driver := j.Value('driver')
	mut kernel := j.Value('kernel')
	mut firmware := j.Value('firmware')
	mut iogpu := j.Value('iogpu')
	mut iosurface := j.Value('iosurface')
	mut rtbuddy := j.Value('rtbuddy')
	mut driver_uuid := context.uuid(driver)!
	mut firmware_uuid := context.uuid(firmware)!
	mut rtbuddy_uuid := context.uuid(rtbuddy)!
	if driver_uuid != controller_value('DRIVER_UUID') {
		return error('unsupported AGXG17X UUID ' + controller_uuid_text(driver_uuid))
	}
	if firmware_uuid != controller_value('FIRMWARE_UUID') {
		return error('unsupported G17 firmware UUID ' + controller_uuid_text(firmware_uuid))
	}
	if rtbuddy_uuid != controller_value('RTBUDDY_UUID') {
		return error('unsupported G17 RTBuddy UUID ' + controller_uuid_text(rtbuddy_uuid))
	}
	symbol_2009 := context.code(driver, controller_value('INIT_FIRMWARE_DATA'))!
	mut function_address := symbol_2009.arr()[0]
	mut function := symbol_2009.arr()[1]
	mut driver_root := context.invoke('recover_driver_root', {
		'code': function
	})!
	controller_put(mut driver_root, ['function'], controller_value('INIT_FIRMWARE_DATA'))
	controller_put(mut driver_root, ['function_address'], function_address)
	mut accelerator := context.invoke('recover_driver_accelerator_layouts', {
		'image': driver
	})!
	mut init_sequence_provider := context.invoke('recover_g17_init_sequence_provider', {
		'image': driver
	})!
	symbol_2015 := context.code(driver, controller_value('INIT_UAT_HANDOFF'))!
	mut handoff_code := symbol_2015.arr()[1]
	mut handoff := context.invoke('recover_g17_handoff', {
		'code': handoff_code
	})!
	symbol_2017 := context.code(driver, controller_value('ALLOC_ARM_FIRMWARE_DATA'))!
	mut arm_allocation_code := symbol_2017.arr()[1]
	symbol_2018 := context.code(driver, controller_value('PREPARE_FIRMWARE_DATA'))!
	mut prepare_data_code := symbol_2018.arr()[1]
	symbol_2019 := context.code(driver, controller_value('COMPLETE_FIRMWARE_DATA'))!
	mut complete_data_code := symbol_2019.arr()[1]
	symbol_2020 := context.code(driver, controller_value('PREPARE_FIRMWARE_BOOT'))!
	mut prepare_code := symbol_2020.arr()[1]
	symbol_2021 := context.code(driver, controller_value('NOTIFY_FIRMWARE_STARTED'))!
	mut notify_started_code := symbol_2021.arr()[1]
	symbol_2022 := context.code(driver, controller_value('RECEIVED_MESSAGE_FROM_AKF'))!
	mut received_akf_code := symbol_2022.arr()[1]
	symbol_2023 := context.code(driver, controller_value('BOOT_FIRMWARE'))!
	mut boot_firmware_code := symbol_2023.arr()[1]
	mut boot_transport := context.invoke('recover_g17_boot_transport', {
		'notify_code':  notify_started_code
		'receive_code': received_akf_code
		'boot_code':    boot_firmware_code
	})!
	controller_put(mut boot_transport, ['callback_dispatch'], context.invoke('recover_g17_akf_callback', {
		'driver': driver
		'kernel': kernel
	})!)
	controller_put(mut boot_transport, ['callback_dispatch', 'firmware_event_ring'], context.invoke('recover_g17_firmware_event_ring', {
		'driver':    driver
		'iogpu':     iogpu
		'iosurface': iosurface
	})!)
	mut rtbuddy_endpoints := context.invoke('recover_g17_rtbuddy_endpoints', {
		'read_code':     controller_item(context.code(rtbuddy, controller_value('RTBUDDY_READ_MESSAGE'))!, j.Value(1))
		'send_code':     controller_item(context.code(rtbuddy, controller_value('RTBUDDY_SEND_MESSAGE_GATED'))!, j.Value(1))
		'matched_code':  controller_item(context.code(rtbuddy, controller_value('RTBUDDY_MATCHED_ENDPOINT_GATED'))!, j.Value(1))
		'enable_code':   controller_item(context.code(rtbuddy, controller_value('RTBUDDY_ENABLE_ENDPOINTS'))!, j.Value(1))
		'received_code': controller_item(context.code(rtbuddy, controller_value('RTBUDDY_RECEIVED_MESSAGE'))!, j.Value(1))
	})!
	symbol_2040 := context.code(driver, controller_value('ARM_FIRMWARE_PAGE_SHIFT'))!
	mut page_shift_code := symbol_2040.arr()[1]
	symbol_2041 := context.code(driver, controller_value('SET_INIT_REGISTER_64_PA'))!
	mut set_64_pa_code := symbol_2041.arr()[1]
	symbol_2042 := context.code(driver, controller_value('SET_INIT_REGISTER_64'))!
	mut set_64_code := symbol_2042.arr()[1]
	symbol_2043 := context.code(driver, controller_value('SET_INIT_REGISTER_32'))!
	mut set_32_code := symbol_2043.arr()[1]
	mut bootstrap_region := context.invoke('recover_g17_bootstrap_region', {
		'allocation_code': arm_allocation_code
		'prepare_code':    prepare_code
		'page_shift_code': page_shift_code
		'set_64_pa_code':  set_64_pa_code
		'set_64_code':     set_64_code
		'set_32_code':     set_32_code
	})!
	controller_put(mut bootstrap_region, ['accelerator_provider'], init_sequence_provider)
	mut bootstrap_roots := context.invoke('recover_g17_bootstrap_roots', {
		'allocation_code': arm_allocation_code
		'init_code':       function
		'prepare_code':    prepare_data_code
		'complete_code':   complete_data_code
		'page_shift_code': page_shift_code
	})!
	mut platform_config := context.invoke('recover_g17_platform_config', {
		'image':           driver
		'page_shift_code': page_shift_code
	})!
	symbol_2061 := context.code(driver, controller_value('ALLOC_FIRMWARE_DATA'))!
	mut allocation_address := symbol_2061.arr()[0]
	mut allocation_code := symbol_2061.arr()[1]
	mut allocations := context.invoke('recover_firmware_allocations', {
		'image':   driver
		'address': allocation_address
		'code':    allocation_code
	})!
	mut brn_workaround_table := context.invoke('recover_g17_brn_workaround_table', {
		'image':           driver
		'allocation_code': allocation_code
	})!
	for item in allocations.arr() {
		if event_values_equal(at(item.as_map(), 'host_gpu_member'), j.Value(0x338)) {
			return error('zero-sized firmware BRN table was unexpectedly allocated')
		}
	}
	mut appended_allocations := allocations.arr().clone()
	appended_allocations << expr({
		'host_cpu_member': controller_item(brn_workaround_table, j.Value('host_cpu_member'))
		'host_gpu_member': controller_item(brn_workaround_table, j.Value('host_gpu_member'))
		'bytes':           controller_item(brn_workaround_table, j.Value('bytes'))
	})
	allocations = j.Value(appended_allocations)
	mut root_allocation_sizes := context.invoke('recover_root_allocation_sizes', {
		'allocations': allocations
	})!
	symbol_2078 := context.code(driver, controller_value('INIT_BASE_FIRMWARE_DATA'))!
	mut base_init_code := symbol_2078.arr()[1]
	symbol_2079 := context.code(driver, controller_value('BASE_CONFIGURE_DEVICE'))!
	mut configure_code := symbol_2079.arr()[1]
	mut zero_initialized_allocations := context.invoke('recover_g17_zero_initialized_allocations', {
		'code': base_init_code
	})!
	mut role0_bootstrap_regions := context.invoke('recover_g17_role0_bootstrap_regions', {
		'code': base_init_code
	})!
	controller_put(mut accelerator, ['device_control_bindings'], context.invoke('recover_device_control_ring_bindings', {
		'allocations': allocations
		'code':        base_init_code
	})!)
	symbol_2087 := context.code(driver, controller_value('RESET_CHANNEL_STATE'))!
	mut reset_channel_code := symbol_2087.arr()[1]
	symbol_2088 := context.code(driver, controller_value('WRITE_CHANNEL_COMMAND_POINTER'))!
	mut write_channel_code := symbol_2088.arr()[1]
	mut channels := context.invoke('recover_g17_channel_layout', {
		'reset_code': reset_channel_code
		'write_code': write_channel_code
	})!
	controller_put(mut channels, ['pools'], context.invoke('recover_g17_channel_pool_geometry', {
		'code': allocation_code
	})!)
	controller_put(mut channels, ['state_sources'], context.invoke('recover_g17_channel_state_sources', {
		'image':      driver
		'reset_code': reset_channel_code
	})!)
	controller_put(mut channels, ['priority'], context.invoke('recover_g17_channel_priority', {
		'image': driver
	})!)
	controller_put(mut channels, ['submit_info'], context.invoke('recover_g17_channel_submit_info', {
		'image': driver
	})!)
	controller_put(mut channels, ['submission_flag'], context.invoke('recover_g17_channel_submission_flag', {
		'image': driver
	})!)
	controller_put(mut channels, ['data_master_types'], context.invoke('recover_g17_channel_data_master_types', {
		'image': driver
	})!)
	controller_put(mut channels, ['data_master_rings'], context.invoke('recover_g17_data_master_ring_bindings', {
		'allocations': allocations
		'init_code':   base_init_code
	})!)
	controller_put(mut channels, ['data_master_doorbells'], context.invoke('recover_g17_data_master_doorbells', {
		'image': driver
	})!)
	controller_put(mut channels, ['identity'], context.invoke('recover_g17_channel_identity', {
		'driver': driver
		'iogpu':  iogpu
	})!)
	controller_put(mut channels, ['scheduler_state'], context.invoke('recover_g17_scheduler_state', {
		'image': driver
	})!)
	controller_put(mut channels, ['queue_device_inputs'], context.invoke('recover_g17_queue_device_inputs', {
		'driver': driver
		'iogpu':  iogpu
	})!)
	controller_put(mut channels, ['runtime_resources'], context.invoke('recover_g17_channel_runtime_resources', {
		'driver': driver
		'iogpu':  iogpu
	})!)
	controller_put(mut channels, ['command_pools'], context.invoke('recover_g17_channel_command_pools', {
		'image': driver
	})!)
	controller_put(mut channels, ['command_pools', 'backing'], context.invoke('recover_g17_command_pool_backing', {
		'image': driver
	})!)
	controller_put(mut channels, ['command_3d_reclamation'], context.invoke('recover_g17_3d_command_reclamation', {
		'image': driver
	})!)
	controller_put(mut channels, ['command_common_fields'], context.invoke('recover_g17_channel_command_common_fields', {
		'image': driver
	})!)
	controller_put(mut channels, ['command_3d_register_lists'], context.invoke('recover_g17_3d_register_lists', {
		'image': driver
	})!)
	controller_put(mut channels, ['register_entry_codec'], context.invoke('recover_g17_register_entry_codec', {
		'image': driver
	})!)
	controller_put(mut channels, ['constant_virtual_returns'], context.invoke('recover_g17_constant_virtual_returns', {
		'image': driver
	})!)
	controller_put(mut channels, ['memory_map_virtual_address'], context.invoke('recover_g17_memory_map_virtual_address', {
		'driver': driver
		'iogpu':  iogpu
	})!)
	controller_put(mut channels, ['random_provider'], context.invoke('recover_g17_random_provider', {
		'driver': driver
		'kernel': kernel
	})!)
	mut register_selectors := context.invoke('recover_g17_register_selectors', {
		'image': driver
	})!
	mut inline_register_records := context.invoke('recover_g17_inline_register_records', {
		'image': driver
	})!
	controller_put(mut channels, ['register_selectors'], register_selectors)
	controller_put(mut channels, ['inline_register_records'], inline_register_records)
	mut register_emission_cfg := context.invoke('recover_g17_register_emission_cfg', {
		'image':          driver
		'selectors':      register_selectors
		'inline_records': inline_register_records
	})!
	controller_put(mut register_selectors, ['selector_formulas_complete'], controller_item(inline_register_records, j.Value('all_inline_forms_located')))
	controller_put(mut inline_register_records, ['control_flow_complete'], controller_item(register_emission_cfg, j.Value('predicate_expressions_complete')))
	controller_put(mut channels, ['register_selectors'], register_selectors)
	controller_put(mut channels, ['inline_register_records'], inline_register_records)
	controller_put(mut channels, ['register_emission_cfg'], register_emission_cfg)
	controller_put(mut channels, ['command_stream_format'], context.invoke('recover_g17_command_stream_format', {
		'image': driver
	})!)
	mut render_payload_format := context.invoke('recover_g17_render_payload_format', {
		'image': driver
	})!
	controller_put(mut channels, ['render_payload_format'], render_payload_format)
	controller_put(mut channels, ['descriptor_render_command_fields'], context.invoke('recover_g17_render_descriptor_fields', {
		'image':          driver
		'iogpu':          iogpu
		'render_payload': render_payload_format
	})!)
	mut descriptor_3d_common := context.invoke('recover_g17_3d_common_passthrough', {
		'image': driver
	})!
	controller_put(mut descriptor_3d_common, ['boolean_accounting'], context.invoke('explain_g17_3d_common_boolean_accounting', {
		'render_payload':     render_payload_format
		'common_passthrough': descriptor_3d_common
	})!)
	controller_put(mut channels, ['descriptor_3d_common_passthrough'], descriptor_3d_common)
	controller_put(mut channels, ['descriptor_ta_render_passthrough'], context.invoke('recover_g17_ta_render_passthrough', {
		'image': driver
	})!)
	controller_put(mut channels, ['descriptor_3d_initialization'], context.invoke('recover_g17_3d_descriptor_initialization', {
		'image': driver
	})!)
	symbol_2172 := context.code(driver, controller_value('INIT_BASE_POWER_DATA'))!
	mut base_power_code := symbol_2172.arr()[1]
	symbol_2173 := context.code(driver, controller_value('INIT_POWER_DATA'))!
	mut power_code := symbol_2173.arr()[1]
	symbol_2174 := context.code(driver, controller_value('SETUP_CONFIG'))!
	mut setup_code := symbol_2174.arr()[1]
	symbol_2175 := context.code(driver, controller_value('INIT_FIRMWARE_SHARED_DATA'))!
	mut shared_init_code := symbol_2175.arr()[1]
	symbol_2176 := context.code(driver, controller_value('KTRACE_FIRMWARE_CALLBACK'))!
	mut ktrace_code := symbol_2176.arr()[1]
	symbol_2177 := context.code(driver, controller_value('WAIT_FIRMWARE_POWER_OFF'))!
	mut wait_power_off_code := symbol_2177.arr()[1]
	symbol_2178 := context.code(driver, controller_value('WAIT_NEXT_ASC_POWER_GENERATION'))!
	mut wait_generation_code := symbol_2178.arr()[1]
	symbol_2181 := context.code(driver, controller_value('SNAPSHOT_ASC_POWER_GENERATION'))!
	mut snapshot_generation_code := symbol_2181.arr()[1]
	symbol_2184 := context.code(driver, controller_value('GET_SYSTEM_SLEEP_NOTIFICATION'))!
	mut get_sleep_code := symbol_2184.arr()[1]
	symbol_2185 := context.code(driver, controller_value('SET_SYSTEM_SLEEP_NOTIFICATION'))!
	mut set_sleep_code := symbol_2185.arr()[1]
	mut small_shared_data := context.invoke('recover_g17_small_shared_data', {
		'allocations':              allocations
		'shared_init_code':         shared_init_code
		'base_init_code':           base_init_code
		'ktrace_code':              ktrace_code
		'wait_power_off_code':      wait_power_off_code
		'wait_generation_code':     wait_generation_code
		'snapshot_generation_code': snapshot_generation_code
		'get_sleep_code':           get_sleep_code
		'set_sleep_code':           set_sleep_code
	})!
	mut runtime_controls := context.invoke('recover_g17_runtime_controls', {
		'allocations':   allocations
		'accessor_code': context.runtime_codes(driver)!
	})!
	mut runtime_initialization := context.invoke('recover_g17_runtime_initialization', {
		'allocations':     allocations
		'base_init_code':  base_init_code
		'arm_init_code':   function
		'base_power_code': base_power_code
		'arm_power_code':  power_code
	})!
	mut dpe_ppt_target := context.invoke('recover_vtable_target', {
		'image':       driver
		'vtable_name': controller_value('G17_ACCELERATOR_VTABLE')
		'slot':        j.Value(3456)
	})!
	mut dpe_ppt_symbol := context.dpe_symbol(driver, dpe_ppt_target)!
	symbol_2229 := context.code(driver, dpe_ppt_symbol)!
	mut dpe_ppt_code := symbol_2229.arr()[1]
	mut runtime_power_policy := context.invoke('recover_g17_runtime_power_policy', {
		'image':          driver
		'arm_power_code': power_code
		'populate_code':  dpe_ppt_code
	})!
	mut runtime_performance_policy := context.invoke('recover_g17_runtime_performance_policy', {
		'setup_code':     setup_code
		'arm_power_code': power_code
	})!
	mut runtime_platform_policy := context.invoke('recover_g17_runtime_platform_policy', {
		'image': driver
	})!
	mut firmware_shared_data := context.invoke('recover_firmware_shared_data_layout', {
		'allocations': allocations
		'shared_code': shared_init_code
		'base_code':   base_init_code
	})!
	controller_put(mut firmware_shared_data, ['platform_fields'], context.invoke('recover_firmware_shared_platform_fields', {
		'code': function
	})!)
	controller_put(mut firmware_shared_data, ['platform_values'], context.invoke('recover_g17_shared_platform_values', {
		'image': driver
	})!)
	mut hardware_config := context.invoke('recover_hardware_config', {
		'allocations': allocations
		'shared_code': shared_init_code
		'firmware':    firmware
	})!
	controller_put(mut hardware_config, ['host_layout'], context.invoke('recover_driver_hardware_config_layout', {
		'base_init_code':  base_init_code
		'base_power_code': base_power_code
		'arm_power_code':  power_code
	})!)
	controller_put(mut hardware_config, ['address_space_layout'], context.invoke('recover_g17_address_space_layout', {
		'image':          driver
		'base_init_code': base_init_code
	})!)
	controller_put(mut hardware_config, ['color_matrices'], context.invoke('recover_g17_color_matrices', {
		'image': driver
	})!)
	controller_put(mut hardware_config, ['fixed_constants'], context.invoke('recover_g17_hardware_config_constants', {
		'image':          driver
		'base_init_code': base_init_code
		'arm_init_code':  function
	})!)
	controller_put(mut hardware_config, ['setup_constants'], context.invoke('recover_g17_setup_config_constants', {
		'configure_code': configure_code
		'arm_setup_code': setup_code
	})!)
	controller_put(mut hardware_config, ['chip_info'], context.invoke('recover_g17_chip_info', {
		'image':         driver
		'arm_init_code': function
	})!)
	controller_put(mut hardware_config, ['power_sample_period'], context.invoke('recover_g17_power_sample_period', {
		'image':         driver
		'arm_init_code': function
	})!)
	controller_put(mut hardware_config, ['default_mcache_writes'], context.invoke('recover_g17_default_mcache_writes', {
		'image':         driver
		'arm_init_code': function
	})!)
	controller_put(mut hardware_config, ['enabled_usc_config'], context.invoke('recover_g17_enabled_usc_config', {
		'image':         driver
		'arm_init_code': function
	})!)
	controller_put(mut hardware_config, ['uat_config_flag'], context.invoke('recover_g17_uat_config_flag', {
		'image':         driver
		'arm_init_code': function
	})!)
	controller_put(mut hardware_config, ['gptbat_base'], context.invoke('recover_g17_gptbat_base', {
		'image':         driver
		'arm_init_code': function
	})!)
	controller_put(mut hardware_config, ['gpu_identity'], context.invoke('recover_g17_gpu_identity_config', {
		'image':          driver
		'base_init_code': base_init_code
	})!)
	controller_put(mut hardware_config, ['aux_performance_states'], context.invoke('recover_g17_aux_performance_layout', {
		'image':          driver
		'arm_power_code': power_code
	})!)
	controller_put(mut hardware_config, ['relative_boost_frequency_table'], context.invoke('recover_g17_relative_boost_frequency_table', {
		'image':          driver
		'arm_power_code': power_code
	})!)
	controller_put(mut hardware_config, ['sram_power_scale_table'], context.invoke('recover_g17_sram_power_scale_table', {
		'image':           driver
		'base_power_code': base_power_code
		'arm_power_code':  power_code
	})!)
	controller_put(mut hardware_config, ['static_power_scale_table'], context.invoke('recover_g17_static_power_scale_table', {
		'image':          driver
		'kernel_image':   kernel
		'arm_power_code': power_code
	})!)
	controller_put(mut hardware_config, ['afr_relative_boost_frequency_table'], context.invoke('recover_g17_afr_relative_boost_frequency_table', {
		'image':          driver
		'arm_power_code': power_code
	})!)
	controller_put(mut hardware_config, ['secondary_performance_block'], context.invoke('recover_g17_secondary_performance_block', {
		'image': driver
	})!)
	controller_put(mut hardware_config, ['unit_mask_field'], context.invoke('recover_g17_unit_mask_field', {
		'image': driver
	})!)
	controller_put(mut hardware_config, ['core_count_gate'], context.invoke('recover_g17_core_count_gate', {
		'image': driver
	})!)
	controller_put(mut hardware_config, ['chip_info_decode'], context.invoke('recover_g17_chip_info_decode', {
		'image': driver
	})!)
	controller_put(mut hardware_config, ['chip_info_registers'], context.invoke('recover_g17_chip_info_registers', {
		'image': driver
	})!)
	controller_put(mut hardware_config, ['late_controls'], context.invoke('recover_g17_late_controls', {
		'image': driver
	})!)
	controller_put(mut hardware_config, ['linear_power_transfer_tables'], context.invoke('recover_g17_linear_power_transfer_tables', {
		'image':          driver
		'arm_power_code': power_code
	})!)
	controller_put(mut hardware_config, ['performance_state_map_block'], context.invoke('recover_g17_perf_state_map_block', {
		'image':          driver
		'arm_power_code': power_code
	})!)
	controller_put(mut hardware_config, ['pio_mappings'], context.invoke('recover_g17_pio_mappings', {
		'image': driver
	})!)
	controller_put(mut hardware_config, ['pio_uat_mapping'], context.invoke('recover_g17_pio_uat_mapping', {
		'image': driver
	})!)
	controller_put(mut channels, ['accelerator_inputs'], context.invoke('recover_g17_accelerator_channel_inputs', {
		'image':            driver
		'kernel_image':     kernel
		'iogpu_image':      iogpu
		'chip_info_decode': controller_item(hardware_config, j.Value('chip_info_decode'))
	})!)
	mut firmware_root := context.invoke('recover_firmware_root', {
		'code': j.Value(context.hex_value(firmware))
	})!
	return expr({
		'schema':                       j.Value(1)
		'driver_uuid':                  driver_uuid
		'firmware_uuid':                firmware_uuid
		'rtbuddy_uuid':                 rtbuddy_uuid
		'driver_root':                  driver_root
		'firmware_root':                firmware_root
		'bootstrap_roots':              bootstrap_roots
		'boot_transport':               boot_transport
		'rtbuddy_endpoints':            rtbuddy_endpoints
		'bootstrap_region':             bootstrap_region
		'platform_config':              platform_config
		'brn_workaround_table':         brn_workaround_table
		'zero_initialized_allocations': zero_initialized_allocations
		'role0_bootstrap_regions':      role0_bootstrap_regions
		'small_shared_data':            small_shared_data
		'runtime_controls':             runtime_controls
		'runtime_initialization':       runtime_initialization
		'runtime_power_policy':         runtime_power_policy
		'runtime_performance_policy':   runtime_performance_policy
		'runtime_platform_policy':      runtime_platform_policy
		'accelerator':                  accelerator
		'channels':                     channels
		'firmware_shared_data':         firmware_shared_data
		'hardware_config':              hardware_config
		'uat_handoff':                  handoff
		'root_allocation_bytes':        root_allocation_sizes
	})
}

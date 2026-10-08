module t6050power

import appleadt as a
import traceanalysis as j

pub fn recover_apple_pmp_code_contract(functions map[string]Function, symbols map[string]j.Value, rtbuddy_symbols map[string]j.Value) !map[string]j.Value {
	required := [apple_pmp_v2_start, apple_pmp_v2_message_handler, apple_pmp_v2_handle_memory,
		apple_pmp_v2_handle_power, apple_pmp_v2_handle_registry, apple_pmp_v2_send_message,
		apple_pmp_v2_write_dashboard, apple_pmp_v2_get_property_data, apple_pmp_v2_ping_gated]
	missing := required.filter(it !in symbols)
	if missing.len != 0 {
		return error('ApplePMP is missing PMPv2 symbols: ' + j.string_value(j.Value(missing.map(j.Value(it)))))
	}
	missing_rtbuddy := [rtbuddy_endpoint_get_slave, rtbuddy_endpoint_init_owner,
		rtbuddy_endpoint_set_power_action].filter(it !in rtbuddy_symbols)
	if missing_rtbuddy.len != 0 {
		return error('RTBuddy is missing ApplePMP attach symbols: ' + j.string_value(j.Value(missing_rtbuddy.map(j.Value(it)))))
	}
	for name in [apple_pmp_v2_start, apple_pmp_v2_message_handler, apple_pmp_v2_handle_power,
		apple_pmp_v2_send_message, apple_pmp_v2_write_dashboard, apple_pmp_v2_ping_gated] {
		if name !in functions {
			return error('ApplePMP has no code body for ' + name)
		}
	}
	start_code_body := function(functions, apple_pmp_v2_start)!
	start_address := start_code_body.address
	start_code := start_code_body.code
	start_targets := branch_targets(Function{start_address, start_code})!
	for target in [rtbuddy_endpoint_get_slave, rtbuddy_endpoint_init_owner,
		rtbuddy_endpoint_set_power_action] {
		if !targets_have(start_targets, symbol(rtbuddy_symbols, target)!)! {
			return error('ApplePMPv2 start no longer calls ' + target)
		}
	}
	get_slave_offset := unique_call_offset(Function{start_address, start_code}, symbol(rtbuddy_symbols, rtbuddy_endpoint_get_slave)!, 'ApplePMPv2 start call count changed for ' + rtbuddy_endpoint_get_slave)!
	init_owner_offset := unique_call_offset(Function{start_address, start_code}, symbol(rtbuddy_symbols, rtbuddy_endpoint_init_owner)!, 'ApplePMPv2 start call count changed for ' + rtbuddy_endpoint_init_owner)!
	set_power_offset := unique_call_offset(Function{start_address, start_code}, symbol(rtbuddy_symbols, rtbuddy_endpoint_set_power_action)!, 'ApplePMPv2 start call count changed for ' + rtbuddy_endpoint_set_power_action)!
	if !(get_slave_offset < init_owner_offset && init_owner_offset < set_power_offset) {
		return error('ApplePMPv2 RTBuddy attach ordering changed')
	}
	if !a.has_ordered_words(start_code, [
		u32(0xf9404400), // ldr x0, [x0, #0x88] -- endpoint from endpoint service
		u32(0xf9004660), // str x0, [x19, #0x88] -- retained endpoint
		u32(0xb9408808), // ldr w8, [x0, #0x88] -- endpoint identifier
		u32(0xb9009268), // str w8, [x19, #0x90]
		u32(0xf9004e60), // str x0, [x19, #0x98] -- slave processor
		u32(0xf9005a60), // str x0, [x19, #0xb0] -- AppleA7IOPNub
		u32(0xf9404800), // ldr x0, [x0, #0x90] -- wrapper service
		u32(0xf9005e60), // str x0, [x19, #0xb8]
		u32(0xb9400001), // ldr w1, [x0] -- ptd-update-reg-index value
		u32(0xf9405e60), // ldr x0, [x19, #0xb8] -- wrapper service
		u32(0x52800002), // mov w2, #0 -- getDeviceMemoryWithIndex options
		u32(0xf9006260), // str x0, [x19, #0xc0] -- PTD update memory
		u32(0xf9405e60), // ldr x0, [x19, #0xb8] -- wrapper service
		u32(0x52800021), // mov w1, #1 -- mapper index
		u32(0xf9006675), // str x21, [x19, #0xc8] -- retained mapper
	]) {
		return error('ApplePMPv2 wrapper resource attachment changed')
	}
	if !a.has_words_in_order(start_code, [
		u32(0xf9404660), // ldr x0, [x19, #0x88]
		u32(0xb0ffffb0), // adrp x16, page(messageHandler)
		u32(0x91270210), // add x16, x16, #0x9c0
		u32(0xd2830211), // mov x17, #0x1810
		u32(0xdac10230), // pacia x16, x17
		u32(0xaa1003e2), // mov x2, x16
		u32(0xaa1303e1), // mov x1, x19
		u32(0xd2800003), // mov x3, #0
	]) {
		return error('ApplePMPv2 no longer installs its RTBuddy message handler')
	}
	handler_code_body := function(functions, apple_pmp_v2_message_handler)!
	handler_address := handler_code_body.address
	handler_code := handler_code_body.code
	handler_targets := branch_targets(Function{handler_address, handler_code})!
	for target in [apple_pmp_v2_handle_memory, apple_pmp_v2_handle_power, apple_pmp_v2_handle_registry] {
		if !targets_have(handler_targets, symbol(symbols, target)!)! {
			return error('ApplePMPv2 message handler no longer dispatches to ' + target)
		}
	}
	if !a.has_ordered_words(handler_code, [
		u32(0xd374dc28), // ubfx x8, x1, #52, #4 -- message class
		u32(0x51000d09), // sub w9, w8, #3
		u32(0x7100093f), // cmp w9, #2 -- registry classes 3/4
		u32(0x7100091f), // cmp w8, #2 -- power class
		u32(0x7100051f), // cmp w8, #1 -- memory class
	]) {
		return error('ApplePMPv2 message-class decoder changed')
	}
	power_code_body := function(functions, apple_pmp_v2_handle_power)!
	power_code := power_code_body.code
	if !a.has_words_in_order(power_code, [
		u32(0x92500c28), // and x8, x1, #0xf000000000000 -- PM subtype
		u32(0xd2e00029), // mov x9, #0x1000000000000 -- subtype 1
		u32(0xeb09011f), // cmp x8, x9
	]) || !a.has_ordered_words(power_code, [
		u32(0x3904201f), // strb wzr, [x0, #0x108] -- ping no longer busy
		u32(0x91042001), // add x1, x0, #0x108 -- wakeup event
	]) {
		return error('ApplePMPv2 ping-completion message changed')
	}
	send_code_body := function(functions, apple_pmp_v2_send_message)!
	send_code := send_code_body.code
	if !a.has_ordered_words(send_code, [
		u32(0xf90007e1), // str x1, [sp, #8] -- one 64-bit mailbox word
		u32(0xf9404400), // ldr x0, [x0, #0x88] -- RTBuddy service
		u32(0xd2803d11), // mov x17, #0x1e8 -- send vtable slot
		u32(0x910023e1), // add x1, sp, #8
		u32(0xd2800002), // mov x2, #0
		u32(0x52800023), // mov w3, #1 -- one word
	]) {
		return error('ApplePMPv2 RTBuddy send-message ABI changed')
	}
	ping_code_body := function(functions, apple_pmp_v2_ping_gated)!
	ping_code := ping_code_body.code
	if !a.has_ordered_words(ping_code, [
		u32(0x39442008), // ldrb w8, [x0, #0x108] -- reject overlapping ping
		u32(0xd2e00417), // mov x23, #0x20000000000000 -- class 2
		u32(0xb3407c17), // bfxil x23, x0, #0, #32 -- timestamp payload
		u32(0x390422b7), // strb w23, [x21, #0x108] -- mark in flight
		u32(0x910422a1), // add x1, x21, #0x108 -- sleep event
	]) {
		return error('ApplePMPv2 ping request/wait protocol changed')
	}
	dashboard_code_body := function(functions, apple_pmp_v2_write_dashboard)!
	dashboard_address := dashboard_code_body.address
	dashboard_code := dashboard_code_body.code
	dashboard_targets := branch_targets(Function{dashboard_address, dashboard_code})!
	if !targets_have(dashboard_targets, symbol(symbols, apple_pmp_v2_get_property_data)!)! || !a.has_ordered_words(dashboard_code, [
		u32(0xf9406000), // ldr x0, [x0, #0xc0] -- PTD/dashboard object
		u32(0xaa0203f4), // mov x20, x2 -- 64-bit value
		u32(0xaa0103f5), // mov x21, x1 -- dashboard index
		u32(0xd0ff05a1), // adrp x1, page("pmptool-config")
		u32(0x910c0021), // add x1, x1, #0x300
		u32(0xf9000134), // str x20, [x9] -- indexed 64-bit write
	]) {
		return error('ApplePMPv2 diagnostic dashboard write contract changed')
	}
	return j.Value(map[string]j.Value{
		'attachment':           j.Value(map[string]j.Value{
			'provider':                        j.Value('RTBuddyEndpointService')
			'provider_endpoint_offset':        j.Value(u64(136))
			'endpoint_identifier_offset':      j.Value(u64(136))
			'slave_processor_object_offset':   j.Value(u64(152))
			'wrapper_service_object_offset':   j.Value(u64(184))
			'ptd_update_property':             j.Value('ptd-update-reg-index')
			'ptd_update_memory_object_offset': j.Value(u64(192))
			'mapper_index':                    j.Value(u64(1))
			'mapper_object_offset':            j.Value(u64(200))
			'ordering':                        j.Value([
				j.Value('resolve endpoint and slave processor'),
				j.Value('resolve wrapper PTD-update memory and mapper'),
				j.Value('install message callback'),
				j.Value('install power-state callback'),
			])
			'scope':                           j.Value('host attachment only; does not start or prove PMP firmware ready')
		})
		'mailbox':              j.Value(map[string]j.Value{
			'word_bits':             j.Value(u64(64))
			'message_class':         j.Value(map[string]j.Value{
				'shift': j.Value(u64(52))
				'bits':  j.Value(u64(4))
			})
			'classes':               j.Value(map[string]j.Value{
				'memory':   j.Value([j.Value(u64(1))])
				'power':    j.Value([j.Value(u64(2))])
				'registry': j.Value([j.Value(u64(3)), j.Value(u64(4))])
			})
			'rtbuddy_object_offset': j.Value(u64(136))
			'send_vtable_slot':      j.Value(u64(488))
			'send_word_count':       j.Value(u64(1))
		})
		'ping':                 j.Value(map[string]j.Value{
			'request_class':            j.Value(u64(2))
			'request_payload':          j.Value('low 32 bits of host timestamp')
			'completion_power_subtype': j.Value(u64(1))
			'power_subtype':            j.Value(map[string]j.Value{
				'shift': j.Value(u64(48))
				'bits':  j.Value(u64(4))
			})
			'in_flight_byte_offset':    j.Value(u64(264))
			'completion':               j.Value('clear in-flight byte and wake its sleepers')
			'scope':                    j.Value('ping completion, not proof of AGX dashboard readiness')
		})
		'diagnostic_dashboard': j.Value(map[string]j.Value{
			'object_offset':          j.Value(u64(192))
			'configuration_property': j.Value('pmptool-config')
			'index_unit_bits':        j.Value(u64(64))
			'write_bits':             j.Value(u64(64))
			'scope':                  j.Value('diagnostic API, not the ApplePMGR AGX state request')
		})
	}).as_map()
}

pub fn recover_apple_pmp_firmware_code_contract(pmp_functions map[string]Function, pmp_symbols map[string]j.Value, rtbuddy_functions map[string]Function, rtbuddy_symbols map[string]j.Value, pmp_vtable_targets map[string]j.Value, service_vtable_targets map[string]j.Value, firmware_vtable_targets map[string]j.Value) !map[string]j.Value {
	required_pmp := [apple_pmp_firmware_start, apple_pmp_firmware_patch, rtbuddy_firmware_patch_u32]
	missing_pmp := required_pmp.filter(it !in pmp_symbols)
	if missing_pmp.len != 0 {
		return error('ApplePMPFirmware is missing firmware symbols: ' + j.string_value(j.Value(missing_pmp.map(j.Value(it)))))
	}
	for name in [apple_pmp_firmware_start, apple_pmp_firmware_patch] {
		if name !in pmp_functions {
			return error('ApplePMPFirmware has no code body for ' + name)
		}
	}
	required_rtbuddy := [rtbuddy_firmware_service_pre_load, rtbuddy_firmware_service_patch,
		rtbuddy_firmware_fixup, rtbuddy_firmware_copy_to_target, rtbuddy_firmware_create_coredump_map,
		rtbuddy_firmware_publish, rtbuddy_firmware_write_back_patchbay,
		rtbuddy_firmware_update_patchbay, rtbuddy_firmware_update_coredump_patchbay,
		rtbuddy_firmware_get_role, rtbuddy_firmware_announce, rtbuddy_call_patchbay_callback,
		rtbuddy_power_on, rtbuddy_load_firmware_gated, rtbuddy_wait_for_firmware_service_gated]
	missing_rtbuddy := required_rtbuddy.filter(it !in rtbuddy_symbols)
	if missing_rtbuddy.len != 0 {
		return error('RTBuddy is missing PMP firmware-load symbols: ' + j.string_value(j.Value(missing_rtbuddy.map(j.Value(it)))))
	}
	for name in [rtbuddy_firmware_fixup, rtbuddy_load_firmware_gated] {
		if name !in rtbuddy_functions {
			return error('RTBuddy has no code body for ' + name)
		}
	}
	expected_pmp_slots := map[string]j.Value{
		'1520': symbol(pmp_symbols, apple_pmp_firmware_start)!
		'2200': symbol(pmp_symbols, apple_pmp_firmware_patch)!
	}
	if !integer_maps_equal(pmp_vtable_targets, expected_pmp_slots) {
		return error('ApplePMPFirmware vtable overrides changed')
	}
	expected_service_slots := map[string]j.Value{
		'2192': symbol(rtbuddy_symbols, rtbuddy_firmware_service_pre_load)!
		'2200': symbol(rtbuddy_symbols, rtbuddy_firmware_service_patch)!
	}
	if !integer_maps_equal(service_vtable_targets, expected_service_slots) {
		return error('RTBuddyFirmwareService fixup slots changed')
	}
	expected_firmware_slots := map[string]j.Value{
		'2216': symbol(rtbuddy_symbols, rtbuddy_firmware_update_patchbay)!
		'2224': symbol(rtbuddy_symbols, rtbuddy_firmware_update_coredump_patchbay)!
	}
	if !integer_maps_equal(firmware_vtable_targets, expected_firmware_slots) {
		return error('RTBuddyFirmware patchbay slots changed')
	}
	start_code_body := function(pmp_functions, apple_pmp_firmware_start)!
	start_code := start_code_body.code
	if !a.has_ordered_words(start_code, [
		u32(0xf9004e80), // str x0, [x20, #0x98] -- retained RTBuddy
		u32(0xd280d611), // mov x17, #0x6b0 -- its provider accessor
		u32(0xf9005280), // str x0, [x20, #0xa0] -- retained provider nub
	]) {
		return error('ApplePMPFirmware provider chain changed')
	}
	if bytes_count(start_code, encoded_words([u32(1895829535)])) != 4 {
		return error('ApplePMPFirmware property width checks changed')
	}
	if !a.has_ordered_words(start_code, [
		u32(0x12000109), // and w9, w8, #1 -- PMCV
		u32(0x53030d08), // ubfx w8, w8, #3, #1 -- PMCB
		u32(0x291ba289), // stp w9, w8, [x20, #0xdc]
	]) {
		return error('ApplePMPFirmware pmc-pmgr split changed')
	}
	if !a.has_ordered_words(start_code, [
		u32(0xb900ca88), // board-id -> this+0xc8
		u32(0xb900ce88), // dram-vendor-id -> this+0xcc
		u32(0xb900d288), // dram-capacity -> this+0xd0
		u32(0xb900d688), // dram-channel-disable -> this+0xd4
		u32(0xb900da88), // pmc -> this+0xd8
		u32(0x291ba289), // pmc-pmgr bits 0/3 -> this+0xdc/+0xe0
		u32(0xb900e688), // pmc-msg-disabled -> this+0xe4
		u32(0xb900ea88), // soc-chip-variant -> this+0xe8
		u32(0xf9405e82), // Role property object from this+0xb8
	]) {
		return error('ApplePMPFirmware mandatory property collection changed')
	}
	patch_code_body := function(pmp_functions, apple_pmp_firmware_patch)!
	patch_address := patch_code_body.address
	patch_code := patch_code_body.code
	mandatory_words := map[int]u32{
		32:  u32(0x52886855)
		36:  u32(0x72aa09b5)
		40:  u32(0x52882a16)
		44:  u32(0x72a88876)
		52:  u32(0x91032002)
		60:  u32(0x52892881)
		64:  u32(0x72a84881)
		72:  u32(0x91033282)
		80:  u32(0x52892881)
		84:  u32(0x72a88ac1)
		92:  u32(0x91034282)
		100: u32(0x52882a01)
		104: u32(0x72a88861)
		112: u32(0x111bd2c1)
		116: u32(0x91035282)
		128: u32(0x528003a8)
		132: u32(0x2a0802a1)
		136: u32(0x91036282)
		148: u32(0x52800288)
		152: u32(0x2a0802a1)
		156: u32(0x91037282)
		168: u32(0x91038282)
		176: u32(0x52886841)
		180: u32(0x72aa09a1)
		188: u32(0x11005aa1)
		192: u32(0x91039282)
		204: u32(0x9103a282)
		212: u32(0x52882a41)
		216: u32(0x72a86ac1)
	}
	if patch_code.len < 0xe0 || !words_at_offsets(patch_code, mandatory_words) {
		return error('ApplePMPFirmware mandatory patchbay writes changed')
	}
	mandatory_call_offsets := [68, 88, 108, 124, 144, 164, 184, 200, 220]
	if !all_calls_at(Function{patch_address, patch_code}, mandatory_call_offsets, symbol(pmp_symbols, rtbuddy_firmware_patch_u32)!)! {
		return error('ApplePMPFirmware mandatory patchbay call targets changed')
	}
	fixup_code_body := function(rtbuddy_functions, rtbuddy_firmware_fixup)!
	fixup_address := fixup_code_body.address
	fixup_code := fixup_code_body.code
	fixup_direct_order := [rtbuddy_power_on, rtbuddy_firmware_copy_to_target,
		rtbuddy_firmware_create_coredump_map, rtbuddy_call_patchbay_callback, rtbuddy_firmware_publish,
		rtbuddy_firmware_write_back_patchbay]
	mut fixup_offsets := []int{}
	for name in fixup_direct_order {
		offsets := call_offsets(Function{fixup_address, fixup_code}, symbol(rtbuddy_symbols, name)!)!
		if offsets.len != 1 {
			return error('RTBuddy firmware fixup call count changed for ' + name)
		}
		fixup_offsets << offsets[0]
	}
	virtual_slot_words := [u32(0xd2811211), u32(0xd2811311), u32(0xd2811511), u32(0xd2811611)]
	mut virtual_offsets := []int{}
	for word in virtual_slot_words {
		offsets := word_offsets(fixup_code, u32(word))
		if offsets.len != 1 {
			return error('RTBuddy firmware virtual fixup slots changed')
		}
		virtual_offsets << offsets[0]
	}
	complete_fixup_offsets := [fixup_offsets[0], virtual_offsets[0], fixup_offsets[1],
		fixup_offsets[2], virtual_offsets[1], fixup_offsets[3], virtual_offsets[2], virtual_offsets[3],
		fixup_offsets[4], fixup_offsets[5]]
	if complete_fixup_offsets.clone() != sorted_offsets(complete_fixup_offsets) {
		return error('RTBuddy firmware fixup ordering changed')
	}
	load_code_body := function(rtbuddy_functions, rtbuddy_load_firmware_gated)!
	load_address := load_code_body.address
	load_code := load_code_body.code
	load_direct_order := [rtbuddy_firmware_get_role, rtbuddy_wait_for_firmware_service_gated,
		rtbuddy_firmware_fixup, rtbuddy_firmware_announce]
	mut load_offsets := []int{}
	for name in load_direct_order {
		offsets := call_offsets(Function{load_address, load_code}, symbol(rtbuddy_symbols, name)!)!
		if offsets.len != 1 {
			return error('RTBuddy gated load call count changed for ' + name)
		}
		load_offsets << offsets[0]
	}
	load_words := [u32(0xf910f674), u32(0xf950ba62), u32(0x52800028), u32(0x39042e68), u32(0xf950f660)]
	load_word_offsets := load_words.map(bytes_find(load_code, encoded_words([u32(it)]), 0))
	complete_load_offsets := [load_offsets[0], load_offsets[1], load_word_offsets[0],
		load_word_offsets[1], load_offsets[2], load_word_offsets[2], load_word_offsets[3],
		load_word_offsets[4], load_offsets[3]]
	if (-1) in load_word_offsets || complete_load_offsets.clone() != sorted_offsets(complete_load_offsets) {
		return error('RTBuddy gated firmware-load completion changed')
	}
	return j.Value(map[string]j.Value{
		'service':                   j.Value(map[string]j.Value{
			'start_vtable_slot':             j.Value(u64(1520))
			'pre_firmware_load_vtable_slot': j.Value(u64(2192))
			'patch_firmware_vtable_slot':    j.Value(u64(2200))
			'patch_override':                j.Value('ApplePMPFirmware::patchFirmware')
		})
		'mandatory_patchbay_writes': j.Value(mandatory_patch_metadata())
		'mandatory_patchbay_inputs': j.Value(map[string]j.Value{
			'width_bytes':         j.Value(u64(4))
			'width_checked_nodes': j.Value([j.Value(pmp_chosen_path), j.Value(pmp_pmgr_path)])
			'unchecked_node':      j.Value(pmp_provider_node)
			'provider_chain':      j.Value('the retained RTBuddy at +0x98, its vtable slot 0x6b0 provider, cast and retained at +0xa0')
			'absent_behavior':     j.Value("the store is skipped and patchFirmware still writes the field, so an absent property publishes the allocator's zero")
		})
		'rtbuddy_fixup':             j.Value(map[string]j.Value{
			'ordering':                       j.Value([
				j.Value('power on RTBuddy target'),
				j.Value('service preFirmwareLoad'),
				j.Value('copy firmware to target when required'),
				j.Value('create coredump map when required'),
				j.Value('service patchFirmware'),
				j.Value('invoke registered patchbay callback'),
				j.Value('firmware updatePatchBay'),
				j.Value('firmware updateCoredumpWithPatchBay when required'),
				j.Value('publish firmware to IORegistry'),
				j.Value('write patchbay back to the target image'),
			])
			'firmware_object_offset':         j.Value(u64(8680))
			'firmware_service_object_offset': j.Value(u64(8560))
			'firmware_loaded_byte_offset':    j.Value(u64(267))
			'completion':                     j.Value('set firmware-loaded byte, then announce firmware')
			'scope':                          j.Value('image preparation and RTBuddy bookkeeping only; no PMP run-state or dashboard-ready acknowledgement is established')
		})
	}).as_map()
}

pub fn recover_rtbuddy_boot_handshake_code_contract(functions map[string]Function, symbols map[string]j.Value) !map[string]j.Value {
	required := [rtbuddy_load_firmware, rtbuddy_perform_power_state_gated, rtbuddy_iop_validate,
		rtbuddy_iop_validate_polling, rtbuddy_iop_validate_blocking, rtbuddy_set_iop_status,
		rtbuddy_set_iop_status_public, rtbuddy_management_handle_hello,
		rtbuddy_management_handle_ep_rollcall, rtbuddy_build_roll_call, rtbuddy_get_endpoint,
		rtbuddy_create_endpoint, rtbuddy_endpoint_service_create_name]
	missing_symbols := required.filter(it !in symbols)
	if missing_symbols.len != 0 {
		return error('RTBuddy is missing boot-handshake symbols: ' + j.string_value(j.Value(missing_symbols.map(j.Value(it)))))
	}
	missing_functions := required.filter(it !in functions)
	if missing_functions.len != 0 {
		return error('RTBuddy has no boot-handshake code body for ' + j.string_value(j.Value(missing_functions.map(j.Value(it)))))
	}
	load_code_body := function(functions, rtbuddy_load_firmware)!
	load_code := load_code_body.code
	if !a.has_ordered_words(load_code, [
		u32(0x39443668), // power-transition suppression byte at RTBuddy+0x10d
		u32(0x37000168), // skip the power transition when it is set
		u32(0xd2810311), // RTBuddy setPowerState vtable slot 0x818
		u32(0xaa1303e0),
		u32(0x52800021), // requested RTBuddy power state 1
		u32(0xd2800002), // no provider override
		u32(0xd73f0910),
	]) {
		return error('RTBuddy firmware-load power transition changed')
	}
	perform_code_body := function(functions, rtbuddy_perform_power_state_gated)!
	perform_address := perform_code_body.address
	perform_code := perform_code_body.code
	if branch_count(Function{perform_address, perform_code}, symbol(symbols, rtbuddy_set_iop_status)!)! != 2 || branch_count(Function{perform_address, perform_code}, symbol(symbols, rtbuddy_iop_validate)!)! != 1 {
		return error('RTBuddy managed boot status calls changed')
	}
	status_four_offset := bytes_find(perform_code, encoded_words([u32(1384120449)]), 0)
	validate_offsets := call_offsets(Function{perform_address, perform_code}, symbol(symbols, rtbuddy_iop_validate)!)!
	if status_four_offset < 0 || !branch_at_equal(Function{perform_address, perform_code}, (status_four_offset + 4), symbol(symbols, rtbuddy_set_iop_status)!)! || validate_offsets.len != 1 || !a.has_ordered_words(bytes_slice(perform_code, status_four_offset, (validate_offsets[0] + 4)), [
		u32(0x52800081), // status 4 before starting the IOP
		u32(0xf9405a60), // concrete AppleA7IOP wrapper at RTBuddy+0xb0
		u32(0xf950f661), // selected firmware at RTBuddy+0x21e8
		u32(0xd2811111), // AppleA7IOP startCPUWithOptions slot 0x888
		u32(0xd73f0910),
	]) {
		return error('RTBuddy managed CPU-start ordering changed')
	}
	validate_code_body := function(functions, rtbuddy_iop_validate)!
	validate_address := validate_code_body.address
	validate_code := validate_code_body.code
	if branch_count(Function{validate_address, validate_code}, symbol(symbols, rtbuddy_iop_validate_polling)!)! != 1 || branch_count(Function{validate_address, validate_code}, symbol(symbols, rtbuddy_iop_validate_blocking)!)! != 1 || !a.has_ordered_words(validate_code, [
		u32(0x39440008), // validation mode byte at RTBuddy+0x100
		u32(0x39442268), // wrapper-running byte at RTBuddy+0x108
		u32(0x528000d4), // ordinary initial target status 6
		u32(0x52800114), // alternate target status 8
		u32(0xf9009a60), // validation start timestamp at RTBuddy+0x130
		u32(0x52844b08), // polling selector byte at RTBuddy+0x2258
	]) {
		return error('RTBuddy IOP validation dispatch changed')
	}
	polling_code_body := function(functions, rtbuddy_iop_validate_polling)!
	polling_code := polling_code_body.code
	validation_result_words := [u32(0xb9412800), u32(0xd2813d11), u32(0xb9415a88), u32(0x6b08027f),
		u32(0x7140211f), u32(0x528058e9), u32(0x72bc0009), u32(0x11003d2a)]
	if !a.has_ordered_words(polling_code, validation_result_words.map(u32(it))) {
		return error('RTBuddy polling validation loop changed')
	}
	blocking_code_body := function(functions, rtbuddy_iop_validate_blocking)!
	blocking_code := blocking_code_body.code
	if !a.has_ordered_words(blocking_code, [
		u32(0x91056015), // address of status word at RTBuddy+0x158
		u32(0xb9412a80), // timeout configuration at RTBuddy+0x128
		u32(0x91084208), // command-gate sleep vtable slot 0x210
		u32(0xb9415a88), // current IOP status
		u32(0x6b08027f), // success when current status equals the target
		u32(0x7140211f), // terminal failure status 0x8000
		u32(0x528058e9),
		u32(0x72bc0009),
		u32(0x11003d2a),
	]) {
		return error('RTBuddy blocking validation loop changed')
	}
	set_public_code_body := function(functions, rtbuddy_set_iop_status_public)!
	set_public_address := set_public_code_body.address
	set_public_code := set_public_code_body.code
	if branch_count(Function{set_public_address, set_public_code}, symbol(symbols, rtbuddy_set_iop_status)!)! != 1 || !a.has_ordered_words(set_public_code, [
		u32(0xd2811111), // obtain the RTBuddy command gate
		u32(0x91056261), // status word at RTBuddy+0x158
		u32(0x52800002), // wake every waiter for that word
	]) {
		return error('RTBuddy IOP status publication changed')
	}
	hello_code_body := function(functions, rtbuddy_management_handle_hello)!
	hello_address := hello_code_body.address
	hello_code := hello_code_body.code
	hello_status_offsets := call_offsets(Function{hello_address, hello_code}, symbol(symbols, rtbuddy_set_iop_status_public)!)!
	if hello_status_offsets.len != 2 || python_word_at(hello_code, (hello_status_offsets[0] - 4)) != 1384120481 || python_word_at(hello_code, (hello_status_offsets[1] - 4)) != 1385168897 || !a.has_ordered_words(hello_code, [
		u32(0xb9415808), // current IOP status
		u32(0x7100111f), // Hello is expected while status is 4
		u32(0x7140211f), // also handle the 0x8000 failure sentinel
		u32(0xb9010661), // save the Hello word
		u32(0x12003c28), // peer minimum protocol, low 16 bits
		u32(0x7100311f), // peer minimum must be <= 12
		u32(0xd350fc28), // peer maximum protocol, high 16 bits
		u32(0x12003d08),
		u32(0x7100311f), // peer maximum must be >= 12
		u32(0x528000a1), // accepted Hello advances to status 5
	]) {
		return error('RTBuddy management Hello negotiation changed')
	}
	roll_code_body := function(functions, rtbuddy_management_handle_ep_rollcall)!
	roll_address := roll_code_body.address
	roll_code := roll_code_body.code
	if branch_count(Function{roll_address, roll_code}, symbol(symbols, rtbuddy_create_endpoint)!)! != 1 || !a.has_ordered_words(roll_code, [
		u32(0xd3609436), // bitmap group is bits 32..37
		u32(0x531b6ad5), // first wire endpoint is group * 32
		u32(0x36000097), // create an endpoint for each set bitmap bit
		u32(0x110006b5), // advance to the next wire endpoint
		u32(0x53017ef7), // advance to the next bitmap bit
	]) {
		return error('RTBuddy endpoint roll-call bitmap decoder changed')
	}
	if !branch_target_exists(Function{roll_address, roll_code}, symbol(symbols, rtbuddy_build_roll_call)!)! || !a.has_ordered_words(roll_code, [
		u32(0xb9415808), // ldr w8, [x0, #0x158] -- IOP status
		u32(0x7100151f), // cmp w8, #5 -- a roll call is only legal after Hello
		u32(0x1a9f17e0), // cset w0, eq -- group 0 owns the management endpoint
		u32(0xb69800f4), // tbz x20, #0x33 -- bit 51 marks the last group
		u32(0x92604e89), // and x9, x20, #0xfffff00000000
		u32(0x924dc929), // and x9, x9, #0xfff8003fffffffff -- keep group and last
		u32(0xb2490108), // orr x8, x8, #0x80000000000000 -- reply type 8
	]) {
		return error('RTBuddy endpoint roll-call reply changed')
	}
	build_code_body := function(functions, rtbuddy_build_roll_call)!
	build_address := build_code_body.address
	build_code := build_code_body.code
	if !branch_target_exists(Function{build_address, build_code}, symbol(symbols, rtbuddy_get_endpoint)!)! || !a.has_ordered_words(build_code, [
		u32(0xb160261), // add w1, w19, w22 -- group base plus bit index
		u32(0x1ad622e8), // lsl w8, w23, w22
		u32(0x2a080294), // orr w20, w20, w8 -- set the bit for a live endpoint
		u32(0x710082df), // cmp w22, #0x20 -- exactly 32 bits per group
	]) {
		return error('RTBuddy roll-call reply bitmap changed')
	}
	create_name_code_body := function(functions, rtbuddy_endpoint_service_create_name)!
	create_name_code := create_name_code_body.code
	if !a.has_ordered_words(create_name_code, [
		u32(0x51007c33), // generic service suffix = wire endpoint - 0x1f
		u32(0xa9004fe0), // format(provider-name, suffix)
	]) {
		return error('RTBuddy application endpoint service-name mapping changed')
	}
	roll_status_offsets := call_offsets(Function{roll_address, roll_code}, symbol(symbols, rtbuddy_set_iop_status_public)!)!
	if roll_status_offsets.len != 1 || python_word_at(roll_code, (roll_status_offsets[0] - 4)) != 1384120513 || !a.has_ordered_words(roll_code, [
		u32(0xb9415808), // current IOP status
		u32(0x7100151f), // endpoint roll call is expected at status 5
		u32(0xd73f0910), // send the roll-call reply
		u32(0x35000180), // do not advance when the reply send fails
		u32(0xf9403a60), // owning RTBuddy
		u32(0x528000c1), // successful roll call advances to status 6
	]) {
		return error('RTBuddy endpoint roll-call readiness changed')
	}
	return j.Value(map[string]j.Value{
		'firmware_load_power_transition': j.Value(map[string]j.Value{
			'set_power_state_vtable_slot':        j.Value(u64(2072))
			'requested_state':                    j.Value(u64(1))
			'transition_suppression_byte_offset': j.Value(u64(269))
		})
		'managed_cpu_start':              j.Value(map[string]j.Value{
			'status_before_start':                j.Value(u64(4))
			'wrapper_object_offset':              j.Value(u64(176))
			'firmware_object_offset':             j.Value(u64(8680))
			'start_cpu_with_options_vtable_slot': j.Value(u64(2184))
			'completion':                         j.Value('enter IOP validation immediately after CPU start')
		})
		'rtkit_handshake':                j.Value(map[string]j.Value{
			'status_object_offset':        j.Value(u64(344))
			'timeout_object_offset':       j.Value(u64(296))
			'protocol_version':            j.Value(u64(12))
			'states':                      j.Value([j.Value(map[string]j.Value{
				'status':  j.Value(u64(4))
				'meaning': j.Value('CPU start issued; awaiting Hello')
			}), j.Value(map[string]j.Value{
				'status':  j.Value(u64(5))
				'meaning': j.Value('Hello accepted at protocol 12')
			}), j.Value(map[string]j.Value{
				'status':  j.Value(u64(6))
				'meaning': j.Value('endpoint roll-call reply sent successfully')
			}), j.Value(map[string]j.Value{
				'status':  j.Value(u64(8))
				'meaning': j.Value('alternate power-state target')
			}), j.Value(map[string]j.Value{
				'status':  j.Value(u64(32768))
				'meaning': j.Value('terminal validation failure')
			})])
			'validation_modes':            j.Value([j.Value('poll mailbox'),
				j.Value('block on status word')])
			'validation_target_selection': j.Value('status 6 when RTBuddy byte 0x100 or 0x108 is set; otherwise status 8')
			'validation_success':          j.Value('target status reached')
			'validation_failure':          j.Value('status 0x8000 or configured timeout')
			'transport_ready_status':      j.Value(u64(6))
			'endpoint_roll_call':          j.Value(map[string]j.Value{
				'bitmap_word_bits':           j.Value(u64(32))
				'group_field':                j.Value(map[string]j.Value{
					'shift': j.Value(u64(32))
					'bits':  j.Value(u64(6))
				})
				'wire_endpoint':              j.Value('group * 32 + set-bit index')
				'reply':                      j.Value(map[string]j.Value{
					'preserved_fields': j.Value([j.Value('group at bits 32..37'),
						j.Value('last at bit 51')])
					'management_type':  j.Value(u64(8))
					'payload':          j.Value('a bitmap of the endpoints the host already has in that group, so the first reply sets only bit 0 and only for group 0')
					'builder':          j.Value(rtbuddy_build_roll_call)
					'precondition':     j.Value('IOP status 5')
				})
				'application_service_suffix': j.Value('wire endpoint - 0x1f')
				'endpoint1_wire_endpoint':    j.Value(u64(32))
				'scope':                      j.Value('Endpoint1 is a service-name suffix, not RTKit wire endpoint 1')
			})
			'scope':                       j.Value('RTBuddy transport and endpoint discovery only; it does not prove ApplePMGR observed PMP-STATUS or an AGX dashboard ack')
		})
	}).as_map()
}

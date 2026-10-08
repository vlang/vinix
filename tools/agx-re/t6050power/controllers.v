module t6050power

import g17decode as g
import math.big
import traceanalysis as j

// A controller request consumes its reader synchronously. Functions and
// primitive tables are owned values; the reader never appears in metadata.
pub interface ControllerReader {
	identity() !j.Value
	symbols() !map[string]j.Value
	code(name string) !Function
	vtable(name string, slot int) !j.Value
	read_cstring(body Function, adrp_offset int, add_offset int) !string
	read_table(address u64, count int) ![]u32
	read_table64(address u64, count int) ![]u64
}

pub struct ControllerImage {
pub:
	image []u8
}

pub fn (source ControllerImage) identity() !j.Value { return g.macho_uuid(source.image)! }

pub fn (source ControllerImage) symbols() !map[string]j.Value {
	mut result := map[string]j.Value{}
	for name, address in g.macho_symbols(source.image)! { result[name] = j.Value(address) }
	return result
}

pub fn (source ControllerImage) code(name string) !Function {
	address, bytes := g.symbol_code(source.image, name)!
	return Function{j.Value(address), bytes}
}

pub fn (source ControllerImage) vtable(name string, slot int) !j.Value {
	return j.Value(g.recover_vtable_target(source.image, name, big.integer_from_int(slot))!)
}

pub fn (source ControllerImage) read_cstring(body Function, adrp_offset int, add_offset int) !string {
	return g.read_adrp_add_cstring(source.image, body.address, body.code, adrp_offset, add_offset)!
}

pub fn (source ControllerImage) read_table(address u64, count int) ![]u32 {
	return g.read_virtual_u32_table(source.image, big.integer_from_u64(address), big.integer_from_int(count))!
}

pub fn (source ControllerImage) read_table64(address u64, count int) ![]u64 {
	offset := g.virtual_to_file(source.image, big.integer_from_u64(address))!
	position := patch_unpack(source.image, offset, count * 8)!
	mut result := []u64{cap: count}
	for index in 0 .. count { result << patch_u64(source.image, position + index * 8) }
	return result
}

fn controller_identity(reader ControllerReader, expected string, label string) !j.Value {
	identity := reader.identity()!
	if identity != j.Value(expected) {
		return error('unsupported ${label} UUID ${j.string_value(identity)}')
	}
	return identity
}

fn controller_functions(reader ControllerReader, names []string) !map[string]Function {
	mut result := map[string]Function{}
	for name in names { result[name] = reader.code(name)! }
	return result
}

fn controller_vtable(reader ControllerReader, name string, slots []int) !map[string]j.Value {
	mut result := map[string]j.Value{}
	for slot in slots { result[slot.str()] = reader.vtable(name, slot)! }
	return result
}

struct StartString {
	adrp  int
	add   int
	value string
}

fn controller_strings(reader ControllerReader, body Function, proofs []StartString, label string) ! {
	for proof in proofs {
		actual := reader.read_cstring(body, proof.adrp, proof.add)!
		if actual != proof.value {
			return error('${label} string changed at 0x${proof.adrp:x}: ${j.quoted(actual)}')
		}
	}
}

pub fn recover_pmgr_controller(reader ControllerReader) !map[string]j.Value {
	identity := controller_identity(reader, apple_pmgr_uuid, 'ApplePMGR')!
	symbols := reader.symbols()!
	functions := controller_functions(reader, [pmp_send_command, pmp_write_dashboard,
		pmp_set_device_state, pmp_set_virtual_device_state, pmp_init_v2, pmp_get_device_index,
		pmp_notify_initial, pmp_notify_initial_entry, pmp_wait_cluster_power_up,
		pmp_enable_device_gated, pmp_wait_ready, pmp_wait_ready_v2, pmp_ready_gated,
		pmp_ready_action_v2, pmgr_start, pmgr_handle_interrupt_all, pmgr_init_driver, pmgr_constructor,
		apple_ptd_read, apple_ptd_write, pmgr_write_reg64])!
	interrupts := recover_pmgr_interrupt_config_evidence(reader, functions)!
	return {
		'uuid':   identity
		'pmp_v2': j.Value(recover_pmp_code_contract(functions, symbols, j.Value(interrupts))!)
	}
}

pub fn recover_t6050_pmgr_controller(reader ControllerReader, apple_symbols map[string]j.Value) !map[string]j.Value {
	identity := controller_identity(reader, apple_t6050_pmgr_uuid, 'AppleT6050PMGR')!
	symbols := reader.symbols()!
	functions := controller_functions(reader, [t6050_init_reg_maps, pmgr_pmp_v1, pmgr_pmp_v2,
		t6050_restore_hw, t6050_update_hib_device_status])!
	slots := controller_vtable(reader, apple_t6050_pmgr_vtable, [0xab0, 0xab8, 0xac0, 0xac8, 0xb30])!
	return {
		'uuid':  identity
		'power': j.Value(recover_t6050_pmgr_code_contract(functions, symbols, apple_symbols, slots)!)
	}
}

pub fn recover_pmp_controller(reader ControllerReader, rtbuddy ControllerReader) !map[string]j.Value {
	identity := controller_identity(reader, apple_pmp_uuid, 'ApplePMP')!
	symbols := reader.symbols()!
	rtbuddy_identity := controller_identity(rtbuddy, rtbuddy_uuid, 'RTBuddy')!
	rtbuddy_symbols := rtbuddy.symbols()!
	functions := controller_functions(reader, [apple_pmp_v2_start, apple_pmp_v2_message_handler,
		apple_pmp_v2_handle_power, apple_pmp_v2_send_message, apple_pmp_v2_write_dashboard,
		apple_pmp_v2_ping_gated])!
	controller_strings(reader, function(functions, apple_pmp_v2_start)!, [
		StartString{0x94, 0x98, 'role'},
		StartString{0x154, 0x158, 'ptd-update-reg-index'},
		StartString{0x260, 0x264, 'setActive'},
		StartString{0x328, 0x32c, 'PMP workloop'},
		StartString{0x3f8, 0x3fc, 'wait-for'},
	], 'ApplePMPv2 start')!
	return {
		'uuid':         identity
		'rtbuddy_uuid': rtbuddy_identity
		'pmp_v2':       j.Value(recover_apple_pmp_code_contract(functions, symbols, rtbuddy_symbols)!)
	}
}

pub fn recover_a7iop_controller(reader ControllerReader) !map[string]j.Value {
	identity := controller_identity(reader, apple_a7iop_uuid, 'AppleA7IOP')!
	functions := controller_functions(reader, [apple_wrapper_mailbox_start, apple_wrapper_mailbox_reg,
		apple_wrapper_mailbox_physical, apple_a7iop_start, apple_a7iop_start_cpu_options,
		apple_a7iop_reg, apple_a7iop_physical, apple_a7iop_enable_sram, apple_a7iop_enable_power,
		apple_a7iop_dart_map_iboot_firmware, apple_a7iop_has_iboot_firmware])!
	controller_strings(reader, function(functions, apple_a7iop_start)!, [
		StartString{0x794, 0x798, 'sram-index'},
		StartString{0x80c, 0x810, 'should-control-sram'},
		StartString{0x88c, 0x890, 'cpu-ctrl-filtered'},
	], 'AppleA7IOP start')!
	slots := controller_vtable(reader, apple_a7iop_vtable, [apple_a7iop_enable_power_vtable_slot])!
	mut result := {
		'uuid': identity
	}
	for key, value in recover_apple_a7iop_code_contract_evidence(reader, functions, slots)! {
		result[key] = value
	}
	return result
}

pub fn recover_iodart_controller(reader ControllerReader) !map[string]j.Value {
	identity := controller_identity(reader, iodart_family_uuid, 'IODARTFamily')!
	functions := controller_functions(reader, [iodart_mapper_get_page_size, iodart_mapper_iovm_insert,
		iodart_mapper_iovm_insert_one])!
	slots := controller_vtable(reader, iodart_mapper_vtable, [0x888, 0x8a0])!
	body := function(functions, iodart_mapper_iovm_insert)!
	table := g.read_adrp_add_address(body.address, body.code, 0x34, 0x38)!
	directions := reader.read_table(table, 4)!
	mut result := {
		'uuid': identity
	}
	for key, value in recover_iodart_family_code_contract(functions, slots, directions.map(j.Value(it)))! {
		result[key] = value
	}
	return result
}

pub fn recover_t8110_dart_controller(reader ControllerReader) !map[string]j.Value {
	identity := controller_identity(reader, apple_t8110_dart_uuid, 'AppleT8110DART')!
	functions := controller_functions(reader, [apple_t8110_dart_start, apple_t8110_dart_setup,
		apple_t8110_dart_get_sid_property, apple_t8110_dart_get_sid_count,
		apple_t8110_dart_is_bypassed_sid, apple_t8110_dart_enable_translation,
		apple_t8110_dart_set_translation, apple_t8110_dart_set_translation_range,
		apple_t8110_dart_invalidate_tlb])!
	prefix := reader.read_cstring(function(functions, apple_t8110_dart_setup)!, 0xde8, 0xdec)!
	format := reader.read_cstring(function(functions, apple_t8110_dart_get_sid_property)!, 0x3c, 0x40)!
	mut result := {
		'uuid': identity
	}
	for key, value in recover_apple_t8110_dart_code_contract(functions, j.Value(prefix), j.Value(format))! {
		result[key] = value
	}
	return result
}

pub fn recover_kernel_controller(reader ControllerReader) !map[string]j.Value {
	identity := controller_identity(reader, t6050_kernel_uuid, 'T6050 kernel')!
	functions := controller_functions(reader, [t8110_dart_max_translation_levels,
		t8110_dart_vo_tt_index, t8110_dart_vo_tte])!
	body := function(functions, t8110_dart_vo_tt_index)!
	masks_address := g.read_adrp_add_address(body.address, body.code, 0x78, 0x7c)!
	shifts_address := g.read_adrp_add_address(body.address, body.code, 0x88, 0x8c)!
	masks := reader.read_table64(masks_address, 4)!
	shifts := reader.read_table(shifts_address, 4)!
	mut result := {
		'uuid': identity
	}
	for key, value in recover_t8110_kernel_code_contract(functions, masks.map(j.Value(it)), shifts.map(j.Value(it)))! {
		result[key] = value
	}
	return result
}

pub fn recover_ascwrap_controller(reader ControllerReader) !map[string]j.Value {
	identity := controller_identity(reader, apple_ascwrap_v6_uuid, 'AppleASCWrapV6')!
	functions := controller_functions(reader, [apple_ascwrap_v6_initialize,
		apple_ascwrap_v6_set_iorvbar, apple_ascwrap_v6_is_iorvbar_locked,
		apple_ascwrap_v6_map_firmware, apple_ascwrap_v6_run_cpu, apple_ascwrap_v6_inbox,
		apple_ascwrap_v6_outbox, apple_ascwrap_v6_kic_inbox_enabled, apple_ascwrap_v6_inbox_empty,
		apple_ascwrap_v6_inbox_full, apple_ascwrap_v6_outbox_empty, apple_ascwrap_v6_mailbox_item_size])!
	controller_strings(reader, function(functions, apple_ascwrap_v6_initialize)!, [
		StartString{0x84, 0x88, 'nmi-ext-irq'},
		StartString{0xa4, 0xa8, 'ext-irq-reg-index'},
		StartString{0x21c, 0x220, 'idle-ctrl-check'},
	], 'AppleASCWrapV6 initialize')!
	slots := controller_vtable(reader, apple_ascwrap_v6_vtable, [0x970, 0xa18, 0xa28])!
	return {
		'uuid':       identity
		'wrapper_v6': j.Value(recover_apple_ascwrap_v6_code_contract(functions, slots)!)
	}
}

pub fn recover_pmp_firmware_controller(reader ControllerReader, rtbuddy ControllerReader) !map[string]j.Value {
	identity := controller_identity(reader, apple_pmp_firmware_uuid, 'ApplePMPFirmware')!
	rtbuddy_identity := controller_identity(rtbuddy, rtbuddy_uuid, 'RTBuddy')!
	pmp_symbols := reader.symbols()!
	rtbuddy_symbols := rtbuddy.symbols()!
	pmp_functions := controller_functions(reader, [apple_pmp_firmware_start, apple_pmp_firmware_patch])!
	rtbuddy_functions := controller_functions(rtbuddy, [rtbuddy_firmware_fixup,
		rtbuddy_load_firmware_gated, rtbuddy_load_firmware, rtbuddy_perform_power_state_gated,
		rtbuddy_iop_validate, rtbuddy_iop_validate_polling, rtbuddy_iop_validate_blocking,
		rtbuddy_set_iop_status, rtbuddy_set_iop_status_public, rtbuddy_management_handle_hello,
		rtbuddy_management_handle_ep_rollcall, rtbuddy_build_roll_call, rtbuddy_get_endpoint,
		rtbuddy_create_endpoint, rtbuddy_endpoint_service_create_name, rtbuddy_init_config_edt,
		rtbuddy_attempt_firmware_load, rtbuddy_handle_preload_firmware, rtbuddy_firmware_preloaded,
		rtbuddy_firmware_iboot_loaded, rtbuddy_firmware_copy_id_block, rtbuddy_firmware_find_patchbay,
		rtbuddy_patchbay_init_with_data, rtbuddy_patchbay_find, rtbuddy_firmware_get_patchbay,
		rtbuddy_firmware_copy_patchbay_data, rtbuddy_firmware_patch_u32,
		rtbuddy_firmware_write_back_patchbay, rtbuddy_memcpy_to32, rtbuddy_get_segment_map,
		rtbuddy_segment_is_writable])!
	controller_strings(reader, function(pmp_functions, apple_pmp_firmware_start)!, [
		StartString{0xe0, 0xe4, 'role'},
		StartString{0x128, 0x12c, 'firmware-name'},
		StartString{0x1c8, 0x1cc, 'IODeviceTree:/chosen'},
		StartString{0x210, 0x214, 'board-id'},
		StartString{0x2a0, 0x2a4, 'dram-vendor-id'},
		StartString{0x358, 0x35c, 'dram-capacity'},
		StartString{0x3c0, 0x3c4, 'dram-channel-disable'},
		StartString{0x408, 0x40c, 'IODeviceTree:/arm-io/pmgr'},
		StartString{0x450, 0x454, 'pmc'},
		StartString{0x4e0, 0x4e4, 'pmc-pmgr'},
		StartString{0x5a0, 0x5a4, 'pmc-msg-disabled'},
		StartString{0x608, 0x60c, 'soc-chip-variant'},
		StartString{0x670, 0x674, 'Role'},
	], 'ApplePMPFirmware start')!
	pmp_slots := controller_vtable(reader, apple_pmp_firmware_vtable, [0x5f0, 0x898])!
	service_slots := controller_vtable(rtbuddy, rtbuddy_firmware_service_vtable, [
		0x890,
		0x898,
	])!
	firmware_slots := controller_vtable(rtbuddy, rtbuddy_firmware_vtable, [0x8a8, 0x8b0])!
	mut result := {
		'uuid':         identity
		'rtbuddy_uuid': rtbuddy_identity
	}
	result['firmware_load'] = j.Value(recover_apple_pmp_firmware_code_contract(pmp_functions,
		pmp_symbols, rtbuddy_functions, rtbuddy_symbols, pmp_slots, service_slots, firmware_slots)!)
	result['segment_flags'] = j.Value(recover_rtbuddy_segment_flag_contract(rtbuddy_functions, rtbuddy_symbols)!)
	result['patchbay_write'] = j.Value(recover_rtbuddy_patchbay_write_contract(rtbuddy_functions, rtbuddy_symbols)!)
	result['patchbay_format'] = j.Value(recover_rtbuddy_patchbay_contract_evidence(rtbuddy, rtbuddy_functions, rtbuddy_symbols)!)
	preload_slot := rtbuddy.vtable(rtbuddy_vtable, 0x9d8)!
	result['firmware_source'] = j.Value(recover_rtbuddy_firmware_source_contract_evidence(rtbuddy, rtbuddy_functions, rtbuddy_symbols, preload_slot)!)
	result['rtkit_boot'] = j.Value(recover_rtbuddy_boot_handshake_code_contract(rtbuddy_functions, rtbuddy_symbols)!)
	return result
}

pub fn query_controller_evidence(reader ControllerReader, secondary ControllerReader, operation string, request map[string]j.Value) !j.Value {
	result := match operation {
		'recover_apple_pmgr' { recover_pmgr_controller(reader)! }
		'recover_apple_t6050_pmgr' {
			recover_t6050_pmgr_controller(reader, j.value(request, 'apple_pmgr_symbols').as_map())!
		}
		'recover_apple_pmp' { recover_pmp_controller(reader, secondary)! }
		'recover_apple_pmp_firmware' { recover_pmp_firmware_controller(reader, secondary)! }
		'recover_apple_a7iop' { recover_a7iop_controller(reader)! }
		'recover_iodart_family' { recover_iodart_controller(reader)! }
		'recover_apple_t8110_dart' { recover_t8110_dart_controller(reader)! }
		'recover_t8110_kernel' { recover_kernel_controller(reader)! }
		'recover_apple_ascwrap_v6' { recover_ascwrap_controller(reader)! }
		else { return error('unknown T6050 controller operation ${operation}') }
	}
	return j.Value(result)
}

pub fn query_controller_image(data []u8, operation string, request map[string]j.Value) !j.Value {
	if operation in ['recover_apple_pmp', 'recover_apple_pmp_firmware'] {
		secondary := EncodedControllerImage{j.value(request, 'rtbuddy_image'), &ControllerImageState{}}
		return query_controller_evidence(ControllerImage{data}, secondary, operation, request)!
	}
	return query_controller_evidence(ControllerImage{data}, ControllerImage{}, operation, request)!
}

@[heap]
struct ControllerImageState {
mut:
	decoded bool
	image   []u8
}

// Decode the paired image exactly when its first reader call occurs. ApplePMP
// first reads primary symbols; ApplePMPFirmware checks the two UUIDs first.
// This state belongs to this synchronous request and is never returned.
struct EncodedControllerImage {
	encoded j.Value
	state   &ControllerImageState
}

fn (source EncodedControllerImage) materialized() !ControllerImage {
	mut state := source.state
	if !state.decoded {
		state.image = j.bytes_fromhex(j.string_value(j.value(source.encoded.as_map(), '$bytes')))!
		state.decoded = true
	}
	return ControllerImage{state.image}
}

fn (source EncodedControllerImage) identity() !j.Value { return source.materialized()!.identity()! }

fn (source EncodedControllerImage) symbols() !map[string]j.Value {
	return source.materialized()!.symbols()!
}

fn (source EncodedControllerImage) code(name string) !Function {
	return source.materialized()!.code(name)!
}

fn (source EncodedControllerImage) vtable(name string, slot int) !j.Value {
	return source.materialized()!.vtable(name, slot)!
}

fn (source EncodedControllerImage) read_cstring(body Function, adrp_offset int, add_offset int) !string {
	return source.materialized()!.read_cstring(body, adrp_offset, add_offset)!
}

fn (source EncodedControllerImage) read_table(address u64, count int) ![]u32 {
	return source.materialized()!.read_table(address, count)!
}

fn (source EncodedControllerImage) read_table64(address u64, count int) ![]u64 {
	return source.materialized()!.read_table64(address, count)!
}

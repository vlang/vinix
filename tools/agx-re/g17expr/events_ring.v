module g17expr

import encoding.binary
import math.big
import traceanalysis as j

fn firmware_event_ring(driver CommandImage, iogpu CommandImage, iosurface CommandImage, request map[string]j.Value) !j.Value {
	symbols := event_image_symbols(driver)!
	iogpu_symbols := event_image_symbols(iogpu)!
	iosurface_symbols := event_image_symbols(iosurface)!
	event_required(symbols, ['ACCELERATOR_START', 'FIRMWARE_INIT', 'FIRMWARE_DRAIN_EVENT_RING',
		'FIRMWARE_DRAIN_EVENT_RING_ROLE', 'FIRMWARE_RING_FETCH', 'G17_FIRMWARE_VTABLE',
		'G17_HANDLE_FIRMWARE_CONTROLLER_EVENT'], 'driver Mach-O has no ', false)!
	event_required(iogpu_symbols, ['IOGPU_EVENT_GET_NUM_STAMPS', 'IOGPU_EVENT_SIGNAL_STAMP',
		'IOGPU_EVENT_TEST_ALL_STAMPS', 'IOGPU_FENCE_INTERRUPT_OCCURRED', 'IOGPU_FENCE_NOTIFY_CLPC',
		'IOGPU_SCHEDULER_SIGNAL_HARDWARE_ERROR', 'IOGPU_SIGNAL_STAMPS_UPDATED',
		'IOGPU_WEAK_NAMESPACE_GET_OBJECT', 'IOGPU_WEAK_NAMESPACE_REMOVE_OBJECT'], 'IOGPUFamily Mach-O has no ', false)!
	event_required(iosurface_symbols, ['IOSURFACE_ROOT_SIGNAL_EVENT_ID'], 'IOSurface Mach-O has no ', false)!
	init_address, init := driver.code(event_symbol('FIRMWARE_INIT'))!
	_, wrapper := driver.code(event_symbol('FIRMWARE_DRAIN_EVENT_RING'))!
	role_address, role := driver.code(event_symbol('FIRMWARE_DRAIN_EVENT_RING_ROLE'))!
	_, fetch := driver.code(event_symbol('FIRMWARE_RING_FETCH'))!
	event_check(init, 'G17 firmware event-ring validator')!
	mask_bytes := driver.literal(init_address, init, 0x168, 0x16c, 16, request, 'driver')!
	if mask_bytes.len != 16 { return error('struct.error: unpack requires a buffer of 16 bytes') }
	mask := binary.little_endian_u64(mask_bytes[0..8])
	count := binary.little_endian_u64(mask_bytes[8..16])
	if mask != 0x2000ffd3 || count != 0x100 {
		return error('unexpected G17 firmware event mask/count (${mask}, ${count})')
	}
	event_check(wrapper, 'G17 dual-role firmware event drain')!
	event_check(role, 'G17 role firmware event drain')!
	page_word := word32(role, 0x104)!
	add_word := word32(role, 0x108)!
	page := fields('decode_adrp', page_word, role_address + big.integer_from_int(0x104)) or {
		return error('G17 firmware event dispatch table address changed')
	}
	add := fields('decode_add_immediate', add_word, big.zero_int) or {
		return error('G17 firmware event dispatch table address changed')
	}
	if page[0].int() != add[1].int() {
		return error('G17 firmware event dispatch table address changed')
	}
	table_address := big.integer_from_u64(page[1].u64()) + big.integer_from_u64(add[2].u64())
	table_offset := unpack_offset(driver.bytes, driver.virtual(table_address)!, 64)!
	mut dispatch := []j.Value{}
	for index in 0 .. 16 {
		dispatch << j.Value(int(i32(binary.little_endian_u32(driver.bytes[table_offset + index * 4..table_offset + index * 4 + 4]))))
	}
	actions := firmware_event_actions(driver, role_address, role, dispatch, symbols, iogpu_symbols, iosurface_symbols, request)!
	event_check(role, 'G17 firmware completion event')!
	for offset in [0x3bc, 0x3e8, 0x414, 0x440] {
		event_call(role_address, role, offset, iogpu_symbols, 'IOGPU_EVENT_SIGNAL_STAMP', 'G17 completion event no longer signals every firing bit', false)!
	}
	for offset, name in {
		0x12b8: 'IOGPU_FENCE_INTERRUPT_OCCURRED'
		0x12c0: 'IOGPU_SIGNAL_STAMPS_UPDATED'
		0x12c8: 'IOGPU_EVENT_TEST_ALL_STAMPS'
	} {
		event_call(role_address, role, offset, iogpu_symbols, name, 'G17 completion callback no longer calls ' + event_symbol(name), false)!
	}
	event_check(fetch, 'G17 firmware event-ring fetch')!
	mut result := event_metadata('recover_g17_firmware_event_ring').as_map()
	for key, value in actions { result[key] = value }
	result['entries'] = j.Value(count)
	result['accepted_event_mask'] = j.Value(mask)
	return expr(result)
}

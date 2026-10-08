module g17expr

import math.big
import traceanalysis as j

fn firmware_event_actions(driver CommandImage, address big.Integer, role []u8, offsets []j.Value,
	symbols map[string]j.Value, iogpu map[string]j.Value, iosurface map[string]j.Value,
	request map[string]j.Value) !map[string]j.Value {
	if offsets.len != 16 { return error('G17 firmware event dispatch table is not 16 entries') }
	for event_type in [2, 3, 5, 11] {
		event_role_dispatch(address, offsets, event_type, 0xbc, 'G17 firmware event direct host no-op dispatch changed')!
	}
	validators := firmware_event_validators(driver, address, role, request)!
	pm_memory := pm_memory_event(driver, address, role, offsets, symbols, request)!
	uma_async := uma_async_alloc_event(driver, address, role, offsets, symbols)!
	uma_flist := uma_flist_events(driver, address, role, offsets, symbols)!
	event_role_dispatch(address, offsets, 0, 0x11c, 'G17 firmware-controller event dispatch changed')!
	event_check(role, 'G17 firmware-controller event dispatch')!
	if !event_values_equal(event_vtable(driver, event_symbol('G17_FIRMWARE_VTABLE'), 0x878)!, event_target(symbols, 'G17_HANDLE_FIRMWARE_CONTROLLER_EVENT')!) {
		return error('G17 firmware-controller event vtable target changed')
	}
	_, controller := driver.code(event_symbol('G17_HANDLE_FIRMWARE_CONTROLLER_EVENT'))!
	event_noop(controller, 'G17 firmware-controller event handler is no longer a no-op')!
	event_role_dispatch(address, offsets, 14, 0x15c, 'G17 CLPC notification event dispatch changed')!
	event_check(role, 'G17 CLPC notification event')!
	event_call(address, role, 0x178, iogpu, 'IOGPU_FENCE_NOTIFY_CLPC', 'G17 CLPC notification target changed', false)!
	event_role_dispatch(address, offsets, 8, 0x290, 'G17 metrology-aging event dispatch changed')!
	event_check(role, 'G17 metrology-aging event')!
	start_address, start := driver.code(event_symbol('ACCELERATOR_START'))!
	event_check(start, 'G17 reliability-monitor service binding')!
	if event_cstring(driver, start_address, start, 0x2ca4, 0x2ca8, request)! != 'function-reliability_monitor' {
		return error('G17 metrology-aging reliability service changed')
	}
	event_role_dispatch(address, offsets, 4, 0x180, 'G17 GPU-restart event dispatch changed')!
	event_check(role, 'G17 GPU-restart event')!
	event_call(address, role, 0x19c, iogpu, 'IOGPU_EVENT_GET_NUM_STAMPS', 'G17 GPU-restart stamp-count target changed', false)!
	event_call(address, role, 0x284, iogpu, 'IOGPU_SCHEDULER_SIGNAL_HARDWARE_ERROR', 'G17 GPU-restart scheduler target changed', false)!
	event_role_dispatch(address, offsets, 7, 0x590, 'G17 channel-error event dispatch changed')!
	event_check(role, 'G17 channel-error event')!
	event_call(address, role, 0x5c4, iogpu, 'IOGPU_EVENT_GET_NUM_STAMPS', 'G17 channel-error stamp-count target changed', false)!
	event_role_dispatch(address, offsets, 10, 0x540, 'G17 shared-event completion dispatch changed')!
	event_check(role, 'G17 shared-event signal completion')!
	event_call(address, role, 0x584, iosurface, 'IOSURFACE_ROOT_SIGNAL_EVENT_ID', 'G17 shared-event completion target changed', false)!
	event_role_dispatch(address, offsets, 12, 0x6f4, 'G17 process-exit completion dispatch changed')!
	event_check(role, 'G17 process-exit completion')!
	event_call(address, role, 0x71c, iogpu, 'IOGPU_WEAK_NAMESPACE_GET_OBJECT', 'G17 process-exit namespace lookup target changed', false)!
	event_call(address, role, 0x734, iogpu, 'IOGPU_WEAK_NAMESPACE_REMOVE_OBJECT', 'G17 process-exit namespace removal target changed', false)!
	mut result := event_metadata('recover_g17_firmware_event_actions').as_map()
	mut targets := map[string]j.Value{}
	for index, offset in offsets { targets[index.str()] = event_add_offset(address, offset)! }
	result['jump_table_function_offsets'] = expr(targets)
	result['validated_event_types'] = expr(validators)
	result['deferred_host_noop_events'] = j.Value([uma_async])
	mut resources := [pm_memory]
	resources << uma_flist.arr()
	result['host_resource_events'] = j.Value(resources)
	return result
}

module g17expr

import g17decode as arm
import math.big
import traceanalysis as j

fn pm_memory_event(driver CommandImage, address big.Integer, role []u8, offsets []j.Value, symbols map[string]j.Value, request map[string]j.Value) !j.Value {
	event_required(symbols, ['ALLOCATE_PM_MEMORY_EVENT', 'ACCELERATOR_SUBMIT_DEVICE_CONTROL',
		'ARM_SUBMIT_DEVICE_CONTROL', 'SUBMIT_DEVICE_CONTROL', 'HWPB_MANAGER_META_CLASS',
		'PARAMETER_MANAGEMENT_GROW', 'PARAMETER_MANAGEMENT_VIRTUAL_GROW'], 'Mach-O is missing G17 PM-memory symbols: ', true)!
	event_dispatch(offsets, 6, 0xa0, 'G17 PM-memory event dispatch changed')!
	event_check(role, 'G17 PM-memory event')!
	start_address, start := driver.code(event_symbol('ACCELERATOR_START'))!
	event_check(start, 'G17 PM-memory worker registration')!
	if !event_values_equal(scalar(event_address(start_address, start, 0x3848, 0x384c)!), event_target(symbols, 'ALLOCATE_PM_MEMORY_EVENT')!) {
		return error('G17 PM-memory event source worker changed')
	}
	worker_address, worker := driver.code(event_symbol('ALLOCATE_PM_MEMORY_EVENT'))!
	event_check(worker, 'G17 PM-memory allocation worker')!
	if !event_values_equal(scalar(event_address(worker_address, worker, 0xec, 0xf0)!), event_target(symbols, 'ACCELERATOR_SUBMIT_DEVICE_CONTROL')!) {
		return error('G17 PM-memory device-control callback changed')
	}
	if !event_values_equal(scalar(event_address(worker_address, worker, 0x214, 0x218)!), event_target(symbols, 'HWPB_MANAGER_META_CLASS')!) {
		return error('G17 PM-memory manager class changed')
	}
	callback_address, callback := driver.code(event_symbol('ACCELERATOR_SUBMIT_DEVICE_CONTROL'))!
	event_check(callback, 'G17 accelerator device-control callback')!
	if !event_values_equal(scalar(callback_address), event_target(symbols, 'ACCELERATOR_SUBMIT_DEVICE_CONTROL')!) {
		return error('G17 accelerator device-control callback symbol moved')
	}
	physical := event_vtable(driver, event_symbol('PARAMETER_MANAGEMENT_VTABLE'), 0x190)!
	virtual := event_vtable(driver, event_symbol('PARAMETER_MANAGEMENT_VIRTUAL_VTABLE'), 0x190)!
	if !event_values_equal(physical, event_target(symbols, 'PARAMETER_MANAGEMENT_GROW')!) {
		return error('G17 physical parameter-memory grow action changed')
	}
	if !event_values_equal(virtual, event_target(symbols, 'PARAMETER_MANAGEMENT_VIRTUAL_GROW')!) {
		return error('G17 virtual parameter-memory grow action changed')
	}
	if !event_values_equal(event_vtable(driver, event_symbol('G17_FIRMWARE_VTABLE'), 0x280)!, event_target(symbols, 'ARM_SUBMIT_DEVICE_CONTROL')!) {
		return error('G17 PM-memory device-control submitter changed')
	}
	arm_address, arm_code := driver.code(event_symbol('ARM_SUBMIT_DEVICE_CONTROL'))!
	event_check(arm_code, 'G17 PM-memory device-control submission')!
	event_call(arm_address, arm_code, 0x8c, symbols, 'SUBMIT_DEVICE_CONTROL', 'G17 PM-memory base device-control submit target changed', false)!
	role_address := event_address(arm_address, arm_code, 0x60, 0x64)!
	roles := event_table(driver, role_address, 58, request)!
	for selected_role in roles {
		if event_role_greater_than_one(selected_role)! {
			return error('G17 PM-memory device-control role mapping changed')
		}
	}
	if roles.len <= 8 { return error('IndexError: tuple index out of range') }
	if !runtime_equal(roles[8], 0) {
		return error('G17 PM-memory device-control role mapping changed')
	}
	return event_metadata('recover_g17_pm_memory_event_action')
}

fn uma_flist_events(driver CommandImage, address big.Integer, role []u8, offsets []j.Value, symbols map[string]j.Value) !j.Value {
	event_required(symbols, ['USC_PRIV_MEM_FLIST_META_CLASS', 'IMPLICIT_GROW_ENGINE_VTABLE',
		'USC_PRIV_MEM_RETIRE_GROW_REQUEST', 'G17_HAL_UPDATE_UMA_DESC'], 'Mach-O is missing G17 UMA FList symbols: ', true)!
	event_dispatch(offsets, 13, 0x624, 'G17 UMA grow-completion dispatch changed')!
	event_dispatch(offsets, 15, 0x2f0, 'G17 UMA threshold dispatch changed')!
	event_check(role, 'G17 UMA grow-completion event')!
	if !event_values_equal(scalar(event_address(address, role, 0x76c, 0x770)!), event_target(symbols, 'USC_PRIV_MEM_FLIST_META_CLASS')!) {
		return error('G17 UMA grow-completion FList class changed')
	}
	if !event_values_equal(event_vtable(driver, event_symbol('IMPLICIT_GROW_ENGINE_VTABLE'), 0x180)!, event_target(symbols, 'USC_PRIV_MEM_RETIRE_GROW_REQUEST')!) {
		return error('G17 UMA grow-completion action changed')
	}
	event_check(role, 'G17 UMA threshold event')!
	if !event_values_equal(scalar(event_address(address, role, 0x814, 0x818)!), event_target(symbols, 'USC_PRIV_MEM_FLIST_META_CLASS')!) {
		return error('G17 UMA threshold FList class changed')
	}
	if !event_values_equal(event_vtable(driver, event_symbol('G17_ACCELERATOR_VTABLE'), 0x1120)!, event_target(symbols, 'G17_HAL_UPDATE_UMA_DESC')!) {
		return error('G17 UMA threshold descriptor action changed')
	}
	return event_metadata('recover_g17_uma_flist_event_actions')
}

fn uma_async_alloc_event(driver CommandImage, address big.Integer, role []u8, offsets []j.Value, symbols map[string]j.Value) !j.Value {
	if event_symbol('ALLOCATE_UMA_MEMORY_EVENT') !in symbols {
		return error('Mach-O is missing the G17 UMA allocation worker')
	}
	event_dispatch(offsets, 9, 0x47c, 'G17 UMA async-allocation event dispatch changed')!
	event_check(role, 'G17 UMA async-allocation event')!
	start_address, start := driver.code(event_symbol('ACCELERATOR_START'))!
	event_check(start, 'G17 UMA allocation worker registration')!
	if !event_values_equal(scalar(event_address(start_address, start, 0x38a4, 0x38a8)!), event_target(symbols, 'ALLOCATE_UMA_MEMORY_EVENT')!) {
		return error('G17 UMA allocation event source worker changed')
	}
	worker_address, worker := driver.code(event_symbol('ALLOCATE_UMA_MEMORY_EVENT'))!
	if !event_values_equal(scalar(worker_address), event_target(symbols, 'ALLOCATE_UMA_MEMORY_EVENT')!) {
		return error('G17 UMA allocation worker symbol moved')
	}
	event_noop(worker, 'G17 UMA allocation worker is no longer a no-op')!
	return event_metadata('recover_g17_uma_async_alloc_event_action')
}

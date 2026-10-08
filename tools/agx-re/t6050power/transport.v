module t6050power

import appleadt as a
import traceanalysis as j

pub fn recover_pmp_readiness_handshake(functions map[string]Function, symbols map[string]j.Value, interrupt_config j.Value) !map[string]j.Value {
	start_code_body := function(functions, pmgr_start)!
	start_address := start_code_body.address
	start_code := start_code_body.code
	if !branch_target_exists(Function{start_address, start_code}, symbol(symbols, pmp_init_v2)!)! {
		return error('ApplePMGR::start no longer runs the PMP v2 init')
	}
	init_code_body := function(functions, pmp_init_v2)!
	init_address := init_code_body.address
	init_code := init_code_body.code
	if !pc_target_exists(Function{init_address, init_code}, symbol(symbols, pmp_notify_initial)!)! {
		return error('PMP v2 init no longer schedules the initial status walk')
	}
	if !a.has_ordered_words(init_code, [
		u32(0xd2815711), // mov x17, #0xab8 -- _pmpV2() admission
		u32(0xf94dc260), // ldr x0, [x19, #0x1b80] -- command gate
		u32(0xd2803d11), // mov x17, #0x1e8 -- runAction
	]) {
		return error('PMP v2 init no longer gates the walk on its command gate')
	}
	entry_code_body := function(functions, pmp_notify_initial_entry)!
	entry_address := entry_code_body.address
	entry_code := entry_code_body.code
	if !pc_target_exists(Function{entry_address, entry_code}, symbol(symbols, pmp_notify_initial)!)! {
		return error('public initial-status entry no longer runs its gated action')
	}
	if !a.has_ordered_words(entry_code, [
		u32(0xf94dc000),
		u32(0xd2803d11),
	]) {
		return error('public initial-status entry no longer uses the command gate')
	}
	initial_code_body := function(functions, pmp_notify_initial)!
	initial_address := initial_code_body.address
	initial_code := initial_code_body.code
	if !a.has_ordered_words(initial_code, [
		u32(0x528c6088), // mov w8, #0x6304 -- die count
		u32(0x9140f808), // add x8, x0, #0x3e, lsl #12
		u32(0x9105f517), // add x23, x8, #0x17d -- per-die device-type bytes
		u32(0x528001d8), // mov w24, #0xe -- base command
		u32(0x52800039), // mov w25, #1 -- published state
		u32(0x39400108), // ldrb w8, [x8] -- device type
		u32(0x71003d1f), // cmp w8, #0xf -- PMP-managed device type
		u32(0x13001d08), // sxtb w8, w8 -- signed DeviceData flag byte
		u32(0x3100051f), // cmn w8, #1
		u32(0x1a98c701), // cinc w1, w24, le -- command 14 or 15
		u32(0xf10c7f5f), // cmp x26, #0x31f -- last scanned device ID
		u32(0x910c82f7), // add x23, x23, #0x320 -- next die
	]) {
		return error('initial PMP status walk changed')
	}
	ready_wait_slot := encoded_words([
		u32(0xd2815811), // mov x17, #0xac0
	])
	for proof in [
		ScopedProof{'PMP v2 init', Function{init_address, init_code}},
		ScopedProof{'initial PMP state sync', Function{initial_address, initial_code}},
	] {
		scope := proof.scope
		address := proof.function.address
		code := proof.function.code
		if bytes_contain(code, ready_wait_slot) {
			return error(scope + ' unexpectedly gained a PMP readiness wait')
		}
		targets := branch_targets(Function{address, code})!
		if targets_have(targets, symbol(symbols, pmp_wait_ready)!)! || targets_have(targets, symbol(symbols, pmp_ready_gated)!)! {
			return error(scope + ' unexpectedly gained a PMP readiness dependency')
		}
		if targets_have(targets, symbol(symbols, apple_ptd_read)!)! {
			return error(scope + ' unexpectedly gained an ApplePTD status read')
		}
	}
	interrupt_code_body := function(functions, pmgr_handle_interrupt_all)!
	interrupt_address := interrupt_code_body.address
	interrupt_code := interrupt_code_body.code
	if !pc_target_exists(Function{interrupt_address, interrupt_code}, symbol(symbols, pmp_ready_gated)!)! {
		return error('PMP readiness is no longer closed from the PMGR interrupt')
	}
	if !a.has_ordered_words(interrupt_code, [
		u32(0x9140fe68), // add x8, x19, #0x3f, lsl #12
		u32(0x91048117), // add x23, x8, #0x120 -- interrupt configuration block
		u32(0xd2815711), // mov x17, #0xab8 -- _pmpV2() admission
		u32(0x394042e8), // ldrb w8, [x23, #0x10] -- PMP ready slot
		u32(0x7103fd1f), // cmp w8, #0xff -- an absent slot closes nothing
		u32(0xb94002e8), // ldr w8, [x23] -- interrupts per die
		u32(0x1ac80809), // udiv w9, w0, w8 -- die
		u32(0x1b088128), // msub w8, w9, w8, w0 -- slot within the die
		u32(0x394042e9), // ldrb w9, [x23, #0x10]
		u32(0x6b09011f), // cmp w8, w9 -- only the PMP ready slot closes it
		u32(0x9141ca68), // add x8, x19, #0x72, lsl #12
		u32(0x91208118), // add x24, x8, #0x820 -- PMP-STATUS range
		u32(0xd2803d11), // mov x17, #0x1e8 -- runAction
	]) {
		return error('PMP readiness interrupt decode changed')
	}
	ready_v2_code_body := function(functions, pmp_ready_action_v2)!
	ready_v2_address := ready_v2_code_body.address
	ready_v2_code := ready_v2_code_body.code
	if !pc_target_exists(Function{ready_v2_address, ready_v2_code}, symbol(symbols, pmp_ready_gated)!)! {
		return error('per-die PMP ready entry no longer runs its gated action')
	}
	if !a.has_ordered_words(ready_v2_code, [
		u32(0xaa0103e2), // mov x2, x1 -- die becomes the gated argument
		u32(0xf94dc000), // ldr x0, [x0, #0x1b80] -- command gate
		u32(0xd2803d11), // mov x17, #0x1e8 -- runAction
	]) {
		return error('per-die PMP ready entry no longer forwards its die')
	}
	return j.Value(map[string]j.Value{
		'initial_publication': j.Value(map[string]j.Value{
			'driver_entry':                    j.Value(pmgr_start)
			'scheduler':                       j.Value(pmp_init_v2)
			'public_entry':                    j.Value(pmp_notify_initial_entry)
			'gated_action':                    j.Value(pmp_notify_initial)
			'command_gate_action_slot':        j.Value(u64(488))
			'waits_for_ready':                 j.Value(false)
			'reads_ptd_status':                j.Value(false)
			'device_type':                     j.Value(u64(15))
			'device_type_table_object_offset': j.Value(u64(254333))
			'device_type_die_stride':          j.Value(u64(800))
			'first_device_id':                 j.Value(u64(1))
			'last_device_id':                  j.Value(u64(799))
			'die_count_object_offset':         j.Value(u64(25348))
			'published_state':                 j.Value(u64(1))
			'command_selection':               j.Value('command 14, or 15 when the signed DeviceData flag byte is negative')
			'order':                           j.Value('ApplePMGR::start runs the whole publication inside _initPMPv2, so every initial level request precedes the first readiness observation; it is deliberate, not a race')
		})
		'ready_close':         j.Value(map[string]j.Value{
			'source':                           j.Value(pmgr_handle_interrupt_all)
			'interrupt_config':                 j.Value(interrupt_config)
			'admission':                        j.Value(pmgr_pmp_v2)
			'config_block_object_offset':       j.Value(u64(258336))
			'interrupts_per_die_object_offset': j.Value(u64(258336))
			'ready_slot_object_offset':         j.Value(u64(258352))
			'absent_slot_value':                j.Value(u64(255))
			'die_selector':                     j.Value('interrupt index / interrupts-per-die')
			'slot_selector':                    j.Value('interrupt index % interrupts-per-die')
			'per_die_entry':                    j.Value(pmp_ready_action_v2)
			'gated_action':                     j.Value(pmp_ready_gated)
			'effect':                           j.Value('latch the per-die ready byte, then command-gate wake every waiter')
			'secondary_source':                 j.Value('_waitForPMPReadyActionGatedv2 latches the same byte on its own when the PTD PMP-STATUS entry becomes nonzero, so the interrupt is not the only way the handshake closes')
		})
	}).as_map()
}

pub fn recover_rtbuddy_patchbay_write_contract(functions map[string]Function, symbols map[string]j.Value) !map[string]j.Value {
	required := [rtbuddy_firmware_get_patchbay, rtbuddy_firmware_copy_patchbay_data,
		rtbuddy_firmware_copy32_region, rtbuddy_firmware_find_patchbay, rtbuddy_firmware_patch_u32,
		rtbuddy_firmware_write_back_patchbay, rtbuddy_patchbay_find, rtbuddy_patchbay_with_data,
		rtbuddy_patchbay_get_bytes, rtbuddy_coredump_readwrite_map, rtbuddy_memcpy_to32]
	missing := required.filter(it !in symbols)
	if missing.len != 0 {
		return error('RTBuddy is missing patchbay-write symbols: ' + j.string_value(j.Value(missing.map(j.Value(it)))))
	}
	copy_code_body := function(functions, rtbuddy_firmware_copy_patchbay_data)!
	copy_address := copy_code_body.address
	copy_code := copy_code_body.code
	copy_targets := branch_targets(Function{copy_address, copy_code})!
	for name in [rtbuddy_firmware_find_patchbay, rtbuddy_firmware_copy32_region] {
		if !targets_have(copy_targets, j.value(symbols, name))! {
			return error('RTBuddy patchbay copy no longer calls ' + name)
		}
	}
	if !a.has_ordered_words(copy_code, [
		u32(0xf94007e1), // ldr x1, [sp, #8] -- located IOP virtual address
		u32(0xb94007e2), // ldr w2, [sp, #4] -- padded size
	]) {
		return error('RTBuddy patchbay copy arguments changed')
	}
	get_code_body := function(functions, rtbuddy_firmware_get_patchbay)!
	get_address := get_code_body.address
	get_code := get_code_body.code
	get_targets := branch_targets(Function{get_address, get_code})!
	for name in [rtbuddy_firmware_copy_patchbay_data, rtbuddy_patchbay_with_data] {
		if !targets_have(get_targets, j.value(symbols, name))! {
			return error('RTBuddy patchbay accessor no longer calls ' + name)
		}
	}
	if !a.has_ordered_words(get_code, [
		u32(0xf9406400), // ldr x0, [x0, #0xc8] -- cached patchbay
		u32(0x39003fff), // strb wzr, [sp, #0xf] -- assume not writable
		u32(0xb9000bff), // str wzr, [sp, #8] -- assume no alignment pad
		u32(0xf9006660), // str x0, [x19, #0xc8] -- cache the constructed bay
	]) {
		return error('RTBuddy patchbay caching changed')
	}
	write_code_body := function(functions, rtbuddy_firmware_patch_u32)!
	write_address := write_code_body.address
	write_code := write_code_body.code
	write_targets := branch_targets(Function{write_address, write_code})!
	for name in [rtbuddy_firmware_get_patchbay, rtbuddy_patchbay_find] {
		if !targets_have(write_targets, j.value(symbols, name))! {
			return error('RTBuddy patchbay write no longer calls ' + name)
		}
	}
	if !a.has_ordered_words(write_code, [
		u32(0xd2802c11), // mov x17, #0x160 -- OSData::getLength
		u32(0x7100101f), // cmp w0, #4 -- a wrong width is fatal here
		u32(0xd2803311), // mov x17, #0x198 -- OSData::getBytesNoCopy
		u32(0xb9400288), // ldr w8, [x20] -- the requested value
		u32(0xb9000008), // str w8, [x0] -- edited in place
		u32(0x52800020), // mov w0, #1
		u32(0x39007260), // strb w0, [x19, #0x1c] -- mark dirty
	]) {
		return error('RTBuddy patchbay write changed')
	}
	back_code_body := function(functions, rtbuddy_firmware_write_back_patchbay)!
	back_address := back_code_body.address
	back_code := back_code_body.code
	back_targets := branch_targets(Function{back_address, back_code})!
	for name in [rtbuddy_firmware_find_patchbay, rtbuddy_coredump_readwrite_map,
		rtbuddy_patchbay_get_bytes, rtbuddy_memcpy_to32] {
		if !targets_have(back_targets, j.value(symbols, name))! {
			return error('RTBuddy patchbay write-back no longer calls ' + name)
		}
	}
	if !a.has_ordered_words(back_code, [
		u32(0xf9406408), // ldr x8, [x0, #0xc8] -- cached patchbay
		u32(0x39407509), // ldrb w9, [x8, #0x1d] -- writable
		u32(0x36001089), // tbz w9, #0 -- a non-writable region writes nothing
		u32(0x39407108), // ldrb w8, [x8, #0x1c] -- dirty
		u32(0x36001048), // tbz w8, #0 -- an unedited patchbay writes nothing
		u32(0xf9405660), // ldr x0, [x19, #0xa8] -- coredump map
		u32(0xeb1702df), // cmp x22, x23 -- region starts inside the mapping
		u32(0x54000f83), // b.lo -- otherwise abort
		u32(0xeb08031f), // cmp x24, x8 -- region ends inside the mapping
		u32(0x54000de8), // b.hi -- otherwise abort
	]) {
		return error('RTBuddy patchbay write-back guards changed')
	}
	memcpy_code_body := function(functions, rtbuddy_memcpy_to32)!
	memcpy_code := memcpy_code_body.code
	if !a.has_ordered_words(memcpy_code, [
		u32(0x2a000088), // orr w8, w4, w0 -- length and destination
		u32(0xf240051f), // tst x8, #3 -- both must be 4-byte aligned
		u32(0x54000541), // b.ne -- otherwise fatal
		u32(0xb840458d), // ldr w13, [x12], #4
		u32(0xb800456d), // str w13, [x11], #4 -- 32-bit stores only
	]) {
		return error('RTBuddy 32-bit patchbay copy changed')
	}
	return j.Value(map[string]j.Value{
		'host_copy':  j.Value(map[string]j.Value{
			'accessor':            j.Value(rtbuddy_firmware_get_patchbay)
			'cache_object_offset': j.Value(u64(200))
			'reader':              j.Value(rtbuddy_firmware_copy32_region)
			'constructor':         j.Value(rtbuddy_patchbay_with_data)
			'scope':               j.Value('the whole padded region is copied into host memory once and cached; edits never touch the target directly')
		})
		'edit':       j.Value(map[string]j.Value{
			'writer':                j.Value(rtbuddy_firmware_patch_u32)
			'lookup':                j.Value(rtbuddy_patchbay_find)
			'required_value_bytes':  j.Value(u64(4))
			'wrong_width_is_fatal':  j.Value(true)
			'dirty_object_offset':   j.Value(u64(28))
			'ignores_writable_flag': j.Value(true)
			'scope':                 j.Value('the record value is edited in place in the host copy and the bay is marked dirty; a record whose length is not four is fatal here rather than skipped')
		})
		'write_back': j.Value(map[string]j.Value{
			'function':               j.Value(rtbuddy_firmware_write_back_patchbay)
			'writable_object_offset': j.Value(u64(29))
			'requires':               j.Value([j.Value('writable'), j.Value('dirty')])
			'mapping':                j.Value(rtbuddy_coredump_readwrite_map)
			'bounds':                 j.Value('the padded region must lie wholly inside the read-write map')
			'copy':                   j.Value(rtbuddy_memcpy_to32)
			'copy_width_bits':        j.Value(u64(32))
			'copy_alignment':         j.Value(u64(4))
			'scope':                  j.Value('the entire region is pushed back with 32-bit stores, which is why the located region is aligned down and padded up to four')
		})
	}).as_map()
}

pub fn recover_apple_ascwrap_v6_code_contract(functions map[string]Function, vtable_targets map[string]j.Value) !map[string]j.Value {
	required := [apple_ascwrap_v6_initialize, apple_ascwrap_v6_set_iorvbar,
		apple_ascwrap_v6_is_iorvbar_locked, apple_ascwrap_v6_map_firmware, apple_ascwrap_v6_run_cpu,
		apple_ascwrap_v6_inbox, apple_ascwrap_v6_outbox, apple_ascwrap_v6_kic_inbox_enabled,
		apple_ascwrap_v6_inbox_empty, apple_ascwrap_v6_inbox_full, apple_ascwrap_v6_outbox_empty,
		apple_ascwrap_v6_mailbox_item_size]
	missing := required.filter(it !in functions)
	if missing.len != 0 {
		return error('AppleASCWrapV6 has no code body for ' + j.string_value(j.Value(missing.map(j.Value(it)))))
	}
	expected_slots := map[string]j.Value{
		'2416': function(functions, apple_ascwrap_v6_initialize)!.address
		'2584': function(functions, apple_ascwrap_v6_map_firmware)!.address
		'2600': function(functions, apple_ascwrap_v6_run_cpu)!.address
	}
	if !integer_maps_equal(vtable_targets, expected_slots) {
		return error('AppleASCWrapV6 firmware/run vtable targets changed')
	}
	initialize_code_body := function(functions, apple_ascwrap_v6_initialize)!
	initialize_code := initialize_code_body.code
	if !a.has_ordered_words(initialize_code, [
		u32(0xf9407c00), // wrapper provider at this+0xf8
		u32(0xd280e211), // mapDeviceMemoryWithIndex slot 0x710
		u32(0x52800021), // device-memory index 1
		u32(0x52800002), // mapping options 0
		u32(0xd73f0910),
		u32(0xf900c660), // retained map at this+0x188
		u32(0xd2802711), // getVirtualAddress slot 0x138
		u32(0xd73f0910),
		u32(0xf900ca60), // mapped VA at this+0x190
	]) {
		return error('AppleASCWrapV6 IORVBAR resource mapping changed')
	}
	set_code_body := function(functions, apple_ascwrap_v6_set_iorvbar)!
	set_code := set_code_body.code
	expected_set := encoded_words([
		u32(0xd503245f), // bti c
		u32(0xb9418008), // ldr w8, [x0, #0x180] -- register byte offset
		u32(0xb2400029), // orr x9, x1, #1 -- address plus lock bit
		u32(0xf940c80a), // ldr x10, [x0, #0x190] -- device-memory index 1 VA
		u32(0x8b080148), // add x8, x10, x8
		u32(0xf9000109), // str x9, [x8]
		u32(0xd65f03c0), // ret
	])
	if set_code != expected_set {
		return error('AppleASCWrapV6 IORVBAR writer changed')
	}
	locked_code_body := function(functions, apple_ascwrap_v6_is_iorvbar_locked)!
	locked_code := locked_code_body.code
	expected_locked := encoded_words([
		u32(0xd503245f), // bti c
		u32(0xb9418008), // ldr w8, [x0, #0x180] -- register byte offset
		u32(0xf940c809), // ldr x9, [x0, #0x190] -- device-memory index 1 VA
		u32(0x8b080128), // add x8, x9, x8
		u32(0xf9400108), // ldr x8, [x8]
		u32(0x12000100), // and w0, w8, #1
		u32(0xd65f03c0), // ret
	])
	if locked_code != expected_locked {
		return error('AppleASCWrapV6 IORVBAR lock test changed')
	}
	map_code_body := function(functions, apple_ascwrap_v6_map_firmware)!
	map_code := map_code_body.code
	if !a.has_ordered_words(map_code, [
		u32(0x37080243), // options bit 1 skips this mapping path
		u32(0x94000eb4), // _hasiBootFirmware()
		u32(0x34000140), // no iBoot firmware: check inherited IORVBAR lock
		u32(0xf9409e61), // iBoot firmware: mapper at object +0x138
		u32(0xb9418268), // register byte offset at this+0x180
		u32(0xf940ca69), // device-memory index 1 VA at this+0x190
		u32(0x8b080128),
		u32(0xf9400108), // read IORVBAR
		u32(0x36000088), // fail closed when lock bit 0 is clear
	]) {
		return error('AppleASCWrapV6 firmware-map lock requirement changed')
	}
	run_code_body := function(functions, apple_ascwrap_v6_run_cpu)!
	run_code := run_code_body.code
	if !a.has_ordered_words(run_code, [
		u32(0x3944c808), // CPU-control permission byte at this+0x132
		u32(0x36000528), // no permission means no register access
		u32(0xd2813511), // _reg vtable slot 0x9a8
		u32(0x52800881), // register byte offset 0x44
		u32(0xd73f0910),
		u32(0xf9408268), // device-memory index 0 VA at this+0x100
		u32(0x34000094), // branch between run and stop sequences
		u32(0x321c0009), // run: set bit 4
		u32(0xb9004509), // store wrapper register 0x44
		u32(0x121b780a), // stop phase 1: clear bit 4
		u32(0xb900450a),
		u32(0xd2813511), // reread register 0x44
		u32(0x52800881),
		u32(0xd73f0910),
		u32(0x121a7808), // stop phase 2: clear bit 5
		u32(0xb9004528),
	]) {
		return error('AppleASCWrapV6 CPU run-control sequence changed')
	}
	inbox_code_body := function(functions, apple_ascwrap_v6_inbox)!
	inbox_code := inbox_code_body.code
	expected_inbox := encoded_words([
		u32(0xd503245f), // bti c
		u32(0xa9402428), // ldp x8, x9, [x1] -- complete 16-byte item
		u32(0xf940800a), // ldr x10, [x0, #0x100] -- reg[0] mapped VA
		u32(0x5291000b), // mov w11, #0x8800
		u32(0x8b0b014a), // add x10, x10, x11
		u32(0xa9002548), // stp x8, x9, [x10]
		u32(0xd65f03c0), // ret
	])
	if inbox_code != expected_inbox {
		return error('AppleASCWrapV6 mailbox inbox layout changed')
	}
	outbox_code_body := function(functions, apple_ascwrap_v6_outbox)!
	outbox_code := outbox_code_body.code
	expected_outbox := encoded_words([
		u32(0xd503245f), // bti c
		u32(0xf9408008), // ldr x8, [x0, #0x100] -- reg[0] mapped VA
		u32(0x52910609), // mov w9, #0x8830
		u32(0x8b090108), // add x8, x8, x9
		u32(0xa9402508), // ldp x8, x9, [x8]
		u32(0xa9002428), // stp x8, x9, [x1] -- complete 16-byte item
		u32(0xd65f03c0), // ret
	])
	if outbox_code != expected_outbox {
		return error('AppleASCWrapV6 mailbox outbox layout changed')
	}
	item_size_code_body := function(functions, apple_ascwrap_v6_mailbox_item_size)!
	item_size_code := item_size_code_body.code
	if item_size_code != encoded_words([
		u32(0xd503245f),
		u32(0x52800200),
		u32(0xd65f03c0),
	]) {
		return error('AppleASCWrapV6 mailbox item size changed')
	}
	status_contracts := [
		MailboxStatus{apple_ascwrap_v6_kic_inbox_enabled, u32(1385177601), u32(301989888)},
		MailboxStatus{apple_ascwrap_v6_inbox_empty, u32(1385177601), u32(1393640448)},
		MailboxStatus{apple_ascwrap_v6_inbox_full, u32(1385177601), u32(1393574528)},
		MailboxStatus{apple_ascwrap_v6_outbox_empty, u32(1385177729), u32(1393641088)},
	]
	for proof in status_contracts {
		name := proof.name
		register_offset := proof.register_offset
		bit_extract := proof.bit_extract
		code_body := function(functions, name)!
		code := code_body.code
		if !a.has_ordered_words(code, [
			u32(0xd2813511), // _reg vtable slot 0x9a8
			u32(register_offset),
			u32(0xd73f0910),
			u32(bit_extract),
		]) {
			return error('AppleASCWrapV6 mailbox status accessor changed: ' + name)
		}
	}
	return j.Value(map[string]j.Value{
		'iorvbar':         j.Value(map[string]j.Value{
			'device_memory_index':           j.Value(u64(1))
			'map_options':                   j.Value(u64(0))
			'memory_map_object_offset':      j.Value(u64(392))
			'mapped_virtual_address_offset': j.Value(u64(400))
			'register_offset_object_offset': j.Value(u64(384))
			't6050_register_offset':         j.Value(u64(0))
			'access_width_bits':             j.Value(u64(64))
			'write_value':                   j.Value('firmware address OR lock bit 0')
			'map_firmware':                  j.Value(map[string]j.Value{
				'options_skip_bit':      j.Value(u64(1))
				'iboot_probe':           j.Value('_hasiBootFirmware')
				'iboot_behavior':        j.Value('process segment records through mapper; do not access IORVBAR')
				'non_iboot_requirement': j.Value('IORVBAR lock bit 0 must already be set')
			})
		})
		'cpu_run_control': j.Value(map[string]j.Value{
			'device_memory_index':           j.Value(u64(0))
			'register_offset':               j.Value(u64(68))
			'access_width_bits':             j.Value(u64(32))
			'run':                           j.Value('read-modify-write setting bit 4')
			'stop':                          j.Value('read-modify-write clearing bit 4, then reread and clear bit 5')
			'permission_object_offset':      j.Value(u64(306))
			'filter_property':               j.Value('cpu-ctrl-filtered')
			't6050_filter_property_present': j.Value(false)
		})
		'mailbox_v4':      j.Value(map[string]j.Value{
			'device_memory_index': j.Value(u64(0))
			'window_offset':       j.Value(u64(32768))
			'window_size':         j.Value(u64(4096))
			'item_size':           j.Value(u64(16))
			'access_width_bits':   j.Value(u64(64))
			'registers':           j.Value(map[string]j.Value{
				'a2i_control': j.Value(u64(272))
				'i2a_control': j.Value(u64(276))
				'a2i_message': j.Value(u64(2048))
				'i2a_message': j.Value(u64(2096))
			})
			'status_bits':         j.Value(map[string]j.Value{
				'kic_inbox_enabled': j.Value(u64(0))
				'full':              j.Value(u64(16))
				'empty':             j.Value(u64(17))
			})
			'message_words':       j.Value(u64(2))
			'endpoint':            j.Value('low byte of the second 64-bit word')
		})
		'vtable_slots':    j.Value(map[string]j.Value{
			'initialize':    j.Value(u64(2416))
			'map_firmware':  j.Value(u64(2584))
			'run_cpu':       j.Value(u64(2600))
			'register_read': j.Value(u64(2472))
		})
		'scope':           j.Value('concrete firmware/run register contract only; it does not prove that PMP reached RTKit or dashboard readiness')
	}).as_map()
}

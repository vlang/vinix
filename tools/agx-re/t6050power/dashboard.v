module t6050power

import appleadt as a
import traceanalysis as j
import g17decode as g
import math.big

pub fn recover_pmp_code_contract(functions map[string]Function, symbols map[string]j.Value, interrupt_config j.Value) !map[string]j.Value {
	required := [pmp_send_command, pmp_write_dashboard, pmp_set_device_state,
		pmp_set_virtual_device_state, pmp_init_v2, pmp_get_device_index, pmp_notify_initial,
		pmp_notify_initial_entry, pmp_wait_cluster_power_up, pmp_enable_device_gated,
		pmp_device_id_to_data, pmp_check_notify, pmp_wait_ready, pmp_wait_ready_v2, pmp_ready_gated,
		pmp_ready_action_v2, pmgr_start, pmgr_handle_interrupt_all, apple_ptd_read, apple_ptd_write,
		pmgr_get_reg_map, pmgr_write_reg64]
	missing := required.filter(it !in symbols)
	if missing.len != 0 {
		return error('ApplePMGR is missing power symbols: ' + j.string_value(j.Value(missing.map(j.Value(it)))))
	}
	for name in [pmp_send_command, pmp_write_dashboard, pmp_set_device_state,
		pmp_set_virtual_device_state, pmp_init_v2, pmp_get_device_index, pmp_notify_initial,
		pmp_notify_initial_entry, pmp_wait_cluster_power_up, pmp_enable_device_gated, pmp_wait_ready,
		pmp_wait_ready_v2, pmp_ready_gated, pmp_ready_action_v2, pmgr_start, pmgr_handle_interrupt_all,
		apple_ptd_read, apple_ptd_write, pmgr_write_reg64] {
		if name !in functions {
			return error('ApplePMGR has no code body for ' + name)
		}
	}
	ptd_transport := recover_apple_ptd_code_contract(functions, symbols)!
	send_code_body := function(functions, pmp_send_command)!
	send_address := send_code_body.address
	send_code := send_code_body.code
	if !branch_target_exists(Function{send_address, send_code}, j.value(symbols, pmp_write_dashboard))! {
		return error('sendPMPCommand no longer routes to the PMP dashboard')
	}
	dispatch_code_body := function(functions, pmp_write_dashboard)!
	dispatch_address := dispatch_code_body.address
	dispatch_code := dispatch_code_body.code
	dispatch_targets := branch_targets(Function{dispatch_address, dispatch_code})!
	if !a.has_sub_cmp_window(dispatch_code, 1, 14, 2) {
		return error('PMP dashboard no longer selects the command-14/15 window')
	}
	for target in [pmp_set_device_state, pmp_set_virtual_device_state] {
		if !targets_have(dispatch_targets, j.value(symbols, target))! {
			return error('PMP dashboard no longer dispatches to ' + target)
		}
	}
	if !a.has_ordered_words(dispatch_code, [
		u32(0x39400008), // ldrb w8, [x0] -- DeviceData flags
		u32(0x362003c8), // tbz w8, #4 -- ordinary-device fallback
		u32(0x39c03c08), // ldrsb w8, [x0, #0xf] -- virtual class
		u32(0x37f80388), // tbnz w8, #31 -- ordinary-device fallback
	]) {
		return error('PMP dashboard virtual-device dispatch predicate changed')
	}
	state_code_body := function(functions, pmp_set_device_state)!
	state_address := state_code_body.address
	state_code := state_code_body.code
	state_targets := branch_targets(Function{state_address, state_code})!
	if !a.has_cmp_w_immediate(state_code, 3, 2) {
		return error('PMP device dashboard no longer bounds state to 0/1')
	}
	if !a.has_ldrb(state_code, 8, 0, 3) {
		return error('PMP device dashboard index is no longer DeviceData byte 3')
	}
	for target in [apple_ptd_read, apple_ptd_write] {
		if !targets_have(state_targets, j.value(symbols, target))! {
			return error('PMP device dashboard no longer calls ' + target)
		}
	}
	if branch_count(Function{state_address, state_code}, j.value(symbols, apple_ptd_write))! != 1 {
		return error('PMP device dashboard request write count changed')
	}
	if !a.has_ordered_words(state_code, [
		u32(0x39400c08), // ldrb w8, [x0, #3] -- DeviceData selector
		u32(0xb9406b69), // ldr w9, [x27, #0x68] -- selector die stride
		u32(0x1b162128), // madd w8, w9, w22, w8 -- selector + stride*die
		u32(0xb9400153), // ldr w19, [x10] -- mapped soc-device record index
		u32(0x52837b88), // mov w8, #0x1bdc -- multi-PMP flag byte
		u32(0x39400108), // ldrb w8, [x8]
		u32(0x7200011f), // tst w8, #1
		u32(0x1a9f12d5), // csel w21, w22, wzr, ne -- selected PTD die
	]) {
		return error('PMP device-state selector or PTD die selection changed')
	}
	if !a.has_ordered_words(state_code, [
		u32(0x52800029), // mov w9, #1
		u32(0x9ad3213a), // lsl x26, x9, x19 -- 1 << soc-device index
		u32(0xf9401b61), // ldr x1, [x27, #0x30] -- PS-REQ range
		u32(0xaa1a0109), // orr x9, x8, x26 -- requested state 1
		u32(0x8a3a0108), // bic x8, x8, x26 -- requested state 0
		u32(0x7100033f), // cmp w25, #0
		u32(0x9a890103), // csel x3, x8, x9, eq -- select request value
		u32(0xf9401b61), // ldr x1, [x27, #0x30] -- write PS-REQ
	]) {
		return error('PMP device-state request encoding changed')
	}
	if !a.has_ordered_words(state_code, [
		u32(0xb9400148), // ldr w8, [x10] -- soc-device state flags at +8
		u32(0x360812c8), // tbz w8, #1 -- no acknowledgement required
		u32(0x53020908), // ubfx w8, w8, #2, #1 -- skip-enable-ack flag
		u32(0x52800c80), // mov w0, #100
		u32(0x52884801), // mov w1, #0x4240
		u32(0x72a001e1), // movk w1, #0xf -- 1,000,000 (100 ms)
		u32(0x528001e0), // mov w0, #15
		u32(0x52994001), // mov w1, #0xca00
		u32(0x72a77341), // movk w1, #0x3b9a -- 1,000,000,000 (15 s)
		u32(0xf9402b61), // ldr x1, [x27, #0x50] -- PMP-STATUS range
		u32(0xf9401f61), // ldr x1, [x27, #0x38] -- PS-ACK range
		u32(0xa979a3b3), // ldp x19, x8, [x29, #-0x68] -- ack data/metadata
		u32(0x924a0114), // and x20, x8, #0x40000000000000 -- newData bit 54
		u32(0xb4fff234), // cbz x20 -- poll until newData
		u32(0xca080268), // eor x8, x19, x8 -- ack versus requested value
		u32(0x8a1a0108), // and x8, x8, x26 -- compare this device bit
		u32(0xb5fff1a8), // cbnz x8 -- poll until requested value matches
		u32(0xf9402f68), // ldr x8, [x27, #0x58] -- PMPTOOL diagnostics
	]) {
		return error('PMP device-state acknowledgement loop changed')
	}

	status_prefix := encoded_words([u32(0xf9400380), u32(0xf9402b61), u32(0xb9400422), u32(0xd101a3a3),
		u32(0xaa1503e4)])
	status_offset := bytes_find(state_code, status_prefix, 0)
	status_suffix := encoded_words([u32(0xf85983a8), u32(0xf100011f), u32(0x1a9f07e8), u32(0x39000328)])
	if status_offset < 0 || !branch_at_equal(Function{state_address, state_code}, status_offset + 20, symbol(symbols, apple_ptd_read)!)! || bytes_slice(state_code, status_offset + 24, status_offset + 40) != status_suffix {
		return error('PMP device-state status probe changed')
	}
	ready_offset := bytes_find(state_code, encoded_words([u32(0x39400328)]), status_offset + 40)
	ready_branch := if ready_offset >= 0 && ready_offset + 8 <= state_code.len {
		g.decode('decode_test_bit_branch', word_at(state_code, ready_offset + 4), pc_at(state_address, ready_offset + 4)!)
	} else {
		j.value(map[string]j.Value{}, 'missing')
	}
	success_target := if ready_branch is map[string]j.Value {
		j.value(ready_branch, 'target')
	} else {
		j.Value(-1)
	}
	success_offset := g.integer(success_target)! - g.integer(state_address)!
	ack_prefix := encoded_words([u32(0xf9400380), u32(0xf9401f61), u32(0xb9400422), u32(0xd101a3a3),
		u32(0xaa1503e4)])
	if !ready_clear_branch(ready_branch, success_target) || bytes_slice(state_code, ready_offset + 8, ready_offset + 28) != ack_prefix || !branch_at_equal(Function{state_address, state_code}, ready_offset + 28, symbol(symbols, apple_ptd_read)!)! || success_offset < big.integer_from_int(ready_offset + 32) || success_offset + big.integer_from_int(4) > big.integer_from_int(state_code.len) || word_at(state_code, bounded_offset(success_offset)!) != u32(0x52800014) {
		return error('PMP device-state pre-ready acknowledgement bypass changed')
	}
	mut write_offsets := []int{}
	for offset := 0; offset + 4 <= state_code.len; offset += 4 {
		if branch_at_equal(Function{state_address, state_code}, offset, symbol(symbols, apple_ptd_write)!)! {
			write_offsets << offset
		}
	}
	if write_offsets.len != 1 { return error('PMP device-state request write ownership changed') }
	if !(write_offsets[0] < status_offset && status_offset < ready_offset) {
		return error('PMP device-state request/status ordering changed')
	}
	init_code_body := function(functions, pmp_init_v2)!
	init_code := init_code_body.code
	if !a.has_words_in_order(init_code, [
		u32(0x9141ca68), // add x8, x19, #0x72000
		u32(0x91212117), // add x23, x8, #0x848
		u32(0xaa1703e0), // mov x0, x23
		u32(0x52801fe1), // mov w1, #0xff
		u32(0x52808082), // mov w2, #0x404
	]) {
		return error('initPMPv2 no longer initializes the device-index table')
	}
	if !a.has_words_in_order(init_code, [
		u32(0x9141ca68), // add x8, x19, #0x72000
		u32(0x91313118), // add x24, x8, #0xc4c
		u32(0xaa1803e0), // mov x0, x24
		u32(0x52801fe1), // mov w1, #0xff
		u32(0x52808082), // mov w2, #0x404
	]) {
		return error('initPMPv2 no longer initializes the virtual-state table')
	}
	if !a.has_words_in_order(init_code, [
		u32(0xb94002cb), // ldr w11, [x22] -- soc-device ID
		u32(0xd37ef56b), // lsl x11, x11, #2
	]) || !a.has_ordered_words(init_code, [
		u32(0xb9000188), // str w8, [x12] -- table[ID] = record index
		u32(0x91000508), // add x8, x8, #1
		u32(0x9101f2d6), // add x22, x22, #0x7c
	]) {
		return error('initPMPv2 no longer maps SoC-device IDs to record indices')
	}
	if !a.has_ordered_words(init_code, [
		u32(0xb9402ecb), // ldr w11, [x22, #0x2c]
		u32(0xb94002cb), // ldr w11, [x22] -- soc-device ID
		u32(0xb9000189), // str w9, [x12] -- dense virtual-state index
		u32(0x11000529), // add w9, w9, #1
	]) {
		return error('initPMPv2 no longer constructs the virtual-state table')
	}
	lookup_code_body := function(functions, pmp_get_device_index)!
	lookup_code := lookup_code_body.code
	if !a.has_words_in_order(lookup_code, [
		u32(0x39400c08), // ldrb w8, [x0, #3]
		u32(0x9141ca69), // add x9, x19, #0x72000
		u32(0x9120e129), // add x9, x9, #0x838
		u32(0xb9400129), // ldr w9, [x9]
		u32(0x1b142128), // madd w8, w9, w20, w8
		u32(0x7104011f), // cmp w8, #0x100
	]) || !a.has_words_in_order(lookup_code, [
		u32(0x9141ca69), // add x9, x19, #0x72000
		u32(0x91212129), // add x9, x9, #0x848
	]) {
		return error('getPMPDeviceIndex no longer uses selector + die*stride')
	}
	virtual_code_body := function(functions, pmp_set_virtual_device_state)!
	virtual_address := virtual_code_body.address
	virtual_code := virtual_code_body.code
	virtual_targets := branch_targets(Function{virtual_address, virtual_code})!
	if !a.has_cmp_w_immediate(virtual_code, 3, 2) {
		return error('PMP virtual-device dashboard no longer bounds state to 0/1')
	}
	if !a.has_ldrb(virtual_code, 8, 0, 3) {
		return error('PMP virtual-device selector is no longer DeviceData byte 3')
	}
	if !a.has_ordered_words(virtual_code, [
		u32(0x9131314a), // add x10, x10, #0xc4c -- virtual-state table
		u32(0xb9400179), // ldr w25, [x11] -- dense PTD entry index
	]) {
		return error('PMP virtual-device dashboard no longer uses its dense map')
	}
	if !targets_have(virtual_targets, j.value(symbols, apple_ptd_write))! {
		return error('PMP virtual-device dashboard no longer writes ApplePTD')
	}
	initial_code_body := function(functions, pmp_notify_initial)!
	initial_address := initial_code_body.address
	initial_code := initial_code_body.code
	initial_targets := branch_targets(Function{initial_address, initial_code})!
	for target in [pmp_device_id_to_data, pmp_wait_cluster_power_up, pmp_send_command] {
		if !targets_have(initial_targets, j.value(symbols, target))! {
			return error('initial PMP state sync no longer calls ' + target)
		}
	}
	if !a.has_ordered_words(initial_code, [
		u32(0x394002a8), // ldrb w8, [x21] -- DeviceData flags
		u32(0x360801a8), // tbz w8, #1 -- skip records that do not notify PMP
		u32(0x794036a8), // ldrh w8, [x21, #0x1a] -- public handle
		u32(0x35000048), // cbnz w8 -- prefer a nonzero public handle
		u32(0x39400ea8), // ldrb w8, [x21, #3] -- selector fallback
		u32(0xa900e7e8), // stp x8, x25, [sp, #8] -- target and state 1
	]) {
		return error('initial PMP state-notification filter changed')
	}
	cluster_code_body := function(functions, pmp_wait_cluster_power_up)!
	cluster_address := cluster_code_body.address
	cluster_code := cluster_code_body.code
	cluster_targets := branch_targets(Function{cluster_address, cluster_code})!
	if targets_have(cluster_targets, j.value(symbols, apple_ptd_read))! || targets_have(cluster_targets, j.value(symbols, pmp_wait_ready))! || !a.has_ordered_words(cluster_code, [
		u32(0x79403437), // ldrh w23, [x1, #0x1a] -- public handle
		u32(0x35000057), // cbnz w23 -- otherwise selector byte
		u32(0x39400c37), // ldrb w23, [x1, #3]
		u32(0x394026cd), // ldrb w13, [x22, #9] -- cluster transition byte
		u32(0x370000ed), // tbnz w13, #0 -- sleep while transitioning
		u32(0xd2804011), // mov x17, #0x200 -- command-gate sleep slot
		u32(0x910026c1), // add x1, x22, #9 -- sleep event
		u32(0x52800002), // mov w2, #0
		u32(0x384092c8), // ldurb w8, [x22, #9]
		u32(0x3707fe68), // tbnz w8, #0 -- retry until cluster is stable
	]) {
		return error('initial PMP cluster-power wait changed')
	}
	enable_code_body := function(functions, pmp_enable_device_gated)!
	enable_address := enable_code_body.address
	enable_code := enable_code_body.code
	enable_targets := branch_targets(Function{enable_address, enable_code})!
	for target in [pmp_device_id_to_data, pmp_check_notify, pmp_send_command] {
		if !targets_have(enable_targets, j.value(symbols, target))! {
			return error('dynamic PMP state sync no longer calls ' + target)
		}
	}
	notify_test := encoded_words([
		u32(0x360801c8), // tbz w8, #1
	])
	wait_slot := encoded_words([
		u32(0xd2815811), // mov x17, #0xac0
	])
	if bytes_count(enable_code, notify_test) != 2 || bytes_count(enable_code, wait_slot) != 1 || bytes_find(enable_code, wait_slot, 0) > bytes_find(enable_code, notify_test, 0) || !a.has_ordered_words(enable_code, [
		u32(0x794002a1), // ldrh w1, [x21] -- changed device ID
		u32(0x39400008), // ldrb w8, [x0] -- DeviceData flags
		u32(0x360801c8), // tbz w8, #1 -- skip non-notifying records
	]) {
		return error('dynamic PMP state-notification filter changed')
	}
	wait_code_body := function(functions, pmp_wait_ready)!
	wait_code := wait_code_body.code
	if !a.has_ordered_words(wait_code, [
		u32(0xd2815611), // mov x17, #0xab0 -- pmpV1 predicate slot
		u32(0xd2803d11), // mov x17, #0x1e8 -- command-gate action
		u32(0xd2815711), // mov x17, #0xab8 -- pmpV2 predicate slot
		u32(0xd2803d11), // mov x17, #0x1e8 -- command-gate action
	]) {
		return error('PMP readiness version/command-gate dispatch changed')
	}
	wait_v2_code_body := function(functions, pmp_wait_ready_v2)!
	wait_v2_address := wait_v2_code_body.address
	wait_v2_code := wait_v2_code_body.code
	wait_v2_targets := branch_targets(Function{wait_v2_address, wait_v2_code})!
	if !targets_have(wait_v2_targets, j.value(symbols, apple_ptd_read))! || !a.has_ordered_words(wait_v2_code, [
		u32(0xb95bf000), // ldr w0, [x0, #0x1bf0] -- timeout seconds
		u32(0x9141ca88), // add x8, x20, #0x72000
		u32(0x9120f108), // add x8, x8, #0x83c -- per-die ready bytes
		u32(0x394002a8), // ldrb w8, [x21] -- already ready
		u32(0x9141ce88), // add x8, x20, #0x73000
		u32(0x9121c117), // add x23, x8, #0x870 -- ApplePTD pointer
		u32(0x9141ca88), // add x8, x20, #0x72000
		u32(0x91208118), // add x24, x8, #0x820 -- PMP-STATUS range pointer
		u32(0xf94dc280), // ldr x0, [x20, #0x1b80] -- command gate
		u32(0x91084208), // add x8, x16, #0x210 -- deadline sleep slot
		u32(0xf94002e0), // ldr x0, [x23] -- ApplePTD
		u32(0xf9400301), // ldr x1, [x24] -- PMP-STATUS range
		u32(0xb9400422), // ldr w2, [x1, #4] -- PTD entry offset
		u32(0xf94023e8), // ldr x8, [sp, #0x40] -- returned PTD value
		u32(0xb5000188), // cbnz x8 -- a nonzero status is ready
		u32(0x52800028), // mov w8, #1
		u32(0x390002a8), // strb w8, [x21] -- latch per-die ready
	]) {
		return error('PMPv2 PTD readiness wait changed')
	}
	ready_code_body := function(functions, pmp_ready_gated)!
	ready_code := ready_code_body.code
	if !a.has_ordered_words(ready_code, [
		u32(0xd2815611), // mov x17, #0xab0 -- pmpV1 predicate slot
		u32(0xd2815711), // mov x17, #0xab8 -- pmpV2 predicate slot
		u32(0x9141ca68), // add x8, x19, #0x72000
		u32(0x9120f108), // add x8, x8, #0x83c -- per-die ready bytes
		u32(0x52800028), // mov w8, #1
		u32(0x39000028), // strb w8, [x1] -- latch ready
		u32(0xf94dc260), // ldr x0, [x19, #0x1b80] -- command gate
		u32(0xd2804111), // mov x17, #0x208 -- wakeup slot
		u32(0x52800002), // mov w2, #0 -- wake one/all mode
	]) {
		return error('PMP readiness callback changed')
	}
	readiness_handshake := recover_pmp_readiness_handshake(functions, symbols, interrupt_config)!
	return j.Value(map[string]j.Value{
		'device_state_commands': j.Value([j.Value(u64(14)), j.Value(u64(15))])
		'device_states':         j.Value([j.Value(u64(0)), j.Value(u64(1))])
		'device_index_field':    j.Value(u64(3))
		'device_dispatch':       j.Value(map[string]j.Value{
			'virtual_flag':          j.Value(u64(16))
			'virtual_class_field':   j.Value(u64(15))
			'virtual_class_minimum': j.Value(u64(0))
		})
		'ordinary_request_ack':  j.Value(map[string]j.Value{
			'request_range_object_offset':       j.Value(u64(468992))
			'ack_range_object_offset':           j.Value(u64(469000))
			'status_range_object_offset':        j.Value(u64(469024))
			'diagnostic_range_object_offset':    j.Value(u64(469032))
			'device_mask':                       j.Value('1 << soc-device record index')
			'device_index_lookup':               j.Value('table[DeviceData selector + selector-die-stride * requested die]')
			'selector_die_stride_object_offset': j.Value(u64(469048))
			'multi_pmp_flag':                    j.Value(map[string]j.Value{
				'object_offset': j.Value(u64(7132))
				'bit':           j.Value(u64(0))
			})
			'ptd_die':                           j.Value('requested die when multi-PMP bit 0 is set; otherwise die 0')
			'request':                           j.Value('read-modify-write; clear for state 0, set for state 1')
			'ack_required_flag':                 j.Value(u64(2))
			'skip_state_1_ack_flag':             j.Value(u64(4))
			'ack_new_data':                      j.Value(map[string]j.Value{
				'metadata_word': j.Value(u64(1))
				'bit':           j.Value(u64(54))
			})
			'success':                           j.Value('newData is set and the selected ack bit equals the request')
			'timeout_seconds':                   j.Value(u64(15))
			'computed_poll_deadline_ms':         j.Value(u64(100))
			'poll_deadline_observed_use':        j.Value('recomputed in the loop but never read by this function')
			'request_after_success':             j.Value('preserved; there is no second PTD write')
			'pre_ready_behavior':                j.Value('publish the persistent request, sample PMP-STATUS, and return success without reading PS-ACK when status is zero')
			'ready_behavior':                    j.Value('latch the per-die ready byte and poll PS-ACK when PMP-STATUS is nonzero')
			'timeout':                           j.Value('dump the PMPTOOL PTD range and panic')
		})
		'state_notification':    j.Value(map[string]j.Value{
			'flag':                       j.Value(u64(2))
			'flags_field':                j.Value(u64(0))
			'initial_sync':               j.Value(pmp_notify_initial)
			'dynamic_sync':               j.Value(pmp_enable_device_gated)
			'target':                     j.Value('public handle at +0x1a, selector byte at +3 if zero')
			'initial_precondition':       j.Value('wait for dependent cluster transition bytes to become stable')
			'initial_precondition_scope': j.Value('cluster power only; it does not read ApplePTD or call the PMP-ready wait')
		})
		'readiness':             j.Value(map[string]j.Value{
			'scope':                            j.Value('per die')
			'virtual_wait_slot':                j.Value(u64(2752))
			'command_gate_object_offset':       j.Value(u64(7040))
			'command_gate_action_slot':         j.Value(u64(488))
			'command_gate_sleep_deadline_slot': j.Value(u64(528))
			'command_gate_wakeup_slot':         j.Value(u64(520))
			'timeout_seconds_object_offset':    j.Value(u64(7152))
			'ready_bytes_object_offset':        j.Value(u64(469052))
			'ptd_driver_object_offset':         j.Value(u64(473200))
			'status_range_object_offset':       j.Value(u64(469024))
			'ready_value':                      j.Value('nonzero 64-bit PMP-STATUS entry')
			'dynamic_transition_order':         j.Value('checkNotifyPMP, wait until ready, mutate device state, then emit command 14/15')
			'initial_sync':                     j.Value('scheduled separately; it may publish level requests before ready, and the ordinary transaction then bypasses PS-ACK while status is zero')
		})
		'readiness_handshake':   j.Value(readiness_handshake)
		'device_index_map':      j.Value(map[string]j.Value{
			'source':                   j.Value('soc-device')
			'key_offset':               j.Value(u64(0))
			'value':                    j.Value('record index')
			'record_stride':            j.Value(pmp_soc_device_bytes)
			'initial_value':            j.Value((-1))
			'allocated_entries':        j.Value(u64(257))
			'lookup_entries':           j.Value(u64(256))
			'selector_field':           j.Value(u64(3))
			'die_stride_object_offset': j.Value(u64(469048))
			'table_object_offset':      j.Value(u64(469064))
		})
		'virtual_state_map':     j.Value(map[string]j.Value{
			'source':              j.Value('nonzero soc-device word at +0x2c')
			'key':                 j.Value('soc-device id')
			'value':               j.Value('dense PTD entry index')
			'initial_value':       j.Value((-1))
			'allocated_entries':   j.Value(u64(257))
			'table_object_offset': j.Value(u64(470092))
		})
		'ptd_transport':         j.Value(ptd_transport)
		'transport':             j.Value('PTD dashboard request/ack bitsets')
	}).as_map()
}

module t6050power

import appleadt as a
import g17decode as g
import traceanalysis as j

pub fn recover_pmgr_interrupt_config_evidence(reader EvidenceReader, functions map[string]Function) !map[string]j.Value {
	constructor_code_body := function(functions, pmgr_constructor)!
	constructor_code := constructor_code_body.code
	if !a.has_ordered_words(constructor_code, [
		u32(0x9140fc08), // add x8, x0, #0x3f, lsl #12
		u32(0x9104c116), // add x22, x8, #0x130 -- PMP ready slot
		u32(0x52801fe8), // mov w8, #0xff -- absent
		u32(0x390002c8), // strb w8, [x22]
	]) {
		return error('ApplePMGR no longer defaults its PMP ready slot to absent')
	}
	init_code_body := function(functions, pmgr_init_driver)!
	init_address := init_code_body.address
	init_code := init_code_body.code
	property_name := reader.read_cstring(Function{init_address, init_code}, 1640, 1644)!
	if property_name != pmgr_interrupt_config_property {
		return error('PMGR interrupt property changed: ' + j.quoted(property_name))
	}
	ready_name := reader.read_cstring(Function{init_address, init_code}, 1832, 1836)!
	if ready_name != pmp_ready_interrupt_name {
		return error('PMP readiness interrupt name changed: ' + j.quoted(ready_name))
	}
	if !a.has_ordered_words(init_code, [
		u32(0x529999a8), // mov w8, #0xcccd
		u32(0x72b99988), // movk w8, #0xcccc, lsl #16
		u32(0x9ba87c08), // umull x8, w0, w8
		u32(0xd364fd08), // lsr x8, x8, #36 -- property length / 20
		u32(0xb9019348), // str w8, [x26, #0x190] -- interrupts per die
		u32(0x7104fc1f), // cmp w0, #0x13f -- property length bound
		u32(0x39400d49), // ldrb w9, [x10, #3] -- interrupt kind
		u32(0xf100413f), // cmp x9, #0x10 -- at most 16 kinds
		u32(0x3940014a), // ldrb w10, [x10] -- per-die slot
		u32(0x8b151129), // add x9, x9, x21, lsl #4 -- 16 kinds per die
		u32(0x1b152908), // madd w8, w8, w21, w10 -- absolute interrupt index
		u32(0x39000168), // strb w8, [x11]
		u32(0x91001260), // add x0, x19, #4 -- record name
		u32(0x39400268), // ldrb w8, [x19] -- matched per-die slot
		u32(0x39068348), // strb w8, [x26, #0x1a0] -- PMP ready slot
		u32(0x910052f7), // add x23, x23, #0x14 -- 20-byte record stride
	]) {
		return error('PMGR interrupt-config decode changed')
	}
	return j.Value(map[string]j.Value{
		'property':                         j.Value(property_name)
		'record_bytes':                     j.Value(pmgr_interrupt_config_bytes)
		'slot_field':                       j.Value(u64(0))
		'kind_field':                       j.Value(u64(3))
		'kind_limit':                       j.Value(u64(16))
		'name_offset':                      j.Value(pmgr_interrupt_config_name_offset)
		'name_bytes':                       j.Value((pmgr_interrupt_config_bytes - pmgr_interrupt_config_name_offset))
		'maximum_property_bytes':           j.Value(u64(319))
		'interrupts_per_die':               j.Value('property length / 20')
		'interrupts_per_die_object_offset': j.Value(u64(258336))
		'index_table_object_offset':        j.Value(u64(258304))
		'index_table_die_stride':           j.Value(u64(16))
		'index_table_value':                j.Value('interrupts-per-die * die + record slot')
		'ready_interrupt_name':             j.Value(ready_name)
		'ready_slot_object_offset':         j.Value(u64(258352))
		'ready_slot_value':                 j.Value("the matched record's slot byte")
		'ready_slot_default':               j.Value(u64(255))
		'scope':                            j.Value('the runtime property is the boot DeviceTree pmgr property merged with its selected variant overlay, so the per-die count must be read at run time rather than assumed')
	}).as_map()
}

pub fn recover_rtbuddy_patchbay_contract_evidence(reader EvidenceReader, functions map[string]Function, symbols map[string]j.Value) !map[string]j.Value {
	required := [rtbuddy_firmware_copy_id_block, rtbuddy_firmware_find_patchbay,
		rtbuddy_firmware_copy32_from_iop, rtbuddy_firmware_segment_for_iop,
		rtbuddy_segment_is_writable, rtbuddy_patchbay_init_with_data, rtbuddy_patchbay_find]
	missing := required.filter(it !in symbols)
	if missing.len != 0 {
		return error('RTBuddy is missing patchbay symbols: ' + j.string_value(j.Value(missing.map(j.Value(it)))))
	}
	id_code_body := function(functions, rtbuddy_firmware_copy_id_block)!
	id_address := id_code_body.address
	id_code := id_code_body.code
	if !branch_target_exists(Function{id_address, id_code}, symbol(symbols, rtbuddy_firmware_copy32_from_iop)!)! || !a.has_ordered_words(id_code, [
		u32(0x528eaeb8), // mov w24, #0x7575
		u32(0x72ac8d38), // movk w24, #0x6469, lsl #16 -- "uuid"
		u32(0x52800802), // mov w2, #0x40 -- identity block size
		u32(0x121f7908), // and w8, w8, #0xfffffffe
		u32(0x7100111f), // cmp w8, #4 -- version 4 or 5
		u32(0x910012d6), // add x22, x22, #4
		u32(0xf10082df), // cmp x22, #0x20 -- eight candidate offsets
	]) {
		return error('RTKit identity-block search changed')
	}
	candidate_address := g.read_adrp_add_address(id_address, id_code, 68, 72)!
	candidates := reader.read_table(candidate_address, int(rtk_id_block_candidates))!.clone()
	if unique_words(candidates).len != rtk_id_block_candidates || candidates != sorted_words(candidates) {
		return error('RTKit identity-block candidates changed: ' + j.string_value(j.Value(candidates.map(j.Value(it)))))
	}
	find_code_body := function(functions, rtbuddy_firmware_find_patchbay)!
	find_address := find_code_body.address
	find_code := find_code_body.code
	find_targets := branch_targets(Function{find_address, find_code})!
	for name in [rtbuddy_firmware_copy_id_block, rtbuddy_firmware_segment_for_iop,
		rtbuddy_segment_is_writable] {
		if !targets_have(find_targets, symbol(symbols, name)!)! {
			return error('RTBuddy patchbay lookup no longer calls ' + name)
		}
	}
	if !a.has_ordered_words(find_code, [
		u32(0x7100151f), // cmp w8, #5
		u32(0x7100111f), // cmp w8, #4
		u32(0x91008309), // add x9, x24, #0x20 -- v4 offset
		u32(0x91009308), // add x8, x24, #0x24 -- v4 size
		u32(0x9100b308), // add x8, x24, #0x2c -- v5 size
		u32(0x9100a309), // add x9, x24, #0x28 -- v5 offset
		u32(0x12000528), // and w8, w9, #3 -- alignment pad
		u32(0x927ef529), // and x9, x9, #0xfffffffffffffffc
		u32(0x11000d29), // add w9, w9, #3
		u32(0x121e7529), // and w9, w9, #0xfffffffc -- padded size
	]) {
		return error('RTBuddy patchbay lookup changed')
	}
	init_code_body := function(functions, rtbuddy_patchbay_init_with_data)!
	init_code := init_code_body.code
	if !a.has_ordered_words(init_code, [
		u32(0xf9000a96), // str x22, [x20, #0x10] -- retained data
		u32(0xb9001a95), // str w21, [x20, #0x18] -- first record offset
		u32(0x39007693), // strb w19, [x20, #0x1d] -- writable
		u32(0x3900729f), // strb wzr, [x20, #0x1c] -- clean
	]) {
		return error('RTBuddyPatchBay construction changed')
	}
	walk_code_body := function(functions, rtbuddy_patchbay_find)!
	walk_code := walk_code_body.code
	if !a.has_ordered_words(walk_code, [
		u32(0xb9401813), // ldr w19, [x0, #0x18] -- cursor starts at the pad
		u32(0xf9400800), // ldr x0, [x0, #0x10] -- backing data
		u32(0xd2803411), // mov x17, #0x1a0 -- OSData::getBytesNoCopy(offset, len)
		u32(0x52800102), // mov w2, #8 -- one record header
		u32(0xb94002c8), // ldr w8, [x22] -- tag
		u32(0x6b15011f), // cmp w8, w21 -- requested tag
		u32(0xb94006c8), // ldr w8, [x22, #4] -- value length
		u32(0xb080268), // add w8, w19, w8
		u32(0x11002113), // add w19, w8, #8 -- next record
	]) {
		return error('RTBuddyPatchBay record walk changed')
	}
	return j.Value(map[string]j.Value{
		'identity_block': j.Value(map[string]j.Value{
			'magic':                 j.Value(rtk_id_block_magic)
			'magic_bytes':           j.Value('uuid')
			'size':                  j.Value(rtk_id_block_bytes)
			'version_offset':        j.Value(u64(4))
			'accepted_versions':     j.Value([j.Value(u64(4)), j.Value(u64(5))])
			'version_test':          j.Value('version & ~1 == 4')
			'candidate_iop_offsets': j.Value(candidates.map(j.Value(it)))
			'base':                  j.Value("the coredump map's IOP virtual base, or zero when absent")
			'patchbay_fields':       j.Value(map[string]j.Value{
				'4': j.Value(map[string]j.Value{
					'offset': j.Value(u64(32))
					'size':   j.Value(u64(36))
				})
				'5': j.Value(map[string]j.Value{
					'offset': j.Value(u64(40))
					'size':   j.Value(u64(44))
				})
			})
		})
		'region':         j.Value(map[string]j.Value{
			'iop_virtual':         j.Value("identity base + the block's patchbay offset")
			'alignment':           j.Value(u64(4))
			'align_pad':           j.Value('the low two bits of the unaligned address')
			'padded_size':         j.Value('(pad + size + 3) & ~3')
			'writable':            j.Value('the containing segment is writable, or no segment claims the address at all')
			'first_record_offset': j.Value('the alignment pad')
		})
		'record':         j.Value(map[string]j.Value{
			'header_bytes':   j.Value(patchbay_header_bytes)
			'tag_offset':     j.Value(u64(0))
			'length_offset':  j.Value(u64(4))
			'value_offset':   j.Value(patchbay_header_bytes)
			'stride':         j.Value('8 + length, with no inter-record padding')
			'tag_byte_order': j.Value("the driver's u32 constant spells the tag most-significant byte first, so the bytes stored in the image are reversed")
		})
	}).as_map()
}

pub fn recover_rtbuddy_firmware_source_contract_evidence(reader EvidenceReader, functions map[string]Function, symbols map[string]j.Value, preload_vtable_target j.Value) !map[string]j.Value {
	required := [rtbuddy_init_config_edt, rtbuddy_attempt_firmware_load,
		rtbuddy_handle_preload_firmware, rtbuddy_handle_service_firmware,
		rtbuddy_service_matching_role, rtbuddy_firmware_preloaded, rtbuddy_firmware_init_segment_map,
		rtbuddy_firmware_iboot_loaded, rtbuddy_firmware_fixup]
	missing := required.filter(it !in symbols)
	if missing.len != 0 {
		return error('RTBuddy is missing firmware-source symbols: ' + j.string_value(j.Value(missing.map(j.Value(it)))))
	}
	edt_code_body := function(functions, rtbuddy_init_config_edt)!
	edt_address := edt_code_body.address
	edt_code := edt_code_body.code
	mut properties := []string{}
	for proof in [PropertyProof{1276, rtbuddy_preloaded_property},
		PropertyProof{1356, rtbuddy_running_property},
		PropertyProof{1424, rtbuddy_no_firmware_service_property}] {
		offset := proof.offset
		expected := proof.expected
		actual := reader.read_cstring(Function{edt_address, edt_code}, offset, (offset + 4))!
		if actual != expected {
			return error('RTBuddy EDT property at ' + '0x${offset:x}' + ' changed: ' + j.quoted(actual))
		}
		properties << actual
	}
	if !a.has_ordered_words(edt_code, [
		u32(0xf100001f), // cmp x0, #0 -- pre-loaded present?
		u32(0x1a9f07e8), // cset w8, ne
		u32(0x3908c2a8), // strb w8, [x21, #0x230]
		u32(0xf100001f), // cmp x0, #0 -- running present?
		u32(0x1a9f07e8), // cset w8, ne
		u32(0x3908c6a8), // strb w8, [x21, #0x231]
		u32(0x52800020), // mov w0, #1
		u32(0x3908caa0), // strb w0, [x21, #0x232] -- running or no-firmware-service
	]) {
		return error('RTBuddy EDT firmware-source flags changed')
	}
	attempt_code_body := function(functions, rtbuddy_attempt_firmware_load)!
	attempt_address := attempt_code_body.address
	attempt_code := attempt_code_body.code
	attempt_targets := branch_targets(Function{attempt_address, attempt_code})!
	for name in [rtbuddy_handle_service_firmware, rtbuddy_service_matching_role] {
		if !targets_have(attempt_targets, symbol(symbols, name)!)! {
			return error('RTBuddy firmware-load selection no longer calls ' + name)
		}
	}
	if targets_have(attempt_targets, symbol(symbols, rtbuddy_handle_preload_firmware)!)! {
		return error('RTBuddy preload path is no longer a virtual dispatch')
	}
	if !integer_equal(preload_vtable_target, symbol(symbols, rtbuddy_handle_preload_firmware)!) {
		return error('RTBuddy vtable slot ' + '0x${2520:x}' + ' is no longer the preload handler')
	}
	if !a.has_ordered_words(attempt_code, [
		u32(0x39434008), // ldrb w8, [x0, #0xd0] -- already attempted
		u32(0x91400808), // add x8, x0, #0x2, lsl #12
		u32(0x3948c909), // ldrb w9, [x8, #0x232] -- running or opted out
		u32(0x3948c108), // ldrb w8, [x8, #0x230] -- pre-loaded
		u32(0xd2813b11), // mov x17, #0x9d8 -- preload handler
		u32(0x39066109), // strb w9, [x8, #0x198] -- awaiting a firmware service
	]) {
		return error('RTBuddy firmware-load selection changed')
	}
	preload_code_body := function(functions, rtbuddy_handle_preload_firmware)!
	preload_address := preload_code_body.address
	preload_code := preload_code_body.code
	if !branch_target_exists(Function{preload_address, preload_code}, symbol(symbols, rtbuddy_firmware_preloaded)!)! || !a.has_ordered_words(preload_code, [
		u32(0xf950c000), // ldr x0, [x0, #0x2180] -- segment map
		u32(0xf9405e61), // ldr x1, [x19, #0xb8] -- role name
		u32(0xd2812511), // mov x17, #0x928 -- loadFirmware
	]) {
		return error('RTBuddy preload handler changed')
	}
	preloaded_code_body := function(functions, rtbuddy_firmware_preloaded)!
	preloaded_address := preloaded_code_body.address
	preloaded_code := preloaded_code_body.code
	if !branch_target_exists(Function{preloaded_address, preloaded_code}, symbol(symbols, rtbuddy_firmware_init_segment_map)!)! || !a.has_ordered_words(preloaded_code, [
		u32(0x52800028), // mov w8, #1
		u32(0x39030268), // strb w8, [x19, #0xc0] -- iBoot-loaded
	]) {
		return error('RTBuddy preloaded-firmware constructor changed')
	}
	iboot_code_body := function(functions, rtbuddy_firmware_iboot_loaded)!
	iboot_code := iboot_code_body.code
	if iboot_code != encoded_words([u32(3573752927), u32(960692232), u32(301990144), u32(3596551104)]) {
		return error('RTBuddyFirmware iBoot-loaded predicate changed')
	}
	fixup_code_body := function(functions, rtbuddy_firmware_fixup)!
	fixup_code := fixup_code_body.code
	if !a.has_ordered_words(fixup_code, [
		u32(0x39430268), // ldrb w8, [x19, #0xc0] -- iBoot-loaded
		u32(0x37000068), // tbnz w8, #0 -- an iBoot image is never recopied
		u32(0xf9404e68), // ldr x8, [x19, #0x98] -- existing target map
		u32(0xb40000e8), // cbz x8 -- otherwise copy the image to the target
		u32(0x52844628), // mov w8, #0x2231 -- RTBuddy running flag
		u32(0x39400108), // ldrb w8, [x8]
	]) {
		return error('RTBuddy firmware copy-to-target guard changed')
	}
	return j.Value(map[string]j.Value{
		'device_tree_properties':     j.Value(properties.map(j.Value(it)))
		'flag_object_offsets':        j.Value(map[string]j.Value{
			rtbuddy_preloaded_property: j.Value(u64(8752))
			rtbuddy_running_property:   j.Value(u64(8753))
			'skip_firmware_service':    j.Value(u64(8754))
		})
		'skip_firmware_service_rule': j.Value('set when the nub publishes `running` or `no-firmware-service`; `pre-loaded` alone never sets it')
		'selection':                  j.Value([j.Value(map[string]j.Value{
			'when':                        j.Value('skip-firmware-service clear')
			'path':                        j.Value('wait for an RTBuddyFirmwareService matching the role')
			'awaiting_flag_object_offset': j.Value(u64(8600))
		}), j.Value(map[string]j.Value{
			'when': j.Value('skip-firmware-service set and pre-loaded clear')
			'path': j.Value(rtbuddy_handle_service_firmware)
		}), j.Value(map[string]j.Value{
			'when':                       j.Value('skip-firmware-service set and pre-loaded set')
			'path':                       j.Value(rtbuddy_handle_preload_firmware)
			'vtable_slot':                j.Value(u64(2520))
			'segment_map_object_offset':  j.Value(u64(8576))
			'missing_segment_map_result': j.Value(u64(3758097136))
		})])
		'iboot_loaded':               j.Value(map[string]j.Value{
			'predicate':          j.Value(rtbuddy_firmware_iboot_loaded)
			'object_byte_offset': j.Value(u64(192))
			'only_producer':      j.Value(rtbuddy_firmware_preloaded)
			'requires':           j.Value(rtbuddy_firmware_init_segment_map)
			'suppresses':         j.Value(rtbuddy_firmware_copy_to_target)
			'scope':              j.Value('an image adopted from the DeviceTree segment map; a firmware service always produces a non-iBoot image that is copied to the target unless one is already mapped')
		})
		'scope':                      j.Value("this is the image-provenance decision only; it is independent of whether AppleA7IOP treats the nub's DART records as iBoot-owned")
	}).as_map()
}

pub fn recover_apple_a7iop_code_contract_evidence(reader EvidenceReader, functions map[string]Function, vtable_targets map[string]j.Value) !map[string]j.Value {
	required := [apple_wrapper_mailbox_start, apple_wrapper_mailbox_reg,
		apple_wrapper_mailbox_physical, apple_a7iop_start, apple_a7iop_start_cpu_options,
		apple_a7iop_reg, apple_a7iop_physical, apple_a7iop_enable_sram, apple_a7iop_enable_power,
		apple_a7iop_dart_map_iboot_firmware, apple_a7iop_has_iboot_firmware]
	missing := required.filter(it !in functions)
	if missing.len != 0 {
		return error('AppleA7IOP has no code body for ' + j.string_value(j.Value(missing.map(j.Value(it)))))
	}
	start_code_body := function(functions, apple_wrapper_mailbox_start)!
	start_code := start_code_body.code
	if !a.has_ordered_words(start_code, [
		u32(0xf9407e80), // ldr x0, [x20, #0xf8] -- wrapper provider
		u32(0x911c4208), // add x8, x16, #0x710 -- mapDeviceMemoryWithIndex slot
		u32(0xf9438a09), // ldr x9, [x16, #0x710]
		u32(0x52800001), // mov w1, #0 -- device-memory index
		u32(0x52800002), // mov w2, #0 -- map options
		u32(0xd73f0931), // blraa x9, x17
		u32(0xf900a280), // str x0, [x20, #0x140] -- retained memory map
		u32(0xd2802711), // mov x17, #0x138 -- getVirtualAddress slot
		u32(0x8b110210), // add x16, x16, x17
		u32(0xf9400208), // ldr x8, [x16]
		u32(0xd73f0910), // blraa x8, x16
		u32(0xf9008280), // str x0, [x20, #0x100] -- mapped register VA
	]) {
		return error('AppleWrapperMailbox device-memory mapping changed')
	}
	reg_code_body := function(functions, apple_wrapper_mailbox_reg)!
	reg_code := reg_code_body.code
	expected_reg := encoded_words([u32(3573752927), u32(4181753864), u32(3093383424), u32(3596551104)])
	if reg_code != expected_reg {
		return error('AppleWrapperMailbox register accessor changed')
	}
	physical_code_body := function(functions, apple_wrapper_mailbox_physical)!
	physical_address := physical_code_body.address
	physical_code := physical_code_body.code
	if physical_code.len < 32 || python_word_at(physical_code, 12) != 4181762048 || python_word_at(physical_code, 16) != 3019899040 || (python_word_at(physical_code, 20) & 4227858432) != 2483027968 || !branch_at_present(Function{physical_address, physical_code}, 20)! {
		return error('AppleWrapperMailbox physical-address accessor changed')
	}
	a7_start_code_body := function(functions, apple_a7iop_start)!
	a7_start_address := a7_start_code_body.address
	a7_start_code := a7_start_code_body.code
	if !a.has_ordered_words(a7_start_code, [
		u32(0xf9407e80), // ldr x0, [x20, #0xf8] -- wrapper provider
		u32(0x911c4208), // add x8, x16, #0x710 -- mapDeviceMemoryWithIndex slot
		u32(0xf9438a09), // ldr x9, [x16, #0x710]
		u32(0x52800001), // mov w1, #0 -- device-memory index
		u32(0x52800002), // mov w2, #0 -- map options
		u32(0xd73f0931), // blraa x9, x17
		u32(0xf900b680), // str x0, [x20, #0x168] -- retained memory map
		u32(0xd2802711), // mov x17, #0x138 -- getVirtualAddress slot
		u32(0x8b110210), // add x16, x16, x17
		u32(0xf9400208), // ldr x8, [x16]
		u32(0xd73f0910), // blraa x8, x16
		u32(0xf9008280), // str x0, [x20, #0x100] -- mapped register VA
		u32(0xb9400008), // ldr w8, [x0] -- sram-index OSData payload
		u32(0xb9015e88), // str w8, [x20, #0x15c] -- SRAM power selector
		u32(0x7100011f), // cmp w8, #0
		u32(0x1a9f07e2), // cset w2, ne -- should-control-sram value
	]) {
		return error('AppleA7IOP device-memory or SRAM-property mapping changed')
	}
	if !a.has_ordered_words(a7_start_code, [
		u32(0x52800028), // CPU-control writes are enabled by default
		u32(0x3904ca88), // strb w8, [x20, #0x132]
		u32(0xd2805b11), // provider property lookup slot 0x2d8
		u32(0xb4000040), // no cpu-ctrl-filtered property: retain default
		u32(0x3904ca9f), // property present: suppress CPU-control writes
	]) {
		return error('AppleA7IOP CPU-control filter handling changed')
	}
	start_cpu_code_body := function(functions, apple_a7iop_start_cpu_options)!
	start_cpu_code := start_cpu_code_body.code
	if !a.has_ordered_words(start_cpu_code, [
		u32(0xd2814511), // _runCPU vtable slot 0xa28
		u32(0x8b110210),
		u32(0xf9400208),
		u32(0xaa1303e0),
		u32(0x52800021), // requested run state = true
		u32(0xd73f0910),
	]) {
		return error('AppleA7IOP startCPU run-control dispatch changed')
	}
	dart_map_code_body := function(functions, apple_a7iop_dart_map_iboot_firmware)!
	dart_map_code := dart_map_code_body.code
	if !a.has_ordered_words(dart_map_code, [
		u32(0x3944c008), // ldrb w8, [x0, #0x130] -- map-complete latch
		u32(0xf9409408), // ldr x8, [x0, #0x128] -- iBoot segment records
		u32(0xd2811111), // mov x17, #0x888 -- IOMapper::getPageSize
		u32(0xd2811211), // mov x17, #0x890 -- reserve/check mapper range
		u32(0xb9401d0a), // ldr w10, [x8, #0x1c] -- segment flags
		u32(0x370805ea), // tbnz w10, #1 -- skip non-mapped segment
		u32(0xf9400909), // ldr x9, [x8, #0x10] -- segment IOVA
		u32(0xb940190b), // ldr w11, [x8, #0x18] -- segment byte size
		u32(0x7200015f), // tst w10, #1 -- executable/read-only flag
		u32(0x5280006a), // mov w10, #3 -- read/write direction
		u32(0x1a9f0541), // csinc w1, w10, wzr, eq -- 1 or 3
		u32(0xf9400104), // ldr x4, [x8] -- physical base
		u32(0xd2811411), // mov x17, #0x8a0 -- IOMapper::iovmInsert
		u32(0x8a160145), // and x5, x10, x22 -- page-aligned byte size
		u32(0xd2800003), // mov x3, #0 -- no IOVA displacement
		u32(0xd73f0910), // blraa x8, x16
		u32(0x3904c268), // strb w8, [x19, #0x130] -- mapping complete
	]) {
		return error('AppleA7IOP iBoot firmware DART mapping changed')
	}
	a7_start_property := reader.read_cstring(Function{a7_start_address, a7_start_code}, 844, 848)!
	if a7_start_property != apple_a7iop_segment_ranges_property {
		return error('AppleA7IOP iBoot firmware property changed: ' + j.quoted(a7_start_property))
	}
	if !a.has_ordered_words(a7_start_code, [
		u32(0xf9009680), // str x0, [x20, #0x128] -- retained segment-ranges data
		u32(0x3904c29f), // strb wzr, [x20, #0x130]
		u32(0x3904869f), // strb wzr, [x20, #0x121]
	]) {
		return error('AppleA7IOP iBoot firmware retention changed')
	}
	has_iboot_code_body := function(functions, apple_a7iop_has_iboot_firmware)!
	has_iboot_code := has_iboot_code_body.code
	if has_iboot_code != encoded_words([u32(3573752927), u32(4181758984), u32(4043309343),
		u32(446629856), u32(3596551104)]) {
		return error('AppleA7IOP iBoot firmware predicate changed')
	}
	a7_reg_code_body := function(functions, apple_a7iop_reg)!
	a7_reg_code := a7_reg_code_body.code
	if a7_reg_code != expected_reg {
		return error('AppleA7IOP register accessor changed')
	}
	a7_physical_code_body := function(functions, apple_a7iop_physical)!
	a7_physical_address := a7_physical_code_body.address
	a7_physical_code := a7_physical_code_body.code
	if a7_physical_code.len < 32 || python_word_at(a7_physical_code, 12) != 4181767168 || python_word_at(a7_physical_code, 16) != 3019899040 || (python_word_at(a7_physical_code, 20) & 4227858432) != 2483027968 || !branch_at_present(Function{a7_physical_address, a7_physical_code}, 20)! {
		return error('AppleA7IOP physical-address accessor changed')
	}
	enable_sram_code_body := function(functions, apple_a7iop_enable_sram)!
	enable_sram_code := enable_sram_code_body.code
	if !a.has_ordered_words(enable_sram_code, [
		u32(0xb9415c02), // ldr w2, [x0, #0x15c] -- sram-index value
		u32(0x34000222), // cbz w2 -- zero means unsupported
		u32(0xd2813911), // mov x17, #0x9c8 -- _enablePower slot
		u32(0x8b110210), // add x16, x16, x17
		u32(0xf9400208), // ldr x8, [x16]
		u32(0xd73f0910), // blraa x8, x16; x1 remains requested state
		u32(0x52805c40), // mov w0, #0x2e2 -- unsupported error low half
		u32(0x72bc0000), // movk w0, #0xe000, lsl #16
	]) {
		return error('AppleA7IOP SRAM-power dispatch changed')
	}
	if !integer_equal(j.value(vtable_targets, apple_a7iop_enable_power_vtable_slot.str()), function(functions, apple_a7iop_enable_power)!.address) {
		return error('AppleA7IOP SRAM-power vtable target changed')
	}
	enable_power_code_body := function(functions, apple_a7iop_enable_power)!
	enable_power_code := enable_power_code_body.code
	if !a.has_ordered_words(enable_power_code, [
		u32(0xaa0203f3), // mov x19, x2 -- power-domain selector
		u32(0xaa0103f4), // mov x20, x1 -- requested state
		u32(0xf9407c00), // ldr x0, [x0, #0xf8] -- wrapper provider
		u32(0xd2811511), // mov x17, #0x8a8 -- prepare power transition
		u32(0xd73f0910), // blraa x8, x16
		u32(0xf9407ea0), // ldr x0, [x21, #0xf8] -- wrapper provider again
		u32(0x9122c208), // add x8, x16, #0x8b0 -- set power state
		u32(0xf9445a09), // ldr x9, [x16, #0x8b0]
		u32(0xaa1403e1), // mov x1, x20 -- requested state
		u32(0xd2800002), // mov x2, #0
		u32(0xaa1303e3), // mov x3, x19 -- sram-index power selector
		u32(0xd73f0931), // blraa x9, x17
	]) {
		return error('AppleA7IOP provider power transition changed')
	}
	return j.Value(map[string]j.Value{
		'apple_a7iop':     j.Value(map[string]j.Value{
			'device_memory_index':           j.Value(u64(0))
			'map_options':                   j.Value(u64(0))
			'provider_object_offset':        j.Value(u64(248))
			'memory_map_object_offset':      j.Value(u64(360))
			'mapped_virtual_address_offset': j.Value(u64(256))
			'register_access':               j.Value(map[string]j.Value{
				'width_bits':  j.Value(u64(32))
				'offset_unit': j.Value('bytes')
				'address':     j.Value('mapped virtual address + zero-extended offset')
			})
			'physical_address_source':       j.Value('retained device-memory map')
			'sram_power':                    j.Value(map[string]j.Value{
				'selector_property':                  j.Value('sram-index')
				'selector_object_offset':             j.Value(u64(348))
				'zero_means_unsupported':             j.Value(true)
				'published_capability_property':      j.Value('should-control-sram')
				'enable_power_vtable_slot':           j.Value(apple_a7iop_enable_power_vtable_slot)
				'provider_prepare_power_vtable_slot': j.Value(u64(2216))
				'provider_set_power_vtable_slot':     j.Value(u64(2224))
				'provider_selector_argument':         j.Value('x3')
				'meaning':                            j.Value('provider power-domain selector; not a reg[] index')
			})
			'cpu_control':                   j.Value(map[string]j.Value{
				'filter_property':           j.Value('cpu-ctrl-filtered')
				'filter_absent_behavior':    j.Value('permit concrete wrapper CPU-control writes')
				'start_cpu_run_vtable_slot': j.Value(u64(2600))
				'start_cpu_run_argument':    j.Value(true)
			})
			'iboot_firmware_probe':          j.Value(map[string]j.Value{
				'predicate':     j.Value(apple_a7iop_has_iboot_firmware)
				'property':      j.Value(apple_a7iop_segment_ranges_property)
				'object_offset': j.Value(u64(296))
				'rule':          j.Value('true exactly when the nub publishes segment-ranges')
				'scope':         j.Value('this decides DART record ownership only; RTBuddy chooses its firmware image from separate nub properties')
			})
			'iboot_firmware_mapping':        j.Value(map[string]j.Value{
				'mapper_get_page_size_vtable_slot': j.Value(u64(2184))
				'mapper_reserve_vtable_slot':       j.Value(u64(2192))
				'mapper_insert_vtable_slot':        j.Value(u64(2208))
				'segment_record_size':              j.Value(u64(32))
				'physical_offset':                  j.Value(u64(0))
				'iova_offset':                      j.Value(u64(16))
				'size_offset':                      j.Value(u64(24))
				'flags_offset':                     j.Value(u64(28))
				'skip_flag_bit':                    j.Value(u64(1))
				'text_direction':                   j.Value(u64(1))
				'data_direction':                   j.Value(u64(3))
				'meaning':                          j.Value('records with flag bit 1 clear are page-aligned and inserted into the supplied IOMapper before wrapper CPU release; bit 1 marks an iBoot-installed mapping that this path preserves')
			})
			'scope':                         j.Value('resource and power-domain ownership only; does not start or prove the IOP ready')
		})
		'wrapper_mailbox': j.Value(map[string]j.Value{
			'device_memory_index':             j.Value(u64(0))
			'map_options':                     j.Value(u64(0))
			'provider_object_offset':          j.Value(u64(248))
			'map_device_memory_vtable_slot':   j.Value(u64(1808))
			'memory_map_object_offset':        j.Value(u64(320))
			'get_virtual_address_vtable_slot': j.Value(u64(312))
			'mapped_virtual_address_offset':   j.Value(u64(256))
			'register_access':                 j.Value(map[string]j.Value{
				'width_bits':  j.Value(u64(32))
				'offset_unit': j.Value('bytes')
				'address':     j.Value('mapped virtual address + zero-extended offset')
			})
			'physical_address_source':         j.Value('retained device-memory map')
			'scope':                           j.Value('wrapper mailbox/control resource ownership only; does not start or prove the IOP ready')
		})
	}).as_map()
}

module t6050power

import appleadt as a
import traceanalysis as j
import strconv

pub fn recover_apple_ptd_code_contract(functions map[string]Function, symbols map[string]j.Value) !map[string]j.Value {
	required := [apple_ptd_read, apple_ptd_write, pmgr_get_reg_map, pmgr_write_reg64]
	missing := required.filter(it !in symbols)
	if missing.len != 0 {
		return error('ApplePMGR is missing ApplePTD symbols: ' + j.string_value(j.Value(missing.map(j.Value(it)))))
	}
	for name in [apple_ptd_read, apple_ptd_write, pmgr_write_reg64] {
		if name !in functions {
			return error('ApplePMGR has no code body for ' + name)
		}
	}
	read_code_body := function(functions, apple_ptd_read)!
	read_address := read_code_body.address
	read_code := read_code_body.code
	if branch_count(Function{read_address, read_code}, j.value(symbols, pmgr_get_reg_map))! != 1 || !a.has_ordered_words(read_code, [
		u32(0xb9400828), // ldr w8, [x1, #8] -- range entry count
		u32(0xf9400000), // ldr x0, [x0] -- owning ApplePMGR
		u32(0x52800101), // mov w1, #8 -- PTD RegMap
		u32(0xaa0403e2), // mov x2, x4 -- die
		u32(0xf9400c08), // ldr x8, [x0, #0x18] -- mapped base
		u32(0x531c6e89), // lsl w9, w20, #4 -- entry * 16
		u32(0x8b090108), // add x8, x8, x9
		u32(0xa9402508), // ldp x8, x9, [x8] -- data and raw metadata
		u32(0xd341fd2a), // lsr x10, x9, #1
		u32(0x39403e6b), // ldrb w11, [x19, #0xf] -- retained tag
		u32(0xd34afd2c), // lsr x12, x9, #10
		u32(0xb349012c), // bfi x12, x9, #55, #1 -- raw bit 0
		u32(0xaa0be189), // orr x9, x12, x11, lsl #56
		u32(0xb34a0149), // bfi x9, x10, #54, #1 -- raw bit 1
		u32(0xa9002668), // stp x8, x9, [x19] -- decoded Entry
	]) {
		return error('ApplePTD read window or metadata decoding changed')
	}
	write_code_body := function(functions, apple_ptd_write)!
	write_address := write_code_body.address
	write_code := write_code_body.code
	if branch_count(Function{write_address, write_code}, j.value(symbols, pmgr_write_reg64))! != 1 || !a.has_ordered_words(write_code, [
		u32(0xb9400828), // ldr w8, [x1, #8] -- range entry count
		u32(0xf9400000), // ldr x0, [x0] -- owning ApplePMGR
		u32(0x531d7048), // lsl w8, w2, #3 -- entry * 8
		u32(0x11404102), // add w2, w8, #0x10, lsl #12 -- +0x10000
		u32(0x52800101), // mov w1, #8 -- PTD RegMap
	]) {
		return error('ApplePTD write portal changed')
	}
	write_reg_code_body := function(functions, pmgr_write_reg64)!
	write_reg_address := write_reg_code_body.address
	write_reg_code := write_reg_code_body.code
	if branch_count(Function{write_reg_address, write_reg_code}, j.value(symbols, pmgr_get_reg_map))! != 1 || !a.has_ordered_words(write_reg_code, [
		u32(0xaa0303f5), // mov x21, x3 -- value
		u32(0xaa0203f3), // mov x19, x2 -- byte offset
		u32(0xaa0103f6), // mov x22, x1 -- RegMap
		u32(0xaa1403e2), // mov x2, x20 -- die
		u32(0xf9400c08), // ldr x8, [x0, #0x18] -- mapped base
		u32(0xf8334915), // str x21, [x8, w19, uxtw]
	]) {
		return error('ApplePMGR 64-bit register write changed')
	}
	return j.Value(map[string]j.Value{
		'reg_map':       j.Value(u64(8))
		'read':          j.Value(map[string]j.Value{
			'base_offset':  j.Value(u64(0))
			'entry_stride': j.Value(u64(16))
			'width_bytes':  j.Value(u64(16))
			'operation':    j.Value('one 16-byte load of data and raw metadata')
		})
		'write':         j.Value(map[string]j.Value{
			'base_offset':  j.Value(u64(65536))
			'entry_stride': j.Value(u64(8))
			'width_bytes':  j.Value(u64(8))
			'operation':    j.Value('one 64-bit store through ApplePMGR::writeReg64')
		})
		'decoded_entry': j.Value(map[string]j.Value{
			'data_word':      j.Value(u64(0))
			'metadata_word':  j.Value(u64(1))
			'raw_bits_10_63': j.Value('decoded metadata bits 0..53')
			'raw_bit_1':      j.Value('decoded metadata bit 54 (newData)')
			'raw_bit_0':      j.Value('decoded metadata bit 55')
			'caller_tag':     j.Value('decoded metadata bits 56..63, retained from output +0xf')
		})
		'range_check':   j.Value('entry_count must be nonzero; callers supply the entry index')
		'ordering':      j.Value('no explicit lock or DMB/DSB appears in the UUID-pinned read, write, or final register-store sequence; ordering depends on the Device MMIO mapping')
	}).as_map()
}

pub fn recover_rtbuddy_segment_flag_contract(functions map[string]Function, symbols map[string]j.Value) !map[string]j.Value {
	required := [rtbuddy_get_segment_map, rtbuddy_segment_with_physical_range,
		rtbuddy_segment_is_writable]
	missing := required.filter(it !in symbols)
	if missing.len != 0 {
		return error('RTBuddy is missing segment-flag symbols: ' + j.string_value(j.Value(missing.map(j.Value(it)))))
	}
	map_code_body := function(functions, rtbuddy_get_segment_map)!
	map_address := map_code_body.address
	map_code := map_code_body.code
	if !branch_target_exists(Function{map_address, map_code}, j.value(symbols, rtbuddy_segment_with_physical_range))! {
		return error('RTBuddy segment map no longer builds physical ranges')
	}
	if !a.has_ordered_words(map_code, [
		u32(0x29412356), // ldp w22, w8, [x26, #8] -- size and DeviceTree flags
		u32(0x53020909), // ubfx w9, w8, #2, #1 -- flag bit 2 becomes bit 0
		u32(0x331f0109), // bfi w9, w8, #1, #1 -- flag bit 0 becomes bit 1
		u32(0x53017d08), // lsr w8, w8, #1
		u32(0x121e0508), // and w8, w8, #0xc -- flag bits 3 and 4 become 2 and 3
		u32(0x2a08013b), // orr w27, w9, w8
		u32(0x521f0365), // eor w5, w27, #2 -- bit 1 is inverted
	]) {
		return error('RTBuddy segment flag translation changed')
	}
	writable_code_body := function(functions, rtbuddy_segment_is_writable)!
	writable_code := writable_code_body.code
	if writable_code != encoded_words([
		u32(0xd503245f),
		u32(0x39410008),
		u32(0x53010500),
		u32(0xd65f03c0),
	]) {
		return error('RTBuddySegment writability predicate changed')
	}
	return j.Value(map[string]j.Value{
		'device_tree_flags_offset': j.Value(u64(28))
		'translation':              j.Value(map[string]j.Value{
			'segment_bit_0': j.Value('DeviceTree bit 2')
			'segment_bit_1': j.Value('DeviceTree bit 0, inverted')
			'segment_bit_2': j.Value('DeviceTree bit 3')
			'segment_bit_3': j.Value('DeviceTree bit 4')
			'object_offset': j.Value(u64(64))
		})
		'writable':                 j.Value(map[string]j.Value{
			'predicate':        j.Value(rtbuddy_segment_is_writable)
			'segment_bit':      j.Value(u64(1))
			'device_tree_rule': j.Value('writable when DeviceTree flag bit 0 is clear')
		})
		'dart_skip':                j.Value(map[string]j.Value{
			'device_tree_bit': j.Value(u64(1))
			'meaning':         j.Value('iBoot already installed this mapping; do not insert it')
		})
		'scope':                    j.Value('bit 0 is read-only and bit 1 is iBoot-installed; they are distinct and a record commonly sets one without the other')
	}).as_map()
}

pub fn recover_iodart_family_code_contract(functions map[string]Function, vtable_targets map[string]j.Value, direction_lookup []j.Value) !map[string]j.Value {
	required := [iodart_mapper_get_page_size, iodart_mapper_iovm_insert, iodart_mapper_iovm_insert_one]
	missing := required.filter(it !in functions)
	if missing.len != 0 {
		return error('IODARTFamily has no code body for ' + j.string_value(j.Value(missing.map(j.Value(it)))))
	}
	expected_slots := map[string]j.Value{
		'2184': function(functions, iodart_mapper_get_page_size)!.address
		'2208': function(functions, iodart_mapper_iovm_insert)!.address
	}
	for slot_text, expected in expected_slots {
		slot := strconv.parse_uint(slot_text, 10, 64)!
		if !integer_equal(j.value(vtable_targets, slot.str()), expected) {
			return error('IODARTMapper vtable slot ' + '0x${slot:x}' + ' changed')
		}
	}
	if !tuple_equal(direction_lookup, [0, 2, 1, 3]) {
		return error('IODARTMapper direction lookup changed: ' + tuple_repr(direction_lookup))
	}
	page_code_body := function(functions, iodart_mapper_get_page_size)!
	page_code := page_code_body.code
	if page_code != encoded_words([
		u32(0xd503245f),
		u32(0xf9409008),
		u32(0xf9401900),
		u32(0xd65f03c0),
	]) {
		return error('IODARTMapper page-size accessor changed')
	}
	insert_code_body := function(functions, iodart_mapper_iovm_insert)!
	insert_code := insert_code_body.code
	if !a.has_ordered_words(insert_code, [
		u32(0x12000428), // and w8, w1, #3 -- IODirection index
		u32(0xb8685937), // ldr w23, [direction lookup, w8, uxtw #2]
		u32(0xf9408408), // ldr x8, [x0, #0x108] -- mapper DVA prefix
		u32(0xaa020108), // orr x8, x8, x2 -- requested DVA
		u32(0x8b030118), // add x24, x8, x3 -- DVA displacement
		u32(0xf9401908), // ldr x8, [x8, #0x30] -- page size
		u32(0xb9411668), // ldr w8, [x19, #0x114] -- page shift
		u32(0x9ac82716), // lsr x22, x24, x8 -- DVA page
		u32(0x9ac8269b), // lsr x27, x20, x8 -- physical page
		u32(0x97ffff63), // call the per-page insertion path
	]) {
		return error('IODARTMapper iovmInsert argument conversion changed')
	}
	one_code_body := function(functions, iodart_mapper_iovm_insert_one)!
	one_code := one_code_body.code
	if !a.has_ordered_words(one_code, [
		u32(0xaa1503e1), // mapper virtual page
		u32(0xaa1703e2), // physical page number
		u32(0x52800043), // page type 2
		u32(0xaa1603e4), // protection from direction lookup
		u32(0x94000c12), // IODARTVMSpace::setTranslation
		u32(0x52800022), // invalidate one page after insertion
	]) {
		return error('IODARTMapper per-page insertion changed')
	}
	return j.Value(map[string]j.Value{
		'mapper': j.Value(map[string]j.Value{
			'get_page_size_vtable_slot': j.Value(u64(2184))
			'iovm_insert_vtable_slot':   j.Value(u64(2208))
			'direction_lookup':          j.Value(direction_lookup.clone())
			'direction_1_protection':    direction_lookup[1]
			'direction_3_protection':    direction_lookup[3]
			'page_type':                 j.Value(u64(2))
			'invalidation':              j.Value('one DART page after each inserted page')
		})
	}).as_map()
}

pub fn recover_apple_t8110_dart_code_contract(functions map[string]Function, bypass_property_prefix j.Value, sid_property_format j.Value) !map[string]j.Value {
	required := [apple_t8110_dart_start, apple_t8110_dart_setup, apple_t8110_dart_get_sid_property,
		apple_t8110_dart_get_sid_count, apple_t8110_dart_is_bypassed_sid,
		apple_t8110_dart_enable_translation, apple_t8110_dart_set_translation,
		apple_t8110_dart_set_translation_range, apple_t8110_dart_invalidate_tlb]
	missing := required.filter(it !in functions)
	if missing.len != 0 {
		return error('AppleT8110DART has no code body for ' + j.string_value(j.Value(missing.map(j.Value(it)))))
	}
	start_code_body := function(functions, apple_t8110_dart_start)!
	start_code := start_code_body.code
	if !a.has_ordered_words(start_code, [
		u32(0x947625ec), // _t8110dart_get_desc()
		u32(0xf9461a61), // log context at object +0xc30
		u32(0x9100a3e2), // t8110dart_init_data on the stack
		u32(0x91314264), // output context at object +0xc50
		u32(0x52812d03), // init-data bytes = 0x968
		u32(0x94757ec7), // _pmap_iommu_init(...)
	]) {
		return error('AppleT8110DART protected-IOMMU initialization changed')
	}
	setup_code_body := function(functions, apple_t8110_dart_setup)!
	setup_code := setup_code_body.code
	if !a.has_ordered_words(setup_code, [
		u32(0x52800108), // eight-byte optional bypass-address result
		u32(0xf9004fe8),
		u32(0x910263e3),
		u32(0xaa1803e2), // current SID
		u32(0x94000fdf), // _getSidProperty("bypass", SID, &size)
		u32(0x3900a2e8), // mark the per-SID record bypassed
		u32(0xaa1a0108), // add the SID to the bypass bitset
	]) {
		return error('AppleT8110DART per-SID bypass setup changed')
	}
	if bypass_property_prefix != j.Value('bypass') {
		return error('AppleT8110DART bypass property prefix changed: ' + element_repr(bypass_property_prefix))
	}
	property_code_body := function(functions, apple_t8110_dart_get_sid_property)!
	property_code := property_code_body.code
	if !a.has_ordered_words(property_code, [
		u32(0xa9000be1), // property prefix and SID are snprintf arguments
		u32(0x910083e0), // 32-byte formatted-property buffer
		u32(0x52800401),
	]) {
		return error('AppleT8110DART SID-property formatter changed')
	}
	if sid_property_format != j.Value('%s-%d') {
		return error('AppleT8110DART SID-property format changed: ' + element_repr(sid_property_format))
	}
	count_code_body := function(functions, apple_t8110_dart_get_sid_count)!
	count_code := count_code_body.code
	if !a.has_ordered_words(count_code, [
		u32(0x91008108), // first hardware-instance record at owner +0x20
		u32(0x52800e09), // hardware-instance stride 0x70
		u32(0x9ba97c29), // mapper index selects that instance
		u32(0xb9400d08), // PARAMS4 at instance MMIO +0xc
		u32(0x12002100), // SID count is PARAMS4[8:0]
	]) {
		return error('AppleT8110DART mapper/SID-count selection changed')
	}
	bypassed_code_body := function(functions, apple_t8110_dart_is_bypassed_sid)!
	bypassed_code := bypassed_code_body.code
	if !a.has_ordered_words(bypassed_code, [
		u32(0x7100803f), // SID 32 boundary for extended-bypass support
		u32(0xf9448129), // per-SID bypass bitset at object +0x900
		u32(0x9ac82528),
		u32(0x12000100),
	]) {
		return error('AppleT8110DART bypass lookup changed')
	}
	enable_code_body := function(functions, apple_t8110_dart_enable_translation)!
	enable_code := enable_code_body.code
	if !a.has_ordered_words(enable_code, [
		u32(0x7100005f), // cmp w2, #0 -- requested translation state
		u32(0x52902288), // mov w8, #0x8114 -- disable selector
		u32(0x9a880501), // cinc x1, x8, ne -- enable selector 0x8115
		u32(0x52800083), // four-byte SID payload
	]) {
		return error('AppleT8110DART translation-control transport changed')
	}
	set_code_body := function(functions, apple_t8110_dart_set_translation)!
	set_code := set_code_body.code
	if !a.has_ordered_words(set_code, [
		u32(0xd3727d1a), // physical page number -> byte address, shift 14
		u32(0x52880002), // iovmalloc request bytes = one 0x4000 DART page
		u32(0xd3727f08), // DVA page number -> byte address, shift 14
		u32(0xa905a3fa), // one ppl_iommu_segm: physical then DVA
		u32(0xa906ffe8), // byte length then zeroed protection/reserved pair
		u32(0xf9003fff), // reserved word at segment +0x20
		u32(0x52800068), // protection value 3
		u32(0xb90073e8), // store protection at segment +0x18
		u32(0x52800022), // pmap_iommu_map segment count = 1
	]) {
		return error('AppleT8110DART 16 KiB translation path changed')
	}
	range_code_body := function(functions, apple_t8110_dart_set_translation_range)!
	range_code := range_code_body.code
	if !a.has_ordered_words(range_code, [
		u32(0xb94c8669), // byte-range alignment at object +0xc84
		u32(0x1ac90b48), // start offset / alignment
		u32(0x1b09e908), // require zero start remainder
		u32(0x1ac9090a), // inclusive end offset / alignment
		u32(0x1b09a14a),
		u32(0x51000529), // require end remainder == alignment - 1
		u32(0x6b1a011b), // byte length minus one = end - start
		u32(0xd3727ea8), // physical 16-KiB page number -> byte address
		u32(0x8b3a4108), // add byte-range start
		u32(0xd3727f29), // DVA 16-KiB page number -> byte address
		u32(0x8b3a4129), // add the same byte-range start
		u32(0x11000768), // segment byte length = end - start + 1
		u32(0x52800022), // pmap_iommu_map segment count = 1
	]) {
		return error('AppleT8110DART partial-range translation path changed')
	}
	invalidate_code_body := function(functions, apple_t8110_dart_invalidate_tlb)!
	invalidate_code := invalidate_code_body.code
	if invalidate_code != encoded_words([
		u32(0xd503245f),
		u32(0xd65f03c0),
	]) {
		return error('AppleT8110DART invalidate ownership changed')
	}
	return j.Value(map[string]j.Value{
		'translation': j.Value(map[string]j.Value{
			'page_shift':                  j.Value(u64(14))
			'page_size':                   j.Value(u64(16384))
			'disable_selector':            j.Value(u64(33044))
			'enable_selector':             j.Value(u64(33045))
			'sid_payload_bytes':           j.Value(u64(4))
			'driver_invalidate_method':    j.Value('no-op')
			'hardware_update_owner':       j.Value('kernel PPL/SPTM IOMMU request')
			'protected_context':           j.Value(map[string]j.Value{
				'descriptor_source':     j.Value('_t8110dart_get_desc')
				'initializer':           j.Value('_pmap_iommu_init')
				'init_data_bytes':       j.Value(u64(2408))
				'object_context_offset': j.Value(u64(3152))
			})
			'map_request':                 j.Value(map[string]j.Value{
				'segment_bytes':      j.Value(u64(40))
				'segment_count':      j.Value(u64(1))
				'physical_offset':    j.Value(u64(0))
				'iova_offset':        j.Value(u64(8))
				'byte_length_offset': j.Value(u64(16))
				'protection_offset':  j.Value(u64(24))
				'protection':         j.Value(u64(3))
				'reserved_offset':    j.Value(u64(32))
				'meaning_of_3':       j.Value('read/write protection, not segment count')
			})
			'partial_range':               j.Value(map[string]j.Value{
				'alignment_object_offset': j.Value(u64(3204))
				'start_must_be_aligned':   j.Value(true)
				'end_is_inclusive':        j.Value(true)
				'end_remainder':           j.Value('alignment - 1')
				'byte_length':             j.Value('end - start + 1')
				'entry_encoding_owner':    j.Value('kernel PPL/SPTM IOMMU request')
			})
			'mapper_index_semantics':      j.Value('DART hardware instance, not SID')
			'hardware_instance_stride':    j.Value(u64(112))
			'sid_count_register_offset':   j.Value(u64(12))
			'sid_count_mask':              j.Value(u64(511))
			'sid_property_format':         sid_property_format
			'bypass_property_prefix':      bypass_property_prefix
			'bypass_bitset_object_offset': j.Value(u64(2304))
		})
	}).as_map()
}

pub fn recover_t8110_kernel_code_contract(functions map[string]Function, index_masks []j.Value, index_shifts []j.Value) !map[string]j.Value {
	required := [t8110_dart_max_translation_levels, t8110_dart_vo_tt_index, t8110_dart_vo_tte]
	missing := required.filter(it !in functions)
	if missing.len != 0 {
		return error('kernel has no T8110 DART code body for ' + j.string_value(j.Value(missing.map(j.Value(it)))))
	}
	if !tuple_equal(index_masks, [266287972352, 8585740288, 4192256, 2047]) {
		return error('T8110 DART index masks changed: ' + tuple_repr(index_masks))
	}
	if !tuple_equal(index_shifts, [33, 22, 11, 0]) {
		return error('T8110 DART index shifts changed: ' + tuple_repr(index_shifts))
	}
	levels_code_body := function(functions, t8110_dart_max_translation_levels)!
	levels_code := levels_code_body.code
	if !a.has_ordered_words(levels_code, [
		u32(0x52800068),
		u32(0x1a880500),
	]) {
		return error('T8110 DART maximum-level selection changed')
	}
	tte_code_body := function(functions, t8110_dart_vo_tte)!
	tte_code := tte_code_body.code
	if !a.has_ordered_words(tte_code, [
		u32(0x360003ea), // bit 0 is the valid bit
		u32(0xd37ced4a), // encoded address << 4
		u32(0x92726d40), // retain physical bits through 0x3ffffffc000
	]) {
		return error('T8110 DART table-entry decoding changed')
	}
	return j.Value(map[string]j.Value{
		'page_table': j.Value(map[string]j.Value{
			'max_levels':                  j.Value(u64(4))
			'valid_bit':                   j.Value(u64(0))
			'physical_decode_shift':       j.Value(u64(4))
			'physical_decode_mask':        j.Value(u64(4398046494720))
			'index_masks_on_page_number':  j.Value(index_masks.clone())
			'index_shifts_on_page_number': j.Value(index_shifts.clone())
		})
	}).as_map()
}

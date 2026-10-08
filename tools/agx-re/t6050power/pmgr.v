module t6050power

import appleadt as a
import g17decode as g
import traceanalysis as j
import math.big
import strconv

struct RegMapCall {
	reg_map   u32
	reg_index u32
}

fn movz_w(word u32, register u32) ?u32 {
	if word & 0xffe0001f != 0x52800000 | register { return none }
	return (word >> 5) & 0xffff
}

fn reg_map_calls_repr(calls []RegMapCall) string {
	return '[' + calls.map('(' + it.reg_map.str() + ', ' + it.reg_index.str() + ')').join(', ') + ']'
}

fn format_hex(value j.Value) !string {
	match value {
		bool, int, i64, u8, u32, u64 {}
		j.Number {
			if value.text.contains_any('.eE') {
				return error("Unknown format code 'x' for object of type 'float'")
			}
		}
		string { return error("Unknown format code 'x' for object of type 'str'") }
		map[string]j.Value {
			return error('TypeError: unsupported format string passed to dict.__format__')
		}
		[]j.Value { return error('TypeError: unsupported format string passed to list.__format__') }
		else { return error('TypeError: unsupported format string passed to NoneType.__format__') }
	}
	integer := g.integer(value)!
	return if integer.signum < 0 {
		'-0x' + integer.abs().radix_str(16)
	} else {
		'0x' + integer.radix_str(16)
	}
}

pub fn recover_t6050_pmgr_code_contract(functions map[string]Function, symbols map[string]j.Value, apple_pmgr_symbols map[string]j.Value, vtable_targets map[string]j.Value) !map[string]j.Value {
	required := [t6050_init_reg_maps, pmgr_pmp_v1, pmgr_pmp_v2, pmgr_get_num_dies, pmgr_get_die_count]
	missing := required.filter(it !in symbols)
	if missing.len != 0 {
		return error('AppleT6050PMGR is missing symbols: ' + j.string_value(j.Value(missing.map(j.Value(it)))))
	}
	for name in [t6050_init_reg_maps, pmgr_pmp_v1, pmgr_pmp_v2, t6050_restore_hw,
		t6050_update_hib_device_status] {
		if name !in functions { return error('AppleT6050PMGR has no code body for ' + name) }
	}
	base_required := [pmgr_init_reg_map, pmp_wait_ready, pmp_notify_initial_entry,
		pmgr_pm_hibernation_state, pmgr_current_driver_state, pmgr_update_hib_device_status]
	base_missing := base_required.filter(it !in apple_pmgr_symbols)
	if base_missing.len != 0 {
		return error('ApplePMGR is missing T6050 base symbols: ' + j.string_value(j.Value(base_missing.map(j.Value(it)))))
	}
	expected_slots := {
		'2736': symbol(symbols, pmgr_pmp_v1)!
		'2744': symbol(symbols, pmgr_pmp_v2)!
		'2752': symbol(apple_pmgr_symbols, pmp_wait_ready)!
		'2760': symbol(symbols, pmgr_get_num_dies)!
		'2864': symbol(symbols, pmgr_get_die_count)!
	}
	for slot, expected in expected_slots {
		actual := j.value(vtable_targets, slot)
		if !integer_equal(actual, expected) {
			return error('AppleT6050PMGR vtable slot ' + format_hex(j.Value(j.Number{slot}))! + ' changed: ' + element_repr(actual) + ' != ' + format_hex(expected)!)
		}
	}
	v1 := function(functions, pmgr_pmp_v1)!
	v2 := function(functions, pmgr_pmp_v2)!
	if v1.code != encoded_words([u32(0xd503245f), u32(0xb95bd808), u32(0x7100051f), u32(0x1a9f17e0),
		u32(0xd65f03c0)]) {
		return error('AppleT6050PMGR PMP-v1 predicate changed')
	}
	if v2.code != encoded_words([u32(0xd503245f), u32(0xb95bd808), u32(0x7100091f), u32(0x1a9f17e0),
		u32(0xd65f03c0)]) {
		return error('AppleT6050PMGR PMP-v2 predicate changed')
	}
	init := function(functions, t6050_init_reg_maps)!
	mut reg_map_calls := []RegMapCall{}
	for instruction in g.words(init.code) {
		index := instruction.offset / 4
		if index < 5 || instruction.word & 0x7c000000 != 0x14000000 { continue }
		if !branch_at_equal(init, instruction.offset, symbol(apple_pmgr_symbols, pmgr_init_reg_map)!)! {
			continue
		}
		reg_map := movz_w(word_at(init.code, instruction.offset - 16), 1) or { return error('AppleT6050PMGR initRegMap call ABI changed') }
		reg_index := movz_w(word_at(init.code, instruction.offset - 12), 2) or { return error('AppleT6050PMGR initRegMap call ABI changed') }
		if word_at(init.code, instruction.offset - 20) != 0xaa1303e0 || word_at(init.code, instruction.offset - 8) != 0xaa1403e3 || word_at(init.code, instruction.offset - 4) != 0x52800004 {
			return error('AppleT6050PMGR initRegMap call ABI changed')
		}
		reg_map_calls << RegMapCall{reg_map, reg_index}
	}
	if reg_map_calls.len != 60 {
		return error('AppleT6050PMGR RegMap call count changed: ' + reg_map_calls.len.str())
	}
	for index, call in reg_map_calls {
		if call.reg_index != u32(index) {
			return error('AppleT6050PMGR DeviceTree reg-index order changed')
		}
	}
	ptd_calls := reg_map_calls.filter(it.reg_map == 8)
	if ptd_calls.len != 1 || ptd_calls[0].reg_index != 7 {
		return error('AppleT6050PMGR PTD RegMap dispatch changed: ' + reg_map_calls_repr(ptd_calls))
	}
	restore := function(functions, t6050_restore_hw)!
	restore_targets := branch_targets(restore)!
	for name in [pmgr_pm_hibernation_state, pmgr_current_driver_state, pmgr_update_hib_device_status] {
		if !targets_have(restore_targets, symbol(apple_pmgr_symbols, name)!)! {
			return error('AppleT6050PMGR restoreHW no longer calls ' + name)
		}
	}
	republications := branch_count(restore, symbol(apple_pmgr_symbols, pmp_notify_initial_entry)!)!
	if republications != 2 || !a.has_ordered_words(restore.code, [u32(0x7100081f), u32(0x7100081f)]) {
		return error('AppleT6050PMGR restoreHW initial-status republication changed: ' + republications.str())
	}
	hib := function(functions, t6050_update_hib_device_status)!
	hib_targets := branch_targets(hib)!
	if !targets_have(hib_targets, symbol(apple_pmgr_symbols, pmgr_update_hib_device_status)!)! || !targets_have(hib_targets, symbol(apple_pmgr_symbols, pmp_notify_initial_entry)!)! {
		return error('AppleT6050PMGR hibernation status update no longer republishes')
	}
	if !a.has_ordered_words(init.code, [u32(0xd2816611), u32(0x52800014), u32(0xaa1403e3),
		u32(0x11000694), u32(0x912cc208), u32(0xf9459a09), u32(0x54ffd103)]) {
		return error('AppleT6050PMGR per-die RegMap loop changed')
	}
	return {
		'pmp_version':         j.Value({
			'object_offset': j.Value(7128)
			'v1_value':      j.Value(1)
			'v2_value':      j.Value(2)
		})
		'vtable_slots':        j.Value({
			'pmp_v1':         j.Value(2736)
			'pmp_v2':         j.Value(2744)
			'wait_for_ready': j.Value(2752)
			'get_num_dies':   j.Value(2760)
			'get_die_count':  j.Value(2864)
		})
		'initial_publication': j.Value({
			'republication_sites': j.Value([j.Value(t6050_restore_hw),
				j.Value(t6050_update_hib_device_status)])
			'restore_hw_calls':    j.Value(republications)
			'restore_hw_guards':   j.Value([j.Value(pmgr_pm_hibernation_state),
				j.Value(pmgr_current_driver_state)])
			'guard_value':         j.Value(2)
			'entry':               j.Value(pmp_notify_initial_entry)
			'scope':               j.Value('resume republishes the same pre-ready device status that ApplePMGR::start published; it is never conditioned on PMP readiness')
		})
		'reg_maps':            j.Value({
			'initialization_calls_per_die': j.Value(reg_map_calls.len)
			'device_tree_indices':          j.Value(reg_map_calls.map(j.Value(it.reg_index)))
			'ptd':                          j.Value({
				'enum':                  j.Value(8)
				'device_tree_reg_index': j.Value(7)
			})
			'scope':                        j.Value('the complete 60-call table is repeated for every die')
		})
	}
}

fn bitwise_operand(value j.Value, operator string, right bool) !j.Value {
	mut kind := ''
	match value {
		bool, int, i64, u8, u32, u64 { return value }
		j.Number {
			if !value.text.contains_any('.eE') { return value }
			kind = 'float'
		}
		string { kind = 'str' }
		[]j.Value { kind = 'list' }
		map[string]j.Value { kind = 'dict' }
		else { kind = 'NoneType' }
	}
	first := if right { 'int' } else { kind }
	second := if right { kind } else { 'int' }
	return error('TypeError: unsupported operand type(s) for ' + operator + ": '" + first + "' and '" + second + "'")
}

fn decode_movz_query(request map[string]j.Value) !j.Value {
	word := g.integer(bitwise_operand(j.value(request, 'word'), '&', false)!)!
	register := g.integer(bitwise_operand(j.value(request, 'register'), '|', true)!)!
	if register.signum < 0 || register > g.integer(j.Value(u64(0xffffffff)))! {
		return j.value(map[string]j.Value{}, 'missing')
	}
	result := movz_w(masked_word(word)!, masked_word(register)!) or { return j.value(map[string]j.Value{}, 'missing') }
	return j.Value(result)
}

fn masked_word(value big.Integer) !u32 {
	return u32(strconv.parse_uint(value.mod_euclid(big.one_int.left_shift(32)).str(), 10, 64)!)
}

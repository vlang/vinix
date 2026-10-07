module g17decode

import imageextract as image
import traceanalysis as j

pub struct Instruction {
pub:
	offset int
	word   u32
}

pub fn words(code []u8) []Instruction {
	mut result := []Instruction{cap: code.len / 4}
	for offset := 0; offset <= code.len - 4; offset += 4 {
		result << Instruction{offset, image.u32_at(code, offset)}
	}
	return result
}

fn fields(name string, word u32) ?[]j.Value {
	value := decode(name, word, j.Value(0))
	if value is []j.Value { return value }
	return none
}

pub fn find_materialized_constant(code []u8, target j.Value) []j.Value {
	mut result := []j.Value{}
	instructions := words(code)
	for index, instruction in instructions {
		move := fields('decode_move_wide', instruction.word) or { continue }
		if j.string_value(move[0]) != 'movz' { continue }
		register := move[1].int()
		mut value := move[2].u64() << move[3].int()
		mut end := instruction.offset + 4
		for next := index + 1; next < instructions.len && next < index + 5; next++ {
			update := fields('decode_move_wide', instructions[next].word) or { break }
			if instructions[next].offset != end || j.string_value(update[0]) != 'movk' || update[1].int() != register {
				break
			}
			shift := update[3].int()
			value = (value & ~(u64(65535) << shift)) | (update[2].u64() << shift)
			end += 4
			if equal_integer(value, target) {
				result << tuple(j.Value(instruction.offset), j.Value(end), j.Value(register))
			}
		}
		if equal_integer(value, target) && result.len == 0 {
			result << tuple(j.Value(instruction.offset), j.Value(end), j.Value(register))
		}
	}
	return result
}

pub fn register_is_written(word u32, register int) bool {
	for name in ['decode_integer_load_unsigned', 'decode_load_register', 'decode_movz_w',
		'decode_movn_w', 'decode_movk_w'] {
		load := fields(name, word) or { continue }
		if load[0].int() == register { return true }
	}
	if register >= 0 && register <= 31 && word & 0xffc0001f == (u32(0xb9800000) | u32(register)) {
		return true
	}
	if pair := fields('decode_ldp_x', word) {
		if pair[0].int() == register || pair[1].int() == register { return true }
	}
	if move := fields('decode_move_wide', word) {
		if move[1].int() == register { return true }
	}
	return int(word & 31) == register && word & 0x1f000000 in [u32(0x0a000000), 0x0b000000, 0x10000000,
		0x11000000, 0x12000000, 0x13000000, 0x1a000000, 0x1b000000]
}

pub fn resolve_static_w_register(instructions []Instruction, before int, register int, depth int) ?u64 {
	if depth > 8 { return none }
	use_offset := if before < instructions.len {
		u64(instructions[before].offset)
	} else {
		u64(1) << 63
	}
	for index := before - 1; index >= 0; index-- {
		word := instructions[index].word
		if inverted := fields('decode_movn_w', word) {
			if inverted[0].int() == register { return inverted[1].u64() }
		}
		if materialized := fields('decode_movz_w', word) {
			if materialized[0].int() == register { return materialized[1].u64() & 0xffffffff }
		}
		if updated := fields('decode_movk_w', word) {
			if updated[0].int() == register {
				base := resolve_static_w_register(instructions, index, register, depth + 1) or { return none }
				shift := updated[2].int()
				return ((base & ~(u64(65535) << shift)) | (updated[1].u64() << shift)) & 0xffffffff
			}
		}
		if arithmetic := fields('decode_add_sub_immediate_w', word) {
			if arithmetic[1].int() == register {
				base := resolve_static_w_register(instructions, index, arithmetic[2].int(), depth + 1) or { return none }
				return (if j.string_value(arithmetic[0]) == 'add' {
					base + arithmetic[3].u64()
				} else {
					base - arithmetic[3].u64()
				}) & 0xffffffff
			}
		}
		if logical := fields('decode_logical_immediate_w', word) {
			if logical[1].int() == register {
				base := if logical[2].int() == 31 {
					u64(0)
				} else {
					resolve_static_w_register(instructions, index, logical[2].int(), depth + 1) or { return none }
				}
				return match j.string_value(logical[0]) {
					'and', 'ands' { base & logical[3].u64() }
					'orr' { base | logical[3].u64() }
					else { base ^ logical[3].u64() }
				}
			}
		}
		if logical := fields('decode_orr_register', word) {
			if logical[0].int() == register {
				first := if logical[1].int() == 31 {
					u64(0)
				} else {
					resolve_static_w_register(instructions, index, logical[1].int(), depth + 1) or { return none }
				}
				second := if logical[2].int() == 31 {
					u64(0)
				} else {
					resolve_static_w_register(instructions, index, logical[2].int(), depth + 1) or { return none }
				}
				return first | second
			}
		}
		for name in ['decode_load_unsigned', 'decode_load_register'] {
			if load := fields(name, word) {
				if load[0].int() == register { return none }
			}
		}
		if int(word & 31) == register && word & 0x1f000000 in [u32(0x0a000000), 0x0b000000, 0x10000000,
			0x11000000, 0x12000000, 0x13000000, 0x1a000000, 0x1b000000] {
			return none
		}
		if wide := fields('decode_move_wide', word) {
			if wide[1].int() == register { return none }
		}
		if register <= 18 && (word & 0xfc000000 == 0x94000000 || word & 0xfffffc00 == 0xd73f0800) {
			mut skipped := false
			for branch_index := index + 1; branch_index < before; branch_index++ {
				branch := instructions[branch_index]
				if branch.word & 0xfc000000 != 0x14000000 { continue }
				target := u64(i64(branch.offset) + signed(branch.word & 0x03ffffff, 26) * 4)
				if target > use_offset {
					skipped = true
					break
				}
			}
			if !skipped { return none }
		}
	}
	return none
}

pub fn resolve_static_x_register(instructions []Instruction, before int, register int, depth int) ?u64 {
	if depth > 8 { return none }
	for index := before - 1; index >= 0; index-- {
		word := instructions[index].word
		if inverted := fields('decode_movn_w', word) {
			if inverted[0].int() == register { return inverted[1].u64() }
		}
		if materialized := fields('decode_movz_w', word) {
			if materialized[0].int() == register { return materialized[1].u64() & 0xffffffff }
		}
		if updated := fields('decode_movk_w', word) {
			if updated[0].int() == register {
				return resolve_static_w_register(instructions, before, register, 0)
			}
		}
		if wide := fields('decode_move_wide', word) {
			if wide[1].int() == register {
				immediate := wide[2].u64() << wide[3].int()
				kind := j.string_value(wide[0])
				if kind == 'movn' { return ~immediate }
				if kind == 'movz' { return immediate }
				base := resolve_static_x_register(instructions, index, register, depth + 1) or { return none }
				return (base & ~(u64(65535) << wide[3].int())) | immediate
			}
		}
		for name in ['decode_load_unsigned', 'decode_load_register'] {
			if load := fields(name, word) {
				if load[0].int() == register { return none }
			}
		}
		if int(word & 31) == register && word & 0x1f000000 in [u32(0x0a000000), 0x0b000000, 0x11000000,
			0x12000000, 0x13000000, 0x1a000000, 0x1b000000] {
			return none
		}
		if register <= 18 && (word & 0xfc000000 == 0x94000000 || word & 0xfffffc00 == 0xd73f0800) {
			return none
		}
	}
	return none
}

pub struct StoreSpan {
pub:
	base  int
	low   int
	bytes int
	site  int
}

pub fn store_spans(code []u8) []StoreSpan {
	mut result := []StoreSpan{}
	for item in words(code) {
		if store := fields('decode_str_unsigned', item.word) {
			result << StoreSpan{store[1].int(), store[2].int(), store[3].int(), item.offset}
			continue
		}
		width := match item.word & 0xffe00c00 {
			0x38000000 { 1 }
			0x78000000 { 2 }
			0xb8000000, 0xbc000000 { 4 }
			0xf8000000, 0xfc000000 { 8 }
			0x3c800000 { 16 }
			else { 0 }
		}
		if width != 0 {
			result << StoreSpan{int((item.word >> 5) & 31), int(signed((item.word >> 12) & 511, 9)), width, item.offset}
			continue
		}
		pair_width := match item.word & 0xffc00000 {
			0x29000000, 0x2d000000 { 4 }
			0xa9000000, 0x6d000000 { 8 }
			0xad000000 { 16 }
			else { 0 }
		}
		if pair_width != 0 {
			result << StoreSpan{int((item.word >> 5) & 31), int(signed((item.word >> 15) & 127, 7)) * pair_width, pair_width * 2, item.offset}
		}
	}
	return result
}

pub fn stores_covering(code []u8, base int, target i64) []int {
	mut result := []int{}
	for store in store_spans(code) {
		if store.base == base && store.low <= target && target < i64(store.low) + store.bytes {
			result << store.site
		}
	}
	return result
}

pub fn stores_covering_any(code []u8, targets []i64) map[string]j.Value {
	mut result := map[string]j.Value{}
	for store in store_spans(code) {
		for target in targets {
			if store.low <= target && target < i64(store.low) + store.bytes {
				mut hits := (result[target.str()] or { j.Value([]j.Value{}) }).arr()
				hits << tuple(j.Value(store.base), j.Value(store.site))
				result[target.str()] = j.Value(hits)
			}
		}
	}
	return result
}

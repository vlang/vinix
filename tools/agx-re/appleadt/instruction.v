module appleadt

import encoding.binary
import g17decode as g
import math.big
import traceanalysis as j

fn address_at(address j.Value, offset int) j.Value {
	base := g.integer(address) or { return j.Value(0) }
	return j.Value(j.Number{(base + big.integer_from_int(offset)).str()})
}

fn direct_target(function_address j.Value, offset int, word u32) ?u64 {
	if word & 0x7c000000 != 0x14000000 { return none }
	name := if word & 0x80000000 != 0 { 'decode_bl_target' } else { 'decode_b_target' }
	return g.decode(name, word, address_at(function_address, offset)).u64()
}

pub fn direct_branch_targets(function_address j.Value, code []u8) []u64 {
	mut targets := map[u64]bool{}
	for instruction in g.words(code) {
		target := direct_target(function_address, instruction.offset, instruction.word) or { continue }
		targets[target] = true
	}
	mut result := []u64{}
	for target, _ in targets { result << target }
	result.sort()
	return result
}

pub fn direct_branch_count(function_address j.Value, code []u8, target u64) int {
	mut count := 0
	for instruction in g.words(code) {
		actual := direct_target(function_address, instruction.offset, instruction.word) or { continue }
		if actual == target { count++ }
	}
	return count
}

pub fn direct_branch_target_at(function_address j.Value, code []u8, offset int) ?u64 {
	if offset < 0 || offset > code.len - 4 { return none }
	return direct_target(function_address, offset, binary.little_endian_u32(code[offset..offset + 4]))
}

pub fn pc_relative_targets(function_address j.Value, code []u8) []u64 {
	mut result := map[u64]bool{}
	mut pages := map[int]u64{}
	for instruction in g.words(code) {
		page := g.decode('decode_adrp', instruction.word, address_at(function_address, instruction.offset)).arr()
		if page.len != 0 {
			pages[page[0].int()] = page[1].u64()
			continue
		}
		add := g.decode('decode_add_immediate', instruction.word, j.Value(0)).arr()
		if add.len != 0 {
			destination := add[0].int()
			source := add[1].int()
			if source in pages {
				pages[destination] = pages[source] + add[2].u64()
				result[pages[destination]] = true
			} else {
				pages.delete(destination)
			}
			continue
		}
		pages.delete(int(instruction.word & 31))
	}
	mut targets := []u64{}
	for target, _ in result { targets << target }
	targets.sort()
	return targets
}

pub fn has_sub_cmp_window(code []u8, source int, first u64, count u64) bool {
	words := g.words(code)
	for index := 0; index < words.len - 1; index++ {
		left := words[index].word
		right := words[index + 1].word
		if left & 0xff000000 != 0x51000000 { continue }
		left_source := int((left >> 5) & 31)
		immediate := u64((left >> 10) & 4095) << if left & (1 << 22) != 0 { 12 } else { 0 }
		if left_source != source || immediate != first { continue }
		if right & 0xff00001f != 0x7100001f { continue }
		right_source := int((right >> 5) & 31)
		right_immediate := u64((right >> 10) & 4095) << if right & (1 << 22) != 0 { 12 } else { 0 }
		if right_source == int(left & 31) && right_immediate == count { return true }
	}
	return false
}

pub fn has_cmp_w_immediate(code []u8, source int, immediate u64) bool {
	for item in g.words(code) {
		decoded := g.decode('decode_cmp_w_immediate', item.word, j.Value(0)).arr()
		if decoded.len != 0 && decoded[0].int() == source && decoded[1].u64() == immediate {
			return true
		}
	}
	return false
}

pub fn has_ldrb(code []u8, destination int, base int, immediate u64) bool {
	for item in g.words(code) {
		if item.word & 0xffc00000 != 0x39400000 { continue }
		if int(item.word & 31) == destination && int((item.word >> 5) & 31) == base && u64((item.word >> 10) & 4095) == immediate {
			return true
		}
	}
	return false
}

fn encoded_words(words []u32) []u8 {
	mut result := []u8{cap: words.len * 4}
	for word in words { result << [u8(word), u8(word >> 8), u8(word >> 16), u8(word >> 24)] }
	return result
}

pub fn has_words_in_order(code []u8, expected []u32) bool {
	needle := encoded_words(expected)
	if needle.len == 0 { return true }
	for offset := 0; offset <= code.len - needle.len; offset++ {
		if code[offset..offset + needle.len] == needle { return true }
	}
	return false
}

fn find_word(code []u8, word u32, start int) ?int {
	needle := encoded_words([word])
	for offset := start; offset <= code.len - 4; offset++ {
		if code[offset..offset + 4] == needle { return offset }
	}
	return none
}

pub fn has_ordered_words(code []u8, expected []u32) bool {
	mut offset := 0
	for word in expected {
		offset = find_word(code, word, offset) or { return false }
		offset += 4
	}
	return true
}

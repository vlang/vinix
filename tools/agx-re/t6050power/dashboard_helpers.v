module t6050power

import appleadt as a
import g17decode as g
import math.big
import strconv
import traceanalysis as j

fn bytes_find(code []u8, needle []u8, start int) int {
	low := if start < 0 {
		if start < -code.len { 0 } else { code.len + start }
	} else {
		start
	}
	for offset := low; offset <= code.len - needle.len; offset++ {
		if code[offset..offset + needle.len] == needle { return offset }
	}
	return -1
}

fn bytes_count(code []u8, needle []u8) int {
	if needle.len == 0 { return code.len + 1 }
	mut count := 0
	mut offset := 0
	for offset <= code.len - needle.len {
		found := bytes_find(code, needle, offset)
		if found < 0 { break }
		count++
		offset = found + needle.len
	}
	return count
}

fn bytes_slice(code []u8, start int, end int) []u8 {
	low := if start < 0 {
		if start < -code.len { 0 } else { code.len + start }
	} else {
		if start > code.len { code.len } else { start }
	}
	high := if end < 0 {
		if end < -code.len { 0 } else { code.len + end }
	} else {
		if end > code.len { code.len } else { end }
	}
	return code[low..if high < low { low } else { high }]
}

fn word_at(code []u8, offset int) u32 {
	assert offset >= 0 && offset <= code.len - 4
	return u32(code[offset]) | (u32(code[offset + 1]) << 8) | (u32(code[offset + 2]) << 16) | (u32(code[offset + 3]) << 24)
}

fn pc_at(address j.Value, offset int) !j.Value {
	return j.Value(j.Number{(g.integer(address)! + big.integer_from_int(offset)).str()})
}

fn branch_at_equal(body Function, offset int, target j.Value) !bool {
	if offset < 0 || offset > body.code.len - 4 { return false }
	word := word_at(body.code, offset)
	if word & 0x7c000000 != 0x14000000 { return false }
	branch_count(Function{body.address, encoded_words([word])}, j.Value(0))!
	actual := a.direct_branch_target_at(body.address, body.code, offset) or { return false }
	return integer_equal(j.Value(actual), target)
}

fn ready_clear_branch(value j.Value, target j.Value) bool {
	if value !is map[string]j.Value { return false }
	fields := value.as_map()
	return fields.len == 5 && integer_equal(j.value(fields, 'target'), target) && j.value(fields, 'condition') == j.Value('bit_clear') && integer_equal(j.value(fields, 'register'), j.Value(8)) && integer_equal(j.value(fields, 'bit'), j.Value(0)) && integer_equal(j.value(fields, 'bytes'), j.Value(4))
}

fn bounded_offset(offset big.Integer) !int {
	return int(strconv.parse_int(offset.str(), 10, 64)!)
}

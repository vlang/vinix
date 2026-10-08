module t6050power

import appleadt as a
import traceanalysis as j

struct ScopedProof {
	scope    string
	function Function
}

struct MailboxStatus {
	name            string
	register_offset u32
	bit_extract     u32
}

fn branch_targets(body Function) ![]u64 {
	branch_count(body, j.Value(0))!
	return a.direct_branch_targets(body.address, body.code)
}

fn targets_have(targets []u64, target j.Value) !bool {
	match target {
		map[string]j.Value { return error("TypeError: unhashable type: 'dict'") }
		[]j.Value { return error("TypeError: unhashable type: 'list'") }
		else {}
	}
	for address in targets { if integer_equal(j.Value(address), target) { return true } }
	return false
}

fn pc_targets(body Function) ![]u64 {
	for offset := 0; offset + 4 <= body.code.len; offset += 4 {
		match body.address {
			bool, int, i64, u8, u32, u64 {}
			j.Number {
				word := u32(body.code[offset]) | (u32(body.code[offset + 1]) << 8) | (u32(body.code[offset + 2]) << 16) | (u32(body.code[offset + 3]) << 24)
				if body.address.text.contains_any('.eE') && word & 0x9f000000 == 0x90000000 {
					return error("TypeError: unsupported operand type(s) for &: 'float' and 'int'")
				}
			}
			string { return error('TypeError: can only concatenate str (not "int") to str') }
			[]j.Value { return error('TypeError: can only concatenate list (not "int") to list') }
			map[string]j.Value {
				return error("TypeError: unsupported operand type(s) for +: 'dict' and 'int'")
			}
			else {
				return error("TypeError: unsupported operand type(s) for +: 'NoneType' and 'int'")
			}
		}
	}
	return a.pc_relative_targets(body.address, body.code)
}

fn pc_target_exists(body Function, target j.Value) !bool {
	return targets_have(pc_targets(body)!, target)
}

fn bytes_contain(code []u8, needle []u8) bool {
	for offset := 0; offset <= code.len - needle.len; offset++ {
		if code[offset..offset + needle.len] == needle { return true }
	}
	return false
}

fn integer_maps_equal(left map[string]j.Value, right map[string]j.Value) bool {
	if left.len != right.len { return false }
	for key, value in right {
		if key !in left || !integer_equal(j.value(left, key), value) { return false }
	}
	return true
}

fn symbol(symbols map[string]j.Value, name string) !j.Value {
	return symbols[name] or { return error('KeyError: ' + name) }
}

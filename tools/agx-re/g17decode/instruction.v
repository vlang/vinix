module g17decode

import math.big
import math
import traceanalysis as j

fn C.strtod(source &char, end &&char) f64

// These are deliberately the instruction predicates used by the recovery
// proofs, including their acceptance of reserved encodings. This is not an
// architectural validator or a general purpose disassembler.
const conditions = ['eq', 'ne', 'cs', 'cc', 'mi', 'pl', 'vs', 'vc', 'hi', 'ls', 'ge', 'lt', 'gt',
	'le', 'al', 'nv']!

fn tuple(values ...j.Value) j.Value { return j.Value(values) }

fn missing() j.Value { return j.value(map[string]j.Value{}, '') }

fn signed(value u32, bits int) i64 {
	return if value & (u32(1) << (bits - 1)) != 0 {
		i64(value) - (i64(1) << bits)
	} else {
		i64(value)
	}
}

pub fn integer(value j.Value) !big.Integer {
	if value is bool { return big.integer_from_int(if value { 1 } else { 0 }) }
	return big.integer_from_string(j.string_value(value))
}

fn equal_integer(value u64, target j.Value) bool {
	match target {
		bool { return value == if target { u64(1) } else { u64(0) } }
		int, i64, u8, u32, u64 {
			return !target.str().starts_with('-') && value == u64(target)
		}
		j.Number {
			if !target.text.contains_any('.eE') {
				return big.integer_from_u64(value) == (big.integer_from_string(target.text) or { return false })
			}
			// Compare the exact integral value of binary64. Converting the u64
			// operand to f64 would falsely equate UINT64_MAX with 2**64.
			terminated := target.text.clone()
			parsed := unsafe { C.strtod(&char(terminated.str), nil) }
			bits := math.f64_bits(parsed)
			if bits & 0x7fffffffffffffff == 0 { return value == 0 }
			if bits >> 63 != 0 { return false }
			exponent := int((bits >> 52) & 0x7ff) - 1023
			if exponent < 0 || exponent >= 64 { return false }
			significant := (u64(1) << 52) | (bits & 0x000fffffffffffff)
			if exponent >= 52 { return value == significant << (exponent - 52) }
			shift := 52 - exponent
			if significant & ((u64(1) << shift) - 1) != 0 { return false }
			return value == significant >> shift
		}
		else { return false }
	}
}

fn wide_mask(value big.Integer) u64 {
	modulus := big.integer_from_string('18446744073709551616') or { panic(err) }
	mut reduced := value % modulus
	if reduced.signum < 0 { reduced += modulus }
	bytes, _ := reduced.bytes()
	mut result := u64(0)
	for byte in bytes { result = (result << 8) | byte }
	return result
}

fn add_address(address j.Value, delta i64, masked bool) j.Value {
	base := integer(address) or { return missing() }
	value := base + big.integer_from_i64(delta)
	return if masked { j.Value(wide_mask(value)) } else { j.Value(j.Number{value.str()}) }
}

fn logical_mask(word u32, width int) ?u64 {
	n := if width == 64 { (word >> 22) & 1 } else { u32(0) }
	immr := (word >> 16) & 63
	imms := (word >> 10) & 63
	mut length_source := (n << 6) | (~imms & 63)
	mut length := -1
	for length_source != 0 {
		length_source >>= 1
		length++
	}
	if length < 1 { return none }
	levels := u32((1 << length) - 1)
	rotation := int(immr & levels)
	ones := int(imms & levels)
	if ones == int(levels) { return none }
	element_bits := 1 << length
	element_mask := if element_bits == 64 { ~u64(0) } else { (u64(1) << element_bits) - 1 }
	mut element := if ones == 63 { ~u64(0) } else { (u64(1) << (ones + 1)) - 1 }
	if rotation != 0 {
		element = ((element >> rotation) | (element << (element_bits - rotation))) & element_mask
	}
	mut immediate := u64(0)
	for shift := 0; shift < width; shift += element_bits { immediate |= element << shift }
	return immediate
}

// JSON scalar tokens preserve full 64-bit immediates and unbounded local
// branch addresses. Arrays correspond to the public Python tuple ABI.
pub fn decode(name string, word u32, address j.Value) j.Value {
	rd := int(word & 31)
	rn := int((word >> 5) & 31)
	rm := int((word >> 16) & 31)
	rt2 := int((word >> 10) & 31)
	imm12 := int((word >> 10) & 4095)
	width := if word & 0x80000000 != 0 { 8 } else { 4 }
	match name {
		'decode_move_wide' {
			kind := match word & 0xff800000 {
				0x92800000 { 'movn' }
				0xd2800000 { 'movz' }
				0xf2800000 { 'movk' }
				else { return missing() }
			}
			return tuple(j.Value(kind), j.Value(rd), j.Value(int((word >> 5) & 65535)), j.Value(int((word >> 21) & 3) * 16))
		}
		'decode_add_immediate', 'decode_add_sub_immediate_w', 'decode_cmp_w_immediate' {
			if name == 'decode_add_immediate' && word & 0xff000000 != 0x91000000 {
				return missing()
			}
			if name == 'decode_cmp_w_immediate' && word & 0xff00001f != 0x7100001f {
				return missing()
			}
			kind := match word & 0xff000000 {
				0x11000000 { 'add' }
				0x51000000 { 'sub' }
				else { '' }
			}
			if name == 'decode_add_sub_immediate_w' && kind == '' { return missing() }
			immediate := if word & (1 << 22) != 0 { imm12 << 12 } else { imm12 }
			if name == 'decode_cmp_w_immediate' { return tuple(j.Value(rn), j.Value(immediate)) }
			if name == 'decode_add_sub_immediate_w' {
				return tuple(j.Value(kind), j.Value(rd), j.Value(rn), j.Value(immediate))
			}
			return tuple(j.Value(rd), j.Value(rn), j.Value(immediate))
		}
		'decode_ldp_x', 'decode_stp_x', 'decode_pair_q' {
			op := word & 0xffc00000
			if name == 'decode_ldp_x' && op != 0xa9400000 { return missing() }
			if name == 'decode_stp_x' && op != 0xa9000000 { return missing() }
			if name == 'decode_pair_q' && op !in [u32(0xad400000), 0xad000000] { return missing() }
			immediate := signed((word >> 15) & 127, 7) * if name == 'decode_pair_q' {
				16
			} else {
				8
			}
			if name == 'decode_pair_q' {
				return tuple(j.Value(if op == 0xad400000 { 'load' } else { 'store' }), j.Value(rd), j.Value(rt2), j.Value(rn), j.Value(immediate))
			}
			return tuple(j.Value(rd), j.Value(rt2), j.Value(rn), j.Value(immediate))
		}
		'decode_load_unsigned', 'decode_integer_load_unsigned', 'decode_integer_store_unsigned',
		'decode_str_unsigned', 'decode_str_x', 'decode_ldr_x', 'decode_ldr_w', 'decode_ldr_d',
		'decode_str_d', 'decode_ldr_q' {
			op := word & 0xffc00000
			load := name.contains('load') || name.contains('ldr')
			mut bytes := match op {
				0x39400000, 0x39000000 { 1 }
				0x79400000, 0x79000000 { 2 }
				0xb9400000, 0xb9000000, 0xbd400000, 0xbd000000 { 4 }
				0xf9400000, 0xf9000000, 0xfd400000, 0xfd000000 { 8 }
				0x3dc00000, 0x3d800000 { 16 }
				else { return missing() }
			}
			if load && op !in [u32(0x39400000), 0x79400000, 0xb9400000, 0xf9400000, 0xbd400000,
				0xfd400000, 0x3dc00000] {
				return missing()
			}
			if !load && op !in [u32(0x39000000), 0x79000000, 0xb9000000, 0xf9000000, 0xbd000000,
				0xfd000000, 0x3d800000] {
				return missing()
			}
			if name == 'decode_integer_load_unsigned' && op !in [u32(0x39400000), 0x79400000,
				0xb9400000, 0xf9400000] {
				return missing()
			}
			if name == 'decode_integer_store_unsigned' && op !in [u32(0x39000000), 0x79000000,
				0xb9000000, 0xf9000000] {
				return missing()
			}
			exact := match name {
				'decode_str_x' { u32(0xf9000000) }
				'decode_ldr_x' { u32(0xf9400000) }
				'decode_ldr_w' { u32(0xb9400000) }
				'decode_ldr_d' { u32(0xfd400000) }
				'decode_str_d' { u32(0xfd000000) }
				'decode_ldr_q' { u32(0x3dc00000) }
				else { u32(0) }
			}
			if exact != 0 && op != exact { return missing() }
			if exact != 0 { return tuple(j.Value(rd), j.Value(rn), j.Value(imm12 * bytes)) }
			return tuple(j.Value(rd), j.Value(rn), j.Value(imm12 * bytes), j.Value(bytes))
		}
		'decode_load_register' {
			bytes := match word & 0xffe00c00 {
				0x38600800 { 1 }
				0x78600800 { 2 }
				0xb8600800 { 4 }
				0xf8600800 { 8 }
				else { return missing() }
			}
			return tuple(j.Value(rd), j.Value(rn), j.Value(rm), j.Value(bytes))
		}
		'decode_add_register' {
			if word & 0xff200000 != 0x8b000000 { return missing() }
			return tuple(j.Value(rd), j.Value(rn), j.Value(rm), j.Value(int((word >> 10) & 63)))
		}
		'decode_movz_w', 'decode_movn_w', 'decode_movk_w' {
			op := match name {
				'decode_movz_w' { u32(0x52800000) }
				'decode_movn_w' { u32(0x12800000) }
				else { u32(0x72800000) }
			}
			if word & 0xff800000 != op { return missing() }
			shift := int((word >> 21) & 1) * 16
			immediate := (word >> 5) & 65535
			if name == 'decode_movk_w' {
				return tuple(j.Value(rd), j.Value(immediate), j.Value(shift))
			}
			value := immediate << shift
			return tuple(j.Value(rd), j.Value(if name == 'decode_movn_w' { ~value } else { value }))
		}
		'decode_logical_immediate_w', 'decode_logical_immediate_x' {
			x := name.ends_with('_x')
			op := word & 0xff800000
			if (!x && op !in [u32(0x12000000), 0x32000000, 0x52000000, 0x72000000]) || (x && op !in [
				u32(0x92000000),
				0xb2000000,
				0xd2000000,
				0xf2000000,
			]) {
				return missing()
			}
			immediate := logical_mask(word, if x { 64 } else { 32 }) or { return missing() }
			return tuple(j.Value(['and', 'orr', 'eor', 'ands']![int((word >> 29) & 3)]), j.Value(rd), j.Value(rn), j.Value(immediate))
		}
		'decode_register_copy' {
			if word & 0x7fe0ffe0 != 0x2a0003e0 { return missing() }
			return tuple(j.Value(rd), j.Value(rm), j.Value(width))
		}
		'decode_orr_register' {
			if word & 0xffe0fc00 != 0x2a000000 { return missing() }
			return tuple(j.Value(rd), j.Value(rn), j.Value(rm))
		}
		'decode_umaddl' {
			if word & 0xffe08000 != 0x9ba00000 { return missing() }
			return tuple(j.Value(rd), j.Value(rn), j.Value(rm), j.Value(rt2))
		}
		'decode_bfi_x', 'decode_ubfiz_x' {
			if word & 0xffc00000 != if name == 'decode_bfi_x' {
				u32(0xb3400000)
			} else {
				u32(0xd3400000)
			} {
				return missing()
			}
			immr := int((word >> 16) & 63)
			imms := int((word >> 10) & 63)
			if imms >= immr { return missing() }
			return tuple(j.Value(rd), j.Value(rn), j.Value((-immr) & 63), j.Value(imms + 1))
		}
		'decode_stur_x', 'decode_stur_d' {
			if word & 0xffe00c00 != if name == 'decode_stur_x' {
				u32(0xf8000000)
			} else {
				u32(0xfc000000)
			} {
				return missing()
			}
			return tuple(j.Value(rd), j.Value(rn), j.Value(signed((word >> 12) & 511, 9)))
		}
		'decode_adrp' {
			if word & 0x9f000000 != 0x90000000 { return missing() }
			immediate := signed(((word >> 5) & 0x7ffff) << 2 | ((word >> 29) & 3), 21) * 4096
			base := wide_mask(integer(address) or { return missing() }) & ~u64(4095)
			return tuple(j.Value(rd), j.Value(base + u64(immediate)))
		}
		'decode_bl_target', 'decode_b_target', 'decode_local_branch_target',
		'decode_conditional_branch', 'decode_test_bit_branch', 'decode_compare_zero_branch' {
			mut target := missing()
			if name == 'decode_bl_target' || name == 'decode_b_target' {
				if word & 0xfc000000 != if name == 'decode_bl_target' {
					u32(0x94000000)
				} else {
					u32(0x14000000)
				} {
					return missing()
				}
				return add_address(address, signed(word & 0x03ffffff, 26) * 4, true)
			}
			if word & 0xfc000000 == 0x14000000 && name == 'decode_local_branch_target' {
				return add_address(address, signed(word & 0x03ffffff, 26) * 4, true)
			}
			if word & 0xff000010 == 0x54000000 {
				if name !in ['decode_local_branch_target', 'decode_conditional_branch'] {
					return missing()
				}
				target = add_address(address, signed((word >> 5) & 0x7ffff, 19) * 4, false)
			} else if word & 0x7e000000 == 0x34000000 {
				if name !in ['decode_local_branch_target', 'decode_compare_zero_branch'] {
					return missing()
				}
				target = add_address(address, signed((word >> 5) & 0x7ffff, 19) * 4, false)
			} else if word & 0x7e000000 == 0x36000000 {
				if name !in ['decode_local_branch_target', 'decode_test_bit_branch'] {
					return missing()
				}
				target = add_address(address, signed((word >> 5) & 0x3fff, 14) * 4, false)
			} else {
				return missing()
			}
			if name == 'decode_local_branch_target' { return target }
			if name == 'decode_conditional_branch' {
				condition := conditions[int(word & 15)]
				if condition in ['al', 'nv'] { return missing() }
				return tuple(target, j.Value(condition))
			}
			if name == 'decode_test_bit_branch' {
				bit := int(((word >> 31) & 1) << 5 | ((word >> 19) & 31))
				return j.Value(map[string]j.Value{
					'target':    target
					'condition': j.Value(if word & (1 << 24) != 0 { 'bit_set' } else { 'bit_clear' })
					'register':  j.Value(rd)
					'bit':       j.Value(bit)
					'bytes':     j.Value(if bit >= 32 { 8 } else { 4 })
				})
			}
			return j.Value(map[string]j.Value{
				'target':    target
				'condition': j.Value(if word & (1 << 24) != 0 { 'nonzero' } else { 'zero' })
				'register':  j.Value(rd)
				'bytes':     j.Value(width)
			})
		}
		'decode_logical_shifted_register' {
			if word & 0x1f000000 != 0x0a000000 { return missing() }
			amount := int((word >> 10) & 63)
			if width == 4 && amount >= 32 { return missing() }
			kind := if word & (1 << 21) != 0 {
				['bic', 'orn', 'eon', 'bics']![int((word >> 29) & 3)]
			} else {
				['and', 'orr', 'eor', 'ands']![int((word >> 29) & 3)]
			}
			return j.Value(map[string]j.Value{
				'operation':            j.Value(kind)
				'destination_register': j.Value(rd)
				'first_register':       j.Value(rn)
				'second_register':      j.Value(rm)
				'shift':                j.Value(['lsl', 'lsr', 'asr', 'ror']![int((word >> 22) & 3)])
				'amount':               j.Value(amount)
				'bytes':                j.Value(width)
			})
		}
		'decode_add_sub_immediate_value' {
			if word & 0x1f000000 != 0x11000000 { return missing() }
			return j.Value(map[string]j.Value{
				'operation':            j.Value(if word & (1 << 30) != 0 { 'sub' } else { 'add' })
				'destination_register': j.Value(rd)
				'source_register':      j.Value(rn)
				'immediate':            j.Value(if word & (1 << 22) != 0 {
					imm12 << 12
				} else {
					imm12
				})
				'bytes':                j.Value(width)
			})
		}
		'decode_add_sub_register_value' {
			if word & 0x1f000000 != 0x0b000000 { return missing() }
			mut result := map[string]j.Value{
				'operation':            j.Value(if word & (1 << 30) != 0 { 'sub' } else { 'add' })
				'destination_register': j.Value(rd)
				'first_register':       j.Value(rn)
				'second_register':      j.Value(rm)
				'bytes':                j.Value(width)
			}
			if word & (1 << 21) != 0 {
				result['extend'] = j.Value(['uxtb', 'uxth', 'uxtw', 'uxtx', 'sxtb', 'sxth', 'sxtw',
					'sxtx']![int((word >> 13) & 7)])
				result['amount'] = j.Value(int((word >> 10) & 7))
			} else {
				shift := int((word >> 22) & 3)
				if shift == 3 { return missing() }
				result['shift'] = j.Value(['lsl', 'lsr', 'asr']![shift])
				result['amount'] = j.Value(int((word >> 10) & 63))
			}
			return j.Value(result)
		}
		'decode_bitfield_value' {
			if word & 0x1f800000 != 0x13000000 { return missing() }
			op := int((word >> 29) & 3)
			if op == 3 || ((word >> 22) & 1) != u32(width == 8) { return missing() }
			return j.Value(map[string]j.Value{
				'operation':            j.Value(['sbfm', 'bfm', 'ubfm']![op])
				'destination_register': j.Value(rd)
				'source_register':      j.Value(rn)
				'rotate':               j.Value(int((word >> 16) & 63))
				'mask_end':             j.Value(int((word >> 10) & 63))
				'bytes':                j.Value(width)
			})
		}
		'decode_conditional_select_value' {
			if word & 0x1fe00000 != 0x1a800000 { return missing() }
			op2 := int((word >> 10) & 3)
			if op2 > 1 { return missing() }
			kind := ['csel', 'csinc', 'csinv', 'csneg']![int((word >> 30) & 1) * 2 + op2]
			return j.Value(map[string]j.Value{
				'operation':            j.Value(kind)
				'destination_register': j.Value(rd)
				'first_register':       j.Value(rn)
				'second_register':      j.Value(rm)
				'condition':            j.Value(conditions[int((word >> 12) & 15)])
				'bytes':                j.Value(width)
			})
		}
		else { return missing() }
	}
}

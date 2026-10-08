module g17expr

import g17decode as arm
import imageextract as image
import math.big
import traceanalysis as j
import json2
import math
import strconv

struct RuntimeSymbol {
	address u64
	name    string
}

fn runtime_direct_callers(data []u8, target j.Value) ![]string {
	symbols := arm.macho_symbols(data)!
	expected := runtime_target_bits(target)
	mut ordered := []RuntimeSymbol{}
	for name, address in symbols { ordered << RuntimeSymbol{address, name} }
	ordered.sort_with_compare(fn (a &RuntimeSymbol, b &RuntimeSymbol) int {
		if a.address != b.address { return if a.address < b.address { -1 } else { 1 } }
		return if a.name < b.name {
			-1
		} else if a.name == b.name {
			0
		} else {
			1
		}
	})
	mut callers := []string{}
	for command in image.load_commands(data, 0)! {
		if command.command != image.lc_segment_64 { continue }
		segment := image.parse_segment(data, command)!
		if segment.name != '__TEXT_EXEC' { continue }
		start := big.integer_from_u64(segment.file_offset)
		begin := string_offset(data, start)
		end := string_offset(data, start + big.integer_from_u64(segment.file_size))
		code := if begin < end { data[begin..end] } else { []u8{} }
		mut owner := 0
		wide_address := segment.virtual_address > ~u64(0) - u64(code.len)
		for instruction in arm.words(code) {
			if wide_address {
				address := big.integer_from_u64(segment.virtual_address) + big.integer_from_int(instruction.offset)
				for owner + 1 < ordered.len && big.integer_from_u64(ordered[owner + 1].address) <= address {
					owner++
				}
			} else {
				address := segment.virtual_address + u64(instruction.offset)
				for owner + 1 < ordered.len && ordered[owner + 1].address <= address { owner++ }
			}
			if instruction.word & 0xfc000000 != 0x94000000 {
				if target is json2.Null && ordered.len > 0 && ordered[owner].name !in callers {
					callers << ordered[owner].name
				}
				continue
			}
			if wanted := expected {
				// BL addresses wrap at 64 bits; symbol ownership above uses the
				// original unwrapped address, including segments crossing 2**64.
				displacement := (i64((instruction.word & 0x3ffffff) ^ 0x2000000) - 0x2000000) * 4
				actual := segment.virtual_address + u64(instruction.offset) + u64(displacement)
				if actual == wanted && ordered.len > 0 && ordered[owner].name !in callers {
					callers << ordered[owner].name
				}
			}
		}
	}
	callers.sort()
	return callers
}

fn runtime_target_equal(value big.Integer, target j.Value) bool {
	expected := runtime_target_bits(target) or { return false }
	return value == big.integer_from_u64(expected)
}

fn runtime_target_bits(target j.Value) ?u64 {
	match target {
		bool { return if target { u64(1) } else { u64(0) } }
		int, i64, u8, u32, u64 {
			if target.str().starts_with('-') { return none }
			return u64(target)
		}
		j.Number {
			if !target.text.contains_any('.eE') {
				number := big.integer_from_string(target.text) or { return none }
				if number.signum < 0 || number > big.integer_from_u64(~u64(0)) { return none }
				return strconv.parse_uint(number.str(), 10, 64) or { return none }
			}
			text := target.text.clone()
			bits := math.f64_bits(unsafe { C.strtod(&char(text.str), nil) })
			if bits & 0x7fffffffffffffff == 0 { return u64(0) }
			if bits >> 63 != 0 { return none }
			exponent := int((bits >> 52) & 0x7ff) - 1023
			if exponent < 0 || exponent >= 64 { return none }
			significant := (u64(1) << 52) | (bits & 0x000fffffffffffff)
			if exponent >= 52 { return significant << (exponent - 52) }
			shift := 52 - exponent
			if significant & ((u64(1) << shift) - 1) != 0 { return none }
			return significant >> shift
		}
		else { return none }
	}
}

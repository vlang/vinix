module macinspect

import traceanalysis as j
import json2
import encoding.base64
import math.big
import math
import strconv

pub enum Kind {
	null
	string
	number
	boolean
	bytes
	array
	object
	opaque
}

pub struct Property {
pub mut:
	kind    Kind
	text    string
	boolean bool
	bytes   []u8
	array   []Property
	fields  map[string]Property
}

pub fn property(item j.Value) Property {
	return match item {
		json2.Null { Property{} }
		string { Property{ kind: .string, text: item } }
		bool { Property{ kind: .boolean, boolean: item } }
		[]j.Value { Property{ kind: .array, array: item.map(property(it)) } }
		map[string]j.Value {
			if item.len == 1 && '__vinix_binary' in item {
				return Property{ kind: .bytes, bytes: base64.decode(j.string_value(item['__vinix_binary'] or { j.Value(json2.null) })) }
			}
			mut fields := map[string]Property{}
			for key, value in item { fields[key] = property(value) }
			Property{ kind: .object, fields: fields }
		}
		else { Property{ kind: .number, text: j.string_value(item) } }
	}
}

pub fn (p Property) json() j.Value {
	return match p.kind {
		.opaque {
			j.Value(map[string]j.Value{
				'__vinix_opaque': j.Value(p.text)
			})
		}
		.null { j.Value(json2.null) }
		.string { j.Value(p.text) }
		.number { j.Value(j.Number{p.text}) }
		.boolean { j.Value(p.boolean) }
		.bytes {
			j.Value(map[string]j.Value{
				'__vinix_binary': j.Value(base64.encode(p.bytes))
			})
		}
		.array { j.Value(p.array.map(it.json())) }
		.object {
			mut out := map[string]j.Value{}
			for key, value in p.fields { out[key] = value.json() }
			j.Value(out)
		}
	}
}

fn get(fields map[string]Property, name string) Property { return fields[name] or { Property{} } }

fn text(fields map[string]Property, name string) string { return get(fields, name).text }

fn value(fields map[string]j.Value, name string) j.Value {
	return fields[name] or { j.Value(json2.null) }
}

fn object(v j.Value) map[string]j.Value {
	return match v {
		map[string]j.Value { v }
		else { map[string]j.Value{} }
	}
}

fn list_value(v j.Value) []j.Value {
	return match v {
		[]j.Value { v }
		else { []j.Value{} }
	}
}

fn number(n u64) j.Value { return j.Value(j.Number{n.str()}) }

fn integer(v j.Value) !big.Integer {
	return match v {
		bool {
			if v { big.one_int } else { big.zero_int }
		}
		j.Number {
			if v.text.contains_any('.eE') { return error('not an integer') }
			big.integer_from_string(v.text)!
		}
		int, i64, u8, u32, u64 { big.integer_from_string(v.str())! }
		else { return error('not an integer') }
	}
}

fn is_integer(v j.Value) bool {
	if _ := integer(v) { return true }
	return false
}

fn whole(v j.Value) !big.Integer {
	if n := integer(v) { return n }
	match v {
		j.Number {
			x := unsafe { C.strtod(&char(v.text.str), nil) }
			bits := math.f64_bits(x)
			exponent := int((bits >> 52) & 0x7ff)
			if exponent == 0x7ff { return error('not finite') }
			if x == 0 { return big.zero_int }
			mantissa := if exponent == 0 {
				bits & ((u64(1) << 52) - 1)
			} else {
				(bits & ((u64(1) << 52) - 1)) | (u64(1) << 52)
			}
			shift := if exponent == 0 { -1074 } else { exponent - 1023 - 52 }
			mut n := big.integer_from_u64(mantissa)
			if shift >= 0 {
				n = n.left_shift(u32(shift))
			} else {
				divisor := big.one_int.left_shift(u32(-shift))
				q, remainder := n.div_mod(divisor)
				if remainder != big.zero_int { return error('not an integer') }
				n = q
			}
			return if bits >> 63 != 0 { n.neg() } else { n }
		}
		else { return error('not numeric') }
	}
}

fn eq(a j.Value, b j.Value) bool {
	if ai := whole(a) {
		if bi := whole(b) { return ai == bi }
		return false
	}
	if _ := whole(b) { return false }
	return match a {
		map[string]j.Value {
			match b {
				map[string]j.Value {
					if a.len != b.len { return false }
					for key, entry in a {
						if key !in b || !eq(entry, value(b, key)) { return false }
					}
					true
				}
				else { false }
			}
		}
		[]j.Value {
			match b {
				[]j.Value {
					if a.len != b.len { return false }
					for i, entry in a { if !eq(entry, b[i]) { return false } }
					true
				}
				else { false }
			}
		}
		j.Number {
			match b {
				j.Number {
					unsafe { C.strtod(&char(a.text.str), nil) == C.strtod(&char(b.text.str), nil) }
				}
				else { false }
			}
		}
		else { j.encode(a, false) == j.encode(b, false) }
	}
}

fn uword(v j.Value) u64 { return strconv.parse_uint(j.string_value(v), 10, 64) or { 0 } }

fn le(data []u8, offset int, size int) u64 {
	mut n := u64(0)
	for i in 0 .. size { n |= u64(data[offset + i]) << (i * 8) }
	return n
}

fn ascii(data []u8) !string {
	for i, b in data {
		if b >= 128 {
			return error("'ascii' codec can't decode byte 0x${b:02x} in position ${i}: ordinal not in range(128)")
		}
	}
	return data.bytestr()
}

fn trim_nul(data []u8) []u8 {
	mut end := data.len
	for end > 0 && data[end - 1] == 0 { end-- }
	return data[..end]
}

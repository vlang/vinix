// SPDX-License-Identifier: GPL-2.0-or-later
module sessioncore

pub fn decode_data(encoded string) !string {
	if encoded.len == 0 || encoded.len > clipboard_limit * 2 || encoded.len % 2 != 0 {
		return error('invalid exchange payload')
	}
	mut out := []u8{len: encoded.len / 2}
	defer { unsafe { out.free() } }
	for i in 0 .. out.len {
		a := data_nibble(encoded[i * 2])!
		b := data_nibble(encoded[i * 2 + 1])!
		out[i] = (a << 4) | b
	}
	return unsafe { tos(out.data, out.len).clone() }
}

fn data_nibble(byte u8) !u8 {
	if byte >= `0` && byte <= `9` { return byte - `0` }
	if byte >= `a` && byte <= `f` { return byte - `a` + 10 }
	return error('invalid exchange encoding')
}

pub fn (a &Associations) encode() string {
	mut w := Writer{}
	w.add('vinix-associations\t1\n')
	for i in 0 .. a.count {
		v := a.items[i]
		w.add('type\t')
		w.field(v.type.str())
		w.add('\t')
		w.field(v.app.str())
		w.add('\t')
		w.number(int(v.uri))
		w.add('\n')
	}
	return w.finish()
}

pub fn decode_associations(record string) !Associations {
	mut a := Associations{}
	mut start := 0
	mut header := false
	for end in 0 .. record.len + 1 {
		if end < record.len && record[end] != `\n` { continue }
		if end == start {
			start = end + 1
			continue
		}
		f := fields(unsafe { tos(&record.str[start], end - start) })!
		start = end + 1
		if !header {
			if f.count != 2 || f.values[0] != 'vinix-associations' || f.values[1] != '1' {
				return error('invalid associations')
			}
			header = true
			continue
		}
		if f.count != 4 || f.values[0] != 'type' { return error('invalid association entry') }
		kind := unfield(f.values[1])!
		app := unfield(f.values[2])!
		a.set(kind.str(), app.str(), number(f.values[3], 0, 1)! == 1)!
	}
	if !header { return error('missing associations header') }
	return a
}

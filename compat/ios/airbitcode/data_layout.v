// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

const max_layout_specs = 4096

pub struct IRAlignment {
pub:
	bits u32
	abi u64
	preferred u64
}
pub struct IRPointerLayout {
pub:
	address_space u32
	bits u32
	index_bits u32
	abi u64
	preferred u64
}
pub struct IRDataLayout {
pub mut:
	little_endian bool = true
	integers []IRAlignment
	floats []IRAlignment
	vectors []IRAlignment
	pointers []IRPointerLayout
	aggregate_abi u64 = 1
	aggregate_preferred u64 = 8
}
pub fn (d &IRDataLayout) free() {
	unsafe { d.integers.free(); d.floats.free(); d.vectors.free(); d.pointers.free() }
}
pub fn (d IRDataLayout) pointer_layout(space u32) IRPointerLayout {
	mut low := 0; mut high := d.pointers.len
	for low < high { middle := low + (high - low) / 2; if d.pointers[middle].address_space < space { low = middle + 1 } else { high = middle } }
	if low < d.pointers.len && d.pointers[low].address_space == space { return d.pointers[low] }
	return IRPointerLayout{...d.pointers[0], address_space: space}
}
fn layout_number(text string, limit u64) !u64 {
	if text.len == 0 { return error('AIR layout: empty number') }
	mut value := u64(0)
	for ch in text {
		if ch < `0` || ch > `9` { return error('AIR layout: non-decimal number') }
		digit := u64(ch - `0`)
		if value > limit / 10 || (value == limit / 10 && digit > limit % 10) { return error('AIR layout: number limit') }
		value = value * 10 + digit
	}
	return value
}
fn layout_alignment(text string, zero bool) !u64 {
	bits := layout_number(text, 65535)!
	if zero && bits == 0 { return 1 }
	if bits < 8 || bits % 8 != 0 || (bits & (bits - 1)) != 0 { return error('AIR layout: alignment must be byte-sized power of two') }
	return bits / 8
}
fn layout_set(mut specs []IRAlignment, spec IRAlignment) ! {
	for i, old in specs { if old.bits == spec.bits { specs[i] = spec; return } }
	if specs.len >= max_layout_specs { return error('AIR layout: alignment spec limit') }
	specs << spec
}
// This bounded profile accepts ordinary numeric size/alignment specs and
// validated hints that do not change type size. Unknown semantics fail closed.
pub fn parse_data_layout(text string) !IRDataLayout {
	if text.len > 65536 { return error('AIR layout: text limit') }
	mut d := IRDataLayout{
		integers: [IRAlignment{8, 1, 1}, IRAlignment{16, 2, 2}, IRAlignment{32, 4, 4}, IRAlignment{64, 4, 8}]
		floats: [IRAlignment{16, 2, 2}, IRAlignment{32, 4, 4}, IRAlignment{64, 8, 8}, IRAlignment{128, 16, 16}]
		pointers: [IRPointerLayout{0, 64, 64, 8, 8}]
	}
	d.integers.flags |= .noslices; d.floats.flags |= .noslices; d.vectors.flags |= .noslices; d.pointers.flags |= .noslices
	mut keep := false
	defer { if !keep { d.free() } }
	if text.len == 0 { keep = true; return d }
	parts := text.split('-'); defer { unsafe { parts.free() } }
	if parts.len > max_layout_specs { return error('AIR layout: component limit') }
	for part in parts {
		if part.len == 0 { return error('AIR layout: empty component') }
		fields := part.split(':'); defer { unsafe { fields.free() } }
		match part[0] {
			`e`, `E` {
				if part.len != 1 { return error('AIR layout: endianness component') }
				d.little_endian = part[0] == `e`
			}
			`p` {
				if fields.len < 3 || fields.len > 5 { return error('AIR layout: pointer spec arity') }
				space := if fields[0].len == 1 { u32(0) } else { u32(layout_number(fields[0][1..], 0xffffff)!) }
				bits := u32(layout_number(fields[1], 0xffffff)!)
				abi := layout_alignment(fields[2], false)!
				pref := if fields.len >= 4 { layout_alignment(fields[3], false)! } else { abi }
				index := if fields.len == 5 { u32(layout_number(fields[4], 0xffffff)!) } else { bits }
				if bits == 0 || index == 0 || index > bits || pref < abi { return error('AIR layout: pointer width/alignment') }
				p := IRPointerLayout{space, bits, index, abi, pref}
				mut found := false
				for i, old in d.pointers { if old.address_space == space { d.pointers[i] = p; found = true; break } }
				if !found { if d.pointers.len >= max_layout_specs { return error('AIR layout: pointer spec limit') }; d.pointers << p }
			}
			`i`, `f`, `v` {
				if fields.len !in [2, 3]! { return error('AIR layout: primitive spec arity') }
				bits := u32(layout_number(fields[0][1..], 0xffffff)!)
				abi := layout_alignment(fields[1], false)!
				pref := if fields.len == 3 { layout_alignment(fields[2], false)! } else { abi }
				if bits == 0 || pref < abi { return error('AIR layout: primitive width/alignment') }
				if part[0] == `i` && bits == 8 && abi != 1 { return error('AIR layout: i8 must be byte aligned') }
				spec := IRAlignment{bits, abi, pref}
				match part[0] { `i` { layout_set(mut d.integers, spec)! } `f` { layout_set(mut d.floats, spec)! } else { layout_set(mut d.vectors, spec)! } }
			}
			`a` {
				if fields[0] != 'a' || fields.len !in [2, 3]! { return error('AIR layout: aggregate spec arity') }
				d.aggregate_abi = layout_alignment(fields[1], true)!
				d.aggregate_preferred = if fields.len == 3 { layout_alignment(fields[2], false)! } else { d.aggregate_abi }
				if d.aggregate_preferred < d.aggregate_abi { return error('AIR layout: aggregate preferred alignment') }
			}
			`n` {
				layout_number(fields[0][1..], 0xffffff) or { return error('AIR layout: native integer widths') }
				for i, field in fields { value := layout_number(if i == 0 { field[1..] } else { field }, 0xffffff)!; if value == 0 { return error('AIR layout: zero native width') } }
			}
			`A`, `P`, `G` { if fields.len != 1 { return error('AIR layout: address space hint') }; layout_number(part[1..], 0xffffff)! }
			`S` { if fields.len != 1 { return error('AIR layout: stack alignment hint') }; layout_alignment(part[1..], false)! }
			`m` { if fields.len != 2 || fields[0] != 'm' || fields[1] !in ['e', 'o', 'm', 'w', 'x', 'a', 'l'] { return error('AIR layout: mangling hint') } }
			`F` { if part.len < 3 || part[1] !in [u8(`i`), `n`]! || fields.len != 1 { return error('AIR layout: function alignment hint') }; layout_alignment(part[2..], false)! }
			else { return error('AIR layout: unsupported component') }
		}
	}
	d.integers.sort(a.bits < b.bits); d.floats.sort(a.bits < b.bits); d.vectors.sort(a.bits < b.bits); d.pointers.sort(a.address_space < b.address_space)
	keep = true; return d
}

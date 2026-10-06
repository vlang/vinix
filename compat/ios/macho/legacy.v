// SPDX-License-Identifier: GPL-2.0-or-later
module macho

// These bytecode constants and formats are documented in mach-o/loader.h.
// The decoder always works on the original file, before any pointer is changed.
struct DyldCursor {
	data []u8
mut:
	offset u64
}

fn (mut c DyldCursor) byte() !u8 {
	if c.offset >= u64(c.data.len) { return error('Mach-O: truncated dyld bytecode') }
	value := c.data[int(c.offset)]
	c.offset++
	return value
}

fn (mut c DyldCursor) uleb() !u64 {
	mut value := u64(0)
	for shift := 0; shift < 70; shift += 7 {
		byte := c.byte()!
		if shift == 63 && byte & 0x7e != 0 { return error('Mach-O: ULEB128 overflow') }
		value |= u64(byte & 0x7f) << shift
		if byte & 0x80 == 0 { return value }
	}
	return error('Mach-O: ULEB128 overflow')
}

fn (mut c DyldCursor) sleb() !i64 {
	mut value := u64(0)
	for shift := 0; shift < 70; shift += 7 {
		byte := c.byte()!
		if shift == 63 && byte & 0x7f !in [u8(0), 0x7f] {
			return error('Mach-O: SLEB128 overflow')
		}
		value |= u64(byte & 0x7f) << shift
		if byte & 0x80 == 0 {
			if shift < 63 && byte & 0x40 != 0 { value |= ~u64(0) << (shift + 7) }
			return i64(value)
		}
	}
	return error('Mach-O: SLEB128 overflow')
}

fn (mut c DyldCursor) name() !string {
	start := c.offset
	for c.byte()! != 0 {
		if c.offset - start > 4096 { return error('Mach-O: dyld symbol name exceeds limit') }
	}
	return c.data[int(start)..int(c.offset - 1)].bytestr()
}

fn (image Image) dyld_cursor(info FileRange) !DyldCursor {
	Reader{image.data}.range(info.offset, info.size)!
	return DyldCursor{data: image.data[int(info.offset)..int(info.offset + info.size)]}
}

// Export lookup follows only the requested path. Limits and cycle detection
// apply even to a malicious trie with nodes pointing back to their parents.
pub fn (image Image) exported_address(name string, layout Layout, base u64) !u64 {
	if image.export_info.size == 0 { return image.defined_address(name, layout, base) }
	mut c := image.dyld_cursor(image.export_info)!
	mut node := u64(0)
	mut prefix := 0
	mut visited := map[u64]bool{}
	for _ in 0 .. 1024 {
		if node in visited { return error('Mach-O: cycle in export trie') }
		visited[node] = true
		c.offset = node
		terminal_size := c.uleb()!
		terminal_end := checked_end(c.offset, terminal_size)!
		if terminal_end >= u64(c.data.len) { return error('Mach-O: export terminal exceeds trie') }
		if prefix == name.len && terminal_size != 0 {
			// Decode terminal data in its own bounded view, so a short terminal
			// cannot borrow bytes from the following children.
			mut terminal := DyldCursor{data: unsafe { c.data[int(c.offset)..int(terminal_end)] }}
			flags := terminal.uleb()!
			if flags & ~u64(0x1f) != 0 || flags & 0x18 != 0 {
				return error('Mach-O: re-export/resolver export is not implemented: ${name}')
			}
			address := terminal.uleb()!
			if flags & 3 == 2 { return address } // Absolute symbol, no slide.
			if flags & 3 != 0 { return error('Mach-O: thread-local export lookup is not implemented') }
			vm_address := checked_end(layout.base, address)!
			if !image.contains_address(vm_address) { return error('Mach-O: export points outside image') }
			return checked_end(base, address)!
		}
		c.offset = terminal_end
		children := c.byte()!
		mut next := ~u64(0)
		mut matched := 0
		for _ in 0 .. children {
			edge := c.name()!
			child := c.uleb()!
			if child >= u64(c.data.len) || edge == '' { return error('Mach-O: invalid export trie edge') }
			if name[prefix..].starts_with(edge) {
				if next != ~u64(0) { return error('Mach-O: ambiguous export trie edge') }
				next = child
				matched = edge.len
			}
		}
		if next == ~u64(0) { return 0 }
		node = next
		prefix += matched
	}
	return error('Mach-O: export trie exceeds depth limit')
}

fn (image Image) defined_address(name string, layout Layout, base u64) !u64 {
	r := Reader{image.data}
	for i in 0 .. image.symbol_count {
		off := image.symbol_offset + u64(i) * 16
		kind := u8(r.u16(off + 4)! & 0xff)
		if kind & 0xe0 != 0 || kind & 1 == 0 || kind & 0x0e !in [u8(0xe), 2] { continue }
		nameoff := u64(r.u32(off)!)
		if nameoff >= image.string_size { return error('Mach-O: defined name exceeds string table') }
		if r.string_at(image.string_offset + nameoff, image.string_size - nameoff)! != name { continue }
		address := r.u64(off + 8)!
		if kind & 0x0e == 2 { return address }
		if !image.contains_address(address) { return error('Mach-O: defined symbol points outside image') }
		return checked_end(base, address - layout.base)!
	}
	return 0
}

fn (image Image) legacy_pointer(layout Layout, segment_index int, within u64) !(u64, u64) {
	if segment_index < 0 || segment_index >= image.segments.len {
		return error('Mach-O: dyld segment index exceeds image')
	}
	segment := image.segments[segment_index]
	if segment.name == '__PAGEZERO' || segment.prot & 2 == 0 || within % 8 != 0 || within > segment.filesize
		|| segment.filesize - within < 8 {
		return error('Mach-O: dyld pointer exceeds writable file-backed segment')
	}
	return segment.address - layout.base + within, segment.fileoff + within
}

fn (image Image) legacy_rebases(layout Layout, base u64) ![]Fixup {
	mut c := image.dyld_cursor(image.rebase_info)!
	mut segment := -1
	mut address := u64(0)
	mut pointer_type := u8(0)
	mut result := []Fixup{}
	mut occupied := map[u64]bool{}
	for c.offset < u64(c.data.len) {
		byte := c.byte()!
		op := byte & 0xf0
		imm := byte & 0xf
		mut count := u64(0)
		mut skip := u64(0)
		match op {
			0 { break }
			0x10 { pointer_type = imm }
			0x20 { segment = int(imm); address = c.uleb()! }
			0x30 { address += c.uleb()! }
			0x40 { address += u64(imm) * 8 }
			0x50 { count = u64(imm) }
			0x60 { count = c.uleb()! }
			0x70 { count = 1; skip = c.uleb()! }
			0x80 { count = c.uleb()!; skip = c.uleb()! }
			else { return error('Mach-O: unknown rebase opcode 0x${byte.hex()}') }
		}
		if count > 1048576 || u64(result.len) + count > 1048576 { return error('Mach-O: too many dyld rebases') }
		for _ in u64(0) .. count {
			if pointer_type != 1 { return error('Mach-O: only pointer rebases are supported') }
			offset, fileoff := image.legacy_pointer(layout, segment, address)!
			if offset in occupied { return error('Mach-O: duplicate dyld rebase') }
			occupied[offset] = true
			word := Reader{image.data}.u64(fileoff)!
			// Darwin RTTI stores its non-unique-name flag in the top byte.
			// Slide the address while preserving those non-address bits.
			target := word & 0x00ffffffffffffff
			if !image.contains_address(target) { return error('Mach-O: dyld rebase target 0x${target.hex()} at file offset 0x${fileoff.hex()} is outside image') }
			value := checked_end(base, target - layout.base)!
			if value >> 56 != 0 { return error('Mach-O: relocated pointer exceeds 56 address bits') }
			result << Fixup{offset, value | (word & 0xff00000000000000)}
			address += 8 + skip
		}
	}
	return result
}

fn (image Image) legacy_resolve(imported Import, weak_stream bool, layout Layout, base u64, resolver Resolver) !u64 {
	if imported.name == '' { return error('Mach-O: bind opcode has no symbol') }
	if imported.ordinal <= 0 || weak_stream {
		own := image.exported_address(imported.name, layout, base)!
		if own != 0 { return own }
	}
	if weak_stream {
		// Undefined weak-coalesced symbols retain the library ordinal from
		// nlist_64; the weak binding stream itself does not carry one.
		for item in image.imported_symbols()! {
			if item.name == imported.name {
				return resolver(item.library, imported.name) or {
					if item.weak { return 0 }
					return err
				}
			}
		}
		return error('Mach-O: weak binding has no definition: ${imported.name}')
	}
	if imported.ordinal > 0 { return resolve_import(image, imported, resolver) }
	if imported.ordinal !in [0, -1, -2, -3] { return error('Mach-O: invalid special bind ordinal') }
	library := match imported.ordinal {
		0 { '<self>' }
		-1 { '<main executable>' }
		-2 { '<flat lookup>' }
		else { '<weak lookup>' }
	}
	return resolver(library, imported.name) or {
		if imported.weak || imported.ordinal == -3 { return 0 }
		return err
	}
}

fn (image Image) legacy_bindings(info FileRange, lazy bool, weak_stream bool, layout Layout, base u64, resolver Resolver) ![]Fixup {
	mut c := image.dyld_cursor(info)!
	mut segment := -1
	mut address := u64(0)
	mut pointer_type := u8(1)
	mut ordinal := 0
	mut name := ''
	mut weak := false
	mut addend := i64(0)
	mut result := []Fixup{}
	mut resolved := map[string]u64{}
	for c.offset < u64(c.data.len) {
		byte := c.byte()!
		op := byte & 0xf0
		imm := byte & 0xf
		mut count := u64(0)
		mut skip := u64(0)
		match op {
			0 {
				if !lazy { break }
				segment = -1; address = 0; pointer_type = 1; ordinal = 0
				name = ''; weak = false; addend = 0
			}
			0x10 { ordinal = int(imm) }
			0x20 {
				value := c.uleb()!
				if value > u64(image.libraries.len) { return error('Mach-O: bind ordinal exceeds libraries') }
				ordinal = int(value)
			}
			0x30 { ordinal = if imm == 0 { 0 } else { int(imm) - 16 } }
			0x40 { name = c.name()!; weak = imm & 1 != 0 }
			0x50 { pointer_type = imm }
			0x60 { addend = c.sleb()! }
			0x70 { segment = int(imm); address = c.uleb()! }
			0x80 { address += c.uleb()! }
			0x90 { count = 1 }
			0xa0 { count = 1; skip = c.uleb()! }
			0xb0 { count = 1; skip = u64(imm) * 8 }
			0xc0 { count = c.uleb()!; skip = c.uleb()! }
			else { return error('Mach-O: unsupported bind opcode 0x${byte.hex()}') }
		}
		if count == 0 { continue }
		if count > 1048576 || u64(result.len) + count > 1048576 { return error('Mach-O: too many dyld bindings') }
		if pointer_type != 1 { return error('Mach-O: only pointer bindings are supported') }
		imported := Import{ordinal: ordinal, weak: weak, name: name}
		key := '${ordinal}:${weak}:${name}'
		value := if key in resolved { resolved[key] } else {
			v := image.legacy_resolve(imported, weak_stream, layout, base, resolver)!
			resolved[key] = v
			v
		}
		// Missing weak symbols remain null, even when an addend is present.
		// Pointer addends use modular arithmetic, including top-byte flags in
		// Darwin RTTI. Range checks apply to the write location, not an external
		// symbol's address (which may be an absolute integer constant).
		bound := if value == 0 && weak { u64(0) } else { value + u64(addend) }
		for _ in u64(0) .. count {
			offset, _ := image.legacy_pointer(layout, segment, address)!
			result << Fixup{offset, bound}
			address += 8 + skip
		}
	}
	return result
}

fn (image Image) plan_legacy_fixups(layout Layout, base u64, resolver Resolver) ![]Fixup {
	mut result := image.legacy_rebases(layout, base) or { return error('Mach-O rebases: ${err}') }
	result << image.legacy_bindings(image.bind_info, false, false, layout, base, resolver) or { return error('Mach-O bindings: ${err}') }
	// Resolve every lazy slot up front; no Darwin dyld_stub_binder is executed.
	result << image.legacy_bindings(image.lazy_bind_info, true, false, layout, base, resolver) or { return error('Mach-O lazy bindings: ${err}') }
	// Coalescing intentionally overwrites rebased pointers to weak definitions.
	result << image.legacy_bindings(image.weak_bind_info, false, true, layout, base, resolver) or { return error('Mach-O weak bindings: ${err}') }
	return result
}

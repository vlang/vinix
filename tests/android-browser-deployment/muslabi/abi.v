// SPDX-License-Identifier: GPL-2.0-or-later
module muslabi

import mapsaccountstage

pub struct Symbol {
pub:
	kind u8
	size u64
	weak bool
}

pub struct Table {
pub:
	imports map[string]Symbol
	exports map[string]Symbol
}

fn word(bytes []u8, at int, length int) u64 {
	mut value := u64(0)
	for i in 0 .. length { value |= u64(bytes[at + i]) << (8 * i) }
	return value
}

fn span(bytes []u8, offset u64, size u64) ![]u8 {
	if offset > u64(bytes.len) || size > u64(bytes.len) - offset {
		return error('musl ABI table outside ELF file')
	}
	return bytes[int(offset)..int(offset + size)]
}

// Section headers are not used by the runtime loader. Require the complete
// table to refer to exactly the same bytes through its unique PT_LOAD mapping,
// including rejection of partial overlaps with file-backed or zero-fill LOADs.
fn mapped_span(bytes []u8, address u64, size u64, section_offset u64) ! {
	if size == 0 || size > ~u64(0) - address { return error('invalid musl ABI mapped span') }
	mut mappings := 0
	mut intersections := 0
	mut mapped_offset := u64(0)
	programs := word(bytes, 32, 8)
	for i in 0 .. int(word(bytes, 56, 2)) {
		at := int(programs) + i * 56
		if word(bytes, at, 4) != 1 { continue }
		start := word(bytes, at + 16, 8)
		filesize := word(bytes, at + 32, 8)
		memory := word(bytes, at + 40, 8)
		// inspect_elf has already checked these program headers, bounds and sums.
		if memory != 0 && address < start + memory && start < address + size { intersections++ }
		if address >= start && address - start <= filesize && size <= filesize - (address - start) {
			mapped_offset = word(bytes, at + 8, 8) + (address - start)
			mappings++
		}
	}
	if mappings != 1 || intersections != 1 || mapped_offset != section_offset {
		return error('musl ABI section does not match unique loader file mapping')
	}
}

// Inspect only a fully described, unversioned dynamic symbol table. The engine
// and both musl implementations are pinned separately; this checks the ABI the
// engine actually requests rather than assuming matching library filenames.
pub fn inspect(bytes []u8) !Table {
	mapsaccountstage.inspect_elf(bytes)!
	mut tags := map[u64]u64{}
	programs := word(bytes, 32, 8)
	for i in 0 .. int(word(bytes, 56, 2)) {
		at := int(programs) + i * 56
		if word(bytes, at, 4) != 2 { continue }
		data := span(bytes, word(bytes, at + 8, 8), word(bytes, at + 32, 8))!
		for entry := 0; entry < data.len; entry += 16 {
			tag := word(data, entry, 8)
			if tag == 0 { break }
			if tag in [u64(0x6ffffff0), 0x6ffffffc, 0x6ffffffd, 0x6ffffffe, 0x6fffffff] {
				return error('versioned musl ABI is unsupported')
			}
			if tag in [u64(5), 6, 10, 11] {
				if tag in tags { return error('duplicate musl ABI metadata') }
				tags[tag] = word(data, entry + 8, 8)
			}
		}
	}
	if tags.len != 4 || tags[11] != 24 { return error('missing musl ABI dynamic metadata') }
	offset, count := word(bytes, 40, 8), word(bytes, 60, 2)
	if word(bytes, 58, 2) != 64 || count == 0 || count > 65535 {
		return error('invalid musl ABI section table')
	}
	sections := span(bytes, offset, count * 64)!
	mut symbols := []u8{}
	mut strings := []u8{}
	mut found := false
	for i in 0 .. int(count) {
		at := i * 64
		kind := word(sections, at + 4, 4)
		if kind in [u64(0x6ffffffd), 0x6ffffffe, 0x6fffffff] {
			return error('versioned musl ABI sections are unsupported')
		}
		if kind != 11 { continue }
		if found || word(sections, at + 16, 8) != tags[6] || word(sections, at + 56, 8) != 24 {
			return error('ambiguous musl ABI dynamic symbol table')
		}
		found = true
		symbols = span(bytes, word(sections, at + 24, 8), word(sections, at + 32, 8))!
		link := word(sections, at + 40, 4)
		if symbols.len == 0 || symbols.len % 24 != 0 || symbols.len > 16 * 1024 * 1024 || link >= count {
			return error('invalid musl ABI symbols or string link')
		}
		mapped_span(bytes, tags[6], u64(symbols.len), word(sections, at + 24, 8))!
		string_at := int(link) * 64
		if word(sections, string_at + 4, 4) != 3 || word(sections, string_at + 16, 8) != tags[5]
			|| tags[10] > word(sections, string_at + 32, 8) {
			return error('musl ABI dynamic strings disagree with sections')
		}
		strings = span(bytes, word(sections, string_at + 24, 8), tags[10])!
		mapped_span(bytes, tags[5], tags[10], word(sections, string_at + 24, 8))!
	}
	if !found { return error('missing musl ABI symbols') }
	mut imports := map[string]Symbol{}
	mut exports := map[string]Symbol{}
	for at := 24; at < symbols.len; at += 24 {
		binding := symbols[at + 4] >> 4
		visibility := symbols[at + 5] & 3
		if binding !in [u8(1), 2] || visibility !in [u8(0), 3] { continue }
		start := word(symbols, at, 4)
		if start == 0 || start >= u64(strings.len) { return error('invalid musl ABI symbol name') }
		mut end := int(start)
		for end < strings.len && strings[end] != 0 {
			if strings[end] < 33 || strings[end] > 126 || strings[end] == `@` {
				return error('unsafe or versioned musl ABI symbol name')
			}
			end++
		}
		if end == strings.len { return error('unterminated musl ABI symbol name') }
		name := strings[int(start)..end].bytestr()
		symbol := Symbol{symbols[at + 4] & 15, word(symbols, at + 16, 8), binding == 2}
		if symbol.kind !in [u8(0), 1, 2, 6] { return error('unsupported musl ABI symbol type') }
		if word(symbols, at + 6, 2) == 0 {
			if name in imports { return error('duplicate musl ABI import') }
			imports[name] = symbol
		} else {
			if name in exports { return error('duplicate musl ABI export') }
			exports[name] = symbol
		}
	}
	return Table{imports, exports}
}

// All required engine imports must be supplied by both the exact link-time
// musl and deployed musl. Dynamic data definitions are checked too: executable
// COPY relocations define their symbols at the executable's copy destination.
// Weak imports may be absent, as specified by ELF.
pub fn verify(engine Table, toolchain Table, runtime Table) ![]string {
	if engine.imports.len == 0 || toolchain.exports.len == 0 || runtime.exports.len == 0 {
		return error('incomplete musl ABI comparison')
	}
	mut requests := engine.imports.clone()
	for name, symbol in engine.exports {
		if symbol.kind in [u8(1), 6] {
			if name in requests { return error('ambiguous engine data symbol') }
			requests[name] = symbol
		}
	}
	mut verified := []string{}
	for name, requested in requests {
		for available in [toolchain.exports, runtime.exports] {
			if name !in available {
				if requested.weak { continue }
				return error('musl ABI symbol missing: ' + name)
			}
			provided := available[name]
			if (requested.kind != 0 && provided.kind != requested.kind)
				|| (requested.kind in [u8(1), 6] && requested.size != 0 && provided.size != requested.size) {
				return error('musl ABI symbol type or size mismatch: ' + name)
			}
		}
		verified << name
	}
	verified.sort()
	return verified
}

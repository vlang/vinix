// SPDX-License-Identifier: GPL-2.0-or-later
module macho

pub type Resolver = fn (library string, symbol string) !u64

pub struct Fixup {
pub:
	offset u64
	value  u64
}

struct Import {
	ordinal int
	weak    bool
	name    string
	addend  i64
}

pub struct ImportedSymbol {
pub:
	library string
	name    string
	weak    bool
}

fn imports(r Reader) ![]Import {
	if r.u32(0)! != 0 || r.u32(24)! != 0 {
		return error('Mach-O: unsupported chained fixups or compressed symbol pool')
	}
	offset := u64(r.u32(8)!)
	symbols := u64(r.u32(12)!)
	count := r.u32(16)!
	format := r.u32(20)!
	stride := match format {
		1 { u64(4) }
		2 { u64(8) }
		3 { u64(16) }
		else { return error('Mach-O: unsupported chained import format ${format}') }
	}
	if offset < 28 || symbols < 28 || count > 65536 {
		return error('Mach-O: invalid chained imports table')
	}
	r.range(offset, u64(count) * stride)!
	r.range(symbols, 0)!
	mut result := []Import{}
	for i in 0 .. count {
		p := offset + u64(i) * stride
		word := if format == 3 { r.u64(p)! } else { u64(r.u32(p)!) }
		raw_ordinal := if format == 3 { int(word & 0xffff) } else { int(word & 0xff) }
		ordinal := if format == 3 {
			if raw_ordinal > 0xfff0 { raw_ordinal - 0x10000 } else { raw_ordinal }
		} else {
			if raw_ordinal > 0xf0 { raw_ordinal - 0x100 } else { raw_ordinal }
		}
		weak := if format == 3 { word & 0x10000 != 0 } else { word & 0x100 != 0 }
		nameoff := if format == 3 { word >> 32 } else { word >> 9 }
		name_position := checked_end(symbols, nameoff)!
		r.range(name_position, 1)!
		addend := match format {
			2 { i64(i32(r.u32(p + 4)!)) }
			3 { i64(r.u64(p + 8)!) }
			else { i64(0) }
		}
		result << Import{
			ordinal: ordinal
			weak:    weak
			name:    r.string_at(name_position, u64(r.data.len) - name_position)!
			addend:  addend
		}
	}
	return result
}

// Inspect legacy undefined nlist_64 symbols without attempting to bind them.
// Defined, debug, local and common symbols are not dynamic imports.
fn (image Image) symbol_imports() ![]ImportedSymbol {
	r := Reader{image.data}
	mut result := []ImportedSymbol{}
	for i in 0 .. image.symbol_count {
		off := image.symbol_offset + u64(i) * 16
		kind := u8(r.u16(off + 4)! & 0xff)
		if kind & 0xe0 != 0 || kind & 0x0e != 0 || kind & 1 == 0 || r.u64(off + 8)! != 0 {
			continue
		}
		nameoff := u64(r.u32(off)!)
		if nameoff >= image.string_size { return error('Mach-O: import name exceeds string table') }
		name := r.string_at(image.string_offset + nameoff, image.string_size - nameoff)!
		if name == '' { return error('Mach-O: empty import name') }
		description := r.u16(off + 6)!
		ordinal := int(description >> 8)
		library := if image.flags & 0x80 == 0 {
			'<flat lookup>'
		} else if ordinal > 0 && ordinal <= image.libraries.len {
			image.libraries[ordinal - 1].name
		} else {
			match ordinal {
				0 { '<self>' }
				0xfe { '<flat lookup>' }
				0xff { '<main executable>' }
				else { return error('Mach-O: invalid symbol library ordinal ${ordinal}') }
			}
		}
		result << ImportedSymbol{library, name, description & 0x40 != 0}
	}
	return result
}

// Import names are independent of execution support. ARM64e and legacy dyld
// images remain inspectable even though their pointers cannot yet be bound.
pub fn (image Image) imported_symbols() ![]ImportedSymbol {
	if image.fixup_size == 0 { return image.symbol_imports() }
	r := Reader{image.data[int(image.fixup_offset)..int(image.fixup_offset + image.fixup_size)]}
	mut result := []ImportedSymbol{}
	for item in imports(r)! {
		library := if item.ordinal > 0 && item.ordinal <= image.libraries.len {
			image.libraries[item.ordinal - 1].name
		} else {
			match item.ordinal {
				0 { '<self>' }
				-1 { '<main executable>' }
				-2 { '<flat lookup>' }
				-3 { '<weak lookup>' }
				else { return error('Mach-O: invalid library ordinal ${item.ordinal}') }
			}
		}
		result << ImportedSymbol{library, item.name, item.weak}
	}
	return result
}

fn resolve_import(image Image, imported Import, resolver Resolver) !u64 {
	if imported.ordinal <= 0 || imported.ordinal > image.libraries.len {
		return error('Mach-O: unsupported library ordinal ${imported.ordinal} for ${imported.name}')
	}
	library := image.libraries[imported.ordinal - 1]
	return resolver(library.name, imported.name) or {
		if imported.weak { return 0 }
		return err
	}
}

fn (image Image) contains_address(address u64) bool {
	for segment in image.segments {
		if segment.name != '__PAGEZERO' && address >= segment.address && address - segment.address < segment.size {
			return true
		}
	}
	return false
}

// Validate every chain and resolve every import before changing image memory.
// The chain words are read from the file, so failure cannot leave a partly
// rewritten chain to be interpreted as more linker metadata.
pub fn (image Image) plan_fixups(layout Layout, runtime_base u64, resolver Resolver) ![]Fixup {
	if image.fixup_size == 0 { return []Fixup{} }
	r := Reader{image.data[int(image.fixup_offset)..int(image.fixup_offset + image.fixup_size)]}
	imported := imports(r)!
	mut resolved := []u64{cap: imported.len}
	for item in imported {
		resolved << resolve_import(image, item, resolver)!
	}
	starts := u64(r.u32(4)!)
	if starts < 28 { return error('Mach-O: invalid chained starts offset') }
	count := r.u32(starts)!
	if count != u32(image.segments.len) {
		return error('Mach-O: chained starts segment count does not match image')
	}
	r.range(starts + 4, u64(count) * 4)!
	mut result := []Fixup{}
	mut occupied := map[u64]bool{}
	file := Reader{image.data}
	for index in 0 .. count {
		relative := u64(r.u32(starts + 4 + u64(index) * 4)!)
		if relative == 0 { continue }
		if relative < 4 + u64(count) * 4 {
			return error('Mach-O: chained segment overlaps starts table')
		}
		p := checked_end(starts, relative)!
		size := u64(r.u32(p)!)
		if size < 22 { return error('Mach-O: truncated chained segment') }
		r.range(p, size)!
		page_size := u64(r.u16(p + 4)!)
		format := r.u16(p + 6)!
		if format !in [u16(2), 6] {
			return error('Mach-O: chained pointer format ${format} is not implemented (ARM64e/PAC requires a separate runtime)')
		}
		if page_size !in [u64(4096), 16384] {
			return error('Mach-O: unsupported chained page size')
		}
		segment := image.segments[int(index)]
		segment_offset := r.u64(p + 8)!
		if segment.address < layout.base || segment_offset != segment.address - layout.base {
			return error('Mach-O: chained segment offset does not match image')
		}
		pages := u64(r.u16(p + 20)!)
		if pages > (size - 22) / 2 || pages > (segment.size + page_size - 1) / page_size {
			return error('Mach-O: chained page table exceeds segment')
		}
		for page in u64(0) .. pages {
			first := u64(r.u16(p + 22 + page * 2)!)
			if first == 0xffff { continue }
			if first & 0x8000 != 0 {
				return error('Mach-O: multiple chained starts per page are not implemented')
			}
			mut cursor := first
			for {
				within := page * page_size + cursor
				if cursor % 4 != 0 || cursor + 8 > page_size || within > segment.filesize
					|| segment.filesize - within < 8 {
					return error('Mach-O: chained pointer exceeds file-backed page')
				}
				offset := segment_offset + within
				if offset in occupied || offset + 4 in occupied || (offset >= 4 && offset - 4 in occupied) {
					return error('Mach-O: overlapping chained pointers')
				}
				occupied[offset] = true
				word := file.u64(segment.fileoff + within)!
				mut value := u64(0)
				if word >> 63 != 0 {
					ordinal := int(word & 0xffffff)
					if ordinal >= imported.len || word & 0x7ffff00000000 != 0 {
						return error('Mach-O: invalid chained bind ordinal or reserved bits')
					}
					// The inline 8-bit addend of PTR_64 is unsigned; the import
					// table addend is signed (see dyld's fixup-chains.h).
					value = u64(i64(resolved[ordinal]) + imported[ordinal].addend + i64((word >> 24) & 0xff))
				} else {
					if word & 0x7fff000000000 != 0 {
						return error('Mach-O: tagged or reserved chained rebase bits are not supported')
					}
					target := word & 0xfffffffff
					address := if format == 6 { checked_end(layout.base, target)! } else { target }
					if !image.contains_address(address) {
						return error('Mach-O: chained rebase target is outside image')
					}
					value = checked_end(runtime_base, address - layout.base)!
				}
				result << Fixup{offset, value}
				next := (word >> 51) & 0xfff
				if next == 0 { break }
				cursor += next * 4
			}
		}
	}
	return result
}

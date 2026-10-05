@[translated]
module applecore

#include "v_abi.h"

fn C.memset(voidptr, i32, usize) voidptr

#include <stddef.h>
#include <stdint.h>

__global adt_to_fdt_state Convert_state

// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.
// SPDX-License-Identifier: GPL-2.0-or-later

// Freestanding helpers for the Apple loader. The loader runs with the MMU off,
// *where every access is Device memory and an unaligned one faults, so these
// *never widen an access past the alignment of its operands. The host tests
// *build the same sources against the C library instead.

pub fn load_le32(pointer voidptr) u32 {
	unsafe {
		bytes := &u8(pointer)
		return u32(bytes[0]) | u32(bytes[1]) << 8 | u32(bytes[2]) << 16 | u32(bytes[3]) << 24
	}
}

pub fn load_le64(pointer voidptr) u64 {
	unsafe {
		bytes := &u8(pointer)
		return u64(load_le32(voidptr(bytes))) | u64(load_le32(voidptr(bytes + 4))) << 32
	}
}

pub fn store_be32(pointer voidptr, value u32) {
	unsafe {
		bytes := &u8(pointer)
		bytes[0] = u8((value >> 24))
		bytes[1] = u8((value >> 16))
		bytes[2] = u8((value >> 8))
		bytes[3] = u8(value)
	}
}

pub fn load_be32(pointer voidptr) u32 {
	unsafe {
		bytes := &u8(pointer)
		return u32(bytes[0]) << 24 | u32(bytes[1]) << 16 | u32(bytes[2]) << 8 | u32(bytes[3])
	}
}

pub fn align_up(value u64, alignment u64) u64 {
	unsafe {
		return (value + alignment - u64(1)) & ~(alignment - u64(1))
	}
}

// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.
// SPDX-License-Identifier: GPL-2.0-or-later

// Word copies only when both sides share the same alignment, so a copy never
// *issues an unaligned access while the MMU is off.

@[export: 'memcpy']
pub fn memcpy(dest voidptr, src voidptr, count usize) voidptr {
	unsafe {
		mut out := &u8(dest)
		mut input := &u8(src)
		mut remaining := count
		if ((usize(out) ^ usize(input)) & 7) == 0 {
			for remaining != 0 && (usize(out) & 7) != 0 {
				*out = *input
				out++
				input++
				remaining--
			}
			for remaining >= 8 {
				*&u64(out) = *&u64(input)
				out += 8
				input += 8
				remaining -= 8
			}
		}
		for remaining != 0 {
			*out = *input
			out++
			input++
			remaining--
		}
		return dest
	}
}

@[export: 'memmove']
pub fn memmove(dest voidptr, src voidptr, count usize) voidptr {
	unsafe {
		out := &u8(dest)
		input := &u8(src)
		if usize(out) <= usize(input) || usize(out) >= usize(input) + count {
			return memcpy(dest, src, count)
		}
		mut remaining := count
		for remaining != 0 {
			remaining--
			out[remaining] = input[remaining]
		}
		return dest
	}
}

@[export: 'memset']
pub fn memset(dest voidptr, value i32, count usize) voidptr {
	unsafe {
		mut out := &u8(dest)
		mut remaining := count
		mut pattern := u64(u8(value))
		pattern |= pattern << 8
		pattern |= pattern << 16
		pattern |= pattern << 32
		for remaining != 0 && (usize(out) & 7) != 0 {
			*out = u8(value)
			out++
			remaining--
		}
		for remaining >= 8 {
			*&u64(out) = pattern
			out += 8
			remaining -= 8
		}
		for remaining != 0 {
			*out = u8(value)
			out++
			remaining--
		}
		return dest
	}
}

@[export: 'memcmp']
pub fn memcmp(left voidptr, right voidptr, count usize) i32 {
	unsafe {
		a := &u8(left)
		b := &u8(right)
		for index := usize(0); index < count; index++ {
			if i32(a[index]) != i32(b[index]) {
				return if i32(a[index]) < i32(b[index]) { -1 } else { 1 }
			}
		}
		return 0
	}
}

@[export: 'strlen']
pub fn strlen(text &char) usize {
	unsafe {
		length := usize(0)
		for text[length] {
			length++
		}
		return length
	}
}

@[export: 'strcmp']
pub fn strcmp(left &char, right &char) i32 {
	unsafe {
		mut a := left
		mut b := right
		for *a != 0 && *a == *b {
			a++
			b++
		}
		return i32(u8(*a)) - i32(u8(*b))
	}
}

@[export: 'lib_strnlen']
pub fn lib_strnlen(text &char, limit usize) usize {
	unsafe {
		length := usize(0)
		for length < limit && i32(text[length]) {
			length++
		}
		return usize(length)
	}
}

// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.
// SPDX-License-Identifier: GPL-2.0-or-later

// Apple DeviceTree (ADT), the recursive little-endian tree iBoot hands over.
// *A node is {u32 property count, u32 child count}, its properties, then its
// *children. A property is a 32-byte NUL-padded name, a u32 whose low 24 bits
// *are the length (iBoot keeps flags in the top byte), and the value padded to
// *four bytes. Nodes are addressed by their byte offset in the blob.

pub struct Adt {
pub mut:
	base &u8
	size usize
}

pub struct Adt_property {
pub mut:
	name &char
	// not NUL-terminated past ADT_NAME_BYTES
	name_length usize
	value       &u8
	length      u32
}

// Check that the whole blob is exactly one well-formed tree.

// Offsets of a node's first property, next property, first child and next
// *sibling. Callers iterate with the counts above; every offset was checked by
// *adt_validate.

// The node's "name" property, or "" when it has none.

// Resolve "/arm-io/wdt" style paths below the root. On success the chain of
// *node offsets from the root is written to path (terminated by SIZE_MAX), so
// *reg translation can walk back up through each bus.

// Translate reg[index] of the last node in chain to a CPU physical address
// *through every ancestor's ranges, as XNU's IODTResolveAddressCell does.

// Default cell counts when a bus omits them.

// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.
// SPDX-License-Identifier: GPL-2.0-or-later

pub fn property_length(adt &Adt, property usize) u32 {
	unsafe {
		return load_le32(voidptr(adt.base + property + 32)) & 16777215
	}
}

@[export: 'adt_property_count']
pub fn adt_property_count(adt &Adt, node usize) u32 {
	unsafe {
		return load_le32(voidptr(adt.base + node))
	}
}

@[export: 'adt_child_count']
pub fn adt_child_count(adt &Adt, node usize) u32 {
	unsafe {
		return load_le32(voidptr(adt.base + node + 4))
	}
}

@[export: 'adt_first_property']
pub fn adt_first_property(node usize) usize {
	unsafe {
		return usize(node + usize(8))
	}
}

@[export: 'adt_next_property']
pub fn adt_next_property(adt &Adt, property usize) usize {
	unsafe {
		return usize(u64(property + usize((32 + 4))) + align_up(u64(property_length(adt, property)), u64(4)))
	}
}

@[export: 'adt_first_child']
pub fn adt_first_child(adt &Adt, node usize) usize {
	unsafe {
		offset := adt_first_property(node)
		count := adt_property_count(adt, node)
		for index := u32(0); index < count; index++ {
			offset = adt_next_property(adt, offset)
		}
		return usize(offset)
	}
}

@[export: 'adt_next_sibling']
pub fn adt_next_sibling(adt &Adt, node usize) usize {
	unsafe {
		offset := adt_first_child(adt, node)
		count := adt_child_count(adt, node)
		for index := u32(0); index < count; index++ {
			offset = adt_next_sibling(adt, offset)
		}
		return usize(offset)
	}
}

// Recursive structural check; returns the end offset of the node or 0.

pub fn validate_node(adt &Adt, node usize, depth u32) usize {
	unsafe {
		if depth > u32(64) || node > adt.size || adt.size - node < usize(8) {
			return usize(0)
		}
		properties := adt_property_count(adt, node)
		children := adt_child_count(adt, node)
		if properties > u32(65536) || children > u32(65536) {
			return usize(0)
		}
		offset := adt_first_property(node)
		for index := u32(0); index < properties; index++ {
			if adt.size - offset < usize((32 + 4)) {
				return usize(0)
			}
			// The name must be terminated inside its 32 bytes.

			if lib_strnlen(&char(voidptr(adt.base)) + offset, usize(32)) == usize(32) {
				return usize(0)
			}
			padded := align_up(u64(property_length(adt, offset)), u64(4))
			if u64(adt.size - offset - usize((32 + 4))) < padded {
				return usize(0)
			}
			offset += u64((32 + 4)) + padded
		}
		for index := u32(0); index < children; index++ {
			offset = validate_node(adt, offset, depth + u32(1))
			if !offset {
				return usize(0)
			}
		}
		return usize(offset)
	}
}

@[export: 'adt_validate']
pub fn adt_validate(adt &Adt) i32 {
	unsafe {
		if (usize(adt.base) == 0) || adt.size < usize(8) {
			return -1
		}
		return if validate_node(adt, usize(0), u32(0)) == adt.size { 0 } else { -1 }
	}
}

@[export: 'adt_read_property']
pub fn adt_read_property(adt &Adt, property usize, out &Adt_property) {
	unsafe {
		out.name = &char(voidptr(adt.base)) + property
		out.name_length = lib_strnlen(out.name, usize(32))
		out.length = property_length(adt, property)
		out.value = adt.base + property + (32 + 4)
	}
}

@[export: 'adt_get']
pub fn adt_get(adt &Adt, node usize, name &char, out &Adt_property) i32 {
	unsafe {
		name_length := strlen(name)
		offset := adt_first_property(node)
		count := adt_property_count(adt, node)
		for index := u32(0); index < count; index++ {
			property := Adt_property{}
			adt_read_property(adt, offset, &property)
			if property.name_length == name_length && !memcmp(voidptr(property.name), voidptr(name), name_length) {
				*out = property
				return 0
			}
			offset = adt_next_property(adt, offset)
		}
		return -1
	}
}

@[export: 'adt_get_u32']
pub fn adt_get_u32(adt &Adt, node usize, name &char, value &u32) i32 {
	unsafe {
		property := Adt_property{}
		if adt_get(adt, node, name, &property) || property.length < u32(4) {
			return -1
		}
		*value = load_le32(voidptr(property.value))
		return 0
	}
}

@[export: 'adt_get_u64']
pub fn adt_get_u64(adt &Adt, node usize, name &char, value &u64) i32 {
	unsafe {
		property := Adt_property{}
		if adt_get(adt, node, name, &property) {
			return -1
		}
		if property.length >= u32(8) {
			*value = load_le64(voidptr(property.value))
		} else if property.length >= u32(4) {
			*value = u64(load_le32(voidptr(property.value)))
		} else {
			return -1
		}
		return 0
	}
}

@[export: 'adt_node_name']
pub fn adt_node_name(adt &Adt, node usize, length &usize) &char {
	unsafe {
		property := Adt_property{}
		if adt_get(adt, node, c'name', &property) || !property.length {
			*length = usize(0)
			return &char(&c''[0])
		}
		*length = lib_strnlen(&char(voidptr(property.value)), usize(property.length))
		return &char(voidptr(property.value))
	}
}

@[export: 'adt_is_compatible']
pub fn adt_is_compatible(adt &Adt, node usize, compatible &char) i32 {
	unsafe {
		property := Adt_property{}
		wanted := strlen(compatible)
		if adt_get(adt, node, c'compatible', &property) {
			return 0
		}
		for offset := usize(0); offset < usize(property.length); {
			entry := &char(voidptr(property.value)) + offset
			length := lib_strnlen(entry, usize(property.length) - offset)
			if length == wanted && !memcmp(voidptr(entry), voidptr(compatible), wanted) {
				return 1
			}
			offset += length + usize(1)
		}
		return 0
	}
}

pub fn find_child(adt &Adt, node usize, name &char, length usize, child &usize) i32 {
	unsafe {
		offset := adt_first_child(adt, node)
		count := adt_child_count(adt, node)
		for index := u32(0); index < count; index++ {
			child_length := usize(0)
			child_name := adt_node_name(adt, offset, &child_length)
			if child_length == length && !memcmp(voidptr(child_name), voidptr(name), length) {
				*child = offset
				return 0
			}
			offset = adt_next_sibling(adt, offset)
		}
		return -1
	}
}

@[export: 'adt_find_path']
pub fn adt_find_path(adt &Adt, path &char, node &usize, chain &usize, chain_capacity usize) i32 {
	unsafe {
		current := usize(0)
		depth := usize(0)
		if chain_capacity < usize(2) {
			return -1
		}
		chain[depth++] = current
		for (*path) {
			for i32((*path)) == i8(`/`) {
				path = path + 1
			}
			if !(*path) {
				break
			}
			length := usize(0)
			for i32(path[length]) && i32(path[length]) != i8(`/`) {
				length++
			}
			if find_child(adt, current, path, length, &current) {
				return -1
			}
			if depth + usize(1) >= chain_capacity {
				return -1
			}
			chain[depth++] = current
			path = path + length
		}
		chain[depth] = u64(0xffffffffffffffff)
		*node = current
		return 0
	}
}

@[export: 'adt_cell_counts']
pub fn adt_cell_counts(adt &Adt, node usize, address_cells &u32, size_cells &u32) {
	unsafe {
		if adt_get_u32(adt, node, c'#address-cells', address_cells) {
			*address_cells = u32(2)
		}
		if adt_get_u32(adt, node, c'#size-cells', size_cells) {
			*size_cells = u32(2)
		}
	}
}

pub fn read_cells(value &u8, cells u32) u64 {
	unsafe {
		if cells == u32(0) {
			return u64(0)
		}
		if cells == u32(1) {
			return u64(load_le32(voidptr(value)))
		}
		return load_le64(voidptr(value))
	}
}

@[export: 'adt_get_reg']
pub fn adt_get_reg(adt &Adt, chain &usize, index usize, address &u64, size &u64) i32 {
	unsafe {
		depth := usize(0)
		for chain[depth] != u64(0xffffffffffffffff) {
			depth++
		}
		if depth < usize(2) {
			return -1
		}
		node := chain[depth - usize(1)]
		address_cells := u32(0)
		size_cells := u32(0)

		adt_cell_counts(adt, chain[depth - usize(2)], &address_cells, &size_cells)
		if address_cells > u32(2) || size_cells > u32(2) {
			return -1
		}
		reg := Adt_property{}
		if adt_get(adt, node, c'reg', &reg) {
			return -1
		}
		stride := usize(u32(4) * (address_cells + size_cells))
		if !stride || (index + usize(1)) * stride > usize(reg.length) {
			return -1
		}
		entry := reg.value + (index * stride)
		result := read_cells(entry, address_cells)
		if size {
			*size = read_cells(entry + (u32(4) * address_cells), size_cells)
		}
		// Walk each bus from the node's parent up to (not including) the root.
		//     *Like XNU's IODTResolveAddressCell, a bus without ranges ends the walk:
		//     *the address is already a CPU physical address there.

		for bus_index := depth - usize(2); bus_index > usize(0); bus_index-- {
			bus := chain[bus_index]
			parent := chain[bus_index - usize(1)]
			ranges := Adt_property{}
			if adt_get(adt, bus, c'ranges', &ranges) || !ranges.length {
				break
			}
			child_cells := u32(0)
			bus_size_cells := u32(0)
			parent_cells := u32(0)
			parent_size_cells := u32(0)

			adt_cell_counts(adt, bus, &child_cells, &bus_size_cells)
			adt_cell_counts(adt, parent, &parent_cells, &parent_size_cells)
			range_stride := usize(u32(4) * (child_cells + parent_cells + bus_size_cells))
			if !range_stride || usize(ranges.length) % range_stride {
				return -1
			}
			translated := i32(0)
			for offset := usize(0); offset < usize(ranges.length); offset += range_stride {
				range := ranges.value + offset
				child := read_cells(range, child_cells)
				parent_address := read_cells(range + (u32(4) * child_cells), parent_cells)
				length := read_cells(range + (u32(4) * (child_cells + parent_cells)), bus_size_cells)
				if result >= child && result - child < length {
					result = parent_address + (result - child)
					translated = 1
					break
				}
			}
			if !translated {
				return -1
			}
		}
		*address = result
		return 0
	}
}

// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.
// SPDX-License-Identifier: GPL-2.0-or-later

// A sequential flattened-device-tree writer, and the conversion of an Apple
// *DeviceTree into one.
// * *The conversion keeps every node and property under Apple's own names so the
// *kernel's native-ADT code (compatible "aic,3", "/arm-io/gfx-asc", ...) sees
// *the tree iBoot described. Property values stay little-endian, as that code
// *reads them with the devicetree module's le helpers, with one exception: the
// *cell-structured properties the generic FDT helpers parse -- #address-cells,
// *#size-cells, reg and ranges -- are re-encoded big-endian value by value, and
// *each AAPL,phandle gains a big-endian "phandle".

pub struct Fdt_builder {
pub mut:
	buffer &u8
	// header, reservation map, then the structure block
	capacity usize
	length   usize
	// end of the structure block written so far
	strings          &char
	strings_length   usize
	strings_capacity usize
	hash             &u32
	// offset + 1 into strings, 0 for empty
	hash_slots usize
	// power of two
	error i32
}

// Every buffer is provided by the caller; nothing is allocated.

// Appends the strings block and fills in the header; returns the total size,
// *or 0 if anything overflowed.

// Properties added to the converted root and /chosen.

pub struct Adt_fdt_extras {
pub mut:
	bootargs &char
	// may be NULL

	// Out: reg/ranges properties kept verbatim because their length is not a
	//     *whole number of entries for the cell counts in force.
	malformed_cells u32
}

// Convert the whole ADT; returns 0 on success.

// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.
// SPDX-License-Identifier: GPL-2.0-or-later

// one terminating entry

pub fn put32(builder &Fdt_builder, value u32) {
	unsafe {
		if builder.error || builder.capacity - builder.length < usize(4) {
			builder.error = 1
			return
		}
		store_be32(voidptr(builder.buffer + builder.length), value)
		builder.length += usize(4)
	}
}

pub fn put_bytes(builder &Fdt_builder, bytes voidptr, length usize) {
	unsafe {
		padded := usize(align_up(u64(length), u64(4)))
		if builder.error || builder.capacity - builder.length < padded {
			builder.error = 1
			return
		}
		memcpy(voidptr(builder.buffer + builder.length), voidptr(bytes), length)
		memset(voidptr(builder.buffer + builder.length + length), 0, padded - length)
		builder.length += padded
	}
}

@[export: 'fdt_begin']
pub fn fdt_begin(builder &Fdt_builder, buffer voidptr, capacity usize, strings &char, strings_capacity usize, hash &u32, hash_slots usize) {
	unsafe {
		builder.buffer = &u8(buffer)
		builder.capacity = capacity
		builder.strings = strings
		builder.strings_length = usize(0)
		builder.strings_capacity = strings_capacity
		builder.hash = hash
		builder.hash_slots = hash_slots
		builder.error = (hash_slots & (hash_slots - usize(1))) != usize(0) || capacity < usize(40 + 16)
		if builder.error {
			return
		}
		memset(voidptr(hash), 0, hash_slots * sizeof(u32))
		memset(voidptr(buffer), 0, u64(40 + 16))
		builder.length = usize(40 + 16)
	}
}

@[export: 'fdt_begin_node']
pub fn fdt_begin_node(builder &Fdt_builder, name &char, name_length usize) {
	unsafe {
		padded := usize(align_up(u64(name_length + usize(1)), u64(4)))
		put32(builder, u32(1))
		if builder.error || builder.capacity - builder.length < padded {
			builder.error = 1
			return
		}
		memcpy(voidptr(builder.buffer + builder.length), voidptr(name), name_length)
		memset(voidptr(builder.buffer + builder.length + name_length), 0, padded - name_length)
		builder.length += padded
	}
}

pub fn string_offset(builder &Fdt_builder, name &char, length usize) u32 {
	unsafe {
		hash := u32(2166136261)
		for index := usize(0); index < length; index++ {
			hash ^= u32(u8(name[index]))
			hash *= 16777619
		}
		mask := builder.hash_slots - usize(1)
		for probe := usize(0); probe < builder.hash_slots; probe++ {
			slot := (usize(hash) + probe) & mask
			entry := builder.hash[slot]
			if !entry {
				if builder.strings_capacity - builder.strings_length < length + usize(1) {
					builder.error = 1
					return u32(0)
				}
				offset := u32(builder.strings_length)
				memcpy(voidptr(builder.strings + offset), voidptr(name), length)
				builder.strings[usize(offset) + length] = i8(0)
				builder.strings_length += length + usize(1)
				builder.hash[slot] = offset + u32(1)
				return offset
			}
			existing := builder.strings + entry - 1
			if lib_strnlen(existing, length + usize(1)) == length && !memcmp(voidptr(existing), voidptr(name), length) {
				return entry - u32(1)
			}
		}
		builder.error = 1
		return u32(0)
	}
}

@[export: 'fdt_property']
pub fn fdt_property(builder &Fdt_builder, name &char, name_length usize, value voidptr, length usize) {
	unsafe {
		offset := string_offset(builder, name, name_length)
		put32(builder, u32(3))
		put32(builder, u32(length))
		put32(builder, offset)
		put_bytes(builder, voidptr(value), length)
	}
}

@[export: 'fdt_end_node']
pub fn fdt_end_node(builder &Fdt_builder) {
	unsafe {
		put32(builder, u32(2))
	}
}

@[export: 'fdt_finish']
pub fn fdt_finish(builder &Fdt_builder) usize {
	unsafe {
		put32(builder, u32(9))
		if builder.error {
			return usize(0)
		}
		structure_offset := usize(40 + 16)
		structure_length := builder.length - structure_offset
		strings_offset := builder.length
		if builder.capacity - builder.length < builder.strings_length {
			builder.error = 1
			return usize(0)
		}
		memcpy(voidptr(builder.buffer + strings_offset), voidptr(builder.strings), builder.strings_length)
		total := usize(align_up(u64(strings_offset + builder.strings_length), u64(8)))
		if total > builder.capacity {
			builder.error = 1
			return usize(0)
		}
		memset(voidptr(builder.buffer + strings_offset + builder.strings_length), 0, total - strings_offset - builder.strings_length)
		header := builder.buffer
		store_be32(voidptr(header + 0), u32(3490578157))
		store_be32(voidptr(header + 4), u32(total))
		store_be32(voidptr(header + 8), u32(structure_offset))
		store_be32(voidptr(header + 12), u32(strings_offset))
		store_be32(voidptr(header + 16), u32(40))
		store_be32(voidptr(header + 20), u32(17))
		store_be32(voidptr(header + 24), u32(16))
		store_be32(voidptr(header + 28), u32(0))
		store_be32(voidptr(header + 32), u32(builder.strings_length))
		store_be32(voidptr(header + 36), u32(structure_length))
		return usize(total)
	}
}

// --- ADT conversion ----------------------------------------------------

pub fn name_is(property &Adt_property, name &char) i32 {
	unsafe {
		length := strlen(name)
		return i32(property.name_length == length && !memcmp(voidptr(property.name), voidptr(name), length))
	}
}

// Re-encode a sequence of little-endian values of the given cell widths as
// *big-endian FDT cells. A multi-cell value is one little-endian integer (low
// *word first), so reversing all of its bytes gives the FDT order.

pub fn encode_cells(property &Adt_property, widths &u32, width_count usize, out &u8, out_capacity usize) i32 {
	unsafe {
		stride := usize(0)
		for index := usize(0); index < width_count; index++ {
			stride += usize(u32(4) * widths[index])
		}
		if !stride || usize(property.length) % stride || usize(property.length) > out_capacity {
			return -1
		}
		for offset := usize(0); offset < usize(property.length); offset += stride {
			field := offset
			for index := usize(0); index < width_count; index++ {
				bytes := usize(u32(4) * widths[index])
				for byte_ := usize(0); byte_ < bytes; byte_++ {
					out[field + byte_] = property.value[field + bytes - usize(1) - byte_]
				}
				field += bytes
			}
		}
		return 0
	}
}

pub struct Convert_state {
pub mut:
	adt       &Adt
	builder   &Fdt_builder
	extras    &Adt_fdt_extras
	malformed u32
	scratch   [65536]u8
}

pub fn emit_u32(builder &Fdt_builder, name &char, value u32) {
	unsafe {
		encoded := [4]u8{}
		store_be32(voidptr(&encoded[0]), value)
		fdt_property(builder, name, strlen(name), voidptr(&encoded[0]), usize(4))
	}
}

// Converts the node at offset; returns the offset just past it, or 0.

pub fn convert_node(state &Convert_state, node usize, parent_address u32, parent_size u32, depth u32) usize {
	unsafe {
		adt := state.adt
		builder := state.builder
		address_cells := u32(0)
		size_cells := u32(0)

		has_address_cells := i32(0)
		has_size_cells := i32(0)

		if depth > u32(64) {
			return usize(0)
		}
		has_address_cells = !adt_get_u32(adt, node, c'#address-cells', &address_cells)
		has_size_cells = !adt_get_u32(adt, node, c'#size-cells', &size_cells)
		if !has_address_cells {
			address_cells = u32(2)
		}
		if !has_size_cells {
			size_cells = u32(2)
		}
		if depth == u32(0) {
			fdt_begin_node(builder, c'', usize(0))
		} else {
			name_length := usize(0)
			name := adt_node_name(adt, node, &name_length)
			fdt_begin_node(builder, name, name_length)
		}
		property_count := adt_property_count(adt, node)
		offset := adt_first_property(node)
		for index := u32(0); index < property_count; index++ {
			property := Adt_property{}
			adt_read_property(adt, offset, &property)
			offset = adt_next_property(adt, offset)
			if name_is(&property, c'#address-cells') || name_is(&property, c'#size-cells') {
				if property.length != u32(4) {
					return usize(0)
				}
				emit_u32(builder, property.name, load_le32(voidptr(property.value)))
				continue
			}
			if name_is(&property, c'reg') && depth > u32(0) {
				widths := [parent_address, parent_size]!

				if property.length && !encode_cells(&property, &widths[0], usize(2), &state.scratch[0], sizeof([65536]u8)) {
					fdt_property(builder, c'reg', usize(3), &state.scratch[0], usize(property.length))
					continue
				}
				// Not a whole number of entries: keep the bytes, and let a reader
				//             *that trusts the cell counts reject it rather than misparse it.

				state.malformed++
			}
			if name_is(&property, c'ranges') {
				widths := [address_cells, parent_address, size_cells]!

				if property.length && !encode_cells(&property, &widths[0], usize(3), &state.scratch[0], sizeof([65536]u8)) {
					fdt_property(builder, c'ranges', usize(6), &state.scratch[0], usize(property.length))
					continue
				}
				state.malformed++
			}
			if name_is(&property, c'AAPL,phandle') && property.length == u32(4) {
				emit_u32(builder, c'phandle', load_le32(voidptr(property.value)))
			}
			fdt_property(builder, property.name, property.name_length, voidptr(property.value), usize(property.length))
		}
		child_count := adt_child_count(adt, node)
		// The kernel's defaults for missing cell counts are not Apple's, so make
		//     *them explicit wherever a child's reg or this node's ranges need them.

		if child_count {
			if !has_address_cells {
				emit_u32(builder, c'#address-cells', address_cells)
			}
			if !has_size_cells {
				emit_u32(builder, c'#size-cells', size_cells)
			}
		}
		if depth == u32(0) {
			fdt_property(builder, c'vinix,apple-adt', usize(15), voidptr(c''), usize(0))
		}
		if depth == u32(1) && !(usize(state.extras) == 0) && !(usize(state.extras.bootargs) == 0) {
			name_length := usize(0)
			name := adt_node_name(adt, node, &name_length)
			if name_length == usize(6) && !memcmp(voidptr(name), voidptr(c'chosen'), u64(6)) {
				bootargs := state.extras.bootargs
				fdt_property(builder, c'bootargs', usize(8), voidptr(bootargs), strlen(bootargs) + u64(1))
			}
		}
		for index := u32(0); index < child_count; index++ {
			offset = convert_node(state, offset, address_cells, size_cells, depth + u32(1))
			if !offset {
				return usize(0)
			}
		}
		fdt_end_node(builder)
		return usize(offset)
	}
}

@[export: 'adt_to_fdt']
pub fn adt_to_fdt(adt &Adt, builder &Fdt_builder, extras &Adt_fdt_extras) i32 {
	unsafe {
		if adt_validate(adt) {
			return -1
		}
		adt_to_fdt_state.adt = adt
		adt_to_fdt_state.builder = builder
		adt_to_fdt_state.extras = extras
		adt_to_fdt_state.malformed = u32(0)
		end := convert_node(&adt_to_fdt_state, usize(0), u32(2), u32(2), u32(0))
		if extras {
			extras.malformed_cells = adt_to_fdt_state.malformed
		}
		if end != adt.size || builder.error {
			return -1
		}
		return 0
	}
}

// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.
// SPDX-License-Identifier: GPL-2.0-or-later

// Apple's native page; also a multiple of 4 KiB

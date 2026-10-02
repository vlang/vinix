// SPDX-License-Identifier: GPL-2.0-or-later
module ext2

import errno

// V promotes mutable metadata receivers even through unsafe addresses and
// fixed arrays. Native, function-scoped scratch storage makes their lifetime
// explicit; raw cache I/O copies the bytes before returning.
fn C.__builtin_alloca(usize) voidptr

const ea_magic = u32(0xea020000)
const ea_header_size = 32
const ea_entry_size = 16

@[packed]
struct EAHeader {
mut:
	magic u32
	refs u32
	blocks u32
	hash u32
	reserved [4]u32
}

@[packed]
struct EAEntry {
mut:
	name_len u8
	index u8
	value_offset u16
	value_block u32
	value_size u32
	hash u32
}

fn ea_round(size int) int { return (size + 3) & ~3 }

fn ea_entry(block voidptr, offset int) &EAEntry {
	return unsafe { &EAEntry(u64(block) + u64(offset)) }
}

fn ea_name(block voidptr, offset int) string {
	entry := ea_entry(block, offset)
	return unsafe { tos(&u8(u64(block) + u64(offset + ea_entry_size)), int(entry.name_len)) }
}

// ext2 sorts by namespace, name length, then unsigned name bytes.
fn ea_compare(index u8, name string, entry_index u8, entry_name string) int {
	if index != entry_index { return int(index) - int(entry_index) }
	if name.len != entry_name.len { return name.len - entry_name.len }
	for i in 0 .. name.len {
		if name[i] != entry_name[i] { return int(name[i]) - int(entry_name[i]) }
	}
	return 0
}

// Validate the whole untrusted block before exposing borrowed views. Values
// may share neither descriptor bytes nor one another; all arithmetic is
// bounded by the block size before a pointer is read.
fn ea_validate(block voidptr, size int) bool {
	if block == unsafe { nil } || size < 1024 || size > 65536 { return false }
	header := unsafe { &EAHeader(block) }
	if header.magic != ea_magic || header.blocks != 1 || header.refs == 0
		|| header.refs > 1024 { return false }
	for word in header.reserved { if word != 0 { return false } }
	mut offset := ea_header_size
	mut previous := -1
	mut values_start := size
	for {
		if offset > size - 4 { return false }
		if unsafe { *(&u32(u64(block) + u64(offset))) } == 0 { break }
		if offset > size - ea_entry_size { return false }
		entry := ea_entry(block, offset)
		next := offset + ea_round(ea_entry_size + int(entry.name_len))
		if next > size - 4 || entry.index == 0 || entry.value_block != 0 { return false }
		if (entry.index == 2 || entry.index == 3) && entry.name_len != 0 { return false }
		name := ea_name(block, offset)
		for c in name { if c == 0 { return false } }
		if previous >= 0 {
			last := ea_entry(block, previous)
			if ea_compare(entry.index, name, last.index, ea_name(block, previous)) <= 0 { return false }
		}
		value_offset := int(entry.value_offset)
		if entry.value_size > u32(size) || value_offset > size - int(entry.value_size) { return false }
		if entry.value_size != 0 {
			if value_offset & 3 != 0 { return false }
			if value_offset < values_start { values_start = value_offset }
		}
		previous = offset
		offset = next
	}
	if offset + 4 > values_start { return false }
	// Reject overlapping nonempty values, including overlapping padded tails.
	mut a := ea_header_size
	for a < offset {
		entry := ea_entry(block, a)
		mut b := ea_header_size
		for b < a {
			other := ea_entry(block, b)
			if entry.value_size != 0 && other.value_size != 0 {
				start := int(entry.value_offset)
				end := start + ea_round(int(entry.value_size))
				other_start := int(other.value_offset)
				other_end := other_start + ea_round(int(other.value_size))
				if end > size || other_end > size || (start < other_end && other_start < end) { return false }
			}
			b += ea_round(ea_entry_size + int(other.name_len))
		}
		if entry.value_size != 0 && int(entry.value_offset) + ea_round(int(entry.value_size)) > size { return false }
		a += ea_round(ea_entry_size + int(entry.name_len))
	}
	return true
}

fn ea_find(block voidptr, index u8, name string) int {
	mut offset := ea_header_size
	for unsafe { *(&u32(u64(block) + u64(offset))) } != 0 {
		entry := ea_entry(block, offset)
		compared := ea_compare(index, name, entry.index, ea_name(block, offset))
		if compared == 0 { return offset }
		if compared < 0 { return -1 }
		offset += ea_round(ea_entry_size + int(entry.name_len))
	}
	return -1
}

struct EABuilder {
mut:
	descriptors int = ea_header_size
	values int
}

fn ea_emit(block voidptr, mut builder EABuilder, index u8,
	name string, value voidptr, length int) ? {
	entry_bytes := ea_round(ea_entry_size + name.len)
	value_bytes := ea_round(length)
	if name.len > 255 || value_bytes > builder.values || builder.descriptors + entry_bytes + 4 > builder.values - value_bytes {
		errno.set(errno.enospc)
		return none
	}
	builder.values -= value_bytes
	mut entry := ea_entry(block, builder.descriptors)
	entry.name_len = u8(name.len)
	entry.index = index
	entry.value_offset = if length == 0 { u16(0) } else { u16(builder.values) }
	entry.value_size = u32(length)
	mut hash := u32(0)
	for i, c in name {
		unsafe { *(&u8(u64(block) + u64(builder.descriptors + ea_entry_size + i))) = c }
		hash = (hash << 5) ^ (hash >> 27) ^ u32(c)
	}
	if length != 0 {
		unsafe { C.memcpy(voidptr(u64(block) + u64(builder.values)), value, u64(length)) }
		for off := 0; off < value_bytes; off += 4 {
			word := unsafe { *(&u32(u64(block) + u64(builder.values + off))) }
			hash = (hash << 16) ^ (hash >> 16) ^ word
		}
	}
	entry.hash = hash
	builder.descriptors += entry_bytes
}

// Rebuild into a zeroed, private block. Unknown namespace indexes survive
// unchanged. A failed size check cannot modify the existing on-disk block.
fn ea_rebuild(old voidptr, output voidptr, size int, index u8, name string,
	value voidptr, length int, removing bool) ?int {
	mut header := unsafe { &EAHeader(output) }
	header.magic = ea_magic
	header.refs = 1
	header.blocks = 1
	mut builder := EABuilder{values: size}
	mut offset := ea_header_size
	mut inserted := removing
	mut count := 0
	if old != unsafe { nil } {
		for unsafe { *(&u32(u64(old) + u64(offset))) } != 0 {
			entry := ea_entry(old, offset)
			old_name := ea_name(old, offset)
			compared := ea_compare(index, name, entry.index, old_name)
			if !inserted && compared <= 0 {
				ea_emit(output, mut builder, index, name, value, length)?
				inserted = true
				count++
			}
			if compared != 0 {
				ea_emit(output, mut builder, entry.index, old_name,
					voidptr(u64(old) + u64(entry.value_offset)), int(entry.value_size))?
				count++
			}
			offset += ea_round(ea_entry_size + int(entry.name_len))
		}
	}
	if !inserted {
		ea_emit(output, mut builder, index, name, value, length)?
		count++
	}
	mut position := ea_header_size
	for position < builder.descriptors {
		entry := ea_entry(output, position)
		if entry.hash == 0 { header.hash = 0; break }
		header.hash = (header.hash << 16) ^ (header.hash >> 16) ^ entry.hash
		position += ea_round(ea_entry_size + int(entry.name_len))
	}
	return count
}

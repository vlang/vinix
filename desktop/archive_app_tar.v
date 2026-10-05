// SPDX-License-Identifier: GPL-2.0-or-later
// Strict, bounded USTAR/TAR parsing. No entry may name an unsafe filesystem object.
module main

const archive_max_bytes = 64 * 1024 * 1024
const archive_max_entries = 2048
const archive_max_depth = 32
const archive_chunk = 64 * 1024
const archive_path_limit = 4096

struct ArchiveEntry {
mut:
	name        string
	source_path string
	size_text   string
	size        u64
	offset      int
	directory   bool
	inode       u64
	device      u64
	mtime       i64
	mtime_nsec  i64
}

fn archive_borrow(bytes []u8, start int, end int) string {
	if end <= start { return '' }
	return unsafe { tos(&u8(bytes.data) + start, end - start) }
}

fn archive_name_valid(name string) bool {
	if name.len == 0 || name.len > 255 || name[0] == `/` || name[name.len - 1] == `/` {
		return false
	}
	mut component := 0
	mut depth := 1
	mut at := 0
	for at < name.len {
		byte := name[at]
		if byte == `/` {
			length := at - component
			if length == 0 || (length == 1 && name[component] == `.`)
				|| (length == 2 && name[component] == `.` && name[component + 1] == `.`) {
				return false
			}
			component = at + 1
			depth++
			if depth > archive_max_depth { return false }
			at++
			continue
		}
		if byte < 0x20 || byte == 0x7f || byte == `\\` { return false }
		length := editor_utf8_length(byte)
		if length == 0 || at + length > name.len { return false }
		for index in 1 .. length {
			if !editor_utf8_follows(byte, index, name[at + index]) { return false }
		}
		if length == 2 && byte == 0xc2 && name[at + 1] <= 0x9f { return false }
		at += length
	}
	length := name.len - component
	return length > 0 && !(length == 1 && name[component] == `.`)
		&& !(length == 2 && name[component] == `.` && name[component + 1] == `.`)
}

fn archive_is_parent(parent string, child string) bool {
	return child.len > parent.len && child[parent.len] == `/`
		&& unsafe { C.memcmp(parent.str, child.str, usize(parent.len)) } == 0
}

fn archive_entry_conflict(entries []ArchiveEntry, name string, directory bool) bool {
	for entry in entries {
		if entry.name == name || (!entry.directory && archive_is_parent(entry.name, name))
			|| (!directory && archive_is_parent(name, entry.name)) {
			return true
		}
	}
	return false
}

fn archive_free_entries(mut entries []ArchiveEntry) {
	for mut entry in entries {
		unsafe {
			entry.name.free()
			entry.source_path.free()
			entry.size_text.free()
		}
		entry.name = ''
		entry.source_path = ''
		entry.size_text = ''
	}
	entries.clear()
}

fn archive_octal(bytes []u8, start int, length int) (u64, bool) {
	mut value := u64(0)
	mut found := false
	mut ended := false
	for at in start .. start + length {
		byte := bytes[at]
		if byte == 0 || byte == ` ` {
			if found { ended = true }
			continue
		}
		if ended || byte < `0` || byte > `7` || value > (u64(~u64(0)) >> 3) { return 0, false }
		found = true
		value = (value << 3) | u64(byte - `0`)
	}
	return value, found
}

fn archive_zero(bytes []u8, start int, end int) bool {
	for at in start .. end { if bytes[at] != 0 { return false } }
	return true
}

fn archive_tar_field(bytes []u8, start int, length int) string {
	mut end := start
	for end < start + length && bytes[end] != 0 { end++ }
	return archive_borrow(bytes, start, end)
}

// All names are owned by entries; data is borrowed only while parsing.
// Requiring two end blocks and rejecting nonzero trailers avoids silently
// accepting truncated archives or concatenated hidden payloads.
fn archive_parse_tar(data []u8, mut entries []ArchiveEntry) (u64, string) {
	archive_free_entries(mut entries)
	if data.len >= 2 && ((data[0] == 0x1f && data[1] == 0x8b) || (data[0] == `P` && data[1] == `K`)) {
		return 0, 'archive.unsupported'
	}
	if data.len < 1024 || data.len % 512 != 0 || data.len > archive_max_bytes {
		return 0, 'archive.invalid_tar'
	}
	mut at := 0
	mut total := u64(0)
	for at + 512 <= data.len {
		if archive_zero(data, at, at + 512) {
			if at + 1024 > data.len || !archive_zero(data, at, data.len) {
				return 0, 'archive.invalid_tar'
			}
			return total, ''
		}
		if entries.len >= archive_max_entries { return 0, 'archive.entry_limit' }
		checksum, checksum_ok := archive_octal(data, at + 148, 8)
		mut sum := u64(0)
		for index in 0 .. 512 {
			sum += if index >= 148 && index < 156 { u64(32) } else { u64(data[at + index]) }
		}
		if !checksum_ok || sum != checksum { return 0, 'archive.invalid_tar' }
		magic := archive_tar_field(data, at + 257, 6)
		if magic.len > 0 && magic != 'ustar' && magic != 'ustar ' {
			return 0, 'archive.unsupported'
		}
		type_byte := data[at + 156]
		directory := type_byte == `5`
		if type_byte != 0 && type_byte != `0` && !directory {
			return 0, 'archive.unsafe_entry'
		}
		size, size_ok := archive_octal(data, at + 124, 12)
		if !size_ok || size > u64(archive_max_bytes) || total + size > u64(archive_max_bytes)
			|| (directory && size != 0) {
			return 0, 'archive.invalid_tar'
		}
		mut raw_name := archive_tar_field(data, at, 100)
		prefix := if magic.len > 0 { archive_tar_field(data, at + 345, 155) } else { '' }
		if directory && raw_name.len > 0 && raw_name[raw_name.len - 1] == `/` {
			raw_name = unsafe { tos(raw_name.str, raw_name.len - 1) }
		}
		name := if prefix.len > 0 { '${prefix}/${raw_name}' } else { raw_name.clone() }
		if !archive_name_valid(name) || archive_entry_conflict(entries, name, directory) {
			unsafe { name.free() }
			return 0, 'archive.unsafe_entry'
		}
		padded := ((size + 511) / 512) * 512
		if u64(at) + 512 + padded > u64(data.len) {
			unsafe { name.free() }
			return 0, 'archive.invalid_tar'
		}
		entries << ArchiveEntry{}
		entries[entries.len - 1].name = name
		entries[entries.len - 1].size = size
		entries[entries.len - 1].size_text = archive_size_text(size)
		entries[entries.len - 1].offset = at + 512
		entries[entries.len - 1].directory = directory
		total += size
		at += 512 + int(padded)
	}
	return 0, 'archive.invalid_tar'
}

fn archive_put_octal(mut header [512]u8, start int, width int, value u64) {
	mut next := value
	for index := start + width - 2; index >= start; index-- {
		header[index] = u8(`0`) + u8(next & 7)
		next >>= 3
	}
	header[start + width - 1] = 0
}

fn archive_tar_name_parts(name string) (int, bool) {
	if name.len <= 100 { return -1, true }
	mut split := -1
	for at in 0 .. name.len {
		if name[at] == `/` && at <= 155 && name.len - at - 1 <= 100 { split = at }
	}
	return split, split >= 0
}

fn archive_tar_header(entry ArchiveEntry) [512]u8 {
	mut header := [512]u8{}
	split, _ := archive_tar_name_parts(entry.name)
	start := if split >= 0 { split + 1 } else { 0 }
	for at in start .. entry.name.len { header[at - start] = entry.name[at] }
	if split >= 0 {
		for at in 0 .. split { header[345 + at] = entry.name[at] }
	}
	archive_put_octal(mut header, 100, 8, if entry.directory { u64(0o700) } else { u64(0o600) })
	archive_put_octal(mut header, 108, 8, 0)
	archive_put_octal(mut header, 116, 8, 0)
	archive_put_octal(mut header, 124, 12, entry.size)
	archive_put_octal(mut header, 136, 12, if entry.mtime > 0 { u64(entry.mtime) } else { u64(0) })
	for at in 148 .. 156 { header[at] = ` ` }
	header[156] = if entry.directory { u8(`5`) } else { u8(`0`) }
	for at, byte in 'ustar' { header[257 + at] = byte }
	header[263] = `0`
	header[264] = `0`
	mut checksum := u64(0)
	for byte in header { checksum += u64(byte) }
	archive_put_octal(mut header, 148, 8, checksum)
	return header
}

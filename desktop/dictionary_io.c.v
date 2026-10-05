// SPDX-License-Identifier: GPL-2.0-or-later
// Only an index and headwords stay in memory; definition reads are bounded.
module main

const dictionary_default_path = '/usr/share/vinix/dictionary/dictionary.vnd'
const dictionary_file_limit = 64 * 1024 * 1024
const dictionary_entry_limit = 200000
const dictionary_key_limit = 128
const dictionary_definition_limit = 64 * 1024
const dictionary_header_size = 24
const dictionary_record_size = 16

struct DictionarySource {
mut:
	fd int = -1
	count int
	table []u8
	keys []u8
	definitions_offset u64
	file_size u64
	modified_sec i64
	modified_nsec i64
}

fn dictionary_u32(bytes []u8, at int) u32 {
	return u32(bytes[at]) | u32(bytes[at + 1]) << 8 | u32(bytes[at + 2]) << 16 | u32(bytes[at + 3]) << 24
}

fn dictionary_compare(first string, second string) int {
	limit := if first.len < second.len { first.len } else { second.len }
	for index in 0 .. limit {
		if first[index] < second[index] { return -1 }
		if first[index] > second[index] { return 1 }
	}
	return if first.len < second.len { -1 } else if first.len > second.len { 1 } else { 0 }
}

fn dictionary_valid_text(text string, headword bool) bool {
	mut at := 0
	for at < text.len {
		lead := text[at]
		if lead < 0x20 || lead == 0x7f {
			if !headword && lead == `\n` { at++; continue }
			return false
		}
		length := editor_utf8_length(lead)
		if length == 0 || at + length > text.len { return false }
		for part in 1 .. length { if !editor_utf8_follows(lead, part, text[at + part]) { return false } }
		if length == 2 && lead == 0xc2 && text[at + 1] <= 0x9f { return false }
		at += length
	}
	return text.len > 0
}

fn (mut source DictionarySource) close() {
	if source.fd >= 0 { desktop_close(source.fd) }
	unsafe { source.table.free(); source.keys.free() }
	source = DictionarySource{}
}

fn dictionary_open_file(path string) int {
	if !backup_valid_path(path) { return -1 }
	mut separator := 0
	for at, byte in path { if byte == `/` { separator = at } }
	parent := console_borrow(path, 0, separator).clone()
	name := console_borrow(path, separator + 1, path.len).clone()
	defer { unsafe { parent.free(); name.free() } }
	directory := if separator == 0 { C.open(c'/', C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC, 0) } else { backup_open_directory(parent) }
	if directory < 0 { return -1 }
	defer { desktop_close(directory) }
	return C.openat(directory, &char(name.str), C.O_RDONLY | C.O_NONBLOCK | C.O_CLOEXEC | C.O_NOFOLLOW, 0)
}

fn dictionary_read_source(path string) ?DictionarySource {
	fd := dictionary_open_file(path)
	if fd < 0 { return none }
	mut source := DictionarySource{ fd: fd }
	mut accepted := false
	defer { if !accepted { source.close() } }
	mut info := C.stat{}
	if unsafe { C.fstat(fd, &info) } != 0 || u32(info.st_mode) & u32(C.S_IFMT) != u32(C.S_IFREG)
		|| info.st_size < dictionary_header_size || info.st_size > dictionary_file_limit { return none }
	mut header := []u8{len: dictionary_header_size}
	defer { unsafe { header.free() } }
	if !desktop_read_all(fd, header.data, u64(header.len)) { return none }
	if unsafe { tos(header.data, 8) } != 'VNXDICT1' { return none }
	count := dictionary_u32(header, 8)
	key_size := dictionary_u32(header, 12)
	definition_size := dictionary_u32(header, 16)
	if count == 0 || count > dictionary_entry_limit || key_size == 0
		|| u64(key_size) > u64(count) * dictionary_key_limit || definition_size == 0
		|| dictionary_u32(header, 20) != 0 { return none }
	definitions_offset := u64(dictionary_header_size) + u64(count) * dictionary_record_size + u64(key_size)
	if definitions_offset + u64(definition_size) != u64(info.st_size) { return none }
	source.table = []u8{len: int(count) * dictionary_record_size}
	source.keys = []u8{len: int(key_size)}
	if !desktop_read_all(fd, source.table.data, u64(source.table.len))
		|| !desktop_read_all(fd, source.keys.data, u64(source.keys.len)) { return none }
	source.count = int(count)
	source.definitions_offset = definitions_offset
	source.file_size = u64(info.st_size)
	source.modified_sec = i64(info.st_mtime)
	source.modified_nsec = unsafe { C.vinix_backup_mtime_nsec(&info) }
	mut key_end := u32(0)
	mut definition_end := u32(0)
	mut previous := ''
	for index in 0 .. source.count {
		at := index * dictionary_record_size
		start := dictionary_u32(source.table, at)
		length := dictionary_u32(source.table, at + 4)
		definition_start := dictionary_u32(source.table, at + 8)
		definition_length := dictionary_u32(source.table, at + 12)
		if start != key_end || length == 0 || length > dictionary_key_limit
			|| u64(start) + length > key_size || definition_start != definition_end
			|| definition_length == 0 || definition_length > dictionary_definition_limit
			|| u64(definition_start) + definition_length > definition_size { return none }
		word := source.word(index)
		if !dictionary_valid_text(word, true) || (index > 0 && dictionary_compare(previous, word) >= 0) { return none }
		previous = word
		key_end += length
		definition_end += definition_length
	}
	if key_end != key_size || definition_end != definition_size { return none }
	mut after := C.stat{}
	if unsafe { C.fstat(fd, &after) } != 0 || after.st_size != info.st_size
		|| i64(after.st_mtime) != source.modified_sec
		|| unsafe { C.vinix_backup_mtime_nsec(&after) } != source.modified_nsec { return none }
	accepted = true
	return source
}

fn (source &DictionarySource) word(index int) string {
	if index < 0 || index >= source.count { return '' }
	at := index * dictionary_record_size
	start := dictionary_u32(source.table, at)
	length := dictionary_u32(source.table, at + 4)
	return unsafe { tos(&u8(source.keys.data) + start, int(length)) }
}

fn (source &DictionarySource) lower_bound(query string) int {
	mut low := 0
	mut high := source.count
	for low < high {
		middle := low + (high - low) / 2
		if dictionary_compare(source.word(middle), query) < 0 { low = middle + 1 } else { high = middle }
	}
	return low
}

fn (source &DictionarySource) read_definition(index int) ?string {
	if source.fd < 0 || index < 0 || index >= source.count { return none }
	mut info := C.stat{}
	if unsafe { C.fstat(source.fd, &info) } != 0 || u64(info.st_size) != source.file_size
		|| i64(info.st_mtime) != source.modified_sec
		|| unsafe { C.vinix_backup_mtime_nsec(&info) } != source.modified_nsec { return none }
	at := index * dictionary_record_size
	start := dictionary_u32(source.table, at + 8)
	length := dictionary_u32(source.table, at + 12)
	if !desktop_seek_start(source.fd, source.definitions_offset + start) { return none }
	mut bytes := []u8{len: int(length)}
	defer { unsafe { bytes.free() } }
	if !desktop_read_all(source.fd, bytes.data, u64(bytes.len)) { return none }
	mut after := C.stat{}
	if unsafe { C.fstat(source.fd, &after) } != 0 || u64(after.st_size) != source.file_size
		|| i64(after.st_mtime) != source.modified_sec
		|| unsafe { C.vinix_backup_mtime_nsec(&after) } != source.modified_nsec { return none }
	text := editor_bytes_text(bytes)
	if !dictionary_valid_text(text, false) { return none }
	return text.clone()
}

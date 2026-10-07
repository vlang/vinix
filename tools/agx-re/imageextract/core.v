module imageextract

import encoding.binary
import encoding.hex
import encoding.utf8
import math.big
import os
import traceanalysis as j

pub const macho_magic_64 = u32(0xfeedfacf)
pub const lc_segment_64 = u32(0x19)
pub const lc_symtab = u32(2)
pub const lc_dysymtab = u32(0xb)
pub const lc_uuid = u32(0x1b)
pub const lc_function_starts = u32(0x26)
pub const lc_fileset_entry = u32(0x80000035)
pub const default_entries = ['com.apple.kernel', 'com.apple.driver.AppleARMPlatform',
	'com.apple.driver.ApplePMGR', 'com.apple.driver.AppleT6050PMGR', 'com.apple.driver.ApplePMP',
	'com.apple.driver.ApplePMPFirmware', 'com.apple.driver.RTBuddy', 'com.apple.driver.AppleA7IOP',
	'com.apple.driver.AppleA7IOP-ASCWrap-v6', 'com.apple.driver.AppleT8110DART',
	'com.apple.driver.IODARTFamily', 'com.apple.AGXFirmwareKextG17XRTBuddy',
	'com.apple.AGXFirmwareKextRTBuddy64', 'com.apple.AGXG17X', 'com.apple.iokit.IOGPUFamily',
	'com.apple.iokit.IOSurface']

pub struct Span {
pub:
	start int
	end   int
}

// Fixture construction also uses the native DER implementation. It is kept
// here so independent recovery tests can retain their existing import helper.
pub fn der_encode(tag u8, value []u8) []u8 {
	mut result := [tag]
	if value.len < 0x80 {
		result << u8(value.len)
	} else {
		mut length := u32(value.len)
		mut encoded := []u8{}
		for length != 0 {
			encoded.insert(0, u8(length & 0xff))
			length >>= 8
		}
		result << u8(0x80 | encoded.len)
		result << encoded
	}
	result << value
	return result
}

pub fn bytes_repr(data []u8) string {
	quote := if data.contains(`'`) && !data.contains(`"`) { '"' } else { "'" }
	mut text := 'b' + quote
	for byte in data {
		text += match byte {
			`\n` { '\\n' }
			`\r` { '\\r' }
			`\t` { '\\t' }
			`\\` { '\\\\' }
			else {
				if byte < 32 || byte >= 127 {
					'\\x${byte:02x}'
				} else if byte.ascii_str() == quote {
					'\\' + quote
				} else {
					byte.ascii_str()
				}
			}
		}
	}
	return text + quote
}

pub fn der_length(data []u8, offset int) !(u64, int) {
	if offset < 0 || offset >= data.len { return error('truncated DER length') }
	first := data[offset]
	if first < 0x80 { return u64(first), offset + 1 }
	count := int(first & 0x7f)
	if count == 0 || count > 4 || offset + 1 + count > data.len {
		return error('unsupported DER length')
	}
	mut length := u64(0)
	for digit in data[offset + 1..offset + 1 + count] { length = length << 8 | digit }
	return length, offset + 1 + count
}

pub fn der_item(data []u8, offset int, tag u8) !(Span, int) {
	if offset < 0 || offset >= data.len || data[offset] != tag {
		return error('expected DER tag 0x${tag:02x} at offset ${offset}')
	}
	length, content := der_length(data, offset + 1)!
	if length > u64(data.len - content) { return error('truncated DER item') }
	return Span{content, content + int(length)}, content + int(length)
}

pub struct Im4p {
pub:
	image_type Span
	payload    Span
	extra      bool
}

pub fn unwrap_im4p(blob []u8) !Im4p {
	outer, end := der_item(blob, 0, 0x30)!
	if end != blob.len { return error('trailing data after IM4P DER sequence') }
	mut sequence := unsafe { blob[outer.start..outer.end] }
	mut sequence_start := outer.start
	mut kind, mut offset := der_item(sequence, 0, 0x16)!
	if sequence[kind.start..kind.end].bytestr() == 'IMG4' {
		inner, _ := der_item(sequence, offset, 0x30)!
		sequence_start += inner.start
		sequence = sequence[inner.start..inner.end]
		kind, offset = der_item(sequence, 0, 0x16)!
	}
	if sequence[kind.start..kind.end].bytestr() != 'IM4P' {
		return error('not an IM4P payload (kind=${bytes_repr(sequence[kind.start..kind.end])})')
	}
	image_type, next := der_item(sequence, offset, 0x16)!
	_, description_end := der_item(sequence, next, 0x16)!
	payload, payload_end := der_item(sequence, description_end, 0x04)!
	return Im4p{
		image_type: Span{sequence_start + image_type.start, sequence_start + image_type.end}
		payload:    Span{sequence_start + payload.start, sequence_start + payload.end}
		extra:      payload_end != sequence.len
	}
}

pub fn im4p_payload(blob []u8) !Span {
	container := unwrap_im4p(blob)!
	kind := blob[container.image_type.start..container.image_type.end]
	if kind.bytestr() !in ['gfxf', 'gf1f'] {
		return error('not an AGX firmware IM4P (type=${bytes_repr(kind)})')
	}
	if container.extra { return error('unsupported extra IM4P fields') }
	return container.payload
}

pub fn kernel_im4p_payload(blob []u8) !Span {
	container := unwrap_im4p(blob)!
	kind := blob[container.image_type.start..container.image_type.end]
	if kind.bytestr() != 'krnl' { return error('not a kernel IM4P (type=${bytes_repr(kind)})') }
	return container.payload
}

pub fn pmp_payload(blob []u8) !Span {
	outer, end := der_item(blob, 0, 0x30)!
	if end != blob.len { return error('trailing data after DER sequence') }
	mut sequence := unsafe { blob[outer.start..outer.end] }
	mut sequence_start := outer.start
	mut kind, mut offset := der_item(sequence, 0, 0x16)!
	initial_kind := unsafe { sequence[kind.start..kind.end] }
	if initial_kind.bytestr() == 'IMG4' {
		inner, _ := der_item(sequence, offset, 0x30)!
		sequence_start += inner.start
		sequence = sequence[inner.start..inner.end]
		kind, offset = der_item(sequence, 0, 0x16)!
	} else if initial_kind.bytestr() != 'IM4P' {
		return error('not an IM4P or IMG4 container (kind=${bytes_repr(initial_kind)})')
	}
	image_type, next := der_item(sequence, offset, 0x16)!
	_, description_end := der_item(sequence, next, 0x16)!
	payload, _ := der_item(sequence, description_end, 0x04)!
	if sequence[kind.start..kind.end].bytestr() != 'IM4P'
		|| sequence[image_type.start..image_type.end].bytestr() != 'pmpf' {
		return error('not a PMP firmware IM4P (kind=${bytes_repr(sequence[kind.start..kind.end])}, type=${bytes_repr(sequence[image_type.start..image_type.end])})')
	}
	return Span{sequence_start + payload.start, sequence_start + payload.end}
}

pub fn im4p_sequence(blob []u8) !Span {
	outer, end := der_item(blob, 0, 0x30)!
	if end != blob.len { return error('trailing data after DER sequence') }
	sequence := unsafe { blob[outer.start..outer.end] }
	kind, offset := der_item(sequence, 0, 0x16)!
	name := sequence[kind.start..kind.end]
	if name.bytestr() == 'IM4P' { return outer }
	if name.bytestr() != 'IMG4' {
		return error('not an IM4P or IMG4 container (kind=${bytes_repr(name)})')
	}
	inner, _ := der_item(sequence, offset, 0x30)!
	return Span{outer.start + inner.start, outer.start + inner.end}
}

pub fn find_source(preboot string, mode string, platform_name string) !string {
	pattern, description := match mode {
		'firmware' { '*/restore/Firmware/agx', 'G17X recovery firmware directory' }
		'pmp' { '*/restore/Firmware/pmp/t6050pmp.im4p', 'T6050 PMP firmware image' }
		'platform' {
			'*/restore-staged/kernelcache.release.' + platform_name, 'staged ' + platform_name + ' kernel collection'
		}
		else {
			'*/boot/*/System/Library/Caches/com.apple.kernelcaches/kernelcache', 'boot kernel collection'
		}
	}
	mut candidates := []string{}
	for path in os.glob(os.join_path(preboot, pattern)) or { []string{} } {
		if mode == 'firmware' {
			if os.is_file(os.join_path(path, 'armfw_g17x.im4p')) && os.is_file(os.join_path(path, 'armfw1_g17x.im4p')) {
				candidates << path_value(path)
			}
		} else if os.is_file(path) {
			candidates << path_value(path)
		}
	}
	candidates.sort()
	if candidates.len != 1 {
		return error('expected one ${description}, found: ${if candidates.len == 0 {
			'none'
		} else {
			candidates.join(', ')
		}}')
	}
	return candidates[0]
}

// Path objects remove redundant separators and dot components, while keeping
// parent components and the POSIX double-slash root in their original spelling.
pub fn path_value(text string) string {
	root := if text.starts_with('//') && !text.starts_with('///') {
		'//'
	} else if text.starts_with('/') {
		'/'
	} else {
		''
	}
	mut parts := []string{}
	for part in text.split('/') { if part !in ['', '.'] { parts << part } }
	result := root + parts.join('/')
	return if result == '' { '.' } else { result }
}

pub fn select_variant(container string, variant string) !(string, []u8) {
	blob := os.read_bytes(container)!
	span := im4p_payload(blob)!
	payload := unsafe { blob[span.start..span.end] }
	entries := firmware_entries(payload)!
	mut matching := []FirmwareEntry{}
	for entry in entries {
		if image_variant(payload[entry.image.start..entry.image.end])! == variant {
			matching << entry
		}
	}
	if matching.len != 1 {
		mut found := []string{}
		for entry in entries {
			found << image_variant(payload[entry.image.start..entry.image.end])!
		}
		return error('${container}: expected one ${variant} image, found [${found.join(', ')}]')
	}
	entry := matching[0]
	return entry.tag, payload[entry.image.start..entry.image.end].clone()
}

pub struct FirmwareEntry {
pub:
	tag   string
	image Span
}

pub fn firmware_entries(payload []u8) ![]FirmwareEntry {
	table := payload.bytestr().index('rkosftab') or { return error('missing rkosftab firmware table') }
	if table + 16 > payload.len { return error('missing rkosftab firmware table') }
	count := u64_at(payload, table + 8)
	if count == 0 || count > 16 { return error('invalid firmware table entry count ${count}') }
	mut entries := []FirmwareEntry{}
	mut cursor := table + 16
	for _ in 0 .. int(count) {
		if cursor + 16 > payload.len { return error('truncated firmware table') }
		tag := payload[cursor..cursor + 4]
		start := u64(u32_at(payload, cursor + 4))
		size := u64_at(payload, cursor + 8)
		cursor += 16
		if start < u64(cursor) || start > u64(payload.len) || size > u64(payload.len) - start {
			return error('firmware table entry lies outside the IM4P payload')
		}
		image := payload[int(start)..int(start + size)]
		if image.len < 4 || u32_at(image, 0) != macho_magic_64 {
			return error('firmware entry ${bytes_repr(tag)} is not an arm64e Mach-O')
		}
		entries << FirmwareEntry{ascii(tag)!, Span{int(start), int(start + size)}}
	}
	return entries
}

pub fn image_variant(image []u8) !string {
	marker := 'FW Build variant: '
	position := image.bytestr().index(marker) or { return error('firmware image has no build-variant marker') }
	start := position + marker.len
	mut end := start
	for end < image.len && image[end] != 0 { end++ }
	if end == image.len { return error('unterminated firmware build-variant marker') }
	return ascii(image[start..end])
}

fn ascii(data []u8) !string {
	for index, byte in data {
		if byte > 127 {
			return error("'ascii' codec can't decode byte 0x${byte:02x} in position ${index}: ordinal not in range(128)")
		}
	}
	return data.bytestr()
}

pub fn u32_at(data []u8, offset int) u32 {
	return binary.little_endian_u32(data[offset..offset + 4])
}

pub fn u64_at(data []u8, offset int) u64 {
	return binary.little_endian_u64(data[offset..offset + 8])
}

fn set_u32(mut data []u8, offset int, word u32) {
	binary.little_endian_put_u32(mut data[offset..offset + 4], word)
}

fn set_u64(mut data []u8, offset int, word u64) {
	binary.little_endian_put_u64(mut data[offset..offset + 8], word)
}

pub struct LoadCommand {
pub:
	command u32
	offset  int
	size    int
}

pub fn load_commands(image []u8, header_offset int) ![]LoadCommand {
	if header_offset < 0 || header_offset > image.len - 32 {
		return error('truncated Mach-O header')
	}
	if u32_at(image, header_offset) != macho_magic_64 {
		return error('no 64-bit little-endian Mach-O at offset 0x${header_offset:x}')
	}
	count := u32_at(image, header_offset + 16)
	command_bytes := u64(u32_at(image, header_offset + 20))
	mut offset := header_offset + 32
	if command_bytes > u64(image.len - offset) {
		return error('Mach-O load commands extend past the image')
	}
	end := offset + int(command_bytes)
	mut result := []LoadCommand{}
	for _ in 0 .. u64(count) {
		if offset > end - 8 { return error('truncated Mach-O load command') }
		command := u32_at(image, offset)
		size := u64(u32_at(image, offset + 4))
		if size < 8 || size > u64(end - offset) { return error('invalid Mach-O load command size') }
		result << LoadCommand{command, offset, int(size)}
		offset += int(size)
	}
	if offset != end { return error('Mach-O load-command size does not match its header') }
	return result
}

pub struct Segment {
pub:
	command_offset  int
	name            string
	virtual_address u64
	virtual_size    u64
	file_offset     u64
	file_size       u64
	section_count   u32
}

pub fn parse_segment(image []u8, item LoadCommand) !Segment {
	if item.size < 72 { return error('truncated LC_SEGMENT_64') }
	if item.offset < 0 || item.offset > image.len - 72 { return error('truncated LC_SEGMENT_64') }
	raw_name := image[item.offset + 8..item.offset + 24]
	name_end := raw_name.bytestr().index('\x00') or { raw_name.len }
	return Segment{item.offset, ascii(raw_name[..name_end])!, u64_at(image, item.offset + 24), u64_at(image, item.offset + 32), u64_at(image, item.offset + 40), u64_at(image, item.offset + 48), u32_at(image, item.offset + 64)}
}

fn segment_metadata(segment Segment) map[string]j.Value {
	return {
		'name':            j.Value(segment.name)
		'virtual_address': j.Value(segment.virtual_address)
		'virtual_size':    j.Value(segment.virtual_size)
		'file_offset':     j.Value(segment.file_offset)
		'file_size':       j.Value(segment.file_size)
	}
}

fn uuid_text(raw []u8) string {
	text := hex.encode(raw).to_upper()
	return '${text[..imin(8, text.len)]}-${text[imin(8, text.len)..imin(12, text.len)]}-${text[imin(12, text.len)..imin(16, text.len)]}-${text[imin(16, text.len)..imin(20, text.len)]}-${text[imin(20, text.len)..]}'
}

pub fn macho_metadata(image []u8) !map[string]j.Value {
	if image.len < 32 || u32_at(image, 0) != macho_magic_64 {
		return error('firmware image is not a complete 64-bit little-endian Mach-O')
	}
	count := u32_at(image, 16)
	command_bytes := u64(u32_at(image, 20))
	mut offset := 32
	if command_bytes > u64(image.len - offset) {
		return error('Mach-O load commands extend past the firmware image')
	}
	end := offset + int(command_bytes)
	mut uuid := j.Value(json_null())
	mut segments := []j.Value{}
	mut populated := []Segment{}
	for _ in 0 .. u64(count) {
		if offset > end - 8 { return error('truncated Mach-O load command') }
		command := u32_at(image, offset)
		size := u64(u32_at(image, offset + 4))
		if size < 8 || size > u64(end - offset) { return error('invalid Mach-O load command size') }
		if command == lc_uuid {
			if size < 24 { return error('truncated Mach-O UUID command') }
			uuid = j.Value(uuid_text(image[offset + 8..offset + 24]))
		} else if command == lc_segment_64 {
			if size < 72 { return error('truncated Mach-O segment command') }
			segment := parse_segment(image, LoadCommand{command, offset, int(size)})!
			segments << j.Value(segment_metadata(segment))
			if segment.virtual_size != 0 { populated << segment }
		}
		offset += int(size)
	}
	if offset != end { return error('Mach-O load-command size does not match its header') }
	mut virtual_start := u64(0)
	mut virtual_end := big.zero_int
	for index, segment in populated {
		if index == 0 || segment.virtual_address < virtual_start {
			virtual_start = segment.virtual_address
		}
		last := big.integer_from_u64(segment.virtual_address) + big.integer_from_u64(segment.virtual_size)
		if last > virtual_end { virtual_end = last }
	}
	return {
		'cpu_type':              j.Value(i64(i32(u32_at(image, 4))))
		'cpu_subtype':           j.Value(i64(i32(u32_at(image, 8))))
		'file_type':             j.Value(u32_at(image, 12))
		'uuid':                  uuid
		'virtual_address_start': j.Value(virtual_start)
		'virtual_address_end':   j.Value(j.Number{virtual_end.str()})
		'segments':              j.Value(segments)
	}
}

fn json_null() j.Value { return j.decode('null') or { panic(err) } }

pub fn macho_identity(image []u8) !map[string]j.Value {
	mut uuid := json_null()
	mut symbol_count := u32(0)
	mut segments := []j.Value{}
	for item in load_commands(image, 0)! {
		if item.command == lc_uuid {
			uuid = j.Value(uuid_text(image[item.offset + 8..imin(item.offset + 24, image.len)]))
		} else if item.command == lc_symtab {
			if item.offset > image.len - 16 {
				return error('truncated Mach-O symbol-table command')
			}
			symbol_count = u32_at(image, item.offset + 12)
		} else if item.command == lc_segment_64 {
			segments << j.Value(segment_metadata(parse_segment(image, item)!))
		}
	}
	return {
		'uuid':         uuid
		'symbol_count': j.Value(symbol_count)
		'segments':     j.Value(segments)
	}
}

pub struct Entry {
pub:
	virtual_address u64
	file_offset     u64
}

pub fn fileset_entries(collection []u8) !map[string]Entry {
	mut entries := map[string]Entry{}
	for item in load_commands(collection, 0)! {
		if item.command != lc_fileset_entry { continue }
		if item.size < 32 { return error('truncated LC_FILESET_ENTRY') }
		name_offset := u32_at(collection, item.offset + 24)
		if name_offset < 32 || u64(name_offset) >= u64(item.size) {
			return error('invalid LC_FILESET_ENTRY name offset')
		}
		start := item.offset + int(name_offset)
		mut end := start
		for end < item.offset + item.size && collection[end] != 0 { end++ }
		if end == item.offset + item.size { return error('unterminated LC_FILESET_ENTRY name') }
		name := collection[start..end].bytestr()
		if !utf8.validate_str(name) { return error(utf8_error(collection[start..end])) }
		if name in entries { return error('duplicate fileset entry ${name}') }
		entries[name] = Entry{u64_at(collection, item.offset + 8), u64_at(collection, item.offset + 16)}
	}
	return entries
}

fn utf8_error(data []u8) string {
	mut position := 0
	for position < data.len {
		first := data[position]
		if first < 0x80 {
			position++
			continue
		}
		count := if first >= 0xc2 && first <= 0xdf {
			2
		} else if first >= 0xe0 && first <= 0xef {
			3
		} else if first >= 0xf0 && first <= 0xf4 {
			4
		} else {
			0
		}
		if count == 0 { return utf8_message(data, position, position + 1, 'invalid start byte') }
		for continuation in 1 .. count {
			if position + continuation >= data.len {
				return utf8_message(data, position, data.len, 'unexpected end of data')
			}
			byte := data[position + continuation]
			if byte < 0x80 || byte > 0xbf || (continuation == 1 && ((first == 0xe0 && byte < 0xa0) || (first == 0xed && byte >= 0xa0)
				|| (first == 0xf0 && byte < 0x90) || (first == 0xf4 && byte >= 0x90))) {
				return utf8_message(data, position, position + continuation, 'invalid continuation byte')
			}
		}
		position += count
	}
	return 'invalid UTF-8 fileset entry name'
}

fn utf8_message(data []u8, start int, end int, reason string) string {
	if end == start + 1 {
		return "'utf-8' codec can't decode byte 0x${data[start]:02x} in position ${start}: ${reason}"
	}
	return "'utf-8' codec can't decode bytes in position ${start}-${end - 1}: ${reason}"
}

pub fn align_up(value int, alignment int) int { return (value + alignment - 1) & -alignment }

fn rebase_linkedit_offset(mut image []u8, offset int, delta i64) ! {
	if offset < 0 || offset > image.len - 4 { return error('truncated Mach-O linkedit command') }
	old := u32_at(image, offset)
	if old == 0 { return }
	new := i64(old) + delta
	if new < 0 || new > 0xffffffff {
		return error('rebased Mach-O linkedit offset exceeds 32 bits')
	}
	set_u32(mut image, offset, u32(new))
}

pub fn extract_entry(collection []u8, entry_offset int) ![]u8 {
	commands := load_commands(collection, entry_offset)!
	mut segments := []Segment{}
	for item in commands {
		if item.command == lc_segment_64 { segments << parse_segment(collection, item)! }
	}
	if segments.len == 0 || segments[0].file_offset != u64(entry_offset) {
		return error('fileset entry does not begin in its first segment')
	}
	for segment in segments {
		if segment.file_offset > u64(collection.len) || segment.file_size > u64(collection.len) - segment.file_offset {
			return error('segment ${segment.name} extends past the kernel collection')
		}
	}
	mut placements := map[int]int{}
	mut cursor := 0
	for index, segment in segments {
		if segment.file_size == 0 {
			placements[segment.command_offset] = 0
			continue
		}
		if cursor > max_int - 0x4000 {
			return error('compacted Mach-O exceeds the host array size')
		}
		new_offset := if index == 0 { 0 } else { align_up(cursor, 0x4000) }
		if segment.file_size > u64(max_int - new_offset) {
			return error('compacted Mach-O exceeds the host array size')
		}
		placements[segment.command_offset] = new_offset
		cursor = new_offset + int(segment.file_size)
	}
	mut output := []u8{len: cursor}
	for segment in segments {
		if segment.file_size == 0 { continue }
		destination := placements[segment.command_offset]
		for index in 0 .. int(segment.file_size) {
			output[destination + index] = collection[int(segment.file_offset) + index]
		}
	}
	header_size := 32 + int(u32_at(collection, entry_offset + 20))
	mut header := collection[entry_offset..entry_offset + header_size].clone()
	header_commands := load_commands(header, 0)!
	mut copied_segments := []Segment{}
	for item in header_commands {
		if item.command == lc_segment_64 { copied_segments << parse_segment(header, item)! }
	}
	if copied_segments.len != segments.len {
		return error('copied Mach-O header changed its segment count')
	}
	mut has_linkedit := false
	mut delta := i64(0)
	for index, old in segments {
		new := copied_segments[index]
		new_file_offset := placements[old.command_offset]
		set_u64(mut header, new.command_offset + 40, u64(new_file_offset))
		mut command_size := 0
		for item in header_commands {
			if item.offset == new.command_offset {
				command_size = item.size
				break
			}
		}
		for section_index in 0 .. u64(new.section_count) {
			section := u64(new.command_offset + 72) + section_index * 80
			if section + 80 > u64(new.command_offset + command_size) {
				return error('segment ${new.name} has truncated section commands')
			}
			section_size := u64_at(header, int(section) + 40)
			old_section_offset := u64(u32_at(header, int(section) + 48))
			if section_size == 0 {
				set_u32(mut header, int(section) + 48, 0)
			} else if old_section_offset >= old.file_offset && old_section_offset - old.file_offset < old.file_size {
				new_offset := u64(new_file_offset) + old_section_offset - old.file_offset
				if new_offset > 0xffffffff {
					return error('rebased Mach-O section offset exceeds 32 bits')
				}
				set_u32(mut header, int(section) + 48, u32(new_offset))
			}
		}
		if old.name == '__LINKEDIT' {
			has_linkedit = true
			delta = i64(new_file_offset) - i64(old.file_offset)
		}
	}
	if !has_linkedit { return error('fileset entry has no __LINKEDIT segment') }
	for item in header_commands {
		if item.command == lc_symtab {
			rebase_linkedit_offset(mut header, item.offset + 8, delta)!
			rebase_linkedit_offset(mut header, item.offset + 16, delta)!
		} else if item.command == lc_dysymtab {
			for field in [32, 40, 48, 56, 64, 72] {
				rebase_linkedit_offset(mut header, item.offset + field, delta)!
			}
		} else if item.command == lc_function_starts {
			rebase_linkedit_offset(mut header, item.offset + 8, delta)!
		}
	}
	// Python's bytearray prefix assignment can extend a truncated first segment.
	if header.len > output.len { output << []u8{len: header.len - output.len} }
	for index, byte in header { output[index] = byte }
	return output
}

pub fn pmp_command_summary(image []u8) !map[string]j.Value {
	if image.len < 32 || u32_at(image, 0) != macho_magic_64 {
		return error('PMP payload is not a complete 64-bit little-endian Mach-O')
	}
	cpu := i32(u32_at(image, 4))
	if cpu != 0x0100000c { return error('PMP Mach-O has unexpected CPU type ${signed_hex(cpu)}') }
	file_type := u32_at(image, 12)
	if file_type != 5 { return error('PMP Mach-O is not MH_PRELOAD (type=${file_type})') }
	mut cursor := 32
	command_bytes := u64(u32_at(image, 20))
	if command_bytes > u64(image.len - cursor) {
		return error('Mach-O load commands extend past the PMP payload')
	}
	end := cursor + int(command_bytes)
	mut command_ids := []j.Value{}
	mut symbol_count := u32(0)
	mut has_function_starts := false
	for _ in 0 .. u64(u32_at(image, 16)) {
		if cursor > end - 8 { return error('truncated PMP Mach-O load command') }
		command := u32_at(image, cursor)
		size := u64(u32_at(image, cursor + 4))
		if size < 8 || size > u64(end - cursor) {
			return error('invalid PMP Mach-O load command size')
		}
		command_ids << j.Value(command)
		if command == lc_symtab {
			if size < 24 { return error('truncated PMP symbol-table command') }
			symbol_count = u32_at(image, cursor + 12)
		} else if command == lc_function_starts {
			if size < 16 { return error('truncated PMP function-starts command') }
			has_function_starts = true
		}
		cursor += int(size)
	}
	if cursor != end { return error('PMP Mach-O load-command size does not match its header') }
	return {
		'load_commands':       j.Value(command_ids)
		'symbol_count':        j.Value(symbol_count)
		'has_function_starts': j.Value(has_function_starts)
	}
}

fn signed_hex(word i32) string {
	if word < 0 { return '-0x${-i64(word):x}' }
	return '0x${word:x}'
}

fn imin(a int, b int) int { return if a < b { a } else { b } }

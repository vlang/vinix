module t6050power

import math.big
import strconv
import traceanalysis as j

const t6050_pmp_image_id_uuid = 'ed70ac9090873857b454318e50a9223f'

struct ProtectedSegment {
	name         string
	virtual      u64
	virtual_size u64
	file_offset  u64
	file_size    u64
	writable     bool
}

fn patch_lookup(value j.Value, key string) !j.Value {
	match value {
		map[string]j.Value { return value[key] or { return error('KeyError: ' + key) } }
		string { return error('TypeError: string indices must be integers') }
		[]j.Value { return error('TypeError: list indices must be integers or slices, not str') }
		else { return error("TypeError: '${patch_type(value)}' object is not subscriptable") }
	}
}

fn patch_type(value j.Value) string {
	return match value {
		bool { 'bool' }
		int, i64, u8, u32, u64 { 'int' }
		j.Number {
			if value.text.contains_any('.eE') { 'float' } else { 'int' }
		}
		string { 'str' }
		[]j.Value { 'list' }
		map[string]j.Value { 'dict' }
		else { 'NoneType' }
	}
}

fn patch_integer(value j.Value) !big.Integer {
	if patch_type(value) !in ['int', 'bool'] {
		if patch_type(value) == 'float' {
			return error('TypeError: integer argument expected, got float')
		}
		return error("TypeError: '${patch_type(value)}' object cannot be interpreted as an integer")
	}
	return exact_integer(value) or { return error('TypeError: integer argument expected') }
}

fn patch_unpack(data []u8, offset big.Integer, size int) !int {
	minimum := big.integer_from_string('-9223372036854775808')!
	maximum := big.integer_from_string('9223372036854775807')!
	if offset < minimum || offset > maximum {
		return error('OverflowError: Python int too large to convert to C ssize_t')
	}
	position := if offset.signum < 0 { big.integer_from_int(data.len) + offset } else { offset }
	if position.signum < 0 {
		return error('struct.error: offset ${offset} out of range for ${data.len}-byte buffer')
	}
	if position + big.integer_from_int(size) > big.integer_from_int(data.len) {
		if offset.signum < 0 {
			return error('struct.error: not enough data to unpack ${size} bytes at offset ${offset}')
		}
		return error('struct.error: unpack_from requires a buffer of at least ${position + big.integer_from_int(size)} bytes for unpacking ${size} bytes at offset ${offset} (actual buffer size is ${data.len})')
	}
	return strconv.atoi(position.str())!
}

fn patch_u64(data []u8, offset int) u64 {
	return u64(word_at(data, offset)) | (u64(word_at(data, offset + 4)) << 32)
}

fn segment_name(data []u8) !string {
	mut length := data.len
	for length > 0 && data[length - 1] == 0 { length-- }
	for index in 0 .. length {
		if data[index] >= 128 {
			return error('UnicodeDecodeError: ' + j.encode(j.Value(map[string]j.Value{
				'encoding': j.Value('ascii')
				'object':   j.Value(data[..length].hex())
				'start':    j.Value(index)
				'end':      j.Value(index + 1)
				'reason':   j.Value('ordinal not in range(128)')
			}), false))
		}
	}
	return data[..length].bytestr()
}

pub fn protected_segments(image []u8) ![]ProtectedSegment {
	if image.len < 32 { return error('truncated Mach-O header') }
	count := word_at(image, 16)
	mut offset := 32
	mut segments := []ProtectedSegment{}
	for _ in 0 .. count {
		patch_unpack(image, big.integer_from_int(offset), 8)!
		command := word_at(image, offset)
		size := word_at(image, offset + 4)
		if size < 8 || u64(offset) + size > u64(image.len) {
			return error('malformed Mach-O load command')
		}
		if command == 0x19 {
			name := segment_name(bytes_slice(image, offset + 8, offset + 24))!
			patch_unpack(image, big.integer_from_int(offset + 24), 32)!
			virtual := patch_u64(image, offset + 24)
			virtual_size := patch_u64(image, offset + 32)
			file_offset := patch_u64(image, offset + 40)
			file_size := patch_u64(image, offset + 48)
			patch_unpack(image, big.integer_from_int(offset + 56), 8)!
			segments << ProtectedSegment{name, virtual, virtual_size, file_offset, file_size, word_at(image, offset + 60) & 2 != 0}
		}
		offset += int(size)
	}
	if segments.len == 0 { return error('Mach-O has no segments') }
	return segments
}

fn protected_segment_rows(segments []ProtectedSegment) j.Value {
	return j.Value(segments.map(j.Value(map[string]j.Value{
		'name':            j.Value(it.name)
		'virtual_address': j.Value(it.virtual)
		'virtual_size':    j.Value(it.virtual_size)
		'file_offset':     j.Value(it.file_offset)
		'file_size':       j.Value(it.file_size)
		'writable':        j.Value(it.writable)
	})))
}

fn patch_slice_index(value big.Integer, length int) int {
	position := if value.signum < 0 { big.integer_from_int(length) + value } else { value }
	if position.signum < 0 { return 0 }
	if position > big.integer_from_int(length) { return length }
	return strconv.atoi(position.str()) or { 0 }
}

// The virtual extent can exceed u64. Do arithmetic before narrowing physical
// offsets; Python slices clamp even file offsets beyond the actual image.
fn patch_read(image []u8, segments []ProtectedSegment, address big.Integer, size big.Integer) ?[]u8 {
	for segment in segments {
		start := big.integer_from_u64(segment.virtual)
		if start <= address && address + size <= start + big.integer_from_u64(segment.file_size) {
			offset := big.integer_from_u64(segment.file_offset) + address - start
			low := patch_slice_index(offset, image.len)
			high := patch_slice_index(offset + size, image.len)
			return image[low..if high < low { low } else { high }].clone()
		}
	}
	return none
}

fn ascii_patch_tag(tag u32, little_endian bool) string {
	mut result := ''
	for index in 0 .. 4 {
		shift := if little_endian { index * 8 } else { (3 - index) * 8 }
		byte := u8(tag >> shift)
		result += if byte < 128 { [byte].bytestr() } else { '�' }
	}
	return result
}

fn patch_float(value j.Value) f64 {
	if value is bool { return if value { 1.0 } else { 0.0 } }
	text := if value is j.Number { value.text } else { j.string_value(value) }
	return unsafe { C.strtod(&char(text.str), nil) }
}

fn patch_add(first j.Value, second j.Value) !j.Value {
	if patch_type(second) !in ['int', 'bool', 'float'] {
		return error("TypeError: unsupported operand type(s) for +: '${patch_type(first)}' and '${patch_type(second)}'")
	}
	if patch_type(first) == 'float' || patch_type(second) == 'float' {
		return j.Value(j.Number{(patch_float(first) + patch_float(second)).str()})
	}
	return j.Value(j.Number{(patch_integer(first)! + patch_integer(second)!).str()})
}

fn patch_le(first j.Value, second j.Value) bool {
	left := exact_integer(first) or { return patch_float(first) <= patch_float(second) }
	right := exact_integer(second) or { return patch_float(first) <= patch_float(second) }
	return left <= right
}

struct IdentityBytes {
	found bool
	data  []u8
}

fn patch_identity_read(image []u8, segments []ProtectedSegment, address j.Value, size j.Value) !IdentityBytes {
	for segment in segments {
		if patch_le(j.Value(segment.virtual), address) {
			end := patch_add(address, size)!
			mapped_end := j.Value(j.Number{(big.integer_from_u64(segment.virtual) + big.integer_from_u64(segment.file_size)).str()})
			if patch_le(end, mapped_end) {
				if patch_type(address) == 'float' || patch_type(size) == 'float' {
					return error('TypeError: slice indices must be integers or None or have an __index__ method')
				}
				bytes := patch_read(image, [segment], patch_integer(address)!, patch_integer(size)!) or { return IdentityBytes{} }
				return IdentityBytes{true, bytes}
			}
		}
	}
	return IdentityBytes{}
}

fn patch_hex(value j.Value) !string {
	if patch_type(value) == 'float' {
		return error("Unknown format code 'x' for object of type 'float'")
	}
	number := patch_integer(value)!
	return if number.signum < 0 { '-0x' + number.abs().hex() } else { '0x' + number.hex() }
}

struct IdentityMatch {
	candidate j.Value
	version   u32
	block     []u8
}

pub fn recover_pmp_patchbay(image []u8, contract j.Value) !map[string]j.Value {
	identity := patch_lookup(contract, 'identity_block')!
	record := patch_lookup(contract, 'record')!
	segments := protected_segments(image)!
	mut base := segments[0].virtual
	for segment in segments { if segment.virtual < base { base = segment.virtual } }
	base_integer := big.integer_from_u64(base)
	candidates := patch_lookup(identity, 'candidate_iop_offsets')!
	mut candidate_values := []j.Value{}
	match candidates {
		[]j.Value { candidate_values = candidates.clone() }
		string { candidate_values = candidates.runes().map(j.Value(it.str())) }
		map[string]j.Value { candidate_values = candidates.keys().map(j.Value(it)) }
		else { return error("TypeError: '${patch_type(candidates)}' object is not iterable") }
	}
	mut matches := []IdentityMatch{}
	for candidate in candidate_values {
		address := patch_add(j.Value(base), candidate)!
		size := patch_lookup(identity, 'size')!
		read := patch_identity_read(image, segments, address, size)!
		if !read.found { continue }
		block := read.data
		patch_unpack(block, big.zero_int, 8)!
		magic := word_at(block, 0)
		version := word_at(block, 4)
		if !integer_equal(j.Value(magic), patch_lookup(identity, 'magic')!) || version & ~u32(1) != 4 {
			continue
		}
		matches << IdentityMatch{candidate, version, block}
	}
	if matches.len != 1 {
		return error('t6050pmp identity block is ambiguous or absent: ${j.string_value(j.Value(matches.map(it.candidate)))}')
	}
	match_spec := matches[0]
	block := match_spec.block
	uuid := bytes_slice(block, 0x10, 0x20).hex()
	if uuid != t6050_pmp_image_id_uuid { return error('t6050pmp image identity changed: ${uuid}') }
	fields := patch_lookup(patch_lookup(identity, 'patchbay_fields')!, match_spec.version.str())!
	patch_offset_at := patch_unpack(block, patch_integer(patch_lookup(fields, 'offset')!)!, 4)!
	patch_offset := word_at(block, patch_offset_at)
	patch_size_at := patch_unpack(block, patch_integer(patch_lookup(fields, 'size')!)!, 4)!
	patch_size := word_at(block, patch_size_at)
	unaligned := base_integer + big.integer_from_u64(patch_offset)
	pad := (unaligned % big.integer_from_int(4)).int()
	aligned := unaligned - big.integer_from_int(pad)
	padded_size := (u64(pad) + patch_size + 3) & ~u64(3)
	mut owner := -1
	for index, segment in segments {
		start := big.integer_from_u64(segment.virtual)
		if start <= aligned && aligned < start + big.integer_from_u64(segment.file_size) {
			owner = index
			break
		}
	}
	if owner < 0 { return error('t6050pmp patchbay is outside every mapped segment') }
	blob := patch_read(image, segments, aligned, big.integer_from_u64(padded_size)) or { return error('t6050pmp patchbay extends past its segment') }
	header := patch_lookup(record, 'header_bytes')!
	mut cursor := j.Value(pad)
	end := j.Value(u64(pad) + patch_size)
	mut records := []j.Value{}
	for patch_le(patch_add(cursor, header)!, end) {
		position := patch_unpack(blob, patch_integer(cursor)!, 8)!
		tag := word_at(blob, position)
		length := word_at(blob, position + 4)
		finish := patch_add(patch_add(cursor, header)!, j.Value(length))!
		if !patch_le(finish, end) {
			return error('t6050pmp patchbay record at ${patch_hex(cursor)!} overruns')
		}
		records << j.Value(map[string]j.Value{
			'offset':       j.Value(j.Number{(patch_integer(cursor)! - big.integer_from_int(pad)).str()})
			'tag':          j.Value(ascii_patch_tag(tag, false))
			'stored_bytes': j.Value(ascii_patch_tag(tag, true))
			'value_bytes':  j.Value(length)
		})
		cursor = finish
	}
	if !integer_equal(cursor, end) {
		consumed := patch_add(cursor, j.Value(-pad))!
		return error('t6050pmp patchbay records do not tile its region: ${patch_hex(consumed)!} != 0x${patch_size:x}')
	}
	mut by_tag := map[string]j.Value{}
	for entry in records { by_tag[j.string_value(j.value(entry.as_map(), 'tag'))] = entry }
	if by_tag.len != records.len { return error('t6050pmp patchbay repeats a tag') }
	mandatory := mandatory_patch_metadata().map(j.value(it.as_map(), 'tag'))
	for tag in mandatory {
		name := j.string_value(tag)
		entry := by_tag[name] or { return error('t6050pmp patchbay is missing mandatory tag ${name}') }
		length := j.value(entry.as_map(), 'value_bytes').u64()
		if length != 4 {
			return error('t6050pmp patchbay tag ${name} is not a 32-bit value: ${length}')
		}
	}
	return {
		'image_uuid':             j.Value(t6050_pmp_image_id_uuid)
		'iop_virtual_base':       j.Value(base)
		'identity_block':         j.Value(map[string]j.Value{
			'candidate_offset': match_spec.candidate
			'iop_virtual':      j.Value(j.Number{(base_integer + patch_integer(match_spec.candidate)!).str()})
			'version':          j.Value(match_spec.version)
		})
		'region':                 j.Value(map[string]j.Value{
			'offset':      j.Value(patch_offset)
			'iop_virtual': j.Value(j.Number{aligned.str()})
			'align_pad':   j.Value(pad)
			'size':        j.Value(patch_size)
			'padded_size': j.Value(padded_size)
			'segment':     j.Value(segments[owner].name)
			'writable':    j.Value(segments[owner].writable)
		})
		'record_count':           j.Value(records.len)
		'mandatory_tags_present': j.Value(mandatory)
		'records':                j.Value(records)
	}
}

pub fn query_patchbay(image []u8, operation string, request map[string]j.Value) !j.Value {
	if operation == '_macho_segment_table' {
		return protected_segment_rows(protected_segments(image)!)
	}
	return j.Value(recover_pmp_patchbay(image, j.value(request, 'contract'))!)
}

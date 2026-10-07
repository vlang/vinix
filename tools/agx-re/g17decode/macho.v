module g17decode

import encoding.hex
import imageextract as image
import math.big
import traceanalysis as j

pub const kernel_collection_base = u64(0xfffffe0007004000)
pub const driver_uuid = '680ACC23-AB13-301C-B28A-3A2A257F7977'
pub const init_power_data = '__ZN14AGXArmFirmware27initPowerAndPerformanceDataEv'

// Match UTF-8's maximal valid prefix consumption used by Python's replacement
// decoder. An invalid continuation remains available for its own next decode.
pub fn utf8_replace(data []u8) string {
	mut output := []u8{cap: data.len}
	mut index := 0
	for index < data.len {
		lead := data[index]
		if lead < 128 {
			output << lead
			index++
			continue
		}
		count := if lead >= 0xc2 && lead <= 0xdf {
			2
		} else if lead >= 0xe0 && lead <= 0xef {
			3
		} else if lead >= 0xf0 && lead <= 0xf4 {
			4
		} else {
			0
		}
		if count == 0 {
			output << [u8(0xef), 0xbf, 0xbd]
			index++
			continue
		}
		mut consumed := 1
		for consumed < count && index + consumed < data.len {
			byte := data[index + consumed]
			if byte < 0x80 || byte > 0xbf { break }
			if consumed == 1 && ((lead == 0xe0 && byte < 0xa0) || (lead == 0xed && byte >= 0xa0) || (lead == 0xf0 && byte < 0x90) || (lead == 0xf4 && byte >= 0x90)) {
				break
			}
			consumed++
		}
		if consumed == count {
			output << data[index..index + count]
		} else {
			output << [u8(0xef), 0xbf, 0xbd]
		}
		index += consumed
	}
	return output.bytestr()
}

pub fn macho_uuid(data []u8) !j.Value {
	for command in image.load_commands(data, 0)! {
		if command.command != image.lc_uuid { continue }
		if command.size < 24 { return error('truncated LC_UUID') }
		text := hex.encode(data[command.offset + 8..command.offset + 24]).to_upper()
		return j.Value('${text[..8]}-${text[8..12]}-${text[12..16]}-${text[16..20]}-${text[20..]}')
	}
	return missing()
}

pub fn macho_symbols(data []u8) !map[string]u64 {
	mut result := map[string]u64{}
	for command in image.load_commands(data, 0)! {
		if command.command != image.lc_symtab { continue }
		if command.size < 24 { return error('truncated LC_SYMTAB') }
		symbol_offset := u64(image.u32_at(data, command.offset + 8))
		count := u64(image.u32_at(data, command.offset + 12))
		string_offset := u64(image.u32_at(data, command.offset + 16))
		string_size := u64(image.u32_at(data, command.offset + 20))
		if symbol_offset + count * 16 > u64(data.len) {
			return error('Mach-O symbol table extends past the image')
		}
		if string_offset + string_size > u64(data.len) {
			return error('Mach-O string table extends past the image')
		}
		string_end := int(string_offset + string_size)
		for index in 0 .. count {
			entry := int(symbol_offset + index * 16)
			name_offset := u64(image.u32_at(data, entry))
			if name_offset == 0 || name_offset >= string_size { continue }
			start := int(string_offset + name_offset)
			mut end := start
			for end < string_end && data[end] != 0 { end++ }
			if end == string_end { return error('unterminated Mach-O symbol name') }
			result[utf8_replace(data[start..end])] = image.u64_at(data, entry + 8)
		}
		return result
	}
	return error('Mach-O has no symbol table')
}

pub fn virtual_to_file(data []u8, address big.Integer) !big.Integer {
	for command in image.load_commands(data, 0)! {
		if command.command != image.lc_segment_64 { continue }
		segment := image.parse_segment(data, command)!
		start := big.integer_from_u64(segment.virtual_address)
		if start <= address && address < start + big.integer_from_u64(segment.file_size) {
			return big.integer_from_u64(segment.file_offset) + address - start
		}
	}
	return error('virtual address ${hex_integer(address)} is not backed by a Mach-O segment')
}

fn hex_integer(value big.Integer) string {
	return if value.signum < 0 { '-0x' + value.abs().hex() } else { '0x' + value.hex() }
}

fn clipped(value big.Integer, length int) int {
	if value.signum <= 0 { return 0 }
	if value >= big.integer_from_int(length) { return length }
	return int(wide_mask(value))
}

pub fn symbol_code_span(data []u8, name string) !(u64, image.Span) {
	symbols := macho_symbols(data)!
	if name !in symbols { return error('Mach-O has no ${name} symbol') }
	address := symbols[name]
	offset := virtual_to_file(data, big.integer_from_u64(address))!
	mut following := []u64{}
	for _, value in symbols { if value > address { following << value } }
	following.sort()
	end_address := if following.len > 0 {
		big.integer_from_u64(following[0])
	} else {
		big.integer_from_u64(address) + big.integer_from_int(65536)
	}
	end := virtual_to_file(data, end_address - big.one_int) or { big.integer_from_int(data.len) - big.one_int }
	mut finish := end + big.one_int
	// The original fallback caps the default 64 KiB probe even if no segment
	// backs the proposed end, independently of the nearest symbol's distance.
	if _ := virtual_to_file(data, end_address - big.one_int) {
	} else {
		cap_end := offset + big.integer_from_int(65536)
		if finish > cap_end { finish = cap_end }
	}
	start := clipped(offset, data.len)
	mut stop := clipped(finish, data.len)
	if stop < start { stop = start }
	return address, image.Span{start, stop}
}

pub fn symbol_code(data []u8, name string) !(u64, []u8) {
	address, span := symbol_code_span(data, name)!
	return address, data[span.start..span.end].clone()
}

fn word_at(code []u8, offset int) !u32 {
	if offset < 0 && offset > -4 {
		return error('struct.error: not enough data to unpack 4 bytes at offset ${offset}')
	}
	position := if offset < 0 { code.len + offset } else { offset }
	if position < 0 {
		return error('struct.error: offset ${offset} out of range for ${code.len}-byte buffer')
	}
	if position > code.len - 4 {
		return error('struct.error: unpack_from requires a buffer of at least ${position + 4} bytes for unpacking 4 bytes at offset ${offset} (actual buffer size is ${code.len})')
	}
	return image.u32_at(code, position)
}

pub fn read_adrp_add_address(function_address j.Value, code []u8, adrp_offset int, add_offset int) !u64 {
	if adrp_offset > code.len - 4 || add_offset > code.len - 4 {
		return error('truncated PC-relative address reference')
	}
	address := add_address(function_address, i64(adrp_offset), false)
	page_word := word_at(code, adrp_offset)!
	add_word := word_at(code, add_offset)!
	page := fields_address('decode_adrp', page_word, address) or { return error('invalid PC-relative address reference') }
	add := fields('decode_add_immediate', add_word) or { return error('invalid PC-relative address reference') }
	if page[0].int() != add[1].int() { return error('invalid PC-relative address reference') }
	return page[1].u64() + add[2].u64()
}

fn fields_address(name string, word u32, address j.Value) ?[]j.Value {
	value := decode(name, word, address)
	if value is []j.Value { return value }
	return none
}

pub fn read_adrp_add_cstring(data []u8, function_address j.Value, code []u8, adrp_offset int, add_offset int) !string {
	address := read_adrp_add_address(function_address, code, adrp_offset, add_offset)!
	start := virtual_to_file(data, big.integer_from_u64(address))!
	if start >= big.integer_from_int(data.len) { return error('unterminated PC-relative C string') }
	offset := clipped(start, data.len)
	mut end := offset
	for end < data.len && data[end] != 0 { end++ }
	if end == data.len { return error('unterminated PC-relative C string') }
	return utf8_replace(data[offset..end])
}

pub fn read_virtual_u32_table(data []u8, address big.Integer, count big.Integer) ![]u32 {
	if count.signum < 0 { return error('negative virtual table element count') }
	offset := virtual_to_file(data, address)!
	if offset + count * big.integer_from_int(4) > big.integer_from_int(data.len) {
		return error('truncated virtual u32 table')
	}
	mut result := []u32{}
	for index := 0; index < int(wide_mask(count)); index++ {
		result << image.u32_at(data, int(wide_mask(offset)) + index * 4)
	}
	return result
}

pub fn read_adrp_load(data []u8, function_address j.Value, code []u8, adrp_offset int, load_offset int, expected_width int) !image.Span {
	if adrp_offset < 0 || load_offset < 0 || adrp_offset > code.len - 4 || load_offset > code.len - 4 {
		return error('PC-relative load is outside its function')
	}
	page := fields_address('decode_adrp', word_at(code, adrp_offset)!, add_address(function_address, i64(adrp_offset), false)) or { return error('expected ADRP/load pair was not found') }
	load := fields('decode_load_unsigned', word_at(code, load_offset)!) or { return error('expected ADRP/load pair was not found') }
	if load[1].int() != page[0].int() || load[3].int() != expected_width {
		return error('unexpected PC-relative load shape')
	}
	address := big.integer_from_u64(page[1].u64()) + big.integer_from_u64(load[2].u64())
	offset := virtual_to_file(data, address)!
	return image.Span{clipped(offset, data.len), clipped(offset + big.integer_from_int(expected_width), data.len)}
}

pub fn decode_kernel_auth_rebase(raw j.Value) !u64 {
	value := integer(raw)!
	bits := wide_mask(value)
	if bits & 0xc000000000000000 != 0x8000000000000000 {
		return error('not an authenticated kernel rebase: ${hex_integer(value)}')
	}
	return kernel_collection_base + (bits & 0xffffffff)
}

pub fn recover_vtable_target(data []u8, name string, slot big.Integer) !u64 {
	symbols := macho_symbols(data)!
	if name !in symbols { return error('Mach-O has no ${name} symbol') }
	address := big.integer_from_u64(symbols[name]) + big.integer_from_int(16) + slot
	offset := virtual_to_file(data, address)!
	if offset + big.integer_from_int(8) > big.integer_from_int(data.len) {
		return error('truncated ${name} entry at slot ${hex_integer(slot)}')
	}
	return decode_kernel_auth_rebase(j.Value(image.u64_at(data, int(wide_mask(offset)))))!
}

pub fn require_instruction_sequence(code []u8, label string, sequence []u32) ! {
	mut encoded := []u8{cap: sequence.len * 4}
	for word in sequence { encoded << [u8(word), u8(word >> 8), u8(word >> 16), u8(word >> 24)] }
	if encoded.len == 0 { return }
	for offset := 0; offset <= code.len - encoded.len; offset++ {
		if code[offset..offset + encoded.len] == encoded { return }
	}
	return error('missing ${label} instruction sequence')
}

pub fn require_instruction_words_at(code []u8, label string, expected map[int]u32) ! {
	for offset, wanted in expected {
		if offset > code.len - 4 {
			return error('truncated ${label} at ${hex_integer(big.integer_from_int(offset))}')
		}
		actual := word_at(code, offset)!
		if actual != wanted {
			return error('unexpected ${label} instruction at ${hex_integer(big.integer_from_int(offset))}: 0x${actual:08x}, expected 0x${wanted:08x}')
		}
	}
}

pub fn find_authenticated_target_references(data []u8, target j.Value) []int {
	mut result := []int{}
	for offset := 0; offset <= data.len - 8; offset += 8 {
		decoded := decode_kernel_auth_rebase(j.Value(image.u64_at(data, offset))) or { continue }
		if equal_integer(decoded, target) { result << offset }
	}
	return result
}

module androidhost

pub struct AsciiError {
	bytes []u8
	start int
}

pub fn (e AsciiError) msg() string { return 'ordinal not in range(128)' }

pub fn (e AsciiError) code() int { return 0 }

pub struct DexInfo {
pub:
	classes   []string
	callsites u64
}

fn dex_u32(data []u8, offset u64) !u32 {
	if offset > u64(data.len) || 4 > u64(data.len) - offset {
		return error('truncated bootclasspath DEX table')
	}
	return elf_u32(data, int(offset))
}

pub fn dex_info(data []u8) !DexInfo {
	if data.len < 112 || data[..4] != 'dex\n'.bytes() || data[7] != 0 {
		return error('invalid bootclasspath DEX header')
	}
	if dex_u32(data, 32)! != u64(data.len) || dex_u32(data, 36)! != 112 || dex_u32(data, 40)! != 0x12345678 {
		return error('unsupported bootclasspath DEX layout')
	}
	strings := u64(dex_u32(data, 56)!)
	string_offset := u64(dex_u32(data, 60)!)
	types := u64(dex_u32(data, 64)!)
	type_offset := u64(dex_u32(data, 68)!)
	classes := u64(dex_u32(data, 96)!)
	class_offset := u64(dex_u32(data, 100)!)
	if string_offset + strings * 4 > u64(data.len) || type_offset + types * 4 > u64(data.len) || class_offset + classes * 32 > u64(data.len) {
		return error('truncated bootclasspath DEX tables')
	}
	mut names := map[string]bool{}
	for index := u64(0); index < classes; index++ {
		type_id := u64(dex_u32(data, class_offset + index * 32)!)
		if type_id >= types { return error('invalid bootclasspath DEX class type') }
		string_id := u64(dex_u32(data, type_offset + type_id * 4)!)
		if string_id >= strings { return error('invalid bootclasspath DEX class descriptor index') }
		mut cursor := u64(dex_u32(data, string_offset + string_id * 4)!)
		mut terminated := false
		for _ in 0 .. 5 {
			if cursor >= u64(data.len) { return error('truncated bootclasspath DEX string') }
			byte := data[int(cursor)]
			cursor++
			if byte & 0x80 == 0 {
				terminated = true
				break
			}
		}
		if !terminated { return error('invalid bootclasspath DEX string length') }
		start := int(cursor)
		mut end := start
		for end < data.len && data[end] != 0 { end++ }
		if end == data.len { return error('unterminated bootclasspath DEX descriptor') }
		for i in start .. end {
			if data[i] > 127 { return AsciiError{data[start..end].clone(), i - start} }
		}
		descriptor := data[start..end].bytestr()
		if !descriptor.starts_with('L') || !descriptor.ends_with(';') || descriptor.starts_with('L/') || descriptor.contains('..') || descriptor.contains('\\') {
			return error('unsafe bootclasspath class descriptor: ${descriptor}')
		}
		name := descriptor[1..descriptor.len - 1] + '.class'
		if name in names { return error('duplicate bootclasspath DEX class: ${name}') }
		names[name] = true
	}
	map_offset := u64(dex_u32(data, 52)!)
	map_size := u64(dex_u32(data, map_offset)!)
	if map_offset + 4 + map_size * 12 > u64(data.len) {
		return error('truncated bootclasspath DEX map')
	}
	mut callsites := u64(0)
	for index := u64(0); index < map_size; index++ {
		at := int(map_offset + 4 + index * 12)
		if elf_u16(data, at) == 7 { callsites += elf_u32(data, at + 4) }
	}
	mut result := names.keys()
	result.sort()
	return DexInfo{result, callsites}
}

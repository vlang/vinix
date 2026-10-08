module g17expr

import encoding.binary
import encoding.hex
import g17decode as arm
import g17power as power
import json2
import math.big
import traceanalysis as j
import strconv

// Recovery borrows producer bytes synchronously. Fixture mappings describe
// independent image-provider boundaries, never analysis algorithms.
struct CommandImage {
	provider         ImageSource
	bytes            []u8
	fixture          bool
	virtual_offsets  map[string]j.Value
	vtable_targets   map[string]j.Value
	symbol_addresses map[string]j.Value
	code_fields      map[string]j.Value
}

fn command_image(data []u8, request map[string]j.Value, key string) !CommandImage {
	if key + '_fixture' in request {
		options := at(request, key + '_fixture').as_map()
		return CommandImage{ provider: fixture_image(options)!, bytes: hex.decode(text(options, 'data'))!, fixture: true, virtual_offsets: at(options, 'virtual').as_map(), vtable_targets: at(options, 'vtable').as_map(), symbol_addresses: at(options, 'symbols').as_map(), code_fields: at(options, 'codes').as_map() }
	}
	return CommandImage{ provider: DriverImage{data}, bytes: data }
}

fn (image CommandImage) symbols() !map[string]big.Integer {
	mut result := map[string]big.Integer{}
	if image.fixture {
		for name, address in image.symbol_addresses { result[name] = arm.integer(address)! }
	} else {
		for name, address in image.provider.symbols()! {
			result[name] = big.integer_from_u64(address)
		}
	}
	return result
}

fn (image CommandImage) code(name string) !(big.Integer, []u8) {
	if image.fixture {
		node := image.code_fields[name] or { return error('KeyError: ' + name) }
		entry := node.as_map()
		return arm.integer(at(entry, 'address'))!, hex.decode(text(entry, 'code'))!
	}
	address, code := image.provider.code(name)!
	return big.integer_from_u64(address), code
}

fn (image CommandImage) virtual(address big.Integer) !big.Integer {
	if image.fixture {
		return arm.integer(image.virtual_offsets[address.str()] or { return error('KeyError: ' + address.str()) })!
	}
	return arm.virtual_to_file(image.bytes, address)
}

fn (image CommandImage) vtable(name string, slot int) !big.Integer {
	if image.fixture {
		return arm.integer(image.vtable_targets[name + ':' + slot.str()] or { return error('KeyError: ' + name) })!
	}
	return big.integer_from_u64(arm.recover_vtable_target(image.bytes, name, big.integer_from_int(slot))!)
}

fn required_symbols(image CommandImage, names []string, message string, single bool) !map[string]big.Integer {
	symbols := image.symbols()!
	mut missing := []j.Value{}
	for name in names { if name !in symbols { missing << j.Value(name) } }
	if missing.len > 0 {
		return error(message + if single {
			j.string_value(missing[0])
		} else {
			j.string_value(j.Value(missing))
		})
	}
	return symbols
}

fn checked_code(image CommandImage, name string, proof string) ![]u8 {
	_, code := image.code(command_symbol(name))!
	command_check(code, proof)!
	return code
}

fn command_check(code []u8, proof string) ! {
	arm.require_instruction_words_at(code, proof, command_words(proof))!
}

fn word32(code []u8, offset int) !u32 {
	if offset < 0 || offset > code.len - 4 {
		return error('struct.error: unpack_from requires a buffer of at least ${offset + 4} bytes for unpacking 4 bytes at offset ${offset} (actual buffer size is ${code.len})')
	}
	return binary.little_endian_u32(code[offset..offset + 4])
}

fn word64(code []u8, offset int) !u64 {
	if offset < 0 || offset > code.len - 8 {
		return error('struct.error: unpack_from requires a buffer of at least ${offset + 8} bytes for unpacking 8 bytes at offset ${offset} (actual buffer size is ${code.len})')
	}
	return binary.little_endian_u64(code[offset..offset + 8])
}

fn call_target(address big.Integer, code []u8, offset int) !big.Integer {
	instruction := Instruction{ offset: address + big.integer_from_int(offset), word: word32(code, offset)! }
	return branch_target('decode_bl_target', instruction) or { return error('no direct call') }
}

fn command_names(names []string) []string { return names.map(command_symbol(it)) }

fn simple_command_contract(image CommandImage, iogpu CommandImage, operation string, request map[string]j.Value) !map[string]j.Value {
	match operation {
		'recover_g17_command_stream_format' {
			required_symbols(image, command_names(['PARSE_HARDWARE_KERNEL_COMMAND']), 'Mach-O is missing ', true)!
			checked_code(image, 'PARSE_HARDWARE_KERNEL_COMMAND', 'G17 command-stream record parse')!
			if 0xac - 0x10 < 0 || 0xac - 0x10 >= 0xc0 {
				return error('payload length field falls outside the record header')
			}
		}
		'recover_g17_render_payload_format' {
			required_symbols(image, command_names(['PARSE_RENDER_HARDWARE_KERNEL_COMMAND']), 'Mach-O is missing ', true)!
			checked_code(image, 'PARSE_RENDER_HARDWARE_KERNEL_COMMAND', 'G17 render command payload parse')!
			metadata := command_metadata(operation)
			mut fields := at(metadata, 'copy_ranges').arr().clone()
			fields << at(metadata, 'bit_fields').arr()
			for item in fields {
				field := item.as_map()
				size := if 'bytes' in field { number(field, 'bytes') } else { 1 }
				if number(field, 'payload_offset') + size > 0x9d0 {
					return error('render command field falls outside its fixed payload')
				}
			}
		}
		'recover_g17_channel_command_common_fields' {
			required_symbols(image, command_names(['SUBMIT_NOP_UNPREPARED']), 'Mach-O is missing ', true)!
			checked_code(image, 'SUBMIT_NOP_UNPREPARED', 'G17 common channel-command fields')!
			mut end := 0
			for _, item in at(command_metadata(operation), 'fields').as_map() {
				field := item.as_map()
				extent := number(field, 'offset') + number(field, 'bytes')
				if extent > end { end = extent }
			}
			if end != 0x6a || end > 0x80 {
				return error('unexpected common command prefix extent 0x${end:x}')
			}
		}
		'recover_g17_register_entry_codec' {
			required_symbols(image, command_names(['RCE_ENCODE_ENTRY']), 'Mach-O is missing ', true)!
			checked_code(image, 'RCE_ENCODE_ENTRY', 'G17 register-entry codec')!
		}
		'recover_g17_3d_register_lists' {
			required_symbols(image, command_names(['GENERATE_REGISTER_LIST_3D']), 'Mach-O is missing ', true)!
			code := checked_code(image, 'GENERATE_REGISTER_LIST_3D', 'G17 3D register-list framing')!
			command_check(code, 'G17 3D register-list publication')!
			if 0xa0 + 0x700 + 0xc > 0x720 + 0xa0 {
				return error('G17 3D register-list passes overlap')
			}
			if 3 * 0x720 + 0x7a0 + 0xc > command_number('G17_COMMAND_3D_BYTES') {
				return error('G17 3D register-list metadata falls outside the command')
			}
		}
		'recover_g17_3d_command_reclamation' {
			required_symbols(image, command_names(['COMPLETE_COMMAND_3D']), 'Mach-O is missing ', true)!
			checked_code(image, 'COMPLETE_COMMAND_3D', 'G17 3D command reclamation')!
		}
		'recover_g17_channel_identity' {
			driver_symbols := image.symbols()!
			iogpu_symbols := iogpu.symbols()!
			if command_symbol('CHANNEL_INIT') !in driver_symbols {
				return error('driver is missing AGXChannel::init')
			}
			if command_symbol('IOGPU_CHANNEL_INIT') !in iogpu_symbols {
				return error('IOGPUFamily is missing IOGPUChannel::init')
			}
			checked_code(image, 'CHANNEL_INIT', 'G17 IOGPU channel initialization')!
			checked_code(iogpu, 'IOGPU_CHANNEL_INIT', 'IOGPU channel identity store')!
		}
		'recover_g17_channel_runtime_resources' {
			image.symbols()!
			iogpu_symbols := iogpu.symbols()!
			required_symbols(image, command_names(['PI300_CONFIGURE_DEVICE', 'BASE_ALLOC_FIRMWARE_DATA',
				'AGX_COMMAND_QUEUE_INIT', 'AGX_WORK_QUEUE_INIT', 'ALLOCATE_3D_WORK_QUEUE',
				'ALLOCATE_CL_WORK_QUEUE', 'TIMESTAMP_QUEUE_INIT', 'RESET_TIMESTAMP_QUEUE']), 'AGXG17X is missing channel runtime symbols: ', false)!
			if command_symbol('IOGPU_WORK_QUEUE_INIT') !in iogpu_symbols {
				return error('IOGPUFamily is missing IOGPUWorkQueue::init')
			}
			checked_code(image, 'PI300_CONFIGURE_DEVICE', 'G17 configured work-queue default')!
			checked_code(image, 'BASE_ALLOC_FIRMWARE_DATA', 'G17 timestamp-state pool')!
			checked_code(image, 'AGX_COMMAND_QUEUE_INIT', 'G17 command-queue ring request')!
			checked_code(image, 'AGX_WORK_QUEUE_INIT', 'G17 AGX work-queue base initialization')!
			checked_code(iogpu, 'IOGPU_WORK_QUEUE_INIT', 'IOGPU work-queue ring request')!
			checked_code(image, 'ALLOCATE_3D_WORK_QUEUE', 'G17 render work-channel inputs')!
			checked_code(image, 'ALLOCATE_CL_WORK_QUEUE', 'G17 compute work-channel inputs')!
			_, timestamp := image.code(command_symbol('TIMESTAMP_QUEUE_INIT'))!
			if timestamp.len != 0x490 {
				return error('unexpected timestamp-queue init size 0x${timestamp.len:x}')
			}
			command_check(timestamp, 'G17 timestamp-queue mappings')!
			_, reset := image.code(command_symbol('RESET_TIMESTAMP_QUEUE'))!
			if reset.len != 0x38 {
				return error('unexpected timestamp reset size 0x${reset.len:x}')
			}
			command_check(reset, 'G17 timestamp-state reset')!
		}
		'recover_g17_channel_state_sources' {
			required_symbols(image, command_names(['CHANNEL_INIT', 'SET_KICK_CHANNEL_QOS']), 'Mach-O is missing G17 channel-source symbols: ', false)!
			command_check(hex.decode(text(request, 'reset_code'))!, 'G17 channel-state input copies')!
			_, qos := image.code(command_symbol('SET_KICK_CHANNEL_QOS'))!
			if qos.len != 0x28 {
				return error('unexpected kick-channel QoS setter size 0x${qos.len:x}')
			}
			command_check(qos, 'G17 kick-channel QoS setter')!
			checked_code(image, 'CHANNEL_INIT', 'G17 channel input seeding')!
		}
		else { return error('unknown G17 command contract ' + operation) }
	}
	return command_metadata(operation)
}

fn command_hex(value big.Integer) string {
	return if value.signum < 0 { '-0x' + offset_hex(value.abs()) } else { '0x' + offset_hex(value) }
}

fn command_integer(value j.Value) !big.Integer {
	match value {
		json2.Null {
			return error("TypeError: int() argument must be a string, a bytes-like object or a number, not 'NoneType'")
		}
		[]j.Value {
			return error("TypeError: int() argument must be a string, a bytes-like object or a number, not 'list'")
		}
		map[string]j.Value {
			return error("TypeError: int() argument must be a string, a bytes-like object or a number, not 'dict'")
		}
		else {
			return power.decimal_integer(value) or {
				if err.msg() == 'cannot convert float infinity to integer' {
					return error('OverflowError: ' + err.msg())
				}
				return err
			}
		}
	}
}

fn command_field(node map[string]j.Value, key string) !j.Value {
	return node[key] or { return error('KeyError: ' + key) }
}

fn unpack_offset(data []u8, offset big.Integer, width int) !int {
	maximum := big.integer_from_string('9223372036854775807')!
	minimum := maximum.neg() - big.integer_from_int(1)
	if offset < minimum || offset > maximum {
		return error('OverflowError: Python int too large to convert to C ssize_t')
	}
	if offset.signum < 0 {
		if offset < big.integer_from_int(-data.len) {
			return error('struct.error: offset ' + offset.str() + ' out of range for ' + data.len.str() + '-byte buffer')
		}
		if offset + big.integer_from_int(width) > big.zero_int {
			return error('struct.error: not enough data to unpack ' + width.str() + ' bytes at offset ' + offset.str())
		}
		return data.len + int(strconv.parse_int(offset.str(), 10, 64)!)
	}
	if offset + big.integer_from_int(width) > big.integer_from_int(data.len) {
		return error('struct.error: unpack_from requires a buffer of at least ' + (offset + big.integer_from_int(width)).str() + ' bytes for unpacking ' + width.str() + ' bytes at offset ' + offset.str() + ' (actual buffer size is ' + data.len.str() + ')')
	}
	return int(strconv.parse_int(offset.str(), 10, 64)!)
}

fn string_offset(data []u8, offset big.Integer) int {
	size := big.integer_from_int(data.len)
	if offset.signum < 0 {
		if offset < size.neg() { return 0 }
		return data.len + int(strconv.parse_int(offset.str(), 10, 64) or { panic(err) })
	}
	if offset > size { return data.len }
	return int(strconv.parse_int(offset.str(), 10, 64) or { panic(err) })
}

fn utf8_failure(data []u8, start int, end int, reason string) IError {
	return error('UnicodeDecodeError: ' + j.encode(expr({
		'bytes':  j.Value(hex.encode(data))
		'start':  j.Value(start)
		'end':    j.Value(end)
		'reason': j.Value(reason)
	}), false))
}

fn strict_utf8(data []u8) !string {
	mut index := 0
	for index < data.len {
		lead := data[index]
		if lead < 128 {
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
		if count == 0 { return utf8_failure(data, index, index + 1, 'invalid start byte') }
		mut consumed := 1
		for consumed < count && index + consumed < data.len {
			byte := data[index + consumed]
			if byte < 0x80 || byte > 0xbf || (consumed == 1 && ((lead == 0xe0 && byte < 0xa0) || (lead == 0xed && byte >= 0xa0) || (lead == 0xf0 && byte < 0x90) || (lead == 0xf4 && byte >= 0x90))) {
				return utf8_failure(data, index, index + consumed, 'invalid continuation byte')
			}
			consumed++
		}
		if consumed < count {
			return utf8_failure(data, index, index + consumed, 'unexpected end of data')
		}
		index += count
	}
	return data.bytestr()
}

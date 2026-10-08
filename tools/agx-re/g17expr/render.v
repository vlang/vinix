module g17expr

import g17decode as arm
import math.big
import traceanalysis as j

fn descriptor_defaults(image CommandImage) !map[string]j.Value {
	symbols := required_symbols(image, command_names(['ALLOC_3D_COMMAND_DESCRIPTOR',
		'INIT_3D_COMMAND_DESCRIPTOR', 'ALLOC_TA_COMMAND_DESCRIPTOR', 'INIT_TA_COMMAND_DESCRIPTOR']), 'Mach-O is missing 3D descriptor initializers: ', false)!
	checked_code(image, 'ALLOC_3D_COMMAND_DESCRIPTOR', 'G17 3D descriptor allocation defaults')!
	checked_code(image, 'INIT_3D_COMMAND_DESCRIPTOR', 'G17 3D descriptor initialization defaults')!
	ta_alloc := checked_code(image, 'ALLOC_TA_COMMAND_DESCRIPTOR', 'G17 TA descriptor allocation defaults')!
	if ta_alloc.len != 0x1a8 {
		return error('unexpected G17 TA descriptor allocator size 0x${ta_alloc.len:x}')
	}
	address, code := image.code(command_symbol('INIT_TA_COMMAND_DESCRIPTOR'))!
	word32(code, 0x18)!
	target := call_target(address, code, 0x18) or { return error('G17 TA descriptor init no longer calls its 3D base init') }
	if target != symbols[command_symbol('INIT_3D_COMMAND_DESCRIPTOR')] {
		return error('G17 TA descriptor init no longer calls its 3D base init')
	}
	command_check(code, 'G17 TA descriptor initialization defaults')!
	if code.len != 0x1d4 { return error('unexpected G17 TA descriptor init size 0x${code.len:x}') }
	return command_metadata('recover_g17_3d_descriptor_initialization')
}

fn common_passthrough(image CommandImage) !map[string]j.Value {
	required_symbols(image, command_names(['COPY_3D_COMMON_PASSTHROUGH', 'PROCESS_RENDER_SETUP',
		'ALLOC_3D_COMMAND_DESCRIPTOR']), 'Mach-O is missing 3D descriptor producers: ', false)!
	copy_address, code := image.code(command_symbol('COPY_3D_COMMON_PASSTHROUGH'))!
	command_check(code, 'G17 3D common passthrough copy')!
	if code.len != 0x250 {
		return error('unexpected 3D passthrough producer length 0x${code.len:x}')
	}
	address, setup := image.code(command_symbol('PROCESS_RENDER_SETUP'))!
	command_check(setup, 'G17 3D common passthrough source')!
	word32(setup, 0x1f78)!
	target := call_target(address, setup, 0x1f78) or { return error('G17 render setup no longer calls the passthrough producer') }
	if target != copy_address {
		return error('G17 render setup no longer calls the passthrough producer')
	}
	checked_code(image, 'ALLOC_3D_COMMAND_DESCRIPTOR', 'G17 3D descriptor allocation')!
	mut operations := []j.Value{}
	for instruction in instructions_from_code(code) {
		logical := fields('decode_logical_immediate_w', instruction.word, instruction.offset) or { continue }
		if j.string_value(logical[0]) != 'and' || logical[3].u64() != 1 { continue }
		offset := integer(scalar(instruction.offset))
		if offset < 4 || offset + 8 > code.len {
			return error('truncated G17 common boolean mask chain')
		}
		load := fields('decode_integer_load_unsigned', word32(code, offset - 4)!, big.zero_int) or { return error('malformed G17 common boolean mask chain') }
		store := fields('decode_integer_store_unsigned', word32(code, offset + 4)!, big.zero_int) or { return error('malformed G17 common boolean mask chain') }
		if load[0].u64() != logical[2].u64() || load[1].u64() != 1 || load[3].u64() != 1 || store[0].u64() != logical[1].u64() || store[1].u64() != 0 || store[3].u64() != 1 {
			return error('malformed G17 common boolean mask chain')
		}
		operations << expr({
			'producer_offset':   scalar(instruction.offset)
			'source_offset':     load[2]
			'descriptor_member': store[2]
			'mask':              j.Value(1)
		})
	}
	mut metadata := command_metadata('recover_g17_3d_common_passthrough')
	fields := at(metadata, 'bit_fields').arr()
	mut observed := map[string]bool{}
	mut expected := map[string]bool{}
	for item in operations {
		node := item.as_map()
		observed[text(node, 'source_offset') + ':' + text(node, 'descriptor_member')] = true
	}
	for item in fields {
		node := item.as_map()
		expected[text(node, 'source_offset') + ':' + text(node, 'descriptor_member')] = true
	}
	if operations.len != fields.len || observed != expected {
		return error('G17 common boolean copy map does not match mask chains')
	}
	for item in at(metadata, 'copy_ranges').arr() {
		node := item.as_map()
		if number(node, 'source_offset') + number(node, 'bytes') > 0x3ec || number(node, 'descriptor_member') + number(node, 'bytes') > 0xc40 {
			return error('3D passthrough copy falls outside its source or descriptor')
		}
	}
	for item in fields {
		node := item.as_map()
		if number(node, 'source_offset') >= 0x3ec || number(node, 'descriptor_member') >= 0xc40 {
			return error('3D passthrough bit field falls outside its object')
		}
	}
	metadata['mask_operations'] = j.Value(operations)
	return metadata
}

fn ta_passthrough(image CommandImage) !map[string]j.Value {
	symbols := required_symbols(image, command_names(['PROCESS_RENDER_SETUP',
		'COPY_3D_COMMON_PASSTHROUGH']), 'Mach-O is missing TA render passthrough producers: ', false)!
	address, code := image.code(command_symbol('PROCESS_RENDER_SETUP'))!
	word32(code, 0x1f78)!
	target := call_target(address, code, 0x1f78) or { return error('G17 TA render setup no longer calls the 3D common helper') }
	if target != symbols[command_symbol('COPY_3D_COMMON_PASSTHROUGH')] {
		return error('G17 TA render setup no longer calls the 3D common helper')
	}
	command_check(code, 'G17 TA render passthrough')!
	metadata := command_metadata('recover_g17_ta_render_passthrough')
	for key in ['pre_common_copy_ranges', 'post_common_copy_ranges'] {
		for item in at(metadata, key).arr() {
			field := item.as_map()
			if number(field, 'source_offset') + number(field, 'bytes') > 0x9d0 || number(field, 'descriptor_member') + number(field, 'bytes') > 0x15b0 {
				return error('TA render passthrough copy falls outside its objects')
			}
		}
	}
	for key in ['pre_common_bit_fields', 'post_common_bit_fields'] {
		for item in at(metadata, key).arr() {
			field := item.as_map()
			if number(field, 'source_offset') >= 0x9d0 || number(field, 'descriptor_member') + number(field, 'destination_bytes') > 0x15b0 {
				return error('TA render passthrough bit field falls outside its objects')
			}
		}
	}
	return metadata
}

struct PayloadSource {
	offset big.Integer
	masked bool
}

fn raw_payload_source(payload map[string]j.Value, member big.Integer, size big.Integer) !PayloadSource {
	mut matches := []PayloadSource{}
	for item in command_field(payload, 'copy_ranges')!.arr() {
		node := item.as_map()
		base := command_integer(command_field(node, 'command_member')!)!
		bytes := command_integer(command_field(node, 'bytes')!)!
		if base <= member && member + size <= base + bytes {
			matches << PayloadSource{command_integer(command_field(node, 'payload_offset')!)! + member - base, false}
		}
	}
	for item in command_field(payload, 'bit_fields')!.arr() {
		node := item.as_map()
		if command_integer(command_field(node, 'command_member')!)! == member && size == big.integer_from_int(1) {
			matches << PayloadSource{command_integer(command_field(node, 'payload_offset')!)!, true}
		}
	}
	if matches.len != 1 {
		return error('G17 normalized field 0x${offset_hex(member)}+0x${offset_hex(size)} has ${matches.len} raw-payload sources')
	}
	return matches[0]
}

fn render_descriptor(image CommandImage, iogpu CommandImage, payload map[string]j.Value) !map[string]j.Value {
	required_symbols(image, command_names(['PROCESS_RENDER_SETUP', 'BASE_CONFIGURE_DEVICE']), 'Mach-O is missing ', true)!
	required_symbols(iogpu, command_names(['IOGPU_COMMAND_DESCRIPTOR_INIT']), 'IOGPUFamily is missing ', true)!
	checked_code(image, 'PROCESS_RENDER_SETUP', 'G17 normalized render descriptor fields')!
	checked_code(iogpu, 'IOGPU_COMMAND_DESCRIPTOR_INIT', 'G17 descriptor accelerator retention')!
	checked_code(image, 'BASE_CONFIGURE_DEVICE', 'G17 descriptor fallback device bit')!
	mut metadata := command_metadata('recover_g17_render_descriptor_fields')
	mut direct := []j.Value{}
	for item in at(metadata, 'direct_fields').arr() {
		mut field := item.as_map().clone()
		source := raw_payload_source(payload, command_integer(at(field, 'command_member'))!, command_integer(at(field, 'bytes'))!)!
		if source.masked != ('mask' in field) {
			return error('G17 render descriptor mask provenance changed')
		}
		field['payload_offset'] = scalar(source.offset)
		direct << expr(field)
	}
	conditional := raw_payload_source(payload, big.integer_from_int(0x283), big.integer_from_int(1))!
	if !conditional.masked || conditional.offset != big.integer_from_int(0x650) {
		return error('G17 conditional render field provenance changed')
	}
	metadata['direct_fields'] = j.Value(direct)
	return metadata
}

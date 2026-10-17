// SPDX-License-Identifier: GPL-2.0-or-later
module g17expr

import g17decode as arm
import traceanalysis as j

fn visibility_copy(code []u8) ! {
	arm.require_instruction_words_at(code, 'G17 visibility buffer copy', {
		0x1f7c: u32(0xf9400f48) // ldr x8, [x26, #0x18]: retained payload
		0x1f80: u32(0xf9436109) // ldr x9, [x8, #0x6c0]
		0x1f84: u32(0xf9026329) // str x9, [x25, #0x4c0]
	})!
}

// Relate the already instruction-checked raw copy map to the independently
// traced register consumer. Keep semantic field promotion out of the generic
// pointer-correlation tool: this register identity comes from m1n1's
// ISP_OCLQRY_BASE producer, rather than adjacency to another resource field.
fn visibility_layout(passthrough map[string]j.Value, selectors map[string]j.Value) !j.Value {
	mut copies := 0
	for item in at(passthrough, 'post_common_copy_ranges').arr() {
		field := item.as_map()
		if number(field, 'descriptor_member') != 0x4c0 { continue }
		if number(field, 'source_offset') != 0x6c0 || number(field, 'bytes') != 8 {
			return error('G17 visibility buffer payload copy changed')
		}
		copies++
	}
	mut consumers := 0
	producer := at(at(selectors, 'producers').as_map(), '3D').as_map()
	for item in at(producer, 'encoder_entries').arr() {
		entry := item.as_map()
		if number(entry, 'selector') != 0x15310 { continue }
		source := at(entry, 'value_source').as_map()
		expression := at(source, 'expression').as_map()
		load := at(expression, 'source').as_map()
		if number(entry, 'mode') != 1 || text(expression, 'kind') != 'expression'
			|| text(expression, 'operation') != 'and' || number(expression, 'bytes') != 8
			|| at(expression, 'immediate').u64() != ~u64(15)
			|| text(load, 'kind') != 'descriptor_load'
			|| number(load, 'member') != 0x4c0 || number(load, 'bytes') != 8
			|| at(load, 'signed') != j.Value(false) {
			return error('G17 visibility buffer register consumer changed')
		}
		consumers++
	}
	if copies != 1 || consumers != 1 {
		return error('G17 visibility buffer requires exactly one payload copy and register consumer')
	}
	return expr({
		'field':             j.Value('visibility_result_buffer')
		'payload_offset':    j.Value(0x6c0)
		'descriptor_member': j.Value(0x4c0)
		'bytes':             j.Value(8)
		'selector':          j.Value(0x15310)
		'mode':              j.Value(1)
		'value_mask':        j.Value(~u64(15))
	})
}

// Accept only the same Apple driver build as the production G17 recovery.
// This reads a local image; it never loads a kext or writes GPU registers.
pub fn recover_render_visibility(data []u8) !j.Value {
	if arm.macho_uuid(data)! != j.Value(arm.driver_uuid) {
		return error('unsupported AGXG17X UUID for visibility-buffer recovery')
	}
	image := command_image(data, map[string]j.Value{}, 'image')!
	_, setup := image.code(command_symbol('PROCESS_RENDER_SETUP'))!
	visibility_copy(setup)!
	passthrough := ta_passthrough(image)!
	return visibility_layout(passthrough, register_selectors(data)!)
}

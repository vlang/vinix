module g17expr

import g17decode as arm
import math.big
import json2
import traceanalysis as j

fn shared_platform_fields(code []u8) !j.Value {
	layout_seq(code, 'primary shared platform service pair')!
	layout_seq(code, 'primary shared second platform service pair')!
	for instruction, label in {
		u32(0xf9016ea0): 'primary platform address 0x2d8'
		u32(0xf90172a0): 'primary platform address 0x2e0'
		u32(0xf90176a0): 'primary platform address 0x2e8'
		u32(0xf9017aa0): 'primary platform address 0x2f0'
		u32(0xf9017ebf): 'primary reserved address 0x2f8'
	} {
		if !contains_words(code, [instruction]) { return error('missing ' + label + ' store') }
	}
	for instruction, label in {
		u32(0xf9016ebf): 'nullable primary platform address 0x2d8'
		u32(0xf90176bf): 'nullable primary platform address 0x2e8'
	} {
		if !contains_words(code, [instruction]) { return error('missing ' + label + ' zero store') }
	}
	if byte_count(code, encoded_words([u32(0xd2800000)])) < 2 {
		return error('missing nullable secondary platform-service addresses')
	}
	for label in ['secondary shared platform mirrors', 'role-specific shared platform scalars',
		'primary shared calibration copy', 'secondary shared calibration copy',
		'primary shared state initialization'] {
		layout_seq(code, label)!
	}
	return layout_metadata('recover_firmware_shared_platform_fields')
}

fn driver_hardware_layout(base_init []u8, base_power []u8, arm_power []u8) !j.Value {
	layout_seq(base_init, 'color-matrix copy loop')!
	layout_seq(base_init, 'I/O-mapping copy loop')!
	mut base_stores := []int{}
	for instruction in arm.words(base_power) {
		store := fields('decode_str_unsigned', instruction.word, big.zero_int) or { continue }
		if store[1].int() == 8 && store[3].int() == 4 { base_stores << store[2].int() }
	}
	mut missing := []int{}
	for offset in 0 .. 17 {
		if 0xfc4 + offset * 4 !in base_stores { missing << 0xfc4 + offset * 4 }
	}
	for offset in 0 .. 16 {
		if 0x1808 + offset * 4 !in base_stores { missing << 0x1808 + offset * 4 }
	}
	if missing.len > 0 {
		return error('hardware-config producer has incomplete performance tables: ' + layout_hex_list(missing))
	}
	layout_seq(base_power, 'primary and SRAM frequency-table conversion')!
	layout_seq(arm_power, 'voltage-table loop setup')!
	mut voltage_stores := []int{}
	for instruction in arm.words(arm_power) {
		store := fields('decode_str_unsigned', instruction.word, big.zero_int) or { continue }
		if store[1].int() == 10 && store[3].int() == 4 { voltage_stores << store[2].int() }
	}
	for offset in 0 .. 16 {
		if offset * 4 !in voltage_stores || 0x400 + offset * 4 !in voltage_stores {
			return error('hardware-config producer has incomplete 16-column voltage rows')
		}
	}
	layout_seq(arm_power, 'voltage-table row advance')!
	layout_seq(arm_power, 'linear-power table binding')!
	for label in ['table binding at 0x1908', 'table binding at 0x1948', 'table binding at 0x19c8'] {
		layout_seq(arm_power, label)!
	}
	return layout_metadata('recover_driver_hardware_config_layout')
}

fn hardware_config(allocations []j.Value, shared_code []u8, firmware []u8) !j.Value {
	mut size := j.Value(json2.null)
	for item in allocations {
		node := runtime_allocation_node(item)!
		if !runtime_equal(command_field(node, 'host_cpu_member')!, 0x2b8) { continue }
		if !runtime_equal(command_field(node, 'host_gpu_member')!, 0x300) { continue }
		size = command_field(node, 'bytes')!
		break
	}
	if !runtime_equal(size, 0x2710) {
		return error('unexpected hardware config allocation size: ' + j.string_value(runtime_repr_value(size)))
	}
	instructions := arm.words(shared_code)
	mut published := []int{}
	for index, instruction in instructions {
		source := fields('decode_ldr_x', instruction.word, big.zero_int) or { continue }
		if source[0].int() != 1 || source[1].int() != 19 || source[2].int() != 0x300 { continue }
		for next_index := index + 1; next_index < int_min(index + 24, instructions.len); next_index++ {
			load := fields('decode_ldr_x', instructions[next_index].word, big.zero_int) or { continue }
			if load[0].int() != 8 || load[1].int() != 19 { continue }
			for following in instructions[next_index + 1..int_min(next_index + 18, instructions.len)] {
				store := fields('decode_str_x', following.word, big.zero_int) or { continue }
				if store[0].int() == 0 && store[1].int() == 8 && store[2].int() == 0 {
					if load[2].int() !in published { published << load[2].int() }
					break
				}
			}
		}
	}
	published.sort()
	if published != [0xa98, 0xbc8] {
		return error('hardware config address was not published to both firmware roles: ' + layout_hex_list(published))
	}
	mut result := {
		'bytes':                        j.Value(0x2710)
		'host_cpu_member':              j.Value(0x2b8)
		'host_gpu_member':              j.Value(0x300)
		'firmware_shared_offset':       j.Value(0)
		'published_shared_cpu_members': j.Value(published.map(j.Value(it)))
	}
	for key, value in firmware_config_reads(firmware)!.as_map() { result[key] = value }
	return expr(result)
}

fn root_allocation_sizes(allocations []j.Value) !j.Value {
	sizes := layout_allocation_map(allocations)!
	records := [LayoutRootSize{'firmware_shared_data', 0xab8, 0x4c0},
		LayoutRootSize{'secondary_firmware_shared_data', 0xbe8, 0x4c0},
		LayoutRootSize{'runtime_data', 0x388, 0x1ca0},
		LayoutRootSize{'small_shared_data', 0xad0, 0x20},
		LayoutRootSize{'secondary_small_shared_data', 0xc00, 0x20},
		LayoutRootSize{'primary_region', 0xce0, 0xe440},
		LayoutRootSize{'secondary_region', 0xce8, 0x6f0}, LayoutRootSize{'secondary_aux', 0x398, 0xa8}]
	mut result := map[string]j.Value{}
	for record in records {
		size := layout_allocation_get(sizes, record.member)
		if !runtime_equal(size, record.size) {
			return error('unexpected ' + record.name + ' allocation through host member 0x' + record.member.hex() + ': ' + j.string_value(runtime_repr_value(size)))
		}
		result[record.name] = size
	}
	return expr(result)
}

struct LayoutRootSize {
	name   string
	member int
	size   int
}

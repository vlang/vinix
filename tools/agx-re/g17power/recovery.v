module g17power

import g17decode as arm
import imageextract as image
import math
import math.big
import traceanalysis as j

// Recovery proofs accept a byte-backed image provider. Independent fixtures
// can supply their own symbol/code map without replacing the native algorithm.
pub interface RecoverySource {
	data() []u8
	symbols() !map[string]u64
	vtable(name string, slot int) !u64
	code(name string) !(u64, []u8)
	file_offset(address u64) !int
}

pub struct DriverImage {
pub:
	image []u8
}

pub fn (source DriverImage) data() []u8 { return source.image }

pub fn (source DriverImage) symbols() !map[string]u64 { return arm.macho_symbols(source.image) }

pub fn (source DriverImage) vtable(name string, slot int) !u64 {
	return arm.recover_vtable_target(source.image, name, big.integer_from_int(slot))
}

pub fn (source DriverImage) code(name string) !(u64, []u8) {
	return arm.symbol_code(source.image, name)
}

pub fn (source DriverImage) file_offset(address u64) !int {
	position := arm.virtual_to_file(source.image, big.integer_from_u64(address))!
	return int(small(position))
}

fn checked_span(data []u8, offset int, bytes int) ! {
	if offset < 0 {
		return error('struct.error: offset ${offset} out of range for ${data.len}-byte buffer')
	}
	if offset > data.len - bytes {
		return error('struct.error: unpack_from requires a buffer of at least ${offset + bytes} bytes for unpacking ${bytes} bytes at offset ${offset} (actual buffer size is ${data.len})')
	}
}

fn word(data []u8, offset int) !u32 {
	checked_span(data, offset, 4)!
	return image.u32_at(data, offset)
}

fn decoded_fields(name string, word u32, address u64) ?[]j.Value {
	value := arm.decode(name, word, j.Value(address))
	return match value {
		[]j.Value { value }
		else { none }
	}
}

fn proof(code []u8, label string) ! {
	arm.require_instruction_words_at(code, label, proof_words(label))!
}

fn referenced_table(address u64, code []u8, adrp_offset int, add_offset int, register int) !u64 {
	page := decoded_fields('decode_adrp', word(code, adrp_offset)!, address + u64(adrp_offset)) or { return error('chip-leakage fuse table reference changed') }
	add := decoded_fields('decode_add_immediate', word(code, add_offset)!, 0) or { return error('chip-leakage fuse table reference changed') }
	if page[0].int() != register || add[0].int() != register || add[1].int() != register {
		return error('chip-leakage fuse table register changed')
	}
	return page[1].u64() + add[2].u64()
}

fn records_value(records [][]f64) j.Value {
	mut result := []j.Value{}
	for record in records {
		mut row := []j.Value{}
		for number in record { row << j.Value(j.Number{number.str()}) }
		result << j.Value(row)
	}
	return j.Value(result)
}

fn leakage_table(source RecoverySource, name string) !map[string]j.Value {
	address, code := source.code(name)!
	mut buckets := []u64{}
	for offset in [0x10, 0x38] {
		page := decoded_fields('decode_adrp', word(code, offset)!, address + u64(offset)) or { return error('${name} no longer references a parameter table') }
		add := decoded_fields('decode_add_immediate', word(code, offset + 4)!, 0) or { return error('${name} no longer references a parameter table') }
		buckets << page[1].u64() + add[2].u64()
	}
	load := decoded_fields('decode_ldr_d', word(code, 0x20)!, 0) or { return error('${name} no longer loads a bucket count') }
	page := decoded_fields('decode_adrp', word(code, 0x1c)!, address + 0x1c) or { return error('${name} no longer references the bucket count') }
	data := source.data()
	count := word(data, source.file_offset(page[1].u64() + load[2].u64())!)!
	mut tables := [][][]f64{}
	for table in buckets {
		offset := source.file_offset(table)!
		mut table_records := [][]f64{}
		for index in 0 .. count {
			position := offset + int(index) * 0x58
			checked_span(data, position, 0x58)!
			mut row := []f64{}
			for parameter in 0 .. 11 {
				row << math.f64_from_bits(image.u64_at(data, position + parameter * 8))
			}
			table_records << row
		}
		tables << table_records
	}
	if tables[0].len == 0 || tables[1].len == 0 {
		return error('IndexError: list index out of range')
	}
	if tables[0].last()[0] != -1.0 || tables[1].last()[0] != -1.0 {
		return error('${name} parameter table lost its catch-all bucket')
	}
	return {
		'buckets':            j.Value(count)
		'record_bytes':       j.Value(0x58)
		'default_table':      j.Value(buckets[0])
		'variant_table':      j.Value(buckets[1])
		'default_thresholds': j.Value(tables[0].map(j.Value(j.Number{it[0].str()})))
		'variant_thresholds': j.Value(tables[1].map(j.Value(j.Number{it[0].str()})))
		'default_records':    records_value(tables[0])
		'variant_records':    records_value(tables[1])
	}
}

pub fn recover_linear_power_transfer_tables(data []u8, power_code []u8) !map[string]j.Value {
	return recover_with_source(DriverImage{data}, power_code)
}

pub fn recover_with_source(source RecoverySource, power_code []u8) !map[string]j.Value {
	symbols := source.symbols()!
	required := [linear_provider, main_provider, afr_provider, vdd_leakage_provider,
		afr_leakage_provider, equation_provider, chip_leakage_provider]
	missing := required.filter(it !in symbols)
	if missing.len > 0 {
		return error('Mach-O is missing G17 power-model symbols: ${j.string_value(j.Value(missing.map(j.Value(it))))}')
	}
	for slot, name in {
		main_power_slot:   main_provider
		afr_power_slot:    afr_provider
		vdd_leakage_slot:  vdd_leakage_provider
		afr_leakage_slot:  afr_leakage_provider
		equation_slot:     equation_provider
		chip_leakage_slot: chip_leakage_provider
	} {
		target := source.vtable(accelerator_vtable, slot)!
		if target != symbols[name] {
			return error('unexpected G17 power vtable target at 0x${slot:x}: 0x${target:x}')
		}
	}
	proof(power_code, 'G17 linear power-transfer call')!
	call := arm.decode('decode_bl_target', 0x97feaa33, j.Value((symbols[arm.init_power_data] or { return error('KeyError: ${arm.init_power_data}') }) + 0x958)).u64()
	if call != symbols[linear_provider] {
		return error('linear power-transfer call does not reach the producer: 0x${call:x}')
	}
	proof(power_code, 'G17 inlined AFR linear power-transfer producer')!
	_, linear_code := source.code(linear_provider)!
	proof(linear_code, 'G17 linear power-transfer normalisation')!
	_, main_code := source.code(main_provider)!
	proof(main_code, 'G17 maximum-performance power matrix')!
	_, afr_code := source.code(afr_provider)!
	proof(afr_code, 'G17 CS maximum-performance power matrix')!
	leak_address, leak_code := source.code(chip_leakage_provider)!
	mut physical := u64(0)
	for offset in [0xb8, 0xbc, 0xc0] {
		move := decoded_fields('decode_move_wide', word(leak_code, offset)!, 0) or { return error('chip-leakage fuse aperture is no longer materialized') }
		if move[1].int() != 0 {
			return error('chip-leakage fuse aperture uses an unexpected register')
		}
		physical |= move[2].u64() << move[3].int()
	}
	if word(leak_code, 0xc4)! != 0x52820001 {
		return error('chip-leakage fuse aperture size changed')
	}
	call_value := arm.decode('decode_bl_target', word(leak_code, 0xcc)!, j.Value(0xcc))
	match call_value {
		j.Number, u64, i64, int, u32, u8 {}
		else { return error('chip-leakage aperture is not mapped by a direct call') }
	}
	proof(leak_code, 'G17 chip-leakage fuse decode')!
	descriptor_table := referenced_table(leak_address, leak_code, 0x170, 0x174, 8)!
	selector_table := referenced_table(leak_address, leak_code, 0x18c, 0x190, 12)!
	selector_bytes := descriptor_table - selector_table
	if selector_bytes != 0x20 {
		return error('unexpected chip-leakage core selector bytes 0x${selector_bytes:x}')
	}
	data := source.data()
	selector_offset := source.file_offset(selector_table)!
	checked_span(data, selector_offset, 32)!
	mut selectors := []u32{}
	for index in 0 .. 8 { selectors << image.u32_at(data, selector_offset + index * 4) }
	if selectors != [u32(0), 1, 2, 3, 0, 1, 2, 3] {
		return error('unexpected chip-leakage core selectors ${selectors}')
	}
	descriptor_offset := source.file_offset(descriptor_table)!
	mut descriptors := []j.Value{}
	expected := [[u32(0), 0x198, 8, 0x3fff, 0, 0, 0, 0], [u32(1), 0x198, 22, 0x3ff, 0x19c, 0, 0xf,
		10], [u32(1), 0x198, 22, 0x3ff, 0x19c, 0, 0xf, 10], [u32(0), 0x198, 8, 0x3fff, 0, 0, 0,
		0]]
	for index in 0 .. 4 {
		position := descriptor_offset + index * 0x28
		checked_span(data, position, 40)!
		mut fields := []u32{}
		for field in 0 .. 10 { fields << image.u32_at(data, position + field * 4) }
		actual := [u32(if fields[1] != 0 { 1 } else { 0 }), fields[2], fields[3], fields[4], fields[6],
			fields[7], fields[8], fields[9]]
		if actual != expected[index] { return error('G17 chip-leakage fuse descriptors changed') }
		descriptors << j.Value(map[string]j.Value{
			'index':                 j.Value(index)
			'record_bytes':          j.Value(0x28)
			'tag':                   j.Value(fields[0])
			'has_secondary':         j.Value(fields[1] != 0)
			'primary_word_offset':   j.Value(fields[2])
			'primary_shift':         j.Value(fields[3])
			'primary_mask':          j.Value(fields[4])
			'secondary_word_offset': j.Value(fields[6])
			'secondary_shift':       j.Value(fields[7])
			'secondary_mask':        j.Value(fields[8])
			'secondary_left_shift':  j.Value(fields[9])
		})
	}
	return {
		'die_dependent':                 j.Value(true)
		'producer':                      j.Value(linear_provider)
		'formula':                       j.Value('100 * (row_sum(state) - row_sum(base_state)) / (row_sum(maximum_state) - row_sum(base_state))')
		'maximum_state_value':           j.Value(100)
		'state_count_source_offset':     j.Value(0x1b310)
		'afr_state_count_source_offset': j.Value(0x1c4e8)
		'tables':                        j.Value([j.Value(map[string]j.Value{
			'offset':                      j.Value(0x18c8)
			'entries':                     j.Value(16)
			'base_state':                  j.Value(0)
			'matrix_source_offset':        j.Value(0x1c630)
			'matrix_row_bytes':            j.Value(0x40)
			'matrix_column_count_offset':  j.Value(0x4e4)
			'matrix_producer':             j.Value(main_provider)
			'matrix_producer_vtable_slot': j.Value(main_power_slot)
			'leakage':                     j.Value(vdd_leakage_provider)
			'voltage_exponent':            j.Value(j.Number{'1.28'})
			'dynamic_coefficient':         j.Value(j.Number{'20.15'})
			'clamp':                       j.Value(j.Number{'48500.0'})
		}), j.Value(map[string]j.Value{
			'offset':                      j.Value(0x1948)
			'entries':                     j.Value(16)
			'base_state':                  j.Value(0)
			'matrix_source_offset':        j.Value(0x1ca30)
			'matrix_row_bytes':            j.Value(8)
			'matrix_column_count_offset':  j.Value(0x4ec)
			'matrix_producer':             j.Value(afr_provider)
			'matrix_producer_vtable_slot': j.Value(afr_power_slot)
			'voltage_source_offset':       j.Value(0x1c538)
			'leakage':                     j.Value(afr_leakage_provider)
			'voltage_exponent':            j.Value(j.Number{'1.0'})
			'dynamic_coefficient':         j.Value([j.Value(j.Number{'21.7'}),
				j.Value(j.Number{'12.29'})])
			'clamp':                       j.Value([j.Value(j.Number{'38600.0'}),
				j.Value(j.Number{'24800.0'})])
			'chip_variant_offset':         j.Value(0x4a0)
		})])
		'chip_leakage':                  j.Value(map[string]j.Value{
			'producer':                   j.Value(chip_leakage_provider)
			'fuse_physical_address':      j.Value(physical)
			'fuse_bytes':                 j.Value(0x1000)
			'fuse_word_offsets':          j.Value([j.Value(0x198), j.Value(0x19c), j.Value(0x1a0)])
			'core_selector_table':        j.Value(selector_table)
			'core_selectors':             j.Value(selectors.map(j.Value(it)))
			'core_descriptors':           j.Value(descriptors)
			'variant_scales':             j.Value(map[string]j.Value{
				'0x21':      j.Value(map[string]j.Value{
					'primary_multiplier': j.Value(2)
					'secondary_divisor':  j.Value(2)
				})
				'other_g17': j.Value(map[string]j.Value{
					'primary_multiplier': j.Value(1)
					'secondary_divisor':  j.Value(4)
				})
			})
			'group_field':                j.Value(map[string]j.Value{
				'low_word_offset':  j.Value(0x19c)
				'high_word_offset': j.Value(0x1a0)
				'right_shift':      j.Value(25)
				'width':            j.Value(12)
				'multiplier':       j.Value(2)
			})
			'core_leakage_offset':        j.Value(0xe50)
			'core_leakage_second_offset': j.Value(0xed0)
			'group_leakage_offset':       j.Value(0xf20)
			'holder_member':              j.Value(0x5b0)
		})
		'leakage_model':                 j.Value(map[string]j.Value{
			'equation':       j.Value(equation_provider)
			'temperature':    j.Value(j.Number{'110.0'})
			'input_linear':   j.Value(true)
			'pow_terms':      j.Value(4)
			'factor_formula': j.Value('pow(2,(T-105)/c1) * pow(min(V,c7)/min(c7,.75),c4*(1-c5*(T-105)/20)) * min(V,c7,c6)/min(c7,c6,.75) * pow(1+c2*(1-c3*(T-105)/20),(max(V,c6)-max(c6,.75))/.05) * pow(c9,c8*max(V-1.06,0)*(1+c10*(T-105)^2/(T+273.15)))')
			'vdd_gpu':        j.Value(leakage_table(source, vdd_leakage_provider)!)
			'afr':            j.Value(leakage_table(source, afr_leakage_provider)!)
		})
	}
}

pub struct VariantRecords {
pub:
	uuid string
	vdd  [][]f64
	afr  [][]f64
}

pub fn recover_variant_records(data []u8) !VariantRecords {
	uuid := j.string_value(arm.macho_uuid(data)!)
	if uuid != arm.driver_uuid { return error('unsupported AGXG17X UUID ${uuid}') }
	_, code := arm.symbol_code(data, arm.init_power_data)!
	model := j.value(recover_linear_power_transfer_tables(data, code)!, 'leakage_model').as_map()
	if floating(j.value(model, 'temperature'))! != temperature_c {
		return error('G17 leakage-model temperature changed')
	}
	return VariantRecords{uuid, records(j.value(j.value(model, 'vdd_gpu').as_map(), 'variant_records'))!, records(j.value(j.value(model, 'afr').as_map(), 'variant_records'))!}
}

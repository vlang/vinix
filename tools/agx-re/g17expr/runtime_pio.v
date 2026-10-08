module g17expr

import math.big
import traceanalysis as j

fn runtime_pio(image CommandImage, operation string, request map[string]j.Value) !map[string]j.Value {
	if operation == 'recover_g17_pio_uat_mapping' { return pio_uat(image)! }
	symbols := runtime_required(image, ['BASE_CONFIGURE_DEVICE', 'G17_PIO_TABLE', 'G17_PIO_TABLE_LENGTH'])!
	selected_runtime_provider(image, symbols, 'G17_ACCELERATOR_VTABLE', runtime_number('G17_PIO_TABLE_VTABLE_SLOT'), 'G17_PIO_TABLE', 'unexpected G17 PIO table target ')!
	selected_runtime_provider(image, symbols, 'G17_ACCELERATOR_VTABLE', runtime_number('G17_PIO_TABLE_LENGTH_VTABLE_SLOT'), 'G17_PIO_TABLE_LENGTH', 'unexpected G17 PIO table length target ')!
	runtime_stub(image, 'G17_PIO_TABLE_LENGTH', [u32(0xd503245f), 0x52800260, 0xd65f03c0], true, 'unexpected G17 PIO table length provider')!
	address, code := image.code(runtime_symbol('G17_PIO_TABLE'))!
	if code.len < 16 { return error('truncated G17 PIO table provider') }
	if word32(code, 0)! != 0xd503245f || word32(code, 12)! != 0xd65f03c0 {
		return error('unexpected G17 PIO table provider prologue')
	}
	data_address := runtime_address_pair(address, code, 4, 8, 'G17 PIO table provider has no ADRP/add address', 'G17 PIO table provider uses an unexpected register', 0)!
	table := runtime_pio_table()
	offset := image.virtual(data_address)!
	if offset + big.integer_from_int(table.len * 0x20) > big.integer_from_int(image.bytes.len) {
		return error('truncated G17 PIO relative-offset table')
	}
	for index, expected in table {
		position := unpack_offset(image.bytes, offset + big.integer_from_int(index * 0x20), 32)!
		for field, value in expected {
			if word32(image.bytes, position + field * 4)! != value {
				return error('unexpected G17 PIO relative-offset table contents')
			}
		}
	}
	_, configure := image.code(runtime_symbol('BASE_CONFIGURE_DEVICE'))!
	runtime_check(configure, 'G17 PIO source producer')!
	mut records := []j.Value{}
	mut alternates := []j.Value{}
	for row in table {
		if row[1] != 0xffffffff {
			records << expr({
				'index':           j.Value(row[0])
				'relative_offset': j.Value(row[1])
				'total_size':      j.Value(row[2])
				'element_size':    j.Value(row[2])
				'flags':           j.Value(2)
				'writable':        j.Value(true)
			})
		} else {
			alternates << expr({
				'index':            j.Value(row[0])
				'primary_offset':   j.Value(row[1])
				'alternate_offset': j.Value(row[4])
				'alternate_size':   j.Value(row[5])
			})
		}
	}
	mut result := runtime_metadata(operation).as_map().clone()
	result['table_address'] = scalar(data_address)
	result['records'] = j.Value(records)
	result['alternate_entries'] = j.Value(alternates)
	return result
}

fn pio_uat(image CommandImage) !map[string]j.Value {
	symbols := runtime_required(image, ['ACCELERATOR_START', 'INIT_FIRMWARE_DATA',
		'CREATE_FW_PIO_MAPPING', 'CREATE_FW_GPU_MAPPING', 'GART_RANGES'])!
	address, start := image.code(runtime_symbol('ACCELERATOR_START'))!
	runtime_check(start, 'G17 GART range table initialization')!
	table := runtime_address_pair(address, start, 0xea4, 0xea8, 'G17 GART range table address is not materialized', 'G17 GART range table uses unexpected registers', 25)!
	if table != symbols[runtime_symbol('GART_RANGES')] {
		return error('unexpected G17 GART range table ' + command_hex(table))
	}
	offset := image.virtual(table + big.integer_from_int(10 * 0x20))!
	if offset + big.integer_from_int(32) > big.integer_from_int(image.bytes.len) {
		return error('truncated G17 firmware-PIO GART range')
	}
	position := unpack_offset(image.bytes, offset, 32)!
	expected := [u64(0xfffffc2180000000), 0x01400000, 0x18, 0]
	for index, value in expected {
		if word64(image.bytes, position + index * 8)! != value {
			return error('unexpected G17 firmware-PIO GART range')
		}
	}
	pio_address, pio := image.code(runtime_symbol('CREATE_FW_PIO_MAPPING'))!
	runtime_check(pio, 'G17 firmware-PIO physical alignment')!
	word32(pio, 0xb4)!
	target := branch_target('decode_bl_target', Instruction{ offset: pio_address + big.integer_from_int(0xb4), word: word32(pio, 0xb4)! })
	if actual := target {
		if actual != symbols[runtime_symbol('CREATE_FW_GPU_MAPPING')] {
			return error('unexpected G17 firmware-PIO mapper target ' + actual.str())
		}
	} else {
		return error('unexpected G17 firmware-PIO mapper target None')
	}
	_, gpu := image.code(runtime_symbol('CREATE_FW_GPU_MAPPING'))!
	runtime_check(gpu, 'G17 firmware-PIO mapping options')!
	_, init := image.code(runtime_symbol('INIT_FIRMWARE_DATA'))!
	runtime_seq(init, 'G17 firmware-PIO virtual-address publication')!
	runtime_seq(init, 'G17 firmware-PIO mapped-address conversion')!
	return runtime_metadata('recover_g17_pio_uat_mapping').as_map()
}

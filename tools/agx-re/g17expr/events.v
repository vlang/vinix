module g17expr

import g17decode as arm
import g17power as power
import json2
import math
import math.big
import traceanalysis as j

fn event_handles(operation string) bool {
	return operation in ['g17_callback_interrupt_index', 'recover_g17_akf_callback',
		'recover_g17_firmware_event_ring', 'recover_g17_pm_memory_event_action',
		'recover_g17_uma_flist_event_actions', 'recover_g17_uma_async_alloc_event_action',
		'recover_g17_firmware_event_actions', 'recover_g17_firmware_event_validators']
}

fn event_check(code []u8, label string) ! {
	arm.require_instruction_words_at(code, label, event_words(label))!
}

fn event_names(names []string) []string { return names.map(event_symbol(it)) }

fn event_required(symbols map[string]j.Value, names []string, prefix string, grouped bool) ! {
	mut missing := []j.Value{}
	for name in event_names(names) { if name !in symbols { missing << j.Value(name) } }
	if missing.len > 0 {
		return error(prefix + if grouped {
			j.string_value(j.Value(missing))
		} else {
			j.string_value(missing[0]) + ' symbol'
		})
	}
}

fn event_target(symbols map[string]j.Value, name string) !j.Value {
	key := event_symbol(name)
	return symbols[key] or { return error('KeyError: ' + key) }
}

fn event_noop(code []u8, message string) ! {
	if code != encoded_words([u32(0xd503245f), 0xd65f03c0]) { return error(message) }
}

fn event_call(address big.Integer, code []u8, offset int, symbols map[string]j.Value, name string, message string, tail bool) ! {
	instruction := Instruction{ offset: address + big.integer_from_int(offset), word: word32(code, offset)! }
	target := event_target(symbols, name)!
	actual := branch_target(if tail { 'decode_b_target' } else { 'decode_bl_target' }, instruction) or { return error(message) }
	if !event_values_equal(scalar(actual), target) { return error(message) }
}

fn event_address(address big.Integer, code []u8, adrp int, add int) !big.Integer {
	return big.integer_from_u64(arm.read_adrp_add_address(scalar(address), code, adrp, add)!)
}

fn event_cstring(image CommandImage, address big.Integer, code []u8, adrp int, add int, request map[string]j.Value) !string {
	if image.fixture {
		values := at(at(request, 'driver_fixture').as_map(), 'cstrings').as_map()
		key := '${address.str()}:${adrp}:${add}'
		return j.string_value(values[key] or { return error('KeyError: ' + key) })
	}
	return arm.read_adrp_add_cstring(image.bytes, scalar(address), code, adrp, add)
}

fn event_table(image CommandImage, address big.Integer, count int, request map[string]j.Value) ![]j.Value {
	if image.fixture {
		values := at(at(request, 'driver_fixture').as_map(), 'u32_tables').as_map()
		key := '${address.str()}:${count}'
		return (values[key] or { return error('KeyError: ' + key) }).arr()
	}
	return arm.read_virtual_u32_table(image.bytes, address, big.integer_from_int(count))!.map(j.Value(it))
}

fn event_symbols(request map[string]j.Value, key string) !map[string]j.Value {
	return at(request, key).as_map()
}

fn event_dispatch_offsets(request map[string]j.Value) ![]j.Value {
	return at(request, 'dispatch_offsets').arr()
}

fn event_dispatch(offsets []j.Value, index int, expected int, message string) ! {
	if index >= offsets.len { return error('IndexError: dispatch offset index out of range') }
	if !event_values_equal(offsets[index], j.Value(expected - 0x110)) { return error(message) }
}

fn callback_interrupt_index(value j.Value) !int {
	match value {
		bool {
			if value { return 0 }
		}
		j.Number {
			if value.text.contains_any('.eE') || value.text in ['NaN', 'Infinity', '-Infinity'] {
				text := value.text.clone()
				number := unsafe { C.strtod(&char(text.str), nil) }
				if number >= 5 && number <= 8 { return 4 }
			} else {
				number := arm.integer(value)!
				if number >= big.integer_from_int(5) && number <= big.integer_from_int(8) {
					return 4
				}
			}
		}
		int, i64, u8, u32, u64 {
			number := arm.integer(value)!
			if number >= big.integer_from_int(5) && number <= big.integer_from_int(8) { return 4 }
		}
		else {
			kind := match value {
				json2.Null { 'NoneType' }
				string { 'str' }
				[]j.Value { 'list' }
				map[string]j.Value { 'dict' }
				else { 'object' }
			}
			return error("TypeError: '<=' not supported between instances of 'int' and '" + kind + "'")
		}
	}
	if runtime_equal(value, 1) || runtime_equal(value, 4) { return 0 }
	return error('unsupported AGX interrupt count ' + j.string_value(runtime_repr_value(value)))
}

fn akf_callback(driver CommandImage, kernel CommandImage) !j.Value {
	driver_symbols := event_image_symbols(driver)!
	kernel_symbols := event_image_symbols(kernel)!
	event_required(driver_symbols, ['RECEIVED_MESSAGE_FROM_AKF', 'ACCELERATOR_START',
		'BASE_CONFIGURE_DEVICE', 'ACCELERATOR_HANDLE_INTERRUPT', 'FIRMWARE_HANDLE_EVENT',
		'FIRMWARE_DRAIN_EVENT_RING', 'G17_CLEAR_FIRMWARE_INTERRUPTS', 'G17_FIRMWARE_VTABLE',
		'DRAIN_FIRMWARE_RINGS'], 'driver Mach-O has no ', false)!
	event_required(kernel_symbols, ['IOFILTER_INTERRUPT_EVENT_SOURCE_VTABLE',
		'IOFILTER_INTERRUPT_EVENT_SOURCE_FACTORY', 'IOFILTER_SIGNAL_INTERRUPT', 'IOINTERRUPT_GET_INDEX'], 'kernel Mach-O has no ', false)!
	_, receive := driver.code(event_symbol('RECEIVED_MESSAGE_FROM_AKF'))!
	start_address, start := driver.code(event_symbol('ACCELERATOR_START'))!
	_, configure := driver.code(event_symbol('BASE_CONFIGURE_DEVICE'))!
	_, interrupt := driver.code(event_symbol('ACCELERATOR_HANDLE_INTERRUPT'))!
	event_address, event_code := driver.code(event_symbol('FIRMWARE_HANDLE_EVENT'))!
	event_check(receive, 'G17 type-2 callback dispatch')!
	event_check(start, 'G17 interrupt-event-source construction')!
	event_call(start_address, start, 0x35fc, kernel_symbols, 'IOFILTER_INTERRUPT_EVENT_SOURCE_FACTORY',
		'G17 interrupt source is not created by the checked factory', false)!
	event_check(configure, 'G17 callback interrupt selection')!
	event_check(interrupt, 'G17 interrupt action forwarding')!
	event_check(event_code, 'G17 firmware-ring callback event')!
	event_call(event_address, event_code, 0x1b8, driver_symbols, 'DRAIN_FIRMWARE_RINGS',
		'G17 callback event no longer drains firmware rings', true)!
	for slot, name in {
		0x1e8: 'IOINTERRUPT_GET_INDEX'
		0x258: 'IOFILTER_SIGNAL_INTERRUPT'
	} {
		if !event_values_equal(event_vtable(kernel, event_symbol('IOFILTER_INTERRUPT_EVENT_SOURCE_VTABLE'), slot)!, event_target(kernel_symbols, name)!) {
			return error('unexpected IOFilterInterruptEventSource slot 0x${slot:x} target')
		}
	}
	for slot, name in {
		0x328: 'FIRMWARE_HANDLE_EVENT'
		0x880: 'G17_CLEAR_FIRMWARE_INTERRUPTS'
		0x888: 'FIRMWARE_DRAIN_EVENT_RING'
	} {
		if !event_values_equal(event_vtable(driver, event_symbol('G17_FIRMWARE_VTABLE'), slot)!, event_target(driver_symbols, name)!) {
			return error('unexpected G17 firmware slot 0x${slot:x} target')
		}
	}
	_, clear := driver.code(event_symbol('G17_CLEAR_FIRMWARE_INTERRUPTS'))!
	event_noop(clear, 'G17 clearOutstandingFirmwareInterrupts is no longer a no-op')!
	return event_metadata('recover_g17_akf_callback')
}

fn firmware_event_validators(driver CommandImage, address big.Integer, code []u8, request map[string]j.Value) !map[string]j.Value {
	mut recovered := map[string]j.Value{}
	for row in event_validator_records().arr() {
		fields := row.arr()
		event_type := fields[0].int()
		reference := fields[1].int()
		record := j.string_value(fields[2])
		enum_name := j.string_value(fields[3])
		actual := event_cstring(driver, address, code, reference, reference + 4, request)!
		expected := 'const RET *AGXFirmwareRingValidator::validateType(const AGFIFirmwareEventRingEntry *) const [RET = ' + record + ', FWET1 = ' + enum_name + ', FWET2 = kAGFIFirmwareEventNone]'
		if actual != expected {
			return error('G17 firmware event type ${event_type} validator identity changed')
		}
		recovered[event_type.str()] = expr({
			'record': j.Value(record)
			'enum':   j.Value(enum_name)
		})
	}
	return recovered
}

fn event_query(data []u8, operation string, request map[string]j.Value) !j.Value {
	if 'event_options_text' in request {
		return event_query(data, operation, power.decode_device_json(text(request, 'event_options_text'))!.as_map())
	}
	if operation == 'g17_callback_interrupt_index' {
		value := if 'interrupt_count_text' in request {
			power.decode_device_json(text(request, 'interrupt_count_text'))!
		} else {
			at(request, 'interrupt_count')
		}
		return j.Value(callback_interrupt_index(value)!)
	}
	driver := command_image(data, request, 'driver')!
	if operation == 'recover_g17_akf_callback' {
		return akf_callback(driver, command_image(runtime_bytes(request, 'kernel')!, request, 'kernel')!)
	}
	if operation == 'recover_g17_firmware_event_ring' {
		return firmware_event_ring(driver, command_image(runtime_bytes(request, 'iogpu')!, request, 'iogpu')!, command_image(runtime_bytes(request, 'iosurface')!, request, 'iosurface')!, request)
	}
	address := arm.integer(at(request, 'role_address'))!
	code := runtime_bytes(request, 'role_code')!
	if operation == 'recover_g17_firmware_event_validators' {
		return expr(firmware_event_validators(driver, address, code, request)!)
	}
	offsets := event_dispatch_offsets(request)!
	symbols := event_symbols(request, 'driver_symbols')!
	return event_action_query(driver, address, code, offsets, symbols, operation, request) or {
		if err.msg() == 'IndexError: dispatch offset index out of range' {
			return error('IndexError: ' + if text(request, 'dispatch_offsets_kind') == 'tuple' {
				'tuple'
			} else {
				'list'
			} + ' index out of range')
		}
		return error(err.msg())
	}
}

fn event_image_symbols(image CommandImage) !map[string]j.Value {
	if image.fixture { return image.symbol_addresses }
	mut result := map[string]j.Value{}
	for name, address in image.provider.symbols()! { result[name] = j.Value(address) }
	return result
}

fn event_vtable(image CommandImage, name string, slot int) !j.Value {
	if image.fixture {
		return image.vtable_targets[name + ':' + slot.str()] or { return error('KeyError: ' + name + ':' + slot.str()) }
	}
	return scalar(image.vtable(name, slot)!)
}

fn event_values_equal(left j.Value, right j.Value) bool {
	left_kind := runtime_allocation_type(left)
	right_kind := runtime_allocation_type(right)
	if left_kind in ['int', 'float', 'bool'] && right_kind in ['int', 'float', 'bool'] {
		if left_kind == 'float' && right_kind == 'float' {
			left_text := j.encode(left, false)
			right_text := j.encode(right, false)
			return unsafe { C.strtod(&char(left_text.str), nil) } == unsafe { C.strtod(&char(right_text.str), nil) }
		}
		floating := if left_kind == 'float' { left } else { right }
		if left_kind == 'float' || right_kind == 'float' {
			text := j.encode(floating, false)
			value := unsafe { C.strtod(&char(text.str), nil) }
			if !math.is_finite(value) || math.fmod(value, 1) != 0 { return false }
		}
		return (power.decimal_integer(left) or { return false }) == (power.decimal_integer(right) or { return false })
	}
	return left == right
}

fn event_role_greater_than_one(value j.Value) !bool {
	match value {
		j.Number {
			if runtime_allocation_type(value) == 'float' {
				text := value.text.clone()
				return unsafe { C.strtod(&char(text.str), nil) } > 1
			}
			return arm.integer(value)! > big.integer_from_int(1)
		}
		bool { return false }
		int, i64, u8, u32, u64 { return arm.integer(value)! > big.integer_from_int(1) }
		else {
			kind := match value {
				string { 'str' }
				[]j.Value { 'list' }
				map[string]j.Value { 'dict' }
				else { 'NoneType' }
			}
			return error("TypeError: '>' not supported between instances of '" + kind + "' and 'int'")
		}
	}
}

fn event_add_offset(address big.Integer, value j.Value) !j.Value {
	if runtime_allocation_type(value) == 'float' {
		text := j.encode(value, false)
		result := event_float_address(address + big.integer_from_int(0x110))! + unsafe { C.strtod(&char(text.str), nil) } - event_float_address(address)!
		if math.is_nan(result) { return j.Value(j.Number{'NaN'}) }
		if math.is_inf(result, 0) {
			return j.Value(j.Number{if result < 0 { '-Infinity' } else { 'Infinity' }})
		}
		mut token := '${result:.17g}'
		if !token.contains_any('.eE') { token += '.0' }
		return j.Value(j.Number{token})
	}
	return scalar(power.decimal_integer(value)! + big.integer_from_int(0x110))
}

fn event_action_query(driver CommandImage, address big.Integer, code []u8, offsets []j.Value, symbols map[string]j.Value, operation string, request map[string]j.Value) !j.Value {
	match operation {
		'recover_g17_pm_memory_event_action' {
			return pm_memory_event(driver, address, code, offsets, symbols, request)
		}
		'recover_g17_uma_flist_event_actions' {
			return uma_flist_events(driver, address, code, offsets, symbols)
		}
		'recover_g17_uma_async_alloc_event_action' {
			return uma_async_alloc_event(driver, address, code, offsets, symbols)
		}
		else {
			return expr(firmware_event_actions(driver, address, code, offsets, symbols, event_symbols(request, 'iogpu_symbols')!, event_symbols(request, 'iosurface_symbols')!, request)!)
		}
	}
}

fn event_float_address(address big.Integer) !f64 {
	text := address.str()
	value := unsafe { C.strtod(&char(text.str), nil) }
	if !math.is_finite(value) { return error('OverflowError: int too large to convert to float') }
	return value
}

fn event_role_dispatch(address big.Integer, offsets []j.Value, index int, expected int, message string) ! {
	if index >= offsets.len { return error('IndexError: dispatch offset index out of range') }
	value := offsets[index]
	if runtime_allocation_type(value) == 'float' {
		text := j.encode(value, false)
		actual := event_float_address(address + big.integer_from_int(0x110))! + unsafe { C.strtod(&char(text.str), nil) }
		if !math.is_finite(actual) { return error(message) }
		if !event_values_equal(j.Value(j.Number{'${actual:.17g}'}), scalar(address + big.integer_from_int(expected))) {
			return error(message)
		}
		return
	}
	event_dispatch(offsets, index, expected, message)!
}

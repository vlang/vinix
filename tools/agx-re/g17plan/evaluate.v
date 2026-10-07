module g17plan

import traceanalysis { Value }
import math.big

pub fn load(buffer []u8, offset int, bytes int, signed bool) !u64 {
	if offset < 0 || bytes !in [1, 2, 4, 8] || offset > buffer.len - bytes {
		return error('load [${hex_offset(offset)}, ${hex_sum(offset, bytes)}) is outside a 0x${buffer.len:x}-byte buffer')
	}
	mut value := u64(0)
	for i in 0 .. bytes { value |= u64(buffer[offset + i]) << (i * 8) }
	if signed && value >> (bytes * 8 - 1) != 0 { value |= ~mask_bits(bytes * 8) }
	return value
}

fn hex_offset(n int) string {
	number := big.integer_from_i64(i64(n))
	return if number < big.zero_int { '-0x' + number.abs().hex() } else { '0x' + number.hex() }
}

fn hex_sum(a int, b int) string {
	number := big.integer_from_i64(i64(a)) + big.integer_from_i64(i64(b))
	return if number < big.zero_int { '-0x' + number.abs().hex() } else { '0x' + number.hex() }
}

fn shift(value u64, kind Value, amount int, bits int) !u64 {
	if !left_shift_kind(kind) && kind != Value('lsr') {
		return unresolved('unsupported shift ${repr(kind)}')
	}
	if amount < 0 { return error('negative shift count') }
	masked := value & mask_bits(bits)
	if kind == Value('lsr') { return if amount >= bits { u64(0) } else { masked >> amount } }
	if left_shift_kind(kind) {
		return if amount >= bits { u64(0) } else { (masked << amount) & mask_bits(bits) }
	}
	return unresolved('unsupported shift ${repr(kind)}')
}

fn ror(value u64, amount int, bits int) u64 {
	rotation := ((amount % bits) + bits) % bits
	masked := value & mask_bits(bits)
	if rotation == 0 { return masked }
	return ((masked >> rotation) | (masked << (bits - rotation))) & mask_bits(bits)
}

fn replicate(value u64, element int, bits int) u64 {
	mut result := u64(0)
	for n := 0; n < bits; n += element { result |= value << n }
	return result
}

fn bit_masks(rotate int, end int, bits int) !(u64, u64) {
	combined := ((if bits == 64 { 1 } else { 0 }) << 6) | ((~end) & 0x3f)
	mut length := -1
	for n := combined; n > 0; n >>= 1 { length++ }
	if length < 1 { return unresolved('reserved UBFM/BFM mask') }
	levels := (1 << length) - 1
	s := end & levels
	r := rotate & levels
	difference := (s - r) & levels
	element := 1 << length
	return replicate(ror(mask_bits(s + 1), r, element), element, bits), replicate(mask_bits(difference + 1), element, bits)
}

fn command_root(node map[string]Value) ! {
	kind := text(node, 'kind')
	if kind == 'argument' && text(node, 'name') == 'command' { return }
	if kind == 'stack_reload' {
		command_root(required_obj(node, 'source')!)!
		return
	}
	if kind == 'expression' && text(node, 'operation') in ['copy', 'register_copy'] {
		command_root(default_value(node, 'source', val(node, 'expression')).as_map())!
		return
	}
	return unresolved('object base rooted in ${if kind == '' { 'unknown' } else { kind }}')
}

pub fn normalize_predicate(node map[string]Value) !map[string]Value {
	if 'source' in node || 'first' !in node { return node }
	mut output := map[string]Value{}
	for key, value in node {
		if key !in ['first', 'second', 'shift', 'modifier', 'amount'] { output[key] = value }
	}
	output['source'] = required(node, 'first')!
	mut second := required(node, 'second')!
	amount := int_value(default_value(node, 'amount', Value(0)), 'compare shift amount')!
	if amount != 0 {
		second = map[string]Value{
			'kind':      Value('expression')
			'operation': Value('orr')
			'bytes':     default_value(node, 'bytes', Value(8))
			'first':     Value(map[string]Value{
				'kind':  Value('constant')
				'value': Value(0)
			})
			'second':    second
			'shift':     default_value(node, 'shift', val(node, 'modifier'))
			'amount':    Value(amount)
		}
	}
	output['second'] = second
	return output
}

fn compare(a u64, b u64, condition string) ?bool {
	return match condition {
		'eq', 'zero' { a == b }
		'ne', 'nonzero' { a != b }
		'hi' { a > b }
		'ls' { a <= b }
		'cc', 'lo' { a < b }
		'cs', 'hs' { a >= b }
		else { none }
	}
}

pub fn condition(node map[string]Value, condition string, descriptor []u8, command []u8) !bool {
	predicate := normalize_predicate(node)!
	operation := text(predicate, 'operation')
	mask := width_mask(expression_width(predicate, 'predicate bytes')!)!
	source := evaluate(required(predicate, 'source')!, descriptor, command)! & mask
	if operation in ['cmp', 'compare_zero', 'tst'] {
		other := (if 'second' in predicate {
			evaluate(val(predicate, 'second'), descriptor, command)!
		} else {
			masked_integer(if operation == 'tst' {
				required(predicate, 'immediate')!
			} else {
				default_value(predicate, 'immediate', Value(0))
			}, if operation == 'tst' {
				'test immediate'
			} else {
				'compare immediate'
			})!
		}) & mask
		if operation == 'tst' {
			if condition in ['eq', 'ne'] {
				return if condition == 'eq' { source & other == 0 } else { source & other != 0 }
			}
		} else {
			if result := compare(source, other, condition) { return result }
		}
	} else if operation == 'test_bit' {
		bit := field(predicate, 'bit', 'tested bit')!
		if bit < 0 { return error('negative shift count') }
		set := bit < 64 && (source >> bit) & 1 != 0
		if condition in ['bit_set', 'bit_clear'] {
			return if condition == 'bit_set' { set } else { !set }
		}
	} else {
		return unresolved('unsupported predicate operation ${repr(val(predicate, 'operation'))}')
	}
	return unresolved('unsupported condition ${repr(Value(condition))} for ${repr(Value(operation))}')
}

pub fn evaluate(item Value, descriptor []u8, command []u8) !u64 {
	node := match item {
		map[string]Value { item }
		else { return error('value expression node must be an object') }
	}
	kind := text(node, 'kind')
	match kind {
		'constant', 'constant_call' {
			return masked_integer(required(node, 'value')!, 'constant value')!
		}
		'descriptor_load' {
			return load(descriptor, field(node, 'member', 'descriptor member')!, field(node, 'bytes', 'descriptor load width')!, truth(val(node, 'signed')))
		}
		'stack_reload' { return evaluate(required(node, 'source')!, descriptor, command) }
		'computed' { return evaluate(required(node, 'expression')!, descriptor, command) }
		'object_load' {
			command_root(required_obj(node, 'base')!)!
			return load(command, field(node, 'member', 'object member')!, field(node, 'bytes', 'object load width')!, truth(val(node, 'signed')))
		}
		'hardware_input' {
			return unresolved('value needs hardware input ${repr(val(node, 'name'))}')
		}
		'argument', 'virtual_load', 'call_result', 'channel_load', 'accelerator_load' {
			return unresolved('value rooted in external ${kind}')
		}
		else {
			if kind != 'expression' {
				return unresolved('unsupported value kind ${repr(val(node, 'kind'))}')
			}
		}
	}
	operation := text(node, 'operation')
	if operation in ['logical_immediate', 'logical_register', 'conditional', 'bitfield', 'register_copy'] {
		return evaluate(required(node, 'expression')!, descriptor, command)
	}
	bytes := expression_width(node, 'expression bytes')!
	mask := width_mask(bytes)!
	bits := bytes * 8
	if operation == 'copy' {
		return evaluate(required(node, 'source')!, descriptor, command)! & mask
	}
	if operation == 'multiway_select' {
		selector := evaluate(required(node, 'selector')!, descriptor, command)!
		for raw in val(node, 'cases').arr() {
			c := raw.as_map()
			if selector == masked_integer(required(c, 'equals')!, 'case value')! {
				return evaluate(required(c, 'value')!, descriptor, command)! & mask
			}
		}
		return evaluate(required(node, 'default')!, descriptor, command)! & mask
	}
	if operation in ['csel', 'csinc', 'branch_select'] {
		outcome := condition(required_obj(node, 'predicate')!, text(node, 'condition'), descriptor, command)!
		first := if operation == 'branch_select' { 'taken' } else { 'first' }
		second := if operation == 'branch_select' { 'fallthrough' } else { 'second' }
		value := evaluate(required(node, if outcome { first } else { second })!, descriptor, command)!
		return (value + if operation == 'csinc' && !outcome { u64(1) } else { u64(0) }) & mask
	}
	if operation == 'movk' {
		amount := field(node, 'shift', 'MOVK shift')!
		source := evaluate(required(node, 'source')!, descriptor, command)! & mask
		immediate := masked_integer(required(node, 'immediate')!, 'MOVK immediate')! & 0xffff
		return ((source & ~shift(0xffff, Value('lsl'), amount, 64)!) | shift(immediate, Value('lsl'), amount, 64)!) & mask
	}
	if operation in ['ubfm', 'bfm'] {
		source := evaluate(required(node, 'source')!, descriptor, command)! & mask
		rotate := field(node, 'rotate', 'bitfield rotate')!
		wmask, tmask := bit_masks(rotate, field(node, 'mask_end', 'bitfield mask end')!, bits)!
		bottom := ror(source, rotate, bits) & wmask
		if operation == 'ubfm' { return bottom & tmask }
		destination := evaluate(required(node, 'destination')!, descriptor, command)! & mask
		return ((destination & ~tmask) | (((destination & ~wmask) | bottom) & tmask)) & mask
	}
	mut first := u64(0)
	mut second := u64(0)
	if 'source' in node {
		first = evaluate(val(node, 'source'), descriptor, command)!
		second = masked_integer(default_value(node, 'immediate', default_value(node, 'mask', Value(0))), 'immediate')!
	} else {
		first = evaluate(required(node, 'first')!, descriptor, command)!
		second = shift(evaluate(required(node, 'second')!, descriptor, command)!, default_value(node, 'shift', val(node, 'modifier')), int_value(default_value(node, 'amount', Value(0)), 'shift amount')!, bits)!
	}
	return match operation {
		'add' { (first + second) & mask }
		'sub' { (first - second) & mask }
		'and' { (first & second) & mask }
		'orr' { (first | second) & mask }
		'orn' { (first | ~second) & mask }
		'bic' { (first & ~second) & mask }
		'multiply' {
			(first * masked_integer(default_value(node, 'factor', Value(second)), 'multiply factor')!) & mask
		}
		else {
			return unresolved('unsupported expression operation ${repr(val(node, 'operation'))}')
		}
	}
}

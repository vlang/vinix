module g17expr

import g17decode as arm
import traceanalysis as j
import math.big
import strconv

pub struct Visit {
pub:
	use_index int
	register  int
}

pub interface ImageSource {
	symbols() !map[string]u64
	code(name string) !(u64, []u8)
}

pub struct DriverImage {
pub:
	bytes []u8
}

pub fn (source DriverImage) symbols() !map[string]u64 { return arm.macho_symbols(source.bytes) }

pub fn (source DriverImage) code(name string) !(u64, []u8) {
	return arm.symbol_code(source.bytes, name)
}

fn fields(name string, word u32, offset big.Integer) ?[]j.Value {
	value := arm.decode(name, word, scalar(offset))
	return match value {
		[]j.Value { value }
		else { none }
	}
}

fn decoded_object(name string, word u32) ?map[string]j.Value {
	value := arm.decode(name, word, j.Value(0))
	return match value {
		map[string]j.Value { value }
		else { none }
	}
}

fn branch_target(name string, instruction Instruction) ?big.Integer {
	value := arm.decode(name, instruction.word, scalar(instruction.offset))
	return match value {
		j.Number, u64, u32, u8, i64, int { arm.integer(value) or { return none } }
		else { none }
	}
}

fn constant(value u64) map[string]j.Value {
	return map[string]j.Value{
		'kind':  j.Value('constant')
		'value': j.Value(value)
	}
}

fn at(node map[string]j.Value, key string) j.Value {
	return j.value(node, key)
}

fn text(node map[string]j.Value, key string) string { return j.string_value(at(node, key)) }

fn number(node map[string]j.Value, key string) int { return integer(at(node, key)) }

fn object(value j.Value) ?map[string]j.Value {
	return match value {
		map[string]j.Value { value }
		else { none }
	}
}

fn expr(node map[string]j.Value) j.Value { return j.Value(node) }

fn copy(node map[string]j.Value) map[string]j.Value {
	return node.clone()
}

fn call(instruction Instruction) bool {
	if _ := branch_target('decode_bl_target', instruction) { return true }
	return instruction.word & 0xfffffc00 == 0xd73f0800
}

fn last_write(instructions []Instruction, use_index int, register int) ?int {
	for index := use_index - 1; index >= 0; index-- {
		if arm.register_is_written(instructions[index].word, register) { return index }
	}
	return none
}

fn position(instructions []Instruction, offset big.Integer) ?int {
	for index, instruction in instructions {
		if instruction.offset == offset { return index }
	}
	return none
}

fn use_offset(instructions []Instruction, use_index int) big.Integer {
	return if use_index < instructions.len {
		instructions[if use_index < 0 { instructions.len + use_index } else { use_index }].offset
	} else {
		instructions.last().offset + big.integer_from_int(4)
	}
}

fn source_expression(instructions []Instruction, index int, register int, depth int, seen []Visit) ?map[string]j.Value {
	if register == 31 { return constant(0) }
	return value_expression(instructions, index, register, depth, seen)
}

fn integer(value j.Value) int {
	return int(strconv.parse_int(j.string_value(value), 10, 64) or { panic(err) })
}

fn scalar(value big.Integer) j.Value { return j.Value(j.Number{value.str()}) }

fn target_is(name string, instruction Instruction, offset big.Integer) bool {
	target := branch_target(name, instruction) or { return false }
	return target == offset
}

fn instruction_block(instructions []Instruction, start int, end int) []Instruction {
	limit := if end < instructions.len { end } else { instructions.len }
	return instructions[start..limit]
}

fn conditional_is(instruction Instruction, target big.Integer, condition string) bool {
	decoded := fields('decode_conditional_branch', instruction.word, instruction.offset) or { return false }
	return (arm.integer(decoded[0]) or { return false }) == target && j.string_value(decoded[1]) == condition
}

fn value_is_target(value j.Value, target big.Integer) bool {
	return (arm.integer(value) or { return false }) == target
}

fn decoded_object_at(name string, instruction Instruction) ?map[string]j.Value {
	value := arm.decode(name, instruction.word, scalar(instruction.offset))
	return match value {
		map[string]j.Value { value }
		else { none }
	}
}

// Instruction byte addresses are arbitrary precision like the original
// analysis API; loop positions and architectural register widths remain native.
pub struct Instruction {
pub:
	offset     big.Integer
	word       u32
	exact_word bool = true
	full_word  big.Integer
}

fn instructions_from_code(code []u8) []Instruction {
	return arm.words(code).map(Instruction{ offset: big.integer_from_int(it.offset), word: it.word })
}

fn offset_hex(offset big.Integer) string {
	return if offset.signum < 0 { '-' + offset.abs().radix_str(16) } else { offset.radix_str(16) }
}

fn page_base(offset big.Integer) big.Integer {
	page := big.integer_from_int(4096)
	mut remainder := offset % page
	if remainder.signum < 0 { remainder += page }
	return offset - remainder
}

fn native_static_instructions(instructions []Instruction, before int) []arm.Instruction {
	low := big.integer_from_int(0)
	high := big.integer_from_string('9223372036854775807') or { panic(err) }
	if instructions.all(it.offset >= low && it.offset <= high - big.integer_from_int(0x8000000)) {
		return instructions.map(arm.Instruction{int(strconv.parse_int(it.offset.str(), 10, 64) or { panic(err) }), it.word})
	}
	// The static resolver only compares a wrapped B target with a use offset.
	// Rank those exact integers to retain that ordering beyond native widths.
	mut values := instructions.map(it.offset)
	mut targets := map[int]big.Integer{}
	for index, item in instructions {
		if target := branch_target('decode_b_target', item) {
			targets[index] = target
			values << target
		}
	}
	values.sort(a < b)
	pivot := big.integer_from_u64(u64(1) << 63)
	values << pivot
	values.sort(a < b)
	mut ranks := map[string]u64{}
	for value in values {
		key := value.str()
		if key !in ranks {
			ranks[key] = if value < pivot {
				u64(ranks.len + 1)
			} else if value == pivot {
				u64(1) << 63
			} else {
				(u64(1) << 63) + u64(ranks.len + 1)
			}
		}
	}
	mut result := []arm.Instruction{cap: instructions.len}
	for index, item in instructions {
		mut offset := ranks[item.offset.str()]
		if target := targets[index] {
			// decode_b_target at zero supplies the signed displacement modulo64.
			displacement := i64((item.word & 0x3ffffff) ^ 0x2000000) - 0x2000000
			offset = ranks[target.str()] - u64(displacement * 4)
		}
		if index == before { offset = ranks[item.offset.str()] }
		result << arm.Instruction{int(offset), item.word}
	}
	return result
}

fn static_w_register(instructions []Instruction, before int, register int, depth int) ?u64 {
	return arm.resolve_static_w_register(native_static_instructions(instructions, before), before, register, depth)
}

fn static_x_register(instructions []Instruction, before int, register int, depth int) ?u64 {
	return arm.resolve_static_x_register(native_static_instructions(instructions, before), before, register, depth)
}

fn instruction_word(item Instruction) j.Value {
	return if item.exact_word { j.Value(item.word) } else { scalar(item.full_word) }
}

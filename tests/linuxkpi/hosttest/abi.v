// SPDX-License-Identifier: GPL-2.0-or-later
// Structured native compiler-boundary metadata, without implementation bodies.
module hosttest

import os
import json2
import math.big
import encoding.utf8

#include <stdlib.h>
fn C.strtod(&char, &&char) f64

struct AbiNumber {
mut:
	raw string
}

fn (mut number AbiNumber) from_json_number(raw string) ! { number.raw = raw }

// Keep arbitrary integer tokens: compiler constants may exceed both 64-bit
// native ranges. Their type is retained separately from strings and booleans.
type AbiValue = []AbiValue | bool | map[string]AbiValue | string | AbiNumber | json2.Null

fn abi_object(value AbiValue) !map[string]AbiValue {
	if value is map[string]AbiValue { return value }
	return error('Expected native ABI metadata object')
}

fn abi_array(value AbiValue) ![]AbiValue {
	if value is []AbiValue { return value }
	return error('Expected native ABI metadata list')
}

fn abi_string(value AbiValue) !string {
	if value is string { return value }
	return error('Expected native ABI metadata string')
}

fn abi_field(metadata map[string]AbiValue, key string) !AbiValue {
	return metadata[key] or { return error('Missing native ABI metadata field: ${key}') }
}

fn abi_unique(values []string) []string {
	mut result := []string{}
	for value in values { if value !in result { result << value } }
	return result
}

fn abi_text(metadata map[string]AbiValue, key string) !string { return abi_string(abi_field(metadata, key)!)! }
fn abi_list(metadata map[string]AbiValue, key string) ![]AbiValue { return abi_array(abi_field(metadata, key)!)! }
fn abi_optional_list(metadata map[string]AbiValue, key string) ![]AbiValue {
	if key !in metadata { return []AbiValue{} }
	return abi_list(metadata, key)!
}

fn abi_keys(metadata map[string]AbiValue, keys []string) bool {
	return metadata.len == keys.len && keys.all(it in metadata)
}

fn abi_identifier(value AbiValue) !string {
	text := abi_string(value)!
	if text.len == 0 || !(text[0].is_letter() || text[0] == `_`) {
		return error('Invalid native identifier: ${text}')
	}
	for ch in text.runes() {
		if ch != `_` && !utf8.is_letter(ch) && !utf8.is_number(ch) { return error('Invalid native identifier: ${text}') }
	}
	return text
}

fn abi_name(metadata map[string]AbiValue, key string) !string { return abi_identifier(abi_field(metadata, key)!)! }

fn abi_integer(value AbiValue) !string {
	if value is AbiNumber {
		if value.raw.contains('.') || value.raw.contains('e') || value.raw.contains('E') { return error('Invalid native constant') }
		number := big.integer_from_string(value.raw)!
		if number < big.integer_from_int(0) { return error('Invalid native constant') }
		return number.str()
	}
	return error('Invalid native constant')
}

fn abi_numeric_equal(value AbiValue, expected int) bool {
	return match value {
		// Python's JSON floats use binary64 decimal conversion. Use the
		// platform's correctly rounded conversion for metadata equality;
		// integer compiler literals retain their separate exact big integers.
		AbiNumber { unsafe { C.strtod(value.raw.str, nil) } == f64(expected) }
		bool { (if value { 1 } else { 0 }) == expected }
		else { false }
	}
}

fn abi_native_type(value string, types map[string]map[string]AbiValue) !string {
	if value.starts_with('&') { return abi_native_type(value[1..], types)! + ' *' }
	if value in types {
		metadata := types[value]
		name := abi_name(metadata, 'name')!
		kind := abi_text(metadata, 'kind')!
		if kind == 'struct' { return 'struct ' + name }
		if kind == 'typedef' { return name }
		return error('Unknown native declaration kind: ${kind}')
	}
	types_by_name := {'voidptr': 'void *', 'usize': 'size_t', 'u32': 'uint32_t', 'i32': 'int32_t',
		'u64': 'uint64_t', 'i64': 'int64_t', 'u16': 'uint16_t', 'i16': 'int16_t',
		'u8': 'uint8_t', 'i8': 'int8_t', 'bool': 'bool'}
	if value !in types_by_name { return error('Unsupported native declaration type: ${value}') }
	return types_by_name[value]
}

struct AbiExport {
	prototype string
	arity int
}

fn abi_declarations(source_root string, paths []AbiValue, selected []string, types map[string]map[string]AbiValue) !map[string]AbiExport {
	mut result := map[string]AbiExport{}
	resolved_root := os.real_path(os.abs_path(source_root))
	for path in paths {
		relative := abi_string(path)!
		source := os.real_path(os.abs_path(if os.is_abs_path(relative) { relative } else { os.join_path(source_root, relative) }))
		if source != resolved_root && !source.starts_with(resolved_root + os.path_separator) {
			return error('Source path escapes module root: ${relative}')
		}
		mut remaining := os.read_file(source)!
		for remaining.contains('@[export:') {
			remaining = remaining.all_after('@[export:').trim_left(' \t\r\n\v\f')
			if !remaining.starts_with("'") { continue }
			tail := remaining[1..]
			end := tail.index("'") or { continue }
			name_value := tail[..end]
			mut declaration := tail[end + 1..].trim_left(' \t\r\n\v\f')
			if !declaration.starts_with(']') { continue }
			declaration = declaration[1..].trim_left(' \t\r\n\v\f')
			if !declaration.starts_with('pub fn ') { continue }
			declaration = declaration['pub fn '.len..]
			open := declaration.index('(') or { continue }
			if declaration[..open] == '' || !declaration[..open].runes().all(it == `_` || utf8.is_letter(it) || utf8.is_number(it)) { continue }
			close := declaration[open + 1..].index(')') or { continue }
			signature := declaration[open + 1..open + 1 + close]
			returned_tail := declaration[open + close + 2..].trim_left(' \t\r\n\v\f')
			brace := returned_tail.index('{') or { continue }
			if returned_tail[..brace].contains('\n') { continue }
			name := abi_identifier(AbiValue(name_value))!
			if name !in selected { continue }
			mut parameters := []string{}
			if signature.trim_space() != '' {
				for item in signature.split(',') {
					fields := item.fields()
					if fields.len != 2 { return error('Invalid native export parameter: ${item}') }
					parameter := abi_identifier(AbiValue(fields[0]))!
					parameters << abi_native_type(fields[1], types)! + ' ' + parameter
				}
			}
			returned := returned_tail[..brace].trim_space()
			result_type := if returned == '' { 'void' } else { abi_native_type(returned, types)! }
			prototype := result_type + ' ' + name + '(' + (if parameters.len == 0 { 'void' } else { parameters.join(', ') }) + ');'
			if name in result { return error('Duplicate native export: ${name}') }
			result[name] = AbiExport{prototype: prototype, arity: parameters.len}
		}
	}
	return result
}

fn abi_export_arity(exported map[string]AbiExport, name string) !int {
	if name !in exported { return error('Missing V export: ${name}') }
	return exported[name].arity
}

fn abi_atomic_adapter(metadata map[string]AbiValue, exported map[string]AbiExport) !string {
	name := abi_name(metadata, 'name')!
	operation := abi_text(metadata, 'operation')!
	parameters := abi_list(metadata, 'parameters')!.map(abi_string(it)!)
	expected := if operation == 'exchange' { ['ptr', 'value'] } else { ['ptr', 'old', 'value'] }
	if operation !in ['exchange', 'compare_exchange'] || parameters != expected { return error('Invalid atomic operation/parameters: ${name}') }
	widths := abi_list(metadata, 'widths')!
	if widths.len != 5 { return error('Native exchange must preserve all integer widths: ${name}') }
	for index, width in [1, 2, 4, 8, 16] {
		if !abi_numeric_equal(widths[index], width) { return error('Native exchange must preserve all integer widths: ${name}') }
	}
	small := abi_name(metadata, 'small_export')!
	wide := abi_name(metadata, 'wide_export')!
	count := if operation == 'exchange' { 4 } else { 5 }
	if abi_export_arity(exported, small)! != count || abi_export_arity(exported, wide)! != count - 1 { return error('V export arity does not match native adapter: ${name}') }
	p := '__vinix_atomic_pointer'
	old := '__vinix_atomic_expected'
	value := '__vinix_atomic_value'
	out := '__vinix_atomic_result'
	mut lines := ['__auto_type ${p} = (ptr);']
	if operation == 'compare_exchange' { lines << '__typeof__(*${p}) ${old} = (old);' }
	lines << '__typeof__(*${p}) ${value} = (value);'
	lines << '__typeof__(*${p}) ${out};'
	lines << '(void)sizeof(__atomic_load_n(${p}, __ATOMIC_RELAXED));'
	lines << '_Static_assert(!__builtin_types_compatible_p(__typeof__(${p}), const __typeof__(*${p}) *), "atomic storage must be writable");'
	accepted := [1, 2, 4, 8, 16].map('sizeof(*${p}) == ${it}').join(' || ')
	lines << '_Static_assert(${accepted}, "unsupported native atomic width");'
	mut operands := ['(void *)' + p]
	if operation == 'compare_exchange' { operands << '(void *)&' + old }
	operands << '(void *)&' + value
	operands << '(void *)&' + out
	joined := operands.join(', ')
	lines << 'if (sizeof(*${p}) == 16) ${wide}(${joined});'
	lines << 'else ${small}(${joined}, sizeof(*${p}));'
	lines << out + ';'
	continuation := ' \\\n'
	return '#define ' + name + '(' + expected.join(', ') + ') ({' + continuation + lines.map('    ' + it).join(continuation) + continuation + '})'
}

fn abi_call_adapter(metadata map[string]AbiValue, exported map[string]AbiExport) !string {
	name := abi_name(metadata, 'name')!
	parameters := abi_list(metadata, 'parameters')!.map(abi_identifier(it)!)
	mut locals := []string{}
	mut lines := []string{}
	for value in abi_list(metadata, 'steps')! {
		step := abi_object(value)!
		if 'result' in step {
			result := abi_name(step, 'result')!
			if result !in locals { return error('Unknown result in ${name}: ${result}') }
			lines << result + ';'
			continue
		}
		function := abi_name(step, 'call')!
		mut operands := []string{}
		for argument in abi_list(step, 'arguments')! {
			if argument is map[string]AbiValue {
				address := abi_name(argument, 'address')!
				if address !in parameters { return error('Unknown address argument in ${name}: ${address}') }
				operands << '&(' + address + ')'
			} else {
				argument_name := abi_identifier(argument)!
				if argument_name !in parameters && argument_name !in locals { return error('Unknown argument in ${name}: ${argument_name}') }
				operands << '(' + argument_name + ')'
			}
		}
		if abi_export_arity(exported, function)! != operands.len { return error('Native call arity mismatch: ${function}') }
		call := function + '(' + operands.join(', ') + ')'
		if 'publish' in step {
			destination := abi_name(step, 'publish')!
			if destination !in parameters { return error('Unknown output lvalue in ${name}: ${destination}') }
			lines << '(' + destination + ') = ' + call + ';'
		} else if 'capture' in step {
			variable := abi_name(step, 'capture')!
			if variable in locals || variable in parameters { return error('Duplicate result in ${name}: ${variable}') }
			locals << variable
			lines << '__auto_type ' + variable + ' = ' + call + ';'
		} else if 'unless' in step {
			condition := abi_name(step, 'unless')!
			if condition !in locals { return error('Unknown call condition in ${name}: ${condition}') }
			lines << 'if (!' + condition + ') ' + call + ';'
		} else { lines << call + ';' }
	}
	shape := abi_text(metadata, 'shape')!
	if shape !in ['statement', 'expression'] { return error('Unsupported native adapter shape: ${shape}') }
	opening := if shape == 'statement' { 'do {' } else { '({' }
	closing := if shape == 'statement' { '} while (0)' } else { '})' }
	continuation := ' \\\n'
	return '#define ' + name + '(' + parameters.join(', ') + ') ' + opening + continuation + lines.map('    ' + it).join(continuation) + continuation + closing
}

struct AbiSymbol {
	arity int
	kinds []string
	kind string
}

fn abi_operand(value AbiValue, parameters map[string]string) !string {
	node := abi_object(value)!
	if abi_keys(node, ['operand']) {
		name := abi_name(node, 'operand')!
		if name !in parameters { return error('Unknown native type-or-expression operand: ${name}') }
		return name
	}
	if abi_keys(node, ['type']) { return abi_expression_type(abi_field(node, 'type')!, parameters)! }
	return error('Unsupported native type-or-expression operand')
}

fn abi_expression_type(value AbiValue, parameters map[string]string) !string {
	node := abi_object(value)!
	if abi_keys(node, ['typeof']) { return 'typeof(' + abi_operand(abi_field(node, 'typeof')!, parameters)! + ')' }
	if abi_keys(node, ['parameter']) {
		name := abi_name(node, 'parameter')!
		if parameters[name] != 'type' { return error('Unknown native type parameter: ${name}') }
		return name
	}
	if abi_keys(node, ['native']) && abi_text(node, 'native')! in ['int', 'uintptr_t'] { return abi_text(node, 'native')! }
	return error('Unsupported native expression type')
}

fn abi_expression(value AbiValue, parameters map[string]string, symbols map[string]AbiSymbol, locals []string) !string {
	node := abi_object(value)!
	if abi_keys(node, ['literal']) || abi_keys(node, ['literal', 'suffix']) {
		suffix := if 'suffix' in node { abi_text(node, 'suffix')! } else { '' }
		if suffix !in ['', 'UL'] { return error('Invalid native constant') }
		return abi_integer(abi_field(node, 'literal')!)! + suffix
	}
	if abi_keys(node, ['argument']) {
		name := abi_name(node, 'argument')!
		if parameters[name] !in ['value', 'operand'] { return error('Unknown native expression parameter: ${name}') }
		return '(' + name + ')'
	}
	if abi_keys(node, ['local']) {
		name := abi_name(node, 'local')!
		if name !in locals { return error('Unknown native capture local: ${name}') }
		return '(' + name + ')'
	}
	if abi_keys(node, ['address']) { return '(&' + abi_expression(abi_field(node, 'address')!, parameters, symbols, locals)! + ')' }
	if abi_keys(node, ['unary', 'value']) && abi_text(node, 'unary')! in ['-', '!'] {
		return '(' + abi_text(node, 'unary')! + abi_expression(abi_field(node, 'value')!, parameters, symbols, locals)! + ')'
	}
	if abi_keys(node, ['condition', 'yes', 'no']) {
		return '(' + abi_expression(abi_field(node, 'condition')!, parameters, symbols, locals)! + ' ? ' + abi_expression(abi_field(node, 'yes')!, parameters, symbols, locals)! + ' : ' + abi_expression(abi_field(node, 'no')!, parameters, symbols, locals)! + ')'
	}
	if abi_keys(node, ['native_result_capture', 'intrinsic_expression']) {
		captured_result := abi_object(abi_field(node, 'native_result_capture')!)!
		if !abi_keys(captured_result, ['name', 'type', 'initial']) { return error('Invalid native result capture') }
		name := abi_name(captured_result, 'name')!
		if name in parameters || name in locals { return error('Duplicate native result capture: ${name}') }
		expression := abi_object(abi_field(node, 'intrinsic_expression')!)!
		if !abi_keys(expression, ['call', 'arguments']) || symbols[abi_text(expression, 'call')!].kind != 'overflow_intrinsic' {
			return error('A native result capture may only bind a compiler overflow intrinsic')
		}
		initial_node := abi_object(abi_field(captured_result, 'initial')!)!
		if !abi_keys(initial_node, ['literal']) || !abi_numeric_equal(abi_field(initial_node, 'literal')!, 0) { return error('Native overflow output capture must start at zero') }
		operands := abi_list(expression, 'arguments')!
		if operands.len != 3 { return error('Native overflow capture must bind its typed input/output local') }
		input := abi_object(operands[1])!
		output := abi_object(operands[2])!
		if !abi_keys(input, ['local']) || abi_text(input, 'local')! != name || !abi_keys(output, ['address']) { return error('Native overflow capture must bind its typed input/output local') }
		output_local := abi_object(abi_field(output, 'address')!)!
		if !abi_keys(output_local, ['local']) || abi_text(output_local, 'local')! != name { return error('Native overflow capture must bind its typed input/output local') }
		native := abi_expression_type(abi_field(captured_result, 'type')!, parameters)!
		initial := abi_expression(abi_field(captured_result, 'initial')!, parameters, symbols, locals)!
		operation := abi_expression(abi_field(node, 'intrinsic_expression')!, parameters, symbols, [...locals, name])!
		return '({ ' + native + ' ' + name + ' = ' + initial + '; ' + operation + '; })'
	}
	if abi_keys(node, ['cast', 'value']) { return '((' + abi_expression_type(abi_field(node, 'cast')!, parameters)! + ')(' + abi_expression(abi_field(node, 'value')!, parameters, symbols, locals)! + '))' }
	if abi_keys(node, ['sizeof']) { return 'sizeof(' + abi_expression_type(abi_field(node, 'sizeof')!, parameters)! + ')' }
	if abi_keys(node, ['operator', 'left', 'right']) && abi_text(node, 'operator')! in ['+', '-', '*', '<<', '<', '<=', '>', '&&', '||'] {
		return '(' + abi_expression(abi_field(node, 'left')!, parameters, symbols, locals)! + ' ' + abi_text(node, 'operator')! + ' ' + abi_expression(abi_field(node, 'right')!, parameters, symbols, locals)! + ')'
	}
	if abi_keys(node, ['call', 'arguments']) {
		name := abi_name(node, 'call')!
		operands := abi_list(node, 'arguments')!
		if name !in symbols || operands.len != symbols[name].arity { return error('Unknown native expression call/arity: ${name}') }
		mut values := []string{}
		for index, argument in operands {
			kind := symbols[name].kinds[index]
			values << if kind == 'type' { abi_expression_type(argument, parameters)! }
				else if kind == 'operand' { abi_operand(argument, parameters)! }
				else { abi_expression(argument, parameters, symbols, locals)! }
		}
		return name + '(' + values.join(', ') + ')'
	}
	return error('Unsupported native expression node')
}

fn abi_intrinsic(metadata map[string]AbiValue) !string {
	name := abi_name(metadata, 'name')!
	target := abi_name(metadata, 'intrinsic')!
	parameters := abi_list(metadata, 'parameters')!.map(abi_identifier(it)!)
	builtins := {'__builtin_add_overflow': 3, '__builtin_sub_overflow': 3, '__builtin_mul_overflow': 3, '__builtin_constant_p': 1, '__builtin_choose_expr': 3}
	if target !in builtins || parameters.len != builtins[target] || parameters.len != abi_unique(parameters).len { return error('Invalid native intrinsic binding: ${name}') }
	return '#define ' + name + '(' + parameters.join(', ') + ') ' + target + '(' + parameters.map('(' + it + ')').join(', ') + ')'
}

fn abi_expression_parameters(metadata map[string]AbiValue) !map[string]string {
	name := abi_name(metadata, 'name')!
	mut parameters := map[string]string{}
	for item in abi_list(metadata, 'parameters')! {
		parameter := abi_object(item)!
		parameter_name := abi_name(parameter, 'name')!
		kind := abi_text(parameter, 'kind')!
		if parameter_name in parameters || kind !in ['value', 'type', 'operand'] { return error('Invalid native expression parameters: ${name}') }
		parameters[parameter_name] = kind
	}
	return parameters
}

pub fn generate_abi(schema_path string, source_root string, output string) ! {
	decoded := json2.decode[AbiValue](os.read_file(schema_path)!, strict: true) or {
		// Existing audit callers classify malformed metadata by this category.
		return error('JSONDecodeError: ' + err.msg())
	}
	config := abi_object(decoded)!
	if !abi_numeric_equal(abi_field(config, 'version')!, 1) { return error('Unsupported native ABI metadata version') }
	atomic_adapters := abi_optional_list(config, 'native_atomic_adapters')!.map(abi_object(it)!)
	call_adapters := abi_optional_list(config, 'native_call_adapters')!.map(abi_object(it)!)
	intrinsics := abi_optional_list(config, 'native_intrinsic_bindings')!.map(abi_object(it)!)
	expressions := abi_optional_list(config, 'native_expression_adapters')!.map(abi_object(it)!)
	mut selected := []string{}
	for metadata in atomic_adapters { selected << abi_text(metadata, 'small_export')!; selected << abi_text(metadata, 'wide_export')! }
	for metadata in call_adapters {
		for value in abi_list(metadata, 'steps')! {
			step := abi_object(value)!
			if 'call' in step { selected << abi_text(step, 'call')! }
		}
	}
	for value in abi_optional_list(config, 'native_expression_exports')! { selected << abi_string(value)! }
	selected = abi_unique(selected)
	mut types := map[string]map[string]AbiValue{}
	for value in abi_optional_list(config, 'native_types')! {
		metadata := abi_object(value)!
		types[abi_text(metadata, 'vtype')!] = metadata
	}
	exported := abi_declarations(source_root, abi_list(config, 'sources')!, selected, types)!
	if exported.len != selected.len {
		mut missing := selected.filter(it !in exported)
		missing.sort()
		return error('Missing V exports: ' + missing.join(', '))
	}
	guard := abi_name(config, 'guard')!
	mut text := ['// Generated from V declarations and structured ABI metadata; do not maintain.',
		'#ifndef ' + guard, '#define ' + guard, '#include <stdbool.h>', '#include <stddef.h>', '#include <stdint.h>']
	mut symbols := map[string]AbiSymbol{}
	for name, arity in {'__builtin_add_overflow': 3, '__builtin_sub_overflow': 3, '__builtin_mul_overflow': 3, '__builtin_constant_p': 1, '__builtin_choose_expr': 3} {
		symbols[name] = AbiSymbol{arity: arity, kinds: []string{len: arity, init: 'value'}, kind: if name in ['__builtin_add_overflow', '__builtin_sub_overflow', '__builtin_mul_overflow'] { 'overflow_intrinsic' } else { 'intrinsic' }}
	}
	for name, value in exported { symbols[name] = AbiSymbol{arity: value.arity, kinds: []string{len: value.arity, init: 'value'}, kind: 'function'} }
	for metadata in intrinsics {
		abi_intrinsic(metadata)!
		name := abi_name(metadata, 'name')!
		arity := abi_list(metadata, 'parameters')!.len
		symbols[name] = AbiSymbol{arity: arity, kinds: []string{len: arity, init: 'value'}, kind: if abi_text(metadata, 'intrinsic')! in ['__builtin_add_overflow', '__builtin_sub_overflow', '__builtin_mul_overflow'] { 'overflow_intrinsic' } else { 'intrinsic' }}
	}
	for metadata in expressions {
		name := abi_name(metadata, 'name')!
		if name in symbols { return error('Duplicate native expression symbol: ${name}') }
		mut kinds := []string{}
		for value in abi_list(metadata, 'parameters')! {
			kind := abi_text(abi_object(value)!, 'kind')!
			if kind !in ['value', 'type', 'operand'] { return error('Invalid native expression parameter kind: ${name}') }
			kinds << kind
		}
		symbols[name] = AbiSymbol{arity: kinds.len, kinds: kinds, kind: 'expression'}
	}
	for value in abi_optional_list(config, 'native_expression_imports')! {
		metadata := abi_object(value)!
		name := abi_name(metadata, 'name')!
		header := abi_text(metadata, 'header')!
		parameters := abi_list(metadata, 'parameters')!.map(abi_string(it)!)
		if !header.ends_with('.h') || header[..header.len - 2] == '' || !header.bytes().all(it.is_alnum() || it in [`_`, `.`, `/`, `-`]) || '..' in header.split('/') { return error('Invalid native expression import header: ${header}') }
		if name in symbols || parameters.any(it !in ['value', 'type', 'operand']) { return error('Invalid native expression import: ${name}') }
		text << '#include <' + header + '>'
		symbols[name] = AbiSymbol{arity: parameters.len, kinds: parameters, kind: 'native_helper'}
	}
	for _, value in exported { text << value.prototype }
	for metadata in atomic_adapters { text << abi_atomic_adapter(metadata, exported)! }
	for metadata in call_adapters { text << abi_call_adapter(metadata, exported)! }
	for metadata in intrinsics { text << abi_intrinsic(metadata)! }
	for metadata in expressions {
		name := abi_name(metadata, 'name')!
		parameters := abi_expression_parameters(metadata)!
		text << '#define ' + name + '(' + parameters.keys().join(', ') + ') ' + abi_expression(abi_field(metadata, 'expression')!, parameters, symbols, [])!
	}
	mut names := []string{}
	for records in [atomic_adapters, call_adapters, intrinsics, expressions] {
		for metadata in records { names << abi_name(metadata, 'name')! }
	}
	if names.len != abi_unique(names).len { return error('Duplicate native adapter name') }
	for value in abi_optional_list(config, 'aliases')! {
		metadata := abi_object(value)!
		name := abi_name(metadata, 'name')!
		target := abi_name(metadata, 'target')!
		if target !in names || name in names { return error('Invalid native adapter alias: ${name} -> ${target}') }
		text << '#define ' + name + ' ' + target
		names << name
	}
	text << '#endif'
	text << ''
	os.mkdir_all(os.dir(output))!
	os.write_file(output, text.join('\n'))!
}

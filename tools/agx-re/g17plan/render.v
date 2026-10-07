module g17plan

import traceanalysis { Value }

fn u64_text(value u64) string { return 'u64(0x${value:x})' }

fn u32_text(value int) string { return 'u32(0x${u32(value):x})' }

fn generated_expression_width(expression string, bytes int, evaluated bool) string {
	return '${if evaluated { 'g17_eval_width' } else { 'g17_width' }}((${expression}), ${bytes})'
}

fn known_expression(expression string, evaluated bool) string {
	return if evaluated { 'g17_known(${expression})' } else { expression }
}

fn walk(item Value) []map[string]Value {
	mut result := []map[string]Value{}
	match item {
		map[string]Value {
			node := item.as_map()
			result << node
			for _, child in node { result << walk(child) }
		}
		[]Value {
			for child in item { result << walk(child) }
		}
		else {}
	}
	return result
}

fn generated_command_root(item Value) bool {
	return walk(item).any(text(it, 'kind') == 'argument' && text(it, 'name') == 'command')
}

fn external_root(item Value) bool {
	match item {
		[]Value {
			for child in item { if external_root(child) { return true } }
		}
		map[string]Value {
			node := item.as_map()
			kind := text(node, 'kind')
			if kind == 'hardware_input' { return false }
			if kind in ['virtual_load', 'call_result', 'channel_load', 'accelerator_load'] {
				return true
			}
			if kind == 'argument' { return text(node, 'name') != 'command' }
			if kind == 'object_load' { return !generated_command_root(val(node, 'base')) }
			for _, child in node { if external_root(child) { return true } }
		}
		else {}
	}
	return false
}

fn hardware_name(node map[string]Value) !string {
	name := text(node, 'name')
	if name.len == 0 || !((name[0] >= `a` && name[0] <= `z`) || (name[0] >= `A` && name[0] <= `Z`) || name[0] == `_`) || name.bytes().any(!it.is_alnum() && it != `_`) {
		return error('invalid hardware input name ${repr(val(node, 'name'))}')
	}
	if int_value(default_value(node, 'bytes', Value(0)), 'hardware input bytes')! != 4 {
		return error('hardware input ${name} is not 32 bits wide')
	}
	return name
}

fn hardware_inputs(abi map[string]Value) ![]string {
	channels := obj(abi, 'channels')
	roots := [val(obj(obj(channels, 'register_selectors'), 'producers'), '3D'),
		val(emission_graph(abi), 'decisions')]
	mut names := []string{}
	for node in walk(Value(roots)) {
		if text(node, 'kind') == 'hardware_input' {
			name := hardware_name(node)!
			if name !in names { names << name }
		}
	}
	names.sort()
	return names
}

pub fn render_predicate(node map[string]Value, cond string, descriptor string, command string, evaluated bool) !string {
	p := normalize_predicate(node)!
	operation := text(p, 'operation')
	bytes := expression_width(p, 'predicate bytes')!
	label := if evaluated { 'evaluated' } else { 'generated' }
	expression := render_expression(required(p, 'source')!, descriptor, command, evaluated)!
	source := if evaluated {
		expression
	} else {
		generated_expression_width(expression, bytes, false)
	}
	if operation in ['cmp', 'compare_zero', 'tst'] {
		other_value := if 'second' in p {
			render_expression(required(p, 'second')!, descriptor, command, evaluated)!
		} else {
			known_expression(u64_text(masked_integer(if operation == 'tst' {
				required(p, 'immediate')!
			} else {
				default_value(p, 'immediate', Value(0))
			}, if operation == 'tst' {
				'test immediate'
			} else {
				'compare immediate'
			})!), evaluated)
		}
		other := if evaluated {
			other_value
		} else {
			generated_expression_width(other_value, bytes, false)
		}
		if operation == 'tst' {
			if cond !in ['eq', 'ne'] {
				return error('unsupported ${label} TST condition ${repr(Value(cond))}')
			}
			if evaluated {
				return 'g17_test_mask((${source}), (${other}), ${if cond == 'ne' { 1 } else { 0 }}, ${bytes})'
			}
			return '((${source}) & (${other})) ${if cond == 'eq' { '==' } else { '!=' }} 0'
		}
		operator := match cond {
			'eq', 'zero' { '==' }
			'ne', 'nonzero' { '!=' }
			'hi' { '>' }
			'ls' { '<=' }
			'cc', 'lo' { '<' }
			'cs', 'hs' { '>=' }
			else {
				return error('unsupported ${label} condition ${repr(Value(cond))} for ${repr(Value(operation))}')
			}
		}
		if evaluated {
			compare_name := match cond {
				'eq', 'zero' { 'eq' }
				'ne', 'nonzero' { 'ne' }
				'cc', 'lo' { 'lo' }
				'cs', 'hs' { 'hs' }
				else { cond }
			}
			return 'g17_compare((${source}), (${other}), .g17_compare_${compare_name}, ${bytes})'
		}
		return '(${source}) ${operator} (${other})'
	}
	if operation == 'test_bit' {
		bit := field(p, 'bit', 'tested bit')!
		if bit < 0 || bit >= bytes * 8 {
			return error('tested bit ${bit} is outside predicate width')
		}
		if cond !in ['bit_set', 'bit_clear'] {
			return error('unsupported ${label} bit condition ${repr(Value(cond))}')
		}
		if evaluated {
			return 'g17_test_bit((${source}), ${bit}, ${if cond == 'bit_set' { 1 } else { 0 }}, ${bytes})'
		}
		return '((${source}) & (${u64_text(1)} << ${bit})) ${if cond == 'bit_set' {
			'!='
		} else {
			'=='
		}} 0'
	}
	return error('unsupported ${label} predicate ${repr(val(p, 'operation'))}')
}

pub fn render_expression(item Value, descriptor string, command string, evaluated bool) !string {
	label := if evaluated { 'evaluated' } else { 'generated' }
	node := match item {
		map[string]Value { item.as_map() }
		else { return error('${label} expression node must be an object') }
	}
	kind := text(node, 'kind')
	if kind in ['constant', 'constant_call'] {
		return known_expression(u64_text(masked_integer(required(node, 'value')!, 'constant value')!), evaluated)
	}
	if kind == 'descriptor_load' {
		return known_expression('g17_load(${descriptor}, ${field(node, 'member', 'descriptor member')!}, ${field(node, 'bytes', 'descriptor width')!}, ${if truth(val(node, 'signed')) {
			1
		} else {
			0
		}})', evaluated)
	}
	if kind in ['stack_reload', 'computed'] {
		return render_expression(required(node, if kind == 'stack_reload' {
			'source'
		} else {
			'expression'
		})!, descriptor, command, evaluated)
	}
	if kind == 'hardware_input' {
		return known_expression('u64(inputs.${hardware_name(node)!})', evaluated)
	}
	if kind == 'object_load' {
		if !generated_command_root(val(node, 'base')) {
			if evaluated { return 'g17_unknown()' }
			return unresolved('generated object load has an external root')
		}
		return known_expression('g17_load(${command}, ${field(node, 'member', 'command member')!}, ${field(node, 'bytes', 'command width')!}, ${if truth(val(node, 'signed')) {
			1
		} else {
			0
		}})', evaluated)
	}
	if kind in ['argument', 'virtual_load', 'call_result', 'channel_load', 'accelerator_load'] {
		if evaluated { return 'g17_unknown()' }
		return unresolved('generated value is rooted in external ${kind}')
	}
	if kind != 'expression' {
		if evaluated { return 'g17_unknown()' }
		return unresolved('unsupported generated value kind ${repr(val(node, 'kind'))}')
	}
	operation := text(node, 'operation')
	if operation in ['logical_immediate', 'logical_register', 'conditional', 'bitfield', 'register_copy'] {
		return render_expression(required(node, 'expression')!, descriptor, command, evaluated)
	}
	bytes := expression_width(node, 'expression bytes')!
	bits := bytes * 8
	if operation == 'copy' {
		return generated_expression_width(render_expression(required(node, 'source')!, descriptor, command, evaluated)!, bytes, evaluated)
	}
	if operation == 'multiway_select' {
		selector := render_expression(required(node, 'selector')!, descriptor, command, evaluated)!
		mut result := render_expression(required(node, 'default')!, descriptor, command, evaluated)!
		cases := val(node, 'cases').arr()
		for index := cases.len - 1; index >= 0; index-- {
			c := cases[index].as_map()
			value := render_expression(required(c, 'value')!, descriptor, command, evaluated)!
			equals := known_expression(u64_text(masked_integer(required(c, 'equals')!, 'case value')!), evaluated)
			result = if evaluated {
				'g17_select((g17_compare((${selector}), (${equals}), .g17_compare_eq, 8)), (${value}), (${result}))'
			} else {
				'if (${selector}) == ${equals} { (${value}) } else { (${result}) }'
			}
		}
		return generated_expression_width(result, bytes, evaluated)
	}
	if operation in ['csel', 'csinc', 'branch_select'] {
		test := render_predicate(required_obj(node, 'predicate')!, text(node, 'condition'), descriptor, command, evaluated)!
		first := render_expression(required(node, if operation == 'branch_select' {
			'taken'
		} else {
			'first'
		})!, descriptor, command, evaluated)!
		mut second := render_expression(required(node, if operation == 'branch_select' {
			'fallthrough'
		} else {
			'second'
		})!, descriptor, command, evaluated)!
		if operation == 'csinc' {
			second = if evaluated {
				'g17_eval_binary((${second}), (g17_known(${u64_text(1)})), .g17_binary_add, ${bytes})'
			} else {
				'((${second}) + ${u64_text(1)})'
			}
		}
		selected := if evaluated {
			'g17_select((${test}), (${first}), (${second}))'
		} else {
			'if ${test} { (${first}) } else { (${second}) }'
		}
		return generated_expression_width(selected, bytes, evaluated)
	}
	if operation == 'movk' {
		source := render_expression(required(node, 'source')!, descriptor, command, evaluated)!
		immediate := known_expression(u64_text(masked_integer(required(node, 'immediate')!, 'MOVK immediate')! & 0xffff), evaluated)
		return '${if evaluated { 'g17_eval_movk' } else { 'g17_movk' }}((${source}), ${if evaluated {
			'(' + immediate + ')'
		} else {
			immediate
		}}, ${field(node, 'shift', 'MOVK shift')!}, ${bytes})'
	}
	if operation in ['ubfm', 'bfm'] {
		source := render_expression(required(node, 'source')!, descriptor, command, evaluated)!
		destination := if operation == 'bfm' {
			render_expression(required(node, 'destination')!, descriptor, command, evaluated)!
		} else {
			known_expression(u64_text(0), evaluated)
		}
		return '${if evaluated { 'g17_eval_bitfield' } else { 'g17_bitfield' }}((${source}), (${destination}), ${field(node, 'rotate', 'bitfield rotate')!}, ${field(node, 'mask_end', 'bitfield mask end')!}, ${bits}, ${if operation == 'bfm' {
			1
		} else {
			0
		}})'
	}
	mut first := ''
	mut second := ''
	if 'source' in node {
		first = render_expression(required(node, 'source')!, descriptor, command, evaluated)!
		second = known_expression(u64_text(masked_integer(default_value(node, 'immediate', default_value(node, 'mask', Value(0))), 'immediate')!), evaluated)
	} else {
		first = render_expression(required(node, 'first')!, descriptor, command, evaluated)!
		second = render_expression(required(node, 'second')!, descriptor, command, evaluated)!
		kind_shift := default_value(node, 'shift', val(node, 'modifier'))
		amount := int_value(default_value(node, 'amount', Value(0)), 'shift amount')!
		if amount < 0 || amount >= bits {
			return error('shift amount ${amount} is outside ${bits} bits')
		}
		if !left_shift_kind(kind_shift) && kind_shift != Value('lsr') {
			return error('unsupported ${label} shift ${repr(kind_shift)}')
		}
		second = '${if evaluated { 'g17_eval_shift' } else { 'g17_shift' }}((${second}), ${if kind_shift == Value('lsr') {
			1
		} else {
			0
		}}, ${amount}, ${bits})'
	}
	if operation == 'multiply' && 'factor' in node {
		second = known_expression(u64_text(masked_integer(required(node, 'factor')!, 'multiply factor')!), evaluated)
	}
	if evaluated {
		if operation !in ['add', 'sub', 'and', 'orr', 'orn', 'bic', 'multiply'] {
			return 'g17_unknown()'
		}
		return 'g17_eval_binary((${first}), (${second}), .g17_binary_${operation}, ${bytes})'
	}
	operator := match operation {
		'add' { '+' }
		'sub' { '-' }
		'and' { '&' }
		'orr' { '|' }
		'orn' { '| ~' }
		'bic' { '& ~' }
		'multiply' { '*' }
		else {
			return unresolved('unsupported generated expression operation ${repr(val(node, 'operation'))}')
		}
	}
	return generated_expression_width('((${first}) ${operator} (${second}))', bytes, false)
}

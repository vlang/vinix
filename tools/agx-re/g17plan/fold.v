module g17plan

import traceanalysis { Value }

struct Facts {
	flags_member    int
	flags_bytes     int
	never_set       u64
	override_member int
	override        []u8
	column_member   int
	column_bytes    int
	column_input    string
	pointed         map[string]u64
}

fn facts(inputs map[string]Value) !Facts {
	flags := required_obj(inputs, 'feature_flags')!
	chip := required_obj(inputs, 'chip_information')!
	column := required_obj(inputs, 'power_column_count')!
	override := traceanalysis.bytes_fromhex(text(chip, 'override_value'))!
	if override.len != field(chip, 'override_bytes', 'override bytes')! {
		return error('chip-information override has the wrong length')
	}
	mut pointed := map[string]u64{}
	if !is_null(val(inputs, 'perf_counter_sampler')) {
		sampler := obj(inputs, 'perf_counter_sampler')
		policy := required_obj(sampler, 'vinix_policy')!
		if field(sampler, 'running_bytes', 'sampler running bytes')! != 1 {
			return error('sampler running state is not one byte')
		}
		pointed['${field(sampler, 'pointer_member', 'sampler pointer')!}:${field(sampler, 'running_member', 'sampler running member')!}'] = masked_integer(required(policy, 'running')!, 'sampler running policy')! & 0xff
	}
	return Facts{ flags_member: field(flags, 'member', 'feature-flag member')!, flags_bytes: field(flags, 'bytes', 'feature-flag bytes')!, never_set: masked_integer(required(flags, 'never_set_mask')!, 'never-set mask')!, override_member: field(chip, 'override_member', 'override member')!, override: override, column_member: field(column, 'member', 'column member')!, column_bytes: field(column, 'bytes', 'column bytes')!, column_input: text(column, 'hardware_input'), pointed: pointed }
}

fn (f Facts) load(start int, width int) (u64, u64) {
	mut value := u64(0)
	mut known := u64(0)
	for i in 0 .. width {
		member := start + i
		mut byte_value := u64(0)
		mut byte_known := u64(0)
		if member >= f.flags_member && member - f.flags_member < f.flags_bytes {
			amount := (member - f.flags_member) * 8
			byte_known = if amount >= 64 { u64(0) } else { (f.never_set >> amount) & 0xff }
		} else if member >= f.override_member && member - f.override_member < f.override.len {
			byte_value = u64(f.override[member - f.override_member])
			byte_known = 0xff
		}
		value |= byte_value << (i * 8)
		known |= byte_known << (i * 8)
	}
	return value, known
}

fn (f Facts) load_pointed(pointer int, start int, width int) (u64, u64) {
	mut value := u64(0)
	mut known := u64(0)
	for i in 0 .. width {
		key := '${pointer}:${start + i}'
		if key in f.pointed {
			value |= f.pointed[key] << (i * 8)
			known |= u64(0xff) << (i * 8)
		}
	}
	return value, known
}

struct PointerOffset {
	found  bool
	offset int
}

fn (p PointerOffset) option() ?int {
	if p.found { return p.offset }
	return none
}

fn accelerator_offset(item Value) !PointerOffset {
	node := match item {
		map[string]Value { item }
		else { return PointerOffset{} }
	}
	kind := text(node, 'kind')
	operation := text(node, 'operation')
	if kind == 'stack_reload' { return accelerator_offset(val(node, 'source')) }
	if kind == 'expression' && operation in ['copy', 'register_copy'] {
		return accelerator_offset(default_value(node, 'source', val(node, 'expression')))
	}
	if kind == 'object_load' && val(node, 'member').u64() == 0x10 && val(node, 'bytes').u64() == 8 && text(obj(node, 'base'), 'kind') == 'argument' && text(obj(node, 'base'), 'name') == 'channel' {
		return PointerOffset{true, 0}
	}
	if kind == 'expression' && operation == 'add' && !truth(val(node, 'amount')) {
		if 'source' in node && 'immediate' in node {
			base_option := accelerator_offset(val(node, 'source'))!
			if base := base_option.option() {
				return PointerOffset{true, base + field(node, 'immediate', 'pointer offset')!}
			}
		} else if text(obj(node, 'second'), 'kind') == 'constant' {
			base_option := accelerator_offset(val(node, 'first'))!
			if base := base_option.option() {
				return PointerOffset{true, base + field(obj(node, 'second'), 'value', 'pointer offset')!}
			}
		}
	}
	return PointerOffset{}
}

fn pointer_member(item Value) !PointerOffset {
	node := match item {
		map[string]Value { item }
		else { return PointerOffset{} }
	}
	kind := text(node, 'kind')
	if kind == 'stack_reload' { return pointer_member(val(item, 'source')) }
	if kind == 'expression' && text(item, 'operation') in ['copy', 'register_copy'] {
		return pointer_member(default_value(item, 'source', val(item, 'expression')))
	}
	if kind == 'object_load' && val(item, 'bytes').u64() == 8 {
		base_option := accelerator_offset(val(item, 'base'))!
		if base := base_option.option() {
			return PointerOffset{true, base + field(item, 'member', 'pointer member')!}
		}
	}
	return PointerOffset{}
}

fn constant(value u64, origin string) map[string]Value {
	return map[string]Value{
		'kind':   Value('constant')
		'value':  Value(value)
		'folded': Value(origin)
	}
}

struct Fold {
	node  map[string]Value
	value u64
	known u64
}

fn finish(node map[string]Value, value u64, known u64, mask u64) Fold {
	result := value & mask
	certainty := (known & mask) | ~mask
	return Fold{if certainty == word_mask { constant(result, 'folded') } else { node }, result, certainty}
}

fn fold_condition(node map[string]Value, cond string, f Facts, hardware map[string]u64) !(map[string]Value, ?bool) {
	predicate := normalize_predicate(node)!
	operation := text(predicate, 'operation')
	mask := width_mask(expression_width(predicate, 'predicate bytes')!)!
	mut rebuilt := copy_object(predicate)
	source := fold(required(predicate, 'source')!, f, hardware)!
	rebuilt['source'] = source.node
	mut other := u64(0)
	mut other_known := u64(0)
	if 'second' in predicate {
		second := fold(val(predicate, 'second'), f, hardware)!
		rebuilt['second'] = second.node
		other = second.value
		other_known = second.known
	} else if operation != 'test_bit' {
		other = masked_integer(default_value(predicate, 'immediate', Value(0)), 'predicate immediate')!
		other_known = word_mask
	}
	value := source.value & mask
	known := source.known & mask
	other &= mask
	other_known &= mask
	mut outcome := ?bool(none)
	if operation in ['cmp', 'compare_zero'] && known == mask && other_known == mask {
		outcome = compare(value, other, cond)
	} else if operation == 'tst' {
		zero := (known & ~value) | (other_known & ~other)
		one := known & value & other_known & other
		if cond in ['eq', 'ne'] {
			if one != 0 {
				outcome = cond == 'ne'
			} else if zero & mask == mask {
				outcome = cond == 'eq'
			}
		}
	} else if operation == 'test_bit' {
		bit := field(predicate, 'bit', 'tested bit')!
		if bit >= 0 && bit < 64 && (known >> bit) & 1 != 0 && cond in ['bit_set', 'bit_clear'] {
			set := (value >> bit) & 1 != 0
			outcome = if cond == 'bit_set' { set } else { !set }
		}
	}
	return rebuilt, outcome
}

fn fold(item Value, f Facts, hardware map[string]u64) !Fold {
	node := match item {
		map[string]Value { item }
		else { return error('value expression node must be an object') }
	}
	kind := text(node, 'kind')
	if kind in ['constant', 'constant_call'] {
		return Fold{node, masked_integer(required(node, 'value')!, 'constant value')!, word_mask}
	}
	if kind == 'hardware_input' {
		name := text(node, 'name')
		mask := width_mask(field(node, 'bytes', 'input bytes')!)!
		if name in hardware {
			value := hardware[name] & mask
			return Fold{constant(value, 'hardware:${name}'), value, word_mask}
		}
		return Fold{node, 0, ~mask}
	}
	if kind == 'object_load' {
		width := field(node, 'bytes', 'object load width')!
		mask := width_mask(width)!
		base_option := accelerator_offset(val(node, 'base'))!
		if base := base_option.option() {
			start := base + field(node, 'member', 'object member')!
			if start == f.column_member && width == f.column_bytes {
				return fold(map[string]Value{
					'kind':  Value('hardware_input')
					'name':  Value(f.column_input)
					'bytes': Value(width)
				}, f, hardware)
			}
			mut value, mut known := f.load(start, width)
			if truth(val(node, 'signed')) {
				if known != mask { return Fold{node, 0, 0} }
				if value >> (width * 8 - 1) != 0 { value |= ~mask }
				return Fold{constant(value, 'accelerator+${hex_offset(start)}'), value, word_mask}
			}
			known |= ~mask
			return Fold{if known == word_mask {
				constant(value, 'accelerator+${hex_offset(start)}')
			} else {
				node
			}, value, known}
		}
		if truth(val(node, 'signed')) { return Fold{node, 0, 0} }
		pointer_option := pointer_member(val(node, 'base'))!
		if pointer := pointer_option.option() {
			member := field(node, 'member', 'object member')!
			value, known := f.load_pointed(pointer, member, width)
			complete := known | ~mask
			return Fold{if complete == word_mask {
				constant(value, 'accelerator[${hex_offset(pointer)}]+${hex_offset(member)}')
			} else {
				node
			}, value, complete}
		}
		return Fold{node, 0, 0}
	}
	if kind == 'descriptor_load' {
		return Fold{node, 0, if truth(val(node, 'signed')) {
			u64(0)
		} else {
			~width_mask(field(node, 'bytes', 'load width')!)!
		}}
	}
	if kind in ['stack_reload', 'computed'] {
		key := if kind == 'stack_reload' { 'source' } else { 'expression' }
		child := fold(required(node, key)!, f, hardware)!
		if child.known == word_mask { return child }
		mut rebuilt := copy_object(node)
		rebuilt[key] = child.node
		return Fold{rebuilt, child.value, child.known}
	}
	if kind != 'expression' { return Fold{node, 0, 0} }
	operation := text(node, 'operation')
	if operation in ['logical_immediate', 'logical_register', 'conditional', 'bitfield', 'register_copy'] {
		child := fold(required(node, 'expression')!, f, hardware)!
		if child.known == word_mask { return child }
		mut rebuilt := copy_object(node)
		rebuilt['expression'] = child.node
		return Fold{rebuilt, child.value, child.known}
	}
	bytes := expression_width(node, 'expression bytes')!
	mask := width_mask(bytes)!
	bits := bytes * 8
	mut rebuilt := copy_object(node)
	if operation == 'copy' {
		child := fold(required(node, 'source')!, f, hardware)!
		rebuilt['source'] = child.node
		return finish(rebuilt, child.value, child.known, mask)
	}
	if operation == 'multiway_select' {
		selector := fold(required(node, 'selector')!, f, hardware)!
		rebuilt['selector'] = selector.node
		if selector.known == word_mask {
			for raw in val(node, 'cases').arr() {
				c := raw.as_map()
				if selector.value == masked_integer(required(c, 'equals')!, 'case value')! {
					child := fold(required(c, 'value')!, f, hardware)!
					return finish(child.node, child.value, child.known, mask)
				}
			}
			child := fold(required(node, 'default')!, f, hardware)!
			return finish(child.node, child.value, child.known, mask)
		}
		mut cases := []Value{}
		for raw in val(node, 'cases').arr() {
			mut c := copy_object(raw.as_map())
			c['value'] = fold(required(c, 'value')!, f, hardware)!.node
			cases << c
		}
		rebuilt['cases'] = cases
		rebuilt['default'] = fold(required(node, 'default')!, f, hardware)!.node
		return Fold{rebuilt, 0, ~mask}
	}
	if operation in ['csel', 'csinc', 'branch_select'] {
		first_key := if operation == 'branch_select' { 'taken' } else { 'first' }
		second_key := if operation == 'branch_select' { 'fallthrough' } else { 'second' }
		predicate, outcome := fold_condition(required_obj(node, 'predicate')!, text(node, 'condition'), f, hardware)!
		first := fold(required(node, first_key)!, f, hardware)!
		mut second := fold(required(node, second_key)!, f, hardware)!
		if operation == 'csinc' {
			if second.known == word_mask {
				value := (second.value + 1) & mask
				second = Fold{constant(value, 'folded'), value, word_mask}
			} else {
				second = Fold{map[string]Value{
					'kind':      Value('expression')
					'operation': Value('add')
					'bytes':     Value(bytes)
					'source':    Value(second.node)
					'immediate': Value(1)
				}, 0, 0}
			}
		}
		if selected := outcome {
			chosen := if selected { first } else { second }
			return finish(chosen.node, chosen.value, chosen.known, mask)
		}
		rebuilt['predicate'] = predicate
		rebuilt[first_key] = first.node
		rebuilt[second_key] = second.node
		if operation == 'csinc' { rebuilt['operation'] = Value('csel') }
		return finish(rebuilt, first.value, first.known & second.known & ~(first.value ^ second.value), mask)
	}
	if operation == 'movk' {
		child := fold(required(node, 'source')!, f, hardware)!
		amount := field(node, 'shift', 'MOVK shift')!
		immediate := masked_integer(required(node, 'immediate')!, 'MOVK immediate')! & 0xffff
		field_mask := shift(0xffff, Value('lsl'), amount, 64)!
		rebuilt['source'] = child.node
		return finish(rebuilt, (child.value & ~field_mask) | shift(immediate, Value('lsl'), amount, 64)!, (child.known & ~field_mask) | field_mask, mask)
	}
	if operation in ['ubfm', 'bfm'] {
		child := fold(required(node, 'source')!, f, hardware)!
		rotate := field(node, 'rotate', 'bitfield rotate')!
		wmask, tmask := bit_masks(rotate, field(node, 'mask_end', 'bitfield mask end')!, bits)!
		rotated := ror(child.value & mask, rotate, bits)
		certainty := ror(child.known & mask, rotate, bits)
		rebuilt['source'] = child.node
		if operation == 'ubfm' {
			return finish(rebuilt, rotated & wmask & tmask, (~tmask | ~wmask | certainty) & mask, mask)
		}
		dest := fold(required(node, 'destination')!, f, hardware)!
		rebuilt['destination'] = dest.node
		bottom := (dest.value & ~wmask) | (rotated & wmask)
		known := (dest.known & ~wmask) | (certainty & wmask)
		return finish(rebuilt, (dest.value & ~tmask) | (bottom & tmask), (dest.known & ~tmask) | (known & tmask), mask)
	}
	mut first := Fold{}
	mut second := Fold{}
	if 'source' in node {
		first = fold(val(node, 'source'), f, hardware)!
		second = Fold{map[string]Value{}, masked_integer(default_value(node, 'immediate', default_value(node, 'mask', Value(0))), 'immediate')!, word_mask}
		rebuilt['source'] = first.node
	} else {
		first = fold(required(node, 'first')!, f, hardware)!
		second = fold(required(node, 'second')!, f, hardware)!
		rebuilt['first'] = first.node
		rebuilt['second'] = second.node
		kind_shift := default_value(node, 'shift', val(node, 'modifier'))
		amount := int_value(default_value(node, 'amount', Value(0)), 'shift amount')!
		shifted := shift(second.value, kind_shift, amount, bits)!
		mut known := shift(second.known, kind_shift, amount, bits)!
		if kind_shift == Value('lsr') {
			known |= mask & ~shift(mask, kind_shift, amount, bits)!
		} else {
			known |= mask_bits(amount) & mask
		}
		second = Fold{second.node, shifted, known}
	}
	a := first.value & mask
	b := second.value & mask
	both := first.known & second.known
	if operation == 'and' {
		return finish(rebuilt, a & b, both | (first.known & ~a) | (second.known & ~b), mask)
	}
	if operation == 'orr' {
		return finish(rebuilt, a | b, both | (first.known & a) | (second.known & b), mask)
	}
	if operation == 'bic' {
		return finish(rebuilt, a & ~b, both | (first.known & ~a) | (second.known & b), mask)
	}
	if operation == 'orn' {
		return finish(rebuilt, a | ~b, both | (first.known & a) | (second.known & ~b), mask)
	}
	if operation in ['add', 'sub', 'multiply'] {
		if (first.known | ~mask) == word_mask && (second.known | ~mask) == word_mask {
			result := if operation == 'add' {
				a + b
			} else if operation == 'sub' {
				a - b
			} else {
				a * masked_integer(default_value(node, 'factor', Value(b)), 'multiply factor')!
			}
			return finish(rebuilt, result, word_mask, mask)
		}
		return finish(rebuilt, 0, 0, mask)
	}
	return Fold{rebuilt, 0, 0}
}

fn mentions_accelerator(item Value) !bool {
	match item {
		[]Value {
			for child in item { if mentions_accelerator(child)! { return true } }
		}
		map[string]Value {
			node := item.as_map()
			if text(node, 'kind') == 'object_load' {
				base_option := accelerator_offset(val(node, 'base'))!
				if _ := base_option.option() { return true }
			}
			for _, child in node { if mentions_accelerator(child)! { return true } }
		}
		else {}
	}
	return false
}

pub fn fold_accelerator_inputs(abi map[string]Value, hardware map[string]u64) !map[string]Value {
	channels := obj(abi, 'channels')
	if is_null(val(channels, 'accelerator_inputs')) { return abi }
	f := facts(required_obj(channels, 'accelerator_inputs')!)!
	mut result := deep_copy(Value(abi)).as_map()
	mut output := obj(result, 'channels')
	mut selectors := obj(output, 'register_selectors')
	mut producers := obj(selectors, 'producers')
	for name, raw in producers {
		mut producer := copy_object(raw.as_map())
		mut entries := []Value{}
		for raw_entry in val(producer, 'encoder_entries').arr() {
			mut entry := copy_object(raw_entry.as_map())
			if mentions_accelerator(val(entry, 'value_source'))! {
				entry['value_source'] = fold(required(entry, 'value_source')!, f, hardware)!.node
			}
			entries << entry
		}
		producer['encoder_entries'] = entries
		producers[name] = producer
	}
	selectors['producers'] = producers
	output['register_selectors'] = selectors
	mut cfg := obj(output, 'register_emission_cfg')
	mut graphs := obj(cfg, 'producers')
	for name, raw in graphs {
		mut graph := copy_object(raw.as_map())
		mut decisions := []Value{}
		for raw_decision in val(graph, 'decisions').arr() {
			mut decision := copy_object(raw_decision.as_map())
			if 'predicate' in decision && mentions_accelerator(val(decision, 'predicate'))! {
				predicate, outcome := fold_condition(obj(decision, 'predicate'), text(decision, 'condition'), f, hardware)!
				if selected := outcome {
					decision['folded_from'] = map[string]Value{
						'predicate': val(decision, 'predicate')
						'condition': val(decision, 'condition')
					}
					decision['predicate'] = map[string]Value{
						'kind':      Value('condition')
						'operation': Value('cmp')
						'bytes':     Value(4)
						'source':    Value(constant(0, 'folded'))
						'immediate': Value(0)
					}
					decision['condition'] = Value(if selected { 'eq' } else { 'ne' })
				} else {
					decision['predicate'] = predicate
				}
			}
			decisions << decision
		}
		graph['decisions'] = decisions
		graphs[name] = graph
	}
	cfg['producers'] = graphs
	output['register_emission_cfg'] = cfg
	mut names := hardware.keys()
	names.sort()
	output['accelerator_inputs_folded'] = names.map(Value(it))
	result['channels'] = output
	return result
}

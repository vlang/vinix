module g17expr

import g17decode as arm
import math.big
import json2
import traceanalysis as j

fn require_producers(source ImageSource) !map[string]u64 {
	symbols := source.symbols()!
	mut missing := []string{}
	for _, name in producer_names() { if name !in symbols { missing << name } }
	if missing.len > 0 {
		return error('Mach-O is missing register-list producers: ${j.string_value(j.Value(missing.map(j.Value(it))))}')
	}
	return symbols
}

fn sorted_set(values map[u64]bool) j.Value {
	mut keys := values.keys()
	keys.sort()
	return j.Value(keys.map(j.Value(it)))
}

pub fn register_selectors(data []u8) !map[string]j.Value {
	return register_selectors_with_source(DriverImage{data})
}

pub fn register_selectors_with_source(source ImageSource) !map[string]j.Value {
	symbols := require_producers(source)!
	settable := u64(0x0003fff9)
	selector_field := settable & ~u64(1)
	if append_provider !in symbols { return error('Mach-O is missing ${append_provider}') }
	append_address := symbols[append_provider]
	_, append_code := source.code(append_provider)!
	arm.require_instruction_words_at(append_code, 'G17 register-entry append', proof_words('G17 register-entry append'))!
	mut producers := map[string]j.Value{}
	mut encoded_union := map[u64]bool{}
	mut selector_union := map[u64]bool{}
	mut static_union := map[u64]bool{}
	names := producer_names()
	mut labels := names.keys()
	labels.sort()
	for label in labels {
		name := names[label]
		address, code := source.code(name)!
		buffered := instructions_from_code(code)
		mut immediates := map[int]u64{}
		mut recency := map[int]int{}
		mut found := map[u64]bool{}
		mut context := -10
		mut encoder_calls := []j.Value{}
		mut dynamic_appends := []j.Value{}
		for index, instruction in buffered {
			word := instruction.word
			opcode := word & 0xff800000
			if opcode == 0x52800000 || opcode == 0x72800000 {
				register := int(word & 0x1f)
				immediate := u64((word >> 5) & 0xffff)
				shift := ((word >> 21) & 3) * 16
				immediates[register] = if opcode == 0x52800000 {
					immediate << shift
				} else {
					(immediates[register] & ~(u64(0xffff) << shift)) | (immediate << shift)
				}
				recency[register] = index
				continue
			}
			if selector := fields('decode_orr_register', word, big.zero_int) {
				if candidate := immediates[selector[2].int()] {
					if candidate & ~settable == 0 { found[candidate] = true }
				}
				continue
			}
			if word & 0xffc003ff == 0x910003e0 {
				context = index
				continue
			}
			if target := branch_target('decode_bl_target', Instruction{ offset: big.integer_from_u64(address) + instruction.offset, word: word }) {
				if target == big.integer_from_u64(append_address) {
					if index - context > 10 {
						return error('${label} append at producer +0x${offset_hex(instruction.offset)} has no stack encoder')
					}
					resolved := static_w_register(buffered, index, 1, 0)
					mode := static_w_register(buffered, index, 2, 0) or { return error('${label} append mode at producer +0x${offset_hex(instruction.offset)} is no longer a static bit') }
					if mode > 1 {
						return error('${label} append mode at producer +0x${offset_hex(instruction.offset)} is no longer a static bit')
					}
					mut entry := map[string]j.Value{
						'producer_offset': scalar(instruction.offset)
						'mode':            j.Value(mode)
						'form':            j.Value('append')
						'value_source':    expr(classify_value_argument(buffered, index, 3)!)
					}
					if selector := resolved {
						entry['selector'] = j.Value(selector)
						encoder_calls << j.Value(entry)
					} else {
						entry['selector_formula'] = optional_expression(value_expression(buffered, index, 1, 0, []Visit{}))
						dynamic_appends << j.Value(entry)
					}
					continue
				}
			}
			if word & 0xfffffc00 == 0xd73f0800 {
				if candidate := immediates[2] {
					if candidate & ~settable == 0 && index - (recency[2] or { -10 }) < 10 && index - context < 10 {
						found[candidate] = true
					}
				}
				mut publishes := false
				for following_index := index + 1; following_index < buffered.len && following_index < index + 20; following_index++ {
					arithmetic := fields('decode_add_sub_immediate_w', buffered[following_index].word, big.zero_int) or { continue }
					if j.string_value(arithmetic[0]) != 'add' || arithmetic[3].int() != 12 {
						continue
					}
					for following in instruction_block(buffered, following_index + 1, following_index + 3) {
						if following.word & 0xfffffc00 == 0x790e1400 {
							publishes = true
							break
						}
					}
					if publishes { break }
				}
				if index - context <= 10 && publishes {
					resolved := static_w_register(buffered, index, 2, 0) or { return error('${label} selector at producer +0x${offset_hex(instruction.offset)} is no longer statically resolvable') }
					mode := static_w_register(buffered, index, 3, 0) or { return error('${label} mode at producer +0x${offset_hex(instruction.offset)} is no longer a static bit') }
					if mode > 1 {
						return error('${label} mode at producer +0x${offset_hex(instruction.offset)} is no longer a static bit')
					}
					encoder_calls << j.Value(map[string]j.Value{
						'producer_offset': scalar(instruction.offset)
						'selector':        j.Value(resolved)
						'mode':            j.Value(mode)
						'value_source':    expr(classify_value_argument(buffered, index, 4)!)
					})
				}
			}
		}
		if found.len == 0 { return error('${label} producer emits no register selectors') }
		for candidate, _ in found {
			if candidate & 6 != 0 {
				return error('${label} selector 0x${candidate:x} sets a template-owned bit')
			}
			if candidate & ~u64(1) & 7 != 0 {
				return error('${label} selector 0x${candidate:x} is not 8-byte aligned')
			}
		}
		mut emission_sites := 0
		for index, instruction in buffered {
			if instruction.word & 0xffc00000 != 0x11000000 || (instruction.word >> 10) & 0xfff != 12 {
				continue
			}
			for following in instruction_block(buffered, index + 1, index + 3) {
				if following.word & 0xfffffc00 == 0x790e1400 {
					emission_sites++
					break
				}
			}
		}
		if emission_sites <= found.len {
			return error('${label} selector sample is no longer smaller than its ${emission_sites} emission sites')
		}
		mut resolved := map[u64]bool{}
		for entry_value in encoder_calls {
			entry := entry_value.as_map()
			resolved[at(entry, 'selector').u64()] = true
		}
		for candidate, _ in resolved {
			if candidate & ~selector_field != 0 {
				return error('${label} resolved selector 0x${candidate:x} exceeds the field')
			}
		}
		if encoder_calls.len == 0 {
			return error('${label} producer has no classified encoder calls')
		}
		mut literals := map[u64]bool{}
		for encoded, _ in found {
			literals[encoded & ~u64(1)] = true
			encoded_union[encoded] = true
		}
		mut static_values := literals.clone()
		for selector, _ in resolved { static_values[selector] = true }
		for selector, _ in literals { selector_union[selector] = true }
		for selector, _ in static_values { static_union[selector] = true }
		mut summary := map[string]j.Value{
			'producer':                          j.Value(name)
			'literal_encoded_fields':            j.Value(found.len)
			'literal_selectors':                 j.Value(literals.len)
			'entry_emission_sites':              j.Value(emission_sites)
			'encoded_fields':                    sorted_set(found)
			'selectors':                         sorted_set(literals)
			'encoder_call_sites':                j.Value(encoder_calls.len)
			'statically_resolved_encoder_calls': j.Value(encoder_calls.len)
			'resolved_encoder_selectors':        sorted_set(resolved)
			'static_selectors':                  sorted_set(static_values)
			'encoder_entries':                   j.Value(encoder_calls)
			'dynamic_append_entries':            j.Value(dynamic_appends)
		}
		keys := ['mode_0_calls', 'mode_1_calls', 'constant_value_calls', 'descriptor_value_calls',
			'indirect_value_calls', 'computed_value_calls', 'traced_copy_value_calls',
			'copy_value_calls', 'recovered_copy_expression_calls', 'unresolved_copy_value_calls',
			'recovered_expression_calls', 'recovered_conditional_calls', 'append_entries']
		mut counts := []int{len: keys.len}
		for entry_value in encoder_calls {
			entry := entry_value.as_map()
			value := at(entry, 'value_source').as_map()
			if at(entry, 'mode').u64() == 0 { counts[0]++ } else { counts[1]++ }
			for index, kind in ['constant', 'descriptor_load', 'indirect_load', 'computed'] {
				if text(value, 'kind') == kind { counts[index + 2]++ }
			}
			if 'via_register' in value { counts[6]++ }
			if text(value, 'operation') == 'register_copy' {
				counts[7]++
				if 'expression' in value { counts[8]++ } else { counts[9]++ }
			}
			if 'expression' in value {
				counts[10]++
				if text(value, 'operation') == 'conditional' { counts[11]++ }
			}
			if text(entry, 'form') == 'append' { counts[12]++ }
		}
		for index, key in keys { summary[key] = j.Value(counts[index]) }
		mut complete := true
		for entry_value in dynamic_appends {
			entry := entry_value.as_map()
			if j.value(entry, 'selector_formula') is json2.Null { complete = false }
		}
		summary['append_selectors_complete'] = j.Value(complete)
		producers[label] = j.Value(summary)
	}
	mut maximum := u64(0)
	for selector, _ in static_union { if selector > maximum { maximum = selector } }
	return {
		'template_mask':                   j.Value(u32(0xfffc0006))
		'encoded_field':                   j.Value(settable)
		'selector_field':                  j.Value(selector_field)
		'mode_bit':                        j.Value(1)
		'flag_bit':                        j.Value(1)
		'alignment':                       j.Value(8)
		'address_space_identified':        j.Value(false)
		'selectors_complete':              j.Value(false)
		'selector_formulas_complete':      j.Value(false)
		'completeness_note':               j.Value('every virtual encoder and 3D/TA/FastBlit append selector is statically resolved, but the finite static selector set excludes two inline CL words and six CL appends whose selectors are runtime-dependent')
		'distinct_literal_encoded_fields': j.Value(encoded_union.len)
		'distinct_literal_selectors':      j.Value(selector_union.len)
		'distinct_static_selectors':       j.Value(static_union.len)
		'maximum_selector':                j.Value(maximum)
		'producers':                       j.Value(producers)
	}
}

fn optional_expression(value ?map[string]j.Value) j.Value {
	if node := value { return expr(node) }
	return j.Value(json2.null)
}

pub fn inline_register_records(data []u8) !map[string]j.Value {
	return inline_register_records_with_source(DriverImage{data})
}

pub fn inline_register_records_with_source(source ImageSource) !map[string]j.Value {
	require_producers(source)!
	mut codes := map[string][]u8{}
	for label, name in producer_names() {
		_, code := source.code(name)!
		codes[label] = code
	}
	for label in ['3D', 'TA', 'FastBlit', 'CL'] {
		proof_label := 'G17 ${label} inline register records'
		arm.require_instruction_words_at(codes[label], proof_label, proof_words(proof_label))!
	}
	return {
		'static_record_count':         j.Value(8)
		'dynamic_record_count':        j.Value(2)
		'all_inline_forms_located':    j.Value(true)
		'all_inline_values_recovered': j.Value(true)
		'control_flow_complete':       j.Value(false)
		'static_records':              static_records()
		'dynamic_records':             dynamic_records()
	}
}

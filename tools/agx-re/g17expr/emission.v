module g17expr

import json2
import math.big
import traceanalysis as j

struct EmissionCfg {
	instructions []Instruction
	positions    map[string]int
	events       map[string]bool
}

struct EventOutcome {
	next    []big.Integer
	returns bool
	traps   bool
}

fn event_return(item Instruction) bool {
	return item.exact_word && item.word in [u32(0xd65f03c0), 0xd65f0bff, 0xd65f0fff]
}

fn event_break(item Instruction) bool { return item.word & 0xffe0001f == 0xd4200000 }

fn (cfg EmissionCfg) successors(index int) ![]int {
	item := cfg.instructions[index]
	if target := branch_target('decode_b_target', item) {
		position := cfg.positions[target.str()] or { return error('G17 branch at ${command_hex(item.offset)} leaves its producer') }
		return [position]
	}
	if target := branch_target('decode_local_branch_target', item) {
		position := cfg.positions[target.str()] or { return error('G17 branch at ${command_hex(item.offset)} leaves its producer') }
		return if index + 1 < cfg.instructions.len { [position, index + 1] } else { [position] }
	}
	if event_break(item) || event_return(item) { return []int{} }
	return if index + 1 < cfg.instructions.len { [index + 1] } else { []int{} }
}

fn (cfg EmissionCfg) next_events(starts []int) !EventOutcome {
	mut pending := starts.clone()
	mut seen := map[int]bool{}
	mut found := map[string]big.Integer{}
	mut returns := false
	mut traps := false
	for pending.len > 0 {
		index := pending.pop()
		if index in seen { continue }
		seen[index] = true
		item := cfg.instructions[index]
		if item.offset.str() in cfg.events {
			found[item.offset.str()] = item.offset
			continue
		}
		following := cfg.successors(index)!
		if following.len == 0 {
			traps = traps || event_break(item)
			returns = returns || event_return(item) || index + 1 == cfg.instructions.len
		} else {
			pending << following
		}
	}
	mut next := found.values()
	next.sort(a < b)
	return EventOutcome{next, returns, traps}
}

fn outcome(node EventOutcome, traps bool) j.Value {
	mut result := map[string]j.Value{
		'next':       j.Value(node.next.map(scalar(it)))
		'can_return': j.Value(node.returns)
	}
	if traps { result['can_trap'] = j.Value(node.traps) }
	return expr(result)
}

fn event_offsets(values []j.Value) ![]big.Integer {
	mut unique := map[string]big.Integer{}
	for value in values {
		number := request_big({
			'value': value
		}, 'value', 0)!
		unique[number.str()] = number
	}
	mut sorted := unique.values()
	sorted.sort(a < b)
	return sorted
}

pub fn emission_cfg(instructions []Instruction, event_list []big.Integer) !map[string]j.Value {
	if instructions.len == 0 { return error('G17 emission CFG has no instructions') }
	mut positions := map[string]int{}
	for index, item in instructions { positions[item.offset.str()] = index }
	if positions.len != instructions.len {
		return error('G17 emission CFG has duplicate instruction offsets')
	}
	mut events := map[string]bool{}
	mut sorted := event_list.clone()
	sorted.sort(a < b)
	mut missing := []j.Value{}
	for offset in sorted {
		events[offset.str()] = true
		if offset.str() !in positions { missing << scalar(offset) }
	}
	if missing.len > 0 {
		return error('G17 emission offsets are not instructions: ' + j.string_value(j.Value(missing)))
	}
	cfg := EmissionCfg{instructions, positions, events}
	mut reachable := map[int]bool{}
	mut pending := [0]
	for pending.len > 0 {
		index := pending.pop()
		if index in reachable { continue }
		reachable[index] = true
		pending << cfg.successors(index)!
	}
	mut unreachable := []j.Value{}
	for offset in sorted {
		if positions[offset.str()] !in reachable { unreachable << scalar(offset) }
	}
	if unreachable.len > 0 {
		return error('G17 emission events are unreachable: ' + j.string_value(j.Value(unreachable)))
	}
	first := cfg.next_events([0])!
	mut nodes := []j.Value{}
	mut loops := 0
	mut edges := 0
	for offset in sorted {
		following := cfg.next_events(cfg.successors(positions[offset.str()])!)!
		for target in following.next { if target <= offset { loops++ } }
		edges += following.next.len
		mut node := outcome(following, true).as_map()
		node['producer_offset'] = scalar(offset)
		nodes << expr(node)
	}
	mut decisions := []j.Value{}
	mut guards := 0
	mut indices := reachable.keys()
	indices.sort()
	for index in indices {
		item := instructions[index]
		target := branch_target('decode_local_branch_target', item) or { continue }
		if _ := branch_target('decode_b_target', item) { continue }
		branches := cfg.successors(index)!
		if branches.len != 2 { continue }
		taken := cfg.next_events([branches[0]])!
		fallthrough := cfg.next_events([branches[1]])!
		if taken == fallthrough { continue }
		if (taken.next.len == 0 && !taken.returns && taken.traps) || (fallthrough.next.len == 0 && !fallthrough.returns && fallthrough.traps) {
			guards++
			continue
		}
		flags := fields('decode_conditional_branch', item.word, item.offset)
		compare_zero := decoded_object_at('decode_compare_zero_branch', item)
		test_bit := decoded_object_at('decode_test_bit_branch', item)
		mut kind := 'flags'
		mut condition := j.Value(json2.null)
		mut register := j.Value(json2.null)
		if f := flags {
			condition = f[1]
		} else if c := compare_zero {
			kind = 'compare_zero'
			condition = at(c, 'condition')
			register = at(c, 'register')
		} else if t := test_bit {
			kind = 'test_bit'
			condition = at(t, 'condition')
			register = at(t, 'register')
		}
		decisions << expr({
			'producer_offset': scalar(item.offset)
			'target_offset':   scalar(target)
			'kind':            j.Value(kind)
			'condition':       condition
			'register':        register
			'taken':           outcome(taken, false)
			'fallthrough':     outcome(fallthrough, false)
		})
	}
	return {
		'entry':                   j.Value(first.next.map(scalar(it)))
		'empty_return_path':       j.Value(first.returns)
		'pre_emission_trap':       j.Value(first.traps)
		'event_count':             j.Value(events.len)
		'edge_count':              j.Value(edges)
		'loop_edge_count':         j.Value(loops)
		'semantic_decision_count': j.Value(decisions.len)
		'trap_guard_count':        j.Value(guards)
		'decisions':               j.Value(decisions)
		'nodes':                   j.Value(nodes)
	}
}

fn register_emission_cfg(image CommandImage, selectors map[string]j.Value, inline_records map[string]j.Value) !map[string]j.Value {
	static_records := at(inline_records, 'static_records').as_map()
	dynamic_records := at(inline_records, 'dynamic_records').as_map()
	mut producers := map[string]j.Value{}
	mut complete := true
	for label, name in producer_names() {
		_, code := image.code(name)!
		producer := at(at(selectors, 'producers').as_map(), label).as_map()
		calls := at(producer, 'encoder_entries').arr()
		mut entries := calls.clone()
		entries << at(producer, 'dynamic_append_entries').arr()
		entries << at(static_records, label).arr()
		entries << at(dynamic_records, label).arr()
		mut values := []j.Value{}
		for item in entries {
			values << scalar(command_integer(at(item.as_map(), 'producer_offset'))!)
		}
		events := event_offsets(values)!
		instructions := instructions_from_code(code)
		mut graph := emission_cfg(instructions, events)!
		mut recovered := 0
		mut decisions := []j.Value{}
		for item in at(graph, 'decisions').arr() {
			mut decision := item.as_map().clone()
			offset := request_big(decision, 'producer_offset', 0)!
			index := position(instructions, offset) or { return error('KeyError: ' + offset.str()) }
			instruction := instructions[index]
			mut predicate := map[string]j.Value{}
			mut has_predicate := false
			if _ := fields('decode_conditional_branch', instruction.word, instruction.offset) {
				if value := condition_expression(instructions, index, 0, []Visit{}) {
					predicate = value.clone()
					has_predicate = true
				}
			} else {
				compare_zero := decoded_object_at('decode_compare_zero_branch', instruction)
				decoded := (compare_zero or { decoded_object_at('decode_test_bit_branch', instruction) or { return error('missing branch decoder') } }).clone()
				mut source := map[string]j.Value{}
				mut has_source := false
				if value := value_expression(instructions, index, number(decoded, 'register'), 0, []Visit{}) {
					source = value.clone()
					has_source = true
				}
				if !has_source && label == '3D' && offset == big.integer_from_int(0xf8) {
					command_check(code, 'G17 3D register-list pass induction')!
					has_source = true
					source = map[string]j.Value{
						'kind':    j.Value('loop_induction')
						'name':    j.Value('pass')
						'initial': j.Value(0)
						'step':    j.Value(1)
						'limit':   j.Value(4)
						'bytes':   j.Value(4)
					}
				}
				if has_source {
					mut node := map[string]j.Value{
						'kind':            j.Value('condition')
						'producer_offset': scalar(offset)
						'operation':       j.Value(if compare_zero != none {
							'compare_zero'
						} else {
							'test_bit'
						})
						'bytes':           at(decoded, 'bytes')
						'source':          expr(source)
					}
					if 'bit' in decoded { node['bit'] = at(decoded, 'bit') }
					predicate = node.clone()
					has_predicate = true
				}
			}
			if has_predicate {
				decision['predicate'] = expr(predicate)
				recovered++
			}
			decisions << expr(decision)
		}
		graph['decisions'] = j.Value(decisions)
		graph['recovered_predicate_count'] = j.Value(recovered)
		graph['predicates_complete'] = j.Value(recovered == number(graph, 'semantic_decision_count'))
		graph['virtual_call_events'] = j.Value(calls.len)
		graph['inline_events'] = j.Value(events.len - calls.len)
		complete = complete && recovered == number(graph, 'semantic_decision_count')
		producers[label] = expr(graph)
	}
	return {
		'machine_order_complete':         j.Value(true)
		'predicate_expressions_complete': j.Value(complete)
		'producers':                      expr(producers)
	}
}

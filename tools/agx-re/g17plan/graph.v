module g17plan

import traceanalysis { Value }
import math.big

fn catalog_integer(item Value, label string) !Value {
	return Value(traceanalysis.Number{(big.integer_from_string(integer_text(item, label)!)!).str()})
}

pub fn catalog(abi map[string]Value, producer string) !map[int]map[string]Value {
	channels := required_obj(abi, 'channels')!
	selectors := required_obj(channels, 'register_selectors')!
	if !truth(val(selectors, 'selector_formulas_complete')) {
		return error('recovered selector formulas are incomplete')
	}
	producers := required_obj(selectors, 'producers')!
	if producer !in producers {
		return error('no recovered register producer ${repr(Value(producer))}')
	}
	data := obj(producers, producer)
	if truth(val(data, 'dynamic_append_entries')) {
		return error('${producer} appends registers with runtime selectors')
	}
	mut output := map[int]map[string]Value{}
	for raw in required(data, 'encoder_entries')!.arr() {
		node := raw.as_map()
		offset := field(node, 'producer_offset', 'producer offset')!
		output[offset] = {
			'producer_offset': Value(offset)
			'selector':        catalog_integer(required(node, 'selector')!, 'selector')!
			'mode':            catalog_integer(required(node, 'mode')!, 'mode')!
			'value_source':    required(node, 'value_source')!
			'form':            default_value(node, 'form', Value('virtual'))
		}
	}
	inline := required_obj(channels, 'inline_register_records')!
	if !truth(val(inline, 'all_inline_forms_located')) || !truth(val(inline, 'all_inline_values_recovered')) {
		return error('recovered inline register records are incomplete')
	}
	for raw in val(obj(inline, 'static_records'), producer).arr() {
		node := raw.as_map()
		offset := field(node, 'producer_offset', 'inline producer offset')!
		if offset in output {
			return error('duplicate event at producer offset ${hex_offset(offset)}')
		}
		if 'value' !in node {
			return error('inline event ${hex_offset(offset)} has no reproducible value')
		}
		output[offset] = {
			'producer_offset': Value(offset)
			'selector':        catalog_integer(required(node, 'selector')!, 'inline selector')!
			'mode':            catalog_integer(required(node, 'mode')!, 'inline mode')!
			'value_source':    Value(map[string]Value{
				'kind':  Value('constant')
				'value': required(node, 'value')!
			})
			'form':            Value('inline')
		}
	}
	if truth(val(obj(inline, 'dynamic_records'), producer)) {
		return error('dynamic inline ${producer} selectors are not supported')
	}
	return output
}

fn emission_graph(abi map[string]Value) map[string]Value {
	return val(obj(obj(obj(abi, 'channels'), 'register_emission_cfg'), 'producers'), '3D').as_map()
}

fn graph_nodes(g map[string]Value) !map[int]map[string]Value {
	mut nodes := map[int]map[string]Value{}
	for raw in required(g, 'nodes')!.arr() {
		node := raw.as_map()
		nodes[field(node, 'producer_offset', 'CFG node offset')!] = node
	}
	return nodes
}

fn possible(decision map[string]Value) ![]int {
	return offset_union(offsets(val(obj(decision, 'taken'), 'next'))!, offsets(val(obj(decision, 'fallthrough'), 'next'))!)
}

fn choose(decision map[string]Value, descriptor []u8, command []u8, overrides map[int]bool) !map[string]Value {
	taken := required_obj(decision, 'taken')!
	fallthrough := required_obj(decision, 'fallthrough')!
	if same_set(offsets(val(taken, 'next'))!, offsets(val(fallthrough, 'next'))!) { return taken }
	offset := field(decision, 'producer_offset', 'decision offset')!
	outcome := condition(required_obj(decision, 'predicate')!, text(decision, 'condition'), descriptor, command) or {
		if err.code() != unresolved_code { return err }
		if offset !in overrides {
			return error('decision ${hex_offset(offset)} needs an explicit taken/fallthrough override: ${err.msg()}')
		}
		overrides[offset]
	}
	return if outcome { taken } else { fallthrough }
}

pub fn derive_path(abi map[string]Value, descriptor []u8, command []u8, overrides map[int]bool) ![]int {
	g := emission_graph(abi)
	events := catalog(abi, '3D')!
	nodes := graph_nodes(g)!
	decisions := sort_offsets(val(g, 'decisions').arr())!
	mut entries := offsets(val(g, 'entry'))!
	if entries.len != 1 { return error('3D graph has ${entries.len} entry events') }
	first := entries[0]
	for decision in decisions {
		offset := field(decision, 'producer_offset', 'decision offset')!
		if offset >= first { break }
		if !same_set(possible(decision)!, entries) { continue }
		outcome := choose(decision, descriptor, command, overrides)!
		entries = offsets(val(outcome, 'next'))!
		if entries.len == 0 {
			if truth(val(outcome, 'can_return')) { return []int{} }
			return error('decision ${hex_offset(offset)} has no successor')
		}
	}
	mut current := entries[0]
	mut path := []int{}
	for {
		if current !in nodes || current !in events {
			return error('3D graph references unknown event ${hex_offset(current)}')
		}
		if current in path {
			return error('3D graph loops before a pass return at ${hex_offset(current)}')
		}
		path << current
		node := nodes[current]
		if truth(val(node, 'can_return')) { return path }
		mut allowed := offsets(val(node, 'next'))!
		for allowed.len > 1 {
			mut found := false
			for decision in decisions {
				if field(decision, 'producer_offset', 'decision offset')! <= current || !same_set(possible(decision)!, allowed) {
					continue
				}
				outcome := choose(decision, descriptor, command, overrides)!
				allowed = offsets(val(outcome, 'next'))!
				if allowed.len == 0 {
					if truth(val(outcome, 'can_return')) { return path }
					return error('decision ${hex_offset(field(decision, 'producer_offset', 'decision offset')!)} has no successor')
				}
				found = true
				break
			}
			if !found {
				mut ordered := allowed.clone()
				ordered.sort()
				return error('events after ${hex_offset(current)} remain ambiguous: ' + ordered.map(hex_offset(it)).join(', '))
			}
		}
		if allowed.len == 0 {
			return error('event ${hex_offset(current)} cannot reach a recovered return')
		}
		current = allowed[0]
	}
	return path
}

fn matches(event map[string]Value, observation map[string]Value) bool {
	// Catalog integers remain unbounded until the producer masks them. A wide
	// or negative selector must not silently become a matching captured word.
	selector := integer_text(val(event, 'selector'), 'selector') or { return false }
	mode := integer_text(val(event, 'mode'), 'mode') or { return false }
	return selector == val(observation, 'selector').u64().str() &&
		mode == val(observation, 'mode').u64().str()
}

fn match_path(g map[string]Value, events map[int]map[string]Value, observations []map[string]Value, descriptor []u8, command []u8) ![]int {
	if observations.len == 0 {
		if truth(val(g, 'empty_return_path')) { return []int{} }
		return error('empty register pass has no recovered return path')
	}
	nodes := graph_nodes(g)!
	if !same_set(nodes.keys(), events.keys()) {
		mut missing := offset_union(nodes.keys(), events.keys()).filter(it !in nodes || it !in events)
		missing.sort()
		return error('event catalog and CFG disagree at offsets ${missing}')
	}
	mut paths := [][]int{}
	for offset in offsets(val(g, 'entry'))! {
		if offset in events && matches(events[offset], observations[0]) { paths << [offset] }
	}
	for index in 1 .. observations.len {
		observation := observations[index]
		mut next_paths := [][]int{}
		for path in paths {
			for offset in offsets(val(nodes[path.last()], 'next'))! {
				if offset in events && matches(events[offset], observation) {
					mut new_path := path.clone()
					new_path << offset
					if !next_paths.any(it == new_path) { next_paths << new_path }
				}
			}
		}
		paths = next_paths.clone()
		if paths.len == 0 {
			return error('no recovered 0x${val(observation, 'selector').u64():x}/mode-${val(observation, 'mode').u64()} event follows entry ${index - 1}')
		}
		if paths.len > 4096 { return error('register CFG match became ambiguous') }
	}
	finished := paths.filter(truth(val(nodes[it.last()], 'can_return')))
	if finished.len == 0 {
		return error('observed register pass does not reach a recovered return')
	}
	mut matching := [][]int{}
	for path in finished {
		mut valid := true
		for index, offset in path {
			value := evaluate(required(events[offset], 'value_source')!, descriptor, command) or {
				if err.code() == unresolved_code { continue }
				return err
			}
			if value != val(observations[index], 'value').u64() {
				valid = false
				break
			}
		}
		if valid { matching << path }
	}
	if matching.len == 0 {
		return error('observed values do not match any recovered register path')
	}
	if matching.len != 1 {
		return error('observed register pass matches ${matching.len} recovered paths')
	}
	return matching[0]
}

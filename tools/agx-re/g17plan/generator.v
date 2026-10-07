module g17plan

import traceanalysis { Value }
import crypto.sha256

pub fn fingerprint(abi map[string]Value) string {
	channels := obj(abi, 'channels')
	mut selected := map[string]Value{
		'driver_uuid':   val(abi, 'driver_uuid')
		'firmware_uuid': val(abi, 'firmware_uuid')
		'schema':        val(abi, 'schema')
		'layout':        val(channels, 'command_3d_register_lists')
		'codec':         val(channels, 'register_entry_codec')
		'selectors':     val(obj(obj(channels, 'register_selectors'), 'producers'), '3D')
		'inline':        val(obj(obj(channels, 'inline_register_records'), 'static_records'), '3D')
		'cfg':           Value(emission_graph(abi))
	}
	if 'accelerator_inputs' in channels {
		selected['accelerator'] = val(channels, 'accelerator_inputs')
	}
	return sha256.sum(encode(Value(selected), false).bytes()).hex()
}

fn longest_visit(offset int, nodes map[int]map[string]Value, active []int) !int {
	if offset in active { return error('3D graph loops before return at ${hex_offset(offset)}') }
	node := (nodes[offset] or { return error('${offset}') }).clone()
	if truth(val(node, 'can_return')) { return 1 }
	next := offsets(val(node, 'next'))!
	if next.len == 0 { return error('3D event ${hex_offset(offset)} has no return path') }
	mut best := 0
	mut visited := active.clone()
	visited << offset
	for n in next {
		count := longest_visit(n, nodes, visited)!
		if count > best { best = count }
	}
	return best + 1
}

fn validate(abi map[string]Value) !(map[int]map[string]Value, int) {
	channels := required_obj(abi, 'channels')!
	layout := required_obj(channels, 'command_3d_register_lists')!
	codec := required_obj(channels, 'register_entry_codec')!
	cfg := required_obj(channels, 'register_emission_cfg')!
	g := emission_graph(abi)
	if !truth(val(layout, 'record_framing_resolved')) {
		return error('3D command framing is incomplete')
	}
	if !truth(val(cfg, 'machine_order_complete')) {
		return error('3D emission graph is incomplete')
	}
	if !truth(val(g, 'predicates_complete')) { return error('3D predicates are incomplete') }
	for name, expected in {
		'command_bytes':      0x2240
		'passes':             4
		'stride':             0x720
		'stream_offset':      0xa0
		'stream_bytes':       0x700
		'gpu_address_offset': 0x7a0
		'entry_count_offset': 0x7a8
		'byte_length_offset': 0x7aa
		'entry_bytes':        12
	} {
		if int_value(val(layout, name), name) or { -1 } != expected {
			return error('unexpected 3D ${name}: ${repr(val(layout, name))}')
		}
	}
	for name, expected in {
		'selector_mask':           u64(0x3fff8)
		'mode_mask':               u64(1)
		'preserved_template_mask': u64(0xfffc0006)
		'value_offset':            u64(4)
	} {
		if int_value(val(codec, name), name) or { -1 } != int(expected) {
			return error('unexpected register codec ${name}')
		}
	}
	entries := offsets(val(g, 'entry'))!
	if entries.len != 1 { return error('generated 3D graph needs one entry event') }
	first := entries[0]
	for raw in val(g, 'decisions').arr() {
		d := raw.as_map()
		offset := field(d, 'producer_offset', 'decision offset')!
		if offset >= first || !same_set(possible(d)!, entries) { continue }
		if same_set(offsets(val(obj(d, 'taken'), 'next'))!, offsets(val(obj(d, 'fallthrough'), 'next'))!) {
			continue
		}
		outcome := condition(required_obj(d, 'predicate')!, text(d, 'condition'), []u8{len: descriptor_bytes}, []u8{len: 0x2240}) or {
			if err.code() != unresolved_code { return err }
			return error('pre-entry decision ${hex_offset(offset)} is dynamic')
		}
		selected := obj(d, if outcome { 'taken' } else { 'fallthrough' })
		if !same_set(offsets(val(selected, 'next'))!, entries) {
			return error('pre-entry decision ${hex_offset(offset)} can skip a pass')
		}
	}
	events := catalog(abi, '3D')!
	nodes := graph_nodes(g)!
	if !same_set(nodes.keys(), events.keys()) { return error('3D event catalog and CFG differ') }
	mut best := 0
	for entry in entries {
		count := longest_visit(entry, nodes, []int{})!
		if count > best { best = count }
	}
	return events, best
}

fn successor_expression(allowed []int, current int, decisions []map[string]Value, used []int, mut externals map[int]int) !string {
	if allowed.len == 1 { return u32_text(allowed[0]) }
	mut selected := map[string]Value{}
	mut found := false
	for decision in decisions {
		offset := field(decision, 'producer_offset', 'decision offset')!
		if offset > current && offset !in used && same_set(possible(decision)!, allowed) {
			selected = copy_object(decision)
			found = true
			break
		}
	}
	if !found {
		mut ordered := allowed.clone()
		ordered.sort()
		return error('cannot generate successor after ${hex_offset(current)}: ' + ordered.map(hex_offset(it)).join(', '))
	}
	offset := field(selected, 'producer_offset', 'decision offset')!
	mut test := ''
	if external_root(val(selected, 'predicate')) {
		if offset !in externals { externals[offset] = externals.len }
		test = 'inputs.decisions[pass][${externals[offset]}] != 0'
	} else {
		test = render_predicate(obj(selected, 'predicate'), text(selected, 'condition'), 'descriptor', 'command', false)!
	}
	mut used_next := used.clone()
	used_next << offset
	mut results := []string{}
	for name in ['taken', 'fallthrough'] {
		outcome := obj(selected, name)
		next := offsets(val(outcome, 'next'))!
		if next.len == 0 {
			if truth(val(outcome, 'can_return')) {
				results << u32_text(0)
				continue
			}
			return error('decision ${hex_offset(offset)} has no successor')
		}
		results << successor_expression(next, current, decisions, used_next, mut externals)!
	}
	return 'if ${test} { ${results[0]} } else { ${results[1]} }'
}

pub struct Generated {
pub:
	header             string
	source             string
	external_events    []int
	external_decisions []int
	max_writes         int
}

pub fn generate(abi map[string]Value, source_template string, header_template string) !Generated {
	folded := fold_accelerator_inputs(abi, map[string]u64{})!
	digest := fingerprint(folded)
	events, longest := validate(folded)!
	g := emission_graph(folded)
	decisions := sort_offsets(val(g, 'decisions').arr())!
	mut event_offsets := events.keys()
	event_offsets.sort()
	external_events := event_offsets.filter(external_root(val(events[it], 'value_source')))
	mut external_decision_map := map[int]int{}
	mut event_cases := []string{}
	for offset in event_offsets {
		event := events[offset]
		mut value_lines := ''
		index := external_events.index(offset)
		if index >= 0 {
			evaluated := render_expression(required(event, 'value_source')!, 'descriptor', 'command', true)!
			value_lines = '                evaluated = ${evaluated}\n                *value = if evaluated.resolved != 0 { evaluated.value } else {\n                    inputs.values[pass][${index}] }'
		} else {
			value := render_expression(required(event, 'value_source')!, 'descriptor', 'command', false)!
			value_lines = '                *value = ${value}'
		}
		event_cases << '            ${u32_text(offset)} {\n                *selector = u32(0x${masked_integer(val(event, 'selector'), 'selector')! & 0xffffffff:x})\n                *mode = u32(0x${masked_integer(val(event, 'mode'), 'mode')! & 0xffffffff:x})\n${value_lines}\n                return 1\n            }'
	}
	nodes := sort_offsets(val(g, 'nodes').arr())!
	mut node_cases := []string{}
	for node in nodes {
		offset := field(node, 'producer_offset', 'node offset')!
		successor := if truth(val(node, 'can_return')) {
			u32_text(0)
		} else {
			successor_expression(offsets(val(node, 'next'))!, offset, decisions, []int{}, mut external_decision_map)!
		}
		node_cases << '            ${u32_text(offset)} { return ${successor} }'
	}
	mut external_decisions := []int{len: external_decision_map.len}
	for offset, index in external_decision_map { external_decisions[index] = offset }
	mut decision_check := ''
	mut fields := []string{}
	if external_decisions.len > 0 {
		fields << '    decisions [4][${external_decisions.len}]u8'
		decision_check = '        for pass := u32(0); pass < u32(C.VINIX_FAKE_G17_REGISTER_PASSES); pass++ {\n            for decision := u32(0); decision < u32(C.VINIX_FAKE_G17_EXTERNAL_DECISION_COUNT); decision++ {\n                if inputs.decisions[pass][decision] > 1 { return C.VINIX_FAKE_G17_ENCODE_INVALID_ARGUMENT }\n            }\n        }'
	}
	if external_events.len > 0 { fields << '    values [4][${external_events.len}]u64' }
	names := hardware_inputs(folded)!
	for name in names { fields << '    ${name} u32' }
	mut source := source_template
	for key, value in {
		'fingerprint':    digest
		'input_fields':   fields.join('\n')
		'event_cases':    event_cases.join('\n')
		'node_cases':     node_cases.join('\n')
		'decision_check': decision_check
		'entry':          u32_text(offsets(val(g, 'entry'))![0])
	} {
		source = source.replace('@${key}@', value)
	}
	mut enums := []string{}
	mut cfields := []string{}
	if external_events.len > 0 {
		mut constants := []string{}
		for index, offset in external_events {
			constants << '    VINIX_FAKE_G17_EXTERNAL_EVENT_${offset:04X} = ${index},'
		}
		enums << 'enum vinix_fake_g17_external_event {\n' + constants.join('\n') + '\n};\n'
		cfields << '    uint64_t values[VINIX_FAKE_G17_REGISTER_PASSES]\n                   [VINIX_FAKE_G17_EXTERNAL_EVENT_COUNT];'
	}
	if external_decisions.len > 0 {
		mut constants := []string{}
		for index, offset in external_decisions {
			constants << '    VINIX_FAKE_G17_EXTERNAL_DECISION_${offset:04X} = ${index},'
		}
		enums << 'enum vinix_fake_g17_external_decision {\n' + constants.join('\n') + '\n};\n'
		cfields.insert(0, '    uint8_t decisions[VINIX_FAKE_G17_REGISTER_PASSES]\n                     [VINIX_FAKE_G17_EXTERNAL_DECISION_COUNT];')
	}
	for name in names { cfields << '    uint32_t ${name};' }
	max_writes := longest * 4
	mut header := header_template
	for key, value in {
		'fingerprint':    digest
		'event_count':    external_events.len.str()
		'decision_count': external_decisions.len.str()
		'max_writes':     max_writes.str()
		'enum_text':      enums.join('\n')
		'field_text':     cfields.join('\n')
	} {
		header = header.replace('@${key}@', value)
	}
	return Generated{header, source, external_events, external_decisions, max_writes}
}

module g17plan

import traceanalysis { Value }
import os
import json2

fn fixture(name string) map[string]Value {
	return decode(os.read_file(os.join_path(os.dir(@FILE), 'fixtures', name + '.json')) or { panic(err) }) or { panic(err) }
}

fn encoded_fixture() ([]u8, []u8) {
	abi := fixture('synthetic')
	mut descriptor := []u8{len: descriptor_bytes}
	write(mut descriptor, 0, 4, 0x11223344) or { panic(err) }
	external := map[string]Value{
		'decisions': Value(map[string]Value{
			'0x80': Value('taken')
		})
		'values':    Value(map[string]Value{
			'0x400': Value([Value(u64(0xdeadbeef000)), Value(u64(0xdeadbeef001)),
				Value(u64(0xdeadbeef002)), Value(u64(0xdeadbeef003))])
		})
	}
	mut template := []u8{len: 0x2240}
	for p in 0 .. 4 {
		for e in 0 .. 5 {
			write(mut template, p * 0x720 + 0xa0 + e * 12, 4, 0xa5a40006) or { panic(err) }
		}
	}
	result := encode_3d(abi, descriptor, 0x700000000, template, Value(external)) or { panic(err) }
	return result.command, result.descriptor
}

fn parsed_node(source string) Value { return Value(decode(source) or { panic(err) }) }

fn test_bitfields_conditions_and_movk() {
	for source, expected in {
		'{"kind":"expression","operation":"ubfm","bytes":8,"rotate":40,"mask_end":0,"source":{"kind":"constant","value":1}}':                                                                                                                       u64(1) << 24
		'{"kind":"expression","operation":"ubfm","bytes":8,"rotate":60,"mask_end":63,"source":{"kind":"constant","value":17293822569102704640}}':                                                                                                   u64(15)
		'{"kind":"expression","operation":"bfm","bytes":8,"rotate":45,"mask_end":0,"source":{"kind":"constant","value":1},"destination":{"kind":"constant","value":0}}':                                                                            u64(1) << 19
		'{"kind":"expression","operation":"movk","bytes":8,"shift":16,"immediate":43981,"source":{"kind":"constant","value":1234605616436508552}}':                                                                                                 u64(0x11223344abcd7788)
		'{"kind":"expression","operation":"csel","bytes":8,"condition":"hi","predicate":{"operation":"cmp","source":{"kind":"constant","value":9},"immediate":4},"first":{"kind":"constant","value":170},"second":{"kind":"constant","value":85}}': u64(170)
	} {
		assert evaluate(parsed_node(source), []u8{}, []u8{}) or { panic(err) } == expected
	}
	p := decode('{"operation":"compare_zero","bytes":4,"source":{"kind":"constant","value":0}}') or { panic(err) }
	assert condition(p, 'zero', []u8{}, []u8{}) or { panic(err) }
	assert !(condition(p, 'nonzero', []u8{}, []u8{}) or { panic(err) })
}

fn test_compiles_exact_plan_and_reference_encoder() {
	command, descriptor := encoded_fixture()
	plan := compile_plan(fixture('synthetic'), command, descriptor, 0x700000000) or { panic(err) }
	assert text(plan, 'schema') == 'vinix.fake-g17-plan.v1'
	coverage := obj(plan, 'coverage')
	assert val(coverage, 'total_writes').int() == 20
	assert val(coverage, 'recovered_values').int() == 16
	assert val(coverage, 'external_values').int() == 4
	records := val(plan, 'writes').arr()
	assert val(records[2].as_map(), 'value').u64() == 0x11223344
	assert val(records[2].as_map(), 'value_mask').u64() == word_mask
	assert text(records[4].as_map(), 'value_status') == 'external'
	assert val(records[4].as_map(), 'value_mask').u64() == 0
	assert offsets(val(val(plan, 'passes').arr()[0].as_map(), 'producer_offsets')) or { panic(err) } == [
		0x50,
		0x100,
		0x200,
		0x300,
		0x400,
	]
	assert load(command, 0xa0, 4, false) or { panic(err) } & 0xfffc0006 == u64(0xa5a40006) & 0xfffc0006
	assert load(command, 0xa0 + 4 * 12 + 4, 8, false) or { panic(err) } == 0xdeadbeef000
	assert load(descriptor, 0x828, 8, false) or { panic(err) } == 0x7000000a0
}

fn test_reference_encoder_missing_inputs_and_fallthrough() {
	_, descriptor := encoded_fixture()
	abi := fixture('synthetic')
	if _ := encode_3d(abi, descriptor, 0x700000000, none, Value(json2.null)) {
		assert false
	} else {
		assert err.msg().contains('decision 0x80')
	}
	if _ := encode_3d(abi, descriptor, 0x700000000, none, Value(map[string]Value{
		'decisions': Value(map[string]Value{
			'0x80': Value(true)
		})
	})) {
		assert false
	} else {
		assert err.msg().contains('event 0x400')
	}
	result := encode_3d(abi, descriptor, 0x700000000, none, Value(map[string]Value{
		'decisions': Value(map[string]Value{
			'0x80': Value('fallthrough')
		})
		'values':    Value(map[string]Value{
			'0x400': Value(0)
		})
	})) or { panic(err) }
	assert val(obj(result.plan, 'coverage'), 'total_writes').int() == 16
	assert val(obj(result.plan, 'encoder'), 'zero_template') == Value(true)
	assert val(obj(result.plan, 'encoder'), 'paths').arr().len == 4
	assert val(obj(result.plan, 'encoder'), 'paths').arr()[0].arr().len == 4
	assert offsets(val(val(result.plan, 'passes').arr()[0].as_map(), 'producer_offsets')) or { panic(err) } == [
		0x50,
		0x200,
		0x300,
		0x400,
	]
}

fn test_plan_rejects_wrong_order_value_and_summary() {
	original, original_descriptor := encoded_fixture()
	mut command := original.clone()
	mut descriptor := original_descriptor.clone()
	write(mut command, 0xa0, 4, 0x3fff8) or { panic(err) }
	if _ := compile_plan(fixture('synthetic'), command, descriptor, 0x700000000) {
		assert false
	} else {
		assert err.msg().contains('recovered')
	}
	command = original.clone()
	write(mut command, 0xa4, 8, 2) or { panic(err) }
	if _ := compile_plan(fixture('synthetic'), command, descriptor, 0x700000000) {
		assert false
	} else {
		assert err.msg().contains('recovered')
	}
	command = original.clone()
	descriptor[0x828 + 10] = 1
	if _ := compile_plan(fixture('synthetic'), command, descriptor, 0x700000000) {
		assert false
	} else {
		assert err.msg().contains('summary mismatch')
	}
}

fn folded_values(abi map[string]Value) []Value {
	return val(val(obj(obj(obj(abi, 'channels'), 'register_selectors'), 'producers'), '3D').as_map(), 'encoder_entries').arr().map(val(it.as_map(), 'value_source'))
}

fn test_accelerator_folding_preserves_unknowns_and_original() {
	abi := fixture('folding')
	before := encode(Value(abi), false)
	folded := fold_accelerator_inputs(abi, map[string]u64{}) or { panic(err) }
	values := folded_values(folded)
	assert evaluate(values[0], []u8{}, []u8{}) or { panic(err) } == 0
	if _ := evaluate(values[1], []u8{}, []u8{}) {
		assert false
	} else {
		assert err.code() == unresolved_code
	}
	if _ := evaluate(values[2], []u8{}, []u8{}) {
		assert false
	} else {
		assert err.code() == unresolved_code && err.msg().contains('column_count')
	}
	assert evaluate(values[3], []u8{}, []u8{}) or { panic(err) } == 0
	decisions := val(emission_graph(folded), 'decisions').arr()
	assert condition(obj(decisions[0].as_map(), 'predicate'), 'eq', []u8{}, []u8{}) or { panic(err) }
	assert encode(Value(abi), false) == before
	assert encode(decisions[1], false) == encode(val(emission_graph(abi), 'decisions').arr()[1], false)
	unchanged := fixture('synthetic')
	assert encode(Value(fold_accelerator_inputs(unchanged, map[string]u64{}) or { panic(err) }), false) == encode(Value(unchanged), false)
}

fn test_hardware_topology_and_normalized_register_predicates() {
	for columns, expected in {
		4: u64(7)
		8: u64(9)
	} {
		values := folded_values(fold_accelerator_inputs(fixture('folding'), {
			'column_count': u64(columns)
		}) or { panic(err) })
		assert evaluate(values[2], []u8{}, []u8{}) or { panic(err) } == expected
	}
	p := decode('{"operation":"cmp","bytes":4,"first":{"kind":"descriptor_load","member":0,"bytes":4},"second":{"kind":"constant","value":8},"shift":"lsl","amount":1}') or { panic(err) }
	mut descriptor := []u8{len: 16}
	write(mut descriptor, 0, 4, 15) or { panic(err) }
	assert condition(p, 'cc', descriptor, []u8{}) or { panic(err) }
	assert !(condition(p, 'cs', descriptor, []u8{}) or { panic(err) })
	write(mut descriptor, 0, 4, 16) or { panic(err) }
	assert condition(p, 'hs', descriptor, []u8{}) or { panic(err) }
	assert 'source' in normalize_predicate(p) or { panic(err) }
}

fn templates() (string, string) {
	base := os.join_path(os.dir(@FILE), '../templates')
	return os.read_file(os.join_path(base, 'fake_g17_encoder.v.in')) or { panic(err) }, os.read_file(os.join_path(base, 'fake_g17_encoder.h.in')) or { panic(err) }
}

fn test_generated_synthetic_inputs_and_real_kernel_bytes() {
	source_template, header_template := templates()
	generated := generate(fixture('synthetic'), source_template, header_template) or { panic(err) }
	assert generated.external_events == [0x400]
	assert generated.external_decisions == [0x80]
	assert generated.max_writes == 20
	for token in ['VINIX_FAKE_G17_EXTERNAL_EVENT_COUNT = 1',
		'VINIX_FAKE_G17_EXTERNAL_DECISION_COUNT = 1', 'VINIX_FAKE_G17_MAX_WRITES = 20',
		'VINIX_FAKE_G17_EXTERNAL_EVENT_0400 = 0', 'VINIX_FAKE_G17_EXTERNAL_DECISION_0080 = 0'] {
		assert generated.header.contains(token)
	}
	assert generated.source.contains('inputs.values[pass][0]')
	assert generated.source.contains('inputs.decisions[pass][0] != 0')
	base := os.join_path(os.dir(@FILE), '..')
	abi_path := os.join_path(base, 'build/recovered-g17-abi.json')
	if os.exists(abi_path) {
		real := generate(decode(os.read_file(abi_path) or { panic(err) }) or { panic(err) }, source_template, header_template) or { panic(err) }
		assert real.header == os.read_file(os.join_path(base, '../../kernel/c/agx_fake_g17_encode.h')) or { panic(err) }
		assert real.source == os.read_file(os.join_path(base, '../../kernel/lib/agx_fake_g17_encode.v')) or { panic(err) }
	}
}

fn test_generator_hardware_input_and_integer_boundaries() {
	mut abi := fixture('synthetic')
	mut channels := copy_object(obj(abi, 'channels'))
	mut selectors := copy_object(obj(channels, 'register_selectors'))
	mut producers := copy_object(obj(selectors, 'producers'))
	mut producer := copy_object(obj(producers, '3D'))
	mut entries := val(producer, 'encoder_entries').arr().clone()
	mut entry := copy_object(entries[3].as_map())
	entry['value_source'] = folded_values(fixture('folding'))[2]
	entries[3] = entry
	producer['encoder_entries'] = entries
	producers['3D'] = producer
	selectors['producers'] = producers
	channels['register_selectors'] = selectors
	channels['accelerator_inputs'] = val(obj(fixture('folding'), 'channels'), 'accelerator_inputs')
	abi['channels'] = channels
	source, header := templates()
	result := generate(abi, source, header) or { panic(err) }
	assert result.external_events.len == 0
	assert result.header.contains('    uint32_t column_count;')
	assert !result.header.contains('values[')
	assert result.source.contains('inputs.column_count')
	assert masked_integer(Value(traceanalysis.Number{'-1'}), 'constant') or { panic(err) } == word_mask
	assert masked_integer(Value(traceanalysis.Number{'18446744073709551617'}), 'constant') or { panic(err) } == 1
	for value in [Value(true), Value('1'), Value(traceanalysis.Number{'1.0'})] {
		if _ := masked_integer(value, 'constant') {
			assert false
		}
	}
	assert encode(Value(decode('{"z":"🍷é","a":18446744073709551615}') or { panic(err) }), false) == '{"a":18446744073709551615,"z":"\\ud83c\\udf77\\u00e9"}'
}

fn test_catalog_selectors_do_not_wrap_into_captured_words() {
	command, descriptor := encoded_fixture()
	for key in ['selector', 'mode'] {
		for digits in ['-1', '18446744073709551616', '340282366920938463463374607431768216584'] {
			mut abi := fixture('synthetic')
			mut channels := copy_object(obj(abi, 'channels'))
			mut selectors := copy_object(obj(channels, 'register_selectors'))
			mut producers := copy_object(obj(selectors, 'producers'))
			mut producer := copy_object(obj(producers, '3D'))
			mut entries := val(producer, 'encoder_entries').arr().clone()
			mut entry := copy_object(entries[0].as_map())
			entry[key] = Value(traceanalysis.Number{digits})
			entries[0] = Value(entry)
			producer['encoder_entries'] = Value(entries)
			producers['3D'] = Value(producer)
			selectors['producers'] = Value(producers)
			channels['register_selectors'] = Value(selectors)
			abi['channels'] = Value(channels)
			events := catalog(abi, '3D') or { panic(err) }
			assert integer_text(val(events[0x100], key), key) or { panic(err) } == digits
			if _ := compile_plan(abi, command, descriptor, 0x700000000) {
				assert false
			} else {
				assert err.msg().contains('no recovered')
			}
		}
	}
}

fn test_plan_cli_writes_versioned_json() {
	path := os.join_path(os.temp_dir(), 'vinix-g17-plan-${os.getpid()}')
	os.mkdir(path) or { panic(err) }
	defer { os.rmdir_all(path) or { panic(err) } }
	command, descriptor := encoded_fixture()
	os.write_file(os.join_path(path, 'abi.json'), encode(Value(fixture('synthetic')), true)) or { panic(err) }
	os.write_file_array(os.join_path(path, 'command.bin'), command) or { panic(err) }
	os.write_file_array(os.join_path(path, 'descriptor.bin'), descriptor) or { panic(err) }
	assert cli('plan', ['--abi', os.join_path(path, 'abi.json'), '--command',
		os.join_path(path, 'command.bin'), '--descriptor', os.join_path(path, 'descriptor.bin'),
		'--command-gpu-address', '0x700000000', '--output', os.join_path(path, 'plan.json')], os.join_path(os.dir(@FILE), '..')) == 0
	plan := decode(os.read_file(os.join_path(path, 'plan.json')) or { panic(err) }) or { panic(err) }
	assert text(plan, 'schema') == 'vinix.fake-g17-plan.v1'
	assert val(obj(plan, 'coverage'), 'total_writes').int() == 20
}

fn test_encoder_cli_writes_exact_buffers_and_json() {
	path := os.join_path(os.temp_dir(), 'vinix-g17-encoder-${os.getpid()}')
	os.mkdir(path) or { panic(err) }
	defer { os.rmdir_all(path) or { panic(err) } }
	_, descriptor := encoded_fixture()
	abi := fixture('synthetic')
	externals := decode('{"decisions":{"0x80":"taken"},"values":{"0x400":"0x123456789abcdef0"}}') or { panic(err) }
	os.write_file(os.join_path(path, 'abi.json'), encode(Value(abi), true)) or { panic(err) }
	os.write_file_array(os.join_path(path, 'descriptor.bin'), descriptor) or { panic(err) }
	os.write_file(os.join_path(path, 'externals.json'), encode(Value(externals), true)) or { panic(err) }
	assert cli('encode', ['--abi', os.join_path(path, 'abi.json'), '--descriptor',
		os.join_path(path, 'descriptor.bin'), '--command-gpu-address', '0x700000000', '--zero-template',
		'--externals', os.join_path(path, 'externals.json'), '--command-output',
		os.join_path(path, 'command.bin'), '--descriptor-output',
		os.join_path(path, 'out-descriptor.bin'), '--plan-output', os.join_path(path, 'plan.json')], os.join_path(os.dir(@FILE), '..')) == 0
	expected := encode_3d(abi, descriptor, 0x700000000, none, Value(externals)) or { panic(err) }
	assert os.read_bytes(os.join_path(path, 'command.bin')) or { panic(err) } == expected.command
	assert os.read_bytes(os.join_path(path, 'out-descriptor.bin')) or { panic(err) } == expected.descriptor
	assert os.read_file(os.join_path(path, 'plan.json')) or { panic(err) } == encode(Value(expected.plan), true) + '\n'
}

fn test_cli_parser_preserves_argparse_controls() {
	allowed := ['--abi', '--header-output', '--output', '--command-gpu-address']
	flags := ['--check']
	for args in [['--unknown', '--help'], ['--unknown', '-hhh'], ['--hel'], ['--abi=x', '--help']] {
		assert '--help' in parse_options(args, allowed, flags, ['--abi']) or { panic(err) }
	}
	assert (parse_options(['--abi=', '--abi', 'final', '--che'], allowed, flags, []string{}) or { panic(err) })['--abi'] == 'final'
	assert (parse_options(['--abi', ''], allowed, flags, []string{}) or { panic(err) })['--abi'] == '.'
	for args in [['--he'], ['-hgarbage'], ['-h=foo'], ['--check=1'], ['--help=1'], ['--abi', '--help'],
		['--', '--help'], ['--'], ['--command-gpu-address=no', '--help']] {
		if _ := parse_options(args, allowed, flags, []string{}) {
			assert false
		} else {
			assert err.code() == 102
		}
	}
	for value in ['-1', '-.1', '-', 'path'] {
		assert !option_token(value)
	}
	for value in ['-0x1', '-1e3', '--help', '-h'] {
		assert option_token(value)
	}
}

fn test_empty_accelerator_records_fail_closed() {
	mut abi := fixture('synthetic')
	mut channels := copy_object(obj(abi, 'channels'))
	channels['accelerator_inputs'] = empty_object_value()
	abi['channels'] = channels
	if _ := fold_accelerator_inputs(abi, map[string]u64{}) {
		assert false
	} else {
		assert err.msg() == "'feature_flags'"
	}
	abi = fixture('folding')
	channels = copy_object(obj(abi, 'channels'))
	mut inputs := copy_object(obj(channels, 'accelerator_inputs'))
	inputs['perf_counter_sampler'] = empty_object_value()
	channels['accelerator_inputs'] = inputs
	abi['channels'] = channels
	if _ := fold_accelerator_inputs(abi, map[string]u64{}) {
		assert false
	} else {
		assert err.msg() == "'vinix_policy'"
	}
}

fn shifted_fixture(bias int) map[string]Value {
	mut abi := fixture('synthetic')
	mut channels := copy_object(obj(abi, 'channels'))
	mut selectors := copy_object(obj(channels, 'register_selectors'))
	mut producers := copy_object(obj(selectors, 'producers'))
	mut producer := copy_object(obj(producers, '3D'))
	mut entries := []Value{}
	for raw in val(producer, 'encoder_entries').arr() {
		mut entry := copy_object(raw.as_map())
		entry['producer_offset'] = Value(val(entry, 'producer_offset').int() + bias)
		entries << entry
	}
	producer['encoder_entries'] = entries
	producers['3D'] = producer
	selectors['producers'] = producers
	channels['register_selectors'] = selectors
	mut inline := copy_object(obj(channels, 'inline_register_records'))
	mut records := copy_object(obj(inline, 'static_records'))
	mut static_entries := []Value{}
	for raw in val(records, '3D').arr() {
		mut entry := copy_object(raw.as_map())
		entry['producer_offset'] = Value(val(entry, 'producer_offset').int() + bias)
		static_entries << entry
	}
	records['3D'] = static_entries
	inline['static_records'] = records
	channels['inline_register_records'] = inline
	mut cfg := copy_object(obj(channels, 'register_emission_cfg'))
	mut graphs := copy_object(obj(cfg, 'producers'))
	mut g := copy_object(obj(graphs, '3D'))
	mut nodes := []Value{}
	for raw in val(g, 'nodes').arr() {
		mut entry := copy_object(raw.as_map())
		entry['producer_offset'] = Value(val(entry, 'producer_offset').int() + bias)
		next := offsets(val(entry, 'next')) or { panic(err) }
		entry['next'] = Value(number_array(next.map(it + bias)))
		nodes << entry
	}
	g['nodes'] = nodes
	mut decisions := []Value{}
	for raw in val(g, 'decisions').arr() {
		mut decision := copy_object(raw.as_map())
		decision['producer_offset'] = Value(val(decision, 'producer_offset').int() + bias)
		for name in ['taken', 'fallthrough'] {
			mut outcome := copy_object(obj(decision, name))
			next := offsets(val(outcome, 'next')) or { panic(err) }
			outcome['next'] = Value(number_array(next.map(it + bias)))
			decision[name] = outcome
		}
		decisions << decision
	}
	g['decisions'] = decisions
	entry := offsets(val(g, 'entry')) or { panic(err) }
	g['entry'] = Value(number_array(entry.map(it + bias)))
	graphs['3D'] = g
	cfg['producers'] = graphs
	channels['register_emission_cfg'] = cfg
	abi['channels'] = channels
	return abi
}

fn test_graph_and_external_offsets_above_four_gib() {
	command, descriptor := encoded_fixture()
	source, header := templates()
	for bias in [int(u64(1) << 31), int(u64(1) << 32), int(u64(1) << 40)] {
		abi := shifted_fixture(bias)
		plan := compile_plan(abi, command, descriptor, 0x700000000) or { panic(err) }
		assert val(val(plan, 'writes').arr()[0].as_map(), 'producer_offset').int() == bias + 0x50
		roundtrip := decode(encode(Value(plan), false)) or { panic(err) }
		assert val(val(roundtrip, 'writes').arr()[0].as_map(), 'producer_offset').u64() == u64(bias + 0x50)
		result := encode_3d(abi, descriptor, 0x700000000, none, Value(map[string]Value{
			'decisions': Value(map[string]Value{
				(bias + 0x80).str(): Value(true)
			})
			'values':    Value(map[string]Value{
				(bias + 0x400).str(): Value(0)
			})
		})) or { panic(err) }
		assert val(obj(result.plan, 'encoder'), 'external_event_offsets').arr()[0].int() == bias + 0x400
		generated := generate(abi, source, header) or { panic(err) }
		assert generated.external_events == [bias + 0x400]
		assert generated.external_decisions == [bias + 0x80]
		assert generated.max_writes == 20
	}
	for member in [i64(0x7fffffffffffffff), i64(-9223372036854775807) - 1] {
		if _ := load([]u8{len: 8}, int(member), 8, false) {
			assert false
		} else {
			assert err.msg().contains('outside a 0x8-byte buffer')
		}
	}
}

fn empty_object_value() Value {
	record := map[string]Value{}
	return Value(record)
}

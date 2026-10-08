module t6050power

import os
import traceanalysis as j

@[heap]
struct Trace {
mut:
	calls []string
}

struct MockController {
	role      string
	values    map[string]j.Value
	functions map[string]Function
	trace     &Trace
}

fn (source MockController) called(key string) ! {
	mut trace := source.trace
	trace.calls << source.role + ':' + key
	if failure := j.value(source.values, 'errors').as_map()[key] {
		return error(j.string_value(failure))
	}
}

fn (source MockController) identity() !j.Value {
	source.called('identity')!
	return j.value(source.values, 'uuid')
}

fn (source MockController) symbols() !map[string]j.Value {
	source.called('symbols')!
	return j.value(source.values, 'symbols').as_map()
}

fn (source MockController) code(name string) !Function {
	source.called('code:' + name)!
	return source.functions[name] or { return error('missing fixture code ' + name) }
}

fn (source MockController) vtable(name string, slot int) !j.Value {
	key := name + ':' + slot.str()
	source.called('vtable:' + key)!
	return j.value(source.values, 'vtables').as_map()[key] or { return error('missing fixture vtable ' + key) }
}

fn (source MockController) read_cstring(body Function, adrp_offset int, add_offset int) !string {
	key := j.string_value(body.address) + ':' + adrp_offset.str() + ':' + add_offset.str()
	source.called('string:' + key)!
	value := j.value(source.values, 'strings').as_map()[key] or { return error('missing fixture string ' + key) }
	return j.string_value(value)
}

fn (source MockController) read_table(address u64, count int) ![]u32 {
	key := address.str() + ':' + count.str()
	source.called('table:' + key)!
	value := j.value(source.values, 'tables').as_map()[key] or { return error('missing fixture table ' + key) }
	return value.arr().map(u32(it.u64()))
}

fn (source MockController) read_table64(address u64, count int) ![]u64 {
	key := address.str() + ':' + count.str()
	source.called('table64:' + key)!
	value := j.value(source.values, 'tables64').as_map()[key] or { return error('missing fixture table64 ' + key) }
	return value.arr().map(it.u64())
}

fn mock_controller(row map[string]j.Value, role string, trace &Trace) !MockController {
	values := j.value(row, role).as_map()
	mut functions := map[string]Function{}
	for name, value in j.value(values, 'functions').as_map() {
		tuple := value.arr()
		functions[name] = Function{tuple[0], j.bytes_fromhex(j.string_value(j.value(tuple[1].as_map(), '$bytes')))!}
	}
	return MockController{role, values, functions, trace}
}

fn controller_fixture_rows() ![]j.Value {
	return j.decode(os.read_file(os.join_path(os.dir(@FILE), 'testdata/controllers.json'))!)!.arr()
}

fn check_controller_fixture(index int) ! {
	rows := controller_fixture_rows()!
	row := rows[index].as_map()
	trace := &Trace{}
	expected := j.value(row, 'expected').as_map()
	result := query_controller_evidence(mock_controller(row, 'primary', trace)!, mock_controller(row, 'secondary', trace)!, j.string_value(j.value(row, 'operation')), j.value(row, 'request').as_map())!
	assert j.encode(result, false) == j.encode(j.value(expected, 'result'), false)
	assert j.encode(j.Value(trace.calls.map(j.Value(it))), false) == j.encode(j.value(expected, 'trace'), false)
}

fn test_original_recover_apple_pmgr_complete_evidence_and_call_order() {
	check_controller_fixture(0)!
}

fn test_original_recover_apple_t6050_pmgr_complete_evidence_and_call_order() {
	check_controller_fixture(1)!
}

fn test_original_recover_apple_pmp_complete_evidence_and_call_order() {
	check_controller_fixture(2)!
}

fn test_original_recover_apple_pmp_firmware_complete_evidence_and_call_order() {
	check_controller_fixture(3)!
}

fn test_original_recover_apple_a7iop_complete_evidence_and_call_order() {
	check_controller_fixture(4)!
}

fn test_original_recover_iodart_family_complete_evidence_and_call_order() {
	check_controller_fixture(5)!
}

fn test_original_recover_apple_t8110_dart_complete_evidence_and_call_order() {
	check_controller_fixture(6)!
}

fn test_original_recover_t8110_kernel_complete_evidence_and_call_order() {
	check_controller_fixture(7)!
}

fn test_original_recover_apple_ascwrap_v6_complete_evidence_and_call_order() {
	check_controller_fixture(8)!
}

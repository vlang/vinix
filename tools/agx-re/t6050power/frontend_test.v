module t6050power

import appleadt as a
import os
import traceanalysis as j

fn frontend_fixture() !map[string]j.Value {
	return j.decode(os.read_file(os.join_path(os.dir(@FILE), 'testdata/frontend.json'))!)!.as_map()
}

fn frontend_bytes(row map[string]j.Value, name string) ![]u8 {
	return j.bytes_fromhex(j.string_value(j.value(row, name)))!
}

fn test_original_device_tree_payload_with_trailing_metadata() {
	row := frontend_fixture()!
	data := frontend_bytes(row, 'payload_image')!
	span := a.query(data, 'device_tree_im4p_payload', map[string]j.Value{})!.as_map()
	assert data[j.value(span, 'start').int()..j.value(span, 'end').int()] == frontend_bytes(row, 'payload')!
}

fn test_original_adt_property_and_exact_consumption() {
	row := frontend_fixture()!
	data := frontend_bytes(row, 'adt')!
	root := a.parse(data)!
	assert root.property('flagged')! == 'abc'.bytes()
	mut trailing := data.clone()
	trailing << u8(`x`)
	a.parse(trailing) or {
		assert err.msg() == '1 trailing bytes after DeviceTree root'
		return
	}
	assert false
}

fn test_original_pmgr_interrupt_config_full_result_and_rejections() {
	row := frontend_fixture()!
	actual := a.parse_pmgr_interrupt_config(frontend_bytes(row, 'interrupt_config')!, 'test')!
	assert j.encode(j.Value(actual.map(j.Value(it))), false) == j.encode(j.value(row, 'expected_interrupt'), false)
	for bad in j.value(row, 'bad_interrupt').arr() {
		values := bad.as_map()
		a.parse_pmgr_interrupt_config(frontend_bytes(values, 'input')!, 'test') or {
			assert err.msg() == j.string_value(j.value(values, 'error'))
			continue
		}
		assert false
	}
}

fn test_public_constants_use_native_contract_values_and_independent_tuple_shape() {
	values := public_constants()
	assert values.len == 199
	assert j.value(values, 'APPLE_PMGR_UUID') == j.Value(apple_pmgr_uuid)
	assert j.value(values, 'PMP_CHOSEN_PATH') == j.Value('IODeviceTree:/chosen')
	assert j.value(values, 'MAX_DEVICE_TREE_BYTES').u64() == u64(64 << 20)
	mandatory := j.value(values, 'PMP_MANDATORY_PATCHBAY_INPUTS').arr()
	assert mandatory.len == 9
	assert mandatory[0].arr() == [j.Value('BDID'), j.Value('board-id'),
		j.Value('IODeviceTree:/chosen'), j.Value('value'), j.Value(0xc8), j.Value(true)]
	assert mandatory[8].arr() == [j.Value('CVAR'), j.Value('soc-chip-variant'),
		j.Value('the RTBuddy provider nub'), j.Value('value'), j.Value(0xe8), j.Value(false)]
}

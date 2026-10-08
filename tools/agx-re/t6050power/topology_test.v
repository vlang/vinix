module t6050power

import os
import appleadt as a
import traceanalysis as j

fn original_topology_cases() ![]j.Value {
	return j.decode(os.read_file(os.join_path(os.dir(@FILE), 'testdata/topology.json'))!)!.arr()
}

fn check_topology_fixture(index int) ! {
	fixtures := original_topology_cases()!
	record := fixtures[index].as_map()
	expected := j.value(record, 'expected').as_map()
	result := query_topology(j.string_value(j.value(record, 'operation')), j.value(record, 'request').as_map()) or {
		assert err.msg() == j.string_value(j.value(expected, 'error'))
		assert j.value(expected, 'kind') == j.Value('ValueError')
		return
	}
	assert 'result' in expected
	assert j.encode(result, false) == j.encode(j.value(expected, 'result'), false)
}

fn test_original_full_t6050_power_topology_and_schema() { check_topology_fixture(0)! }

fn test_original_sgx_gate_order_rejection() { check_topology_fixture(1)! }

fn test_original_agx_packet_layout_rejection() { check_topology_fixture(2)! }

fn test_topology_tuple_numeric_widths_remain_exact() {
	assert tuple_equal([j.Value(u64(0xffffffffffffffff)), j.Value(true)], [
		u64(0xffffffffffffffff),
		1,
	])
	assert !tuple_equal([j.Value(j.Number{'18446744073709551616'}), j.Value(true)], [
		u64(0),
		1,
	])
}

fn root_with_first_dart_properties(root a.Node, properties map[string]a.Property) a.Node {
	arm := root.children[0]
	mut children := arm.children.clone()
	children[2] = a.Node{properties, children[2].children}
	return a.Node{root.properties, [a.Node{arm.properties, children}]}
}

fn test_wide_sid_counts_select_only_canonical_published_keys() {
	records := original_topology_cases()!
	root := node_from_request(j.value(j.value(records[0].as_map(), 'request').as_map(), 'root'))!
	for count in [u64(0x100000000), u64(0x8000000000000000), ~u64(0)] {
		mut properties := root.children[0].children[2].properties.clone()
		properties['sid-count'] = a.Property{encoded_words([u32(count), u32(count >> 32)]), 0}
		for name in ['bypass-02', 'bypass-+2', 'bypass--2', 'bypass- 2', 'bypass-٢',
			'bypass-18446744073709551616'] {
			properties[name] = a.Property{[u8(1)], 0}
		}
		// The u64 maximum equals this count and therefore is outside range.
		properties['bypass-${count}'] = a.Property{[u8(1)], 0}
		altered := root_with_first_dart_properties(root, properties)
		recover_power_topology(altered) or {
			assert err.msg() == 'T6050 dart-pmp0 contract changed: regs=[(2216296448, 49152), (2216361984, 16384)], sids=[0, 1, 2, 5, 6, 7, 8, 9], bypassed=[2, 5, 6, 7, 8, 9], translated=[0, 1], page=0x4000, count=${count}, options=0x65, flush=0, vm=0x10000000000+0x1000000000'
			continue
		}
		assert false
	}
}

fn test_wide_published_sid_preserves_empty_and_nonempty_rules() {
	records := original_topology_cases()!
	root := node_from_request(j.value(j.value(records[0].as_map(), 'request').as_map(), 'root'))!
	for nonempty in [false, true] {
		count := ~u64(0)
		mut properties := root.children[0].children[2].properties.clone()
		properties['sid-count'] = a.Property{encoded_words([u32(count), u32(count >> 32)]), 0}
		properties['bypass-18446744073709551614'] = a.Property{if nonempty {
			[u8(1)]
		} else {
			[]u8{}
		}, 0}
		altered := root_with_first_dart_properties(root, properties)
		recover_power_topology(altered) or {
			expected := if nonempty {
				'T6050 dart-pmp0 bypass-18446744073709551614 is no longer an empty boolean'
			} else {
				'T6050 dart-pmp0 contract changed: regs=[(2216296448, 49152), (2216361984, 16384)], sids=[0, 1, 2, 5, 6, 7, 8, 9], bypassed=[2, 5, 6, 7, 8, 9, 18446744073709551614], translated=[0, 1], page=0x4000, count=18446744073709551615, options=0x65, flush=0, vm=0x10000000000+0x1000000000'
			}
			assert err.msg() == expected
			continue
		}
		assert false
	}
}

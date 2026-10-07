module g17power

import math.big
import os
import traceanalysis as j

fn fixture() ([]int, [][]f64, [][]f64, string) {
	document := j.object(j.decode(os.read_file(os.join_path(os.dir(@FILE), 'fixtures/leakage.json')) or { panic(err) }) or { panic(err) }) or { panic(err) }
	return j.value(document, 'voltages').arr().map(it.int()), records(j.value(document, 'vdd')) or { panic(err) }, records(j.value(document, 'afr')) or { panic(err) }, j.string_value(j.value(document, 'driver_uuid'))
}

fn fuse_samples(table [][]f64) []int {
	mut samples := [0, 1]
	mut maximum := 1
	for record in table {
		threshold := threshold_quarters(record) or { panic(err) }
		if threshold != big.integer_from_u64(0xffffffff) {
			for value in [int(small(threshold)) - 1, int(small(threshold)), int(small(threshold)) + 1] {
				if value !in samples { samples << value }
				if value > maximum { maximum = value }
			}
		}
	}
	for value := 0; value < maximum + 4096; value += 137 {
		if value !in samples { samples << value }
	}
	samples.sort()
	return samples
}

fn test_binary32_operations_match_native_rounding() {
	values := [0.125, 0.605, 0.75, 1.065, 12.29, 20.15, 24800.0, 48500.0]
	for value in values {
		bits := f32_bits(value) or { panic(err) }
		assert q40_to_f32_bits(f32_bits_to_q40(bits) or { panic(err) }) or { panic(err) } == bits
	}
	for left in values[..6] {
		for right in values[..6] {
			assert f32_mul_bits(f32_bits(left) or { panic(err) }, f32_bits(right) or { panic(err) }) or { panic(err) } == f32_bits(binary32(left) or { panic(err) } * binary32(right) or { panic(err) }) or { panic(err) }
		}
	}
}

fn test_q40_ties_carry_and_unbounded_intermediates() {
	unit := 1.0 / f64(u64(1) << q_bits)
	for number, expected in {
		0.5: 0
		1.5: 2
		2.5: 2
		3.5: 4
	} {
		assert q40(number * unit) or { panic(err) } == big.integer_from_int(expected)
	}
	assert q40_mul(big.integer_from_int(-1), big.one_int) == big.integer_from_int(-1)
	assert q40_mul(big.one_int.left_shift(100), big.one_int.left_shift(100)) == big.one_int.left_shift(160)
	for value in [big.one_int.left_shift(24) - big.one_int, big.one_int.left_shift(24) + big.one_int,
		big.one_int.left_shift(100), big.one_int.left_shift(167)] {
		bits := q40_to_f32_bits(value) or { panic(err) }
		assert bits & 0x7f800000 != 0
	}
	for bits in [u32(1), 0x80000000, 0x7f800000, 0x7fc00000] {
		if _ := f32_bits_to_q40(bits) {
			assert false
		}
	}
}

fn test_fixed_afr_path_matches_producer_rounding() {
	voltages, _, afr, _ := fixture()
	for millivolts in voltages {
		for quarters in fuse_samples(afr) {
			for megahertz in [u32(0), 300, 1250] {
				actual := fixed_afr_power(afr, quarters, millivolts, megahertz) or { panic(err) }
				expected := reference_afr_power(afr, quarters, millivolts, megahertz) or { panic(err) }
				assert actual == big.integer_from_int(expected)
			}
		}
	}
}

fn test_fixed_main_path_matches_producer_rounding() {
	voltages, vdd, _, _ := fixture()
	for millivolts in voltages {
		for quarters in fuse_samples(vdd) {
			for enabled in [u32(0), 1, 9, 10] {
				actual := fixed_main_power(vdd, quarters, millivolts, 1250, enabled, 1234) or { panic(err) }
				expected := reference_main_power(vdd, quarters, millivolts, 1250, enabled, 1234) or { panic(err) }
				assert actual == big.integer_from_int(expected)
			}
		}
	}
}

fn test_generated_kernel_table_preserves_original_bytes() {
	voltages, vdd, afr, uuid := fixture()
	source := generated_source(uuid, voltages.map(big.integer_from_int(it)), vdd, afr) or { panic(err) }
	assert source == os.read_file(os.join_path(os.dir(@FILE), '../../../kernel/gpu/agx/fw/g17_power_tables.v')) or { panic(err) }
}

fn test_native_device_tree_voltage_collection() {
	source := '{"device_tree":{"perf_states":[[{"voltage_mv":750},{"voltage_mv":"800"}]],"cs_perf_states":{"tables":[[{"voltage_uv":749999},{"voltage_uv":800000}]]},"afr_perf_states":{"tables":[[{"voltage_uv":900000}]]}}}'
	assert device_voltages_text(source) or { panic(err) } == [749, 750, 800, 900].map(big.integer_from_int(it))
	for text in [source.replace('750', '0'), source.replace('750', '-1')] {
		if _ := device_voltages_text(text) {
			assert false
		}
	}
}

fn test_binary32_overflow_and_unbounded_thresholds() {
	assert f32_bits(3.4028234663852886e38) or { panic(err) } == 0x7f7fffff
	for value in [3.4028236e38, -3.4028236e38, 1e300, -1e300] {
		if _ := binary32(value) {
			assert false
		} else {
			assert err.msg() == 'float too large to pack with f format'
		}
	}
	assert threshold_quarters([18446744073709551616.0]) or { panic(err) } == big.one_int.left_shift(66)
	for parameter in [1, 6, 7] {
		mut record := [1.0].repeat(11)
		record[parameter] = 0
		if _ := leakage_factor(record, 750) {
			assert false
		} else {
			assert err.msg() == 'float division by zero'
		}
	}
}

fn test_device_voltages_preserve_wide_metadata_and_nonfinite_errors() {
	base := '{"device_tree":{"perf_states":[[{"voltage_mv":TOKEN}]],"cs_perf_states":{"tables":[]},"afr_perf_states":{"tables":[]}}}'
	for token in ['18446744073709551616', '"18446744073709551616"', '1.8446744073709551616e19'] {
		assert device_voltages_text(base.replace('TOKEN', token)) or { panic(err) } == [big.one_int.left_shift(64)]
	}
	for token in ['"7_50"', '"٧٥٠"', '"７５０"', '"  +000750  "'] {
		assert device_voltages_text(base.replace('TOKEN', token)) or { panic(err) } == [big.integer_from_int(750)]
	}
	for token in ['NaN', 'Infinity', '-Infinity', '1e999'] {
		if _ := device_voltages_text(base.replace('TOKEN', token)) {
			assert false
		} else {
			assert err.msg() == if token == 'NaN' {
				'cannot convert float NaN to integer'
			} else {
				'cannot convert float infinity to integer'
			}
		}
	}
	// Non-finite constants outside voltage fields are valid ignored metadata.
	assert device_voltages_text(base.replace('TOKEN', '750').replace('"device_tree"', '"unused": NaN, "device_tree"')) or { panic(err) } == [big.integer_from_int(750)]
}

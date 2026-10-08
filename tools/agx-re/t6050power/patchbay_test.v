module t6050power

import os
import traceanalysis as j

fn original_patchbay_cases() ![]j.Value {
	return j.decode(os.read_file(os.join_path(os.dir(@FILE), 'testdata/patchbay.json'))!)!.arr()
}

fn check_patchbay_fixture(index int) ! {
	rows := original_patchbay_cases()!
	row := rows[index].as_map()
	expected := j.value(row, 'expected').as_map()
	image := j.bytes_fromhex(j.string_value(j.value(row, 'image')))!
	result := query_patchbay(image, j.string_value(j.value(row, 'operation')), j.value(row, 'request').as_map()) or {
		assert j.value(expected, 'kind') == j.Value('ValueError')
		assert err.msg() == j.string_value(j.value(expected, 'error'))
		return
	}
	assert 'result' in expected
	assert j.encode(result, false) == j.encode(j.value(expected, 'result'), false)
}

fn test_original_patchbay_version_alignment_and_segment_protection() {
	for index in 0 .. 16 { check_patchbay_fixture(index)! }
}

fn test_original_patchbay_mandatory_width_and_region_overrun_rejections() {
	for index in 16 .. 20 { check_patchbay_fixture(index)! }
}

fn test_original_patchbay_rejects_ambiguous_identity() { check_patchbay_fixture(20)! }

fn test_original_patchbay_duplicate_and_trailing_record_rejections() {
	check_patchbay_fixture(21)!
	check_patchbay_fixture(22)!
}

fn test_patchbay_unknown_tags_replace_each_non_ascii_byte_independently() {
	check_patchbay_fixture(23)!
	check_patchbay_fixture(24)!
}

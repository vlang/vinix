module g17expr

import os
import traceanalysis as j

fn test_public_manifest_preserves_all_original_scalar_and_container_tags() {
	original := j.decode(os.read_file(os.join_path(os.dir(@FILE), 'fixtures/public-constants.json')) or { panic(err) }) or { panic(err) }
	result := query([]u8{}, 'public_constants', map[string]j.Value{}) or { panic(err) }
	assert result == original
	assert result.as_map().len == 264
	for name in ['DRIVER_UUID', 'FIRMWARE_UUID', 'RTBUDDY_UUID', 'INIT_FIRMWARE_DATA',
		'G17_ADD_REGISTER_OVERRIDE', 'POPULATE_DPE_PPT_CONFIG'] {
		assert result.as_map()[name].arr()[0] == j.Value('scalar')
		assert result.as_map()[name].arr()[1] == controller_value(name)
	}
}

fn test_public_manifest_queries_own_separate_maps() {
	mut first := public_constant_manifest().as_map().clone()
	first['DRIVER_UUID'] = j.Value('changed')
	second := public_constant_manifest()
	assert second.as_map()['DRIVER_UUID'].arr()[1] == controller_value('DRIVER_UUID')
	assert second.as_map()['SUBMIT_DATA_MASTER_CHANNELS'].arr()[0] == j.Value('dict')
	assert second.as_map()['ROOT_FIELDS'].arr()[0] == j.Value('tuple')
}

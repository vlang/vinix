module partition

fn test_gpt_last_sector_is_inclusive_and_invalid_ranges_are_rejected() {
	assert gpt_sector_count(2048, 133119, 135168)? == 131072
	assert gpt_sector_count(17, 17, 18)? == 1
	assert gpt_sector_count(0, 0, 1)? == 1
	if _ := gpt_sector_count(18, 17, 20) {
		assert false
	}
	if _ := gpt_sector_count(0, 20, 20) {
		assert false
	}
	if _ := gpt_sector_count(0, u64(-1), u64(-1)) {
		assert false
	}
	if _ := gpt_sector_count(0, 0, 0) {
		assert false
	}
}

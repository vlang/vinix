module memory

fn test_pressure_hysteresis_and_watermark_scaling() {
	marks := pressure_watermarks(1024 * 1024 * 1024)
	assert marks.critical == 8 * 1024 * 1024
	assert marks.low == 32 * 1024 * 1024
	assert marks.high == 48 * 1024 * 1024
	assert pressure_next_level(0, marks.low, marks) == 1
	assert pressure_next_level(1, marks.low + 1, marks) == 1
	assert pressure_next_level(1, marks.high, marks) == 0
	assert pressure_next_level(0, marks.critical, marks) == 2
	assert pressure_next_level(2, marks.critical * 2 - 1, marks) == 2
	assert pressure_next_level(2, marks.critical * 2, marks) == 1
	assert pressure_next_level(2, marks.high, marks) == 0
	assert pressure_watermarks(64 * 1024 * 1024).low == 8 * 1024 * 1024
	assert pressure_watermarks(u64(64) * 1024 * 1024 * 1024).low == 128 * 1024 * 1024
}

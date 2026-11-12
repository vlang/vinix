module packet

fn decode(bytes []u8, size int, explorer bool) []Report {
	mut decoder := Decoder{}
	mut reports := []Report{}
	for byte in bytes {
		if report := decoder.push(byte, size, explorer) { reports << report }
	}
	return reports
}

fn test_resynchronises_at_the_next_header() {
	reports := decode([u8(0), 0, 0x18, 56, 200, 0x28, 200, 56], 3, false)
	assert reports.len == 2
	assert reports[0].x == -200 && reports[0].y == 200
	assert reports[1].x == 200 && reports[1].y == -200
}

fn test_overflow_consumes_the_packet_and_preserves_the_next_one() {
	reports := decode([u8(0xc8), 8, 8, 0x09, 8, 8], 3, false)
	assert reports.len == 1
	assert reports[0].x == 8 && reports[0].y == 8
	assert reports[0].buttons == 1
}

fn test_explorer_wheel_and_side_buttons() {
	reports := decode([u8(8), 0, 0, 0x1f, 8, 0, 0, 0x21], 4, true)
	assert reports.len == 2
	assert reports[0].scroll == 1 && reports[0].buttons == 8
	assert reports[1].scroll == -1 && reports[1].buttons == 16
}

fn test_intellimouse_uses_the_whole_signed_wheel_byte() {
	reports := decode([u8(8), 0, 0, 0xff, 8, 0, 0, 0x10], 4, false)
	assert reports.len == 2
	assert reports[0].scroll == 1 && reports[1].scroll == -16
}

fn test_partial_packet_does_not_publish() {
	assert decode([u8(8), 1, 2], 4, true).len == 0
}

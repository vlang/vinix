module wsloader

fn test_shared_segment_pages_gaps_and_invalid_extents() {
	base := usize(0x100000)
	reserved := usize(0x114000)
	first := segment_extent(base, reserved, base, 0x100000, 0)
	second := segment_extent(base, reserved, base + 0xfc000, 0x18000, first)
	assert first == 0x100000
	assert second == reserved
	assert segment_extent(base, reserved, base + 0x4000, 0x4000, second) == reserved
	assert segment_extent(base, reserved, base + 0x110000, 0x4000, 0x100000) == reserved
	assert segment_extent(base, reserved, base + reserved, 0, 0) == reserved
	assert segment_extent(base, reserved, base - 1, 1, 0) == ~usize(0)
	assert segment_extent(base, reserved, base + reserved, 1, 0) == ~usize(0)
	assert segment_extent(base, reserved, base, ~usize(0), 0) == ~usize(0)
	assert segment_extent(base, reserved, ~usize(0), 0, 0) == ~usize(0)
}

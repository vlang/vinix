module pages

fn test_reserved_ranges_alignment_exhaustion_and_free() {
	mut pool := Pool{}
	assert pool.add(0, 4096) && pool.count == 0
	assert pool.take(1, 1) == 0
	assert pool.add(0x100001, 0x20fff)
	assert pool.count == 32
	assert pool.add(0x100001, 0x20fff) && pool.count == 32
	assert !pool.add(0xfffff000, 0x2000)
	assert pool.take(16, 16) == 0x110000
	assert pool.count == 16
	assert !pool.add(0x110000, 4096)
	assert !pool.give(0x100000, 1)
	assert !pool.give(0x110001, 1)
	assert pool.give(0x110000, 16)
	assert !pool.give(0x110000, 16)
	mut frames := []u32{}
	for _ in 0 .. 32 {
		frame := pool.take(1, 1)
		assert frame >= 0x101000 && frame <= 0x120000 && frame !in frames
		frames << frame
	}
	assert pool.count == 0 && pool.take(1, 1) == 0
	for frame in frames {
		assert pool.give(frame, 1)
	}
	assert pool.count == 32
}

fn test_last_frame_and_atomic_free_rejection() {
	mut pool := Pool{}
	assert pool.add(0xfffff000, 4096)
	assert pool.take(1, 1) == 0xfffff000
	assert !pool.give(0xffffe000, 2)
	assert pool.count == 0
	assert pool.give(0xfffff000, 1)
	assert pool.take(1, 3) == 0
	assert pool.take(0xffffffff, 1) == 0
}

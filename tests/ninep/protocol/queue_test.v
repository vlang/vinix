module virtio_9p

fn test_actual_queue_policy_and_completions() {
	for n in [u32(0), 1, 3, 1025, 2048, 0xffffffff] {
		assert queue_size(n) == 0
	}
	for n in [u32(2), 4, 128, 1024] {
		assert queue_size(n) == n
		assert used_offset(u16(n)) % 4096 == 0
		assert ring_bytes(u16(n)) >= u64(n) * 26 + 12
	}
	assert valid_completion(0xffff, 0, 0, 7, 65536)
	assert !valid_completion(0, 2, 0, 7, 65536)
	assert !valid_completion(0, 1, 1, 7, 65536)
	assert !valid_completion(0, 1, 0, 6, 65536)
	assert !valid_completion(0, 1, 0, 65537, 65536)
	assert !valid_completion(0, 1, 0, 9, 8)
	assert valid_ring(4096, 16384, 4096)
	assert valid_ring(16384, 16384, 16384)
	assert !valid_ring(u64(1) << 44, 4096, 4096)
	assert !valid_ring((u64(1) << 44) - 4096, 8192, 4096)
	assert !valid_ring(4097, 4096, 4096)
}

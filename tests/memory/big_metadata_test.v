module memory

fn test_valid_geometry_and_address_binding() {
	for size in [u64(2049), page_size - 1, page_size, page_size + 1, page_size * 5] {
		mut metadata := MallocMetadata{}
		pages := (size + page_size - 1) / page_size
		update_big_metadata(mut metadata, pages, size)
		assert big_metadata_valid(unsafe { &metadata })
		copy := metadata
		assert !big_metadata_valid(unsafe { &copy })
		update_big_metadata(mut metadata, pages, size - 1)
		assert big_metadata_valid(unsafe { &metadata }) == ((size - 1 + page_size - 1) / page_size == pages)
	}
}

fn test_every_metadata_word_detects_corruption() {
	mut metadata := MallocMetadata{}
	for word in 0 .. 6 {
		update_big_metadata(mut metadata, 3, 2 * page_size + 1)
		unsafe { (&u64(&metadata))[word] ^= 1 }
		assert !big_metadata_valid(unsafe { &metadata })
	}
	update_big_metadata(mut metadata, 3, 2 * page_size + 1)
	invalidate_big_metadata(mut metadata)
	assert !big_metadata_valid(unsafe { &metadata })
}

fn test_consistent_but_invalid_sizes_cannot_overflow() {
	mut metadata := MallocMetadata{}
	for size in [u64(0), u64(-1), u64(-1) - page_size + 1, big_allocation_max_size() + 1] {
		update_big_metadata(mut metadata, 1, size)
		assert !big_metadata_valid(unsafe { &metadata })
	}
	update_big_metadata(mut metadata, 0, 1)
	assert !big_metadata_valid(unsafe { &metadata })
	update_big_metadata(mut metadata, 2, page_size)
	assert !big_metadata_valid(unsafe { &metadata })
	update_big_metadata(mut metadata, big_allocation_max_size() / page_size, big_allocation_max_size())
	assert big_metadata_valid(unsafe { &metadata })
}

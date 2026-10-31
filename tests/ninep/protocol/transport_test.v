module virtio_9p

fn test_actual_transport_completion_timeout_and_quarantine() {
	fixture_mode = 0
	mut ch := connect('share') or { panic('connect') }
	assert ch.size == 128
	assert exchange(voidptr(ch), ch.tx, 7, ch.rx, 65536) == 7
	// Descriptor publication and writable length are the real production code.
	assert unsafe { *&u16(ch.ring.virt + 12) } == 1
	assert unsafe { *&u16(ch.ring.virt + 28) } == 2
	assert unsafe { *&u32(ch.ring.virt + 24) } == 65536
	assert unsafe { *&u16(ch.avail) } == 1
	ch.close()
	assert fixture_frees == 2 && !ninep_claimed
	for mode in [1, 3, 4] {
		fixture_mode = 0
		ch = connect('share') or { panic('reconnect') }
		fixture_mode = mode
		before := fixture_frees
		assert exchange(voidptr(ch), ch.tx, 7, ch.rx, 65536) == if mode == 1 { -110 } else { -71 }
		assert !ch.ready && !ch.quarantined && fixture_frees == before + 2
		assert exchange(voidptr(ch), ch.tx, 7, ch.rx, 65536) == -5
		ch.close()
		assert fixture_frees == before + 2
	}
	fixture_mode = 0
	ch = connect('share') or { panic('last reconnect') }
	fixture_mode = 2
	before := fixture_frees
	assert exchange(voidptr(ch), ch.tx, 7, ch.rx, 65536) == -110
	assert ch.quarantined && fixture_frees == before
	ch.close()
	assert fixture_frees == before && ninep_claimed
	connect('share') or {
		assert true
		return
	}
	assert false, 'quarantine must refuse reconnect'
}

module virtio_9p

fn test_two_actual_channels_close_and_quarantine_isolation() {
	fixture_mode = 0
	mut a := connect('tag-a') or { panic('a') }
	mut b := connect('tag-b') or { panic('b') }
	assert voidptr(a) != voidptr(b) && a.tx != b.tx && a.rx != b.rx
	assert a.ring.bus != b.ring.bus && a.buffers.bus != b.buffers.bus
	assert exchange(voidptr(a), a.tx, 7, a.rx, 65536) == 7
	assert exchange(voidptr(b), b.tx, 7, b.rx, 65536) == 7
	mut refused := false
	connect('unknown') or { refused = true }
	assert refused
	refused = false
	connect('tag-a') or { refused = true }
	assert refused
	assert exchange(voidptr(b), b.tx, 7, b.rx, 65536) == 7
	a.close()
	assert !a.claimed && b.claimed && ninep_claimed
	assert exchange(voidptr(b), b.tx, 7, b.rx, 65536) == 7
	a = connect('tag-a') or { panic('reconnect a') }
	fixture_mode = 2
	before := fixture_frees
	assert exchange(voidptr(a), a.tx, 7, a.rx, 65536) == -110
	assert a.quarantined && fixture_frees == before
	a.close()
	assert fixture_frees == before
	fixture_mode = 0
	refused = false
	connect('tag-a') or { refused = true }
	assert refused
	assert exchange(voidptr(b), b.tx, 7, b.rx, 65536) == 7
	b.close()
	assert fixture_frees == before + 2 && ninep_claimed
	println('MULTITAG-TRANSPORT-PASS independent DMA; claimed-device exclusion; unknown tag; close and quarantine isolation')
}

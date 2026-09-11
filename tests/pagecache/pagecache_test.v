module pagecache

import errno

struct Device {
mut:
	bytes       []u8
	reads       int
	writes      int
	fail_read   bool
	fail_write  bool
	short_read  bool
	short_write bool
}

fn device(size int) &Device {
	mut d := &Device{bytes: []u8{len: size}}
	for i in 0 .. size { d.bytes[i] = u8(i % 251) }
	return d
}

fn load(context voidptr, buf voidptr, loc u64, count u64) ?i64 {
	mut d := unsafe { &Device(context) }
	d.reads++
	if d.fail_read { errno.set(errno.eio); return none }
	assert loc <= u64(d.bytes.len) && count <= u64(d.bytes.len) - loc
	amount := if d.short_read { count / 2 } else { count }
	if amount != 0 { unsafe { C.memcpy(buf, &d.bytes[int(loc)], amount) } }
	return i64(amount)
}

fn store(context voidptr, buf voidptr, loc u64, count u64) ?i64 {
	mut d := unsafe { &Device(context) }
	d.writes++
	if d.fail_write { errno.set(errno.eio); return none }
	assert loc <= u64(d.bytes.len) && count <= u64(d.bytes.len) - loc
	amount := if d.short_write { count / 2 } else { count }
	if amount != 0 { unsafe { C.memcpy(&d.bytes[int(loc)], buf, amount) } }
	return i64(amount)
}

fn read_bytes(mut cache Cache, d &Device, loc int, count int) []u8 {
	mut out := []u8{len: count}
	mut ptr := voidptr(0)
	if count != 0 { ptr = unsafe { voidptr(&out[0]) } }
	got := cache.read(voidptr(d), load, store, ptr, u64(loc), u64(count), u64(d.bytes.len)) or {
		panic('unexpected cache read failure')
	}
	assert got == count
	return out
}

fn write_bytes(mut cache Cache, d &Device, loc int, bytes []u8) {
	mut ptr := voidptr(0)
	if bytes.len != 0 { ptr = unsafe { voidptr(&bytes[0]) } }
	got := cache.write(voidptr(d), load, store, ptr, u64(loc), u64(bytes.len), u64(d.bytes.len)) or {
		panic('unexpected cache write failure')
	}
	assert got == bytes.len
}

fn test_hits_cross_page_writes_and_writeback() {
	mut d := device(3 * 4096)
	mut cache := Cache{capacity: 3}
	defer { cache.release(voidptr(d), store) or { panic('release failed') } }
	assert read_bytes(mut cache, d, 511, 20) == d.bytes[511..531]
	assert read_bytes(mut cache, d, 1000, 10) == d.bytes[1000..1010]
	assert d.reads == 1
	before := d.bytes.clone()
	payload := []u8{len: 33, init: 0xa5}
	write_bytes(mut cache, d, 4090, payload)
	assert d.bytes == before
	assert d.writes == 0
	assert read_bytes(mut cache, d, 4090, 33) == payload
	assert read_bytes(mut cache, d, 4089, 1)[0] == before[4089]
	assert read_bytes(mut cache, d, 4123, 1)[0] == before[4123]
	cache.sync(voidptr(d), store) or { panic('sync failed') }
	assert d.bytes[4090..4123] == payload
	assert d.bytes[..4090] == before[..4090]
	assert d.bytes[4123..] == before[4123..]
	assert d.writes == 2
	cache.sync(voidptr(d), store) or { panic('clean sync failed') }
	assert d.writes == 2
}

fn test_full_replacement_and_device_tail_need_no_read() {
	mut d := device(4096 + 512)
	mut cache := Cache{capacity: 2}
	defer { cache.release(voidptr(d), store) or { panic('release failed') } }
	write_bytes(mut cache, d, 0, []u8{len: 4096, init: 0x21})
	write_bytes(mut cache, d, 4096, []u8{len: 512, init: 0x43})
	assert d.reads == 0
	cache.sync(voidptr(d), store) or { panic('sync failed') }
	assert d.bytes[..4096] == []u8{len: 4096, init: 0x21}
	assert d.bytes[4096..] == []u8{len: 512, init: 0x43}
}

fn test_failed_and_short_fills_are_not_published() {
	mut d := device(4096)
	mut cache := Cache{}
	defer { cache.release(voidptr(d), store) or { panic('release failed') } }
	mut out := u8(0)
	for short in [false, true] {
		d.fail_read = !short
		d.short_read = short
		mut failed := false
		cache.read(voidptr(d), load, store, &out, 0, 1, 4096) or { failed = true }
		assert failed
		assert cache.pages.len == 0
	}
	d.fail_read = false
	d.short_read = false
	assert read_bytes(mut cache, d, 0, 20) == d.bytes[..20]
	assert d.reads == 3
}

fn test_failed_eviction_retains_dirty_victim_and_retry() {
	mut d := device(8192)
	mut cache := Cache{capacity: 1}
	defer { cache.release(voidptr(d), store) or { panic('release failed') } }
	payload := []u8{len: 4096, init: 0x71}
	write_bytes(mut cache, d, 0, payload)
	d.fail_write = true
	mut out := u8(0)
	mut failed := false
	cache.read(voidptr(d), load, store, &out, 4096, 1, 8192) or { failed = true }
	assert failed
	assert cache.pages.len == 1 && cache.pages[0].index == 0 && cache.pages[0].dirty
	assert read_bytes(mut cache, d, 0, 4096) == payload
	d.fail_write = false
	assert read_bytes(mut cache, d, 4096, 1) == d.bytes[4096..4097]
	assert d.bytes[..4096] == payload
	assert cache.pages.len == 1 && cache.pages[0].index == 1
}

fn test_failed_and_short_sync_are_retryable() {
	mut d := device(4096)
	mut cache := Cache{}
	defer { cache.release(voidptr(d), store) or { panic('release failed') } }
	payload := []u8{len: 4096, init: 0x82}
	write_bytes(mut cache, d, 0, payload)
	for short in [false, true] {
		d.fail_write = !short
		d.short_write = short
		mut failed := false
		cache.sync(voidptr(d), store) or { failed = true }
		assert failed && cache.pages[0].dirty
		assert read_bytes(mut cache, d, 0, 4096) == payload
	}
	d.fail_write = false
	d.short_write = false
	cache.sync(voidptr(d), store) or { panic('retry failed') }
	assert d.bytes == payload
	assert !cache.pages[0].dirty
}

fn test_discard_preserves_dirty_and_partial_pages() {
	mut d := device(8192)
	mut cache := Cache{capacity: 2}
	defer { cache.release(voidptr(d), store) or { panic('release failed') } }
	read_bytes(mut cache, d, 0, 8192)
	cache.discard(1, 8190)
	assert cache.pages.len == 2
	write_bytes(mut cache, d, 0, [u8(99)])
	cache.discard(0, 8192)
	assert cache.pages.len == 1 && cache.pages[0].dirty
	cache.sync(voidptr(d), store) or { panic('sync failed') }
	cache.discard(0, 8192)
	assert cache.pages.len == 0
	reads := d.reads
	assert read_bytes(mut cache, d, 0, 1) == [u8(99)]
	assert d.reads == reads + 1
}

fn test_lru_and_bounded_prefetch() {
	mut d := device(10 * 4096)
	mut cache := Cache{capacity: 2}
	defer { cache.release(voidptr(d), store) or { panic('release failed') } }
	cache.prefetch(voidptr(d), load, store, 0, u64(d.bytes.len), u64(d.bytes.len))
	assert cache.pages.len == 2 && d.reads == 2
	read_bytes(mut cache, d, 0, 1)
	read_bytes(mut cache, d, 8192, 1)
	assert cache.pages[0].index == 0 && cache.pages[1].index == 2
	write_bytes(mut cache, d, 0, [u8(7)])
	read_bytes(mut cache, d, 8192, 1) // Dirty page is now LRU.
	reads := d.reads
	cache.prefetch(voidptr(d), load, store, 12288, 4096, u64(d.bytes.len))
	assert d.reads == reads && d.writes == 0
	assert cache.pages.len == 2
}

fn test_bounds_binding_zero_length_and_release_failure() {
	mut d := device(4096)
	mut other := device(4096)
	mut cache := Cache{}
	assert read_bytes(mut cache, d, 4096, 0).len == 0
	mut out := u8(0)
	for pair in [[u64(4096), u64(1)], [u64(-1), u64(2)], [u64(1), u64(-1)]] {
		mut failed := false
		cache.read(voidptr(d), load, store, &out, pair[0], pair[1], 4096) or { failed = true }
		assert failed
	}
	mut failed := false
	cache.read(voidptr(other), load, store, &out, 0, 1, 4096) or { failed = true }
	assert failed
	write_bytes(mut cache, d, 0, [u8(100)])
	d.fail_write = true
	failed = false
	cache.release(voidptr(d), store) or { failed = true }
	assert failed && cache.pages.len == 1 && cache.pages[0].dirty
	d.fail_write = false
	cache.release(voidptr(d), store) or { panic('release retry failed') }
	assert cache.pages.len == 0
	assert read_bytes(mut cache, other, 0, 1) == other.bytes[..1]
	cache.release(voidptr(other), store) or { panic('release failed') }
}

fn test_randomized_transfers_match_byte_model_under_pressure() {
	mut d := device(7 * 4096 + 512)
	mut expected := d.bytes.clone()
	mut cache := Cache{capacity: 3}
	mut seed := u64(0x12345678)
	for step in 0 .. 400 {
		seed ^= seed << 13
		seed ^= seed >> 7
		seed ^= seed << 17
		loc := int(seed % u64(expected.len))
		mut count := int((seed >> 17) % 7000) + 1
		if count > expected.len - loc { count = expected.len - loc }
		if step % 3 != 0 {
			payload := []u8{len: count, init: u8(seed & 255)}
			write_bytes(mut cache, d, loc, payload)
			for i in 0 .. count { expected[loc + i] = payload[i] }
		} else {
			assert read_bytes(mut cache, d, loc, count) == expected[loc..loc + count]
		}
		if step % 23 == 0 { cache.sync(voidptr(d), store) or { panic('sync failed') } }
		if step % 27 == 0 { cache.discard(0, u64(expected.len)) }
		assert cache.pages.len <= 3
	}
	cache.release(voidptr(d), store) or { panic('release failed') }
	assert d.bytes == expected
}

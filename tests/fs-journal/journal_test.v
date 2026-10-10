module journal

import memory

struct Disk {
mut:
	durable []u8
	pending []u8
	cuts [][]u8
	steps int
	fail_at int
	record bool
}

fn sized_disk(pages u64) &Disk {
	mut d := &Disk{durable: []u8{len: int(reserved_bytes + pages * page_bytes)},
		pending: []u8{len: int(reserved_bytes + pages * page_bytes)}}
	format(d, store, barrier, u64(d.durable.len), pages * page_bytes, [u64(13), 29]!) or { assert false }
	return d
}
fn disk() &Disk { return sized_disk(8) }

fn load(context voidptr, buffer voidptr, offset u64, bytes u64) ?i64 {
	d := unsafe { &Disk(context) }
	if offset > u64(d.pending.len) || bytes > u64(d.pending.len) - offset { return none }
	unsafe { C.memcpy(buffer, &d.pending[int(offset)], bytes) }
	return i64(bytes)
}

fn (mut d Disk) snapshot() {
	if d.record {
		d.cuts << d.durable.clone()
		// A device may persist writes before an explicit barrier too.
		d.cuts << d.pending.clone()
	}
}

fn store(context voidptr, buffer voidptr, offset u64, bytes u64) ?i64 {
	mut d := unsafe { &Disk(context) }
	d.steps++
	if d.steps == d.fail_at { return none }
	if offset > u64(d.pending.len) || bytes > u64(d.pending.len) - offset { return none }
	if d.record {
		// Crash during a torn write, including commit publication/clearing.
		mut torn := d.pending.clone()
		unsafe { C.memcpy(&torn[int(offset)], buffer, bytes / 2) }
		d.cuts << torn
	}
	unsafe { C.memcpy(&d.pending[int(offset)], buffer, bytes) }
	d.snapshot()
	return i64(bytes)
}

fn barrier(context voidptr) ? {
	mut d := unsafe { &Disk(context) }
	d.steps++
	if d.steps == d.fail_at { return none }
	unsafe { C.memcpy(d.durable.data, d.pending.data, d.pending.len) }
	d.snapshot()
}

fn publish(_context voidptr, _buffer voidptr, _offset u64, _bytes u64) {}

fn opened(d &Disk) &Log {
	return open(d, load, store, barrier, publish, u64(d.durable.len), true) or { panic('open failed') }
}

fn transaction(mut log Log) {
	log.begin() or { assert false }
	mut first := [4096]u8{}
	mut second := [4096]u8{}
	unsafe { C.memset(&first[0], 0x51, first.len); C.memset(&second[0], 0xa2, second.len) }
	assert log.write(load, &first[0], 0, page_bytes) or { -1 } == i64(page_bytes)
	assert log.write(load, &second[0], 3 * page_bytes, page_bytes) or { -1 } == i64(page_bytes)
}

fn assert_consistent(d &Disk) {
	first := d.durable[0]
	second := d.durable[3 * page_bytes]
	assert (first == 0 && second == 0) || (first == 0x51 && second == 0xa2)
	for i in 0 .. int(page_bytes) {
		assert d.durable[i] == first
		assert d.durable[int(3 * page_bytes) + i] == second
	}
}

fn test_crc32c_known_vector() {
	text := '123456789'
	assert checksum(text.str, u64(text.len)) == 0xe3069283
}

fn test_staging_abort_and_bounds_never_touch_home_pages() {
	before := memory.live
	mut d := disk()
	mut log := opened(d)
	transaction(mut log)
	mut read := [8]u8{}
	assert log.read(load, &read[0], 4093, 8) or { -1 } == 8
	assert read[0] == 0x51 && read[2] == 0x51 && read[3] == 0
	assert d.pending[0] == 0 && d.durable[0] == 0
	assert log.write(load, &read[0], u64(-1), 8) or { -1 } == -1
	log.abort()
	assert log.read(load, &read[0], 0, 8) or { -1 } == 8 && read[0] == 0
	log.release()
	assert memory.live == before
}

fn test_every_commit_and_recovery_power_cut_is_old_or_new() {
	before := memory.live
	mut d := disk()
	mut log := opened(d)
	d.record = true
	transaction(mut log)
	log.commit() or { assert false }
	assert d.durable[0] == 0x51 && d.durable[3 * page_bytes] == 0xa2
	log.release()
	for image in d.cuts {
		mut reboot := &Disk{durable: image.clone(), pending: image.clone(), record: true}
		mut recovery := opened(reboot)
		recovery.release()
		assert_consistent(reboot)
		// Power can fail again at any recovery checkpoint or marker clear.
		for interrupted in reboot.cuts {
			mut again := &Disk{durable: interrupted.clone(), pending: interrupted.clone()}
			mut retry := opened(again)
			retry.release()
			assert_consistent(again)
		}
	}
	assert memory.live == before
}

fn test_io_error_poison_prevents_reuse_and_next_mount_recovers() {
	before := memory.live
	for failing_step in 1 .. 12 {
		mut d := disk()
		mut log := opened(d)
		transaction(mut log)
		d.steps = 0
		d.fail_at = failing_step
		mut failed := false
		log.commit() or { failed = true }
		assert failed && log.failed
		log.begin() or { assert log.failed }
		mut bytes := [8]u8{}
		assert log.read(load, &bytes[0], 0, 8) or { -1 } == -1
		log.release()
		unsafe { C.memcpy(d.pending.data, d.durable.data, d.durable.len) }
		d.fail_at = 0
		mut retry := opened(d)
		retry.release()
		assert_consistent(d)
	}
	assert memory.live == before
}

fn test_corrupt_committed_payload_fails_before_any_home_write() {
	before := memory.live
	mut d := disk()
	mut log := opened(d)
	transaction(mut log)
	d.steps = 0
	d.fail_at = 7 // first home write, after the committed-log barrier
	log.commit() or {}
	assert log.failed && d.durable[0] == 0
	log.release()
	d.fail_at = 0
	journal_offset := location(u64(d.durable.len)) or { panic('location') }
	d.durable[int(journal_offset + data_start)] ^= 1
	unsafe { C.memcpy(d.pending.data, d.durable.data, d.durable.len) }
	mut rejected := false
	open(d, load, store, barrier, publish, u64(d.durable.len), true) or { rejected = true }
	assert rejected && d.durable[0] == 0 && d.durable[3 * page_bytes] == 0
	assert memory.live == before
}

fn test_dirty_read_only_mount_is_rejected_without_io() {
	before := memory.live
	mut d := disk()
	mut log := opened(d)
	transaction(mut log)
	d.steps = 0
	d.fail_at = 7
	log.commit() or {}
	log.release()
	d.fail_at = 0
	unsafe { C.memcpy(d.pending.data, d.durable.data, d.durable.len) }
	steps := d.steps
	mut rejected := false
	open(d, load, store, barrier, publish, u64(d.durable.len), false) or { rejected = true }
	assert rejected && d.steps == steps
	assert memory.live == before
}

fn test_allocation_failure_aborts_without_poison_or_retention() {
	before := memory.live
	mut d := disk()
	for limit in 0 .. 2 {
		memory.left = limit
		mut rejected := false
		open(d, load, store, barrier, publish, u64(d.durable.len), true) or { rejected = true }
		assert rejected && memory.live == before
	}
	memory.left = -1
	mut log := opened(d)
	log.begin() or { assert false }
	mut byte := u8(0x81)
	assert log.write(load, &byte, 0, 1) or { -1 } == 1
	memory.left = 0
	assert log.write(load, &byte, page_bytes, 1) or { -1 } == -1
	memory.left = -1
	mut rejected := false
	log.commit() or { rejected = true }
	assert rejected && !log.failed && d.durable[0] == 0 && d.pending[0] == 0
	transaction(mut log)
	log.commit() or { assert false }
	log.release()
	assert memory.live == before
}

fn test_capacity_error_cannot_commit_a_partial_mutation() {
	before := memory.live
	mut d := sized_disk(u64(max_pages + 1))
	mut log := opened(d)
	log.begin() or { assert false }
	mut byte := u8(0x9f)
	for i in 0 .. max_pages { assert log.write(load, &byte, u64(i) * page_bytes, 1) or { -1 } == 1 }
	assert log.write(load, &byte, u64(max_pages) * page_bytes, 1) or { -1 } == -1
	mut rejected := false
	log.commit() or { rejected = true }
	assert rejected && !log.failed
	for i in 0 .. max_pages + 1 { assert d.durable[u64(i) * page_bytes] == 0 }
	log.release()
	assert memory.live == before
}

fn test_recovery_rejects_duplicate_and_out_of_range_destinations() {
	before := memory.live
	for duplicate in [true, false] {
		mut d := disk()
		mut log := opened(d)
		transaction(mut log)
		d.steps = 0
		d.fail_at = 7
		log.commit() or {}
		log.release()
		d.fail_at = 0
		offset := location(u64(d.durable.len)) or { panic('location') }
		mut descriptor := unsafe { &Descriptor(&d.durable[offset + 2 * page_bytes + sizeof(Descriptor)]) }
		descriptor.offset = if duplicate { u64(0) } else { offset }
		mut marker := unsafe { &Commit(&d.durable[offset + page_bytes]) }
		marker.descriptors_crc = checksum(unsafe { &d.durable[offset + 2 * page_bytes] }, descriptor_bytes)
		marker.checksum = 0
		marker.checksum = checksum(unsafe { &d.durable[offset + page_bytes] }, page_bytes)
		unsafe { C.memcpy(d.pending.data, d.durable.data, d.durable.len) }
		mut rejected := false
		open(d, load, store, barrier, publish, u64(d.durable.len), true) or { rejected = true }
		assert rejected && d.durable[0] == 0 && d.durable[3 * page_bytes] == 0
	}
	assert memory.live == before
}

fn test_full_descriptor_bank_and_recovery_allocation_failures() {
	before := memory.live
	mut d := sized_disk(u64(max_pages))
	mut log := opened(d)
	log.begin() or { assert false }
	for i in 0 .. max_pages {
		mut byte := u8(i % 251 + 1)
		assert log.write(load, &byte, u64(i) * page_bytes, 1) or { -1 } == 1
	}
	d.steps = 0
	d.fail_at = max_pages + 5 // first home write after all payloads and commit barrier
	log.commit() or {}
	assert log.failed && d.durable[0] == 0
	log.release()
	d.fail_at = 0
	for limit in [0, 1, 2, 17, max_pages + 1] {
		unsafe { C.memcpy(d.pending.data, d.durable.data, d.durable.len) }
		memory.left = limit
		mut rejected := false
		open(d, load, store, barrier, publish, u64(d.durable.len), true) or { rejected = true }
		memory.left = -1
		assert rejected && memory.live == before
		for i in 0 .. max_pages { assert d.durable[u64(i) * page_bytes] == 0 }
	}
	mut recovery := opened(d)
	recovery.release()
	for i in 0 .. max_pages { assert d.durable[u64(i) * page_bytes] == u8(i % 251 + 1) }
	assert memory.live == before
}

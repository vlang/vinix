// SPDX-License-Identifier: GPL-2.0-or-later
// A bounded full-data redo journal. Callers serialize a volume's transactions.
module journal

import errno
import memory

pub const page_bytes = u64(4096)
pub const reserved_bytes = u64(4 * 1024 * 1024)
pub const max_pages = 512
const config_magic = u64(0x314c4e4a58494e56) // VINXJNL1
const commit_magic = u64(0x31544d4358494e56) // VINXCMT1
const descriptor_bytes = u64(8192)
const data_start = u64(4 * 4096)

pub type IO = fn (voidptr, voidptr, u64, u64) ?i64
pub type Barrier = fn (voidptr) ?
pub type Publish = fn (voidptr, voidptr, u64, u64)
pub type Phase = fn (voidptr, int)

@[packed]
struct Config {
mut:
	magic u64
	version u32
	page_size u32
	volume_bytes u64
	offset u64
	reserved u64
	uuid [2]u64
	checksum u32
	padding u32
}

@[packed]
struct Commit {
mut:
	magic u64
	sequence u64
	count u32
	descriptors_crc u32
	checksum u32
	padding u32
}

@[packed]
struct Descriptor {
mut:
	offset u64
	checksum u32
	padding u32
}

struct Image {
mut:
	offset u64
	data voidptr
}

pub struct Log {
mut:
	context voidptr
	load IO = unsafe { nil }
	store IO = unsafe { nil }
	barrier Barrier = unsafe { nil }
	publish Publish = unsafe { nil }
	images [max_pages]Image
	count int
	scratch voidptr
	sequence u64
	active bool
	staging_error int
pub:
	volume_bytes u64
	offset u64
	uuid [2]u64
pub mut:
	failed bool
	// Optional deterministic fault injection; production mounts leave nil.
	phase Phase = unsafe { nil }
	cut_stage int
}

// CRC32C, with no tables, allocation or architecture-specific instructions.
fn checksum(buffer voidptr, bytes u64) u32 {
	mut crc := u32(0xffffffff)
	for i in 0 .. bytes {
		crc ^= unsafe { *(&u8(u64(buffer) + i)) }
		for _ in 0 .. 8 { crc = (crc >> 1) ^ (u32(0x82f63b78) & (u32(0) - (crc & 1))) }
	}
	return ~crc
}

fn exact(io IO, context voidptr, buffer voidptr, offset u64, bytes u64) ? {
	if io(context, buffer, offset, bytes)? != i64(bytes) { errno.set(errno.eio); return none }
}

pub fn location(device_bytes u64) ?u64 {
	if device_bytes < reserved_bytes + page_bytes { errno.set(errno.enospc); return none }
	return (device_bytes / page_bytes) * page_bytes - reserved_bytes
}

// Write this before publishing the filesystem's primary superblock signature.
pub fn format(context voidptr, store IO, barrier Barrier, device_bytes u64,
	volume_bytes u64, uuid [2]u64) ? {
	offset := location(device_bytes)?
	if volume_bytes == 0 || volume_bytes > offset || volume_bytes % page_bytes != 0 {
		errno.set(errno.einval); return none
	}
	buffer := memory.malloc_packed_fallible(page_bytes) @[freed]
	if buffer == unsafe { nil } { errno.set(errno.enomem); return none }
	defer { memory.free(buffer) }
	unsafe { C.memset(buffer, 0, page_bytes) }
	exact(store, context, buffer, offset + page_bytes, page_bytes)?
	mut config := unsafe { &Config(buffer) }
	config.magic = config_magic
	config.version = 1
	config.page_size = u32(page_bytes)
	config.volume_bytes = volume_bytes
	config.offset = offset
	config.reserved = reserved_bytes
	config.uuid = uuid
	config.checksum = checksum(buffer, page_bytes)
	exact(store, context, buffer, offset, page_bytes)?
	barrier(context)?
}

// A missing signature is a legacy volume. A recognized but invalid journal
// fails closed. Recovery happens before a filesystem reads any home metadata.
pub fn open(context voidptr, load IO, store IO, barrier Barrier, publish Publish,
	device_bytes u64, writable bool) ?&Log {
	if device_bytes < reserved_bytes + page_bytes { return unsafe { nil } }
	offset := location(device_bytes)?
	buffer := memory.malloc_packed_fallible(descriptor_bytes) @[freed]
	if buffer == unsafe { nil } { errno.set(errno.enomem); return none }
	mut retained := false
	defer { if !retained { memory.free(buffer) } }
	exact(load, context, buffer, offset, page_bytes)?
	mut config := unsafe { &Config(buffer) }
	if config.magic != config_magic { return unsafe { nil } }
	crc := config.checksum
	config.checksum = 0
	if crc != checksum(buffer, page_bytes) || config.version != 1
		|| config.page_size != page_bytes || config.offset != offset
		|| config.reserved != reserved_bytes || config.volume_bytes == 0
		|| config.volume_bytes > offset || config.volume_bytes % page_bytes != 0 {
		errno.set(errno.eio); return none
	}
	mut log := unsafe { &Log(memory.malloc_packed_fallible(sizeof(Log))) } @[freed]
	if log == unsafe { nil } { errno.set(errno.enomem); return none }
	unsafe { *log = Log{context: context, load: load, store: store, barrier: barrier,
		publish: publish, volume_bytes: config.volume_bytes, offset: offset,
		uuid: config.uuid, scratch: buffer} }
	retained = true
	log.recover(writable) or { log.release(); return none }
	return log
}

pub fn (mut log Log) begin() ? {
	if log.failed || log.active { errno.set(errno.eio); return none }
	log.active = true
}

pub fn (log &Log) staged_pages() int { return log.count }

pub fn (mut log Log) abort() {
	for i in 0 .. log.count { memory.free(log.images[i].data); log.images[i].data = unsafe { nil } }
	log.count = 0
	log.active = false
	log.staging_error = 0
}

pub fn (mut log Log) release() {
	log.abort()
	memory.free(log.scratch)
	memory.free(log)
}

fn (log &Log) valid_range(offset u64, bytes u64) bool {
	return offset <= log.volume_bytes && bytes <= log.volume_bytes - offset
}

fn (log &Log) find(offset u64) int {
	for i in 0 .. log.count { if log.images[i].offset == offset { return i } }
	return -1
}

pub fn (mut log Log) read(base_load IO, buffer voidptr, offset u64, bytes u64) ?i64 {
	return log.read_inner(base_load, buffer, offset, bytes) or {
		if log.active { log.staging_error = if errno.get() != 0 { errno.get() } else { errno.eio } }
		return none
	}
}

fn (mut log Log) read_inner(base_load IO, buffer voidptr, offset u64, bytes u64) ?i64 {
	if log.failed || !log.valid_range(offset, bytes) { errno.set(errno.eio); return none }
	mut done := u64(0)
	for done < bytes {
		at := offset + done
		page := (at / page_bytes) * page_bytes
		chunk := if bytes - done < page_bytes - at % page_bytes { bytes - done }
			else { page_bytes - at % page_bytes }
		index := log.find(page)
		if index >= 0 {
			unsafe { C.memcpy(voidptr(u64(buffer) + done), voidptr(u64(log.images[index].data) + at % page_bytes), chunk) }
		} else { exact(base_load, log.context, voidptr(u64(buffer) + done), at, chunk)? }
		done += chunk
	}
	return i64(bytes)
}

pub fn (mut log Log) write(base_load IO, buffer voidptr, offset u64, bytes u64) ?i64 {
	return log.write_inner(base_load, buffer, offset, bytes) or {
		log.staging_error = if errno.get() != 0 { errno.get() } else { errno.eio }
		return none
	}
}

fn (mut log Log) write_inner(base_load IO, buffer voidptr, offset u64, bytes u64) ?i64 {
	if !log.active || log.failed || !log.valid_range(offset, bytes) { errno.set(errno.eio); return none }
	mut done := u64(0)
	for done < bytes {
		at := offset + done
		page := (at / page_bytes) * page_bytes
		chunk := if bytes - done < page_bytes - at % page_bytes { bytes - done }
			else { page_bytes - at % page_bytes }
		mut index := log.find(page)
		if index < 0 {
			if log.count == max_pages { errno.set(errno.e2big); return none }
			data := memory.malloc_packed_fallible(page_bytes) @[freed]
			if data == unsafe { nil } { errno.set(errno.enomem); return none }
			exact(base_load, log.context, data, page, page_bytes) or { memory.free(data); return none }
			index = log.count
			log.images[index] = Image{offset: page, data: data}
			log.count++
		}
		unsafe { C.memcpy(voidptr(u64(log.images[index].data) + at % page_bytes), voidptr(u64(buffer) + done), chunk) }
		done += chunk
	}
	return i64(bytes)
}

fn (mut log Log) clear_marker() ? {
	unsafe { C.memset(log.scratch, 0, page_bytes) }
	exact(log.store, log.context, log.scratch, log.offset + page_bytes, page_bytes)?
	log.barrier(log.context)?
}

// Checkpoint only after the commit marker and all payloads are durable.
fn (mut log Log) checkpoint() ? {
	for i in 0 .. log.count {
		exact(log.store, log.context, log.images[i].data, log.images[i].offset, page_bytes)?
		if i == 0 { log.notify(3) }
	}
	log.barrier(log.context)?
	log.notify(4)
	for i in 0 .. log.count {
		log.publish(log.context, log.images[i].data, log.images[i].offset, page_bytes)
	}
	log.clear_marker()?
	log.notify(5)
}

fn (log &Log) notify(stage int) {
	if log.phase != unsafe { nil } { log.phase(log.context, stage) }
}

fn (mut log Log) commit_inner() ? {
	unsafe { C.memset(log.scratch, 0, descriptor_bytes) }
	for i in 0 .. log.count {
		mut descriptor := unsafe { &Descriptor(u64(log.scratch) + u64(i) * sizeof(Descriptor)) }
		descriptor.offset = log.images[i].offset
		descriptor.checksum = checksum(log.images[i].data, page_bytes)
		exact(log.store, log.context, log.images[i].data, log.offset + data_start + u64(i) * page_bytes, page_bytes)?
	}
	descriptors_crc := checksum(log.scratch, descriptor_bytes)
	exact(log.store, log.context, log.scratch, log.offset + 2 * page_bytes, descriptor_bytes)?
	log.barrier(log.context)?
	log.notify(1)
	unsafe { C.memset(log.scratch, 0, page_bytes) }
	mut marker := unsafe { &Commit(log.scratch) }
	log.sequence++
	marker.magic = commit_magic
	marker.sequence = log.sequence
	marker.count = u32(log.count)
	marker.descriptors_crc = descriptors_crc
	marker.checksum = checksum(log.scratch, page_bytes)
	exact(log.store, log.context, log.scratch, log.offset + page_bytes, page_bytes)?
	log.barrier(log.context)?
	log.notify(2)
	log.checkpoint()?
}

pub fn (mut log Log) commit() ? {
	if !log.active || log.failed { errno.set(errno.eio); return none }
	if log.staging_error != 0 {
		code := log.staging_error
		log.abort()
		errno.set(u64(code))
		return none
	}
	if log.count != 0 {
		log.commit_inner() or {
			// A failed barrier can leave a committed transaction on disk. Never
			// reuse its log or serve stale home bytes until mount-time recovery.
			log.failed = true
			log.abort()
			return none
		}
	}
	log.abort()
}

fn (mut log Log) recover(writable bool) ? {
	exact(log.load, log.context, log.scratch, log.offset + page_bytes, page_bytes)?
	mut marker := unsafe { &Commit(log.scratch) }
	if marker.magic == 0 { return }
	crc := marker.checksum
	marker.checksum = 0
	if marker.magic != commit_magic || crc != checksum(log.scratch, page_bytes) {
		// A torn commit precedes home writes; a torn clear follows the home
		// barrier. Either leaves a consistent home image. Clear durably before
		// reusing payload slots, including on a second crash during recovery.
		if writable { log.clear_marker()? }
		return
	}
	if !writable { errno.set(errno.erofs); return none }
	count := int(marker.count)
	descriptors_crc := marker.descriptors_crc
	log.sequence = marker.sequence
	if count <= 0 || count > max_pages { errno.set(errno.eio); return none }
	exact(log.load, log.context, log.scratch, log.offset + 2 * page_bytes, descriptor_bytes)?
	if checksum(log.scratch, descriptor_bytes) != descriptors_crc { errno.set(errno.eio); return none }
	// Validate and retain the entire transaction before touching any home page.
	for i in 0 .. count {
		descriptor := unsafe { &Descriptor(u64(log.scratch) + u64(i) * sizeof(Descriptor)) }
		if descriptor.offset % page_bytes != 0 || !log.valid_range(descriptor.offset, page_bytes)
			|| log.find(descriptor.offset) >= 0 || descriptor.padding != 0 {
			errno.set(errno.eio); return none
		}
		data := memory.malloc_packed_fallible(page_bytes) @[freed]
		if data == unsafe { nil } { errno.set(errno.enomem); return none }
		exact(log.load, log.context, data, log.offset + data_start + u64(i) * page_bytes, page_bytes) or {
			memory.free(data); return none
		}
		if checksum(data, page_bytes) != descriptor.checksum { memory.free(data); errno.set(errno.eio); return none }
		log.images[i] = Image{offset: descriptor.offset, data: data}
		log.count++
	}
	log.checkpoint()?
	log.abort()
}

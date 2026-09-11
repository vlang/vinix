// A bounded backing-store page cache. The same cache must be used for every
// access to a backing resource; callbacks must bypass the cache itself.
module pagecache

import errno
import klock

pub const page_bytes = u64(4096)
pub const default_capacity = 128
pub const willneed = 3
pub const dontneed = 4

pub type IO = fn (voidptr, voidptr, u64, u64) ?i64

struct Page {
mut:
	index u64
	valid u64
	dirty bool
	data  [4096]u8
}

pub struct Cache {
mut:
	l        klock.Lock
	pages    []&Page // Least recently used first.
	owner    voidptr
	size     u64
pub:
	capacity int = default_capacity
}

// Binding prevents accidentally using resident pages with a different device
// or capacity. Device sizes are fixed for the lifetime of a cache.
fn (mut this Cache) bind(context voidptr, size u64) ? {
	if context == unsafe { nil } || this.capacity <= 0 {
		errno.set(errno.einval)
		return none
	}
	if this.owner == unsafe { nil } {
		this.owner = context
		this.size = size
	} else if this.owner != context || this.size != size {
		errno.set(errno.einval)
		return none
	}
}

fn valid_range(loc u64, count u64, size u64) bool {
	return loc <= size && count <= size - loc && count <= u64(0x7fffffffffffffff)
}

fn (mut page Page) flush(context voidptr, store IO) ? {
	if !page.dirty {
		return
	}
	ret := store(context, voidptr(&page.data[0]), page.index * page_bytes, page.valid) or {
		return none
	}
	// A short write is not a completed page writeback. Keep the entire page
	// dirty so a later fsync can retry, including the already-written prefix.
	if ret != i64(page.valid) {
		errno.set(errno.eio)
		return none
	}
	page.dirty = false
}

// Called with l held. A failed fill is never published, and a failed eviction
// leaves the dirty victim in the cache, still readable and retryable.
fn (mut this Cache) get(context voidptr, load IO, store IO, index u64, fill bool) ?&Page {
	for i, page in this.pages {
		if page.index == index {
			this.pages.delete(i)
			this.pages << page
			return page
		}
	}

	mut page := &Page(unsafe { nil })
	if this.pages.len >= this.capacity {
		page = this.pages[0]
		page.flush(context, store) or { return none }
		this.pages.delete(0)
	} else {
		page = unsafe { &Page(malloc(sizeof(Page))) }
		if page == unsafe { nil } {
			errno.set(errno.enomem)
			return none
		}
	}
	unsafe { C.memset(page, 0, sizeof(Page)) }
	page.index = index
	page.valid = page_bytes
	if this.size - index * page_bytes < page.valid {
		page.valid = this.size - index * page_bytes
	}
	if fill {
		ret := load(context, voidptr(&page.data[0]), index * page_bytes, page.valid) or {
			unsafe { free(page) }
			return none
		}
		if ret != i64(page.valid) {
			unsafe { free(page) }
			errno.set(errno.eio)
			return none
		}
	}
	this.pages << page
	return page
}

// These are exact backing-store transfers, not file reads: an out-of-bounds
// range is rejected rather than clipped at EOF. On an I/O error after progress,
// return the completed prefix, as a Resource read/write would.
pub fn (mut this Cache) read(context voidptr, load IO, store IO, buf voidptr, loc u64, count u64, size u64) ?i64 {
	this.l.acquire()
	defer { this.l.release() }
	this.bind(context, size) or { return none }
	if !valid_range(loc, count, size) {
		errno.set(errno.einval)
		return none
	}
	mut done := u64(0)
	for done < count {
		index := (loc + done) / page_bytes
		offset := (loc + done) % page_bytes
		mut amount := page_bytes - offset
		if amount > count - done { amount = count - done }
		page := this.get(context, load, store, index, true) or {
			if done != 0 { return i64(done) }
			return none
		}
		unsafe { C.memcpy(voidptr(u64(buf) + done), &page.data[int(offset)], amount) }
		done += amount
	}
	return i64(done)
}

pub fn (mut this Cache) write(context voidptr, load IO, store IO, buf voidptr, loc u64, count u64, size u64) ?i64 {
	this.l.acquire()
	defer { this.l.release() }
	this.bind(context, size) or { return none }
	if !valid_range(loc, count, size) {
		errno.set(errno.einval)
		return none
	}
	mut done := u64(0)
	for done < count {
		index := (loc + done) / page_bytes
		offset := (loc + done) % page_bytes
		mut amount := page_bytes - offset
		if amount > count - done { amount = count - done }
		mut valid := page_bytes
		if size - index * page_bytes < valid { valid = size - index * page_bytes }
		// Full-page replacements need no read. Partial writes must preserve
		// every byte outside the requested range, including device tails.
		mut page := this.get(context, load, store, index, offset != 0 || amount != valid) or {
			if done != 0 { return i64(done) }
			return none
		}
		unsafe { C.memcpy(&page.data[int(offset)], voidptr(u64(buf) + done), amount) }
		page.dirty = true
		done += amount
	}
	return i64(done)
}

pub fn (mut this Cache) sync(context voidptr, store IO) ? {
	this.l.acquire()
	defer { this.l.release() }
	if this.owner == unsafe { nil } { return }
	if this.owner != context {
		errno.set(errno.einval)
		return none
	}
	for mut page in this.pages {
		page.flush(context, store) or { return none }
	}
}

// Best-effort prefetch is deliberately bounded and never evicts dirty data.
// Advice must not turn into an unbounded scan or unexpected writeback storm.
pub fn (mut this Cache) prefetch(context voidptr, load IO, store IO, loc u64, count u64, size u64) {
	this.l.acquire()
	defer { this.l.release() }
	this.bind(context, size) or { return }
	if !valid_range(loc, count, size) || count == 0 { return }
	last := (loc + count - 1) / page_bytes
	mut index := loc / page_bytes
	mut budget := this.capacity
	for index <= last && budget > 0 {
		if this.pages.len >= this.capacity && this.pages[0].dirty { return }
		this.get(context, load, store, index, true) or { return }
		index++
		budget--
	}
}

// Drop only clean pages wholly covered by the physical range. Dirty pages
// stay resident: DONTNEED is not permission to lose acknowledged writes.
pub fn (mut this Cache) discard(loc u64, count u64) {
	this.l.acquire()
	defer { this.l.release() }
	if !valid_range(loc, count, this.size) { return }
	end := loc + count
	for i := this.pages.len - 1; i >= 0; i-- {
		page := this.pages[i]
		start := page.index * page_bytes
		if !page.dirty && start >= loc && start + page.valid <= end {
			this.pages.delete(i)
			unsafe { free(page) }
		}
	}
}

// Drop up to `budget` clean LRU pages without performing I/O. This is the
// cache's memory-pressure path: dirty pages remain resident and retryable, and
// failure to acquire the cache lock simply lets another reclaimer be tried.
pub fn (mut this Cache) reclaim_clean(budget u64) u64 {
	if budget == 0 || !this.l.test_and_acquire() {
		return 0
	}
	defer { this.l.release() }

	mut reclaimed := u64(0)
	mut i := 0
	for i < this.pages.len && reclaimed < budget {
		page := this.pages[i]
		if page.dirty {
			i++
			continue
		}
		this.pages.delete(i)
		unsafe { free(page) }
		reclaimed++
	}
	return reclaimed
}

// Teardown is failure-atomic with respect to dirty data. Callers must not
// destroy the cache/backing resource if release fails.
pub fn (mut this Cache) release(context voidptr, store IO) ? {
	this.l.acquire()
	defer { this.l.release() }
	if this.owner != unsafe { nil } && this.owner != context {
		errno.set(errno.einval)
		return none
	}
	for mut page in this.pages {
		page.flush(context, store) or { return none }
	}
	for page in this.pages { unsafe { free(page) } }
	unsafe { this.pages.free() }
	this.pages = []&Page{}
	this.owner = unsafe { nil }
	this.size = 0
}

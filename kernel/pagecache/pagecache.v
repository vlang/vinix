// A bounded backing-store page cache. The same cache must be used for every
// access to a backing resource; callbacks must bypass the cache itself.
module pagecache

import errno
import klock

pub const page_bytes = u64(4096)
pub const default_capacity = 128
// 256 MiB of cached blocks, reached by an 8 GiB device. A machine that runs
// from its disk demand-pages hundreds of megabytes of executable out of it —
// a browser's own libraries dwarf anything smaller — and a cache that cannot
// hold that working set spends its time re-reading pages it has just dropped.
// Growth stays bounded because the reclaimer hands clean pages back under
// memory pressure.
pub const max_capacity = u64(65536)
pub const willneed = 3
pub const dontneed = 4

pub type IO = fn (voidptr, voidptr, u64, u64) ?i64

struct Page {
mut:
	index u64
	valid u64
	dirty bool
	// Residency is kept as an intrusive LRU list and a bucket chain rather
	// than as one array: a cache large enough to run a system from has
	// thousands of pages, and searching and reordering an array of them on
	// every 4 KiB access costs far more than the transfer it is there to
	// avoid.
	lru_previous &Page = unsafe { nil }
	lru_next     &Page = unsafe { nil }
	bucket_next  &Page = unsafe { nil }
	data         [4096]u8
}

pub struct Cache {
mut:
	l klock.Lock
	// buckets indexes residency by page number; the list orders it by use,
	// least recently used first.
	buckets      []&Page
	bucket_mask  u64
	lru_first    &Page = unsafe { nil }
	lru_last     &Page = unsafe { nil }
	resident     int
	owner        voidptr
	size         u64
	// Recorded by register_cache so a descriptor-less flush -- sync(2), or the
	// reboot path -- can reach the backing store. Both are nil until then.
	writeback_context voidptr
	writeback         IO
pub:
	capacity int = default_capacity
}

// A cache sized for its backing store. The default suits a small volume
// holding user data; a device the whole system runs from needs enough room for
// the inode tables and directory blocks a path walk touches, or every lookup
// evicts the metadata the next one wants. Growth is bounded because the
// reclaimer hands clean pages back under memory pressure.
pub fn new_cache(device_bytes u64) &Cache {
	mut pages := device_bytes / (128 * 1024)
	if pages < u64(default_capacity) {
		pages = u64(default_capacity)
	}
	if pages > max_capacity {
		pages = max_capacity
	}
	return &Cache{
		capacity: int(pages)
	}
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
		this.open_buckets()
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


// One bucket per resident page, rounded up to a power of two so that the page
// number can be masked rather than divided. Page numbers are consecutive, so
// masking spreads a sequential walk across every bucket.
fn (mut this Cache) open_buckets() {
	if this.buckets.len != 0 {
		return
	}
	mut count := 1
	for count < this.capacity {
		count *= 2
	}
	this.buckets = []&Page{len: count, init: unsafe { nil }}
	this.bucket_mask = u64(count - 1)
}

@[inline]
fn (this &Cache) resident_page(index u64) &Page {
	if this.buckets.len == 0 {
		return unsafe { nil }
	}
	mut page := this.buckets[int(index & this.bucket_mask)]
	for page != unsafe { nil } {
		if page.index == index {
			return page
		}
		page = page.bucket_next
	}
	return unsafe { nil }
}

fn (mut this Cache) publish(mut page Page) {
	bucket := int(page.index & this.bucket_mask)
	page.bucket_next = this.buckets[bucket]
	this.buckets[bucket] = page
	this.link_recent(mut page)
	this.resident++
}

fn (mut this Cache) withdraw(mut page Page) {
	bucket := int(page.index & this.bucket_mask)
	mut current := this.buckets[bucket]
	if current == unsafe { nil } {
		return
	}
	if voidptr(current) == voidptr(page) {
		this.buckets[bucket] = page.bucket_next
	} else {
		for current.bucket_next != unsafe { nil } {
			if voidptr(current.bucket_next) == voidptr(page) {
				current.bucket_next = page.bucket_next
				break
			}
			current = current.bucket_next
		}
	}
	page.bucket_next = unsafe { nil }
	this.unlink(mut page)
	this.resident--
}

// The list runs least recently used first, so eviction and reclaim take its
// front and every use moves a page to its back.
fn (mut this Cache) link_recent(mut page Page) {
	page.lru_previous = this.lru_last
	page.lru_next = unsafe { nil }
	if this.lru_last != unsafe { nil } {
		this.lru_last.lru_next = page
	} else {
		this.lru_first = page
	}
	this.lru_last = page
}

fn (mut this Cache) unlink(mut page Page) {
	if page.lru_previous != unsafe { nil } {
		page.lru_previous.lru_next = page.lru_next
	} else {
		this.lru_first = page.lru_next
	}
	if page.lru_next != unsafe { nil } {
		page.lru_next.lru_previous = page.lru_previous
	} else {
		this.lru_last = page.lru_previous
	}
	page.lru_previous = unsafe { nil }
	page.lru_next = unsafe { nil }
}

// Called with l held. A failed fill is never published, and a failed eviction
// leaves the dirty victim in the cache, still readable and retryable.
fn (mut this Cache) get(context voidptr, load IO, store IO, index u64, fill bool) ?&Page {
	mut resident := this.resident_page(index)
	if resident != unsafe { nil } {
		this.unlink(mut resident)
		this.link_recent(mut resident)
		return resident
	}

	mut page := &Page(unsafe { nil })
	if this.resident >= this.capacity && this.lru_first != unsafe { nil } {
		page = this.lru_first
		page.flush(context, store) or { return none }
		this.withdraw(mut page)
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
	this.publish(mut page)
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
	mut page := this.lru_first
	for page != unsafe { nil } {
		page.flush(context, store) or { return none }
		page = page.lru_next
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
		if this.resident >= this.capacity && this.lru_first != unsafe { nil }
			&& this.lru_first.dirty {
			return
		}
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
	mut page := this.lru_first
	for page != unsafe { nil } {
		mut victim := page
		page = page.lru_next
		start := victim.index * page_bytes
		if !victim.dirty && start >= loc && start + victim.valid <= end {
			this.withdraw(mut victim)
			unsafe { free(victim) }
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
	mut page := this.lru_first
	for page != unsafe { nil } && reclaimed < budget {
		mut victim := page
		page = page.lru_next
		if victim.dirty {
			continue
		}
		this.withdraw(mut victim)
		unsafe { free(victim) }
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
	mut page := this.lru_first
	for page != unsafe { nil } {
		page.flush(context, store) or { return none }
		page = page.lru_next
	}
	page = this.lru_first
	for page != unsafe { nil } {
		next := page.lru_next
		unsafe { free(page) }
		page = next
	}
	unsafe { this.buckets.free() }
	this.buckets = []&Page{}
	this.bucket_mask = 0
	this.lru_first = unsafe { nil }
	this.lru_last = unsafe { nil }
	this.resident = 0
	this.owner = unsafe { nil }
	this.size = 0
}

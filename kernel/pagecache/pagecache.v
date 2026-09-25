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
// How far writers may run ahead of the device. Every change to an EXT2
// directory flushes the whole cache before it returns, holding the lock every
// other access to the filesystem waits for with interrupts off; with a
// download's 256 MiB of dirty pages in the cache, creating a file stopped the
// machine for minutes. Past this many, a write puts the oldest dirty pages on
// the device before it returns, so no flush has more than this to do.
pub const dirty_limit = 1024
// Consecutive dirty pages go to the device together, up to this many to a
// request, and a store callback must take that much. A request is a
// synchronous round trip, which under QEMU costs milliseconds almost whatever
// its size: page by page, writing back the dirty limit took seconds.
pub const max_run_pages = u64(32)
pub const willneed = 3
pub const dontneed = 4

pub type IO = fn (voidptr, voidptr, u64, u64) ?i64

struct Page {
mut:
	index u64
	valid u64
	dirty bool
	// Set while sync writes a copy of the page with the lock dropped. Until the
	// write lands the page cannot be evicted, discarded or freed, and nothing
	// else may write it: an older copy landing after a newer one would leave
	// the disk behind the cache.
	writeback bool
	// Dirty pages are also on a list of their own, oldest first, so that
	// writing some back does not mean searching every resident page for them.
	dirty_previous &Page = unsafe { nil }
	dirty_next     &Page = unsafe { nil }
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
	dirty_first  &Page = unsafe { nil }
	dirty_last   &Page = unsafe { nil }
	dirty_pages  int
	// Held by sync across the device write of one page, and by nothing else.
	// l is free meanwhile, so reads and writes carry on; taking this turns
	// interrupts off all the same, so the writer cannot be preempted with a
	// page in flight while every CPU that could resume it waits for the page.
	writing klock.Lock
	// Where a run is gathered to be written: one for sync, used under writing,
	// and one for writers past the dirty limit, used under l. Allocated on
	// first use and kept, since every close of a file on EXT2 syncs.
	sync_run   voidptr
	behind_run voidptr
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

// Called with l held, and never for a page in flight.
fn (mut this Cache) flush_page(mut page Page, context voidptr, store IO) ? {
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
	this.mark_clean(mut page)
}

fn (mut this Cache) mark_dirty(mut page Page) {
	if page.dirty {
		return
	}
	page.dirty = true
	page.dirty_previous = this.dirty_last
	page.dirty_next = unsafe { nil }
	if this.dirty_last != unsafe { nil } {
		this.dirty_last.dirty_next = page
	} else {
		this.dirty_first = page
	}
	this.dirty_last = page
	this.dirty_pages++
}

fn (mut this Cache) mark_clean(mut page Page) {
	if !page.dirty {
		return
	}
	page.dirty = false
	if page.dirty_previous != unsafe { nil } {
		page.dirty_previous.dirty_next = page.dirty_next
	} else {
		this.dirty_first = page.dirty_next
	}
	if page.dirty_next != unsafe { nil } {
		page.dirty_next.dirty_previous = page.dirty_previous
	} else {
		this.dirty_last = page.dirty_previous
	}
	page.dirty_previous = unsafe { nil }
	page.dirty_next = unsafe { nil }
	this.dirty_pages--
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

// The page a miss would replace: the least recently used one that sync is not
// writing back. Nil only when every resident page is on its way to the device.
fn (this &Cache) victim() &Page {
	mut page := this.lru_first
	for page != unsafe { nil } && page.writeback {
		page = page.lru_next
	}
	return page
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
	// With nothing it may replace, the cache runs over its capacity by the
	// pages in flight, rather than waiting for them with the lock held.
	if this.resident >= this.capacity {
		page = this.victim()
	}
	if page != unsafe { nil } {
		this.flush_page(mut page, context, store) or { return none }
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
		this.mark_dirty(mut page)
		done += amount
	}
	this.write_behind(context, store)
	return i64(done)
}

// Called with l held. A page that will not go stays dirty for sync to report;
// one in flight is skipped, as nothing may write it until it lands.
fn (mut this Cache) write_behind(context voidptr, store IO) {
	for this.dirty_pages > dirty_limit {
		mut oldest := this.dirty_first
		for oldest != unsafe { nil } && oldest.writeback {
			oldest = oldest.dirty_next
		}
		if oldest == unsafe { nil } {
			return
		}
		if this.behind_run == unsafe { nil } {
			this.behind_run = unsafe { malloc(isize(max_run_pages * page_bytes)) }
		}
		if this.behind_run == unsafe { nil } {
			this.flush_page(mut oldest, context, store) or { return }
			continue
		}
		count := this.run_length(oldest)
		length := this.gather_run(oldest.index, count, this.behind_run)
		written := store(context, this.behind_run, oldest.index * page_bytes, length) or {
			return
		}
		if written != i64(length) {
			return
		}
		for i in 0 .. count {
			mut page := this.resident_page(oldest.index + i)
			this.mark_clean(mut page)
		}
	}
}

// Called with l held. How many consecutive pages from first on can go to the
// device with it: resident, dirty and not already on their way.
fn (this &Cache) run_length(first &Page) u64 {
	mut count := u64(1)
	for count < max_run_pages {
		next := this.resident_page(first.index + count)
		if next == unsafe { nil } || !next.dirty || next.writeback {
			break
		}
		count++
	}
	return count
}

// Called with l held. Copies a run into buffer and returns its length, which
// is short only if the run ends in the device's short last page.
fn (this &Cache) gather_run(first u64, count u64, buffer voidptr) u64 {
	mut length := u64(0)
	for i in 0 .. count {
		page := this.resident_page(first + i)
		unsafe { C.memcpy(voidptr(u64(buffer) + length), &page.data[0], page.valid) }
		length += page.valid
	}
	return length
}

// Every page dirty when sync is called is on the device when it returns. Each
// is copied with the lock held and written with it dropped. The lock is the one
// every read and write of the filesystem waits for with interrupts off, and a
// write is a synchronous device round trip: holding it across a whole system
// disk's cache, 256 MiB of pages dirtied by a large download, stopped every
// CPU that touched the disk for minutes at a time, and with them the desktop.
pub fn (mut this Cache) sync(context voidptr, store IO) ? {
	this.l.acquire()
	if this.owner == unsafe { nil } {
		this.l.release()
		return
	}
	if this.owner != context {
		this.l.release()
		errno.set(errno.einval)
		return none
	}
	// Pages dirtied after this point are the next sync's to write, so a
	// steady writer cannot keep this one going indefinitely.
	mut dirty := []u64{cap: this.dirty_pages}
	mut page := this.dirty_first
	for page != unsafe { nil } {
		dirty << page.index
		page = page.dirty_next
	}
	this.l.release()
	defer {
		unsafe { dirty.free() }
	}
	if dirty.len == 0 {
		// A page another sync has in flight looks clean, but is not on the
		// device yet. Writing a page of its own waits for it too.
		this.writing.acquire()
		this.writing.release()
		return
	}

	for index in dirty {
		this.write_back(context, store, index)?
	}
}

fn (mut this Cache) write_back(context voidptr, store IO, index u64) ? {
	this.writing.acquire()
	defer {
		this.writing.release()
	}
	this.l.acquire()
	first := this.resident_page(index)
	// A page gone was written on its way out; one found clean was written by
	// another sync, or by a writer past the dirty limit.
	if first == unsafe { nil } || !first.dirty {
		this.l.release()
		return
	}
	if this.sync_run == unsafe { nil } {
		this.sync_run = unsafe { malloc(isize(max_run_pages * page_bytes)) }
		if this.sync_run == unsafe { nil } {
			this.l.release()
			errno.set(errno.enomem)
			return none
		}
	}
	count := this.run_length(first)
	length := this.gather_run(index, count, this.sync_run)
	for i in 0 .. count {
		mut page := this.resident_page(index + i)
		page.writeback = true
		this.mark_clean(mut page)
	}
	this.l.release()

	written := store(context, this.sync_run, index * page_bytes, length) or { i64(-1) }

	this.l.acquire()
	for i in 0 .. count {
		// Still resident: nothing drops a page in flight.
		mut page := this.resident_page(index + i)
		page.writeback = false
		// A failed or short write leaves the whole run dirty for a later sync
		// to retry, including any prefix that did land. A write made to a page
		// while this was in flight has left it dirty already.
		if written != i64(length) {
			this.mark_dirty(mut page)
		}
	}
	this.l.release()
	if written != i64(length) {
		if written >= 0 {
			errno.set(errno.eio)
		}
		return none
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
		if this.resident >= this.capacity {
			victim := this.victim()
			if victim != unsafe { nil } && victim.dirty {
				return
			}
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
		if !victim.dirty && !victim.writeback && start >= loc
			&& start + victim.valid <= end {
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
		if victim.dirty || victim.writeback {
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
	// A page in flight belongs to a sync still running, which will touch it
	// again when its write lands.
	mut page := this.lru_first
	for page != unsafe { nil } {
		if page.writeback {
			errno.set(errno.ebusy)
			return none
		}
		page = page.lru_next
	}
	page = this.lru_first
	for page != unsafe { nil } {
		this.flush_page(mut page, context, store) or { return none }
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
	this.dirty_first = unsafe { nil }
	this.dirty_last = unsafe { nil }
	this.dirty_pages = 0
	if this.sync_run != unsafe { nil } {
		unsafe { free(this.sync_run) }
	}
	if this.behind_run != unsafe { nil } {
		unsafe { free(this.behind_run) }
	}
	this.sync_run = unsafe { nil }
	this.behind_run = unsafe { nil }
	this.owner = unsafe { nil }
	this.size = 0
}

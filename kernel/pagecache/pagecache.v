// A bounded backing-store page cache. The same cache must be used for every
// access to a backing resource; callbacks must bypass the cache itself.
module pagecache

import errno
import klock
import memory
import proc
import cgcontrol

pub const page_bytes = u64(4096)
pub const default_capacity = 128
// Up to 1 GiB of cached blocks, reached by a 16 GiB device. Steam's Chromium
// helper maps a library larger than the old 256 MiB limit in each subprocess;
// evicting its first pages while reading its last ones makes every new helper
// read the library from disk again.
// Growth stays bounded because the reclaimer hands clean pages back under
// memory pressure.
pub const max_capacity = u64(262144)
// How far writers may run ahead of the device. Past this many dirty pages,
// EXT2 has the writing thread flush on its way back to userspace, holding no
// lock. Every change to a directory is flushed the same way before the call
// that made it returns, and this bounds what that flush has to write.
pub const dirty_limit = 1024
// Past this many, a write puts the oldest dirty pages on the device itself,
// holding the lock: a write too large to wait for its call's end, or one made
// by a kernel thread, which has no end to wait for.
pub const dirty_ceiling = 4 * dirty_limit
// Consecutive dirty pages go to the device together, up to this many to a
// request, and a store callback must take that much. A request is a
// synchronous round trip, which under QEMU costs milliseconds almost whatever
// its size: page by page, writing back the dirty limit took seconds.
pub const max_run_pages = u64(32)
pub const willneed = 3
pub const dontneed = 4

pub type IO = fn (voidptr, voidptr, u64, u64) ?i64
pub type Flush = fn (context voidptr) ?

fn C.vinix_stack_alloc(size u64) voidptr

struct Page {
mut:
	index u64
	valid u64
	dirty bool
	io_group &cgcontrol.Group = unsafe { nil }
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
	// page_bytes of the page's contents, allocated apart; see new_data().
	data &u8 = unsafe { nil }
}

// Where a page's contents are kept. Header and contents in one allocation
// were a little over 4 KiB, more than any slab holds on a machine with 4 KiB
// pages, so each cached page took three contiguous physical pages: 12 KiB, in
// runs that left memory too broken up for any larger allocation. There the
// contents now take one page of their own; larger pages are shared.
fn new_data() &u8 {
	if page_size == page_bytes {
		physical := memory.pmm_alloc_nozero_fallible(1)
		if physical == unsafe { nil } {
			return unsafe { nil }
		}
		return unsafe { &u8(u64(physical) + higher_half) }
	}
	return unsafe { &u8(memory.malloc_packed_fallible(page_bytes)) }
}

// A page that is in no cache yet, or nil when memory has run out.
fn new_page() &Page {
	mut page := unsafe { &Page(memory.malloc_packed_fallible(sizeof(Page))) }
	if page == unsafe { nil } {
		return page
	}
	page.data = new_data()
	if page.data == unsafe { nil } {
		unsafe { free(page) }
		return unsafe { nil }
	}
	return page
}

// Free a page that has left the cache, contents and header.
fn free_page(page &Page) {
	if page.data != unsafe { nil } {
		if page_size == page_bytes {
			memory.pmm_free(voidptr(u64(page.data) - higher_half), 1)
		} else {
			unsafe { free(page.data) }
		}
	}
	unsafe { free(page) }
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
	// reboot path -- can reach the backing store and its completion barrier.
	writeback_context voidptr
	writeback         IO
	writeback_flush   Flush = unsafe { nil }
pub:
	capacity int = default_capacity
}

// A cache sized for its backing store. The default suits a small volume
// holding user data; a device the whole system runs from needs enough room for
// the inode tables and directory blocks a path walk touches, or every lookup
// evicts the metadata the next one wants. Growth is bounded because the
// reclaimer hands clean pages back under memory pressure.
pub fn new_cache(device_bytes u64) &Cache {
	mut pages := device_bytes / (64 * 1024)
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
	previous_io := proc.begin_cgroup_io(page.io_group)
	defer { proc.end_cgroup_io(previous_io) }
	ret := store(context, voidptr(page.data), page.index * page_bytes, page.valid) or {
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
	page.io_group = proc.current_cgroup_io()
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
	// Freed by release().
	this.buckets = []&Page{len: count, init: unsafe { nil }} @[freed]
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
	mut recycled := false
	// With nothing it may replace, the cache runs over its capacity by the
	// pages in flight, rather than waiting for them with the lock held.
	if this.resident >= this.capacity {
		page = this.victim()
		recycled = page != unsafe { nil }
	}
	if page == unsafe { nil } {
		page = new_page()
		if page == unsafe { nil } {
			// Out of memory, and the reclaimers cannot take this cache's
			// pages while its lock is held here: reuse one of them.
			page = this.victim()
			if page == unsafe { nil } {
				errno.set(errno.enomem)
				return none
			}
			recycled = true
		}
	}
	if recycled {
		this.flush_page(mut page, context, store) or { return none }
		this.withdraw(mut page)
	}
	data := page.data
	unsafe {
		C.memset(page, 0, sizeof(Page))
		C.memset(data, 0, page_bytes)
	}
	page.data = data
	page.index = index
	page.valid = page_bytes
	if this.size - index * page_bytes < page.valid {
		page.valid = this.size - index * page_bytes
	}
	if fill {
		ret := load(context, voidptr(page.data), index * page_bytes, page.valid) or {
			free_page(page)
			return none
		}
		if ret != i64(page.valid) {
			free_page(page)
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
		unsafe { C.memcpy(voidptr(u64(buf) + done), &page.data[offset], amount) }
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
		unsafe { C.memcpy(&page.data[offset], voidptr(u64(buf) + done), amount) }
		this.mark_dirty(mut page)
		done += amount
	}
	this.write_behind(context, store)
	return i64(done)
}

// Whether writers have run far enough ahead that one should flush. A hint:
// read without the lock.
pub fn (this &Cache) over_dirty_limit() bool {
	return this.dirty_pages > dirty_limit
}

// Called with l held. A page that will not go stays dirty for sync to report;
// one in flight is skipped, as nothing may write it until it lands.
fn (mut this Cache) write_behind(context voidptr, store IO) {
	for this.dirty_pages > dirty_ceiling {
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
		previous_io := proc.begin_cgroup_io(oldest.io_group)
		written := store(context, this.behind_run, oldest.index * page_bytes, length) or {
			proc.end_cgroup_io(previous_io)
			return
		}
		proc.end_cgroup_io(previous_io)
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
		if next == unsafe { nil } || !next.dirty || next.writeback || voidptr(next.io_group) != voidptr(first.io_group) {
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
		unsafe { C.memcpy(voidptr(u64(buffer) + length), page.data, page.valid) }
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
	mut dirty := []u64{cap: this.dirty_pages} @[freed]
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
	run_group := first.io_group
	length := this.gather_run(index, count, this.sync_run)
	for i in 0 .. count {
		mut page := this.resident_page(index + i)
		page.writeback = true
		this.mark_clean(mut page)
	}
	this.l.release()

	previous_io := proc.begin_cgroup_io(run_group)
	defer { proc.end_cgroup_io(previous_io) }
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
	// One bounded slot per invocation, outside the loop. The cache owns a
	// page only after the entire clustered transfer succeeds.
	pages := unsafe { &voidptr(C.vinix_stack_alloc(max_run_pages * sizeof(voidptr))) }
	for index <= last && budget > 0 {
		mut resident := this.resident_page(index)
		if resident != unsafe { nil } {
			this.unlink(mut resident)
			this.link_recent(mut resident)
			index++
			budget--
			continue
		}
		mut wanted := u64(1)
		for wanted < max_run_pages && wanted < u64(budget) && wanted < u64(this.capacity)
			&& wanted <= last - index && this.resident_page(index + wanted) == unsafe { nil } {
			wanted++
		}
		// Speculation can replace clean pages, but cannot initiate writeback
		// or exceed the residency bound when every victim is busy or dirty.
		for this.resident + int(wanted) > this.capacity {
			mut victim := this.victim()
			if victim == unsafe { nil } || victim.dirty {
				available := this.capacity - this.resident
				if available <= 0 { return }
				wanted = u64(available)
				break
			}
			this.withdraw(mut victim)
			free_page(victim)
		}
		buffer := memory.malloc_packed_fallible(wanted * page_bytes)
		if buffer == unsafe { nil } { return }
		mut made := u64(0)
		mut bytes := u64(0)
		for made < wanted {
			mut page := new_page()
			if page == unsafe { nil } { break }
			data := page.data
			unsafe { C.memset(page, 0, sizeof(Page)) }
			page.data = data
			page.index = index + made
			page.valid = if size - page.index * page_bytes < page_bytes {
				size - page.index * page_bytes
			} else { page_bytes }
			unsafe { pages[made] = voidptr(page) }
			bytes += page.valid
			made++
		}
		read := if made != 0 { load(context, buffer, index * page_bytes, bytes) or { i64(-1) } } else { i64(-1) }
		for slot := u64(0); slot < made; slot++ {
			mut page := unsafe { &Page(pages[slot]) }
			if read != i64(bytes) {
				free_page(page)
				continue
			}
			unsafe { C.memcpy(page.data, voidptr(u64(buffer) + slot * page_bytes), page.valid) }
			this.publish(mut page)
		}
		unsafe { free(buffer) }
		if made == 0 || read != i64(bytes) { return }
		index += made
		budget -= int(made)
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
			free_page(victim)
		}
	}
}

// A journal has already made this complete page durable. Refresh existing
// clean residency without creating dirty writeback or allocating on commit.
// The filesystem serializes all home reads against its journal checkpoint.
pub fn (mut this Cache) publish_durable(buffer voidptr, loc u64, count u64) bool {
	this.l.acquire()
	defer { this.l.release() }
	if loc % page_bytes != 0 || count != page_bytes || !valid_range(loc, count, this.size) { return false }
	mut page := this.resident_page(loc / page_bytes)
	if page == unsafe { nil } { return true }
	if page.dirty || page.writeback { return false }
	unsafe { C.memcpy(page.data, buffer, count) }
	page.valid = count
	return true
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
		free_page(victim)
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
		free_page(page)
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

module mmap

import klock
import katomic
import memory
import numa
import resource
import proc
import errno
import lib
import event

pub const prot_none = 0x00
pub const prot_read = 0x01
pub const prot_write = 0x02
pub const prot_exec = 0x04
pub const map_private = 0x02
pub const map_shared = 0x01
pub const map_fixed = 0x10
pub const map_fixed_noreplace = 0x100000
pub const map_populate = 0x8000
pub const map_anon = 0x20
pub const map_anonymous = 0x20

const prot_mask = prot_read | prot_write | prot_exec
const ms_async = 1
const ms_invalidate = 2
const ms_sync = 4

// OpenBSD-style W^X remains the default. exec permits an explicit environment
// request only through an administrator's launch or executable mount policy.
// Fork inherits that decision; each exec validates its request again.
fn validate_protection(prot int) ? {
	if prot & ~prot_mask != 0 {
		errno.set(errno.einval)
		return none
	}
	if prot & (prot_write | prot_exec) == (prot_write | prot_exec) {
		current := proc.current_thread()
		if current == unsafe { nil } || !current.process.allow_wx {
			errno.set(errno.enotsup)
			return none
		}
	}
}

// Private bookkeeping flag for the one large brk arena.  Only the committed
// portion up to brk_current is charged to RLIMIT_AS; the inaccessible reserve
// exists solely to keep unrelated mappings out of future heap addresses.
const map_brk_reservation = 0x20000000
// Asked by the caller for a shared mapping of a file opened without write
// access, which mprotect() then may not make writable; see no_write.
pub const map_no_write = 0x40000000
// Internal permission ceiling for files mapped through a noexec mount.
pub const map_no_exec = 0x10000000

// Runtimes such as JavaScriptCore reserve multi-gigabyte anonymous arenas but
// commit only a small fraction of them. Keep large reservations sparse and let
// the existing page-fault path allocate the pages that are actually touched.
const lazy_anonymous_threshold = u64(64 * 1024 * 1024)

__global (
	// Guards every global range's list of locals. A MAP_SHARED range is shared
	// by every process that fork left mapping it, and each changes the list
	// under nothing but its own page map's lock: a fork appends its child, and
	// an exec or exit in any of them removes one. Unguarded, a fork racing an
	// exec reallocated the list under the delete and corrupted the heap. Taken
	// inside a page map's lock, and only for the change itself.
	range_locals_lock klock.Lock
	// Identifies an insertion even when a slab reuses a removed local pointer.
	next_range_generation = u64(1)
)

// Resources that need uncached page table mappings (e.g., framebuffers).
// On ARM64, device memory must be Non-Cacheable so writes reach hardware.
__global (
	uncached_resources     [8]voidptr
	uncached_resources_cnt = u32(0)
)

pub fn register_uncached_resource(res voidptr) {
	if uncached_resources_cnt >= 8 {
		return
	}
	uncached_resources[uncached_resources_cnt] = res
	uncached_resources_cnt++
}

// Extract the underlying object pointer from a V interface value.
// V interfaces are stored as { _object voidptr, _interface_idx int }.
fn interface_object_ptr(iface voidptr) voidptr {
	return unsafe { *&voidptr(iface) }
}

fn is_uncached_resource(iface_ptr voidptr) bool {
	obj := interface_object_ptr(iface_ptr)
	for i := u32(0); i < uncached_resources_cnt; i++ {
		if uncached_resources[i] == obj {
			return true
		}
	}
	return false
}

pub struct MmapRangeLocal {
pub mut:
	pagemap   &memory.Pagemap = unsafe { nil }
	global    &MmapRangeGlobal = unsafe { nil }
	base      u64
	length    u64
	offset    i64
	prot      int
	flags     int
	cow       bool
	immutable bool
	// What fork(2) does with the range, set by madvise(2) and minherit(2):
	// leaves it out of the child, or gives the child an empty one.
	dont_fork    bool
	wipe_on_fork bool
	tree_left &MmapRangeLocal = unsafe { nil }
	tree_right &MmapRangeLocal = unsafe { nil }
	tree_priority u64
	list_index int
	generation u64
}

pub struct MmapRangeGlobal {
pub mut:
	// A reservation needs no physical page tables until its first page is
	// installed. top_level is created under shadow_pagemap.l at that point.
	shadow_pagemap    memory.Pagemap
	locals            []&MmapRangeLocal
	resource          &resource.Resource = unsafe { nil }
	handle            voidptr
	handle_ref        fn (voidptr) = unsafe { nil }
	handle_unref      fn (voidptr) = unsafe { nil }
	base              u64
	length            u64
	offset            i64
	pte_extra         u64 // Extra PTE flags (e.g., pte_uncached for device memory)
	owns_resource_ref bool
	owns_mapping_ref  bool
	lazy_file         bool
	segmented_file    bool
	file_data_start   u64
	file_data_length  u64
	// A shared mapping of something the mapper could only read. It may never
	// be writable: mprotect() would otherwise have let anyone who can read a
	// file write it, through a mapping made read-only. Linux clears
	// VM_MAYWRITE for the same reason.
	no_write bool
	no_exec bool
}

struct MmapOptions {
mut:
	lazy_file        bool
	segmented_file   bool
	file_data_start  u64
	file_data_length u64
	no_write         bool
	no_exec          bool
}

pub fn list_ranges(pagemap &memory.Pagemap) {
	C.printf(c'Ranges for %llx:\n', voidptr(pagemap))
	for i := u64(0); i < pagemap.mmap_ranges.len; i++ {
		r := unsafe { &MmapRangeLocal(pagemap.mmap_ranges[i]) }
		C.printf(c'                                Base: %p  Length: %p  Offset: %p\n', r.base, r.length, r.offset)
		C.printf(c'    Global: %p  Base: %p  Length: %p  Offset: %p\n', r.global, r.global.base, r.global.length, r.global.offset)
	}
}

fn addr2range(pagemap &memory.Pagemap, addr u64) ?(&MmapRangeLocal, u64, u64) {
	r := range_floor(pagemap, addr)
	if r == unsafe { nil } {
		return none
	}
	if addr >= r.base && addr < r.base + r.length {
		memory_page := addr / page_size
		file_page := u64(r.offset) / page_size + (memory_page - r.base / page_size)
		return r, memory_page, file_page
	}
	return none
}

// The address index is a treap. The separate list allows O(1) removal even
// when an allocator frees tens of thousands of ranges in creation order.
fn range_priority(base u64) u64 {
	mut x := base >> 14
	x = (x ^ (x >> 30)) * u64(0xbf58476d1ce4e5b9)
	x = (x ^ (x >> 27)) * u64(0x94d049bb133111eb)
	return x ^ (x >> 31)
}

fn rotate_range_left(mut root MmapRangeLocal) &MmapRangeLocal {
	mut next := root.tree_right
	root.tree_right = next.tree_left
	next.tree_left = root
	return next
}

fn rotate_range_right(mut root MmapRangeLocal) &MmapRangeLocal {
	mut next := root.tree_left
	root.tree_left = next.tree_right
	next.tree_right = root
	return next
}

fn range_tree_insert(_root &MmapRangeLocal, node &MmapRangeLocal) &MmapRangeLocal {
	mut root := unsafe { _root }
	if root == unsafe { nil } {
		return node
	}
	if node.base < root.base {
		root.tree_left = range_tree_insert(root.tree_left, node)
		if root.tree_left.tree_priority < root.tree_priority {
			root = rotate_range_right(mut root)
		}
	} else {
		root.tree_right = range_tree_insert(root.tree_right, node)
		if root.tree_right.tree_priority < root.tree_priority {
			root = rotate_range_left(mut root)
		}
	}
	return root
}

fn range_tree_merge(_left &MmapRangeLocal, _right &MmapRangeLocal) &MmapRangeLocal {
	mut left := unsafe { _left }
	mut right := unsafe { _right }
	if left == unsafe { nil } {
		return right
	}
	if right == unsafe { nil } {
		return left
	}
	if left.tree_priority < right.tree_priority {
		left.tree_right = range_tree_merge(left.tree_right, right)
		return left
	}
	right.tree_left = range_tree_merge(left, right.tree_left)
	return right
}

fn range_tree_remove(_root &MmapRangeLocal, node &MmapRangeLocal) &MmapRangeLocal {
	mut root := unsafe { _root }
	if root == unsafe { nil } {
		return root
	}
	if node.base < root.base {
		root.tree_left = range_tree_remove(root.tree_left, node)
	} else if node.base > root.base || voidptr(node) != voidptr(root) {
		root.tree_right = range_tree_remove(root.tree_right, node)
	} else {
		return range_tree_merge(root.tree_left, root.tree_right)
	}
	return root
}

fn range_floor(pagemap &memory.Pagemap, base u64) &MmapRangeLocal {
	mut node := unsafe { &MmapRangeLocal(pagemap.mmap_root) }
	mut found := unsafe { &MmapRangeLocal(nil) }
	for node != unsafe { nil } {
		if node.base <= base {
			found = node
			node = node.tree_right
		} else {
			node = node.tree_left
		}
	}
	return found
}

fn range_lower_bound(pagemap &memory.Pagemap, base u64) &MmapRangeLocal {
	mut node := unsafe { &MmapRangeLocal(pagemap.mmap_root) }
	mut found := unsafe { &MmapRangeLocal(nil) }
	for node != unsafe { nil } {
		if node.base >= base {
			found = node
			node = node.tree_left
		} else {
			node = node.tree_right
		}
	}
	return found
}

fn insert_range_unlocked(mut pagemap memory.Pagemap, _local &MmapRangeLocal) {
	mut local := unsafe { _local }
	local.generation = katomic.inc(mut &next_range_generation)
	local.tree_left = unsafe { nil }
	local.tree_right = unsafe { nil }
	local.tree_priority = range_priority(local.base)
	local.list_index = pagemap.mmap_ranges.len
	pagemap.mmap_ranges << voidptr(local)
	pagemap.mmap_root = range_tree_insert(unsafe { &MmapRangeLocal(pagemap.mmap_root) }, local)
}

fn remove_range_unlocked(mut pagemap memory.Pagemap, local &MmapRangeLocal) {
	pagemap.mmap_root = range_tree_remove(unsafe { &MmapRangeLocal(pagemap.mmap_root) }, local)
	index := local.list_index
	last := pagemap.mmap_ranges.len - 1
	if index != last {
		mut moved := unsafe { &MmapRangeLocal(pagemap.mmap_ranges[last]) }
		pagemap.mmap_ranges[index] = voidptr(moved)
		moved.list_index = index
	}
	pagemap.mmap_ranges.delete(last)
}

// Whether `pagemap` is the calling process' own and the process is in a
// cgroup that accounts its memory, so that its private anonymous memory is
// filled in on demand.
fn memory_accounted(process &proc.Process, pagemap &memory.Pagemap) bool {
	return unsafe { process != nil } && voidptr(process.pagemap) == voidptr(pagemap)
		&& proc.cgroup_accounts_memory(process)
}

// The anonymous memory a process actually has: the pages present in its
// anonymous mappings, private or shared. It is what cgroup memory accounting
// charges; file-backed pages are page cache, which Linux charges to whoever
// first read them, and counting them here would count every mapped binary.
// Large anonymous reservations are filled in on demand, so their length says
// little and only the pages really there are counted. A page shared with
// other processes -- after fork, until one of them writes it -- counts only
// its share, so a group of processes forked from one another counts it once,
// as Linux charges a page once.
pub fn anonymous_resident_bytes(_pagemap &memory.Pagemap) u64 {
	mut pagemap := unsafe { _pagemap }
	if pagemap == unsafe { nil } {
		return 0
	}
	// Not waiting for good on a pagemap another CPU is busy with: this runs for
	// every process of a group, and a count a moment late is fine.
	mut acquired := false
	for _ in 0 .. 100000 {
		if pagemap.l.test_and_acquire() {
			acquired = true
			break
		}
	}
	if !acquired {
		return 0
	}
	defer {
		pagemap.l.release()
	}
	mut bytes := u64(0)
	for i := 0; i < pagemap.mmap_ranges.len; i++ {
		range := unsafe { &MmapRangeLocal(pagemap.mmap_ranges[i]) }
		if unsafe { range == nil } || range.prot == prot_none || range.flags & map_anonymous == 0 {
			continue
		}
		bytes += pagemap.resident_share(range.base, range.base + range.length)
	}
	return bytes
}

// Whether `addr` lies in a MAP_SHARED mapping, whose pages are the same
// physical memory in every address space that maps them.
pub fn is_shared_address(_pagemap &memory.Pagemap, addr u64) bool {
	mut pagemap := unsafe { _pagemap }
	pagemap.l.acquire()
	defer {
		pagemap.l.release()
	}
	local_range, _, _ := addr2range(pagemap, addr) or { return false }
	return local_range.flags & map_shared != 0
}

// The caller must hold pagemap.l. MAP_FIXED_NOREPLACE and non-fixed address
// hints need this check to reserve Windows' preferred image addresses without
// destroying an existing mapping.
fn range_is_free_unlocked(pagemap &memory.Pagemap, base u64, length u64) bool {
	end := base + length
	if end < base {
		return false
	}
	previous := range_floor(pagemap, base)
	if previous != unsafe { nil } && base < previous.base + previous.length {
		return false
	}
	next := range_lower_bound(pagemap, base)
	if next != unsafe { nil } && end > next.base {
		return false
	}
	return true
}

fn overlap_length(first_base u64, first_length u64, second_base u64, second_length u64) u64 {
	first_end := first_base + first_length
	second_end := second_base + second_length
	start := if first_base > second_base { first_base } else { second_base }
	end := if first_end < second_end { first_end } else { second_end }
	return if end > start { end - start } else { 0 }
}

fn address_space_bytes_unlocked(pagemap &memory.Pagemap, process &proc.Process) u64 {
	mut total := u64(0)
	for ptr in pagemap.mmap_ranges {
		range_local := unsafe { &MmapRangeLocal(ptr) }
		mut charged := range_local.length
		if range_local.flags & map_brk_reservation != 0 {
			if process.brk_base == 0 || process.brk_current <= process.brk_base {
				charged = 0
			} else {
				charged = overlap_length(range_local.base, range_local.length, process.brk_base, lib.align_up(process.brk_current - process.brk_base, page_size))
			}
		}
		if charged > u64(-1) - total {
			return u64(-1)
		}
		total += charged
	}
	return total
}

fn charged_overlap(range_local &MmapRangeLocal, process &proc.Process, base u64, length u64) u64 {
	if range_local.flags & map_brk_reservation == 0 {
		return overlap_length(range_local.base, range_local.length, base, length)
	}
	if process.brk_base == 0 || process.brk_current <= process.brk_base {
		return 0
	}
	heap_length := lib.align_up(process.brk_current - process.brk_base, page_size)
	heap_overlap_base := if range_local.base > process.brk_base {
		range_local.base
	} else {
		process.brk_base
	}
	heap_end := if range_local.base + range_local.length < process.brk_base + heap_length {
		range_local.base + range_local.length
	} else {
		process.brk_base + heap_length
	}
	if heap_end <= heap_overlap_base {
		return 0
	}
	return overlap_length(heap_overlap_base, heap_end - heap_overlap_base, base, length)
}

pub fn address_space_bytes(pagemap &memory.Pagemap, process &proc.Process) u64 {
	mut locked := unsafe { pagemap }
	locked.l.acquire()
	defer { locked.l.release() }
	return address_space_bytes_unlocked(pagemap, process)
}

fn mapping_fits_address_limit(pagemap &memory.Pagemap, process &proc.Process, base u64, length u64, replacing bool, charged_length u64, credit u64) bool {
	limit := proc.soft_limit(process, proc.rlimit_as)
	if limit == proc.rlim_infinity {
		return true
	}
	mut current := address_space_bytes_unlocked(pagemap, process)
	if credit < current {
		current -= credit
	} else {
		current = 0
	}
	if replacing {
		for ptr in pagemap.mmap_ranges {
			range_local := unsafe { &MmapRangeLocal(ptr) }
			replaced := charged_overlap(range_local, process, base, length)
			if replaced < current {
				current -= replaced
			} else {
				current = 0
			}
		}
	}
	return charged_length <= limit && current <= limit - charged_length
}

// Find a hole at or above start. The guard page retained between ordinary
// allocations matches the old monotonic mmap cursor's behaviour.
fn find_free_base_unlocked(pagemap &memory.Pagemap, start u64, length u64) ?u64 {
	mut base := lib.align_up(start, page_size)
	for {
		if base + length < base {
			errno.set(errno.enomem)
			return none
		}
		mut collision := unsafe { &MmapRangeLocal(nil) }
		previous := range_floor(pagemap, base)
		if previous != unsafe { nil } && base < previous.base + previous.length {
			collision = previous
		}
		next := range_lower_bound(pagemap, base)
		if collision == unsafe { nil } && next != unsafe { nil }
			&& base + length > next.base {
			collision = next
		}
		if collision == unsafe { nil } {
			return base
		}
		if collision.base + collision.length > u64(-1) - page_size {
			errno.set(errno.enomem)
			return none
		}
		base = lib.align_up(collision.base + collision.length + page_size, page_size)
	}
	return none
}

pub fn delete_pagemap(mut pagemap memory.Pagemap) ? {
	delete_pagemap_impl(mut pagemap, false)?
}

pub fn delete_pagemap_traced(mut pagemap memory.Pagemap) ? {
	delete_pagemap_impl(mut pagemap, true)?
}

fn delete_pagemap_impl(mut pagemap memory.Pagemap, trace bool) ? {
	if trace {
		println('exec[gpu]/vm: acquiring old page-map lock')
	}
	// New inspection references are acquired under the process-table lock;
	// callers detached this map there before reaching destruction. Wait for
	// copies already resolving its pages without holding either lock.
	for {
		pagemap.l.acquire()
		if pagemap.inspection_refs == 0 {
			break
		}
		generation := event.generation(mut pagemap.inspection_drained)
		pagemap.l.release()
		mut storage := [&pagemap.inspection_drained]!
		mut drained := unsafe { event.stack_list(&storage[0], storage.len) }
		event.await_from_generation(mut drained, true, 0, generation) or {}
	}
	if trace {
		C.kprintf(c'exec[gpu]/vm: old page-map lock acquired; ranges=%lld\n', i64(pagemap.mmap_ranges.len))
	}

	// Address-space destruction is a kernel-internal operation and must be able
	// to reclaim immutable ranges after the process can no longer observe them.
	// Every caller has taken the page map off every CPU first: exit and exec
	// switch to the kernel's and have stopped the other threads, and a failed
	// fork never ran it. Retained tagged translations are invalidated first;
	// its pages then come out without TLB maintenance each.
	pagemap.prepare_tlb_teardown()
	pagemap.dying = true
	mut range_index := u64(0)
	for pagemap.mmap_ranges.len != 0 {
		local_range := unsafe { &MmapRangeLocal(pagemap.mmap_ranges[0]) }
		old_len := pagemap.mmap_ranges.len
		if trace {
			C.kprintf(c'exec[gpu]/vm: unmapping range %llu base=0x%llx len=0x%llx remaining=%lld\n',
				u64(range_index), u64(local_range.base), u64(local_range.length), i64(old_len))
		}
		munmap_unlocked_impl(mut pagemap, voidptr(local_range.base), local_range.length,
			false) or {
			if trace {
				C.kprintf(c'exec[gpu]/vm: ERROR unmapping old range %llu\n', u64(range_index))
			}
			pagemap.l.release()
			return none
		}
		if pagemap.mmap_ranges.len >= old_len {
			if trace {
				C.kprintf(c'exec[gpu]/vm: ERROR old range list did not shrink at %llu\n',
					u64(range_index))
			}
			pagemap.l.release()
			errno.set(errno.einval)
			return none
		}
		if trace {
			C.kprintf(c'exec[gpu]/vm: unmapped range %llu\n', u64(range_index))
		}
		range_index++
	}

	pagemap.release_tlb_tag()
	top_level := pagemap.top_level
	pagemap.l.release()
	if trace {
		println('exec[gpu]/vm: old page-map ranges empty; lock released')
	}

	unsafe {
		pagemap.mmap_ranges.free()
	}
	if trace {
		println('exec[gpu]/vm: old range array freed; freeing top-level table')
	}
	memory.pmm_free(top_level, 1)
	if trace {
		println('exec[gpu]/vm: old top-level table freed; freeing page-map object')
	}
	unsafe { free(pagemap) }
	if trace {
		println('exec[gpu]/vm: old page-map object freed')
	}
}

pub fn fork_pagemap(_old_pagemap &memory.Pagemap) ?&memory.Pagemap {
	memory.register_cow_resolver(resolve_cow_fault)
	register_page_in_resolver()
	mut old_pagemap := unsafe { _old_pagemap }
	mut new_pagemap := memory.new_pagemap()
	// Sized for every range up front: grown one push at a time, each array
	// lost the blocks it outgrew.
	mut old_private_globals := []voidptr{cap: old_pagemap.mmap_ranges.len} @[freed]
	mut new_private_globals := []&MmapRangeGlobal{cap: old_pagemap.mmap_ranges.len} @[freed]
	defer {
		unsafe {
			old_private_globals.free()
			new_private_globals.free()
		}
	}

	old_pagemap.l.acquire()
	defer {
		old_pagemap.l.release()
	}

	for ptr in old_pagemap.mmap_ranges {
		mut local_range := unsafe { &MmapRangeLocal(ptr) }
		mut global_range := local_range.global

		// MADV_DONTFORK, minherit(MAP_INHERIT_NONE): not the child's at all.
		if local_range.dont_fork {
			continue
		}

		mut new_local_range := &MmapRangeLocal{
			pagemap: unsafe { nil }
			global: unsafe { nil }
		}
		unsafe {
			*new_local_range = *local_range
		}
		new_local_range.pagemap = new_pagemap

		// MADV_WIPEONFORK, minherit(MAP_INHERIT_ZERO): the child gets the
		// range empty, to fill with zero pages as it touches them, and none
		// of what the parent kept there: a random generator's state, a key.
		if local_range.wipe_on_fork {
			new_local_range.cow = false
			new_local_range.offset = 0
			mut empty_global := &MmapRangeGlobal{
				locals: []&MmapRangeLocal{}
				base: local_range.base
				length: local_range.length
				shadow_pagemap: memory.Pagemap{
					top_level: unsafe { &u64(0) }
				}
			}
			empty_global.shadow_pagemap.top_level = &u64(memory.pmm_alloc(1))
			new_local_range.global = empty_global
			empty_global.add_local(new_local_range)
			insert_range_unlocked(mut new_pagemap, new_local_range)
			continue
		}

		if local_range.flags & map_shared != 0 {
			range_locals_lock.acquire()
			global_range.add_local(new_local_range)
			range_locals_lock.release()
			// Only the pages there are: a large reservation holds few.
			range_end := local_range.base + local_range.length
			mut i := old_pagemap.next_present(local_range.base, range_end)
			for i < range_end {
				old_pte := old_pagemap.virt2pte(i, false) or { return none }
				new_pte := new_pagemap.virt2pte(i, true) or { return none }
				unsafe {
					*new_pte = *old_pte
				}
				i = old_pagemap.next_present(i + page_size, range_end)
			}
		} else {
			// Private resident pages start shared and read-only in both address
			// spaces.  Their original writable protection remains in the range;
			// the write-fault path uses it to distinguish COW from a real fault.
			local_range.cow = true
			new_local_range.cow = true
			mut new_global_range := &MmapRangeGlobal(unsafe { nil })
			global_index := old_private_globals.index(voidptr(global_range))
			if global_index >= 0 {
				new_global_range = new_private_globals[global_index]
			} else {
				new_global_range = &MmapRangeGlobal{
					resource: global_range.resource
					handle: global_range.handle
					handle_ref: global_range.handle_ref
					handle_unref: global_range.handle_unref
					base: global_range.base
					length: global_range.length
					offset: global_range.offset
					pte_extra: global_range.pte_extra
					owns_resource_ref: global_range.owns_resource_ref
					owns_mapping_ref: global_range.owns_mapping_ref
					no_write: global_range.no_write
					no_exec: global_range.no_exec
					lazy_file: global_range.lazy_file
					segmented_file: global_range.segmented_file
					file_data_start: global_range.file_data_start
					file_data_length: global_range.file_data_length
					locals: []&MmapRangeLocal{}
					shadow_pagemap: memory.Pagemap{
						top_level: unsafe { &u64(0) }
					}
				}
				new_global_range.shadow_pagemap.top_level = &u64(memory.pmm_alloc(1))
				if new_global_range.handle != unsafe { nil }
					&& new_global_range.handle_ref != unsafe { nil } {
					new_global_range.handle_ref(new_global_range.handle)
				} else if new_global_range.owns_resource_ref {
					mut retained := new_global_range.resource
					resource.retain_resource(mut retained)
				}
				if new_global_range.owns_mapping_ref {
					mut retained := new_global_range.resource
					if !resource.retain_mapping_range(mut retained, new_global_range.handle,
						u64(new_global_range.offset), new_global_range.length, local_range.flags) {
						return none
					}
				}
				old_private_globals << voidptr(global_range)
				new_private_globals << new_global_range
			}
			new_local_range.global = new_global_range
			new_global_range.add_local(new_local_range)

			// Only the pages there are: a large reservation holds few.
			range_end := local_range.base + local_range.length
			mut next := old_pagemap.next_present(local_range.base, range_end)
			for next < range_end {
				i := next
				next = old_pagemap.next_present(i + page_size, range_end)
				old_pte := old_pagemap.virt2pte(i, false) or { continue }
				if unsafe { *old_pte } & 1 == 0 {
					continue
				}
				phys := unsafe { *old_pte } & memory.pte_flags_mask
				if !memory.pmm_retain(voidptr(phys), 1) {
					return none
				}
				new_pte := new_pagemap.virt2pte(i, true) or { return none }
				new_spte := new_global_range.shadow_pagemap.virt2pte(i, true) or { return none }
				unsafe {
					*new_pte = *old_pte
					*new_spte = *new_pte
				}
				cow_flags := page_table_flags(local_range.prot, global_range.pte_extra, false)
				old_pagemap.flag_page(i, cow_flags) or { return none }
				new_pagemap.flag_page(i, cow_flags) or { return none }
			}
		}

		insert_range_unlocked(mut new_pagemap, new_local_range)
	}

	return new_pagemap
}

fn page_table_flags(prot int, extra u64, writable bool) u64 {
	mut flags := memory.pte_present | extra
	if prot != prot_none {
		flags |= memory.pte_user
	}
	if writable && prot & prot_write != 0 {
		flags |= memory.pte_writable
	}
	if prot & prot_exec == 0 {
		flags |= memory.pte_noexec
	}
	return flags
}

fn range_page_has_file_data(global &MmapRangeGlobal, virt u64) bool {
	if !global.segmented_file {
		return true
	}
	relative := virt - global.base
	data_end := global.file_data_start + global.file_data_length
	return relative < data_end && relative + page_size > global.file_data_start
}

// This does not follow a local/global range pointer: the caller may have
// dropped pagemap.l while acquiring memory and the range may have vanished.
fn acquire_anonymous_page() ?voidptr {
	// First touch decides where anonymous memory lives, respecting the
	// faulting thread's set_mempolicy/mbind policy. The allocator zeros it.
	page := numa.alloc_user_page()
	if page == unsafe { nil } {
		errno.set(errno.enomem)
		return none
	}
	return page
}

fn acquire_range_page(local &MmapRangeLocal, virt u64, file_page u64) ?voidptr {
	global := local.global
	if local.flags & map_anonymous != 0
		|| (global.segmented_file && !range_page_has_file_data(global, virt)) {
		return acquire_anonymous_page()
	}

	mut res := global.resource
	page := res.mmap(global.handle, file_page, local.flags)
	if page == unsafe { nil } {
		return none
	}
	if global.segmented_file {
		relative := virt - global.base
		data_begin := if global.file_data_start > relative {
			global.file_data_start - relative
		} else {
			u64(0)
		}
		absolute_end := global.file_data_start + global.file_data_length
		data_end := if absolute_end < relative + page_size {
			absolute_end - relative
		} else {
			page_size
		}
		if data_begin != 0 {
			unsafe { C.memset(voidptr(u64(page) + higher_half), 0, data_begin) }
		}
		if data_end < page_size {
			unsafe {
				C.memset(voidptr(u64(page) + higher_half + data_end), 0, page_size - data_end)
			}
		}
	}
	return page
}

fn release_range_page(global &MmapRangeGlobal, virt u64, file_page u64,
	physical voidptr, flags int) {
	if flags & map_anonymous != 0
		|| (global.segmented_file && !range_page_has_file_data(global, virt)) {
		memory.pmm_free(physical, 1)
		return
	}
	mut res := global.resource
	resource.release_mapping(mut res, global.handle, file_page, physical, flags)
}

// add_local records one more local range on a global one. Nothing slices the
// list, so one that grows frees the buffer it outgrew: a split of a range
// that already had two locals lost the old buffer.
fn (mut g MmapRangeGlobal) add_local(local &MmapRangeLocal) {
	g.locals.flags |= .noslices
	g.locals << unsafe { local }
}

// Split `piece` off `_local`: a new range on the same global, covering the
// low or the high end of what `_local` covers, which keeps the rest. The
// piece goes on the global's list and `_local` shrinks in one hold of
// range_locals_lock, so the pages changing hands are some local's
// throughout. Shrunk first and added after, they were no one's in between,
// and another process unmapping the same shared range then freed them under
// this one's page tables. The caller holds the page map's lock.
fn split_off_unlocked(mut pagemap memory.Pagemap, _local &MmapRangeLocal, piece &MmapRangeLocal) {
	mut local := unsafe { _local }
	mut global := local.global
	range_locals_lock.acquire()
	global.add_local(piece)
	if piece.base == local.base {
		local.offset += i64(piece.length)
		local.base += piece.length
	}
	local.length -= piece.length
	range_locals_lock.release()
	insert_range_unlocked(mut pagemap, piece)
}

pub fn map_page_in_range(_g &MmapRangeGlobal, virt_addr u64, phys_addr u64, _prot int) ? {
	mut g := unsafe { _g }

	// Shadow pagemap always gets full access (kernel tracking only)
	shadow_flags := memory.pte_present | memory.pte_writable | memory.pte_noexec
	g.shadow_pagemap.map_page(virt_addr, phys_addr, shadow_flags) or { return none }

	for i := u64(0); i < g.locals.len; i++ {
		mut l := g.locals[i]
		if virt_addr < l.base || virt_addr >= l.base + l.length {
			continue
		}
		// Shared globals may have different protections in each process. Apply
		// the local range's policy rather than the faulting caller's policy.
		pt_flags := page_table_flags(l.prot, g.pte_extra, true)
		l.pagemap.map_page(virt_addr, phys_addr, pt_flags) or { return none }
	}
}

// Install a page just obtained for `virt` unless another thread got there
// first. Faults, pre-faults and mprotect commits all drop the address-space
// lock before allocating, so two threads touching the same absent page can
// each come back with a fresh one; mapping both would let the second silently
// replace a page the first has already written to -- a Go program's heap
// metadata or a futex word vanishing into a zeroed page. The range's shadow
// pagemap decides: the first page installed there backs the address, and a
// loser gives its own page back and maps the winner's.
//
// The page is mapped only for the process that owns `local`. Another process
// sharing the range picks it up from the shadow when it touches it itself.
// Mapping it into every sharer's page tables from here meant walking the
// range's list of locals, which a fork appends to and an exec removes from --
// freeing the page map the local named -- under locks this side does not
// hold, and a fault in containerd racing its fork of a shim mapped pages
// through a freed page map.
//
// The caller looked `local` up and let the page map's lock go while it
// acquired the page. Another thread may have unmapped the range since, freeing
// it, so it is looked up again under the lock before anything of it is used;
// an address no longer mapped fails as the fault it now is.
//
// Nothing is left for the caller to release: a page that loses is released
// here, and one that wins belongs to the range.
pub fn install_range_page(mut pagemap memory.Pagemap, local &MmapRangeLocal, generation u64, virt u64, file_page u64, page voidptr, flags int) ? {
	pagemap.l.acquire()
	current, _, _ := addr2range(pagemap, virt) or {
		pagemap.l.release()
		drop_unmapped_page(page, flags)
		return none
	}
	// A split or replacement changed the range while the page was acquired.
	// A pointer match alone is insufficient: slab reuse can give a replacement
	// the old pointer. Retry against the range which now covers the address.
	if voidptr(current) != voidptr(local) || current.generation != generation {
		pagemap.l.release()
		drop_unmapped_page(page, flags)
		return
	}
	mut g := local.global
	// What giving `page` back takes, read while the range is sure to be there.
	// The giving back itself waits until the lock is let go: a shared file page
	// goes back through its filesystem, which may write it out.
	release := PageRelease{
		resource: g.resource
		handle:   g.handle
		direct:   flags & map_anonymous != 0
			|| (g.segmented_file && !range_page_has_file_data(g, virt))
	}
	shadow_flags := memory.pte_present | memory.pte_writable | memory.pte_noexec
	mut phys := u64(page)
	mut surplus := false
	g.shadow_pagemap.l.acquire()
	if g.shadow_pagemap.top_level == unsafe { nil } {
		g.shadow_pagemap.top_level = &u64(memory.pmm_alloc(1))
	}
	if existing := g.shadow_pagemap.virt2phys(virt) {
		// Another thread got the page in first; ours goes back.
		phys = existing
		surplus = true
	} else {
		g.shadow_pagemap.map_page_unlocked(virt, phys, shadow_flags) or {
			g.shadow_pagemap.l.release()
			pagemap.l.release()
			release.give_back(file_page, page, flags)
			return none
		}
	}
	g.shadow_pagemap.l.release()
	// A private page that a fork child still shares stays read-only, so that
	// the first write copies it instead of changing both processes.
	writable := !(local.cow && memory.pmm_refcount(voidptr(phys)) > 1)
	pt_flags := page_table_flags(local.prot, g.pte_extra, writable)
	mut mapped := true
	pagemap.map_page_unlocked(virt, phys, pt_flags) or { mapped = false }
	pagemap.l.release()
	if surplus {
		release.give_back(file_page, page, flags)
	}
	if !mapped {
		return none
	}
}

// How to give back a page a range acquired: straight to the allocator, or to
// the file it came from. See release_range_page.
struct PageRelease {
	resource &resource.Resource = unsafe { nil }
	handle   voidptr
	direct   bool
}

fn (release PageRelease) give_back(file_page u64, physical voidptr, flags int) {
	if release.direct {
		memory.pmm_free(physical, 1)
		return
	}
	mut res := release.resource
	resource.release_mapping(mut res, release.handle, file_page, physical, flags)
}

// A page acquired for a range that changed before it could be installed.
// Anonymous memory is ours to free. A file's page is a reference on a page
// cache entry, released through a range that may be gone; it is left rather
// than risk the freed range, which only a fault racing its own process'
// munmap or mprotect can cause.
fn drop_unmapped_page(page voidptr, flags int) {
	if flags & map_anonymous != 0 {
		memory.pmm_free(page, 1)
	}
}

// Resolve a write to a private page shared by fork().  A range retains its
// requested PROT_WRITE bit while its PTE is read-only, so no software-only PTE
// bit is needed and both architectures use exactly the same state machine.
pub fn resolve_cow_fault(_pagemap &memory.Pagemap, address u64) bool {
	mut pagemap := unsafe { _pagemap }
	virt := lib.align_down(address, page_size)
	pagemap.l.acquire()
	defer { pagemap.l.release() }

	mut local_range, _, _ := addr2range(pagemap, virt) or { return false }
	if !local_range.cow || local_range.flags & map_shared != 0
		|| local_range.prot & prot_write == 0 {
		return false
	}
	old_phys := pagemap.virt2phys(virt) or { return false }
	// Another thread resolved this page while we waited for the lock, and its
	// writes already go to the page mapped now. Copying that page again would
	// lose whatever they change before the new mapping reaches every CPU.
	if _ := pagemap.user_page_phys(virt, true) {
		return true
	}
	if _ := unshare_private_page_unlocked(mut pagemap, local_range, virt, old_phys, true) {
		return true
	}
	return false
}

// A kernel write to a private anonymous mapping must also break fork's
// sharing. The caller holds the pagemap lock and supplies the mapped page.
fn unshare_private_page_unlocked(mut pagemap memory.Pagemap, local_range &MmapRangeLocal, virt u64, old_phys u64, writable bool) ?u64 {
	flags := page_table_flags(local_range.prot, local_range.global.pte_extra, true)
	if memory.pmm_refcount(voidptr(old_phys)) <= 1 {
		if writable {
			pagemap.flag_page(virt, flags) or { return none }
		}
		return old_phys
	}

	// A private copy is written by, and then read by, the thread taking this
	// fault, so it belongs on that thread's node rather than next to the shared
	// page it was copied from.
	new_page := numa.alloc_user_page_nozero()
	if new_page == unsafe { nil } {
		return none
	}
	unsafe {
		C.memcpy(voidptr(u64(new_page) + higher_half), voidptr(old_phys + higher_half), page_size)
	}
	shadow_flags := memory.pte_present | memory.pte_writable | memory.pte_noexec
	local_range.global.shadow_pagemap.map_page(virt, u64(new_page), shadow_flags) or {
		memory.pmm_free(new_page, 1)
		return none
	}
	pagemap.map_page_unlocked(virt, u64(new_page), page_table_flags(local_range.prot,
		local_range.global.pte_extra, writable)) or {
		memory.pmm_free(new_page, 1)
		return none
	}
	memory.pmm_free(voidptr(old_phys), 1)
	return u64(new_page)
}

pub fn map_range(mut pagemap memory.Pagemap, _virt_addr u64, phys_addr u64, _length u64, prot int, _flags int) ? {
	validate_protection(prot)?
	flags := _flags | map_anonymous

	virt_addr := lib.align_down(_virt_addr, page_size)
	length := lib.align_up(_length + (_virt_addr - virt_addr), page_size)

	mut range_local := &MmapRangeLocal{
		pagemap: unsafe { pagemap }
		base: virt_addr
		length: length
		prot: prot
		flags: flags
		global: unsafe { nil }
	}

	mut range_global := &MmapRangeGlobal{
		locals: []&MmapRangeLocal{}
		base: virt_addr
		length: length
		resource: unsafe { nil }
		shadow_pagemap: memory.Pagemap{
			top_level: unsafe { &u64(0) }
		}
	}

	range_local.global = range_global

	range_global.add_local(range_local)
	range_global.shadow_pagemap.top_level = &u64(memory.pmm_alloc(1))

	pagemap.l.acquire()
	insert_range_unlocked(mut pagemap, range_local)
	pagemap.l.release()

	for i := u64(0); i < length; i += page_size {
		map_page_in_range(range_global, virt_addr + i, phys_addr + i, prot) or { return none }
	}
}

// map_pages creates one virtual range backed by an arbitrary list of physical
// pages. Large executable images do not require physically contiguous RAM;
// keeping one range also lets munmap/mprotect treat the mapping normally.
pub fn map_pages(mut pagemap memory.Pagemap, virt_addr u64, phys_pages []u64, prot int, _flags int) ? {
	validate_protection(prot)?
	if phys_pages.len == 0 || virt_addr != lib.align_down(virt_addr, page_size) {
		return none
	}

	flags := _flags | map_anonymous
	length := u64(phys_pages.len) * page_size
	mut range_local := &MmapRangeLocal{
		pagemap: unsafe { pagemap }
		base: virt_addr
		length: length
		prot: prot
		flags: flags
		global: unsafe { nil }
	}
	mut range_global := &MmapRangeGlobal{
		locals: []&MmapRangeLocal{}
		base: virt_addr
		length: length
		resource: unsafe { nil }
		shadow_pagemap: memory.Pagemap{
			top_level: unsafe { &u64(0) }
		}
	}

	range_local.global = range_global
	range_global.add_local(range_local)
	range_global.shadow_pagemap.top_level = &u64(memory.pmm_alloc(1))

	pagemap.l.acquire()
	insert_range_unlocked(mut pagemap, range_local)
	pagemap.l.release()

	for i, phys in phys_pages {
		map_page_in_range(range_global, virt_addr + u64(i) * page_size, phys, prot) or {
			return none
		}
	}
}

pub fn mmap(_pagemap &memory.Pagemap, addr voidptr, _length u64, prot int, flags int, _resource &resource.Resource, offset i64, handle voidptr, handle_ref fn (voidptr), handle_unref fn (voidptr)) ?voidptr {
	return mmap_with_credit(_pagemap, addr, _length, prot, flags, _resource, offset, handle, handle_ref, handle_unref, 0, MmapOptions{})
}

// Install an ELF PT_LOAD range without populating it. file_data_start is the
// in-page displacement of the segment, and bytes outside its exact file image
// are supplied as zero-filled memory when each page first faults.
pub fn mmap_file_segment(_pagemap &memory.Pagemap, addr u64, length u64, prot int,
	_res &resource.Resource, offset i64, file_data_start u64, file_data_length u64) ?voidptr {
	if file_data_start > length || file_data_length > length - file_data_start {
		errno.set(errno.einval)
		return none
	}
	return mmap_with_credit(_pagemap, voidptr(addr), length, prot, map_private | map_fixed, _res, offset, unsafe { nil }, unsafe { nil }, unsafe { nil }, 0, MmapOptions{
		lazy_file: true
		segmented_file: true
		file_data_start: file_data_start
		file_data_length: file_data_length
	})
}

// mremap builds the destination before dropping the source. Credit the bytes
// which the same operation is about to unmap so RLIMIT_AS applies to its final
// footprint instead of the harmless temporary overlap.
fn mmap_with_credit(_pagemap &memory.Pagemap, addr voidptr, _length u64, prot int,
	requested_flags int, _resource &resource.Resource, offset i64, handle voidptr,
	handle_ref fn (voidptr), handle_unref fn (voidptr), limit_credit u64,
	options MmapOptions) ?voidptr {
	mut pagemap := unsafe { _pagemap }
	mut resource_ := unsafe { _resource }
	flags := requested_flags & ~(map_no_write | map_no_exec)
	no_exec := (options.no_exec || requested_flags & map_no_exec != 0)
		&& flags & map_anonymous == 0
	if no_exec && prot & prot_exec != 0 {
		errno.set(errno.eperm)
		return none
	}
	no_write := (options.no_write || requested_flags & map_no_write != 0)
		&& flags & map_shared != 0 && flags & map_anonymous == 0
	if no_write && prot & prot_write != 0 {
		errno.set(errno.eacces)
		return none
	}

	// Every user mapping, the program's own segments included, is made here,
	// so the resolver is in place before anything can copy from one.
	register_page_in_resolver()

	validate_protection(prot)?
	if _length == 0 {
		C.printf(c'mmap: length is 0\n')
		errno.set(errno.einval)
		return none
	}
	if flags & map_anonymous == 0 && (offset < 0 || offset % i64(page_size) != 0) {
		errno.set(errno.einval)
		return none
	}

	length := lib.align_up(_length, page_size)
	fixed := flags & map_fixed != 0
	fixed_noreplace := flags & map_fixed_noreplace != 0
	user_limit := memory.user_address_limit()
	requested := u64(addr)
	if (fixed || fixed_noreplace)
		&& (requested >= user_limit || length > user_limit - requested) {
		errno.set(errno.enomem)
		return none
	}

	if flags & map_anonymous == 0 && resource_.can_mmap == false {
		errno.set(errno.enodev)
		return none
	}

	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	mut base := u64(0)
	mut hint := lib.align_down(requested, page_size)
	if !fixed && !fixed_noreplace
		&& (hint >= user_limit || length > user_limit - hint) {
		hint = 0
	}
	if (fixed || fixed_noreplace) && (u64(addr) == 0 || u64(addr) != hint) {
		errno.set(errno.einval)
		return none
	}

	mut range_local := &MmapRangeLocal{
		pagemap: pagemap
		base: base
		length: length
		offset: offset
		prot: prot
		flags: flags
		global: unsafe { nil }
	}

	// Device memory (framebuffers) needs uncached mapping on ARM64 so
	// writes reach physical RAM instead of staying in CPU cache.
	mut extra_pte := u64(0)
	if flags & map_anonymous == 0 && voidptr(resource_) != unsafe { nil }
		&& is_uncached_resource(voidptr(resource_)) {
		extra_pte = memory.pte_uncached
		// Device memory mapped with Non-Cacheable attribute
	}
	mut range_handle := voidptr(0)
	if flags & map_anonymous == 0 {
		range_handle = handle
	}
	// Device ownership and attributes must be settled before the VMA is
	// visible, without holding pagemap.l across driver/usercopy locks.
	mut mapping_retained := false
	mut resource_retained := false
	mut handle_retained := false
	mut published := false
	defer {
		if !published {
			if mapping_retained {
				resource.release_mapping_range(mut resource_, range_handle, u64(offset), length, flags)
			}
			if handle_retained {
				handle_unref(range_handle)
			} else if resource_retained {
				resource.release_resource(mut resource_)
			}
		}
	}
	if range_handle != unsafe { nil } && handle_ref != unsafe { nil } {
		handle_ref(range_handle)
		handle_retained = true
	} else if flags & map_anonymous == 0 && voidptr(resource_) != unsafe { nil } {
		resource.retain_resource(mut resource_)
		resource_retained = true
	}
	if flags & map_anonymous == 0 && voidptr(resource_) != unsafe { nil } {
		if !resource.retain_mapping_range(mut resource_, range_handle, u64(offset), length, flags) {
			unsafe { free(range_local) }
			return none
		}
		mapping_retained = true
		extra_pte |= resource.mapping_attributes(mut resource_, range_handle, u64(offset))
	}
	lazy_file := options.lazy_file || (flags & map_anonymous == 0
		&& flags & map_shared != 0 && voidptr(resource_) != unsafe { nil }
		&& resource.lazy_shared_mapping(mut resource_))

	mut range_global := &MmapRangeGlobal{
		locals: []&MmapRangeLocal{}
		base: base
		length: length
		resource: resource_
		handle: range_handle
		handle_ref: handle_ref
		handle_unref: handle_unref
		offset: offset
		pte_extra: extra_pte
		owns_mapping_ref: mapping_retained
		owns_resource_ref: resource_retained
		lazy_file: lazy_file
		segmented_file: options.segmented_file
		file_data_start: options.file_data_start
		file_data_length: options.file_data_length
		no_write: no_write
		no_exec: no_exec
		shadow_pagemap: memory.Pagemap{
			top_level: unsafe { &u64(0) }
		}
	}

	range_local.global = range_global

	range_global.add_local(range_local)

	// Choose and claim the virtual span as one locked operation. Wine first
	// probes preferred PE addresses with MAP_FIXED_NOREPLACE, while POSIX mmap
	// callers commonly pass the same addresses as best-effort hints.
	pagemap.l.acquire()
	charged_length := if flags & map_brk_reservation != 0 { u64(0) } else { length }
	if fixed_noreplace {
		base = hint
		if !range_is_free_unlocked(pagemap, base, length) {
			pagemap.l.release()
			unsafe {
				range_global.locals.free()
				free(range_global)
				free(range_local)
			}
			errno.set(errno.eexist)
			return none
		}
		if voidptr(pagemap) == voidptr(process.pagemap)
			&& !mapping_fits_address_limit(pagemap, process, base, length, false, charged_length, limit_credit) {
			pagemap.l.release()
			unsafe {
				range_global.locals.free()
				free(range_global)
				free(range_local)
			}
			errno.set(errno.enomem)
			return none
		}
	} else if fixed {
		base = u64(addr)
		if voidptr(pagemap) == voidptr(process.pagemap)
			&& !mapping_fits_address_limit(pagemap, process, base, length, true, charged_length, limit_credit) {
			pagemap.l.release()
			unsafe {
				range_global.locals.free()
				free(range_global)
				free(range_local)
			}
			errno.set(errno.enomem)
			return none
		}
		munmap_unlocked(mut pagemap, addr, length) or {
			pagemap.l.release()
			unsafe {
				range_global.locals.free()
				free(range_global)
				free(range_local)
			}
			return none
		}
	} else if hint != 0 && range_is_free_unlocked(pagemap, hint, length) {
		base = hint
	} else {
		base = find_free_base_unlocked(pagemap, process.mmap_anon_non_fixed_base, length) or {
			pagemap.l.release()
			unsafe {
				range_global.locals.free()
				free(range_global)
				free(range_local)
			}
			return none
		}
		process.mmap_anon_non_fixed_base = base + length + page_size
	}
	if !fixed && voidptr(pagemap) == voidptr(process.pagemap)
		&& !mapping_fits_address_limit(pagemap, process, base, length, false, charged_length, limit_credit) {
		pagemap.l.release()
		unsafe {
			range_global.locals.free()
			free(range_global)
			free(range_local)
		}
		errno.set(errno.enomem)
		return none
	}
	range_local.base = base
	range_global.base = base
	published = true
	insert_range_unlocked(mut pagemap, range_local)
	range_generation := range_local.generation
	pagemap.l.release()

	// Private anonymous x86 mappings are committed on first touch. Reserving
	// a short-lived span which is never touched then needs neither data pages
	// nor a separate shadow page-table hierarchy. Shared small mappings keep
	// their existing eager policy, and MAP_POPULATE explicitly commits pages.
	// ARM keeps small mappings eager: HVF cannot handle every LDP/STP data
	// abort on an absent page, so changing that policy needs separate testing.
	// Large reservations and cgroup-accounted mappings were already sparse.
	lazy_anonymous := flags & map_anonymous != 0 && flags & map_populate == 0
		&& (length >= lazy_anonymous_threshold
			|| (flags & map_shared == 0
				&& (demand_private_anonymous() || memory_accounted(process, pagemap))))
	lazy_private_file := flags & map_anonymous == 0 && flags & map_shared == 0
	// Convert movable shared-file storage before any page can be handed out,
	// including when the mapping itself will be populated on demand.
	if flags & map_anonymous == 0 && flags & map_shared != 0
		&& voidptr(resource_) != unsafe { nil } {
		reserve_length := if u64(offset) < u64(resource_.stat.size) {
			min_u64(length, u64(resource_.stat.size) - u64(offset))
		} else {
			u64(0)
		}
		if reserve_length > 0
			&& !resource.reserve_shared_mapping(mut resource_, u64(offset), reserve_length) {
			munmap(mut pagemap, voidptr(base), length) or {}
			errno.set(errno.enomem)
			return none
		}
	}
	if prot != prot_none && !lazy_anonymous && !lazy_private_file && !lazy_file {
		for i := u64(0); i < length; i += page_size {
			file_page := u64((offset + i64(i)) / i64(page_size))
			// Past the end of the file there is nothing to pre-fault, and a
			// mapping is allowed to reach there: a dynamic loader maps one span
			// over an object's segments and replaces the tail with anonymous
			// memory, and an ordinary mmap of a rounded-up length covers the
			// slack past the last page. Leave those pages unmapped -- touching
			// one is the SIGBUS POSIX asks for -- rather than making the
			// resource grow to back a page the file does not have.
			if flags & map_anonymous == 0 && u64(offset) + i >= u64(resource_.stat.size) {
				continue
			}
			page := if flags & map_anonymous != 0 {
				acquire_anonymous_page()
			} else {
				acquire_range_page(range_local, base + i, file_page)
			} or {
				munmap(mut pagemap, voidptr(base), length) or {}
				errno.set(errno.einval)
				return none
			}
			if flags & map_anonymous == 0 && page == unsafe { nil } {
				if u64(offset) + i < u64(resource_.stat.size) {
					munmap(mut pagemap, voidptr(base), length) or {}
					errno.set(errno.einval)
					return none
				}
				continue
			}
			if page != unsafe { nil } {
				// The range is already visible to the process' other threads,
				// which may fault on this very page while it is pre-faulted.
				install_range_page(mut pagemap, range_local, range_generation, base + i, file_page, page, flags) or {
					munmap(mut pagemap, voidptr(base), length) or {}
					errno.set(errno.enomem)
					return none
				}
			}
		}
	}

	return voidptr(base)
}

pub fn syscall_munmap(_ voidptr, addr voidptr, length u64) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: munmap(0x%llx, 0x%llx)\n', process.name.str, addr, length)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	// An address inside a page is refused, as Linux refuses it, rather than
	// taken for the page around it.
	if u64(addr) % page_size != 0 {
		return errno.err, errno.einval
	}
	munmap(mut process.pagemap, addr, length) or { return errno.err, errno.get() }

	return 0, 0
}

pub fn syscall_mprotect(_ voidptr, addr voidptr, length u64, prot int) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	// Likewise. On arm64's 16 KiB pages a program written for 4 KiB ones
	// protected the second half of a page and had the whole page taken from
	// it: its next write to the first half faulted, and a SIGSEGV handler
	// that returned faulted on it again for good.
	if u64(addr) % page_size != 0 {
		return errno.err, errno.einval
	}
	mprotect(mut process.pagemap, addr, length, prot) or { return errno.err, errno.get() }

	return 0, 0
}

// Synchronize shared file mappings. Without an asynchronous writeback worker,
// MS_ASYNC is conservatively completed before return just like MS_SYNC.
pub fn syscall_msync(_ voidptr, addr u64, _length u64, flags int) (u64, u64) {
	if addr % page_size != 0 || flags & ~(ms_async | ms_invalidate | ms_sync) != 0
		|| (flags & ms_async != 0 && flags & ms_sync != 0) {
		return errno.err, errno.einval
	}
	if _length == 0 {
		return 0, 0
	}
	length := lib.align_up(_length, page_size)
	if length < _length || addr >= memory.user_address_limit()
		|| length > memory.user_address_limit() - addr {
		return errno.err, errno.enomem
	}

	mut pagemap := proc.current_thread().process.pagemap
	pagemap.l.acquire()
	defer { pagemap.l.release() }
	if immutable_overlap_unlocked(pagemap, addr, length) {
		return errno.err, errno.eperm
	}
	mut current := addr
	end := addr + length
	for current < end {
		local_range, _, _ := addr2range(pagemap, current) or {
			return errno.err, errno.enomem
		}
		range_end := if local_range.base + local_range.length < end {
			local_range.base + local_range.length
		} else {
			end
		}
		if local_range.flags & map_shared != 0
			&& local_range.flags & map_anonymous == 0 {
			mut res := local_range.global.resource
			file_offset := u64(local_range.offset) + (current - local_range.base)
			resource.sync_mapping(mut res, local_range.global.handle, file_offset, range_end - current) or { return errno.err, errno.get() }
		}
		current = range_end
	}
	return 0, 0
}

pub fn mprotect(mut pagemap memory.Pagemap, addr voidptr, len u64, prot int) ? {
	validate_protection(prot)?
	if len == 0 {
		errno.set(errno.einval)
		return none
	}
	length := lib.align_up(len, page_size)
	if length < len || u64(addr) > u64(-1) - length {
		errno.set(errno.einval)
		return none
	}

	// Preflight before populating sparse pages. Otherwise a denied protection
	// change could still allocate physical memory inside an immutable range.
	pagemap.l.acquire()
	if immutable_overlap_unlocked(pagemap, u64(addr), length) {
		pagemap.l.release()
		errno.set(errno.eperm)
		return none
	}
	if prot & prot_exec != 0 && no_exec_overlap_unlocked(pagemap, u64(addr), length) {
		pagemap.l.release()
		errno.set(errno.eacces)
		return none
	}
	if prot & prot_write != 0 && no_write_overlap_unlocked(pagemap, u64(addr), length) {
		pagemap.l.release()
		errno.set(errno.eacces)
		return none
	}
	pagemap.l.release()

	// mmap() deliberately leaves PROT_NONE reservations without physical pages.
	// ARM64 HVF cannot reliably resume every paired load/store page fault, so
	// populate pages here, before an application can touch a newly accessible
	// part of the reservation. A process in a cgroup is left to fault them in
	// instead, as mmap() leaves it to (see there).
	if prot != prot_none && !memory_accounted(proc.current_thread().process, &pagemap) {
		populate_missing_pages(mut pagemap, u64(addr), len, prot, true)?
	}

	pagemap.l.acquire()
	defer {
		pagemap.l.release()
	}

	mprotect_unlocked(mut pagemap, addr, len, prot)?
}

// Fill in the pages of [address, address + length) a range has no page for
// yet, in an address space that need not be the active one: exec writes a
// program's first stack through it.
pub fn populate(mut pagemap memory.Pagemap, address u64, length u64) ? {
	populate_missing_pages(mut pagemap, address, length, prot_read | prot_write, false)?
}

fn populate_missing_pages(mut pagemap memory.Pagemap, address u64, _length u64, prot int,
	skip_lazy_shared bool) ? {
	length := lib.align_up(_length, page_size)
	for virt := address; virt < address + length; virt += page_size {
		pagemap.l.acquire()
		local_range, _, file_page := addr2range(pagemap, virt) or {
			pagemap.l.release()
			errno.set(errno.enomem)
			return none
		}
		if _ := pagemap.virt2phys(virt) {
			pagemap.l.release()
			continue
		}

		flags := local_range.flags
		generation := local_range.generation
		lazy_shared := skip_lazy_shared && flags & map_shared != 0 && local_range.global.lazy_file
		pagemap.l.release()
		if lazy_shared {
			continue
		}

		page := if flags & map_anonymous != 0 {
			acquire_anonymous_page()
		} else {
			acquire_range_page(local_range, virt, file_page)
		} or {
			errno.set(errno.enomem)
			return none
		}
		install_range_page(mut pagemap, local_range, generation, virt, file_page, page, flags) or {
			errno.set(errno.enomem)
			return none
		}
	}
}

// Where the piece of `local_range` from `begin` ends: the range's end or the
// request's, whichever is first. Worked out rather than stepped to a page at
// a time, which a range of terabytes made a matter of seconds.
fn snip_end_of(local_range &MmapRangeLocal, request_end u64, begin u64) u64 {
	range_end := local_range.base + local_range.length
	end := if range_end < request_end { range_end } else { request_end }
	return if end > begin { end } else { begin + page_size }
}

// The start of the first range after `from` and before `end`, or `end`: how
// far a walk over a hole between mappings can skip. The caller holds the
// pagemap lock.
fn next_mapped_start(pagemap &memory.Pagemap, from u64, end u64) u64 {
	if from == u64(-1) {
		return end
	}
	next := range_lower_bound(pagemap, from + 1)
	if next != unsafe { nil } && next.base < end {
		return next.base
	}
	return end
}

// Successive brk() calls commit the next slice of the same reserved arena.
// Extend its existing writable local range instead of appending a new one
// for every slice. Assemblers can grow the break thousands of times; leaving
// each slice separate makes later limit and immutable-range checks scan an
// ever-growing list. The caller holds the pagemap lock and has already
// populated any pages needed by the newly accessible slice.
fn extend_brk_range_unlocked(mut pagemap memory.Pagemap, base u64, length u64, prot int) bool {
	if prot != (prot_read | prot_write) {
		return false
	}
	mut committed := unsafe { &MmapRangeLocal(nil) }
	mut reserve := unsafe { &MmapRangeLocal(nil) }
	for ptr in pagemap.mmap_ranges {
		mut local := unsafe { &MmapRangeLocal(ptr) }
		if local.flags & map_brk_reservation == 0 {
			continue
		}
		if local.base == base && local.length >= length && local.prot == prot_none {
			reserve = local
		} else if local.base + local.length == base && local.prot == prot {
			committed = local
		}
	}
	if committed == unsafe { nil } || reserve == unsafe { nil }
		|| committed.global != reserve.global || committed.flags != reserve.flags
		|| committed.cow != reserve.cow || committed.immutable != reserve.immutable
		|| committed.dont_fork != reserve.dont_fork
		|| committed.wipe_on_fork != reserve.wipe_on_fork || committed.offset + i64(committed.length) != reserve.offset {
		return false
	}

	end := base + length
	mut next_page := pagemap.next_present(base, end)
	for next_page < end {
		page := next_page
		next_page = pagemap.next_present(page + page_size, end)
		mut writable := true
		if reserve.cow {
			phys := pagemap.virt2phys(page) or { u64(0) }
			writable = phys == 0 || memory.pmm_refcount(voidptr(phys)) <= 1
		}
		pt_flags := page_table_flags(prot, reserve.global.pte_extra, writable)
		pagemap.flag_page(page, pt_flags) or {}
	}

	committed.length += length
	reserve.base = end
	reserve.length -= length
	reserve.offset += i64(length)
	return true
}

// Whether a shared mapping that may never be writable overlaps the range.
fn no_write_overlap_unlocked(pagemap &memory.Pagemap, base u64, length u64) bool {
	if length == 0 || base > u64(-1) - length {
		return false
	}
	end := base + length
	mut range_local := range_floor(pagemap, base)
	if range_local == unsafe { nil } {
		range_local = range_lower_bound(pagemap, base)
	}
	for range_local != unsafe { nil } {
		if range_local.base >= end {
			break
		}
		if range_local.global.no_write && base < range_local.base + range_local.length {
			return true
		}
		if range_local.base == u64(-1) {
			break
		}
		range_local = range_lower_bound(pagemap, range_local.base + 1)
	}
	return false
}

pub fn mprotect_unlocked(mut pagemap memory.Pagemap, addr voidptr, _length u64, prot int) ? {
	validate_protection(prot)?
	if _length == 0 {
		C.printf(c'mprotect: length is 0\n')
		errno.set(errno.einval)
		return none
	}

	length := lib.align_up(_length, page_size)
	if length < _length || u64(addr) > u64(-1) - length {
		errno.set(errno.einval)
		return none
	}
	if immutable_overlap_unlocked(pagemap, u64(addr), length) {
		errno.set(errno.eperm)
		return none
	}
	if prot & prot_exec != 0 && no_exec_overlap_unlocked(pagemap, u64(addr), length) {
		errno.set(errno.eacces)
		return none
	}
	if prot & prot_write != 0 && no_write_overlap_unlocked(pagemap, u64(addr), length) {
		errno.set(errno.eacces)
		return none
	}
	if extend_brk_range_unlocked(mut pagemap, u64(addr), length, prot) {
		return
	}

	mut i := u64(addr)
	for i < u64(addr) + length {
		mut local_range, _, _ := addr2range(pagemap, i) or {
			i = next_mapped_start(pagemap, i, u64(addr) + length)
			continue
		}

		mut global_range := local_range.global

		// A range that has the protection already is passed over whole.
		if local_range.prot == prot {
			i = snip_end_of(local_range, u64(addr) + length, i)
			continue
		}

		snip_begin := i
		i = snip_end_of(local_range, u64(addr) + length, snip_begin)
		snip_end := i
		snip_size := snip_end - snip_begin

		if snip_begin > local_range.base && snip_end < local_range.base + local_range.length {
			// Create new range for portion after snip
			mut postsplit_range := &MmapRangeLocal{
				pagemap: local_range.pagemap
				base: snip_end
				length: (local_range.base + local_range.length) - snip_end
				offset: local_range.offset + i64(snip_end - local_range.base)
				prot: local_range.prot
				flags: local_range.flags
				cow: local_range.cow
				immutable: local_range.immutable
				dont_fork: local_range.dont_fork
				wipe_on_fork: local_range.wipe_on_fork
				global: local_range.global
			}
			split_off_unlocked(mut pagemap, local_range, postsplit_range)
		}

		// Only a page that is there has a protection to change.
		mut next_page := pagemap.next_present(snip_begin, snip_end)
		for next_page < snip_end {
			j := next_page
			next_page = pagemap.next_present(j + page_size, snip_end)
			mut writable := true
			if local_range.cow && prot & prot_write != 0 {
				phys := pagemap.virt2phys(j) or { u64(0) }
				writable = phys == 0 || memory.pmm_refcount(voidptr(phys)) <= 1
			}
			pt_flags := page_table_flags(prot, global_range.pte_extra, writable)
			pagemap.flag_page(j, pt_flags) or {}
		}

		if snip_size == local_range.length {
			local_range.prot = prot
		} else {
			mut new_range := &MmapRangeLocal{
				pagemap: local_range.pagemap
				base: snip_begin
				length: snip_size
				offset: local_range.offset + i64(snip_begin - local_range.base)
				prot: prot
				flags: local_range.flags
				cow: local_range.cow
				immutable: local_range.immutable
				dont_fork: local_range.dont_fork
				wipe_on_fork: local_range.wipe_on_fork
				global: local_range.global
			}
			split_off_unlocked(mut pagemap, local_range, new_range)
		}
	}
}

pub fn munmap(mut pagemap memory.Pagemap, addr voidptr, len u64) ? {
	pagemap.l.acquire()
	defer {
		pagemap.l.release()
	}

	munmap_unlocked(mut pagemap, addr, len)?
}

pub fn munmap_unlocked(mut pagemap memory.Pagemap, addr voidptr, _length u64) ? {
	munmap_unlocked_impl(mut pagemap, addr, _length, true)?
}

// A split or a fork can keep a global range alive after one local stops
// covering a page. Its shadow mapping must not keep that page alive on its
// own. The caller holds range_locals_lock while changing the locals and
// reclaiming their newly uncovered pages, so another process cannot remove
// the last local (and destroy the global) in the middle of the walk.
fn reclaim_uncovered_shadow_pages_locked(mut global_range MmapRangeGlobal, begin u64, end u64,
	flags int) {
	// There are no pages to reclaim from a reservation never touched. The
	// shadow lock also serializes a sharer installing its very first page.
	global_range.shadow_pagemap.l.acquire()
	empty := global_range.shadow_pagemap.top_level == unsafe { nil }
	global_range.shadow_pagemap.l.release()
	if empty {
		return
	}
	mut cursor := begin
	for cursor < end {
		global_range.shadow_pagemap.l.acquire()
		page := global_range.shadow_pagemap.next_present(cursor, end)
		if page == end {
			global_range.shadow_pagemap.l.release()
			break
		}
		cursor = page + page_size
		mut covered := false
		for local in global_range.locals {
			if page >= local.base && page < local.base + local.length {
				covered = true
				break
			}
		}
		if covered {
			global_range.shadow_pagemap.l.release()
			continue
		}
		phys := global_range.shadow_pagemap.virt2phys(page) or {
			global_range.shadow_pagemap.l.release()
			continue
		}
		global_range.shadow_pagemap.unmap_page_unlocked(page) or {
			global_range.shadow_pagemap.l.release()
			continue
		}
		global_range.shadow_pagemap.l.release()
		file_page := u64(global_range.offset) / page_size + (page - global_range.base) / page_size
		release_range_page(global_range, page, file_page, voidptr(phys), flags)
	}
}

fn munmap_unlocked_impl(mut pagemap memory.Pagemap, addr voidptr, _length u64,
	enforce_immutable bool) ? {
	if _length == 0 {
		C.printf(c'munmap: length is 0\n')
		errno.set(errno.einval)
		return none
	}

	length := lib.align_up(_length, page_size)
	if length < _length || u64(addr) > u64(-1) - length {
		errno.set(errno.einval)
		return none
	}
	if enforce_immutable && immutable_overlap_unlocked(pagemap, u64(addr), length) {
		errno.set(errno.eperm)
		return none
	}

	mut i := u64(addr)
	for i < u64(addr) + length {
		mut local_range, _, _ := addr2range(pagemap, i) or {
			i = next_mapped_start(pagemap, i, u64(addr) + length)
			continue
		}

		mut global_range := local_range.global

		snip_begin := i
		i = snip_end_of(local_range, u64(addr) + length, snip_begin)
		snip_end := i
		snip_size := snip_end - snip_begin

		if snip_begin > local_range.base && snip_end < local_range.base + local_range.length {
			// Create new range for portion after snip
			mut postsplit_range := &MmapRangeLocal{
				pagemap: local_range.pagemap
				base: snip_end
				length: (local_range.base + local_range.length) - snip_end
				offset: local_range.offset + i64(snip_end - local_range.base)
				prot: local_range.prot
				flags: local_range.flags
				cow: local_range.cow
				immutable: local_range.immutable
				dont_fork: local_range.dont_fork
				wipe_on_fork: local_range.wipe_on_fork
				global: local_range.global
			}
			split_off_unlocked(mut pagemap, local_range, postsplit_range)
		}

		// Only the pages there are: MariaDB's 8 TiB reservation took ten
		// seconds a page at a time, and a killed container stayed a zombie
		// for as long.
		mut present := pagemap.next_present(snip_begin, snip_end)
		for present < snip_end {
			pagemap.unmap_page_unlocked(present) or {}
			present = pagemap.next_present(present + page_size, snip_end)
		}

		if snip_size == local_range.length {
			// Decided under the lock: once this is the last local, no other
			// process maps the range, so none can fork another onto it, and it
			// can be torn down after the lock is let go.
			range_locals_lock.acquire()
			last := global_range.locals.len == 1
			if !last {
				global_range.locals.delete(global_range.locals.index(local_range))
				reclaim_uncovered_shadow_pages_locked(mut global_range, snip_begin, snip_end,
					local_range.flags)
			}
			range_locals_lock.release()
			if last {
				global_end := global_range.base + global_range.length
				mut next_shadow := if global_range.shadow_pagemap.top_level == unsafe { nil } {
					global_end
				} else {
					global_range.shadow_pagemap.next_present(global_range.base, global_end)
				}
				for next_shadow < global_end {
					j := next_shadow
					next_shadow = global_range.shadow_pagemap.next_present(j + page_size, global_end)
					phys := global_range.shadow_pagemap.virt2phys(j) or { continue }
					global_range.shadow_pagemap.unmap_page(j) or {
						errno.set(errno.einval)
						return none
					}
					file_page := u64(global_range.offset) / page_size + (j - global_range.base) / page_size
					release_range_page(global_range, j, file_page, voidptr(phys), local_range.flags)
				}
				if global_range.shadow_pagemap.top_level != unsafe { nil } {
					memory.pmm_free(global_range.shadow_pagemap.top_level, 1)
				}
				if global_range.owns_mapping_ref {
					mut retained := global_range.resource
					resource.release_mapping_range(mut retained, global_range.handle,
						u64(global_range.offset), global_range.length, local_range.flags)
				}
				if global_range.handle != unsafe { nil }
					&& global_range.handle_unref != unsafe { nil } {
					global_range.handle_unref(global_range.handle)
				} else if global_range.owns_resource_ref {
					mut retained := global_range.resource
					resource.release_resource(mut retained)
				}
				unsafe {
					global_range.locals.free()
					free(global_range)
				}
			}
			remove_range_unlocked(mut pagemap, local_range)
			unsafe { free(local_range) }
		} else {
			range_locals_lock.acquire()
			if snip_begin == local_range.base {
				local_range.offset += i64(snip_size)
				local_range.base = snip_end
			}
			local_range.length -= snip_size
			reclaim_uncovered_shadow_pages_locked(mut global_range, snip_begin, snip_end,
				local_range.flags)
			range_locals_lock.release()
		}
	}
}

fn min_u64(a u64, b u64) u64 {
	return if a < b { a } else { b }
}

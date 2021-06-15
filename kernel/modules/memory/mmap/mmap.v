module mmap

import memory
import resource
import sched

const pte_present  = u64(1 << 0)
const pte_writable = u64(1 << 1)
const pte_user     = u64(1 << 2)

pub const prot_none  = 0x00
pub const prot_read  = 0x01
pub const prot_write = 0x02
pub const prot_exec  = 0x04

pub const map_private   = 0x01
pub const map_shared    = 0x02
pub const map_fixed     = 0x04
pub const map_anon      = 0x08
pub const map_anonymous = 0x08

pub struct MmapRangeLocal {
pub mut:
	pagemap &memory.Pagemap
	global  &MmapRangeGlobal
	base    u64
	length  u64
	offset  i64
	prot    int
	flags   int
}

pub struct MmapRangeGlobal {
pub mut:
	shadow_pagemap &memory.Pagemap
	locals         []&MmapRangeLocal
	resource       &resource.Resource
	base           u64
	length         u64
	offset         i64
}

pub fn mmap(_pagemap &memory.Pagemap, addr voidptr, length u64,
			prot int, flags int, _resource &resource.Resource, offset i64) voidptr {
	mut pagemap  := unsafe { _pagemap }
	mut resource := unsafe { _resource }

	if length & page_size != 0 || length == 0 {
		print('mmap: length is not a multiple of page size or is 0\n')
		//errno = einval
		return voidptr(-1)
	}

	mut current_thread := sched.current_thread()
	mut process := current_thread.process

	mut base := u64(0)
	if flags & map_fixed != 0 {
		base = addr
	} else {
		base = process.mmap_anon_non_fixed_base
		process.mmap_anon_non_fixed_base += length + page_size
	}

	pool := unsafe { C.malloc(sizeof(MmapRangeLocal) + sizeof(MmapRangeGlobal)) }
	mut range_local  := unsafe { &MmapRangeLocal(pool) }
	mut range_global := unsafe { &MmapRangeGlobal(u64(pool) + sizeof(MmapRangeLocal)) }

	range_local.pagemap = pagemap
	range_local.global  = range_global
	range_local.base    = base
	range_local.length  = length
	range_local.offset  = offset
	range_local.prot    = prot
	range_local.flags   = flags

	range_global.locals = []&MmapRangeLocal{}
	range_global.locals << range_local
	range_global.base     = base
	range_global.length   = length
	range_global.resource = resource
	range_global.offset   = offset

	range_global.shadow_pagemap.top_level = &u64(memory.pmm_alloc(1))

	pagemap.l.acquire()
	pagemap.mmap_ranges << voidptr(range_local)
	pagemap.l.release()

	if voidptr(resource) != 0 {
		resource.refcount++
	}

	return voidptr(base)
}

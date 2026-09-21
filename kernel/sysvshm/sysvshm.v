// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
@[has_globals]
module sysvshm

// Linux System V shared memory.  glibc compatibility programs still use this
// interface for small, process-shared transports (Sublime Text's plugin host
// is one example), even when most of their mappings use mmap(2).

import errno
import fs
import klock
import memory.mmap
import proc
import resource
import usercopy

const ipc_private = i32(0)
const ipc_creat = 0o1000
const ipc_excl = 0o2000

const ipc_rmid = 0
const ipc_set = 1
const ipc_stat = 2

const shm_rdonly = 0o10000
const shm_rnd = 0o20000
const shm_remap = 0o40000
const shm_exec = 0o100000

// Keep bogus requests from pinning all RAM.  This is deliberately a per-
// segment limit; Vinix does not yet expose the Linux SHM_INFO tuning knobs.
const shm_segment_max = u64(1024 * 1024 * 1024)

@[packed]
struct Ipc64Perm {
mut:
	key     i32
	uid     u32
	gid     u32
	cuid    u32
	cgid    u32
	mode    u32
	seq     u16
	pad2    u16
	pad3    u32
	unused1 u64
	unused2 u64
}

// asm-generic's arm64 shmid64_ds layout (112 bytes).
@[packed]
struct Shmid64Ds {
mut:
	perm    Ipc64Perm
	segsz   u64
	atime   i64
	dtime   i64
	ctime   i64
	cpid    i32
	lpid    i32
	nattch  u64
	unused4 u64
	unused5 u64
}

@[heap]
struct Segment {
mut:
	id          int
	key         i32
	mode        u32
	uid         u32
	gid         u32
	cuid        u32
	cgid        u32
	size        u64
	creator_pid int
	last_pid    int
	attachments u64
	operations  u64
	removed     bool
	backing     &resource.Resource = unsafe { nil }
}

__global (
	segments      = []&Segment{}
	segments_lock klock.Lock
	next_id       = int(1)
)

fn find_id_unlocked(id int) &Segment {
	for segment in segments {
		if segment.id == id {
			return segment
		}
	}
	return unsafe { nil }
}

fn find_key_unlocked(key i32) &Segment {
	for segment in segments {
		if !segment.removed && segment.key == key {
			return segment
		}
	}
	return unsafe { nil }
}

fn find_handle_unlocked(handle voidptr) &Segment {
	for segment in segments {
		if voidptr(segment) == handle {
			return segment
		}
	}
	return unsafe { nil }
}

fn destroy_unlocked(segment &Segment) {
	index := segments.index(segment)
	if index >= 0 {
		segments.delete(index)
	}
	mut backing := segment.backing
	backing.unref(unsafe { nil }) or {}
	unsafe { free(segment) }
}

fn finish_operation_unlocked(_segment &Segment) {
	mut segment := unsafe { _segment }
	if segment.operations != 0 {
		segment.operations--
	}
	if segment.removed && segment.attachments == 0 && segment.operations == 0 {
		destroy_unlocked(segment)
	}
}

fn retain_mapping(handle voidptr) {
	if handle == unsafe { nil } {
		return
	}
	mut segment := unsafe { &Segment(handle) }
	segments_lock.acquire()
	segment.attachments++
	segment.last_pid = proc.current_thread().process.pid
	segments_lock.release()
}

fn release_mapping(handle voidptr) {
	if handle == unsafe { nil } {
		return
	}
	mut segment := unsafe { &Segment(handle) }
	segments_lock.acquire()
	if segment.attachments != 0 {
		segment.attachments--
	}
	segment.last_pid = proc.current_thread().process.pid
	if segment.removed && segment.attachments == 0 && segment.operations == 0 {
		destroy_unlocked(segment)
	}
	segments_lock.release()
}

pub fn syscall_shmget(_ voidptr, key i32, size u64, flags int) (u64, u64) {
	segments_lock.acquire()

	if key != ipc_private {
		existing := find_key_unlocked(key)
		if existing != unsafe { nil } {
			if flags & ipc_creat != 0 && flags & ipc_excl != 0 {
				segments_lock.release()
				return errno.err, errno.eexist
			}
			if size > existing.size {
				segments_lock.release()
				return errno.err, errno.einval
			}
			id := existing.id
			segments_lock.release()
			return u64(id), 0
		}
		if flags & ipc_creat == 0 {
			segments_lock.release()
			return errno.err, errno.enoent
		}
	}

	if size == 0 || size > shm_segment_max {
		segments_lock.release()
		return errno.err, errno.einval
	}

	mut backing := fs.create_anonymous(u32(flags & 0o777))
	backing.grow(unsafe { nil }, size) or {
		backing.unref(unsafe { nil }) or {}
		segments_lock.release()
		return errno.err, errno.enomem
	}

	mut process := proc.current_thread().process
	id := next_id
	next_id++
	mut segment := &Segment{
		id: id
		key: key
		mode: u32(flags & 0o777)
		uid: process.euid
		gid: process.egid
		cuid: process.euid
		cgid: process.egid
		size: size
		creator_pid: process.pid
		last_pid: process.pid
		backing: backing
	}
	segments << segment
	segments_lock.release()
	return u64(id), 0
}

pub fn syscall_shmat(_ voidptr, shmid int, requested_address u64, flags int) (u64, u64) {
	if flags & ~(shm_rdonly | shm_rnd | shm_remap | shm_exec) != 0 {
		return errno.err, errno.einval
	}

	mut address := requested_address
	if address != 0 {
		if flags & shm_rnd != 0 {
			address &= ~(page_size - 1)
		} else if address & (page_size - 1) != 0 {
			return errno.err, errno.einval
		}
	}

	segments_lock.acquire()
	mut segment := find_id_unlocked(shmid)
	// Linux keeps an IPC_RMID segment addressable by id until its final
	// detach. Xorg relies on this ordering: a client marks its MIT-SHM segment
	// for deletion before the server attaches to it.
	if segment == unsafe { nil } {
		segments_lock.release()
		return errno.err, errno.einval
	}
	// Keep IPC_RMID from reclaiming the segment between lookup and mmap's
	// mapping-retain callback.
	segment.operations++
	segments_lock.release()

	mut process := proc.current_thread().process
	mut prot := mmap.prot_read
	if flags & shm_rdonly == 0 {
		prot |= mmap.prot_write
	}
	if flags & shm_exec != 0 {
		prot |= mmap.prot_exec
	}
	mut map_flags := mmap.map_shared
	if address != 0 {
		if flags & shm_remap != 0 {
			map_flags |= mmap.map_fixed
		} else {
			map_flags |= mmap.map_fixed_noreplace
		}
	}

	result := mmap.mmap(process.pagemap, voidptr(address), segment.size, prot, map_flags, segment.backing, 0, voidptr(segment), retain_mapping, release_mapping) or {
		segments_lock.acquire()
		finish_operation_unlocked(segment)
		segments_lock.release()
		return errno.err, errno.get()
	}

	segments_lock.acquire()
	finish_operation_unlocked(segment)
	segments_lock.release()
	return u64(result), 0
}

pub fn syscall_shmdt(_ voidptr, address u64) (u64, u64) {
	if address == 0 || address & (page_size - 1) != 0 {
		return errno.err, errno.einval
	}

	mut process := proc.current_thread().process
	mut handle := voidptr(0)
	mut base := u64(0)
	mut length := u64(0)
	process.pagemap.l.acquire()
	for pointer in process.pagemap.mmap_ranges {
		range_local := unsafe { &mmap.MmapRangeLocal(pointer) }
		if range_local.global.base == address {
			handle = range_local.global.handle
			base = range_local.global.base
			length = range_local.global.length
			break
		}
	}
	process.pagemap.l.release()

	if handle == unsafe { nil } {
		return errno.err, errno.einval
	}
	segments_lock.acquire()
	valid := find_handle_unlocked(handle) != unsafe { nil }
	segments_lock.release()
	if !valid {
		return errno.err, errno.einval
	}

	mmap.munmap(mut process.pagemap, voidptr(base), length) or {
		return errno.err, errno.get()
	}
	return 0, 0
}

pub fn syscall_shmctl(_ voidptr, shmid int, command int, buffer u64) (u64, u64) {
	segments_lock.acquire()
	mut segment := find_id_unlocked(shmid)
	if segment == unsafe { nil } {
		segments_lock.release()
		return errno.err, errno.einval
	}

	match command {
		ipc_rmid {
			segment.removed = true
			if segment.attachments == 0 && segment.operations == 0 {
				destroy_unlocked(segment)
			}
			segments_lock.release()
			return 0, 0
		}
		ipc_stat {
			if buffer == 0 {
				segments_lock.release()
				return errno.err, errno.efault
			}
			info := Shmid64Ds{
				perm: Ipc64Perm{
					key: segment.key
					uid: segment.uid
					gid: segment.gid
					cuid: segment.cuid
					cgid: segment.cgid
					mode: segment.mode
				}
				segsz: segment.size
				cpid: i32(segment.creator_pid)
				lpid: i32(segment.last_pid)
				nattch: segment.attachments
			}
			segments_lock.release()
			if !usercopy.copy_to_user(buffer, voidptr(&info), sizeof(Shmid64Ds)) {
				return errno.err, errno.efault
			}
			return 0, 0
		}
		ipc_set {
			if buffer == 0 {
				segments_lock.release()
				return errno.err, errno.efault
			}
			mut info := Shmid64Ds{}
			// Do not hold the global spinlock while walking user page tables.
			segment.operations++
			segments_lock.release()
			if !usercopy.copy_from_user(voidptr(&info), buffer, sizeof(Shmid64Ds)) {
				segments_lock.acquire()
				finish_operation_unlocked(segment)
				segments_lock.release()
				return errno.err, errno.efault
			}
			segments_lock.acquire()
			segment.uid = info.perm.uid
			segment.gid = info.perm.gid
			segment.mode = (segment.mode & ~u32(0o777)) | (info.perm.mode & 0o777)
			finish_operation_unlocked(segment)
			segments_lock.release()
			return 0, 0
		}
		else {
			segments_lock.release()
			return errno.err, errno.einval
		}
	}
}

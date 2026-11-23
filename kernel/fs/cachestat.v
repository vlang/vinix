// SPDX-License-Identifier: GPL-2.0-or-later
module fs

import errno
import file
import proc
import resource
import sched
import stat
import usercopy

struct CacheStatRange {
	offset u64
	length u64
}

struct CacheStat {
mut:
	cached           u64
	dirty            u64
	writeback        u64
	evicted          u64
	recently_evicted u64
}

const cachestat_scan_batch = u64(512)

pub fn syscall_cachestat(_ voidptr, fdnum u32, range_ptr u64, result_ptr u64, flags u32) (u64, u64) {
	mut fd := file.fd_from_fdnum(unsafe { nil }, int(i32(fdnum))) or { return errno.err, errno.ebadf }
	defer { fd.unref() }
	mut handle := fd.handle
	if handle.flags & resource.o_path != 0 {
		return errno.err, errno.ebadf
	}
	mut query := CacheStatRange{}
	if !usercopy.copy_from_user(unsafe { &query }, range_ptr, sizeof(CacheStatRange)) {
		return errno.err, errno.efault
	}
	handle.mac_check(proc.mac_inspect) or { return errno.err, errno.get() }
	mut res := handle.resource
	// Linux restricts this cache observation to owners, callers with a
	// writable description, or callers with current inode write permission.
	access := handle.flags & resource.o_accmode
	if access != resource.o_rdwr && access != resource.o_wronly && !owns_resource(res.stat.uid) {
		node := unsafe { &VFSNode(handle.node) }
		handle.mac_check(proc.mac_write) or { return errno.err, errno.eperm }
		check_access_on_resource(node, res, access_write, true) or { return errno.err, errno.eperm }
	}
	if flags != 0 {
		return errno.err, errno.einval
	}
	mut result := CacheStat{}
	if mut res is TmpFSResource {
		if stat.isreg(res.stat.mode) {
			first := query.offset / page_size
			last := if query.length == 0 { u64(-1) } else { (query.offset + query.length - 1) / page_size }
			result.cached = res.cached_file_pages(first, last)
		}
	} else if !cacheless_resource(res) {
		// Block-cache entries are keyed by the device, not by the inode
		// and file offset. They cannot supply this file's cache counts.
		return errno.err, errno.eopnotsupp
	}
	if !usercopy.copy_to_user(result_ptr, unsafe { &result }, sizeof(CacheStat)) {
		return errno.err, errno.efault
	}
	return 0, 0
}

fn cacheless_resource(res &resource.Resource) bool {
	mode := res.stat.mode
	return stat.ischr(mode) || stat.isifo(mode) || stat.issock(mode) || mode & stat.ifmt == stat.ifpipe
		|| res is ProcFSResource || res is SysFSResource || res is DevTmpFSResource
}

fn (mut this TmpFSResource) cached_file_pages(first u64, last u64) u64 {
	this.l.acquire()
	defer { this.l.release() }
	size := u64(this.stat.size)
	if size == 0 || first > last || first > (size - 1) / page_size {
		return 0
	}
	file_end := (size - 1) / page_size + 1
	end := if last >= file_end { file_end } else { last + 1 }
	if !this.paged {
		// Small files store their data in a resident buffer. The initramfs
		// can also supply a larger, permanently resident borrowed buffer.
		return if this.storage == unsafe { nil } { u64(0) } else { end - first }
	}
	page_end := if end < u64(this.pages.len) { end } else { u64(this.pages.len) }
	mut cached := u64(0)
	mut page := first
	for page < page_end {
		stop := if page_end - page > cachestat_scan_batch { page + cachestat_scan_batch } else { page_end }
		for page < stop {
			if this.pages[int(page)] != 0 {
				cached++
			}
			page++
		}
		if page < page_end {
			// Allow writers and other tasks to run between batches. Only the
			// index is retained: a writer may replace the page vector.
			this.l.release()
			sched.yield(true)
			this.l.acquire()
		}
	}
	return cached
}

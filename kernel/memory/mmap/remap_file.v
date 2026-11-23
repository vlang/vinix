// SPDX-License-Identifier: GPL-2.0-or-later
module mmap

import errno
import lib
import memory
import proc
import stat

const map_nonblock = u64(0x10000)
const max_file_mapping_size = u64(0x7fffffffffffffff)

struct FileRemapSource {
	serial       u64
	locked       bool
	sealed       bool
	immutable    bool
	dont_fork    bool
	wipe_on_fork bool
	populate     bool
}

// Linux implements the legacy syscall as a new fixed shared mapping of the
// original open description with a different file offset.
pub fn syscall_remap_file_pages(_ voidptr, address u64, size u64, requested_prot u64,
	file_page u64, flags u64) (u64, u64) {
	base := lib.align_down(address, page_size)
	length := lib.align_down(size, page_size)
	if requested_prot != 0 || length == 0 || base > u64(-1) - length
		|| file_page > u64(-1) - length / page_size {
		return errno.err, errno.einval
	}
	mut pagemap := proc.current_thread().process.pagemap
	begin_mapping_update(mut pagemap) or { return errno.err, errno.get() }
	defer { end_mapping_update(mut pagemap) }
	pagemap.l.acquire()
	source, _, _ := addr2range(pagemap, base) or {
		pagemap.l.release()
		return errno.err, errno.einval
	}
	global := source.global
	res := global.resource
	if source.flags & (map_shared | map_anonymous | map_read_only_handle) != map_shared
		|| global.handle == unsafe { nil } || global.handle_ref == unsafe { nil }
		|| global.handle_unref == unsafe { nil } || global.on_unmap != unsafe { nil }
		|| res == unsafe { nil } || !stat.isreg(res.stat.mode)
		|| !matching_file_span_unlocked(pagemap, base + length, source) {
		pagemap.l.release()
		return errno.err, errno.einval
	}
	if length > max_file_mapping_size || file_page > (max_file_mapping_size - length) / page_size {
		pagemap.l.release()
		return errno.err, errno.eoverflow
	}
	prot := source.prot
	map_flags := map_shared | map_fixed | (source.flags & map_locked)
	handle := global.handle
	handle_ref := global.handle_ref
	handle_unref := global.handle_unref
	// munmap can retire the VMA while the spinlock is dropped. Keep its
	// description alive until the fixed replacement has been revalidated.
	handle_ref(handle)
	defer { handle_unref(handle) }
	options := MmapOptions{
		lazy_file: true
		no_write: global.no_write
		no_exec: global.no_exec
		file_remap: FileRemapSource{
			serial: global.serial
			locked: map_flags & map_locked != 0
			sealed: source.sealed
			immutable: source.immutable
			dont_fork: source.dont_fork
			wipe_on_fork: source.wipe_on_fork
			populate: flags & map_nonblock == 0
		}
	}
	pagemap.l.release()
	offset := i64(file_page * page_size)
	mmap_with_credit(pagemap, voidptr(base), length, prot, map_flags, res,
		offset, handle, handle_ref, handle_unref, 0, options) or { return errno.err, errno.get() }
	return 0, 0
}

fn file_remap_matches_unlocked(pagemap &memory.Pagemap, base u64, end u64,
	prot int, options MmapOptions) bool {
	source, _, _ := addr2range(pagemap, base) or { return false }
	expected := options.file_remap
	return source.global.serial == expected.serial && source.prot == prot
		&& (source.flags & map_locked != 0) == expected.locked
		&& source.global.no_write == options.no_write && source.global.no_exec == options.no_exec
		&& source.sealed == expected.sealed && source.immutable == expected.immutable
		&& source.dont_fork == expected.dont_fork && source.wipe_on_fork == expected.wipe_on_fork
		&& matching_file_span_unlocked(pagemap, end, source)
}

fn matching_file_span_unlocked(pagemap &memory.Pagemap, end u64,
	source &MmapRangeLocal) bool {
	shared_flags := map_shared | map_anonymous | map_read_only_handle | map_locked
	mut cursor := source.base + source.length
	for cursor < end {
		part, _, _ := addr2range(pagemap, cursor) or { return false }
		if part.global.handle != source.global.handle || part.global.on_unmap != unsafe { nil }
			|| part.prot != source.prot
			|| part.flags & shared_flags != source.flags & shared_flags
			|| part.global.no_write != source.global.no_write || part.global.no_exec != source.global.no_exec
			|| part.sealed != source.sealed || part.immutable != source.immutable
			|| part.dont_fork != source.dont_fork || part.wipe_on_fork != source.wipe_on_fork {
			return false
		}
		cursor = part.base + part.length
	}
	return true
}

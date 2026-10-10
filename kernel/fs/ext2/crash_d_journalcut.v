module ext2

import limine
import kprint
import memory
import errno

fn C.alloc_track_dump(&char, u64, u64) u64

// The normal procfs report filters groups below fifty objects. Qualification
// needs singleton call sites as well when a retention measurement fails.
fn journal_test_sites() ?int {
	$if alloc_track ? {
		cap := u64(65536)
		@[freed]
		buffer := memory.malloc_packed_fallible(cap)
		if buffer == unsafe { nil } { errno.set(errno.enomem); return none }
		defer { unsafe { free(buffer) } }
		length := C.alloc_track_dump(unsafe { &char(buffer) }, cap, 1)
		kprint.journal_sites(buffer, length)
	}
	return 0
}

fn journal_test_mode() int {
	kernel := limine.kernel_file()
	if kernel == unsafe { nil } || kernel.cmdline == unsafe { nil } { return 0 }
	text := unsafe { cstring_to_vstring(kernel.cmdline) }
	prefix := 'vinix.journal_mode='
	for i in 0 .. text.len {
		if i + prefix.len > text.len { break }
		mut matches := true
		for j in 0 .. prefix.len { if text[i + j] != prefix[j] { matches = false; break } }
		if !matches { continue }
		mut result := 0
		for j := i + prefix.len; j < text.len && text[j] >= `0` && text[j] <= `9`; j++ {
			result = result * 10 + int(text[j] - `0`)
		}
		return result
	}
	return 0
}

// Only the crash qualification kernel includes this handler. The host kills
// QEMU at the marker without permitting another filesystem operation.
fn journal_test_phase(context voidptr, stage int) {
	filesystem := unsafe { &EXT2Filesystem(context) }
	if stage != filesystem.journal.cut_stage { return }
	kprint.journal_cut(stage)
	for {}
}

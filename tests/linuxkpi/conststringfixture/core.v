// SPDX-License-Identifier: GPL-2.0-only
// Independent page ownership, protected mappings and externally visible checks.
@[translated]
module conststringfixture

#include "contract.h"
@[typedef] struct C.vks_const_char {}
@[typedef] struct C.vks_const_void {}
fn C.kstrdup_const(&C.vks_const_char,u32) &C.vks_const_char
fn C.kfree_const(&C.vks_const_void)
fn C.vinix_linuxkpi_is_kernel_rodata(&C.vks_const_void) bool
fn C.vkr_kmalloc(usize,u32) voidptr
fn C.vkr_ksize(voidptr) usize
fn C.vkr_page_allocation_size(voidptr) usize
fn C.posix_memalign(&voidptr,usize,usize) i32
fn C.free(voidptr)
fn C.memset(voidptr,i32,usize) voidptr
fn C.memcpy(voidptr,voidptr,usize) voidptr
fn C.memcmp(voidptr,voidptr,usize) i32
fn C.printf(&char,...) i32
fn C.fflush(voidptr) i32
@[noreturn] fn C.exit(i32)
fn C.csh_map(usize) voidptr
fn C.csh_writable(voidptr,usize) i32
fn C.csh_readonly(voidptr,usize) i32
fn C.csh_inaccessible(voidptr,usize) i32
fn C.munmap(voidptr,usize) i32

@[cinit]
__global (
	assertions u32
	scenarios u32
	image_first usize
	image_last usize
	page_calls u32
	page_frees u32
	live_pages usize
	fail_pages bool
	sleepable bool = true
	last_reclaim bool
	page_bases [32]voidptr
	page_counts [32]usize
)

fn check(ok bool) {
	unsafe {
		assertions++
		if !ok { C.printf(c'CONST STRING failed assertion=%u scenario=%u\n',assertions,scenarios); C.fflush(nil); C.exit(86) }
	}
}
@[export:'csh_rodata_start'] pub fn rodata_start() voidptr { return unsafe { voidptr(image_first) } }
@[export:'csh_rodata_end'] pub fn rodata_end() voidptr { return unsafe { voidptr(image_last) } }
@[export:'vinix_linuxkpi_page_size'] pub fn page_size() usize { return 4096 }
@[export:'vinix_linuxkpi_may_sleep'] pub fn may_sleep() bool { return unsafe { sleepable } }
@[export:'vinix_linuxkpi_alloc_pages'] pub fn allocate(pages usize,reclaim bool) voidptr {
	unsafe {
		check(pages != 0 && (!reclaim || sleepable))
		page_calls++; last_reclaim = reclaim
		if fail_pages { return nil }
		mut base := voidptr(nil)
		check(C.posix_memalign(&base,4096,pages*4096) == 0 && base != nil)
		C.memset(base,0xa5,pages*4096)
		mut slot := 0
		for slot < 32 && page_bases[slot] != nil { slot++ }
		check(slot < 32)
		page_bases[slot] = base; page_counts[slot] = pages; live_pages += pages
		return base
	}
}
@[export:'vinix_linuxkpi_free_pages'] pub fn release(base voidptr,pages usize) {
	unsafe {
		mut slot := 0
		for slot < 32 && page_bases[slot] != base { slot++ }
		check(slot < 32 && base != nil && page_counts[slot] == pages && pages != 0)
		page_bases[slot] = nil; page_counts[slot] = 0; live_pages -= pages; page_frees++
		C.free(base)
	}
}
@[export:'vinix_linuxkpi_bug'; noreturn] pub fn bug(reason &C.vks_const_char,line i32) {
	C.printf(c'CONST STRING unexpected invariant %s:%d\n',reason,line); C.fflush(unsafe { nil }); C.exit(87)
}
fn classify(p voidptr) bool { return unsafe { C.vinix_linuxkpi_is_kernel_rodata(&C.vks_const_void(p)) } }
fn duplicate(p voidptr,flags u32) voidptr { return unsafe { voidptr(C.kstrdup_const(&C.vks_const_char(p),flags)) } }
fn free_copy(p voidptr) { unsafe { C.kfree_const(&C.vks_const_void(p)) } }
fn owned_copy(source voidptr,size usize,flags u32) voidptr {
	result := duplicate(source,flags)
	check(result != unsafe { nil } && result != source && C.vkr_ksize(result) == size && C.vkr_page_allocation_size(result) == size)
	check(C.memcmp(result,source,size) == 0)
	return result
}

fn boundaries_and_borrowing() voidptr {
	unsafe {
		mapping := C.csh_map(12288); check(usize(mapping) != usize(-1))
		image_first = usize(mapping)+4096; image_last = image_first+4096
		check(!classify(nil) && !classify(voidptr(image_first-1)) && classify(voidptr(image_first)) && classify(voidptr(image_last-1)) && !classify(voidptr(image_last)) && !classify(voidptr(usize(-1))))
		calls := page_calls; frees := page_frees
		fail_pages = true
		// The complete designated image interval is PROT_NONE: no candidate read.
		for index := 0; index < 2; index++ {
			p := voidptr(if index == 0 { image_first } else { image_last-1 })
			check(duplicate(p,u32(-1)) == p)
			free_copy(p)
		}
		check(page_calls == calls && page_frees == frees && fail_pages && live_pages == 0)
		check(duplicate(nil,3264) == nil && duplicate(nil,u32(-1)) == nil)
		free_copy(nil)
		check(page_calls == calls && page_frees == frees && fail_pages)
		fail_pages = false
		check(C.csh_writable(voidptr(image_first),4096) == 0)
		C.memcpy(voidptr(image_first),c'image-rodata',13)
		check(C.csh_readonly(voidptr(image_first),4096) == 0)
		check(duplicate(voidptr(image_first),3264) == voidptr(image_first))
		free_copy(voidptr(image_first))
		check(page_calls == calls && page_frees == frees)
		scenarios++
		return mapping
	}
}

fn ordinary_inputs() {
	unsafe {
		mut source := [u8(`a`),`b`,0,0x5a]!
		copy := owned_copy(&source[0],3,3264)
		check(last_reclaim)
		source[0] = `z`; check((&u8(copy))[0] == `a` && (&u8(copy))[2] == 0)
		free_copy(copy); check(source[0] == `z` && source[3] == 0x5a && live_pages == 0)
		mut empty := [1]u8{}
		empty_copy := owned_copy(&empty[0],1,0); check(!last_reclaim); free_copy(empty_copy)
		original := C.vkr_kmalloc(6,3264); check(original != nil)
		C.memcpy(original,c'owned',6)
		second := owned_copy(original,6,3264)
		free_copy(original); check(C.memcmp(second,c'owned',6) == 0); free_copy(second)
		check(live_pages == 0)
		sleepable = false
		atomic_copy := owned_copy(&source[0],3,3264); check(!last_reclaim); free_copy(atomic_copy)
		sleepable = true
		scenarios++
	}
}

fn readonly_outside_image() {
	unsafe {
		mapping := C.csh_map(8192); check(usize(mapping) != usize(-1) && !classify(mapping))
		check(C.csh_writable(mapping,4096) == 0)
		source := voidptr(usize(mapping)+4092)
		C.memcpy(source,c'end',4)
		check(C.csh_readonly(mapping,4096) == 0 && !classify(source))
		copy := owned_copy(source,4,3264)
		free_copy(copy)
		check(C.memcmp(source,c'end',4) == 0 && live_pages == 0 && C.munmap(mapping,8192) == 0)
		scenarios++
	}
}

fn allocation_failures_and_churn() {
	unsafe {
		mut source := [8193]u8{}
		C.memset(&source[0],`x`,8192)
		before := page_calls; frees := page_frees
		fail_pages = true
		check(duplicate(&source[0],3264) == nil && page_calls == before+1 && page_frees == frees && live_pages == 0 && fail_pages)
		check(duplicate(&source[0],u32(-1)) == nil && page_calls == before+1 && live_pages == 0 && fail_pages)
		fail_pages = false
		for index := 0; index < 256; index++ {
			copy := owned_copy(&source[0],8193,if index & 1 == 0 { u32(3264) } else { u32(0x100) })
			check(live_pages >= 3 && source[0] == `x` && source[8192] == 0)
			free_copy(copy); check(live_pages == 0)
		}
		check(page_calls == before+257 && page_frees == frees+256)
		scenarios++
	}
}

@[export:'main'] pub fn main(_argc i32,_argv &&char) i32 {
	mapping := boundaries_and_borrowing()
	ordinary_inputs(); readonly_outside_image(); allocation_failures_and_churn()
	check(C.munmap(mapping,12288) == 0 && unsafe { live_pages == 0 })
	unsafe { for slot := 0; slot < 32; slot++ { check(page_bases[slot] == nil && page_counts[slot] == 0) } }
	C.printf(c'PASS: original const strings; half-open PROT_NONE classifier, immutable identity, NULL, copied stack/owned/readonly inputs, checked OOM/GFP and exact page recovery; scenarios=%u assertions=%u live_pages=%zu\n',unsafe { scenarios },unsafe { assertions },unsafe { live_pages })
	return 0
}

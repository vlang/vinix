// SPDX-License-Identifier: GPL-2.0-only
// Independent observations of genuine native variadic calls and page ownership.
@[translated]
module kasprintffixture

import abiargs

#include "contract.h"
@[typedef]
struct C.vkf_native_va {}

@[typedef]
struct C.vks_const_char {}

@[typedef]
struct C.vks_const_void {}

@[typedef]
struct C.kph_sll {}

@[typedef]
struct C.kph_ull {}

fn C.va_start(C.vkf_native_va, &C.vks_const_char)
fn C.va_end(C.vkf_native_va)
fn C.vkf_va_parameter(C.vkf_native_va) voidptr
fn C.kvasprintf(u32, &C.vks_const_char, C.vkf_native_va) &char
fn C.kvasprintf_const(u32, &C.vks_const_char, C.vkf_native_va) &C.vks_const_char
fn C.kasprintf(u32, &C.vks_const_char, ...) &char
fn C.vkf_kvasprintf(u32, voidptr, voidptr) voidptr
fn C.vkf_kvasprintf_const(u32, voidptr, voidptr) voidptr
fn C.kfree_const(&C.vks_const_void)
fn C.vkr_ksize(voidptr) usize
fn C.vkr_page_allocation_size(voidptr) usize
fn C.vkr_format_entry(&char, usize, &char, voidptr, &u32) i32
fn C.test_taint(u32) i32
fn C.posix_memalign(&voidptr, usize, usize) i32
fn C.free(voidptr)
fn C.memset(voidptr, i32, usize) voidptr
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.strlen(&char) usize
fn C.strcmp(&char, &char) i32
fn C.printf(&char, ...) i32
fn C.fflush(voidptr) i32

@[noreturn]
fn C.exit(i32)

fn C.kph_map(usize) voidptr
fn C.kph_readonly(voidptr, usize) i32
fn C.munmap(voidptr, usize) i32
fn C.getpagesize() i32

struct VaDescriptor {
	fmt &char
	va  voidptr
}

@[cinit]
__global (
	assertions        u32
	scenarios         u32
	image_first       usize
	image_last        usize
	page_calls        u32
	page_frees        u32
	live_pages        usize
	fail_pages        bool
	sleepable         bool = true
	last_reclaim      bool
	page_bases        [32]voidptr
	page_counts       [32]usize
	call_mode         u32
	expected          &char
	expected_bytes    usize
	expected_capacity usize
	expected_identity voidptr
	expected_nil      bool
	preserved         bool
	mutation_pointer  voidptr
	mutation_data     &char
	mutation_size     usize
	expected_warning  &char
	warnings          u32
)

fn check(ok bool) {
	unsafe {
		assertions++
		if !ok {
			C.printf(c'KASPRINTF failed assertion=%u scenario=%u mode=%u\n', assertions, scenarios, call_mode)
			C.fflush(nil)
			C.exit(86)
		}
	}
}

fn text(p &char) &C.vks_const_char { return unsafe { &C.vks_const_char(p) } }

fn sll(bits i64) C.kph_sll {
	unsafe {
		mut value := C.kph_sll{}
		C.memcpy(&value, &bits, sizeof(value))
		return value
	}
}

fn ull(bits u64) C.kph_ull {
	unsafe {
		mut value := C.kph_ull{}
		C.memcpy(&value, &bits, sizeof(value))
		return value
	}
}

@[export:'kph_rodata_start']
pub fn rodata_start() voidptr {
	return unsafe { voidptr(image_first) }
}

@[export:'kph_rodata_end']
pub fn rodata_end() voidptr { return unsafe { voidptr(image_last) } }

@[export:'vinix_linuxkpi_page_size']
pub fn page_size() usize { return 4096 }

@[export:'vinix_linuxkpi_may_sleep']
pub fn may_sleep() bool { return unsafe { sleepable } }

@[export:'vinix_linuxkpi_alloc_pages']
pub fn allocate(pages usize, reclaim bool) voidptr {
	unsafe {
		check(pages != 0 && (!reclaim || sleepable))
		page_calls++
		last_reclaim = reclaim
		if fail_pages { return nil }
		mut base := voidptr(nil)
		check(C.posix_memalign(&base, 4096, pages * 4096) == 0 && base != nil)
		C.memset(base, 0xa5, pages * 4096)
		mut slot := 0
		for slot < 32 && page_bases[slot] != nil { slot++ }
		check(slot < 32)
		page_bases[slot] = base
		page_counts[slot] = pages
		live_pages += pages
		if mutation_pointer != nil {
			C.memcpy(mutation_pointer, mutation_data, mutation_size)
			mutation_pointer = nil
			mutation_data = nil
			mutation_size = 0
		}
		return base
	}
}

@[export:'vinix_linuxkpi_free_pages']
pub fn release(base voidptr, pages usize) {
	unsafe {
		mut slot := 0
		for slot < 32 && page_bases[slot] != base { slot++ }
		check(slot < 32 && base != nil && page_counts[slot] == pages && pages != 0)
		page_bases[slot] = nil
		page_counts[slot] = 0
		live_pages -= pages
		page_frees++
		C.free(base)
	}
}

@[export:'vinix_linuxkpi_bug'; noreturn]
pub fn bug(reason &C.vks_const_char, line i32) {
	C.printf(c'KASPRINTF unexpected invariant %s:%d\n', reason, line)
	C.fflush(unsafe { nil })
	C.exit(87)
}

@[export:'kph_log_entry']
pub fn log_entry(fmt &char, cursor voidptr) i32 {
	unsafe {
		mut buffer := [8192]char{}
		mut status := u32(0)
		count := C.vkr_format_entry(&buffer[0], sizeof(buffer), fmt, cursor, &status)
		check(status == 0 && expected_warning != nil && count == i32(C.strlen(expected_warning)))
		check(C.strcmp(&buffer[0], expected_warning) == 0 && C.test_taint(9) != 0)
		warnings++
		return count
	}
}

fn expect(bytes &char, length usize, capacity usize, identity voidptr, nil_result bool, keep_cursor bool) {
	unsafe {
		expected = bytes
		expected_bytes = length
		expected_capacity = capacity
		expected_identity = identity
		expected_nil = nil_result
		preserved = keep_cursor
	}
}

fn verify(result voidptr) {
	unsafe {
		if expected_nil {
			check(result == nil)
			return
		}
		check(result != nil)
		if expected_identity != nil {
			check(result == expected_identity)
		} else {
			check(C.vkr_ksize(result) == expected_capacity && C.vkr_page_allocation_size(result) == expected_capacity)
			check(expected_bytes <= expected_capacity && C.memcmp(result, expected, expected_bytes) == 0)
		}
		C.kfree_const(&C.vks_const_void(result))
		check(live_pages == 0)
	}
}

// C emits a real native ellipsis and builtin va_start/end. No slot-array model.
fn origin(flags u32, fmt &C.vks_const_char, ...) {
	unsafe {
		ap := C.vkf_native_va{}
		C.va_start(ap, fmt)
		cursor := C.vkf_va_parameter(ap)
		mut before := [4]u64{}
		C.memcpy(&before[0], cursor, abiargs.native_size())
		result := match call_mode {
			0 { voidptr(C.kvasprintf(flags, fmt, ap)) }
			1 { voidptr(C.kvasprintf_const(flags, fmt, ap)) }
			2 { C.vkf_kvasprintf(flags, voidptr(fmt), cursor) }
			else { C.vkf_kvasprintf_const(flags, voidptr(fmt), cursor) }
		}
		// Genuine public va_list has by-value pointer/struct semantics outside SysV.
		if preserved || (call_mode < 2 && C.VINIX_VA_ABI != 3) {
			check(C.memcmp(&before[0], cursor, abiargs.native_size()) == 0)
		} else {
			check(abiargs.integer(cursor) == 0x425a6719)
		}
		C.va_end(ap)
		verify(result)
	}
}

// The descriptor borrows a separate genuine compiler cursor; nested parsing
// must copy it during both allocation passes and preserve the inner caller.
fn nested_count(outer &char, fmt &C.vks_const_char, ...) {
	unsafe {
		ap := C.vkf_native_va{}
		C.va_start(ap, fmt)
		cursor := C.vkf_va_parameter(ap)
		mut before := [4]u64{}
		C.memcpy(&before[0], cursor, abiargs.native_size())
		descriptor := VaDescriptor{ fmt: &char(fmt), va: cursor }
		origin(3264, text(outer), &descriptor, u32(0x425a6719))
		check(C.memcmp(&before[0], cursor, abiargs.native_size()) == 0)
		C.va_end(ap)
	}
}

fn ordinary_and_capture() {
	unsafe {
		for mode := u32(0); mode < 4; mode++ {
			call_mode = mode
			expect(c'', 1, 1, nil, false, false)
			origin(3264, text(c''), u32(0x425a6719))
			expect(c'100%', 5, 5, nil, false, false)
			origin(3264, text(c'100%%'), u32(0x425a6719))
			mixed := &char(c'-128|255|-32768|65535|-17|18|-9223372036854775808|18446744073709551615|-19|20|-21|00000000000000ab|  abc|7|8|9')
			mixed_size := C.strlen(mixed) + 1
			expect(mixed, mixed_size, mixed_size, nil, false, false)
			origin(3264, text(c'%hhd|%hhu|%hd|%hu|%ld|%lu|%lld|%llu|%zd|%zu|%td|%px|%*.*s|%u|%u|%u'), i32(128), i32(-1), i32(-32768), i32(65535), isize(-17), usize(18), sll(i64(-9223372036854775807) - 1), ull(~u64(0)), isize(-19), usize(20), isize(-21), voidptr(0xab), i32(5), i32(3), c'abcdef', u32(7), u32(8), u32(9), u32(0x425a6719))
			expect(c'[(null)]', 9, 9, nil, false, false)
			origin(0, text(c'[%s]'), voidptr(nil), u32(0x425a6719))
			check(!last_reclaim)
			expect(c'[7/ok]', 7, 7, nil, false, false)
			nested_count(c'[%pV]', text(c'%u/%s'), u32(7), c'ok')
			scenarios++
		}
		call_mode = 4
		expect(c'', 1, 1, nil, false, false)
		verify(C.kasprintf(3264, &C.vks_const_char(c'')))
		expect(c'42/yes/1/2/3/4/5/6/7', 21, 21, nil, false, false)
		verify(C.kasprintf(3264, &C.vks_const_char(c'%u/%s/%u/%u/%u/%u/%u/%u/%u'), u32(42), c'yes', u32(1), u32(2), u32(3), u32(4), u32(5), u32(6), u32(7)))
		mixed := &char(c'-128|255|-32768|65535|-17|18|-9223372036854775808|18446744073709551615|-19|20|-21|00000000000000ab|  abc|7|8|9')
		mixed_size := C.strlen(mixed) + 1
		expect(mixed, mixed_size, mixed_size, nil, false, false)
		verify(C.kasprintf(3264, &C.vks_const_char(c'%hhd|%hhu|%hd|%hu|%ld|%lu|%lld|%llu|%zd|%zu|%td|%px|%*.*s|%u|%u|%u'), i32(128), i32(-1), i32(-32768), i32(65535), isize(-17), usize(18), sll(i64(-9223372036854775807) - 1), ull(~u64(0)), isize(-19), usize(20), isize(-21), voidptr(0xab), i32(5), i32(3), c'abcdef', u32(7), u32(8), u32(9)))
		check(last_reclaim)
		calls := page_calls
		frees := page_frees
		fail_pages = true
		expect(nil, 0, 0, nil, true, true)
		verify(C.kasprintf(3264, &C.vks_const_char(c'%u/%s'), u32(42), c'borrowed'))
		check(page_calls == calls + 1 && page_frees == frees && live_pages == 0 && fail_pages)
		verify(C.kasprintf(u32(-1), &C.vks_const_char(c'%u/%s'), u32(42), c'borrowed'))
		check(page_calls == calls + 1 && live_pages == 0 && fail_pages)
		fail_pages = false
		sleepable = false
		expect(c'atomic', 7, 7, nil, false, false)
		verify(C.kasprintf(3264, text(c'%s'), c'atomic'))
		check(!last_reclaim)
		sleepable = true
		scenarios++
	}
}

fn constant_fastpaths() voidptr {
	unsafe {
		host_page := usize(C.getpagesize())
		check(host_page >= 4096 && (host_page & (host_page - 1)) == 0)
		mapping := C.kph_map(host_page * 2)
		check(usize(mapping) != usize(-1))
		image_first = usize(mapping)
		image_last = image_first + host_page
		C.memcpy(mapping, c'image-rodata', 13)
		check(C.kph_readonly(mapping, host_page) == 0)
		for mode in [u32(1), 3]! {
			call_mode = mode
			before := page_calls
			frees := page_frees
			fail_pages = true
			expect(&char(mapping), 13, 0, mapping, false, true)
			origin(u32(-1), text(&char(mapping)), u32(0x425a6719))
			expect(&char(image_first + 12), 1, 0, voidptr(image_first + 12), false, true)
			origin(u32(-1), text(&char(image_first + 12)), u32(0x425a6719))
			expect(&char(image_first + 6), 7, 0, voidptr(image_first + 6), false, false)
			origin(u32(-1), text(c'%s'), voidptr(image_first + 6), u32(0x425a6719))
			expect(&char(image_first + 12), 1, 0, voidptr(image_first + 12), false, false)
			origin(u32(-1), text(c'%s'), voidptr(image_first + 12), u32(0x425a6719))
			expect(nil, 0, 0, nil, true, false)
			origin(3264, text(c'%s'), voidptr(nil), u32(0x425a6719))
			check(page_calls == before && page_frees == frees && fail_pages && live_pages == 0)
			mut source := [u8(`a`), `b`, 0, 0x5a]!
			expect(nil, 0, 0, nil, true, false)
			origin(3264, text(c'%s'), &source[0], u32(0x425a6719))
			check(page_calls == before + 1 && page_frees == frees && fail_pages)
			origin(u32(-1), text(c'%s'), &source[0], u32(0x425a6719))
			check(page_calls == before + 1 && fail_pages)
			expect(nil, 0, 0, nil, true, true)
			origin(3264, text(&char(&source[0])), u32(0x425a6719))
			check(page_calls == before + 2 && page_frees == frees && fail_pages && live_pages == 0)
			fail_pages = false
			expect(c'ab', 3, 3, nil, false, false)
			origin(3264, text(c'%s'), &source[0], u32(0x425a6719))
			check(source[0] == `a` && source[3] == 0x5a)
			expect(c'ab', 3, 3, nil, false, true)
			origin(3264, text(&char(&source[0])), u32(0x425a6719))
			expect(c'image-rodata', 13, 13, nil, false, false)
			origin(3264, text(c'%.*s'), i32(12), mapping, u32(0x425a6719))
			expect(c'image-rodata!', 14, 14, nil, false, false)
			origin(3264, text(c'%s!'), mapping, u32(0x425a6719))
			scenarios++
		}
		// An arbitrary readonly mapping outside the designated image must be copied.
		outside := voidptr(image_last)
		C.memcpy(outside, c'external', 9)
		check(C.kph_readonly(outside, host_page) == 0)
		call_mode = 1
		expect(c'external', 9, 9, nil, false, true)
		origin(3264, text(&char(outside)), u32(0x425a6719))
		expect(c'external', 9, 9, nil, false, false)
		origin(3264, text(c'%s'), outside, u32(0x425a6719))
		scenarios++
		return mapping
	}
}

fn failures_and_mismatch() {
	unsafe {
		for mode := u32(0); mode < 4; mode++ {
			call_mode = mode
			before := page_calls
			frees := page_frees
			expect(nil, 0, 0, nil, true, true)
			fail_pages = true
			origin(3264, text(c'%u/%s'), u32(42), c'borrowed', u32(0x425a6719))
			check(page_calls == before + 1 && page_frees == frees && live_pages == 0 && fail_pages)
			origin(u32(-1), text(c'%u/%s'), u32(42), c'borrowed', u32(0x425a6719))
			check(page_calls == before + 1 && live_pages == 0 && fail_pages)
			fail_pages = false
			mut source := [16]char{}
			C.memcpy(&source[0], c'ab', 3)
			mutation_pointer = &source[0]
			mutation_data = c'abcdef'
			mutation_size = 7
			// Brackets force the ordinary path even for kvasprintf_const.
			expected_warning = c'\x01\x34linuxkpi: warning at kernel/linuxkpi/compatcore/kasprintf.v:0: different return values (4 and 8) from vsnprintf("[%s]", ...)'
			expect(c'[abc', 5, 5, nil, false, false)
			origin(3264, text(c'[%s]'), &source[0], u32(0x425a6719))
			check(source[0] == char(`a`) && source[5] == char(`f`) && mutation_pointer == nil)
			C.memcpy(&source[0], c'abcdef', 7)
			mutation_pointer = &source[0]
			mutation_data = c'x'
			mutation_size = 2
			expected_warning = c'\x01\x34linuxkpi: warning at kernel/linuxkpi/compatcore/kasprintf.v:0: different return values (8 and 3) from vsnprintf("[%s]", ...)'
			expect(c'[x]', 4, 9, nil, false, false)
			origin(3264, text(c'[%s]'), &source[0], u32(0x425a6719))
			check(source[0] == char(`x`) && mutation_pointer == nil)
			expected_warning = nil
			scenarios++
		}
	}
}

fn churn() {
	unsafe {
		for mode := u32(0); mode < 4; mode++ {
			call_mode = mode
			before := page_calls
			frees := page_frees
			for index := 0; index < 128; index++ {
				expect(c'owned/42', 9, 9, nil, false, false)
				origin(if index & 1 == 0 { u32(3264) } else { u32(0x100) }, text(c'%s/%u'), c'owned', u32(42), u32(0x425a6719))
				check(live_pages == 0)
			}
			check(page_calls == before + 128 && page_frees == frees + 128)
			scenarios++
		}
	}
}

@[export:'main']
pub fn main(_argc i32, _argv &&char) i32 {
	ordinary_and_capture()
	mapping := constant_fastpaths()
	failures_and_mismatch()
	overflow_cases()
	churn()
	check(unsafe { warnings == 16 && scenarios == 32 })
	check(C.munmap(mapping, usize(C.getpagesize()) * 2) == 0 && unsafe { live_pages == 0 })
	unsafe {
		for slot := 0; slot < 32; slot++ {
			check(page_bases[slot] == nil && page_counts[slot] == 0)
		}
	}
	C.printf(c'PASS: original formatted allocation; genuine va_start typed public lists, named2 capture, ownership, GFP/OOM, checked counts and real WARN; ABI=%d scenarios=%u assertions=%u warnings=%u live_pages=%zu\n', C.VINIX_VA_ABI, unsafe { scenarios }, unsafe { assertions }, unsafe { warnings }, unsafe { live_pages })
	return 0
}

// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The screen while the machine sleeps.
//
// A machine that is asleep should not show a picture: a display that keeps
// its backlight shows the last frame for as long as the sleep lasts, and it
// is that frame which says "awake" to whoever looks at it. Where the screen
// is the boot loader's framebuffer -- a PC with no display driver, a virtual
// machine -- the kernel can do one thing about it, and does: the picture is
// put away, the screen is painted black, and the picture is put back when
// the machine wakes. Whoever drew it, the console or a compositor, finds it
// as it was and is not asked to draw again.
//
// The picture is kept in single pages, so that a large screen does not need
// one large piece of memory at the moment the machine goes down. If the
// pages are not to be had the screen is left as it is: a frozen picture is
// better than one that cannot be put back.
//
// A panel with a driver of its own -- Apple's, through DCP -- is not reached
// by this: its backlight and its power are that driver's to switch, and it
// does not yet.
@[has_globals]
module term

import memory

fn C.memcpy(dest voidptr, source voidptr, length uint) voidptr
fn C.memset(dest voidptr, value i32, length uint) voidptr

__global (
	// The physical address of each page of the picture put away.
	screen_pages      &u64
	screen_page_count u64
	screen_dark       bool
	screen_sleeps     u64
	screen_refusals   u64
)

fn screen_bytes() u64 {
	if framebuffer_tag == unsafe { nil } {
		return 0
	}
	return u64(framebuffer_tag.pitch) * u64(framebuffer_tag.height)
}

fn screen_release(mut list &u64, count u64) {
	for i in 0 .. count {
		memory.pmm_free(voidptr(unsafe { list[i] }), 1)
	}
	memory.free(voidptr(list))
}

// Put the picture away and paint the screen black. False if there is no
// such screen, it is dark already, or there was no memory for the picture;
// the screen is then as it was. Called with nothing left to draw: userspace
// frozen and the devices down.
pub fn screen_sleep() bool {
	bytes := screen_bytes()
	if bytes == 0 || screen_dark {
		return false
	}
	count := (bytes + page_size - 1) / page_size
	// Freed by screen_wake().
	mut list := unsafe { &u64(memory.malloc_packed_fallible(count * 8)) }
	if list == unsafe { nil } {
		screen_refusals++
		return false
	}
	for i in 0 .. count {
		page := memory.pmm_alloc_nozero_fallible(1)
		if page == unsafe { nil } {
			screen_release(mut list, i)
			screen_refusals++
			return false
		}
		unsafe {
			list[i] = u64(page)
		}
	}
	picture := unsafe { &u8(framebuffer_tag.address) }
	// With the console's lock: a line being drawn is finished first, and
	// from the moment the screen is dark no other is started (print()).
	terminal_print_lock.acquire()
	for i in 0 .. count {
		offset := i * page_size
		length := if bytes - offset < page_size { bytes - offset } else { page_size }
		unsafe { C.memcpy(voidptr(list[i] + higher_half), picture + offset, uint(length)) }
	}
	unsafe { C.memset(picture, 0, uint(bytes)) }
	screen_pages = list
	screen_page_count = count
	screen_dark = true
	terminal_print_lock.release()
	screen_sleeps++
	return true
}

// Put the picture back. Nothing happens if the screen was not made dark.
pub fn screen_wake() {
	if !screen_dark {
		return
	}
	bytes := screen_bytes()
	mut list := screen_pages
	count := screen_page_count
	picture := unsafe { &u8(framebuffer_tag.address) }
	terminal_print_lock.acquire()
	for i in 0 .. count {
		offset := i * page_size
		length := if bytes - offset < page_size { bytes - offset } else { page_size }
		unsafe { C.memcpy(picture + offset, voidptr(list[i] + higher_half), uint(length)) }
	}
	screen_pages = unsafe { nil }
	screen_page_count = 0
	screen_dark = false
	terminal_print_lock.release()
	screen_release(mut list, count)
}

// How often the screen went dark for a sleep, and how often it was left lit
// for want of memory.
pub fn screen_sleep_counts() (u64, u64) {
	return screen_sleeps, screen_refusals
}

// The kernel is panicking. What it has to say goes on the screen, dark or
// not: nothing is put back or freed -- this may be the allocator's panic --
// the console just draws again, on the black.
pub fn screen_for_panic() {
	screen_dark = false
}

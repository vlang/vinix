// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The xHCI driver on x86-64: registers through the direct map, the device
// core's clock, and the PS/2 drivers' own state for what the keyboards and
// pointers report -- a USB key is given to the console as the scancode the
// same key has on a PS/2 keyboard, and a USB pointer moves /dev/pointer.
//
// Nothing here polls this driver for anyone else, so a thread of its own
// does, at the rate a USB keyboard would be asked for its keys anyway.
module xhci

import dev.console
import dev.mouse
import devcore
import memory
import x86.kio

const pte_write_through = u64(1) << 3
const pte_cache_disable = u64(1) << 4
// A full-speed keyboard asks to be polled every 8 or 10 ms.
const poll_ms = u64(8)

fn map_registers(phys u64, length u64) u64 {
	hhdm := memory.get_hhdm_offset()
	if phys + length <= u64(0x100000000) {
		return phys + hhdm
	}
	flags := memory.pte_present | memory.pte_writable | memory.pte_noexec | pte_write_through | pte_cache_disable
	for page := phys & ~u64(0xfff); page < phys + length; page += 0x1000 {
		kernel_pagemap.map_page(page + hhdm, page, flags) or { return 0 }
	}
	return phys + hhdm
}

fn rd(addr u64) u32 {
	return kio.mmin[u32](unsafe { &u32(addr) })
}

fn wr(addr u64, value u32) {
	kio.mmout[u32](unsafe { &u32(addr) }, value)
}

// Stores reach memory in the order they were made, and the controller is
// told of them by a register write that comes after.
fn barrier() {
}

fn barrier_full() {
}

fn now_ns() u64 {
	return devcore.now_ns()
}

fn busywait_us(microseconds u64) {
	devcore.stall(microseconds * 1000)
}

fn sink_key(code u16, value u32) {
	console.usb_key(code, value)
}

fn sink_declare_pointer(absolute bool, max_x int, max_y int) {
	mouse.usb_declare(absolute, max_x, max_y)
}

fn sink_absolute(x int, y int) {
	mouse.usb_absolute(x, y)
}

fn sink_relative(dx int, dy int) {
	mouse.usb_relative(dx, dy)
}

fn sink_scroll(delta int) {
	mouse.usb_scroll(delta)
}

fn sink_buttons(buttons u32) {
	mouse.usb_buttons(buttons)
}

fn poll_thread() {
	for {
		poll()
		devcore.sleep_ms(poll_ms)
	}
}

fn start_polling() {
	if !xhci_polled {
		xhci_polled = true
		spawn poll_thread()
	}
}

// The thread above polls whether or not the machine sleeps.
fn sleeping(asleep bool) {
}

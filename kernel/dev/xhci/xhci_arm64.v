// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The xHCI driver on AArch64: registers reached through the device mapping
// and read and written 32 bits at a time with a barrier, the generic timer
// for time, and virtio_input for what the keyboards and pointers report --
// it holds the state the console and /dev/pointer read, and polls this
// driver from the idle loop as it polls itself.
module xhci

import aarch64.cpu
import aarch64.timer
import aarch64.virtio_input
import devcore
import katomic
import memory
import wakesrc

fn map_registers(phys u64, length u64) u64 {
	return memory.map_mmio(phys, length)
}

@[noinline]
fn rd(addr u64) u32 {
	value := unsafe { *&u32(addr) }
	cpu.dmb_ish()
	return value
}

@[noinline]
fn wr(addr u64, value u32) {
	cpu.dmb_ish()
	unsafe {
		*&u32(addr) = value
	}
}

fn barrier() {
	cpu.dmb_ish()
}

fn barrier_full() {
	cpu.dsb_sy()
}

fn now_ns() u64 {
	return timer.get_ns()
}

fn busywait_us(microseconds u64) {
	timer.busywait_us(microseconds)
}

// A key going down ends a sleep, if keys may: virtio_input says so for its own
// devices where it takes their events, which these do not pass through.
fn sink_key(code u16, value u32) {
	if value == 1 {
		wakesrc.report(.keyboard)
	}
	virtio_input.report_key(code, value)
}

fn sink_declare_pointer(absolute bool, max_x int, max_y int) {
	virtio_input.declare_pointer(absolute, max_x, max_y)
}

fn sink_absolute(x int, y int) {
	wakesrc.report(.pointer)
	virtio_input.report_absolute(x, y)
}

fn sink_relative(dx int, dy int) {
	wakesrc.report(.pointer)
	virtio_input.report_relative(dx, dy)
}

fn sink_scroll(delta int) {
	virtio_input.report_scroll(delta)
}

fn sink_buttons(buttons u32) {
	virtio_input.report_buttons(buttons)
}

// With every program stopped for a sleep nothing asks virtio_input for keys,
// and this driver is only ever asked through it. So for as long as the
// devices are suspended a thread asks instead: a key on a USB keyboard is
// then seen, and ends a suspend to idle as a key on any other does.
fn sleep_poll_thread() {
	for {
		if katomic.load(&xhci_sleep_polling) != 0 {
			virtio_input.poll()
			devcore.sleep_ms(10)
		} else {
			devcore.sleep_ms(200)
		}
	}
}

fn sleeping(asleep bool) {
	katomic.store(mut &xhci_sleep_polling, if asleep { u32(1) } else { u32(0) })
}

// poll() is called from virtio_input.poll(), under its lock.
fn start_polling() {
	virtio_input.set_extra_poller(voidptr(poll))
	if !xhci_polled {
		xhci_polled = true
		spawn sleep_poll_thread()
	}
}

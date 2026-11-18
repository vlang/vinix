// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module kio

import aarch64.cpu
import aarch64.timer
import klock

__global mailbox_base = u64(0)
__global send_lock = unsafe { &klock.Lock(nil) }
__global mailbox_send_started = u64(0)
__global available_at = u64(0)
__global send_barrier_start = u32(0)
__global status_reads = u64(0)
__global send_writes = 0
__global mailbox_send_words = [2]u64{}
pub const simulated_aic_base = u64(0x23b100000)
__global simulated_aic_event = u32(0)
__global simulated_aic_masks = [28]u32{}
__global simulated_aic_targets = [896]u32{}
__global simulated_aic_unmasks = 0

pub fn queue_aic_event(irq u32) {
	assert simulated_aic_event == 0 && irq < 896
	simulated_aic_event = (u32(1) << 16) | irq
}

pub fn aic_irq_masked(irq u32) bool {
	return simulated_aic_masks[irq / 32] & (u32(1) << (irq % 32)) != 0
}

pub fn aic_cpu_target(irq u32) u32 {
	return simulated_aic_targets[irq]
}

pub fn aic_unmasks() int { return simulated_aic_unmasks }

pub fn configure_send(base u64, guard &klock.Lock, full_for_us u64) {
	mailbox_base = base
	send_lock = unsafe { guard }
	mailbox_send_started = timer.get_us()
	available_at = full_for_us
	send_barrier_start = cpu.send_barriers()
	status_reads = 0
	send_writes = 0
}

pub fn mmin32(addr &u32) u32 {
	if u64(addr) == simulated_aic_base + 4 { return 896 }
	if u64(addr) == simulated_aic_base + 0x2004 {
		evt := simulated_aic_event
		if evt != 0 {
			irq := evt & 0xffff
			simulated_aic_masks[irq / 32] |= u32(1) << (irq % 32)
			simulated_aic_event = 0
		}
		return evt
	}
	assert u64(addr) == mailbox_base + 0x110 && send_lock.is_held()
	status_reads++
	return if timer.get_us() - mailbox_send_started < available_at { u32(1 << 16) } else { u32(0) }
}

pub fn mmout32(addr &u32, value u32) {
	offset := u64(addr) - simulated_aic_base
	if offset >= 0x3000 && offset < 0x3000 + 896 * 4 {
		simulated_aic_targets[(offset - 0x3000) / 4] = value
	} else if offset >= 0x4100 && offset < 0x4100 + 28 * 4 {
		simulated_aic_masks[(offset - 0x4100) / 4] |= value
	} else if offset >= 0x4180 && offset < 0x4180 + 28 * 4 {
		simulated_aic_masks[(offset - 0x4180) / 4] &= ~value
		simulated_aic_unmasks++
	} else {
		assert offset in [u64(0x200c), 0x2028]! || (offset >= 0x4080 && offset < 0x4080 + 28 * 4)
	}
}

pub fn mmin(_ &u64) u64 {
	panic('unexpected 64-bit mailbox read')
}

pub fn mmout(addr &u64, value u64) {
	assert send_lock.is_held()
	assert cpu.send_barriers() == send_barrier_start + 1
	assert timer.get_us() - mailbox_send_started >= available_at
	assert send_writes < mailbox_send_words.len
	assert u64(addr) == mailbox_base + 0x800 + u64(send_writes) * 8
	mailbox_send_words[send_writes] = value
	send_writes++
}

pub fn send_result() (u64, int, [2]u64) {
	return status_reads, send_writes, mailbox_send_words
}

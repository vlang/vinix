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
	assert u64(addr) == mailbox_base + 0x110 && send_lock.is_held()
	status_reads++
	return if timer.get_us() - mailbox_send_started < available_at { u32(1 << 16) } else { u32(0) }
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

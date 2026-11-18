// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module gpu

import aarch64.aic
import aarch64.cpu
import aarch64.exception
import aarch64.kio
import aarch64.timer
import apple.ascmailbox

__global tx_irq_waits = 0
__global tx_irq_pulses = [2]int{}

fn check_asc_mailbox_send() {
	base := u64(0x206408000)
	message := ascmailbox.MboxMsg{data0: 0x123456789abcdef0, data1: 0x21}
	mut box := ascmailbox.new_mailbox(base)
	timer.require_unlocked_waits(unsafe { &box.lock })
	for sample in [[u64(0), 0]!, [u64(1), 100]!, [u64(100), 100]!, [u64(101), 200]!,
		[u64(499999), 500000]!, [u64(500000), 500000]!, [u64(500001), 500000]!]! {
		start := timer.get_us()
		barriers := cpu.send_barriers()
		kio.configure_send(base, unsafe { &box.lock }, sample[0])
		sent := box.send_timed(message)
		assert sent == (sample[0] <= 500000)
		assert timer.get_us() - start == sample[1]
		assert !box.lock.is_held()
		reads, writes, words := kio.send_result()
		assert reads == sample[1] / 100 + 1
		if sent {
			assert cpu.send_barriers() == barriers + 1 && writes == 2
			assert words == [message.data0, message.data1]!
		} else {
			assert cpu.send_barriers() == barriers && writes == 0
			// A fresh attempt has its own budget once the previous send did
			// not publish either word.
			assert box.send_timed(message)
			assert timer.get_us() - start == 500100 && !box.lock.is_held()
			retry_reads, retry_writes, retry_words := kio.send_result()
			assert retry_reads == reads + 2 && retry_writes == 2
			assert retry_words == [message.data0, message.data1]!
		}
	}
	kio.configure_send(base, unsafe { &box.lock }, 1)
	legacy_start := timer.get_us()
	assert !box.send(message)
	legacy_reads, legacy_writes, _ := kio.send_result()
	assert legacy_reads == 1000000 && legacy_writes == 0
	assert timer.get_us() == legacy_start && !box.lock.is_held()
	timer.require_unlocked_waits(unsafe { nil })
	kio.configure_send(0, unsafe { nil }, 0)
	println('ASC mailbox: seven transmit boundary cases, one fresh retry and one legacy timeout')
}

fn simulate_send_empty() {
	tx_irq_waits++
	if tx_irq_waits in tx_irq_pulses {
		assert !kio.aic_irq_masked(575)
		assert !aic.deferred_send_irq_pending(575)
		kio.queue_aic_event(575)
		exception.dispatch()
		assert aic.deferred_send_irq_pending(575) && kio.aic_irq_masked(575)
	}
}

struct SendIrqCase {
	available_us u64
	elapsed_us   u64
	pulses       [2]int
	reads        u64
	arms         int
	masked       bool
}

fn check_asc_mailbox_send_irq() {
	base := u64(0x206408000)
	irq := u32(575)
	message := ascmailbox.MboxMsg{data0: 0x123456789abcdef0, data1: 0x21}
	mut box := ascmailbox.new_mailbox(base)
	timer.require_unlocked_waits(unsafe { &box.lock })
	for sample in [
		SendIrqCase{reads: 1},
		SendIrqCase{available_us: 1, elapsed_us: 20, pulses: [2, 0]!, reads: 2, arms: 1},
		// The first latched notification arrives with the FIFO still full.
		SendIrqCase{available_us: 15, elapsed_us: 30, pulses: [1, 3]!, reads: 3, arms: 2},
		SendIrqCase{available_us: 51, elapsed_us: 100, reads: 2, arms: 1},
		SendIrqCase{available_us: 51, elapsed_us: 100, reads: 2, masked: true},
		SendIrqCase{available_us: 500001, elapsed_us: 500000, reads: 5001, arms: 1},
	]! {
		start := timer.get_us()
		unmasks := kio.aic_unmasks()
		barriers := cpu.send_barriers()
		kio.configure_send(base, unsafe { &box.lock }, sample.available_us)
		tx_irq_waits = 0
		tx_irq_pulses = sample.pulses
		timer.watch_busywait(simulate_send_empty)
		cpu.set_interrupt_state(!sample.masked)
		sent := box.send_timed_irq(message, irq)
		cpu.set_interrupt_state(true)
		timer.watch_busywait(unsafe { nil })
		assert sent == (sample.available_us <= 500000)
		assert timer.get_us() - start == sample.elapsed_us
		assert kio.aic_unmasks() == unmasks + sample.arms && kio.aic_irq_masked(irq)
		assert !box.lock.is_held()
		reads, writes, words := kio.send_result()
		assert reads == sample.reads
		if sent {
			assert cpu.send_barriers() == barriers + 1 && writes == 2
			assert words == [message.data0, message.data1]!
		} else {
			assert cpu.send_barriers() == barriers && writes == 0
			assert box.send_timed_irq(message, irq)
			assert timer.get_us() - start == 500100 && kio.aic_irq_masked(irq)
			retry_reads, retry_writes, retry_words := kio.send_result()
			assert retry_reads == reads + 2 && retry_writes == 2
			assert retry_words == [message.data0, message.data1]!
		}
	}
	timer.require_unlocked_waits(unsafe { nil })
	kio.configure_send(0, unsafe { nil }, 0)
	println('ASC send-empty IRQ: fast path, delivery, stale IRQ, fallback, masked caller, timeout and retry passed')
}

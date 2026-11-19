// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module gpu

import aarch64.aic
import aarch64.cpu
import aarch64.exception
import aarch64.kio
import aarch64.timer
import apple.ascmailbox
import klock

__global tx_irq_waits = 0
__global tx_irq_pulses = [2]int{}
__global tx_contended_mailbox = unsafe { &ascmailbox.Mailbox(nil) }

fn contend_for_send_empty() {
	timer.watch_busywait(unsafe { nil })
	assert !kio.aic_irq_masked(575) && !tx_contended_mailbox.lock.is_held()
	start := timer.get_us()
	unmasks := kio.aic_unmasks()
	assert tx_contended_mailbox.send_timed_irq(ascmailbox.MboxMsg{data0: 0x123, data1: 0x21}, 575)
	assert timer.get_us() - start == 100
	assert !kio.aic_irq_masked(575) && kio.aic_unmasks() == unmasks
	_, writes, words := kio.send_result()
	assert writes == 2 && words == [u64(0x123), 0x21]!
	// Let the original waiter observe the next empty FIFO.
	kio.configure_send(tx_contended_mailbox.base, unsafe { &tx_contended_mailbox.lock }, 1)
	kio.queue_aic_event(575)
	exception.dispatch()
}

fn delay_timed_retry() {
	timer.watch_busywait(unsafe { nil })
	timer.busywait_us(500_001)
}

fn contend_with_timed_retry() {
	timer.watch_busywait(unsafe { nil })
	klock.on_next_acquire(unsafe { &tx_contended_mailbox.lock }, delay_timed_retry)
}

fn check_asc_mailbox_retry_deadline() {
	base := u64(0x206408000)
	message := ascmailbox.MboxMsg{data0: 0x123456789abcdef0, data1: 0x21}
	mut box := ascmailbox.new_mailbox(base)
	tx_contended_mailbox = unsafe { &box }
	timer.require_unlocked_waits(unsafe { &box.lock })
	for irq in [u32(0), 575]! {
		for contended in [false, true]! {
			kio.configure_send(base, unsafe { &box.lock }, 500_001)
			barriers := cpu.send_barriers()
			start := timer.get_us()
			timer.watch_busywait(if contended { contend_with_timed_retry } else { delay_timed_retry })
			assert !box.send_timed_irq(message, irq), 'ASC timed retry must refuse a FIFO that becomes ready after the deadline'
			reads, writes, _ := kio.send_result()
			assert timer.get_us() - start > 500_000 && reads == 1 && writes == 0
			assert cpu.send_barriers() == barriers && !box.lock.is_held() && kio.aic_irq_masked(575)
			assert box.send_timed_irq(message, irq)
			retry_reads, retry_writes, words := kio.send_result()
			assert retry_reads == 2 && retry_writes == 2 && words == [message.data0, message.data1]!
		}
	}
	timer.require_unlocked_waits(unsafe { nil })
	tx_contended_mailbox = unsafe { nil }
	kio.configure_send(0, unsafe { nil }, 0)
	println('ASC timed retry: four IRQ and polling cases preserve the deadline across wait and lock delays')
}

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
	start := timer.get_us()
	unmasks := kio.aic_unmasks()
	tx_contended_mailbox = unsafe { &box }
	kio.configure_send(base, unsafe { &box.lock }, 1)
	timer.watch_busywait(contend_for_send_empty)
	assert box.send_timed_irq(message, irq)
	assert timer.get_us() - start == 110
	assert kio.aic_unmasks() == unmasks + 1 && kio.aic_irq_masked(irq)
	reads, writes, words := kio.send_result()
	assert reads == 1 && writes == 2 && words == [message.data0, message.data1]!
	tx_contended_mailbox = unsafe { nil }
	kio.configure_send(base, unsafe { &box.lock }, 1)
	assert box.send_timed_irq(message, irq)
	assert kio.aic_unmasks() == unmasks + 2 && kio.aic_irq_masked(irq)
	timer.require_unlocked_waits(unsafe { nil })
	kio.configure_send(0, unsafe { nil }, 0)
	println('ASC send-empty IRQ: fast path, delivery, stale IRQ, fallback, masked caller, timeout, retry and contention passed')
}

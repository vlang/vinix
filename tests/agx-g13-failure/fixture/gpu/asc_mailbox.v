// SPDX-License-Identifier: GPL-2.0-or-later
module gpu

import aarch64.cpu
import aarch64.kio
import aarch64.timer
import apple.ascmailbox

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

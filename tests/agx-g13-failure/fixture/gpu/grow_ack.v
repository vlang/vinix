// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module gpu

import aarch64.kio
import aarch64.timer
import apple.ascmailbox
import apple.mailbox
import apple.rtkit
import gpu.agx.channel
import gpu.agx.fw
import gpu.agx.hw

enum GrowAckCase {
	grew
	fits_limit
	exceeds_limit
	at_limit
	allocation_failed
	unknown_owner
	polled
	stopped
	fifo_timeout
	ring_full
	fatal_growth
}

__global grow_ack_case = GrowAckCase.grew
__global grow_ack_header = unsafe { &channel.RingHeader(nil) }
__global grow_ack_entry = unsafe { &fw.FwGrowTVBAck(nil) }

fn (mgr &GpuManager) g13_tvb_owner_locked(vm_slot u32, buffer_slot u32) ?&G13RenderBufferResources {
	assert mgr.lock.is_held() && vm_slot == 3 && buffer_slot == 2
	if mgr.tvb_owner == unsafe { nil } { return none }
	return mgr.tvb_owner
}

fn observe_grow_ack_wait() {
	assert grow_ack_header.write_ptr == 1 && grow_ack_entry.counter == 0x81234567
	assert !rtkit_owner.channels.device_ctrl.lock.is_held(), 'the ring must be released before waiting'
	if grow_ack_case == .stopped {
		stop_during_batch_doorbell()
	} else if grow_ack_case == .fifo_timeout {
		assert !rtkit_owner.lock.is_held()
		timer.watch_busywait(unsafe { nil })
	} else {
		observe_runtime_wait()
	}
}

fn check_g13_grow_ack_transmit() {
	base := u64(0x206408000)
	mut tx := ascmailbox.new_mailbox(base)
	mailbox.set_wait_transport(unsafe { &tx })
	for abi in [hw.FirmwareAbi.v12_3, .v13_5_partial]! {
		for sample in [GrowAckCase.grew, .fits_limit, .exceeds_limit, .at_limit, .allocation_failed, .unknown_owner, .polled,
			.stopped, .fifo_timeout, .ring_full, .fatal_growth]! {
			mut transport := rtkit.RTKit{name: 'g13-grow-ack'}
			boot_g13_fixture_transport(mut transport)
			mut status := fw.G13FwStatus{halt_count: 0x1234567887654321}
			mut graph := G13ChannelAllocations{fw_status: SharedBuffer{phys: u64(unsafe { &status })}}
			mut header := channel.RingHeader{read_ptr: if sample == .ring_full { u32(1) } else { u32(0) }}
			mut ring := [2]fw.FwGrowTVBAck{}
			mut stats := fw.G13BufferStats{reset: 1}
			mut owner := G13RenderBufferResources{stats: SharedBuffer{phys: u64(unsafe { &stats })}, active_scenes: 1}
			initial_blocks := match sample {
				.fits_limit { g13_tvb_max_blocks - u32(10) }
				.exceeds_limit { g13_tvb_max_blocks - u32(9) }
				.at_limit { g13_tvb_max_blocks }
				else { u32(0) }
			}
			if initial_blocks != 0 { owner.blocks = []u8{len: int(initial_blocks)} }
			original_blocks := unsafe { owner.blocks }
			mut mgr := GpuManager{hw_config: hw.HwConfig{gpu_gen: .g13, firmware_abi: abi},
				rtkit_send_irq: if sample == .polled { u32(0) } else { u32(575) },
				g13_channels: unsafe { &graph }, rtk: unsafe { &transport },
				tvb_grow_fails: sample == .allocation_failed, tvb_grow_fatal: sample == .fatal_growth}
			if sample in [.grew, .fits_limit, .exceeds_limit, .at_limit, .allocation_failed, .fatal_growth]! {
				mgr.tvb_owner = unsafe { &owner }
			}
			mgr.channels.device_ctrl = channel.new_tx_channel('device', 1, u64(unsafe { &header }),
				1, u64(unsafe { &ring }), 2, u32(sizeof(fw.FwGrowTVBAck)))
			rtkit_owner = unsafe { &mgr }
			grow_ack_header = unsafe { &header }
			grow_ack_entry = unsafe { &ring[0] }
			grow_ack_case = sample
			kio.require_send_owner(unsafe { &mgr.lock })
			kio.configure_send(base, unsafe { &tx.lock }, if sample == .fifo_timeout { u64(500_001) } else { u64(1) })
			runtime_case = .timely
			runtime_waits = 0
			timer.watch_busywait(observe_grow_ack_wait)
			mgr.checked_handle_g13_grow_tvb(3, 2, 0x81234567)
			timer.watch_busywait(unsafe { nil })
			assert !mgr.lock.is_held() && !tx.lock.is_held() && kio.aic_irq_masked(575)
			reads, writes, words := kio.send_result()
			if sample in [.ring_full, .fatal_growth]! {
				assert header.write_ptr == 0 && reads == 0 && writes == 0 && mgr.state == .error
			} else {
				assert header.write_ptr == 1
				assert ring[0] == fw.FwGrowTVBAck{tag: if abi == .v12_3 { u32(0x0d) } else { u32(0x0e) },
					unk_4: 1, buffer_slot: 2, vm_slot: 3, counter: 0x81234567, halt_count: status.halt_count}
				if sample == .stopped {
					assert mgr.state == .stopped && reads == 1 && writes == 0
				} else if sample == .fifo_timeout {
					assert mgr.state == .error && reads == 5001 && writes == 0
				} else if sample == .polled {
					assert mgr.state == .running && reads == 0 && writes == 0
					assert transport.mbox.timed_attempts == 4 && transport.mbox.irq_send_attempts == 0
					assert transport.mbox.last == mailbox.MboxMsg{data0: 0x0083000000000011, data1: 0x21}
				} else {
					assert mgr.state == .running && reads == 2 && writes == 2 && runtime_waits == 1
					assert words == [u64(0x0083000000000011), 0x21]!
				}
			}
			grows := sample in [.grew, .fits_limit]!
			assert mgr.tvb_calls == if grows || sample in [.allocation_failed, .fatal_growth]! { 1 } else { 0 },
				'GrowTVB must leave the buffer alone when ten more blocks do not fit'
			assert owner.blocks.len == int(initial_blocks) + if grows { 10 } else { 0 }
			if initial_blocks != 0 && owner.blocks.data != original_blocks.data {
				unsafe { original_blocks.free() }
			}
			if owner.blocks.len != 0 { unsafe { owner.blocks.free() } }
		}
	}
	assert sizeof(fw.FwGrowTVBAck) == 0x30 && __offsetof(fw.FwGrowTVBAck, halt_count) == 0x18
	assert fw.make_grow_tvb_ack(.g17_26_5_partial, 2, 3, 4, 0) == none
	assert fw.make_recover_channel(.g17_26_5_partial, 2, 1, 4) == none
	mailbox.set_wait_transport(unsafe { nil })
	rtkit_owner = unsafe { nil }
	grow_ack_header = unsafe { nil }
	grow_ack_entry = unsafe { nil }
	kio.require_send_owner(unsafe { nil })
	kio.configure_send(0, unsafe { nil }, 0)
	println('G13 GrowTVBAck: both wire tags, full halt count, IRQ, polling, error and shutdown paths passed')
}

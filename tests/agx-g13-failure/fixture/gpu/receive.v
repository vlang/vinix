// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module gpu

import gpu.agx.channel
import gpu.agx.fw
import gpu.agx.hw
import katomic
import klock

__global receive_owner = unsafe { &GpuManager(nil) }
__global reused_event = unsafe { &fw.FwEventMsg(nil) }

fn stop_receive_owner() {
	assert !receive_owner.lock.is_held()
	receive_owner.shutdown()
}

fn require_receive_lock() {
	assert receive_owner.lock.is_held(), 'RX acknowledged a record outside the teardown lock'
}

fn reuse_event_record() {
	require_receive_lock()
	reused_event.tag = fw.fw_event_fault
	reused_event.payload[0] = 0
	reused_event.payload[1] = 0
	reused_event.payload[2] = 0
}

fn check_g13_receive_shutdown() {
	for abi in [hw.FirmwareAbi.v12_3, .v13_5_partial]! {
		for kind in 0 .. 3 {
			for order in 0 .. 3 {
				mut mgr := GpuManager{hw_config: hw.HwConfig{gpu_gen: .g13, firmware_abi: abi}}
				mut header := channel.RingHeader{write_ptr: 2}
				ring := [u64(0x123456789abcdef0), 0xfedcba9876543210, 0, 0]!
				mut rx := match kind {
					0 { unsafe { &mgr.channels.event } }
					1 { unsafe { &mgr.channels.ktrace } }
					else { unsafe { &mgr.channels.stats } }
				}
				unsafe {
					*rx = channel.new_rx_channel('test', 1, u64(&header), 2, u64(&ring), 4, 8)
					receive_owner = &mgr
				}
				if order == 1 {
					klock.on_next_acquire(unsafe { &mgr.lock }, stop_receive_owner)
				} else {
					katomic.on_next_sync(require_receive_lock)
					if order == 2 {
						klock.on_next_release(unsafe { &mgr.lock }, stop_receive_owner)
					}
				}
				mut value := u64(0)
				assert mgr.dequeue_g13_rx(mut rx, unsafe { &value }) == (order != 1)
				assert !mgr.lock.is_held()
				if order == 1 {
					assert value == 0 && header.read_ptr == 0
				} else {
					assert value == ring[0] && header.read_ptr == 1
				}
				if order != 0 {
					assert mgr.state == .stopped
					assert !mgr.dequeue_g13_rx(mut rx, unsafe { &value })
					mgr.mark_g13_worker_error()
					assert mgr.state == .stopped
					mgr.shutdown()
					assert_failed(&mgr)
					assert header.read_ptr == if order == 1 { u32(0) } else { u32(1) }
				}
				receive_owner = unsafe { nil }
			}
		}
		for tag in [fw.fw_event_fault, fw.fw_event_timeout, fw.fw_event_channel_error]! {
			mut header := channel.RingHeader{write_ptr: 2}
			mut ring := [4]fw.FwEventMsg{}
			ring[0].tag = tag
			ring[1].tag = fw.fw_event_grow_tvb
			mut mgr := GpuManager{hw_config: hw.HwConfig{gpu_gen: .g13, firmware_abi: abi}}
			mgr.channels.event = channel.new_rx_channel('event', 1, u64(unsafe { &header }), 2, u64(unsafe { &ring }), 4, 0x38)
			receive_owner = unsafe { &mgr }
			klock.on_next_release(unsafe { &mgr.lock }, stop_receive_owner)
			mgr.handle_event()
			assert_failed(&mgr)
			assert header.read_ptr == 1 && mgr.grows == 0
			receive_owner = unsafe { nil }
		}
		mut header := channel.RingHeader{write_ptr: 1}
		mut ring := [4]fw.FwEventMsg{}
		ring[0].tag = fw.fw_event_grow_tvb
		ring[0].payload[0] = 31
		ring[0].payload[1] = 9
		ring[0].payload[2] = 0x81234567
		mut mgr := GpuManager{hw_config: hw.HwConfig{gpu_gen: .g13, firmware_abi: abi}}
		mgr.channels.event = channel.new_rx_channel('event', 1, u64(unsafe { &header }), 2, u64(unsafe { &ring }), 4, 0x38)
		receive_owner = unsafe { &mgr }
		reused_event = unsafe { &ring[0] }
		katomic.on_next_sync(reuse_event_record)
		mgr.handle_event()
		assert mgr.grows == 1 && mgr.last_growth == [u32(31), 9, 0x81234567]!
		assert header.read_ptr == 1 && ring[0].tag == fw.fw_event_fault
		receive_owner = unsafe { nil }
		reused_event = unsafe { nil }
	}
	println('G13 receive shutdown: 18 ring interleavings, six stale fatal events and two TVB payload snapshots passed')
}

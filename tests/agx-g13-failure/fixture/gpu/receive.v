// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module gpu

import apple.mailbox
import apple.rtkit
import gpu.agx.channel
import gpu.agx.fw
import gpu.agx.hw
import katomic
import klock

__global receive_owner = unsafe { &GpuManager(nil) }
__global reused_event = unsafe { &fw.FwEventMsg(nil) }
__global receive_order = unsafe { &ReceiveOrder(nil) }

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

struct ReceiveOrder {
mut:
	headers [4]channel.RingHeader
	acknowledgements int
}

fn observe_receive_order() {
	require_receive_lock()
	assert receive_owner.rtk.iop_power_state == 0, 'a later RTKit message overtook the doorbell'
	for index, header in receive_order.headers {
		expected := if index < receive_order.acknowledgements { u32(1) } else { u32(0) }
		assert header.read_ptr == expected, 'unexpected receive ring acknowledgement order'
	}
	receive_order.acknowledgements++
	if receive_order.acknowledgements < 4 {
		katomic.on_next_sync(observe_receive_order)
	}
}

enum ReceiveOrderCase {
	doorbell
	fatal_doorbell
	fallback
	fatal_fallback
	invalid_doorbell
}

fn check_g13_receive_order() {
	for abi in [hw.FirmwareAbi.v12_3, .v13_5_partial]! {
		for scenario in [ReceiveOrderCase.doorbell, .fatal_doorbell, .fallback,
			.fatal_fallback, .invalid_doorbell]! {
			check_g13_receive_order_case(abi, scenario)
		}
	}
	println('G13 receive order: 10 doorbell and fallback transcripts across both ABIs')
}

fn check_g13_receive_order_case(abi hw.FirmwareAbi, scenario ReceiveOrderCase) {
	fatal := scenario in [.fatal_doorbell, .fatal_fallback]!
	mut order := ReceiveOrder{headers: [channel.RingHeader{write_ptr: 1},
		channel.RingHeader{write_ptr: 1}, channel.RingHeader{write_ptr: 1},
		channel.RingHeader{write_ptr: if fatal { u32(2) } else { u32(1) }}]!}
	mut log_payloads := []fw.FwLogPayload{len: 6 * 256}
	defer { unsafe { log_payloads.free() } }
	log_payloads[0] = fw.FwLogPayload{msg_type: 3}
	log_payloads[0].message[0] = `D`
	log_ring := [fw.FwLogMsg{msg_type: 2}, fw.FwLogMsg{}]!
	aux_ring := [u64(0x1234), 0]!
	event_ring := [fw.FwEventMsg{tag: if fatal { fw.fw_event_fault } else { fw.fw_event_grow_tvb }},
		fw.FwEventMsg{tag: fw.fw_event_grow_tvb}, fw.FwEventMsg{}]!
	mut graph := G13ChannelAllocations{
		fwlog_payload: SharedBuffer{phys: u64(log_payloads.data), size: fw.g13_fw_log_payload_size}
	}
	mut transport := rtkit.RTKit{name: 'g13-doorbell'}
	mut mgr := GpuManager{
		hw_config: hw.HwConfig{gpu_gen: .g13, firmware_abi: abi}
		g13_channels: unsafe { &graph }
		rtk: unsafe { &transport }
	}
	mgr.channels.fw_log = channel.new_rx_channel('fwlog', 1, u64(unsafe { &order.headers[0] }),
		2, u64(unsafe { &log_ring }), 2, 0x38)
	mgr.channels.ktrace = channel.new_rx_channel('ktrace', 1, u64(unsafe { &order.headers[1] }),
		2, u64(unsafe { &aux_ring }), 2, 8)
	mgr.channels.stats = channel.new_rx_channel('stats', 1, u64(unsafe { &order.headers[2] }),
		2, u64(unsafe { &aux_ring }), 2, 8)
	mgr.channels.event = channel.new_rx_channel('event', 1, u64(unsafe { &order.headers[3] }),
		2, u64(unsafe { &event_ring }), 3, 0x38)
	receive_owner = unsafe { &mgr }
	receive_order = unsafe { &order }
	katomic.on_next_sync(observe_receive_order)
	ack := mailbox.MboxMsg{data0: 0x0070000000000020}
	if scenario in [.doorbell, .fatal_doorbell]! {
		doorbell := mailbox.MboxMsg{data0: msg_rx_doorbell, data1: ep_firmware}
		transport.mbox.inject(doorbell)
		transport.mbox.inject(doorbell)
		transport.mbox.inject(ack)
		assert mgr.checked_poll_rtkit_messages()
		assert order.acknowledgements == 4
		if fatal {
			assert mgr.state == .error && transport.iop_power_state == 0
			next := transport.recv_msg() or { panic('missing queued doorbell') }
			later_ack := transport.recv_msg() or { panic('missing queued IOP acknowledgement') }
			assert next == doorbell && later_ack == ack
		} else {
			assert mgr.state == .running && transport.iop_power_state == 0x20
		}
	} else if scenario == .invalid_doorbell {
		transport.mbox.inject(mailbox.MboxMsg{data0: msg_rx_doorbell, data1: 0x21})
		transport.mbox.inject(mailbox.MboxMsg{data0: msg_rx_doorbell | 1, data1: ep_firmware})
		assert mgr.checked_poll_rtkit_messages()
		assert order.acknowledgements == 0
	}
	event_worker(mut mgr)
	for header in order.headers {
		assert header.read_ptr == 1
	}
	assert order.acknowledgements == 4 && !mgr.lock.is_held()
	if fatal {
		assert mgr.grows == 0
		assert_failed(&mgr)
	} else {
		assert mgr.grows == 1
	}
	receive_order = unsafe { nil }
	receive_owner = unsafe { nil }
}

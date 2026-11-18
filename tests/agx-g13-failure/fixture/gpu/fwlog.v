// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module gpu

import gpu.agx.channel
import gpu.agx.fw
import gpu.agx.hw
import gpu.agx.pgtable
import katomic

__global reused_log_payload = unsafe { &fw.FwLogPayload(nil) }

fn reuse_log_payload() {
	reused_log_payload.sequence = 0
	reused_log_payload.message[0] = 0
}

fn check_fw_log() {
	assert sizeof(fw.FwLogMsg) == 0x38 && __offsetof(fw.FwLogMsg, msg_index) == 0x8
	assert sizeof(fw.FwLogPayload) == 0xd8 && __offsetof(fw.FwLogPayload, message) == 0x10
	assert fw.g13_fw_log_payload_size == 0x51000
	for abi in [hw.FirmwareAbi.v12_3, .v13_5_partial]! {
		mut states := [6]channel.RingHeader{}
		mut ring := []fw.FwLogMsg{len: 6 * 256}
		mut texts := []fw.FwLogPayload{len: 6 * 256}
		defer {
			unsafe { ring.free(); texts.free() }
		}
		mut graph := G13ChannelAllocations{
			fwlog_payload: SharedBuffer{phys: u64(texts.data), size: 0x51000}
		}
		mut mgr := GpuManager{
			hw_config: hw.HwConfig{gpu_gen: .g13, firmware_abi: abi}
			g13_channels: unsafe { &graph }
		}
		mgr.channels.fw_log = channel.new_rx_channel_with_subchannels('log',
			1, u64(unsafe { &states }), 2, u64(ring.data), 256, 0x38, 6)
		for subchannel := u32(0); subchannel < 6; subchannel++ {
			base := subchannel * 256
			states[subchannel].read_ptr = 255
			states[subchannel].write_ptr = 1
			ring[base + 255] = fw.FwLogMsg{msg_type: 2, msg_index: 0}
			ring[base] = fw.FwLogMsg{msg_type: 2, msg_index: 255}
			texts[base] = fw.FwLogPayload{msg_type: 3, sequence: base + 1, timestamp: 10}
			texts[base].message[0] = u8(65 + subchannel)
			texts[base + 255] = fw.FwLogPayload{msg_type: 3, sequence: base + 256, timestamp: 20}
			reused_log_payload = unsafe { &texts[base] }
			katomic.on_next_sync(reuse_log_payload)
			copied := mgr.read_g13_fw_log(subchannel) or { panic('missing first payload') }
			assert states[subchannel].read_ptr == 0 && texts[base].sequence == 0
			assert copied.sequence == base + 1 && copied.timestamp == 10
			assert copied.message[0] == u8(65 + subchannel)
			last := mgr.read_g13_fw_log(subchannel) or { panic('missing wrapped payload') }
			assert states[subchannel].read_ptr == 1 && last.sequence == base + 256 && last.timestamp == 20
			assert mgr.read_g13_fw_log(subchannel) == none
			reused_log_payload = unsafe { nil }
		}
		for index, desc in [fw.FwLogMsg{msg_type: 3, msg_index: 0},
			fw.FwLogMsg{msg_type: 2, msg_index: 256}, fw.FwLogMsg{msg_type: 2, msg_index: ~u64(0)}]! {
			ring[1 + index] = desc
			states[0].write_ptr = u32(2 + index)
			copied := mgr.read_g13_fw_log(0) or { panic('descriptor was not consumed') }
			assert copied.msg_type == 0
			assert states[0].read_ptr == u32(2 + index) && !mgr.channels.fw_log.has_fault()
		}
		ring[4] = fw.FwLogMsg{msg_type: 2}
		states[0].write_ptr = 5
		graph.fwlog_payload.size--
		assert mgr.read_g13_fw_log(0) == none && states[0].read_ptr == 4
		graph.fwlog_payload.size++
		mgr.state = .stopped
		assert mgr.read_g13_fw_log(0) == none && states[0].read_ptr == 4
		mgr.state = .running
		assert mgr.read_g13_fw_log(6) == none
		states[0].write_ptr = 4
		states[5].write_ptr = ~u32(0)
		event_worker(mut mgr)
		assert_failed(&mgr)
		assert states[5].read_ptr == 1 && mgr.channels.fw_log.has_fault()
	}
	mut valid := fw.FwLogPayload{msg_type: 3}
	valid.message[0] = 90
	print_g13_fw_log(4, valid)
	print_g13_fw_log(4, fw.FwLogPayload{msg_type: 3, message: [0xc8]u8{init: 0x58}})
	print_g13_fw_log(4, fw.FwLogPayload{msg_type: 2})
	println('G13 firmware log: 24 payloads survived descriptor wrap and immediate reuse, with bounds and fault checks on both ABIs')
}

struct ChannelTestHeap {}
fn (mut _ ChannelTestHeap) gc() {}

struct ChannelTestUat {}
fn (_ &ChannelTestUat) unmap_kernel(_ u64, _ u64) { panic('unexpected auxiliary unmap') }

__global uat_mgr = unsafe { &ChannelTestUat(nil) }

struct ChannelAllocProbe {
mut:
	fail_at int = -1
	calls int
	live int
	protections [37]u64
	sizes [37]u64
	headers [37]channel.RingHeader
}

fn (mut mgr GpuManager) alloc_g13_buffer_with_protection(size u64, protection u64) ?SharedBuffer {
	mut probe := &mgr.channel_alloc
	at := probe.calls
	probe.calls++
	if at == probe.fail_at { return none }
	probe.live++
	probe.sizes[at] = size
	probe.protections[at] = protection
	return SharedBuffer{phys: unsafe { u64(&probe.headers[at]) }, va: u64(at + 1) << 16, size: size}
}

fn (mut mgr GpuManager) free_shared_buffer(mut buffer SharedBuffer) {
	if buffer.phys == 0 { return }
	if buffer.allocator == buffer_allocator_g13_rtkit {
		assert mgr.rtkit_buffer_lock.is_held()
		unsafe { C.free(voidptr(buffer.phys)) }
		buffer = SharedBuffer{}
		return
	}
	mut probe := &mgr.channel_alloc
	at := int(buffer.va >> 16) - 1
	assert probe.sizes[at] == buffer.size && probe.sizes[at] != 0
	probe.sizes[at] = 0
	probe.live--
	buffer = SharedBuffer{}
}

fn check_fw_log_allocations() {
	for abi in [hw.FirmwareAbi.v12_3, .v13_5_partial]! {
		for fail_at in 0 .. 37 {
			mut mgr := GpuManager{
				hw_config: hw.HwConfig{gpu_gen: .g13, firmware_abi: abi}
				channel_alloc: ChannelAllocProbe{fail_at: fail_at}
			}
			assert !mgr.init_channels() && mgr.g13_channels == unsafe { nil }
			assert mgr.channel_alloc.calls == fail_at + 1 && mgr.channel_alloc.live == 0
		}
		mut mgr := GpuManager{hw_config: hw.HwConfig{gpu_gen: .g13, firmware_abi: abi}}
		assert mgr.init_channels()
		assert mgr.channel_alloc.calls == 37 && mgr.channel_alloc.live == 37
		assert mgr.channels.fw_log.entry_size == 0x38 && mgr.channels.fw_log.ring_size == 256
		assert mgr.channels.fw_log.subchannels == 6
		assert mgr.channel_alloc.sizes[6] == 6 * 0x30 && mgr.channel_alloc.sizes[7] == 6 * 256 * 0x38
		assert mgr.channel_alloc.sizes[36] == 0x51000
		assert mgr.channel_alloc.protections[7] == pgtable.gpu_prot_fw_shared_rw
		assert mgr.channel_alloc.protections[36] == pgtable.gpu_prot_fw_shared_rw
		assert mgr.g13_channels.fwlog_payload.va != mgr.channels.fw_log.ring_base
		mgr.lock.acquire()
		mgr.checked_release_g13_channels()
		mgr.checked_release_g13_channels()
		mgr.lock.release()
		assert mgr.channel_alloc.live == 0 && mgr.g13_channels == unsafe { nil }
		assert mgr.channels.fw_log.ring_phys == 0
	}
	println('G13 firmware log ownership: 74 failed allocations and two complete releases drain all owners')
}

// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_fwlog_reference(channel string, wire string, manager string) ! {
	descriptor := section(wire, 'pub(crate) struct RawFwLogMsg {', 'pub(crate) struct RawFwLogPayloadMsg {', 'Asahi log descriptor')!
	require_order(descriptor, ['msg_type: u32', '__pad0: u32', 'msg_index: U64', '__pad1: Pad<0x28>'], 'Asahi 0x38-byte descriptors')!
	payload := section(wire, 'pub(crate) struct RawFwLogPayloadMsg {', 'pub(crate) struct RawKTraceMsg {', 'Asahi log payload')!
	require_order(payload, ['msg_type: u32', 'seq_no: u32', 'timestamp: U64', 'msg: Array<0xc8, u8>'], 'Asahi 0xd8-byte payloads')!
	require(wire.contains('impl RxChannelState for FwLogChannelState {\n    const SUB_CHANNELS: usize = 6;'),
		'Asahi log channel has six state records')!
	log := section(channel, 'impl FwLogChannel {', 'pub(crate) struct KTraceChannel', 'Asahi log polling')!
	require_order(log, ['const RING_SIZE: usize = 0x100', 'const BUF_SIZE: usize = 0x100',
		'RxChannel::<FwLogChannelState, RawFwLogMsg>::new(alloc, Self::RING_SIZE)',
		'.array_empty(Self::BUF_SIZE * FwLogChannelState::SUB_CHANNELS)',
		'while let Some(msg) = self.ch.peek(i)', 'if msg.msg_type != 2',
		'if msg.msg_index.0 as usize >= Self::BUF_SIZE', 'Self::BUF_SIZE * i + msg.msg_index.0 as usize',
		'&self.payload_buf.as_slice()[index]', 'if payload.msg_type != 3',
		'payload.msg.iter().position(|&r| r == 0)', 'self.ch.get(i);'],
		'Asahi has separate descriptor and payload storage and reads before acknowledging')!
	require_order(manager, ['let p_fw_log = rxc.fw_log.to_raw()', 'let p_fwlog_buf = rxc.fw_log.get_buf()',
		'raw.fw_log = p_fw_log', 'raw.fwlog_buf = Some(p_fwlog_buf)'], 'Asahi publishes distinct firmware log addresses')!
}

fn check_fwlog_vinix(manager string, channel string, wire string) ! {
	owner := section(manager, 'fn (mut mgr GpuManager) free_g13_channel_allocations(', 'fn (mut mgr GpuManager) fail_g13_initialization(', 'Vinix log backing')!
	require_order(owner, ['mgr.free_shared_buffer(mut allocations.fwlog_payload)',
		'mgr.channels = GpuChannels{}', 'mgr.g13_channels = unsafe { nil }',
		'mgr.free_g13_channel_allocations(mut allocations)', 'unsafe { free(allocations) }'],
		'Vinix clears published channel pointers and returns all backing when releasing the graph')!
	require_order(owner, ['defer {', 'if !complete', 'mgr.free_g13_channel_allocations(mut allocations)',
		'unsafe { free(allocations) }', 'log_count * fw.fw_log_size * sizeof(fw.FwLogMsg)',
		'allocations.fwlog_payload = mgr.alloc_g13_shared_buffer(fw.g13_fw_log_payload_size)',
		'complete = true', 'mgr.g13_channels = allocations'],
		'Vinix allocates and owns both buffers before publishing the log channel')!
	require_order(manager, ['runtime.fw_log = fw.make_g13_ring_pointers(mgr.channels.fw_log.state_base, mgr.channels.fw_log.ring_base)',
		'runtime.fwlog_buffer = graph.fwlog_payload.va'], 'Vinix publishes distinct firmware log addresses')!
	require_order(wire, ['pub const fw_log_size = u32(256)', 'pub const fw_log_subchannels = u32(6)',
		'descriptor.msg_type != 2 || subchannel >= fw_log_subchannels || descriptor.msg_index >= fw_log_size',
		'(u64(subchannel) * fw_log_size + descriptor.msg_index) * sizeof(FwLogPayload)',
		'sizeof(FwLogMsg) == 0x38 && sizeof(FwLogPayload) == 0xd8'], 'Vinix validates wire widths and payload indexing')!
	log := section(manager, 'fn (mut mgr GpuManager) read_g13_fw_log(', '// Caller holds mgr.lock. A queued fault', 'Vinix log polling')!
	require_order(log, ['mgr.lock.acquire()', 'defer { mgr.lock.release() }', 'mgr.g13_channels == unsafe { nil }',
		'buffer.size < fw.g13_fw_log_payload_size', 'fw_log.peek_subchannel(', 'g13_fw_log_payload_offset(',
		'*&fw.FwLogPayload(u64(buffer.cpu_address()) + offset)', 'fw_log.dequeue_subchannel(', 'return payload',
		'if payload.msg_type == 3', 'if payload.message[index] == 0',
		'if subchannel == 0 { return false }', 'payload := mgr.read_g13_fw_log(subchannel) or { break }',
		'_ = print_g13_fw_log(subchannel, payload)'],
		'Vinix snapshots payloads under the teardown lock before acknowledging and printing')!
	rx := section(channel, 'fn (mut ch RxChannel) read_subchannel(', '// Check if the transmit', 'Vinix log ring')!
	require_order(rx, ['rp >= ch.ring_size || wp >= ch.ring_size', 'katomic.store(mut &ch.faulted',
		'C.memcpy(data, src, ch.entry_size)', 'if consume', 'katomic.sync()', 'katomic.store(mut read_ptr'],
		'Vinix retains sticky pointer errors and acknowledges only after copying')!
}

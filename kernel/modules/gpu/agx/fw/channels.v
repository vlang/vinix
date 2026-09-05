module fw

// Firmware channel state structures
// Defines the shared memory layout for ring buffer channels
// Translates fw channel structures from the Asahi Linux GPU driver

// G13 v12.3 EventMsg discriminants.
pub const fw_event_fault = u32(0)
pub const fw_event_flag = u32(1)
pub const fw_event_timeout = u32(4)
pub const fw_event_grow_tvb = u32(7)

// Channel sizes (number of entries)
pub const device_control_size = u32(256)
pub const event_size = u32(256)
pub const fw_ctl_size = u32(256)
pub const fw_log_size = u32(256)
pub const ktrace_size = u32(512)
pub const stats_size = u32(256)
pub const pipe_size = u32(256)

// G13 v12.3 generic channel state. Keep this duplicate definition in sync
// with channel.RingHeader until all raw firmware types live in one module.
@[packed]
pub struct FwChannelState {
pub mut:
	read_ptr  u32
	pad_04    [7]u32
	write_ptr u32
	pad_24    [3]u32
}

@[packed]
pub struct FwCtlChannelState {
pub mut:
	read_ptr  u32
	pad_04    [3]u32
	write_ptr u32
	pad_14    [3]u32
}

@[packed]
pub struct ChannelRingPointers {
pub:
	state u64
	ring  u64
}

// G13 v12.3 device-control messages are a 32-bit discriminant followed by a
// fixed 0x2c-byte payload. Initialize (0x19) carries an all-zero payload.
pub const device_control_initialize = u32(0x19)

@[packed]
pub struct FwDeviceControlMsg {
pub mut:
	tag     u32
	payload [11]u32
}

pub fn make_device_control_initialize() FwDeviceControlMsg {
	return FwDeviceControlMsg{
		tag: device_control_initialize
	}
}

// Pipe channels carry a request to run a separately allocated firmware work
// queue; they never contain a vertex/fragment/compute command inline.
@[packed]
pub struct FwRunWorkQueueMsg {
pub mut:
	pipe_type       u32
	pad_04          u32
	work_queue_addr u64
	write_ptr       u32
	event_slot      u32
	is_new          u8
	pad_19          [31]u8
}

// Event channel message
@[packed]
pub struct FwEventMsg {
pub mut:
	tag     u32
	payload [13]u32
}

// Firmware control channel message
@[packed]
pub struct FwFwCtlMsg {
pub mut:
	addr       u64
	unk_8      u32
	slot       u32
	page_count u16
	unk_12     u16
}

// Firmware log channel message
@[packed]
pub struct FwLogMsg {
pub mut:
	msg_type  u32
	pad_04    u32
	msg_index u64
	pad_10    [40]u8
}

// Kernel trace channel message
@[packed]
pub struct FwKTraceMsg {
pub mut:
	msg_type  u32
	pad_04    u32
	timestamp u64
	args      [4]u64
	code      u8
	channel   u8
	pad_32    u8
	thread    u8
	pad_34    [4]u8
	unk_flag  u64
}

// Stats channel message
@[packed]
pub struct FwStatsMsg {
pub mut:
	tag     u32
	payload [11]u32
}

// Validate only the channel envelopes already ported from the G13 v12.3
// source. This is intentionally distinct from the full-ABI boot gate.
pub fn validate_g13_channel_layouts() bool {
	return sizeof(FwChannelState) == 0x30 && sizeof(FwCtlChannelState) == 0x20
		&& sizeof(ChannelRingPointers) == 0x10 && sizeof(FwDeviceControlMsg) == 0x30
		&& sizeof(FwRunWorkQueueMsg) == 0x38 && sizeof(FwEventMsg) == 0x38
		&& sizeof(FwFwCtlMsg) == 0x14 && sizeof(FwLogMsg) == 0x38
		&& sizeof(FwKTraceMsg) == 0x40 && sizeof(FwStatsMsg) == 0x30
}

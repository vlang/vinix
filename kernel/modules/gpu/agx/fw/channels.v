module fw

// Firmware channel state structures
// Defines the shared memory layout for ring buffer channels
// Translates fw channel structures from the Asahi Linux GPU driver

// Event types
pub const fw_event_init = u32(0)
pub const fw_event_device_ctrl_ack = u32(1)
pub const fw_event_vertex_done = u32(2)
pub const fw_event_fragment_done = u32(3)
pub const fw_event_compute_done = u32(4)
pub const fw_event_error = u32(5)
pub const fw_event_timeout = u32(6)
pub const fw_event_stamp = u32(7)

// Channel sizes (number of entries)
pub const device_control_size = u32(256)
pub const event_size = u32(256)
pub const fw_ctl_size = u32(64)
pub const fw_log_size = u32(256)
pub const ktrace_size = u32(256)
pub const stats_size = u32(64)
pub const pipe_size = u32(256)

// Channel state (ring buffer header in shared memory)
@[packed]
pub struct FwChannelState {
pub mut:
	write_ptr u32
	pad0      [15]u32
	read_ptr  u32
	pad1      [15]u32
}

// Device control channel message
@[packed]
pub struct FwDeviceControlMsg {
pub mut:
	tag      u32
	unk_4    u32
	msg_type u32
	data     u64
	pad      [5]u32
}

// Event channel message
@[packed]
pub struct FwEventMsg {
pub mut:
	tag        u32
	event_type u32
	data       [6]u32
}

// Firmware control channel message
@[packed]
pub struct FwFwCtlMsg {
pub mut:
	tag      u32
	msg_type u32
	param    u64
	pad      [4]u32
}

// Firmware log channel message
@[packed]
pub struct FwLogMsg {
pub mut:
	timestamp u64
	msg       [224]u8
}

// Kernel trace channel message
@[packed]
pub struct FwKTraceMsg {
pub mut:
	timestamp u64
	event_id  u32
	arg0      u64
	arg1      u64
	pad       u32
}

// Stats channel message
@[packed]
pub struct FwStatsMsg {
pub mut:
	timestamp u64
	data      [28]u32
}

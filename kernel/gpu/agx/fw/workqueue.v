module fw

// Firmware workqueue structures recovered from the v12.3 Asahi ABI.

// G13 v12.3 firmware work-command discriminants. Blitter occupies slot 2;
// compute must therefore be 3 (the previous sketch incorrectly used 2).
pub const cmd_type_run_vertex = u32(0x00)
pub const cmd_type_run_fragment = u32(0x01)
pub const cmd_type_run_blitter = u32(0x02)
pub const cmd_type_run_compute = u32(0x03)
pub const cmd_type_barrier = u32(0x04)
pub const cmd_type_init_buffer = u32(0x06)

pub const g13_workqueue_entries = u32(0x500)
pub const g13_gpu_buffer_size = u64(0x2c18)

// Work error codes
pub const work_err_none = u32(0)
pub const work_err_timeout = u32(1)
pub const work_err_fault = u32(2)
pub const work_err_killed = u32(3)
pub const work_err_channel_error = u32(4)

// The actual v12.3 queue state is seven cache-line-separated words. Firmware
// owns the read/done pointers while the host publishes cpu_wptr and
// cpu_freeptr with release ordering.
@[packed]
pub struct G13WorkQueueRingState {
pub mut:
	gpu_doneptr u32
	pad_04      [3]u32
	unk_10      u32
	pad_14      [3]u32
	unk_20      u32
	pad_24      [3]u32
	gpu_rptr    u32
	pad_34      [3]u32
	cpu_wptr    u32
	pad_44      [3]u32
	rb_size     u32
	pad_54      [3]u32
	cpu_freeptr u32
	pad_64      [3]u32
}

@[packed]
pub struct G13WorkQueuePriority {
pub mut:
	value_0 u32
	value_4 u32
	mask    u64
	value_10 u32
	value_14 u32
	value_18 u32
}

// QueueInfo for G13 + macOS 12.3. Every pointer is a canonical firmware IOVA,
// not a CPU physical address.
@[packed]
pub struct G13WorkQueueInfo {
pub mut:
	state         u64
	ring          u64
	notifier_list u64
	gpu_buffer    u64
	gpu_rptr_1    u32
	gpu_rptr_2    u32
	gpu_rptr_3    u32
	event_id      i32
	priority      G13WorkQueuePriority
	unk_4c        i32
	uuid          u32
	unk_54        i32
	unk_58        u64
	busy          u32
	pad_64        [0x20]u8
	unk_84        u32
	unk_88        u32
	unk_8c        u32
	unk_90        u32
	unk_94        u32
	pending       u32
	unk_9c        u32
	gpu_context   u64
	unk_a8        u64
}

@[packed]
pub struct G13GpuContextData {
pub mut:
	data [0x40]u8
}

@[packed]
pub struct G13BarrierCommand {
pub mut:
	tag          u32
	wait_stamp   u64
	wait_value   u32
	wait_slot    u32
	stamp_self   u32
	uuid         u32
	barrier_type u32
	padding      [0x20]u8
}

pub fn g13_workqueue_priority(priority u32) ?G13WorkQueuePriority {
	return match priority {
		0 {
			G13WorkQueuePriority{
				value_0: 0
				value_4: 0
				mask: u64(0xffffffffffff0000)
				value_10: 1
				value_14: 0
				value_18: 1
			}
		}
		1 {
			G13WorkQueuePriority{
				value_0: 1
				value_4: 1
				mask: u64(0xffffffff00000000)
				value_18: 0
			}
		}
		2 {
			G13WorkQueuePriority{
				value_0: 2
				value_4: 2
				mask: u64(0xffff000000000000)
				value_18: 2
			}
		}
		3 {
			G13WorkQueuePriority{
				value_0: 3
				value_4: 3
				value_18: 3
			}
		}
		else { none }
	}
}

pub fn initialize_g13_gpu_context(data voidptr, size u64) bool {
	if data == unsafe { nil } || size < sizeof(G13GpuContextData) {
		return false
	}
	unsafe {
		C.memset(data, 0, sizeof(G13GpuContextData))
		mut context := &G13GpuContextData(data)
		context.data[0] = 0xff
		context.data[1] = 0xff
		context.data[5] = 1
		context.data[0x1e] = 0xff
		context.data[0x23] = 2
	}
	return true
}

pub fn validate_g13_workqueue_layouts() bool {
	return sizeof(G13WorkQueueRingState) == 0x70
		&& sizeof(G13WorkQueuePriority) == 0x1c
		&& sizeof(G13WorkQueueInfo) == 0xb0
		&& sizeof(G13GpuContextData) == 0x40
		&& sizeof(G13BarrierCommand) == 0x40
}

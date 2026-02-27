module fw

// GPU microsequence (command stream) structures
// The microsequence is a small program embedded in shared memory that
// the GPU firmware interprets to orchestrate work execution. Each
// operation is a packed struct prefixed by a MicroseqHeader. The
// firmware walks the sequence linearly, executing each op until it
// reaches an End op.

// Microsequence opcodes
pub const useq_op_wait_stamp = u32(0x01)
pub const useq_op_set_stamp = u32(0x02)
pub const useq_op_run_vertex = u32(0x03)
pub const useq_op_run_fragment = u32(0x04)
pub const useq_op_run_compute = u32(0x05)
pub const useq_op_barrier = u32(0x06)
pub const useq_op_timestamp = u32(0x07)
pub const useq_op_end = u32(0x18)

@[packed]
pub struct MicroseqHeader {
pub mut:
	opcode u32
	size   u32
	next   u64
}

@[packed]
pub struct MicroseqWaitStamp {
pub mut:
	header      MicroseqHeader
	stamp_addr  u64
	stamp_value u32
	pad         u32
}

@[packed]
pub struct MicroseqSetStamp {
pub mut:
	header      MicroseqHeader
	stamp_addr  u64
	stamp_value u32
	pad         u32
}

@[packed]
pub struct MicroseqRunVertex {
pub mut:
	header   MicroseqHeader
	cmd_addr u64
	unk_10   u64
}

@[packed]
pub struct MicroseqRunFragment {
pub mut:
	header   MicroseqHeader
	cmd_addr u64
	unk_10   u64
}

@[packed]
pub struct MicroseqRunCompute {
pub mut:
	header   MicroseqHeader
	cmd_addr u64
	unk_10   u64
}

@[packed]
pub struct MicroseqBarrier {
pub mut:
	header MicroseqHeader
}

@[packed]
pub struct MicroseqTimestamp {
pub mut:
	header      MicroseqHeader
	stamp_addr  u64
	stamp_value u32
	pad         u32
}

@[packed]
pub struct MicroseqEnd {
pub mut:
	header MicroseqHeader
}

// --- Builder helpers ---
// These functions construct individual microsequence operations with
// the correct opcode and size fields pre-filled.

// Build a wait-stamp operation that blocks until the given stamp
// address contains a value >= stamp_value.
pub fn build_wait_stamp(stamp_addr u64, stamp_value u32) MicroseqWaitStamp {
	return MicroseqWaitStamp{
		header: MicroseqHeader{
			opcode: useq_op_wait_stamp
			size:   u32(sizeof(MicroseqWaitStamp))
		}
		stamp_addr:  stamp_addr
		stamp_value: stamp_value
	}
}

// Build a set-stamp operation that writes stamp_value to the given
// stamp address, signaling completion to waiters.
pub fn build_set_stamp(stamp_addr u64, stamp_value u32) MicroseqSetStamp {
	return MicroseqSetStamp{
		header: MicroseqHeader{
			opcode: useq_op_set_stamp
			size:   u32(sizeof(MicroseqSetStamp))
		}
		stamp_addr:  stamp_addr
		stamp_value: stamp_value
	}
}

// Build a run-vertex operation that dispatches a vertex command
// located at cmd_addr.
pub fn build_run_vertex(cmd_addr u64) MicroseqRunVertex {
	return MicroseqRunVertex{
		header: MicroseqHeader{
			opcode: useq_op_run_vertex
			size:   u32(sizeof(MicroseqRunVertex))
		}
		cmd_addr: cmd_addr
	}
}

// Build a run-fragment operation that dispatches a fragment command
// located at cmd_addr.
pub fn build_run_fragment(cmd_addr u64) MicroseqRunFragment {
	return MicroseqRunFragment{
		header: MicroseqHeader{
			opcode: useq_op_run_fragment
			size:   u32(sizeof(MicroseqRunFragment))
		}
		cmd_addr: cmd_addr
	}
}

// Build a run-compute operation that dispatches a compute command
// located at cmd_addr.
pub fn build_run_compute(cmd_addr u64) MicroseqRunCompute {
	return MicroseqRunCompute{
		header: MicroseqHeader{
			opcode: useq_op_run_compute
			size:   u32(sizeof(MicroseqRunCompute))
		}
		cmd_addr: cmd_addr
	}
}

// Build a barrier operation that forces all preceding operations
// to complete before subsequent ones begin.
pub fn build_barrier() MicroseqBarrier {
	return MicroseqBarrier{
		header: MicroseqHeader{
			opcode: useq_op_barrier
			size:   u32(sizeof(MicroseqBarrier))
		}
	}
}

// Build an end operation that terminates the microsequence.
pub fn build_end() MicroseqEnd {
	return MicroseqEnd{
		header: MicroseqHeader{
			opcode: useq_op_end
			size:   u32(sizeof(MicroseqEnd))
		}
	}
}

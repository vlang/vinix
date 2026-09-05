module fw

// Exact outer layouts for the macOS 12.3 G13 firmware object graph. The global
// configuration body and native work commands are still incomplete, so these
// structures do not make the v12.3_partial ABI safe to boot by themselves.

pub const g13_runtime_pointers_size = u64(0x6bc0)
pub const g13_globals_size = u64(0x11d40)
pub const g13_initdata_size = u64(0xb4)
pub const g13_fwlog_subchannels = u32(6)
pub const g13_fwlog_payload_count = u32(0x100)

@[packed]
pub struct G13GlobalStatsVertex {
pub mut:
	total_commands u32
	opaque         [0x3000]u8
}

@[packed]
pub struct G13GlobalStatsFragment {
pub mut:
	total_commands u32
	unk_004        u32
	opaque_008     [0x100]u8
	current_stamp  i32
	opaque_10c     [0x14]u8
	unknown_id     i32
	opaque_124     [0x1000]u8
}

@[packed]
pub struct G13GlobalStatsCompute {
pub mut:
	opaque [0x3000]u8
}

@[packed]
pub struct G13PipeChannels {
pub mut:
	vertex   ChannelRingPointers
	fragment ChannelRingPointers
	compute  ChannelRingPointers
}

// The channel prefix is fully typed. The remaining pointer and scratch region
// retains its exact 12.3 size and key pointer slots without pretending the
// still-unknown hardware data is ready for firmware consumption.
@[packed]
pub struct G13RuntimePointers {
pub mut:
	pipes               [4]G13PipeChannels
	device_control      ChannelRingPointers
	event               ChannelRingPointers
	fw_log              ChannelRingPointers
	ktrace              ChannelRingPointers
	stats               ChannelRingPointers
	pad_110             [0x50]u8
	unk_160             u64
	unk_168             u64
	stats_vertex        u64
	stats_fragment      u64
	stats_compute       u64
	hwdata_a            u64
	unkptr_190          u64
	unkptr_198          u64
	hwdata_b            u64
	hwdata_b_2          u64
	fwlog_buffer        u64
	unkptr_1b8          u64
	unkptr_1c0          u64
	unkptr_1c8          u64
	unk_1d0             u32
	unk_1d4             u32
	unk_1d8             [0x3c]u8
	buffer_mgr_gpu_addr u64
	buffer_mgr_fw_addr  u64
	pad_224             [0x5c]u8
	gpu_scratch         [0x6940]u8
}

// Globals is much larger than its configuration prefix. Preserve the known
// prefix fields and the exact G13 v12.3 extent while the power model is ported.
@[packed]
pub struct G13Globals {
pub mut:
	ktrace_enable u32
	unk_004       [0x20]u8
	unk_024       u32
	unk_028       u32
	unk_02c       u32
	unk_030       u32
	unk_034       u32
	opaque_038    [0x11d08]u8
}

@[packed]
pub struct G13FwStatus {
pub mut:
	fwctl ChannelRingPointers
	flags [0x70]u8
}

@[packed]
pub struct G13UatLevelInfo {
pub mut:
	unk_3       u8
	unk_1       u8
	unk_2       u8
	index_shift u8
	num_entries u16
	unk_4       u16
	unk_8       u64
	unk_10      u64
	index_mask  u64
}

// V12.3 predates the four-u16 ver_info prefix used by later firmware.
@[packed]
pub struct G13InitData {
pub mut:
	unk_buffer                 u64
	unk_008                    u32
	unk_00c                    u32
	runtime_pointers           u64
	globals                    u64
	fw_status                  u64
	uat_page_size              u16
	uat_page_bits              u8
	uat_num_levels             u8
	uat_level_info             [3]G13UatLevelInfo
	pad_08c                    [0x14]u8
	host_mapped_fw_allocations u32
	unk_0a4                    u32
	unk_0a8                    u32
	unk_0ac                    u32
	unk_0b0                    u32
}

pub fn make_g13_ring_pointers(state u64, ring u64) ChannelRingPointers {
	return ChannelRingPointers{
		state: state
		ring: ring
	}
}

fn make_g13_uat_level_info(oas u32, index_shift u8, num_entries u16) G13UatLevelInfo {
	oas_mask := ((u64(1) << oas) - 1) & ~u64(0x3fff)
	return G13UatLevelInfo{
		unk_3: 8
		unk_1: 14
		unk_2: 14
		index_shift: index_shift
		num_entries: num_entries
		unk_4: 0x4000
		unk_8: 1
		unk_10: oas_mask
		index_mask: u64(num_entries - 1) << index_shift
	}
}

pub fn build_g13_initdata(unk_buffer u64, runtime_pointers u64, globals u64,
	fw_status u64, oas u32) ?G13InitData {
	if unk_buffer == 0 || runtime_pointers == 0 || globals == 0 || fw_status == 0
		|| oas < 14 || oas > 48 {
		return none
	}
	return G13InitData{
		unk_buffer: unk_buffer
		runtime_pointers: runtime_pointers
		globals: globals
		fw_status: fw_status
		uat_page_size: 0x4000
		uat_page_bits: 14
		uat_num_levels: 3
		uat_level_info: [make_g13_uat_level_info(oas, 36, 8), make_g13_uat_level_info(oas, 25, 2048),
			make_g13_uat_level_info(oas, 14, 2048)]!
		host_mapped_fw_allocations: 1
	}
}

pub fn validate_g13_initdata_layouts() bool {
	return sizeof(G13PipeChannels) == 0x30
		&& sizeof(G13RuntimePointers) == g13_runtime_pointers_size
		&& sizeof(G13Globals) == g13_globals_size && sizeof(G13FwStatus) == 0x80
		&& sizeof(G13UatLevelInfo) == 0x20 && sizeof(G13InitData) == g13_initdata_size
		&& sizeof(G13GlobalStatsVertex) == 0x3004
		&& sizeof(G13GlobalStatsFragment) == 0x1124
		&& sizeof(G13GlobalStatsCompute) == 0x3000
}

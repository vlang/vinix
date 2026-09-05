module fw

// Common G13/macOS 12.3 job records embedded in vertex, fragment, and compute
// work commands.

@[packed]
pub struct G13JobMeta {
pub mut:
	unk_0          u16
	unk_2          u8
	no_preemption  u8
	stamp          u64
	fw_stamp       u64
	stamp_value    u32
	stamp_slot     u32
	evctl_index    u32
	flush_stamps   u32
	uuid           u32
	event_sequence u32
}

@[packed]
pub struct G13EncoderParams {
pub mut:
	unk_8         u32
	sync_grow     u32
	unk_10        u32
	encoder_id    u32
	unk_18        u32
	unk_mask      u32
	sampler_array u64
	sampler_count u32
	sampler_max   u32
}

@[packed]
pub struct G13JobTimestamps {
pub mut:
	start u64
	end   u64
}

@[packed]
pub struct G13RenderTimestamps {
pub mut:
	vertex   G13JobTimestamps
	fragment G13JobTimestamps
}

pub fn validate_g13_job_layouts() bool {
	return sizeof(G13JobMeta) == 0x2c && sizeof(G13EncoderParams) == 0x28
		&& sizeof(G13JobTimestamps) == 0x10 && sizeof(G13RenderTimestamps) == 0x20
}

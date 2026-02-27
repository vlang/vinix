module fw

// Firmware InitData structure tree
// Massive initialization data structure that must be byte-perfect
// for firmware version 12.3.0 on M1 (t8103).
// Translates fw/initdata.rs from the Asahi Linux GPU driver

import gpu.agx.hw

// Top-level InitData structure
@[packed]
pub struct InitData {
pub mut:
	ver_info       [8]u32 // version info block
	unk_20         u64
	unk_28         u64
	region_a_addr  u64
	unk_38         u64
	region_b_addr  u64
	region_c_addr  u64
	fw_status_addr u64
	unk_58         u64
	unk_60         u64
	unk_68         u64
	unk_70         u64
	unk_78         u64
	unk_80         u64
	unk_88         u64
	unk_90         u64
	unk_98         u32
	pad_9c         u32
	unk_a0         u64
}

// Region A: Shared globals -- channels, logs, traces, stats
@[packed]
pub struct RegionA {
pub mut:
	channels_addr u64
	unk_8         u64
	unk_10        u64
	unk_18        u64
	fw_log_addr   u64
	fw_log_size   u32
	pad_2c        u32
	ktrace_addr   u64
	ktrace_size   u32
	pad_3c        u32
	stats_addr    u64
	stats_size    u32
	pad_4c        u32
}

// Region B: Hardware/power configuration
@[packed]
pub struct RegionB {
pub mut:
	unk_0               u64
	unk_8               u64
	unk_10              u64
	unk_18              u64
	unk_20              u64
	unk_28              u32
	num_cores            u32
	num_cores_per_cluster u32
	num_clusters         u32
	unk_38              u32
	gpu_gen             u32
	gpu_variant         u32
	gpu_rev             u32
	unk_48              u32
	chip_id             u32
	unk_50              [32]u32
	pwr_config_addr     u64
	unk_d8              u64
	unk_e0              u64
	unk_e8              u64
	io_mappings_addr    u64
	unk_f8              u64
}

// Region C: Firmware runtime state
@[packed]
pub struct RegionC {
pub mut:
	unk_0 [64]u64
}

// Power configuration block
@[packed]
pub struct FwPwrConfig {
pub mut:
	base_ps             u32
	unk_4               u32
	perf_base_clk       u32
	perf_boost_clk      u32
	unk_10              u32
	min_sram_uv         u32
	unk_18              u32
	unk_1c              u32
	avg_pwr_filter_tc_ms u32
	avg_pwr_ki_dt       u32
	avg_pwr_kp          u32
	ppm_ki              u32
	ppm_kp              u32
	pad                 [19]u32
}

// I/O mapping descriptor for firmware
@[packed]
pub struct FwIoMapping {
pub mut:
	phys  u64
	virt  u64
	size  u64
	range u64
	flags u32
	pad   u32
}

// Firmware status
@[packed]
pub struct FwStatus {
pub mut:
	status u32
	pad    [15]u32
}

// Build InitData from hardware config and region addresses
pub fn build_initdata(cfg &hw.HwConfig, channel_base u64, log_base u64, ktrace_base u64, stats_base u64) InitData {
	mut data := InitData{}

	// Fill version info
	data.ver_info[0] = fw_ver_major
	data.ver_info[1] = fw_ver_minor
	data.ver_info[2] = fw_ver_patch
	data.ver_info[3] = cfg.chip_id

	// Seed key pointers; caller patches final in-memory offsets.
	data.region_a_addr = channel_base
	data.region_b_addr = channel_base + 0x400
	data.region_c_addr = channel_base + 0x800
	data.fw_status_addr = channel_base + 0x1000
	data.unk_20 = log_base
	data.unk_28 = ktrace_base
	data.unk_38 = stats_base

	return data
}

// Build Region A with channel and log pointers
pub fn build_region_a(channel_base u64, log_base u64, log_size u32, ktrace_base u64, ktrace_size u32, stats_base u64, stats_size u32) RegionA {
	return RegionA{
		channels_addr: channel_base
		fw_log_addr:   log_base
		fw_log_size:   log_size
		ktrace_addr:   ktrace_base
		ktrace_size:   ktrace_size
		stats_addr:    stats_base
		stats_size:    stats_size
	}
}

// Build Region B from hardware configuration
pub fn build_region_b(cfg &hw.HwConfig) RegionB {
	mut rb := RegionB{}

	rb.num_cores = cfg.gpu_core_count
	rb.num_cores_per_cluster = cfg.num_cores_per_cluster
	rb.num_clusters = cfg.num_clusters
	rb.gpu_gen = u32(cfg.gpu_gen)
	rb.gpu_variant = u32(cfg.gpu_variant)
	rb.gpu_rev = u32(cfg.gpu_rev)
	rb.chip_id = cfg.chip_id
	rb.pwr_config_addr = cfg.shared_region_base
	rb.io_mappings_addr = cfg.shared_region_base + 0x8000

	return rb
}

// Build power configuration from hardware config
pub fn build_pwr_config(cfg &hw.HwConfig) FwPwrConfig {
	return FwPwrConfig{
		base_ps:             cfg.pwr_base_ps
		perf_base_clk:       cfg.pwr_perf_base_clk
		perf_boost_clk:      cfg.pwr_perf_boost_clk
		min_sram_uv:         cfg.pwr_min_sram_microvolt
		avg_pwr_filter_tc_ms: cfg.pwr_avg_power_filter_tc_ms
		avg_pwr_ki_dt:       cfg.pwr_avg_power_ki_dt
		avg_pwr_kp:          cfg.pwr_avg_power_kp
		ppm_ki:              cfg.pwr_ppm_ki
		ppm_kp:              cfg.pwr_ppm_kp
	}
}

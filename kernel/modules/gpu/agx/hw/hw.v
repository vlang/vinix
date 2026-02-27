module hw

// GPU hardware configuration types
// Defines chip-specific parameters used throughout the driver
// Translates hw.rs from the Asahi Linux GPU driver

pub enum GpuGen {
	g13  = 13 // M1 family (t8103, t6000, t6001, t6002)
	g14  = 14 // M2 family (t8112)
	g14x = 15 // M2 Pro/Max/Ultra
}

pub enum GpuVariant {
	s = 0 // Base (single die)
	c = 1 // Max (dual cluster)
	d = 2 // Ultra (dual die)
	g = 3 // Pro variant
}

pub enum GpuRevision {
	a0 = 0
	a1 = 1
	b0 = 2
	b1 = 3
	c0 = 4
	c1 = 5
}

pub struct IoMapping {
pub:
	phys       u64
	virt       u64
	size       u64
	range_size u64
	writable   bool
}

pub struct HwConfig {
pub:
	chip_id                u32
	gpu_gen                GpuGen
	gpu_variant            GpuVariant
	gpu_rev                GpuRevision
	gpu_core_count         u32
	gpu_feat_compat        u32
	gpu_feat_incompat      u32
	max_dies               u32
	num_clusters           u32
	num_cores_per_cluster  u32
	num_frags              u32
	num_gps                u32
	base_clock_hz          u64
	uat_oas                u32 // Output address size (bits)
	num_banks              u32
	// Memory regions
	shared_region_base     u64
	shared_region_size     u64
	fw_private_region_base u64
	fw_private_region_size u64
	gpu_region_base        u64
	gpu_region_size        u64
	// Power status MMIO
	pwr_status_base        u32
	pwr_status_size        u32
	// Power configuration
	pwr_base_ps            u32
	pwr_unk_ps             u32
	pwr_filter_time_const  u32
	pwr_perf_base_clk      u32
	pwr_perf_boost_clk     u32
	pwr_min_sram_microvolt u32
	pwr_avg_power_filter_tc_ms u32
	pwr_avg_power_ki_dt    u32
	pwr_avg_power_kp       u32
	pwr_ppm_ki             u32
	pwr_ppm_kp             u32
	// MMIO I/O mappings
	io_mappings            [20]IoMapping
	io_mapping_count       u32
}

pub struct DynConfig {
pub mut:
	pwr_temp_tbl       [16]u32
	pwr_temp_tbl_count u32
}

pub fn get_config(chip_id u32) ?HwConfig {
	match chip_id {
		0x8103 {
			return t8103_config()
		}
		else {
			C.printf(c'agx: Unknown chip ID 0x%x\n', chip_id)
			return none
		}
	}
}

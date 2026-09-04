module hw

// GPU hardware configuration types
// Defines chip-specific parameters used throughout the driver
// Translates hw.rs from the Asahi Linux GPU driver
pub enum GpuGen {
	g13  = 13 // M1 family (t8103, t6000, t6001, t6002)
	g14  = 14 // M2 family (t8112)
	g14x = 15 // M2 Pro/Max/Ultra
	g17  = 17 // M5 family (t6050, t6051, t6052)
}

pub enum GpuVariant {
	s = 0 // S variant
	c = 1 // C variant
	d = 2 // D variant
	g = 3 // G variant
}

pub enum GpuRevision {
	a0      = 0
	a1      = 1
	b0      = 2
	b1      = 3
	c0      = 4
	c1      = 5
	unknown = 0xff
}

// InitData and channel layouts are private firmware ABIs. A chip may be
// discoverable before Vinix has a compatible ABI implementation.
pub enum FirmwareAbi {
	unknown
	v12_3
	// The macOS 26.5 G17C root header and RTKit transport are identified,
	// but its nested InitData/channel/work layouts are not complete.
	g17_26_5_partial
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
	chip_id               u32
	gpu_gen               GpuGen
	gpu_variant           GpuVariant
	gpu_rev               GpuRevision
	firmware_abi          FirmwareAbi
	gpu_core_count        u32
	gpu_feat_compat       u32
	gpu_feat_incompat     u32
	max_dies              u32
	num_clusters          u32
	num_cores_per_cluster u32
	num_frags             u32
	num_gps               u32
	num_mgpus             u32
	usc_gen               u32
	core_mask_list        [4]u32
	kickid_qid_mask       u32
	kickid_qid_shift      u32
	is_sksm               bool
	base_clock_hz         u64
	uat_ias               u32 // Input address size (bits)
	uat_oas               u32 // Output address size (bits)
	map_kernel_to_user    bool
	num_banks             u32
	// Memory regions
	shared_region_base     u64
	shared_region_size     u64
	fw_private_region_base u64
	fw_private_region_size u64
	gpu_region_base        u64
	gpu_region_size        u64
	// Power status MMIO
	pwr_status_base u32
	pwr_status_size u32
	// Power configuration
	pwr_base_ps                u32
	pwr_unk_ps                 u32
	pwr_filter_time_const      u32
	pwr_perf_base_clk          u32
	pwr_perf_boost_clk         u32
	pwr_min_sram_microvolt     u32
	pwr_avg_power_filter_tc_ms u32
	pwr_avg_power_ki_dt        u32
	pwr_avg_power_kp           u32
	pwr_ppm_ki                 u32
	pwr_ppm_kp                 u32
	// MMIO I/O mappings
	io_mappings      [20]IoMapping
	io_mapping_count u32

	// Native Apple DeviceTree performance data. G17 firmware has capacity for
	// 16 states and 16 voltage domains; the M5 Max currently supplies 14 x 4.
pub mut:
	// Translated primary GPU register aperture discovered from the boot
	// DeviceTree. Modern firmware derives its PIO records from this range.
	gpu_mmio_base            u64
	gpu_mmio_size            u64
	perf_state_count         u32
	perf_state_table_count   u32
	perf_state_frequencies   [16]u32
	perf_state_voltages      [256]u32
	perf_state_sram_voltages [256]u32
}

// The firmware structures under gpu.agx.fw currently describe only the
// macOS 12.3-era G13 protocol. Keep newer chips read-only until their exact
// RTKit, InitData, channel, and work-command layouts have been implemented.
pub fn (cfg &HwConfig) can_boot_firmware() bool {
	return cfg.gpu_gen == .g13 && cfg.firmware_abi == .v12_3
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
		0x6050 {
			return t6050_config()
		}
		else {
			C.printf(c'agx: Unknown chip ID 0x%x\n', chip_id)
			return none
		}
	}
}

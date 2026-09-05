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
	// The G13 v12.3 transport has been identified, but Vinix does not yet
	// construct the complete nested InitData graph or native work commands.
	v12_3_partial
	// Reserved for the byte-validated implementation. No chip may select this
	// value until bootstrap and command submission match the firmware ABI.
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

pub fn (mapping &IoMapping) is_present() bool {
	return mapping.phys != 0 && mapping.size != 0
}

// Native CS/AFR clock-domain data. G17's Apple DeviceTree record has up to
// sixteen states and two voltage rails; the arrays use state-major indexing.
pub struct AuxPerfStateConfig {
pub mut:
	state_count   u32
	table_count   u32
	frequencies   [16]u32
	voltages      [32]u32
	sram_voltages [32]u32
}

pub struct G13PowerZoneConfig {
pub mut:
	target        u32
	target_offset u32
	filter_tc     u32
}

// Raw M1 firmware power-controller inputs. Fields named *_f32 store their
// IEEE-754 bit patterns; Vinix builds the kernel with floating point disabled.
pub struct G13PowerConfig {
pub mut:
	valid                           bool
	power_zone_count                u32
	power_zones                     [5]G13PowerZoneConfig
	core_leak_coef_f32              [8]u32
	sram_leak_coef_f32              [8]u32
	avg_power_filter_tc_ms          u32
	avg_power_ki_only_f32           u32
	avg_power_kp_f32                u32
	avg_power_min_duty_cycle        u32
	avg_power_target_filter_tc      u32
	fast_die0_integral_gain_f32     u32
	fast_die0_proportional_gain_f32 u32
	fast_die0_prop_tgt_delta        u32
	fast_die0_release_temp          u32
	fender_idle_off_delay_ms        u32
	fw_early_wake_timeout_ms        u32
	idle_off_delay_ms               u32
	idle_off_standby_timer          u32
	perf_boost_ce_step              u32
	perf_boost_min_util             u32
	perf_filter_drop_threshold      u32
	perf_filter_time_constant       u32
	perf_filter_time_constant2      u32
	perf_integral_gain_f32          u32
	perf_integral_gain2_f32         u32
	perf_integral_min_clamp         u32
	perf_proportional_gain_f32      u32
	perf_proportional_gain2_f32     u32
	perf_reset_iters                u32
	perf_tgt_utilization            u32
	ppm_filter_time_constant_ms     u32
	ppm_ki_f32                      u32
	ppm_kp_f32                      u32
	pwr_filter_time_constant        u32
	pwr_integral_gain_f32           u32
	pwr_integral_min_clamp          u32
	pwr_min_duty_cycle              u32
	pwr_proportional_gain_f32       u32
	pwr_sample_period_aic_clks      u32
	se_engagement_criteria          i32
	se_filter_time_constant         u32
	se_filter_time_constant_1       u32
	se_inactive_threshold           u32
	se_ki_f32                       u32
	se_ki_1_f32                     u32
	se_kp_f32                       u32
	se_kp_1_f32                     u32
	se_reset_criteria               u32
}

pub struct HwConfig {
pub:
	chip_id               u32
	gpu_gen               GpuGen
	gpu_variant           GpuVariant
	firmware_abi          FirmwareAbi
	firmware_gpu_core_id  u32
	gpu_feat_compat       u32
	gpu_feat_incompat     u32
	max_dies              u32
	num_mgpus             u32
	usc_gen               u32
	kickid_qid_mask       u32
	kickid_qid_shift      u32
	is_sksm               bool
	base_clock_hz         u64
	uat_ias               u32 // Input address size (bits)
	uat_oas               u32 // Output address size (bits)
	map_kernel_to_user    bool
	num_banks             u32
	preempt1_size         u64
	preempt2_size         u64
	preempt3_size         u64
	compute_preempt1_size u64
	render_tiling_control u32
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
	// Runtime topology is read from hardware on G13 because fused-off cores
	// differ between otherwise identical t8103 products.
	gpu_rev               GpuRevision
	gpu_core_count        u32
	num_clusters          u32
	num_cores_per_cluster u32
	num_frags             u32
	num_gps               u32
	core_mask_list        [4]u32
	// Translated primary GPU register aperture discovered from the boot
	// DeviceTree. Modern firmware derives its PIO records from this range.
	gpu_mmio_base            u64
	gpu_mmio_size            u64
	soc_revision_major       u32
	soc_revision_minor       u32
	gpu_power_sample_period  u32
	min_sram_microvolt       u32
	perf_state_count         u32
	perf_state_base          u32
	perf_state_table_count   u32
	perf_state_frequencies   [16]u32
	perf_state_powers        [16]u32
	perf_state_voltages      [256]u32
	perf_state_sram_voltages [256]u32
	max_power_mw             u32
	firmware_version         [4]u32
	g13_power                G13PowerConfig
	cs_perf_states           AuxPerfStateConfig
	afr_perf_states          AuxPerfStateConfig
}

// The firmware structures under gpu.agx.fw currently describe only the
// macOS 12.3-era G13 protocol. Keep newer chips read-only until their exact
// RTKit, InitData, channel, and work-command layouts have been implemented.
pub fn (cfg &HwConfig) can_boot_firmware() bool {
	return cfg.gpu_gen == .g13 && cfg.firmware_abi == .v12_3
}

pub fn (cfg &HwConfig) firmware_abi_name() &char {
	return match cfg.firmware_abi {
		.unknown { c'unknown' }
		.v12_3_partial { c'G13 v12.3 (partial)' }
		.v12_3 { c'G13 v12.3' }
		.g17_26_5_partial { c'G17 26.5 (partial)' }
	}
}

// Apply topology read from the G13 identity registers. Static configuration
// fields are maxima; the active core count and masks vary with fused-off cores
// (the base M1 Air commonly reports seven active cores).
pub fn (mut cfg HwConfig) apply_g13_identity(revision_code u32, num_clusters u32,
	num_cores_per_cluster u32, num_frags_per_cluster u32, num_gps_per_cluster u32,
	total_active_cores u32, core_masks [4]u32) bool {
	if cfg.gpu_gen != .g13 || num_clusters == 0 || num_clusters > cfg.num_clusters
		|| num_cores_per_cluster == 0 || num_cores_per_cluster > cfg.num_cores_per_cluster
		|| num_frags_per_cluster > cfg.num_frags / cfg.num_clusters
		|| num_gps_per_cluster > cfg.num_gps / cfg.num_clusters || total_active_cores == 0
		|| total_active_cores > num_clusters * num_cores_per_cluster {
		return false
	}
	revision := match revision_code {
		0x00 { GpuRevision.a0 }
		0x01 { GpuRevision.a1 }
		0x10 { GpuRevision.b0 }
		0x11 { GpuRevision.b1 }
		0x20 { GpuRevision.c0 }
		0x21 { GpuRevision.c1 }
		else {
			return false
		}
	}
	cfg.gpu_rev = revision
	cfg.gpu_core_count = total_active_cores
	cfg.num_clusters = num_clusters
	cfg.num_cores_per_cluster = num_cores_per_cluster
	cfg.num_frags = num_clusters * num_frags_per_cluster
	cfg.num_gps = num_clusters * num_gps_per_cluster
	cfg.core_mask_list = core_masks
	return true
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

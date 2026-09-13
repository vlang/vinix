module hw

// Apple M1 (t8103) GPU configuration
// G13 generation, G variant, 8 cores, 24MHz base clock, 40-bit OAS
// The runtime identity decoder replaces the eight-core maximum with the fused
// topology, including the seven-core base M1 Air configuration.

pub fn t8103_config() HwConfig {
	mut mappings := [20]IoMapping{}

	// Keep these at their firmware ABI indices, including empty slots. They
	// match Asahi's t8103 HWCONFIG I/O mapping table.
	// Fender
	mappings[0] = IoMapping{
		phys: 0x204d00000
		size: 0x1c000
		range_size: 0x1c000
		writable: true
	}
	// AICTimer
	mappings[1] = IoMapping{
		phys: 0x20e100000
		size: 0x4000
		range_size: 0x4000
		writable: false
	}
	// AICSWInt
	mappings[2] = IoMapping{
		phys: 0x23b104000
		size: 0x4000
		range_size: 0x4000
		writable: true
	}
	// RGX
	mappings[3] = IoMapping{
		phys: 0x204000000
		size: 0x20000
		range_size: 0x20000
		writable: true
	}
	// Slots 4-6 are UVD, unused, and DisplayUnderrunWA on t8103.
	// AnalogTempSensorControllerRegs
	mappings[7] = IoMapping{
		phys: 0x23b2e8000
		size: 0x1000
		range_size: 0x1000
		writable: false
	}
	// PMPDoorbell
	mappings[8] = IoMapping{
		phys: 0x23bc00000
		size: 0x1000
		range_size: 0x1000
		writable: true
	}
	// MetrologySensorRegs
	mappings[9] = IoMapping{
		phys: 0x204d80000
		size: 0x5000
		range_size: 0x5000
		writable: true
	}
	// GMGIFAFRegs
	mappings[10] = IoMapping{
		phys: 0x204d61000
		size: 0x1000
		range_size: 0x1000
		writable: true
	}
	// MCache registers
	mappings[11] = IoMapping{
		phys: 0x200000000
		size: 0xd6400
		range_size: 0xd6400
		writable: true
	}
	// Slot 12 is AICBankedRegisters on other SoCs.
	// PMGRScratch
	mappings[13] = IoMapping{
		phys: 0x23b738000
		size: 0x1000
		range_size: 0x1000
		writable: true
	}

	return HwConfig{
		chip_id: 0x8103
		gpu_gen: .g13
		gpu_variant: .g
		gpu_rev: .a1
		firmware_abi: .v12_3
		firmware_gpu_core_id: 11 // G13G in the firmware ABI
		gpu_core_count: 8
		gpu_feat_compat: 0
		gpu_feat_incompat: 0
		max_dies: 1
		num_clusters: 1
		num_cores_per_cluster: 8
		num_frags: 8
		num_gps: 4
		base_clock_hz: 24000000 // 24 MHz
		uat_ias: 39
		uat_oas: 40
		map_kernel_to_user: false
		num_banks: 1
		preempt1_size: 0x540
		preempt2_size: 0x280
		preempt3_size: 0x20
		compute_preempt1_size: 0x7f80
		render_tiling_control: 0xa041
		shared_region_base: 0x6800000000
		shared_region_size: 0x140000
		fw_private_region_base: 0x6800140000
		fw_private_region_size: 0x3C000
		gpu_region_base: 0x680017C000
		gpu_region_size: 0x5440000
		pwr_base_ps: 11
		pwr_unk_ps: 0
		pwr_filter_time_const: 9
		pwr_perf_base_clk: 1000
		pwr_perf_boost_clk: 1398
		pwr_avg_power_filter_tc_ms: 1000
		pwr_avg_power_ki_dt: 0
		pwr_avg_power_kp: 0
		pwr_ppm_ki: 0
		pwr_ppm_kp: 0
		io_mappings: mappings
		// This is the number of ABI slots, not the number of present mappings.
		io_mapping_count: 20
	}
}

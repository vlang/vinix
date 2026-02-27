module hw

// Apple M1 (t8103) GPU configuration
// G13 generation, G variant, 8 cores, 24MHz base clock, 40-bit OAS
// This must be byte-perfect -- firmware will crash on any error

pub fn t8103_config() HwConfig {
	mut mappings := [20]IoMapping{}

	// SGX register block
	mappings[0] = IoMapping{
		phys:       0x204d00000
		size:       0x1c000
		range_size: 0x1c000
		writable:   true
	}
	// ASC register block
	mappings[1] = IoMapping{
		phys:       0x20e100000
		size:       0x4000
		range_size: 0x4000
		writable:   false
	}
	// AIC register block
	mappings[2] = IoMapping{
		phys:       0x23b104000
		size:       0xc000
		range_size: 0xc000
		writable:   true
	}

	return HwConfig{
		chip_id:                0x8103
		gpu_gen:                .g13
		gpu_variant:            .g
		gpu_rev:                .a1
		gpu_core_count:         8
		gpu_feat_compat:        0
		gpu_feat_incompat:      0
		max_dies:               1
		num_clusters:           1
		num_cores_per_cluster:  8
		num_frags:              8
		num_gps:                4
		base_clock_hz:          24000000 // 24 MHz
		uat_oas:                40
		num_banks:              1
		shared_region_base:     0x6800000000
		shared_region_size:     0x140000
		fw_private_region_base: 0x6800140000
		fw_private_region_size: 0x3C000
		gpu_region_base:        0x680017C000
		gpu_region_size:        0x5440000
		pwr_base_ps:            11
		pwr_unk_ps:             0
		pwr_filter_time_const:  9
		pwr_perf_base_clk:      1000
		pwr_perf_boost_clk:     1398
		pwr_min_sram_microvolt: 790000
		pwr_avg_power_filter_tc_ms: 1000
		pwr_avg_power_ki_dt:    0
		pwr_avg_power_kp:       0
		pwr_ppm_ki:             0
		pwr_ppm_kp:             0
		io_mappings:            mappings
		io_mapping_count:       3
	}
}

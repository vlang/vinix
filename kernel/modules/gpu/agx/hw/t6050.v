module hw

// Apple M5 Max (t6050) discovery configuration.
//
// These topology fields come from the AGXG17X GPUConfigurationVariable
// published by macOS on a Mac17,6. The firmware ABI and register programming
// are intentionally not enabled: G17 uses a newer private protocol than the
// v12.3 G13 structures currently implemented by Vinix.
pub fn t6050_config() HwConfig {
	mut core_masks := [4]u32{}
	core_masks[0] = 0x3ff
	core_masks[1] = 0x3ff
	core_masks[2] = 0x3ff
	core_masks[3] = 0x3ff

	return HwConfig{
		chip_id:               0x6050
		gpu_gen:               .g17
		gpu_variant:           .c
		gpu_rev:               .unknown
		firmware_abi:          .g17_26_5_partial
		gpu_core_count:        40
		max_dies:              1
		num_clusters:          4
		num_cores_per_cluster: 10
		num_frags:             40
		num_gps:               16
		num_mgpus:             4
		usc_gen:               3
		core_mask_list:        core_masks
		kickid_qid_mask:       0x7f
		kickid_qid_shift:      40
		is_sksm:               true
		uat_ias:               42
		uat_oas:               42
		map_kernel_to_user:    true
	}
}

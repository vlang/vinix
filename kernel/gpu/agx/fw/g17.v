// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module fw

import gpu.agx.hw
import katomic
import klock

// Verified anchors for the G17C firmware shipped with macOS 26.5 (25F71),
// RTKit build 3255.120.11. This is deliberately only the root bootstrap
// header: unknown nested structures must not be represented as compatible
// with the older G13 InitData types in this module.
pub const g17_init_message = u64(0x81) << 48
pub const g17_init_address_mask = (u64(1) << 44) - 1
pub const g17_akf_message_type_shift = u32(48)
pub const g17_akf_message_type_mask = u64(0x3f)
pub const g17_akf_callback_type = u8(2)
pub const g17_akf_ready_type = u8(9)
pub const g17_ready_ack_message = u64(0x89) << 48
pub const g17_interface_magic = u64(0x0c8bc322072804c0)
pub const g17_bootstrap_header_size = u64(0xc8)
pub const g17_bootstrap_page_size = u64(0x4000)
pub const g17_bootstrap_region_size = u64(0x4000)
pub const g17_init_register_entry_size = u64(0x18)
pub const g17_init_register_terminator = u32(0)
pub const g17_init_register_write_32 = u32(1)
pub const g17_init_register_write_64 = u32(2)
pub const g17_init_register_write_64_pa = u32(3)
pub const g17_platform_config_size = u64(0x68)
pub const g17_firmware_shared_data_offset = u64(0x18)
pub const g17_runtime_data_offset = u64(0x20)
pub const g17_firmware_role_offset = u64(0x28)
pub const g17_host_mapped_allocations_offset = u64(0x2c)
pub const g17_small_shared_data_offset = u64(0xa8)
pub const g17_primary_region_offset = u64(0xb0)
pub const g17_secondary_region_offset = u64(0xb8)
pub const g17_secondary_aux_offset = u64(0xc0)
pub const g17_accelerator_ring_entries = u32(256)
pub const g17_accelerator_ring_state_size = u64(0x30)
pub const g17_device_control_entries_size = u64(0x4000)
pub const g17_accelerator_ring_addresses_offset = u64(0x1a0)
pub const g17_accelerator_ring_addresses_size = u64(0x20)
pub const g17_auxiliary_ring_addresses_offset = u64(0x1c0)
pub const g17_auxiliary_ring_address_count = 8
pub const g17_firmware_event_state_auxiliary_index = 0
pub const g17_firmware_event_entries_auxiliary_index = 1
pub const g17_firmware_event_ring_entries = u32(256)
pub const g17_firmware_event_entry_size = u64(0x48)
pub const g17_firmware_event_entries_size = u64(0x4800)
pub const g17_firmware_event_type_mask = u32(0x2000ffd3)
pub const g17_firmware_event_controller = u32(0)
pub const g17_firmware_event_completion = u32(1)
pub const g17_firmware_event_gpu_restart = u32(4)
pub const g17_firmware_event_pm_request_memory = u32(6)
pub const g17_firmware_event_host_noop_mask = u32(0x20000801)
pub const g17_firmware_event_channel_error = u32(7)
pub const g17_firmware_event_metrology_aging = u32(8)
pub const g17_firmware_event_uma_async_alloc = u32(9)
pub const g17_firmware_event_shared_event_signal_complete = u32(10)
pub const g17_firmware_event_process_exit_complete = u32(12)
pub const g17_firmware_event_uma_grow_pool = u32(13)
pub const g17_firmware_event_rt_completion = u32(14)
pub const g17_firmware_event_uma_threshold_interrupt = u32(15)
pub const g17_firmware_event_flag_limit = u16(0x18)
// Apple's type-4/type-7 handlers compare against IOGPUEventMachine's dynamic
// stamp count. Vinix's v12.3 event manager exposes exactly the same 128 slots
// (event.max_stamps), so reject records outside the locally configured array.
pub const g17_firmware_event_stamp_slots = u32(128)
pub const g17_firmware_event_pm_manager_limit = u32(0x7f)
pub const g17_firmware_event_pm_request_kind_limit = u32(0x40)
pub const g17_firmware_event_uma_flist_limit = u32(0x100)
pub const g17_t6050_callback_interrupt_index = u32(4)
pub const g17_data_master_entry_size = u64(0x18)
pub const g17_data_master_entries_bytes = u64(0x1800)
pub const g17_data_master_priorities = u32(4)
pub const g17_data_master_command_types = u32(3)
pub const g17_data_master_address_record_size = u64(0x20)
pub const g17_data_master_priority_record_size = u64(0x60)
pub const g17_data_master_address_table_size = u64(0x180)
pub const g17_device_control_entry_size = u64(0x40)
pub const g17_device_control_allocate_pm_memory = u32(8)
pub const g17_device_control_update_uma_threshold = u32(0x21)
pub const g17_device_control_allocate_pm_flags = u32(0x19)
pub const g17_device_control_role_primary = u32(0)
pub const g17_device_control_allocate_pm_doorbell = u64(0x8400000000000011)
pub const g17_channel_priority_count = u32(4)
pub const g17_channel_default_subpriority = u32(2)
pub const g17_accelerator_command_ta = u32(0)
pub const g17_accelerator_command_3d = u32(1)
pub const g17_accelerator_command_cl = u32(2)
pub const g17_data_master_channel_id = u8(0x80)
pub const g17_data_master_channel_flag = u8(0)
pub const g17_channel_state_size = u64(0xc0)
pub const g17_channel_control_header_size = u64(0x70)
pub const g17_channel_pool_base_size = u64(0x70)
pub const g17_channel_pool_queue_stride = u64(0x80)
pub const g17_cached_command_pointer_size = u64(0x08)
pub const g17_default_configured_work_queues = u32(80)
pub const g17_maximum_channel_queue_request = u32(0x80)
pub const g17_channel_pointers_per_queue = u32(16)
pub const g17_timestamp_state_size = u64(0x18)
pub const g17_firmware_shared_data_size = u64(0x4c0)
pub const g17_runtime_data_size = u64(0x1ca0)
pub const g17_runtime_platform_values_offset = u64(0x54)
pub const g17_runtime_performance_policy_offset = u64(0xa4)
pub const g17_runtime_performance_policy_size = u64(0x40)
pub const g17_runtime_power_policy_offset = u64(0xec)
pub const g17_runtime_power_policy_size = u64(0x6d8)
pub const g17_runtime_smart_idle_offset = u64(0x7c4)
pub const g17_runtime_smart_idle_size = u64(0x28)
pub const g17_small_shared_data_size = u64(0x20)
pub const g17_primary_region_size = u64(0xe440)
pub const g17_secondary_region_size = u64(0x6f0)
pub const g17_secondary_aux_size = u64(0xa8)
pub const g17_hardware_config_size = u64(0x2710)
pub const g17_address_space_layout_size = u64(0x38)
pub const g17_firmware_scalar_block_size = u64(0x134)
pub const g17_firmware_scalar_word_count = 77
pub const g17_userspace_va_map = u64(0x6f00000000)
pub const g17_userspace_va_limit = u64(0xffc00000)
pub const g17_usc_start = u64(0x1000000000)
pub const g17_unknown_page = u64(0x2ffffff8000)
pub const g17_timestamp_area_base = u64(0xfffffc2181400000)
pub const g17_common_control_size = u64(0x88)
pub const g17_role_large_region_size = u64(0x79800)
pub const g17_role0_bootstrap_254_size = u64(0xc18)
pub const g17_role0_bootstrap_25c_size = u64(0x1048)
pub const g17_role0_bootstrap_264_size = u64(0xe10)
pub const g17_role0_bootstrap_26c_size = u64(0x68)
pub const g17_role0_bootstrap_274_size = u64(0x800)
pub const g17_role1_secondary_471_size = u64(0x11dd0)
pub const g17_primary_shared_state_initial = u8(0xff)
pub const g17_default_usc_max_tgmem = u32(12)
pub const g17_color_matrix_count = 64
pub const g17_color_matrix_size = u64(0x18)
pub const g17_io_mapping_count = 53
pub const g17_io_mapping_size = u64(0x28)
pub const g17_performance_state_capacity = 16
pub const g17_voltage_table_columns = 16
pub const g17_aux_performance_state_capacity = 16
pub const g17_aux_voltage_table_columns = 2
pub const g17_aux_performance_state_cap = u32(14)
pub const g17_aux_performance_block_size = u64(0x148)
pub const g17_performance_state_map_block_size = u64(0x80)
pub const g17_sram_power_scale = u32(0x3f828f5c)
pub const g17_linear_power_transfer_maximum = u32(100)
pub const g17_leakage_fuse_physical_address = u64(0x23_8837_4000)
pub const g17_leakage_fuse_size = u64(0x1000)
pub const g17_leakage_fuse_word_198 = u64(0x198)
pub const g17_leakage_fuse_word_19c = u64(0x19c)
pub const g17_leakage_fuse_word_1a0 = u64(0x1a0)
pub const g17_leakage_core_capacity = 8
pub const g17_leakage_group_capacity = 2
pub const g17_fw_util_pstate_control_count = 4
pub const g17_fw_util_pstate_control_size = u64(0x06)
pub const g17_register_override_count = 16
pub const g17_register_override_size = u64(0x18)
pub const g17_default_mcache_writes = u64(0x0000000607800004)
pub const g17_setup_config_value_f4c = u32(0x31)
pub const g17_fixed_config_value_f8c = u64(0x00000000fffeae80)

@[inline]
pub fn g17_init_message_for_root(root_iova u64) u64 {
	return g17_init_message | (root_iova & g17_init_address_mask)
}

@[inline]
pub fn g17_akf_message_type(message u64) u8 {
	return u8((message >> g17_akf_message_type_shift) & g17_akf_message_type_mask)
}

// Allocation sizes in the order published at shared offsets
// 0x1c0, 0x1c8, ... 0x1f8 for each firmware role.
pub fn g17_auxiliary_ring_size(index u32) ?u64 {
	return match index {
		0 { u64(0x30) }
		1 { u64(0x4800) }
		2 { u64(0x1b0) }
		3 { u64(0x28800) }
		4 { u64(0x30) }
		5 { u64(0x9000) }
		6 { u64(0x30) }
		7 { u64(0x4800) }
		else { none }
	}
}

// Exact 0x68-byte slice copied from fields 0x18..0x7f of the G17 legacy
// shared-GART backing object into both bootstrap roots at offset 0x30.
@[packed]
pub struct G17PlatformConfig {
pub mut:
	value_000     u16
	value_002     u8
	value_003     u32
	value_007     u8
	value_008     u16
	page_size_00a u16
	value_00c     u64
	value_014     u64
	value_01c     u64
	value_024     u32
	value_028     u16
	page_size_02a u16
	value_02c     u64
	value_034     u64
	value_03c     u64
	value_044     u32
	value_048     u16
	page_size_04a u16
	value_04c     u64
	value_054     u64
	value_05c     u64
	reserved_064  u32
}

pub fn new_g17_platform_config() G17PlatformConfig {
	return G17PlatformConfig{
		value_000: 0x1000
		value_002: 0x0c
		value_003: 0x0e0e0803
		value_007: 0x24
		value_008: 0x40
		page_size_00a: 0x4000
		value_00c: 0x1
		value_014: 0x000003ffffffc000
		value_01c: 0x3f000000000
		value_024: 0x190e0e08
		value_028: 0x800
		page_size_02a: 0x4000
		value_02c: 0x1
		value_034: 0x000003ffffffc000
		value_03c: 0xffe000000
		value_044: 0x0e0e0e08
		value_048: 0x800
		page_size_04a: 0x4000
		value_04c: 0x1
		value_054: 0x000003ffffffc000
		value_05c: 0x1ffc000
	}
}

// Root+0x08 points at a 16 KiB firmware-page mapping containing 0x18-byte
// register writes. The pinned G17 accelerator's producer is a no-op, so its
// boot-time contents are one kind-zero terminator followed by zeroed storage.
@[packed]
pub struct G17InitRegisterEntry {
pub mut:
	value       u64
	register    u32
	auxiliary   u32
	kind        u32
	padding_014 u32
}

pub fn new_g17_init_register_terminator() G17InitRegisterEntry {
	return G17InitRegisterEntry{
		kind: g17_init_register_terminator
	}
}

pub fn initialize_g17_bootstrap_region(buffer voidptr, size u64) bool {
	if buffer == unsafe { nil } || size != g17_bootstrap_region_size {
		return false
	}
	unsafe {
		C.memset(buffer, 0, size)
		terminator := &G17InitRegisterEntry(buffer)
		*terminator = new_g17_init_register_terminator()
	}
	return true
}

// The primary G17C firmware copies exactly 0xc8 bytes from the host-provided
// root before dereferencing any nested pointers. The names below describe
// allocation roles established by the local G17 host driver; the nested
// allocation layouts remain intentionally opaque. The primary and secondary
// firmware roots populate different tail regions.
@[packed]
pub struct G17BootstrapHeader {
pub mut:
	interface_magic              u64
	bootstrap_region_address     u64
	opaque_010                   u64
	firmware_shared_data_address u64
	runtime_data_address         u64
	firmware_role                u32
	host_mapped_allocations      u32
	platform_config_030          G17PlatformConfig
	opaque_098                   [0x10]u8
	small_shared_data_address    u64
	primary_region_address       u64
	secondary_region_address     u64
	secondary_aux_address        u64
}

// Each firmware role receives its own host/firmware mapped 16 KiB page. Only
// the leading 0xc8-byte header is consumed by the checked G17 bootstrap
// handler; clearing the tail makes the entire handoff deterministic.
@[packed]
pub struct G17BootstrapPage {
pub mut:
	header  G17BootstrapHeader
	padding [0x3f38]u8
}

pub fn new_g17_bootstrap_header(role u32) G17BootstrapHeader {
	return G17BootstrapHeader{
		interface_magic: g17_interface_magic
		firmware_role: role
		host_mapped_allocations: 1
	}
}

// Construct only the top-level object consumed by the G17 initialization
// handler. The 0x68-byte platform block is a separate recovered input; callers
// must not substitute the older G13 InitData contents for it.
pub fn populate_g17_bootstrap_header(mut header G17BootstrapHeader, role u32,
	bootstrap_region_address u64, firmware_shared_data_address u64, runtime_data_address u64,
	small_shared_data_address u64, primary_region_address u64, secondary_region_address u64,
	secondary_aux_address u64, platform_config voidptr, platform_config_size u64) bool {
	if role > 1 || bootstrap_region_address == 0 || firmware_shared_data_address == 0 || runtime_data_address == 0 || small_shared_data_address == 0 || platform_config == unsafe { nil } || platform_config_size != g17_platform_config_size {
		return false
	}
	if (role == 0 && primary_region_address == 0) || (role == 1 && (secondary_region_address == 0 || secondary_aux_address == 0)) {
		return false
	}

	header = new_g17_bootstrap_header(role)
	header.bootstrap_region_address = bootstrap_region_address
	header.firmware_shared_data_address = firmware_shared_data_address
	header.runtime_data_address = runtime_data_address
	header.small_shared_data_address = small_shared_data_address
	if role == 0 {
		header.primary_region_address = primary_region_address
	} else {
		header.secondary_region_address = secondary_region_address
		header.secondary_aux_address = secondary_aux_address
	}
	unsafe {
		C.memcpy(&header.platform_config_030, platform_config, g17_platform_config_size)
	}
	return validate_g17_bootstrap_header(&header)
}

pub fn validate_g17_bootstrap_header(header &G17BootstrapHeader) bool {
	return sizeof(G17BootstrapHeader) == g17_bootstrap_header_size && sizeof(G17PlatformConfig) == g17_platform_config_size && sizeof(header.platform_config_030) == g17_platform_config_size && header.interface_magic == g17_interface_magic && header.firmware_role <= 1 && header.host_mapped_allocations != 0
}

pub fn initialize_g17_bootstrap_page(buffer voidptr, size u64, role u32,
	bootstrap_region_address u64, firmware_shared_data_address u64, runtime_data_address u64,
	small_shared_data_address u64, primary_region_address u64, secondary_region_address u64,
	secondary_aux_address u64, platform_config voidptr, platform_config_size u64) bool {
	if buffer == unsafe { nil } || size != g17_bootstrap_page_size
		|| sizeof(G17BootstrapPage) != g17_bootstrap_page_size {
		return false
	}
	mut header := G17BootstrapHeader{}
	if !populate_g17_bootstrap_header(mut header, role, bootstrap_region_address, firmware_shared_data_address, runtime_data_address, small_shared_data_address, primary_region_address, secondary_region_address, secondary_aux_address, platform_config, platform_config_size) {
		return false
	}
	unsafe {
		C.memset(buffer, 0, size)
		C.memcpy(buffer, &header, sizeof(G17BootstrapHeader))
	}
	return true
}

// Shared object referenced by root+0x18. The host driver writes these fields
// in initFirmwareSharedData and initFirmwareData. Pointer meanings below stay
// opaque until their target allocations have independently recovered layouts.
@[packed]
pub struct G17FirmwareSharedData {
pub mut:
	address_000              u64
	address_008              u64
	address_010              u64
	opaque_018               [0x188]u8
	accelerator_ring         G17AcceleratorRingAddresses
	auxiliary_ring_addresses [g17_auxiliary_ring_address_count]u64
	address_200              u64
	opaque_208               [0x48]u8
	state_250                u32
	addresses_254            [5]u64
	opaque_27c               [0x54]u8
	address_2d0              u64
	platform_address_2d8     u64
	platform_address_2e0     u64
	platform_address_2e8     u64
	platform_address_2f0     u64
	reserved_2f8             u64
	value_300                u32
	value_304                u32
	opaque_308               [0xd8]u8
	state_3e0                u8
	status_3e1               [0x90]u8
	secondary_address_471    u64
	calibration_479          [0x10]u8
	opaque_489               [0x37]u8
}

// Six-byte per-state firmware-utilization controls selected by the low two
// bits of the packed host request. Each value is stored most-significant byte
// first by the G17 host producer.
@[packed]
pub struct G17FwUtilPStateControl {
pub mut:
	debounce_period_high  u8
	debounce_period_low   u8
	pstate_threshold_high u8
	pstate_threshold_low  u8
	pstate_step_size_high u8
	pstate_step_size_low  u8
}

// Runtime register override records are indexed with a 24-byte stride. The
// producer admits at most 16 entries and publishes the active count at 0x984.
@[packed]
pub struct G17RegisterOverride {
pub mut:
	value       u64
	mask        u64
	register    u32
	padding_014 u32
}

// Runtime object referenced by root+0x20. The named tail controls below are
// independently fixed by short, symbolized G17 accessors. Opaque ranges still
// contain configuration populated by initFirmwareData and must not be treated
// as zero-compatible until their producers are recovered.
@[packed]
pub struct G17RuntimeData {
pub mut:
	opaque_000                          [0x0c]u8
	dm_pause_mode                       u32
	opaque_010                          [0x04]u8
	dm_pause_timer                      u32
	opaque_018                          [0x08]u8
	mtr_sensor_ptd_override_mask        u64
	frg_task_timeout                    u32
	power_config_02c                    u32
	power_config_030                    u32
	smart_idle_enabled                  u32
	state_038                           u32
	opaque_03c                          [0x04]u8
	cpms_window_size                    u32
	cpms_tfca_size                      u32
	state_048                           u32
	kick_channel_qos_04c                u32
	kick_channel_qos_050                u32
	platform_values_054                 [3]u16
	state_05a                           u32
	state_05e                           u32
	state_062                           u32
	opaque_066                          [0x04]u8
	state_06a                           u32
	opaque_06e                          [0x0a]u8
	command_submission_enabled          u32
	opaque_07c                          [0x08]u8
	power_config_084                    u32
	opaque_088                          [0x0c]u8
	performance_controller_override     u32
	performance_state_cap               u32
	state_09c                           u32
	state_0a0                           u32
	performance_controller_target       u32
	performance_controller_dead_zone    u32
	performance_controller_transfer     u32
	performance_boost_min_util          u32
	performance_boost_ce_step           u32
	performance_controller_reset_iters  u32
	performance_boost_min_util_valid    u8
	performance_time_filter_constants   [2]u32
	performance_integral_gain_bits      [2]u32
	performance_proportional_gain_bits  [2]u32
	performance_dual_filter             u8
	performance_time_filter_valid       [2]u8
	performance_integral_gain_valid     [2]u8
	performance_proportional_gain_valid [2]u8
	performance_dual_filter_valid       u8
	opaque_0dd                          [0x07]u8
	clpc_deadline_control_effort        u32
	clpc_deadline_control_override      u32
	// Apple rearranges this range from a DPE/PPT source block. The checked
	// G17C vtable producer clears that entire source, so the initial payload is
	// exactly zero even though its individual firmware-owned fields are opaque.
	power_controller_payload_0ec         [0x6d8]u8
	smart_idle_standby_timer_us          u32
	smart_idle_probability_initial_bits  u32
	smart_idle_fn_hit_bits               u32
	smart_idle_fi_hit_bits               u32
	smart_idle_fn_miss_bits              u32
	smart_idle_fi_miss_bits              u32
	smart_idle_neighbor_hit_bits         u32
	smart_idle_gpu_min_confidence_bits   u32
	smart_idle_gpu_high_confidence_bits  u32
	smart_idle_reset_iterations          u32
	ut_engagement_primary                u32
	ut_engagement_secondary              u32
	pmu_engagement                       u32
	gpu_keepalive_perf_mode_default      u32
	gpu_keepalive_off_mode_default       u32
	opaque_800                           [0x04]u8
	register_overrides                   [g17_register_override_count]G17RegisterOverride
	register_override_count              u32
	opaque_988                           [0x14]u8
	progress_check_interval_3d           u32
	progress_check_interval_ta           u32
	progress_check_interval_cl           u32
	progress_check_threshold             u32
	progress_check_dm_config             u32
	opaque_9b0                           [0x0c]u8
	gpu_idle_off_delay                   u32
	fender_idle_off_delay                u32
	firmware_early_wake_timeout          u32
	gvdm_timer_interval                  u32
	cl_context_switch_timeout            u32
	cl_kill_timeout                      u32
	phase_one_cdm_context_switch_timeout u32
	frg_context_switch_timeout           u32
	frg_kill_timeout                     u32
	opaque_9e0                           [0x08]u8
	fw_util_default_fab_pstate_high      u8
	fw_util_default_fab_pstate_low       u8
	fw_util_timer_period                 u8
	fw_util_pstate_controls              [g17_fw_util_pstate_control_count]G17FwUtilPStateControl
	opaque_a03                           u8
	startup_zero_a04                     [0x28]u8
	opaque_a2c                           [0x1200]u8
	firmware_callback_1c2c               u32
	gpu_keepalive_override               u32
	gfxc_keepalive_override              u32
	gpu_keepalive_perf_mode_threshold    u32
	gpu_keepalive_off_mode_threshold     u32
	opaque_1c40                          u8
	normalized_role_count_1c41           u32
	startup_zero_1c45                    u64
	startup_zero_1c4d                    u32
	opaque_1c51                          [0x30]u8
	riart_u_level_mask_1c81              u32
	riart_u_level_disable_mask_1c85      u32
	riart_t_level_disable_mask_1c89      u32
	riart_state_1c8d                     u32
	opaque_1c91                          [0x0f]u8
}

// The active G17C configureDevice path replaces the base platform halfwords
// with ffff/0028/ffff. Its configurePowerAndPerformanceController override
// then installs this Smart Idle policy at accelerator+0xe948; the ARM firmware
// copies it to runtime+0x7c4 and converts the final reset count to float.
pub fn initialize_g17_runtime_platform_policy(buffer voidptr, size u64) bool {
	if buffer == unsafe { nil } || size < g17_runtime_data_size
		|| sizeof(G17RuntimeData) != g17_runtime_data_size {
		return false
	}
	unsafe {
		mut runtime := &G17RuntimeData(buffer)
		runtime.platform_values_054[0] = 0xffff
		runtime.platform_values_054[1] = 40
		runtime.platform_values_054[2] = 0xffff
		runtime.smart_idle_standby_timer_us = 1500
		runtime.smart_idle_probability_initial_bits = 0x3f800000
		runtime.smart_idle_fn_hit_bits = 0x3f4ccccd
		runtime.smart_idle_fi_hit_bits = 0x3e4ccccd
		runtime.smart_idle_fn_miss_bits = 0x3f666666
		runtime.smart_idle_fi_miss_bits = 0x3dcccccd
		runtime.smart_idle_neighbor_hit_bits = 0x3e800000
		runtime.smart_idle_gpu_min_confidence_bits = 0x3f19999a
		runtime.smart_idle_gpu_high_confidence_bits = 0x3f666666
		runtime.smart_idle_reset_iterations = 0x40c00000
	}
	return true
}

// setupConfig explicitly clears the 57 meaningful bytes in the host-side
// performance-controller policy before initPowerAndPerformanceData copies the
// enclosing 64-byte slot to runtime+0xa4. The last seven bytes are alignment
// padding; clear them too so the host-to-firmware snapshot is deterministic.
// With the override-valid bytes unset, firmware uses the DeviceTree-backed
// boost minimum-utilization and CE-step values from the hardware config.
pub fn initialize_g17_runtime_performance_policy(buffer voidptr, size u64) bool {
	if buffer == unsafe { nil } || size < g17_runtime_data_size
		|| sizeof(G17RuntimeData) != g17_runtime_data_size {
		return false
	}
	unsafe {
		C.memset(voidptr(u64(buffer) + g17_runtime_performance_policy_offset), 0, g17_runtime_performance_policy_size)
	}
	return true
}

// The pinned G17C accelerator inherits the generic DPE/PPT producer at
// vtable slot 0xd80. That routine clears 0x6e0 bytes at host-object offset
// 0x1105c; every source byte rearranged into runtime 0x0ec..0x7c3 is within
// that cleared block. Initialize the proven destination explicitly rather
// than relying on the shared allocator's current zero-fill behavior.
pub fn initialize_g17_runtime_power_policy(buffer voidptr, size u64) bool {
	if buffer == unsafe { nil } || size < g17_runtime_data_size
		|| sizeof(G17RuntimeData) != g17_runtime_data_size {
		return false
	}
	unsafe {
		C.memset(voidptr(u64(buffer) + g17_runtime_power_policy_offset), 0, g17_runtime_power_policy_size)
	}
	return true
}

@[packed]
pub struct G17SmallSharedData {
pub mut:
	ktrace_state              u32
	host_ready                u32
	system_sleep_notification u32
	reserved_00c              u32
	firmware_power_state      u32
	reserved_014              u32
	reserved_018              u32
	asc_power_generation      u32
}

pub fn new_g17_small_shared_data(ktrace_state u32) G17SmallSharedData {
	return G17SmallSharedData{
		ktrace_state: ktrace_state
		host_ready: 1
	}
}

pub fn initialize_g17_small_shared_data(buffer voidptr, size u64, ktrace_state u32) bool {
	if buffer == unsafe { nil } || size != g17_small_shared_data_size
		|| sizeof(G17SmallSharedData) != g17_small_shared_data_size {
		return false
	}
	data := new_g17_small_shared_data(ktrace_state)
	unsafe {
		C.memcpy(buffer, &data, sizeof(G17SmallSharedData))
	}
	return true
}

@[packed]
pub struct G17PrimaryRegion {
pub mut:
	opaque [0xe440]u8
}

@[packed]
pub struct G17SecondaryRegion {
pub mut:
	opaque [0x6f0]u8
}

@[packed]
pub struct G17SecondaryAux {
pub mut:
	opaque [0xa8]u8
}

// These allocations are cleared by the pinned G17 host producer. Region 0x25c
// then receives two -1 sentinels; the remaining regions stay entirely zero.
// Their consumers have not yet given the individual bytes semantic names.
@[packed]
pub struct G17Role0Region254 {
pub mut:
	zero_000 [0xc18]u8
}

@[packed]
pub struct G17Role0Region25c {
pub mut:
	zero_000     [0xa18]u8
	sentinel_a18 u32
	zero_a1c     [0x14]u8
	sentinel_a30 u32
	zero_a34     [0x614]u8
}

@[packed]
pub struct G17Role0Region264 {
pub mut:
	zero_000 [0xe10]u8
}

@[packed]
pub struct G17Role0Region26c {
pub mut:
	zero_000 [0x68]u8
}

@[packed]
pub struct G17Role0Region274 {
pub mut:
	zero_000 [0x800]u8
}

@[packed]
pub struct G17SharedControl {
pub mut:
	zero_000 [0x88]u8
}

pub fn new_g17_role0_region_254() G17Role0Region254 {
	return G17Role0Region254{}
}

pub fn new_g17_role0_region_25c() G17Role0Region25c {
	return G17Role0Region25c{
		sentinel_a18: 0xffffffff
		sentinel_a30: 0xffffffff
	}
}

pub fn initialize_g17_role0_region_25c(buffer voidptr, size u64) bool {
	if buffer == unsafe { nil } || size != g17_role0_bootstrap_25c_size {
		return false
	}
	unsafe {
		C.memset(buffer, 0, size)
		*&u32(u64(buffer) + 0xa18) = 0xffffffff
		*&u32(u64(buffer) + 0xa30) = 0xffffffff
	}
	return true
}

pub fn new_g17_role0_region_264() G17Role0Region264 {
	return G17Role0Region264{}
}

pub fn new_g17_role0_region_26c() G17Role0Region26c {
	return G17Role0Region26c{}
}

pub fn new_g17_role0_region_274() G17Role0Region274 {
	return G17Role0Region274{}
}

pub fn new_g17_shared_control() G17SharedControl {
	return G17SharedControl{}
}

@[packed]
pub struct G17ColorMatrixRecord {
pub mut:
	coefficients [12]i16
}

// Modern G17 I/O mappings are 0x28 bytes rather than the 0x20-byte records in
// older AGX firmware. The host copies these fields from one of 53 accelerator
// PIO descriptors, then later replaces virtual_address when it installs the
// mapping in the firmware UAT.
@[packed]
pub struct G17IoMappingRecord {
pub mut:
	physical_address u64
	virtual_address  u64
	total_size       u32
	element_size     u32
	relative_offset  u64
	flags            u32
	padding          u32
}

@[packed]
pub struct G17VoltageTableRow {
pub mut:
	values [g17_voltage_table_columns]u32
}

@[packed]
pub struct G17AuxVoltageTableRow {
pub mut:
	values [g17_aux_voltage_table_columns]u32
}

// Firmware view of the optional CS and AFR clock-domain tables. Apple's host
// stores max_state at +0, its G17 domain cap at +4, then MHz frequencies,
// core millivolts, and SRAM millivolts.
@[packed]
pub struct G17AuxPerformanceBlock {
pub mut:
	performance_state_max u32
	performance_state_cap u32
	frequency_table       [g17_aux_performance_state_capacity]u32
	voltage_table         [g17_aux_performance_state_capacity]G17AuxVoltageTableRow
	sram_voltage_table    [g17_aux_performance_state_capacity]G17AuxVoltageTableRow
}

// G17C's selected map-register parser is a no-op, so the family fallback
// supplies an identity primary bank and a zero auxiliary bank.
@[packed]
pub struct G17PerformanceStateMapBlock {
pub mut:
	primary   [g17_performance_state_capacity]u32
	auxiliary [g17_performance_state_capacity]u32
}

// Fixed address-space prefix at the start of the hardware/configuration
// allocation. G17C uses an identity firmware-address conversion. Its selected
// setupCSCAllocation implementation is a no-op, so the optional YUV table
// mapping at +0x30 is deliberately zero.
@[packed]
pub struct G17AddressSpaceLayout {
pub mut:
	userspace_va_map      u64
	userspace_va_limit    u64
	usc_start_010         u64
	usc_start_018         u64
	unknown_page          u64
	timestamp_area_base   u64
	yuv_csc_table_address u64
}

pub fn new_g17_address_space_layout() G17AddressSpaceLayout {
	return G17AddressSpaceLayout{
		userspace_va_map: g17_userspace_va_map
		userspace_va_limit: g17_userspace_va_limit
		usc_start_010: g17_usc_start
		usc_start_018: g17_usc_start
		unknown_page: g17_unknown_page
		timestamp_area_base: g17_timestamp_area_base
		yuv_csc_table_address: 0
	}
}

// The selected PI_300 producer copies two 32-record read-only tables into the
// accelerator object. All records except 7, 8, and 28 in each bank are zero.
fn populate_g17_color_matrices(mut config G17HardwareConfig) {
	config.color_matrices_038[7].coefficients = [i16(8200), 0, 0, 0, 0, 8200, 0, 0, 0, 0, 8200,
		0]!
	config.color_matrices_038[8].coefficients = [i16(9419), 0, 11514, -13942, 9419, -2826, -5865,
		6263, 9419, 14553, 0, -16981]!
	config.color_matrices_038[28].coefficients = [i16(8192), -8, 11483, -11475, 8192, -2816, -5850,
		8666, 8192, 14518, 8, -14526]!
	config.color_matrices_038[32 + 7].coefficients = [i16(32736), 0, 0, 0, 0, 32736, 0, 0, 0, 0,
		32736, 0]!
	config.color_matrices_038[32 + 8].coefficients = [i16(-32768), 0, 0, 0, 0, -32768, 0, 0, 0,
		0, -32768, 0]!
	config.color_matrices_038[32 + 28].coefficients = [i16(9797), 19235, 3736, 0, -5537, -10846,
		16383, 16384, 16384, -13730, -2654, 16384]!
}

// Four-byte-aligned scalar controls at hardware-config offsets 0xe90..0xfc3.
// Only independently recovered startup values are populated here. This
// includes feature-derived words whose selected configureDevice producer is
// deterministic; all other feature-derived words remain zero.
@[packed]
pub struct G17FirmwareScalarBlock {
pub mut:
	values [g17_firmware_scalar_word_count]u32
}

fn g17_enabled_usc_count(hardware &hw.HwConfig) u32 {
	mut count := u32(0)
	mut any_mask := false
	for source_mask in hardware.core_mask_list {
		mut mask := source_mask
		if mask != 0 {
			any_mask = true
		}
		for mask != 0 {
			count += mask & 1
			mask >>= 1
		}
	}
	return if any_mask { count } else { hardware.gpu_core_count }
}

pub fn new_g17_firmware_scalar_block(hardware &hw.HwConfig, uat_ttb_base u64) G17FirmwareScalarBlock {
	mut result := G17FirmwareScalarBlock{}
	// retrieveChipInfo publishes the chosen-node chip ID followed by the
	// major/minor fields extracted from /arm-io/chip-revision.
	result.values[0] = hardware.chip_id
	result.values[1] = hardware.soc_revision_major
	result.values[2] = hardware.soc_revision_minor
	result.values[(0xeb8 - 0xe90) / 4] = 1
	// PI_300 configureDevice unconditionally installs accelerator feature bit
	// 10; initFirmwareData extracts that bit into this word.
	result.values[(0xec0 - 0xe90) / 4] = 1
	result.values[(0xec8 - 0xe90) / 4] = 1
	result.values[(0xed0 - 0xe90) / 4] = 24_000
	// The standard path starts with Apple's debug flags disabled, selecting 1.
	result.values[(0xed4 - 0xe90) / 4] = 1
	// G17's selected getSamplePeriod returns the native DeviceTree scalar
	// cached by configureDevice without applying a conversion.
	result.values[(0xed8 - 0xe90) / 4] = hardware.gpu_power_sample_period
	result.values[(0xee0 - 0xe90) / 4] = 1
	result.values[(0xee4 - 0xe90) / 4] = 1
	result.values[(0xee8 - 0xe90) / 4] = 1
	result.values[(0xf04 - 0xe90) / 4] = 31
	result.values[(0xf24 - 0xe90) / 4] = u32(g17_default_mcache_writes)
	result.values[(0xf28 - 0xe90) / 4] = u32(g17_default_mcache_writes >> 32)
	result.values[(0xf34 - 0xe90) / 4] = 1
	result.values[(0xf38 - 0xe90) / 4] = 1
	// configureDevice installs 0x31 at accelerator +0xf76c after clearing
	// the containing defaults. setupConfig copies it unchanged here.
	result.values[(0xf4c - 0xe90) / 4] = g17_setup_config_value_f4c
	result.values[(0xf88 - 0xe90) / 4] = g17_enabled_usc_count(hardware)
	result.values[(0xf8c - 0xe90) / 4] = u32(g17_fixed_config_value_f8c)
	result.values[(0xf90 - 0xe90) / 4] = u32(g17_fixed_config_value_f8c >> 32)
	// PI_300 start installs UAT configuration 4; the firmware record stores
	// only whether that value is nonzero.
	result.values[(0xfac - 0xe90) / 4] = 1
	// With gptbat-ready set, Apple's secure-monitor object reconstructs this
	// physical address from register 0xd0802c (PFN << 14). The live T6050
	// DeviceTree's gpu-region-base and ttbat-phys-addr-base encode the same
	// address, which is the reserved 64-context TTBR table used by our UAT.
	result.values[(0xfb0 - 0xe90) / 4] = u32(uat_ttb_base)
	result.values[(0xfb4 - 0xe90) / 4] = u32(uat_ttb_base >> 32)
	// getDeviceConfig exposes these same three fields at offsets 0x20, 0x24,
	// and 0x30. The base firmware producer copies them unchanged from the
	// accelerator core record into the hardware configuration.
	result.values[(0xfb8 - 0xe90) / 4] = hardware.firmware_gpu_core_id
	result.values[(0xfbc - 0xe90) / 4] = u32(hardware.gpu_rev)
	result.values[(0xfc0 - 0xe90) / 4] = hardware.gpu_core_count
	return result
}

// Hardware/configuration allocation published at offset zero of both
// firmware-shared objects. The host producer and primary firmware consumer
// independently establish the record boundaries below. Unknown scalar and
// derived-power meanings remain opaque.
@[packed]
pub struct G17HardwareConfig {
pub mut:
	address_space_layout_000          G17AddressSpaceLayout
	color_matrices_038                [g17_color_matrix_count]G17ColorMatrixRecord
	border_color_table_address_638    u64
	io_mappings_640                   [g17_io_mapping_count]G17IoMappingRecord
	opaque_e88                        [0x8]u8
	firmware_scalar_block_e90         G17FirmwareScalarBlock
	performance_state_max_fc4         u32
	frequency_table_fc8               [g17_performance_state_capacity]u32
	voltage_table_1008                [g17_performance_state_capacity]G17VoltageTableRow
	sram_voltage_table_1408           [g17_performance_state_capacity]G17VoltageTableRow
	secondary_frequency_table_1808    [g17_performance_state_capacity]u32
	sram_power_scale_1848             [g17_performance_state_capacity]u32
	static_power_scale_1888           [g17_performance_state_capacity]u32
	firmware_table_18c8               [g17_performance_state_capacity]u32
	relative_boost_frequency_1908     [g17_performance_state_capacity]u32
	firmware_table_1948               [g17_performance_state_capacity]u32
	afr_relative_boost_frequency_1988 [g17_performance_state_capacity]u32
	performance_state_map_19c8        G17PerformanceStateMapBlock
	cs_performance_1a48               G17AuxPerformanceBlock
	afr_performance_1b90              G17AuxPerformanceBlock
	// Second performance-state block, shaped like the primary one at +0xfc4
	// and sourced from the accelerator's SRAM-side arrays at
	// +0x1bb58/+0x1bb60/+0x1bba0. Its producer is gated on accelerator byte
	// +0x505 and that gate is always clear on G17, so these stay zero; the
	// fields are typed to record the layout, not to be filled.
	secondary_performance_max_1cd8 u32
	secondary_frequency_1cdc       [g17_performance_state_capacity]u32
	secondary_voltage_1d1c         [g17_performance_state_capacity]G17VoltageTableRow
	secondary_sram_voltage_211c    [g17_performance_state_capacity]G17VoltageTableRow
	opaque_251c                    [0x24]u8
	firmware_late_controls_2540    [0x1d0]u8
}

pub fn validate_g17_bootstrap_allocations() bool {
	return sizeof(G17BootstrapPage) == g17_bootstrap_page_size && sizeof(G17InitRegisterEntry) == g17_init_register_entry_size && sizeof(G17FirmwareSharedData) == g17_firmware_shared_data_size && sizeof(G17RuntimeData) == g17_runtime_data_size && sizeof(G17FwUtilPStateControl) == g17_fw_util_pstate_control_size && sizeof(G17RegisterOverride) == g17_register_override_size && sizeof(G17SmallSharedData) == g17_small_shared_data_size && sizeof(G17PrimaryRegion) == g17_primary_region_size && sizeof(G17SecondaryRegion) == g17_secondary_region_size && sizeof(G17SecondaryAux) == g17_secondary_aux_size && sizeof(G17Role0Region254) == g17_role0_bootstrap_254_size && sizeof(G17Role0Region25c) == g17_role0_bootstrap_25c_size && sizeof(G17Role0Region264) == g17_role0_bootstrap_264_size && sizeof(G17Role0Region26c) == g17_role0_bootstrap_26c_size && sizeof(G17Role0Region274) == g17_role0_bootstrap_274_size && sizeof(G17SharedControl) == g17_common_control_size && sizeof(G17HardwareConfig) == g17_hardware_config_size && sizeof(G17AddressSpaceLayout) == g17_address_space_layout_size && sizeof(G17FirmwareScalarBlock) == g17_firmware_scalar_block_size && sizeof(G17ColorMatrixRecord) == g17_color_matrix_size && sizeof(G17IoMappingRecord) == g17_io_mapping_size && sizeof(G17VoltageTableRow) == g17_voltage_table_columns * sizeof(u32) && sizeof(G17AuxVoltageTableRow) == g17_aux_voltage_table_columns * sizeof(u32) && sizeof(G17AuxPerformanceBlock) == g17_aux_performance_block_size && sizeof(G17PerformanceStateMapBlock) == g17_performance_state_map_block_size && sizeof(G17SchedulerState) == g17_scheduler_state_size
}

// G17PowerMatrix carries one Apple power-matrix row per performance state.
// The primary matrix lives at accelerator +0x1c630 with a 16-column row, the
// AFR matrix at +0x1ca30 with a 2-column row. Apple fills both from an analog
// leakage model seeded with per-die fuse calibration, so the rows are machine
// specific and cannot be embedded here; the caller supplies them.
pub struct G17PowerMatrix {
pub mut:
	state_count u32
	columns     u32
	stride      u32
	values      [g17_performance_state_capacity * g17_voltage_table_columns]u32
}

// Per-die leakage calibration recovered from the G17 fuse aperture. Values
// are kept in quarter units so the M5 Max path does not need floating point.
// g17_power_model.v combines them with generated, version-pinned Q24.40
// evaluations of Apple's fixed-temperature leakage equation.
pub struct G17LeakageCalibration {
pub mut:
	core_count             u32
	group_count            u32
	core_combined_quarters [g17_leakage_core_capacity]u32
	group_quarters         [g17_leakage_group_capacity]u32
}

// Decode the three fuse words consumed by populateChipLeakageData. G17C uses
// selector order 0,1,2,3 twice. Selectors 0/3 take bits 8..21 of word 0x198;
// selectors 1/2 join bits 22..31 of 0x198 with bits 0..3 of 0x19c. Every core
// also receives bits 4..15 of 0x19c. The group field crosses the 0x19c/0x1a0
// boundary. Variant 0x21 applies the alternate x2 and /2 scales; M5 Max is
// variant 0x22 and takes x1 and /4.
pub fn decode_g17_leakage_calibration(word_198 u32, word_19c u32, word_1a0 u32,
	chip_variant u32, core_count u32, group_count u32) ?G17LeakageCalibration {
	if core_count == 0 || core_count > g17_leakage_core_capacity
		|| group_count == 0 || group_count > g17_leakage_group_capacity
		|| chip_variant < 0x20 || chip_variant > 0x22 {
		return none
	}

	plain := (word_198 >> 8) & 0x3fff
	joined := ((word_198 >> 22) & 0x3ff) | ((word_19c & 0xf) << 10)
	secondary := (word_19c >> 4) & 0xfff
	selectors := [u32(0), 1, 2, 3, 0, 1, 2, 3]!

	mut result := G17LeakageCalibration{
		core_count: core_count
		group_count: group_count
	}
	for core := u32(0); core < core_count; core++ {
		primary := if selectors[core] == 0 || selectors[core] == 3 { plain } else { joined }
		// Store exact quarter units: x2 becomes x8 quarters, x1 becomes x4;
		// /2 becomes x2 quarters and /4 becomes x1.
		primary_quarters := primary * if chip_variant == 0x21 { u32(8) } else { u32(4) }
		secondary_quarters := secondary * if chip_variant == 0x21 { u32(2) } else { u32(1) }
		result.core_combined_quarters[core] = primary_quarters + secondary_quarters
	}

	joined_groups := (u64(word_1a0) << 32) | u64(word_19c)
	group_quarters := u32((joined_groups >> 25) & 0xfff) * 8
	for group := u32(0); group < group_count; group++ {
		result.group_quarters[group] = group_quarters
	}
	return result
}

fn g17_power_matrix_row_sum(matrix &G17PowerMatrix, state u32) u32 {
	mut total := u32(0)
	for column := u32(0); column < matrix.columns; column++ {
		total += matrix.values[state * matrix.stride + column]
	}
	return total
}

// Reproduce AGXAccelerator::populateLinearPowerTransferTable for one table.
// Entries below the base state are cleared and the rest are rescaled into
// 0..100 against the maximum state. Apple sums, subtracts, multiplies and
// divides in 32 bits, so the wraparound is part of the ABI and this must not
// be widened to 64-bit arithmetic.
fn g17_linear_power_transfer_curve(matrix &G17PowerMatrix, base_state u32) ?[g17_performance_state_capacity]u32 {
	if matrix.state_count == 0 || matrix.state_count > g17_performance_state_capacity {
		return none
	}
	if matrix.columns == 0 || matrix.stride == 0 || matrix.columns > matrix.stride
		|| matrix.stride > g17_voltage_table_columns {
		return none
	}
	if base_state >= matrix.state_count {
		return none
	}
	base := g17_power_matrix_row_sum(matrix, base_state)
	maximum := g17_power_matrix_row_sum(matrix, matrix.state_count - 1)
	if maximum <= base {
		return none
	}
	range := maximum - base
	mut values := [g17_performance_state_capacity]u32{}
	for state := base_state; state < matrix.state_count; state++ {
		delta := g17_power_matrix_row_sum(matrix, state) - base
		values[state] = delta * g17_linear_power_transfer_maximum / range
	}
	return values
}

// Fill both gated linear power-transfer tables. Apple calls the shared
// producer for +0x18c8 with the primary matrix and inlines the same
// normalisation for +0x1948 against the AFR matrix; both use base state 0.
pub fn populate_g17_linear_power_transfer_tables(mut config G17HardwareConfig, primary &G17PowerMatrix, afr &G17PowerMatrix) bool {
	primary_curve := g17_linear_power_transfer_curve(primary, 0) or { return false }
	afr_curve := g17_linear_power_transfer_curve(afr, 0) or { return false }
	config.firmware_table_18c8 = primary_curve
	config.firmware_table_1948 = afr_curve
	return true
}

fn populate_g17_performance_state_map(mut config G17HardwareConfig) {
	for state := 0; state < g17_performance_state_capacity; state++ {
		config.performance_state_map_19c8.primary[state] = u32(state)
	}
}

// Populate the table subset whose source and scale are established by both
// the Apple DeviceTree and the G17 host producer. Frequencies are converted
// from Hz to MHz exactly as the host does. Derived power tables remain zero
// until their producers have been recovered.
pub fn populate_g17_performance_tables(mut config G17HardwareConfig, hardware &hw.HwConfig) bool {
	if hardware.perf_state_count == 0 || hardware.perf_state_count > g17_performance_state_capacity || hardware.perf_state_table_count == 0 || hardware.perf_state_table_count > g17_voltage_table_columns {
		return false
	}
	if hardware.perf_state_base == 0 || hardware.perf_state_base >= hardware.perf_state_count - 1 {
		return false
	}
	base_frequency := hardware.perf_state_frequencies[hardware.perf_state_base]
	max_frequency := hardware.perf_state_frequencies[hardware.perf_state_count - 1]
	if max_frequency <= base_frequency {
		return false
	}

	config.performance_state_max_fc4 = hardware.perf_state_count - 1
	for state := u32(0); state < hardware.perf_state_count; state++ {
		config.frequency_table_fc8[state] = hardware.perf_state_frequencies[state] / 1_000_000
		config.sram_power_scale_1848[state] = g17_sram_power_scale
		// Apple's second source is the perf-states-sram frequency column. The
		// parser has already required it to match the core frequency exactly.
		config.secondary_frequency_table_1808[state] = hardware.perf_state_frequencies[state] / 1_000_000
		base_voltage := hardware.perf_state_voltages[state * g17_voltage_table_columns]
		base_sram_voltage := hardware.perf_state_sram_voltages[state * g17_voltage_table_columns]
		for table := u32(0); table < g17_voltage_table_columns; table++ {
			offset := state * g17_voltage_table_columns + table
			config.voltage_table_1008[state].values[table] = if table < hardware.perf_state_table_count {
				hardware.perf_state_voltages[offset]
			} else {
				base_voltage
			}
			config.sram_voltage_table_1408[state].values[table] = if table < hardware.perf_state_table_count {
				hardware.perf_state_sram_voltages[offset]
			} else {
				base_sram_voltage
			}
		}
	}
	// The second performance-state block stays zero on G17. Its producer is
	// gated on accelerator byte +0x505, which getProbeScore relays from
	// chip-info +0x85; that record is cleared and no selected G17C reader
	// writes the byte, so Apple's TBZ always skips the block. The fields are
	// typed above to document the layout, not because they are filled.
	for state := hardware.perf_state_base + 1; state < hardware.perf_state_count; state++ {
		frequency_delta := u64(hardware.perf_state_frequencies[state] - base_frequency)
		frequency_range := u64(max_frequency - base_frequency)
		config.relative_boost_frequency_1908[state] = u32(frequency_delta * 100 / frequency_range)
	}
	if hardware.afr_perf_states.state_count == 0
		|| hardware.afr_perf_states.state_count > g17_performance_state_capacity
		|| hardware.perf_state_base >= hardware.afr_perf_states.state_count - 1 {
		return false
	}
	afr_base_frequency := hardware.afr_perf_states.frequencies[hardware.perf_state_base]
	afr_max_frequency := hardware.afr_perf_states.frequencies[hardware.afr_perf_states.state_count - 1]
	if afr_max_frequency <= afr_base_frequency {
		return false
	}
	for state := hardware.perf_state_base + 1; state < hardware.afr_perf_states.state_count; state++ {
		frequency_delta := u64(hardware.afr_perf_states.frequencies[state] - afr_base_frequency)
		frequency_range := u64(afr_max_frequency - afr_base_frequency)
		config.afr_relative_boost_frequency_1988[state] = u32(frequency_delta * 100 / frequency_range)
	}
	populate_g17_performance_state_map(mut config)
	return true
}

fn populate_g17_aux_performance_block(mut destination G17AuxPerformanceBlock, source &hw.AuxPerfStateConfig) bool {
	if source.state_count == 0 || source.state_count > g17_aux_performance_state_capacity
		|| source.table_count == 0 || source.table_count > g17_aux_voltage_table_columns {
		return false
	}
	destination.performance_state_max = source.state_count - 1
	// The selected G17C getPerfStateCap implementation returns 14 for both
	// the CS and AFR domains, independently of the parsed table count.
	destination.performance_state_cap = g17_aux_performance_state_cap
	for state := u32(0); state < source.state_count; state++ {
		destination.frequency_table[state] = source.frequencies[state] / 1_000_000
		for table := u32(0); table < source.table_count; table++ {
			index := state * g17_aux_voltage_table_columns + table
			destination.voltage_table[state].values[table] = source.voltages[index]
			destination.sram_voltage_table[state].values[table] = source.sram_voltages[index]
		}
	}
	return true
}

fn populate_g17_pio_mappings(mut config G17HardwareConfig, hardware &hw.HwConfig) bool {
	// Recovered from the G17C getPIORelativeOffsetTable virtual selected by
	// the pinned macOS 26.5 driver. Entries whose primary offset is -1 use a
	// different host-only mapping path and do not populate these records.
	indices := [u32(17), 47, 26, 29, 31, 33, 34, 28, 32, 35, 37, 43]
	offsets := [u64(0), 0x23d00, 0xd04000, 0xd10000, 0xd40000, 0xd44000, 0xd4c000, 0xd50000,
		0xd60000, 0xe00000, 0xe40000, 0xe60000]
	sizes := [u32(0x21500), 0x200, 0x8000, 0x4000, 0x4000, 0x4000, 0x200, 0x10000, 0x20000, 0x4000,
		0x4000, 0x58]

	if hardware.gpu_mmio_base == 0 || hardware.gpu_mmio_size == 0 {
		return false
	}
	for mapping := 0; mapping < indices.len; mapping++ {
		end := offsets[mapping] + u64(sizes[mapping])
		if end < offsets[mapping] || end > hardware.gpu_mmio_size {
			return false
		}
		index := indices[mapping]
		config.io_mappings_640[index] = G17IoMappingRecord{
			physical_address: hardware.gpu_mmio_base + offsets[mapping]
			total_size: sizes[mapping]
			element_size: sizes[mapping]
			relative_offset: offsets[mapping]
			// All twelve source records are initialized with bit 1. The host
			// passes that bit as the writable argument to createFWPIOMapping.
			flags: 2
		}
	}
	return true
}

// Initialize the recovered DeviceTree-backed subset directly in mapped
// storage. This avoids placing the 0x2710-byte object on the kernel stack.
// Outstanding pieces of the G17 hardware configuration, as a bitmask. The
// firmware boot gate is derived from this rather than from a bare `false`, so
// the blockers are enumerated where they would be fixed and the gate opens by
// construction once they are all gone.
pub const g17_gap_linear_power_transfer = u32(1 << 0)
pub const g17_gap_late_control_runtime = u32(1 << 1)

// Bits still set for this build. Each has a recovered reason:
//
//   linear_power_transfer  CLEARED. Config +0x18c8 and +0x1948 are built from
//                          the recovered main/AFR power matrices. The four-pow
//                          fixed-temperature leakage equation is generated as
//                          Q24.40 factors and its binary32 rounding boundaries
//                          are reproduced with integer operations.
//
//   late_control_runtime   CLEARED. All 36 fields in +0x2540..+0x270f are
//                          accounted for: 34 fixed and two computed from the
//                          core-mask and identity registers.
//
// Anything not listed here is recovered and emitted.
pub fn g17_hardware_config_gaps() u32 {
	return 0
}

// The hardware configuration may only be handed to firmware once every gap is
// closed. A partially correct config is worse than none: firmware acts on it,
// so a wrong power curve or control word wedges the GPU rather than failing.
pub fn g17_hardware_config_complete() bool {
	return g17_hardware_config_gaps() == 0
}

pub const g17_late_controls_offset = u64(0x2540)
pub const g17_late_controls_size = u64(0x1d0)

// The statically determined part of the late-control block. Apple's ARM
// producer writes 36 fields into config +0x2540..+0x270f; 34 are fixed
// for G17, including four tests of the fixed feature mask and one more field
// derived from it, all of which come out zero. The other two are computed
// from hardware. Every field in the block is now accounted for.
// Values the late-control block needs that are read from hardware rather than
// fixed. Passed as a struct so adding the remaining ones does not keep
// widening the hardware-config signature.
pub struct G17LateControlInputs {
pub:
	enabled_core_count u32
	unit_mask          u32
}

fn populate_g17_late_controls(mut config G17HardwareConfig, inputs G17LateControlInputs) {
	fixed_u32 := [
		u64(0x2540),
		0x2548,
		0x255c,
		0x2574,
		0x258c,
		0x259c,
		0x25a4,
		0x25a8,
		0x25b4,
		0x25b8,
		0x25ec,
		0x25f0,
		0x26c4,
		0x26e0,
		0x2706,
		0x270a,
		// These read accelerator members that nothing ever writes; the
		// accelerator is zero-allocated, so the sources and these fields are
		// clear. +0x2544 is only written when its source is nonzero, which it
		// never is.
		0x2544,
		0x25f4,
		0x26a4,
		0x26bc,
		// Guarded by a feature bit that is clear, so its store never runs.
		0x25ac,
		// The address converter is the identity and its input member is only
		// ever cleared, so this converts zero to zero.
		0x269c,
	]!
	unsafe {
		base := &u8(&config.firmware_late_controls_2540[0])
		for offset in fixed_u32 {
			mut slot := &u32(base + offset - g17_late_controls_offset)
			*slot = 0
		}
		for offset in [u64(0x2578), 0x25a0, 0x26c0]! {
			mut slot := &u32(base + offset - g17_late_controls_offset)
			*slot = 1
		}
		for offset in [u64(0x2600), 0x26a8, 0x25f8]! {
			mut wide := &u64(base + offset - g17_late_controls_offset)
			*wide = 0
		}
		// +0x2560 copies the accelerator core-mask pair, but only when either
		// half is nonzero. Those halves are the chip-info record's first two
		// words, which no selected G17C reader writes, so the copy never runs.
		C.memset(voidptr(base + u64(0x2560) - g17_late_controls_offset), 0, 16)
		mut one := &u64(base + u64(0x26f0) - g17_late_controls_offset)
		*one = 1
		// +0x2570 has two producers picked by a chip-info byte that is always
		// set, so the population count of the core masks always wins over the
		// scaled core count.
		mut cores := &u32(base + u64(0x2570) - g17_late_controls_offset)
		*cores = inputs.enabled_core_count
		// +0x2554 is a mask sized by the third chip-info nibble product.
		mut units := &u32(base + u64(0x2554) - g17_late_controls_offset)
		*units = inputs.unit_mask
		// A 48-byte run of ones at +0x25bc, written as two vector stores.
		C.memset(voidptr(base + u64(0x25bc) - g17_late_controls_offset), 0xff, 0x30)
		// Copied from accelerator members configureDevice clears before this
		// runs, so both bytes are zero here.
		mut copied := base + u64(0x26f8) - g17_late_controls_offset
		*copied = 0
		*(copied + 1) = 0
	}
}

pub fn initialize_g17_hardware_config(buffer voidptr, size u64, hardware &hw.HwConfig,
	uat_ttb_base u64, inputs G17LateControlInputs) bool {
	if buffer == unsafe { nil } || size != g17_hardware_config_size
		|| sizeof(G17HardwareConfig) != g17_hardware_config_size
		|| uat_ttb_base == 0 || uat_ttb_base & (g17_bootstrap_page_size - 1) != 0
		|| hardware.firmware_gpu_core_id == 0 || hardware.gpu_rev == .unknown
		|| hardware.perf_state_count == 0
		|| hardware.perf_state_count > g17_performance_state_capacity
		|| hardware.perf_state_table_count == 0
		|| hardware.perf_state_table_count > g17_voltage_table_columns
		|| hardware.perf_state_base == 0 || hardware.perf_state_base >= hardware.perf_state_count - 1 {
		return false
	}

	unsafe {
		C.memset(buffer, 0, size)
		mut config := &G17HardwareConfig(buffer)
		config.address_space_layout_000 = new_g17_address_space_layout()
		populate_g17_color_matrices(mut config)
		// G17's selected virtual provider returns zero for this optional table.
		config.border_color_table_address_638 = 0
		populate_g17_late_controls(mut config, inputs)
		config.firmware_scalar_block_e90 = new_g17_firmware_scalar_block(hardware, uat_ttb_base)
		if !populate_g17_pio_mappings(mut config, hardware) {
			return false
		}
		if !populate_g17_aux_performance_block(mut config.cs_performance_1a48, &hardware.cs_perf_states)
			|| !populate_g17_aux_performance_block(mut config.afr_performance_1b90, &hardware.afr_perf_states) {
			return false
		}
		config.performance_state_max_fc4 = hardware.perf_state_count - 1
		base_frequency := hardware.perf_state_frequencies[hardware.perf_state_base]
		max_frequency := hardware.perf_state_frequencies[hardware.perf_state_count - 1]
		if max_frequency <= base_frequency {
			return false
		}
		for state := u32(0); state < hardware.perf_state_count; state++ {
			config.frequency_table_fc8[state] = hardware.perf_state_frequencies[state] / 1_000_000
			config.sram_power_scale_1848[state] = g17_sram_power_scale
			config.secondary_frequency_table_1808[state] = hardware.perf_state_frequencies[state] / 1_000_000
			base_voltage := hardware.perf_state_voltages[state * g17_voltage_table_columns]
			base_sram_voltage := hardware.perf_state_sram_voltages[state * g17_voltage_table_columns]
			for table := u32(0); table < g17_voltage_table_columns; table++ {
				offset := state * g17_voltage_table_columns + table
				config.voltage_table_1008[state].values[table] = if table < hardware.perf_state_table_count {
					hardware.perf_state_voltages[offset]
				} else {
					base_voltage
				}
				config.sram_voltage_table_1408[state].values[table] = if table < hardware.perf_state_table_count {
					hardware.perf_state_sram_voltages[offset]
				} else {
					base_sram_voltage
				}
			}
		}
		for state := hardware.perf_state_base + 1; state < hardware.perf_state_count; state++ {
			frequency_delta := u64(hardware.perf_state_frequencies[state] - base_frequency)
			frequency_range := u64(max_frequency - base_frequency)
			config.relative_boost_frequency_1908[state] = u32(frequency_delta * 100 / frequency_range)
		}
		if hardware.perf_state_base >= hardware.afr_perf_states.state_count - 1 {
			return false
		}
		afr_base_frequency := hardware.afr_perf_states.frequencies[hardware.perf_state_base]
		afr_max_frequency := hardware.afr_perf_states.frequencies[hardware.afr_perf_states.state_count - 1]
		if afr_max_frequency <= afr_base_frequency {
			return false
		}
		for state := hardware.perf_state_base + 1; state < hardware.afr_perf_states.state_count; state++ {
			frequency_delta := u64(hardware.afr_perf_states.frequencies[state] - afr_base_frequency)
			frequency_range := u64(afr_max_frequency - afr_base_frequency)
			config.afr_relative_boost_frequency_1988[state] = u32(frequency_delta * 100 / frequency_range)
		}
		populate_g17_performance_state_map(mut config)
	}
	return true
}

// Each G17 work context owns a state object and separate cached/uncached
// allocations. The state points at the GPU mappings; the host updates the
// uncached indices and stores command addresses in the cached pointer array.
@[packed]
pub struct G17ChannelState {
pub mut:
	uncached_gpu_address u64
	cached_gpu_address   u64
	context_cookie       u64
	control_018          u32
	control_01c          u32
	control_020          u32
	sentinel_024         u32
	mode_028             u32
	mode_02c             u32
	threshold_030        u64
	control_038          u32
	subpriority_03c      u32
	qos_040              u32
	sentinel_044         u32
	owning_process_id    u32
	opaque_04c           [0x38]u8
	flag_084             u32
	opaque_088           [0x14]u8
	queue_address_09c    u64
	opaque_0a4           [0x1c]u8
}

@[packed]
pub struct G17ChannelControl {
pub mut:
	read_index   u32
	opaque_004   [0x0c]u8
	control_010  u32
	opaque_014   [0x0c]u8
	control_020  u32
	opaque_024   [0x0c]u8
	control_030  u32
	opaque_034   [0x0c]u8
	write_index  u32
	opaque_044   [0x0c]u8
	sentinel_050 u32
	opaque_054   [0x0c]u8
	ring_entries u32
	opaque_064   [0x0c]u8
}

@[packed]
pub struct G17CachedCommandPointer {
pub mut:
	address u64
}

// Derive the firmware pointer-ring capacity exactly as AGXChannel::init does.
// The configured device count is capped before multiplication, so this helper
// cannot overflow and remains valid for a future device-tree override.
pub fn g17_channel_ring_entries(configured_queues u32) u32 {
	request := if configured_queues < g17_maximum_channel_queue_request {
		configured_queues
	} else {
		g17_maximum_channel_queue_request
	}
	return request * g17_channel_pointers_per_queue
}

// The cached and uncached channel pools both use this element geometry.  For
// T6050's recovered default of 80 it is 0x2870 bytes, of which the cached
// channel consumes 0x2800 bytes as 1,280 eight-byte command pointers.
pub fn g17_channel_memory_size(configured_queues u32) u64 {
	return g17_channel_pool_base_size + u64(configured_queues) * g17_channel_pool_queue_stride
}

// Byte size of every G17 channel command, from the table
// AGXFirmware::configurePoolElementSizes installs.
pub const g17_command_ta_size = u32(0x9c0)
pub const g17_command_3d_size = u32(0x2240)
pub const g17_command_fast_blit_size = u32(0xa00)
pub const g17_command_cl_size = u32(0x1040)
pub const g17_command_barrier_size = u32(0x80)
pub const g17_command_pm_grow_size = u32(0x40)
pub const g17_command_pm_rebuild_size = u32(0x40)
pub const g17_command_remote_node_size = u32(0x80)
pub const g17_command_final_frg_kick_size = u32(0x40)
pub const g17_command_ksm_add_kicks_size = u32(0x40)
pub const g17_command_ksm_config_update_size = u32(0xc0)
pub const g17_command_ksm_kick_queue_size = u32(0x40)
pub const g17_channel_command_known_prefix_size = u64(0x6a)
pub const g17_shared_stream_parser_size = u64(0x18)
pub const g17_hardware_command_header_size = u64(0xc0)
pub const g17_parsed_hardware_command_size = u64(0x170)
pub const g17_hardware_command_payload_length_offset = u64(0x9c)
pub const g17_primary_extension_length_offset = u64(0x90)
pub const g17_aux_u16_extension_gate_offset = u64(0x88)
pub const g17_aux_u16_extension_length_offset = u64(0x8c)
pub const g17_aux_u64_extension_gate_offset = u64(0x94)
pub const g17_aux_u64_extension_length_offset = u64(0x98)
pub const g17_extension_count_header_size = u64(0x10)
pub const g17_hardware_command_terminator_error = u32(0x100)
pub const g17_hardware_command_auxiliary_error = u32(0x102)
pub const g17_render_payload_size = u64(0x9d0)
pub const g17_render_kernel_command_size = u64(0x284)
pub const g17_render_payload_framing_error = u32(0x100)
pub const g17_render_payload_validation_error = u32(0x0a)
pub const g17_command_pool_fallback_capacity = u32(80)
pub const g17_work_command_pool_multiplier = u32(3)
pub const g17_fallback_work_command_slots = g17_command_pool_fallback_capacity * g17_work_command_pool_multiplier

// Common packed prefix written by AGXChannel::submitNopUnprepared after a
// command slot has been selected. Only these four host-written fields are
// named. In particular, callers must preserve every opaque byte because the
// pool backing constructor may have installed command-specific templates.
@[packed]
pub struct G17ChannelCommandKnownPrefix {
pub mut:
	opaque_000       [0x1a]u8
	control_01a      u32
	opaque_01e       [0x04]u8
	data_master_type u32
	opaque_026       [0x0c]u8
	control_032      u32
	opaque_036       [0x2c]u8
	control_062      u64
}

// Apply only the recovered common fields to an existing pool command. This
// intentionally does not clear the command or any opaque byte.
pub fn populate_g17_channel_command_common_fields(command voidptr, command_bytes u64,
	data_master_type u32) bool {
	if command == unsafe { nil } || command_bytes < g17_channel_command_known_prefix_size
		|| data_master_type > g17_accelerator_command_cl {
		return false
	}

	unsafe {
		mut prefix := &G17ChannelCommandKnownPrefix(command)
		prefix.control_01a = 1
		prefix.data_master_type = data_master_type
		prefix.control_032 = 0
		prefix.control_062 = 0
	}
	return true
}

// Cursor layout used by AGXSharedStreamParser. Vinix constructs these from
// kernel-owned staged buffers; start/end/cursor are never accepted from
// userspace. Keeping addresses as integers makes every bounds transition
// explicit and avoids undefined pointer arithmetic at the end of a span.
@[packed]
pub struct G17SharedStreamParser {
pub mut:
	start  u64
	end    u64
	cursor u64
}

pub fn initialize_g17_shared_stream_parser(mut parser G17SharedStreamParser, data voidptr,
	bytes u64) bool {
	start := u64(data)
	if (data == unsafe { nil } && bytes != 0) || bytes > ~u64(0) - start {
		return false
	}
	parser.start = start
	parser.end = start + bytes
	parser.cursor = start
	return true
}

struct G17StreamSpan {
	start u64
	end   u64
}

fn take_g17_stream_span(mut parser G17SharedStreamParser, bytes u64) ?G17StreamSpan {
	if parser.cursor < parser.start || parser.cursor > parser.end
		|| bytes > ~u64(0) - parser.cursor {
		return none
	}
	end := parser.cursor + bytes
	if end > parser.end {
		return none
	}
	span := G17StreamSpan{
		start: parser.cursor
		end: end
	}
	parser.cursor = end
	return span
}

fn take_g17_span_address(cursor u64, end u64, count u64, element_bytes u64) ?G17StreamSpan {
	if element_bytes != 0 && count > ~u64(0) / element_bytes {
		return none
	}
	bytes := count * element_bytes
	if cursor > end || bytes > ~u64(0) - cursor || cursor + bytes > end {
		return none
	}
	return G17StreamSpan{
		start: cursor
		end: cursor + bytes
	}
}

fn read_g17_u32(address u64) u32 {
	mut value := u32(0)
	unsafe {
		C.memcpy(&value, voidptr(address), sizeof(u32))
	}
	return value
}

// Host-side result of AGXHardwareKernelCommand::parseAndValidate. The object
// points into the staged primary and auxiliary streams; it must be consumed
// before those buffers are released and must never be sent to firmware as-is.
@[packed]
pub struct G17ParsedHardwareCommand {
pub mut:
	opaque_000               [0x08]u8
	success                  u8
	opaque_009               [0x03]u8
	error_marker             u32
	record_header            [0xc0]u8
	payload_start            u64
	payload_end              u64
	payload_pointer          u64
	primary_extension_counts [4]u32
	primary_u16_array        u64
	primary_24_byte_array    u64
	opaque_108               [0x18]u8
	aux_u16_extension_counts [4]u32
	aux_u16_arrays           [4]u64
	aux_u64_extension_counts [4]u32
	aux_u64_group_arrays     [2]u64
}

fn fail_g17_hardware_command(mut command G17ParsedHardwareCommand, marker u32) bool {
	command.success = 0
	command.error_marker = marker
	return false
}

// Parse one base hardware-command record from two kernel-owned streams. The
// primary stream contains the fixed header, payload, and optional primary
// extension; the two auxiliary extensions consume consecutive ranges from the
// separate auxiliary stream. Successful pointers always remain inside their
// corresponding staged span.
pub fn parse_g17_hardware_command(mut command G17ParsedHardwareCommand,
	mut primary G17SharedStreamParser, mut auxiliary G17SharedStreamParser) bool {
	command.success = 0
	command.error_marker = 0
	command.payload_start = 0
	command.payload_end = 0
	command.payload_pointer = 0
	command.primary_u16_array = 0
	command.primary_24_byte_array = 0
	for index := 0; index < 4; index++ {
		command.aux_u16_arrays[index] = 0
	}
	command.aux_u64_group_arrays[0] = 0
	command.aux_u64_group_arrays[1] = 0

	header := take_g17_stream_span(mut primary, g17_hardware_command_header_size) or {
		return fail_g17_hardware_command(mut command, g17_hardware_command_terminator_error)
	}
	unsafe {
		C.memcpy(&command.record_header[0], voidptr(header.start), g17_hardware_command_header_size)
	}

	payload_length := read_g17_u32(header.start + g17_hardware_command_payload_length_offset)
	payload := take_g17_stream_span(mut primary, u64(payload_length)) or {
		return fail_g17_hardware_command(mut command, g17_hardware_command_terminator_error)
	}
	if payload.start == payload.end {
		return fail_g17_hardware_command(mut command, g17_hardware_command_terminator_error)
	}
	command.payload_start = payload.start
	command.payload_end = payload.end
	command.payload_pointer = payload.start

	primary_extension_bytes := read_g17_u32(header.start + g17_primary_extension_length_offset)
	if primary_extension_bytes != 0 {
		extension := take_g17_stream_span(mut primary, g17_extension_count_header_size + u64(primary_extension_bytes)) or {
			return fail_g17_hardware_command(mut command, g17_hardware_command_terminator_error)
		}
		unsafe {
			C.memcpy(&command.primary_extension_counts[0], voidptr(extension.start), g17_extension_count_header_size)
		}
		mut cursor := extension.start + g17_extension_count_header_size
		first_array := take_g17_span_address(cursor, extension.end, u64(command.primary_extension_counts[0]), 2) or {
			return fail_g17_hardware_command(mut command, g17_hardware_command_terminator_error)
		}
		command.primary_u16_array = first_array.start
		cursor = first_array.end
		second_array := take_g17_span_address(cursor, extension.end, u64(command.primary_extension_counts[1]), 24) or {
			return fail_g17_hardware_command(mut command, g17_hardware_command_terminator_error)
		}
		command.primary_24_byte_array = second_array.start
	}

	if read_g17_u32(header.start + g17_aux_u16_extension_gate_offset) != 0 {
		extension_bytes := read_g17_u32(header.start + g17_aux_u16_extension_length_offset)
		extension := take_g17_stream_span(mut auxiliary, u64(extension_bytes)) or {
			return fail_g17_hardware_command(mut command, g17_hardware_command_auxiliary_error)
		}
		if u64(extension_bytes) < g17_extension_count_header_size {
			return fail_g17_hardware_command(mut command, g17_hardware_command_auxiliary_error)
		}
		unsafe {
			C.memcpy(&command.aux_u16_extension_counts[0], voidptr(extension.start), g17_extension_count_header_size)
		}
		mut cursor := extension.start + g17_extension_count_header_size
		for index := 0; index < 4; index++ {
			array := take_g17_span_address(cursor, extension.end, u64(command.aux_u16_extension_counts[index]), 2) or {
				return fail_g17_hardware_command(mut command, g17_hardware_command_auxiliary_error)
			}
			command.aux_u16_arrays[index] = array.start
			cursor = array.end
		}
	}

	if read_g17_u32(header.start + g17_aux_u64_extension_gate_offset) != 0 {
		extension_bytes := read_g17_u32(header.start + g17_aux_u64_extension_length_offset)
		extension := take_g17_stream_span(mut auxiliary, u64(extension_bytes)) or {
			return fail_g17_hardware_command(mut command, g17_hardware_command_auxiliary_error)
		}
		if u64(extension_bytes) < g17_extension_count_header_size {
			return fail_g17_hardware_command(mut command, g17_hardware_command_auxiliary_error)
		}
		unsafe {
			C.memcpy(&command.aux_u64_extension_counts[0], voidptr(extension.start), g17_extension_count_header_size)
		}
		mut cursor := extension.start + g17_extension_count_header_size
		first_group_count := u64(command.aux_u64_extension_counts[0]) + u64(command.aux_u64_extension_counts[1])
		second_group_count := u64(command.aux_u64_extension_counts[2]) + u64(command.aux_u64_extension_counts[3])
		first_group := take_g17_span_address(cursor, extension.end, first_group_count, 8) or {
			return fail_g17_hardware_command(mut command, g17_hardware_command_auxiliary_error)
		}
		command.aux_u64_group_arrays[0] = first_group.start
		cursor = first_group.end
		second_group := take_g17_span_address(cursor, extension.end, second_group_count, 8) or {
			return fail_g17_hardware_command(mut command, g17_hardware_command_auxiliary_error)
		}
		command.aux_u64_group_arrays[1] = second_group.start
	}

	command.success = 1
	return true
}

// Host-side normalized object produced by
// AGXRenderHardwareKernelCommand::parseAndValidate. This is not a firmware
// work command: retained_payload_pointer is only valid while the staged input
// remains alive, and processRender consumes this object before constructing a
// 3D channel command. Every byte through +0x283 is now accounted for by the
// pinned G17C producer; reserved spans remain named as opaque storage so later
// consumers cannot accidentally infer a field ABI from them.
@[packed]
pub struct G17ParsedRenderCommand {
pub mut:
	opaque_000               [0x08]u8
	success                  u8
	opaque_009               [0x03]u8
	error_marker             u32
	opaque_010               [0x08]u8
	retained_payload_pointer u64
	normalized_020           [0x264]u8
}

// Normalize one render subtype payload exactly as the UUID-pinned macOS 26.5
// AGXG17X 351.2 parser does. The source may contain later records, so this
// consumes the fixed 0x9d0-byte prefix rather than requiring equality. The
// caller owns both kernel buffers and must keep payload alive while using the
// retained pointer. No user address may be passed directly to this function.
pub fn parse_g17_render_payload(command voidptr, command_bytes u64, payload voidptr,
	payload_bytes u64) bool {
	if command == unsafe { nil } || command_bytes < g17_render_kernel_command_size {
		return false
	}

	unsafe {
		mut parsed := &G17ParsedRenderCommand(command)
		parsed.success = 0
		if payload == nil || payload_bytes < g17_render_payload_size {
			parsed.retained_payload_pointer = 0
			parsed.error_marker = g17_render_payload_framing_error
			return false
		}

		parsed.retained_payload_pointer = u64(payload)
		mut destination := &u8(command)
		source := &u8(payload)
		C.memcpy(voidptr(destination + 0x020), voidptr(source + 0x0c8), 0x78)
		C.memcpy(voidptr(destination + 0x098), voidptr(source + 0x4d8), 0x78)
		C.memcpy(voidptr(destination + 0x110), voidptr(source + 0x140), 0x48)
		C.memcpy(voidptr(destination + 0x158), voidptr(source + 0x550), 0x48)
		C.memcpy(voidptr(destination + 0x1a0), voidptr(source + 0x24c), 0x0c)
		C.memcpy(voidptr(destination + 0x1ac), voidptr(source + 0x658), 0x0c)
		C.memcpy(voidptr(destination + 0x1bc), voidptr(source + 0x234), 0x04)
		C.memcpy(voidptr(destination + 0x1db), voidptr(source + 0x25f), 0x20)
		C.memcpy(voidptr(destination + 0x200), voidptr(source + 0x668), 0x08)
		C.memcpy(voidptr(destination + 0x208), voidptr(source + 0x821), 0x01)
		C.memcpy(voidptr(destination + 0x210), voidptr(source + 0x840), 0x70)

		destination[0x1b8] = source[0x240] & 1
		destination[0x1b9] = source[0x8b0] & 1
		destination[0x1c0] = source[0x247] & 1
		destination[0x1d8] = source[0x25c] & 1
		destination[0x1d9] = source[0x25d] & 1
		destination[0x1da] = source[0x25e] & 1
		destination[0x280] = source[0x23c] & 1
		destination[0x281] = source[0x646] & 1
		destination[0x282] = source[0x248] & 1
		destination[0x283] = source[0x650] & 1

		if (source[0x7e0] & 1) != (source[0x240] & 1)
			|| ((source[0x23c] & 1) != 0 && (source[0x646] & 1) == 0) {
			parsed.error_marker = g17_render_payload_validation_error
			return false
		}

		parsed.error_marker = 0
		parsed.success = 1
	}
	return true
}

// Host-only staging layout selected through AGXTACommandDescriptor::MetaClass.
// Its first 0xc40 bytes are the AGX3DCommandDescriptor base-class prefix.
// Firmware never receives this object directly. The HAL300 work-command
// producer reads it while building the firmware-private register lists.
pub const g17_3d_descriptor_base_size = u64(0xc40)
pub const g17_3d_descriptor_size = u64(0x15b0)
pub const g17_3d_common_payload_offset = u64(0x2d0)
pub const g17_3d_common_passthrough_size = u64(0x3ec)

@[packed]
pub struct G17ThreeDDescriptor {
pub mut:
	opaque [0x15b0]u8
}

struct G17DescriptorScalar {
	member u32
	bytes  u32
	value  u64
}

// Recovered nonzero defaults for the selected AGXTACommandDescriptor. Keep
// this manifest as the single source used by native and fake G17 staging.
const g17_descriptor_scalars = [
	G17DescriptorScalar{ member: 0x144, bytes: 4, value: 0xffff_ffff },
	G17DescriptorScalar{ member: 0x1c1, bytes: 2, value: 0x101 },
	G17DescriptorScalar{ member: 0x2d4, bytes: 4, value: 0xffff_ffff },
	G17DescriptorScalar{ member: 0x400, bytes: 4, value: 1 },
	G17DescriptorScalar{ member: 0x410, bytes: 4, value: 2 },
	G17DescriptorScalar{ member: 0x900, bytes: 4, value: 0xffff_ffff },
	G17DescriptorScalar{ member: 0x968, bytes: 4, value: 0xffff_ffff },
	G17DescriptorScalar{ member: 0xaa0, bytes: 8, value: 0xffff_ffff },
	G17DescriptorScalar{ member: 0xb60, bytes: 4, value: 0xffff_ffff },
	G17DescriptorScalar{ member: 0xc30, bytes: 4, value: 1 },
	G17DescriptorScalar{ member: 0xe18, bytes: 4, value: 0xffff_ffff },
	G17DescriptorScalar{ member: 0xf60, bytes: 4, value: 2 },
	G17DescriptorScalar{ member: 0x1208, bytes: 4, value: 0xffff_ffff },
	G17DescriptorScalar{ member: 0x1264, bytes: 4, value: 0xffff_ffff },
	G17DescriptorScalar{ member: 0x126c, bytes: 4, value: 0xffff_ffff },
	G17DescriptorScalar{ member: 0x13a8, bytes: 8, value: 0xffff_ffff },
	G17DescriptorScalar{ member: 0x13e8, bytes: 4, value: 0xffff_ffff },
]

fn write_g17_descriptor_value(destination &u8, member u64, bytes u64, value u64) {
	unsafe {
		C.memcpy(voidptr(destination + member), &value, bytes)
	}
}

fn copy_g17_descriptor_range(destination &u8, member u64, source &u8,
	source_offset u64, bytes u64) {
	unsafe {
		C.memcpy(voidptr(destination + member), voidptr(source + source_offset), bytes)
	}
}

fn copy_g17_descriptor_bit(destination &u8, member u64, bytes u64, source &u8,
	source_offset u64) {
	unsafe {
		write_g17_descriptor_value(destination, member, bytes, u64(source[source_offset] & 1))
	}
}

fn g17_descriptor_scalar_manifest_valid() bool {
	for index, field in g17_descriptor_scalars {
		if (field.bytes != 1 && field.bytes != 2 && field.bytes != 4 && field.bytes != 8)
			|| u64(field.member) > g17_3d_descriptor_size
			|| u64(field.bytes) > g17_3d_descriptor_size - u64(field.member) {
			return false
		}
		for previous := 0; previous < index; previous++ {
			other := g17_descriptor_scalars[previous]
			if field.member < other.member + other.bytes
				&& other.member < field.member + field.bytes {
				return false
			}
		}
	}
	return true
}

// Initialize the scalar part of Apple's selected derived descriptor without
// constructing any of its host C++ base classes or retained OSObject pointers.
// A full clear is a Vinix staging invariant; processRenderSetup-equivalent
// stages must populate every resource-owned field before command generation.
pub fn initialize_g17_3d_descriptor(descriptor voidptr, descriptor_bytes u64) bool {
	if descriptor == unsafe { nil } || descriptor_bytes < g17_3d_descriptor_size {
		return false
	}
	if !g17_descriptor_scalar_manifest_valid() {
		return false
	}
	unsafe {
		C.memset(descriptor, 0, g17_3d_descriptor_size)
		destination := &u8(descriptor)
		for field in g17_descriptor_scalars {
			write_g17_descriptor_value(destination, field.member, field.bytes, field.value)
		}
	}
	return true
}

// The scoped Mesa-to-G17 descriptor bridge. These thirteen members are
// triangulated rather than inferred from selector numbers alone:
//
// - the recovered G17 graph loads them for selectors 0x1c880, 0x15368,
//   0x15370, 0x15378, 0x15380, 0x15328, 0x15330, 0x153c0, 0x153c8,
//   0x15338, 0x15340, 0x153d0, and 0x153d8;
// - the color, depth, and stencil resource traces carry the corresponding GPU
//   VAs through members 0xfe0, 0x610, 0x768, 0x668, 0x670, 0x6e8, 0x6f0,
//   0x680, 0x688, 0x710, and 0x718; and
// - m1n1 commit 940439's independent register-list producer assigns those
//   selector pairs to the matching Asahi command fields.
//
// This is deliberately a narrow field identity. It does not claim that the
// still-unidentified selector address space is SGX MMIO, nor does it assign
// adjacent partial-pipeline or partial-depth members without equivalent
// evidence.
pub const g17_render_encoder_member = u32(0xfe0)
pub const g17_render_load_pipeline_bind_member = u32(0x608)
pub const g17_render_load_pipeline_member = u32(0x610)
pub const g17_render_store_pipeline_bind_member = u32(0x760)
pub const g17_render_store_pipeline_member = u32(0x768)
pub const g17_render_depth_buffer_load_member = u32(0x668)
pub const g17_render_depth_buffer_store_member = u32(0x670)
pub const g17_render_depth_meta_buffer_load_member = u32(0x6e8)
pub const g17_render_depth_meta_buffer_store_member = u32(0x6f0)
pub const g17_render_stencil_buffer_load_member = u32(0x680)
pub const g17_render_stencil_buffer_store_member = u32(0x688)
pub const g17_render_stencil_meta_buffer_load_member = u32(0x710)
pub const g17_render_stencil_meta_buffer_store_member = u32(0x718)

pub struct G17RenderDescriptorFields {
pub:
	encoder              u64
	load_pipeline_bind   u64
	load_pipeline        u64
	store_pipeline_bind  u64
	store_pipeline       u64
	depth_buffer_load    u64
	depth_buffer_store   u64
	depth_meta_load      u64
	depth_meta_store     u64
	stencil_buffer_load  u64
	stencil_buffer_store u64
	stencil_meta_load    u64
	stencil_meta_store   u64
}

// Populate normalized values only after initialize_g17_3d_descriptor has
// installed the recovered base-class defaults. The caller owns UAPI-specific
// address translation; this layer owns the recovered native member layout.
pub fn populate_g17_render_resource_fields(descriptor voidptr,
	descriptor_bytes u64, fields G17RenderDescriptorFields) bool {
	if descriptor == unsafe { nil } || descriptor_bytes < g17_3d_descriptor_size {
		return false
	}
	unsafe {
		destination := &u8(descriptor)
		write_g17_descriptor_value(destination, g17_render_encoder_member, 8,
			fields.encoder)
		write_g17_descriptor_value(destination,
			g17_render_load_pipeline_bind_member, 8, fields.load_pipeline_bind)
		write_g17_descriptor_value(destination, g17_render_load_pipeline_member,
			8, fields.load_pipeline)
		write_g17_descriptor_value(destination,
			g17_render_store_pipeline_bind_member, 8, fields.store_pipeline_bind)
		write_g17_descriptor_value(destination, g17_render_store_pipeline_member,
			8, fields.store_pipeline)
		write_g17_descriptor_value(destination,
			g17_render_depth_buffer_load_member, 8, fields.depth_buffer_load)
		write_g17_descriptor_value(destination,
			g17_render_depth_buffer_store_member, 8, fields.depth_buffer_store)
		write_g17_descriptor_value(destination,
			g17_render_depth_meta_buffer_load_member, 8, fields.depth_meta_load)
		write_g17_descriptor_value(destination,
			g17_render_depth_meta_buffer_store_member, 8, fields.depth_meta_store)
		write_g17_descriptor_value(destination,
			g17_render_stencil_buffer_load_member, 8, fields.stencil_buffer_load)
		write_g17_descriptor_value(destination,
			g17_render_stencil_buffer_store_member, 8, fields.stencil_buffer_store)
		write_g17_descriptor_value(destination,
			g17_render_stencil_meta_buffer_load_member, 8, fields.stencil_meta_load)
		write_g17_descriptor_value(destination,
			g17_render_stencil_meta_buffer_store_member, 8, fields.stencil_meta_store)
	}
	return true
}

// Copy the common 3D record retained inside a validated render payload into
// its internal descriptor. The scatter map and the source at payload +0x2d0
// are recovered independently from processRenderSetup and its leaf helper.
// This deliberately preserves all descriptor bytes outside the recovered
// fields: later setup stages own them, and zero is not a proven substitute.
pub fn populate_g17_3d_common_passthrough(descriptor voidptr, descriptor_bytes u64,
	payload voidptr, payload_bytes u64) bool {
	if descriptor == unsafe { nil } || descriptor_bytes < g17_3d_descriptor_size
		|| payload == unsafe { nil }
		|| payload_bytes < g17_3d_common_payload_offset + g17_3d_common_passthrough_size {
		return false
	}

	unsafe {
		destination := &u8(descriptor)
		source := &u8(payload) + g17_3d_common_payload_offset
		C.memcpy(voidptr(destination + 0x4e8), voidptr(source + 0x000), 0x80)
		C.memcpy(voidptr(destination + 0x5e8), voidptr(source + 0x080), 0x30)
		C.memcpy(voidptr(destination + 0x4b8), voidptr(source + 0x0e0), 0x08)
		C.memcpy(voidptr(destination + 0x4b0), voidptr(source + 0x0e8), 0x08)
		C.memcpy(voidptr(destination + 0x648), voidptr(source + 0x0f8), 0x10)
		C.memcpy(voidptr(destination + 0x658), voidptr(source + 0x108), 0x08)
		C.memcpy(voidptr(destination + 0x660), voidptr(source + 0x110), 0x10)
		C.memcpy(voidptr(destination + 0x698), voidptr(source + 0x120), 0x08)
		C.memcpy(voidptr(destination + 0x6c8), voidptr(source + 0x128), 0x08)
		C.memcpy(voidptr(destination + 0x6e8), voidptr(source + 0x130), 0x08)
		C.memcpy(voidptr(destination + 0x700), voidptr(source + 0x138), 0x08)
		C.memcpy(voidptr(destination + 0x670), voidptr(source + 0x140), 0x08)
		C.memcpy(voidptr(destination + 0x6a0), voidptr(source + 0x148), 0x08)
		C.memcpy(voidptr(destination + 0x6d0), voidptr(source + 0x150), 0x08)
		C.memcpy(voidptr(destination + 0x6f0), voidptr(source + 0x158), 0x08)
		C.memcpy(voidptr(destination + 0x708), voidptr(source + 0x160), 0x08)
		C.memcpy(voidptr(destination + 0x680), voidptr(source + 0x168), 0x08)
		C.memcpy(voidptr(destination + 0x6b0), voidptr(source + 0x170), 0x08)
		C.memcpy(voidptr(destination + 0x6d8), voidptr(source + 0x178), 0x08)
		C.memcpy(voidptr(destination + 0x710), voidptr(source + 0x180), 0x08)
		C.memcpy(voidptr(destination + 0x728), voidptr(source + 0x188), 0x08)
		C.memcpy(voidptr(destination + 0x688), voidptr(source + 0x190), 0x08)
		C.memcpy(voidptr(destination + 0x6b8), voidptr(source + 0x198), 0x08)
		C.memcpy(voidptr(destination + 0x6e0), voidptr(source + 0x1a0), 0x08)
		C.memcpy(voidptr(destination + 0x718), voidptr(source + 0x1a8), 0x08)
		C.memcpy(voidptr(destination + 0x730), voidptr(source + 0x1b0), 0x08)
		C.memcpy(voidptr(destination + 0x740), voidptr(source + 0x1b8), 0x10)
		C.memcpy(voidptr(destination + 0x750), voidptr(source + 0x1c8), 0x10)
		C.memcpy(voidptr(destination + 0x738), voidptr(source + 0x1d8), 0x08)
		C.memcpy(voidptr(destination + 0x4e0), voidptr(source + 0x0f0), 0x08)
		C.memcpy(voidptr(destination + 0x7f8), voidptr(source + 0x1e0), 0x08)
		C.memcpy(voidptr(destination + 0xad0), voidptr(source + 0x1e8), 0x04)
		C.memcpy(voidptr(destination + 0xad8), voidptr(source + 0x1f0), 0x08)
		C.memcpy(voidptr(destination + 0x7b0), voidptr(source + 0x1f8), 0x08)
		C.memcpy(voidptr(destination + 0x7c0), voidptr(source + 0x200), 0x04)
		C.memcpy(voidptr(destination + 0x7e8), voidptr(source + 0x2a8), 0x08)
		C.memcpy(voidptr(destination + 0x7a8), voidptr(source + 0x368), 0x08)
		C.memcpy(voidptr(destination + 0x790), voidptr(source + 0x0b0), 0x08)
		C.memcpy(voidptr(destination + 0x798), voidptr(source + 0x0b8), 0x04)
		C.memcpy(voidptr(destination + 0x760), voidptr(source + 0x0c0), 0x10)
		C.memcpy(voidptr(destination + 0x770), voidptr(source + 0x0d0), 0x10)
		C.memcpy(voidptr(destination + 0x888), voidptr(source + 0x370), 0x04)
		C.memcpy(voidptr(destination + 0x410), voidptr(source + 0x384), 0x04)
		C.memcpy(voidptr(destination + 0xae0), voidptr(source + 0x3a0), 0x10)
		C.memcpy(voidptr(destination + 0xaf0), voidptr(source + 0x3b0), 0x10)
		C.memcpy(voidptr(destination + 0xb00), voidptr(source + 0x3c0), 0x10)
		C.memcpy(voidptr(destination + 0xb28), voidptr(source + 0x3d0), 0x10)
		C.memcpy(voidptr(destination + 0xb38), voidptr(source + 0x3e0), 0x08)
		C.memcpy(voidptr(destination + 0xb40), voidptr(source + 0x3e8), 0x04)

		destination[0x88c] = source[0x375] & 1
		destination[0x895] = source[0x378] & 1
		destination[0x896] = source[0x379] & 1
		destination[0x898] = source[0x37b] & 1
		destination[0x962] = source[0x37c] & 1
		destination[0x963] = source[0x37d] & 1
		destination[0x899] = source[0x37e] & 1
		destination[0x7e0] = source[0x37f] & 1
	}
	return true
}

// Reproduce the raw-payload portion of AGXCommandQueue::processRenderSetup
// for the selected AGXTACommandDescriptor. Resource addresses and fields
// computed by the rest of processRenderSetup remain separate stages.
pub fn populate_g17_ta_render_passthrough(descriptor voidptr, descriptor_bytes u64,
	payload voidptr, payload_bytes u64) bool {
	if descriptor == unsafe { nil } || descriptor_bytes < g17_3d_descriptor_size
		|| payload == unsafe { nil } || payload_bytes < g17_render_payload_size {
		return false
	}

	unsafe {
		destination := &u8(descriptor)
		source := &u8(payload)
		copy_g17_descriptor_range(destination, 0xfe0, source, 0x000, 0x30)
		copy_g17_descriptor_range(destination, 0x1050, source, 0x030, 0x40)
		copy_g17_descriptor_range(destination, 0x1010, source, 0x1f0, 0x20)
		copy_g17_descriptor_range(destination, 0x1030, source, 0x210, 0x08)
		copy_g17_descriptor_range(destination, 0x1038, source, 0x220, 0x10)
		copy_g17_descriptor_range(destination, 0x1048, source, 0x230, 0x04)
		copy_g17_descriptor_range(destination, 0x10c0, source, 0x0b8, 0x0c)
		copy_g17_descriptor_range(destination, 0x1090, source, 0x070, 0x30)
		copy_g17_descriptor_range(destination, 0x10e0, source, 0x1e4, 0x0c)
		copy_g17_descriptor_range(destination, 0x1110, source, 0x168, 0x08)
		copy_g17_descriptor_range(destination, 0x1108, source, 0x0a0, 0x08)
		copy_g17_descriptor_range(destination, 0x13b0, source, 0x238, 0x04)
		copy_g17_descriptor_range(destination, 0x0f60, source, 0x258, 0x04)
		copy_g17_descriptor_range(destination, 0x14d0, source, 0x280, 0x30)
		copy_g17_descriptor_range(destination, 0x1518, source, 0x2b0, 0x10)
		copy_g17_descriptor_range(destination, 0x1528, source, 0x2c0, 0x0c)
		copy_g17_descriptor_range(destination, 0x086c, source, 0x810, 0x04)
		copy_g17_descriptor_range(destination, 0x0870, source, 0x818, 0x08)
		copy_g17_descriptor_range(destination, 0x0961, source, 0x822, 0x01)
		copy_g17_descriptor_range(destination, 0x0950, source, 0x830, 0x0c)

		copy_g17_descriptor_bit(destination, 0x1100, 4, source, 0x246)
		copy_g17_descriptor_bit(destination, 0x1129, 1, source, 0x23d)
		copy_g17_descriptor_bit(destination, 0x1130, 1, source, 0x243)
		copy_g17_descriptor_bit(destination, 0x112a, 1, source, 0x23e)
		copy_g17_descriptor_bit(destination, 0x112b, 1, source, 0x23f)
		copy_g17_descriptor_bit(destination, 0x112d, 1, source, 0x241)
		copy_g17_descriptor_bit(destination, 0x112f, 1, source, 0x242)
		copy_g17_descriptor_bit(destination, 0x1132, 1, source, 0x249)
		copy_g17_descriptor_bit(destination, 0x1270, 1, source, 0x244)
		copy_g17_descriptor_bit(destination, 0x1271, 1, source, 0x245)
		copy_g17_descriptor_bit(destination, 0x1539, 1, source, 0x24b)
		copy_g17_descriptor_bit(destination, 0x15a8, 1, source, 0x24a)
		copy_g17_descriptor_bit(destination, 0x112e, 1, source, 0x820)
		copy_g17_descriptor_bit(destination, 0x0868, 1, source, 0x814)
		copy_g17_descriptor_bit(destination, 0x088d, 1, source, 0x820)
	}

	if !populate_g17_3d_common_passthrough(descriptor, descriptor_bytes, payload,
		payload_bytes) {
		return false
	}

	unsafe {
		destination := &u8(descriptor)
		source := &u8(payload)
		copy_g17_descriptor_range(destination, 0x04c0, source, 0x6c0, 0x08)
		copy_g17_descriptor_range(destination, 0x0618, source, 0x6c8, 0x30)
		copy_g17_descriptor_range(destination, 0x0568, source, 0x728, 0x80)
		copy_g17_descriptor_range(destination, 0x0678, source, 0x7a8, 0x08)
		copy_g17_descriptor_range(destination, 0x06f8, source, 0x7b0, 0x08)
		copy_g17_descriptor_range(destination, 0x0690, source, 0x7b8, 0x08)
		copy_g17_descriptor_range(destination, 0x0720, source, 0x7c0, 0x08)
		copy_g17_descriptor_range(destination, 0x06a8, source, 0x7c8, 0x08)
		copy_g17_descriptor_range(destination, 0x06c0, source, 0x7d0, 0x08)
		copy_g17_descriptor_range(destination, 0x079c, source, 0x6f8, 0x0c)
		copy_g17_descriptor_range(destination, 0x0780, source, 0x708, 0x10)
		copy_g17_descriptor_range(destination, 0x04c8, source, 0x7e8, 0x18)
		copy_g17_descriptor_range(destination, 0x0aa8, source, 0x808, 0x04)

		copy_g17_descriptor_bit(destination, 0x088e, 1, source, 0x7d8)
		copy_g17_descriptor_bit(destination, 0x088f, 1, source, 0x7d9)
		copy_g17_descriptor_bit(destination, 0x0890, 1, source, 0x7da)
		copy_g17_descriptor_bit(destination, 0x0891, 1, source, 0x7db)
		copy_g17_descriptor_bit(destination, 0x0892, 1, source, 0x7dc)
		copy_g17_descriptor_bit(destination, 0x089a, 1, source, 0x7dd)
		copy_g17_descriptor_bit(destination, 0x089b, 1, source, 0x7de)
		copy_g17_descriptor_bit(destination, 0x0800, 1, source, 0x80c)
	}
	return true
}

// Copy the normalized-command portion of processRenderSetup into the staging
// descriptor. This is a separate nine-write stage: eight writes are direct
// command fields and the ninth selects between literal one and a device bit.
// The selected G17 configureDevice path explicitly initializes that retained
// accelerator bit to zero. It must not be counted as a ninth boolean in the
// eight-chain common helper.
pub fn populate_g17_render_descriptor_fields(descriptor voidptr, descriptor_bytes u64,
	command voidptr, command_bytes u64) bool {
	if descriptor == unsafe { nil } || descriptor_bytes < g17_3d_descriptor_size
		|| command == unsafe { nil } || command_bytes < g17_render_kernel_command_size {
		return false
	}

	unsafe {
		destination := &u8(descriptor)
		source := &u8(command)
		// processRenderSetup only reaches this block after parseAndValidate.
		if source[0x08] != 1 {
			return false
		}

		destination[0x1598] = source[0x282] & 1
		copy_g17_descriptor_range(destination, 0x04a0, source, 0x25c, 0x08)
		copy_g17_descriptor_range(destination, 0x04a8, source, 0x264, 0x04)
		destination[0x112c] = source[0x1b8] & 1
		destination[0x1128] = source[0x280] & 1
		destination[0x0897] = source[0x1b8] & 1
		destination[0x0893] = source[0x281] & 1
		destination[0x0960] = source[0x208]
		destination[0x0c38] = if source[0x283] & 1 != 0 {
			u8(1)
		} else {
			u8(0)
		}
	}
	return true
}

// Register-list layout inside the 3D channel command.
// generateRegisterListFor3D runs four passes with a 0x720 stride. Pass i keeps
// its stream at i * 0x720 + 0xa0 and its metadata at i * 0x720 + 0x7a0, so a
// pass owns 0x700 stream bytes and the next pass starts 0x14 bytes after the
// previous metadata ends. Entries are 12 bytes: a selector word then an
// unaligned 64-bit value. Apple's selector argument is statically recovered at
// every virtual encoder call, and both 3D inline forms are located. Every x4
// writer is classified as a constant, descriptor load, or bounded computation,
// including safe traces through dominating callee-saved copies and 105 complete
// descriptor/object/stack-rooted expression trees. Four trees use the UUID-pinned
// DUPM minimum/maximum virtual methods, which return 1 and 2; four more use the
// cross-image-checked IOGPUMemoryMap GPU-address accessor. Bit-test, compare-zero,
// and nested forward merges are represented without guessing; the CL runtime
// random and post-increment counter roots are pinned too. The complete emission
// graph and all semantic ordering predicates are recovered by the UUID-pinned
// tooling. The generated allocation-free implementation lives in
// kernel/c/agx_fake_g17_encode.c and is exposed through
// gpu.agx.fake.encode_fake_g17_3d;
// these low-level append helpers remain useful for structural tests.
pub const g17_3d_register_passes = u32(4)
pub const g17_3d_register_stride = u64(0x720)
pub const g17_3d_register_stream_offset = u64(0xa0)
pub const g17_3d_register_stream_bytes = u64(0x700)
pub const g17_3d_register_metadata_offset = u64(0x7a0)
pub const g17_3d_register_entry_size = u64(0xc)
pub const g17_3d_register_selector_mask = u32(0xfffc0006)
pub const g17_3d_register_summary_offset = u64(0x828)
pub const g17_3d_register_summary_stride = u64(0x10)

// Field split of a register-list entry. HAL300 encodeEntry masks the selector
// argument to bits 3..17 and inserts a separate one-bit mode argument at bit
// zero; bits 1, 2 and 18..31 remain from the command-pool template. What the
// selectors name is not established: they are not SGX MMIO offsets.
pub const g17_3d_register_selector_field = u32(0x3fff8)
pub const g17_3d_register_mode_field = u32(0x1)
pub const g17_3d_register_selector_align = u32(8)

// Reject a selector Apple's w2 encoding could not have produced.
pub fn valid_g17_register_selector(selector u32) bool {
	return selector & ~g17_3d_register_selector_field == 0
}

// Per-pass metadata: the stream's GPU address followed by its entry and byte
// counters, both 16-bit.
@[packed]
pub struct G17RegisterStreamTrailer {
pub mut:
	gpu_address u64
	entry_count u16
	byte_length u16
}

// The 0x10-byte record each pass is summarised into inside the descriptor.
@[packed]
pub struct G17RegisterPassSummary {
pub mut:
	gpu_address u64
	entry_count u16
	reserved    [6]u8
}

fn g17_register_pass(command voidptr, pass u32) &G17RegisterStreamTrailer {
	return unsafe {
		&G17RegisterStreamTrailer(&u8(command) + u64(pass) * g17_3d_register_stride + g17_3d_register_metadata_offset)
	}
}

// Point one pass's stream at its GPU address and empty it, matching the setup
// generateRegisterListFor3D does before each pass.
pub fn bind_g17_register_stream(command voidptr, pass u32, stream_gpu_address u64) bool {
	if command == unsafe { nil } || pass >= g17_3d_register_passes
		|| stream_gpu_address == 0 {
		return false
	}

	mut trailer := g17_register_pass(command, pass)
	trailer.gpu_address = stream_gpu_address
	trailer.entry_count = 0
	trailer.byte_length = 0
	return true
}

// Append one {selector, mode, value} record to a pass's stream. Apple keeps
// the template bits already present in the first word, installs mode at bit 0,
// and writes the 64-bit value unaligned four bytes later.
pub fn append_g17_register_entry(command voidptr, pass u32, selector u32, mode u8,
	value u64) bool {
	if command == unsafe { nil } || pass >= g17_3d_register_passes {
		return false
	}

	if !valid_g17_register_selector(selector) || mode > 1 {
		return false
	}

	mut trailer := g17_register_pass(command, pass)
	if u64(trailer.byte_length) + g17_3d_register_entry_size > g17_3d_register_stream_bytes {
		return false
	}

	unsafe {
		entry := &u8(command) + u64(pass) * g17_3d_register_stride + g17_3d_register_stream_offset + u64(trailer.byte_length)
		mut selector_word := &u32(entry)
		*selector_word = (*selector_word & g17_3d_register_selector_mask) | (selector & g17_3d_register_selector_field) | u32(mode)
		mut encoded := value
		C.memcpy(voidptr(entry + 4), &encoded, 8)
	}
	trailer.byte_length += u16(g17_3d_register_entry_size)
	trailer.entry_count++
	return true
}

// Copy every pass's GPU address and entry count into the descriptor summary
// array, as the producer's exit block does.
pub fn publish_g17_register_summaries(command voidptr, descriptor voidptr) bool {
	if command == unsafe { nil } || descriptor == unsafe { nil } {
		return false
	}

	for pass := u32(0); pass < g17_3d_register_passes; pass++ {
		trailer := g17_register_pass(command, pass)
		unsafe {
			mut summary := &G17RegisterPassSummary(&u8(descriptor) + g17_3d_register_summary_offset + u64(pass) * g17_3d_register_summary_stride)
			summary.gpu_address = trailer.gpu_address
			summary.entry_count = trailer.entry_count
		}
	}
	return true
}

// One preallocated channel-command slot ring. Apple keeps one of these per
// command type in a 0x40-byte firmware-object block; only the fields the
// allocator actually uses are modelled here.
pub struct G17CommandPool {
pub mut:
	cpu_base      voidptr
	gpu_base      u64
	in_use        &u8 = unsafe { nil }
	element_bytes u32
	slot_count    u32
	slot_cursor   u32
	exhausted     bool
	lock          klock.Lock
}

// Geometry produced by PoolClass::createBacking. The requested element count
// is rounded up in bytes to one 16 KiB kernel/GPU page, after which every
// complete element in the rounded allocation becomes a usable slot. This is
// why slot_count can be slightly larger than requested_slots.
pub struct G17CommandPoolGeometry {
pub:
	requested_slots u32
	backing_bytes   u64
	slot_count      u32
}

pub struct G17CommandSlot {
pub:
	index u32
	cpu   voidptr
	gpu   u64
}

// Calculate the exact backing geometry used by Apple's G17 pool constructor.
pub fn g17_command_pool_geometry(element_bytes u32, requested_slots u32) ?G17CommandPoolGeometry {
	if element_bytes == 0 || requested_slots == 0 {
		return none
	}
	requested_bytes := u64(element_bytes) * u64(requested_slots)
	if requested_bytes > u64(0xffff_ffff_ffff_ffff) - (g17_bootstrap_page_size - 1) {
		return none
	}
	backing_bytes := (requested_bytes + g17_bootstrap_page_size - 1) & ~(g17_bootstrap_page_size - 1)
	slot_count := backing_bytes / u64(element_bytes)
	if backing_bytes == 0 || slot_count < u64(requested_slots) || slot_count > 0xffff_ffff {
		return none
	}
	return G17CommandPoolGeometry{
		requested_slots: requested_slots
		backing_bytes: backing_bytes
		slot_count: u32(slot_count)
	}
}

// Bind an already mapped, page-rounded backing allocation and its host-only
// in-use array to a pool. The backing must match the recovered constructor's
// geometry exactly; accepting a merely large-enough allocation would change
// the slot count observed by the allocator.
pub fn initialize_g17_command_pool(mut pool G17CommandPool, cpu_base voidptr,
	gpu_base u64, backing_bytes u64, in_use &u8, in_use_bytes u64,
	element_bytes u32, requested_slots u32) bool {
	geometry := g17_command_pool_geometry(element_bytes, requested_slots) or { return false }
	if cpu_base == unsafe { nil } || gpu_base == 0 || in_use == unsafe { nil }
		|| backing_bytes != geometry.backing_bytes
		|| in_use_bytes < u64(geometry.slot_count) {
		return false
	}
	last_offset := backing_bytes - 1
	if u64(cpu_base) > u64(0xffff_ffff_ffff_ffff) - last_offset
		|| gpu_base > u64(0xffff_ffff_ffff_ffff) - last_offset {
		return false
	}

	unsafe {
		C.memset(in_use, 0, u64(geometry.slot_count))
	}
	pool.cpu_base = cpu_base
	pool.gpu_base = gpu_base
	unsafe {
		pool.in_use = in_use
	}
	pool.element_bytes = element_bytes
	pool.slot_count = geometry.slot_count
	pool.slot_cursor = 0
	pool.exhausted = false
	return true
}

// Reproduce AGXFirmware::requestChannelCommandX. Apple scans forward from the
// cursor for at most slot_count entries, takes the first slot whose in-use
// byte is clear, marks it and leaves the cursor one past it. A full ring
// returns none instead of blocking, matching the null Apple returns.
pub fn (mut pool G17CommandPool) acquire_g17_command_slot() ?G17CommandSlot {
	pool.lock.acquire()
	defer {
		pool.lock.release()
	}
	if pool.slot_count == 0 || pool.element_bytes == 0
		|| pool.in_use == unsafe { nil } || pool.cpu_base == unsafe { nil } {
		return none
	}

	mut slot := pool.slot_cursor % pool.slot_count
	mut remaining := pool.slot_count
	for remaining > 0 {
		if unsafe { pool.in_use[slot] } == 0 {
			break
		}
		slot = (slot + 1) % pool.slot_count
		remaining--
	}
	if remaining == 0 {
		return none
	}

	offset := u64(slot) * u64(pool.element_bytes)
	unsafe {
		pool.in_use[slot] = pool.in_use[slot] + 1
	}
	pool.slot_cursor = (slot + 1) % pool.slot_count
	cpu := unsafe { voidptr(&u8(pool.cpu_base) + offset) }
	pool.exhausted = cpu == unsafe { nil }
	return G17CommandSlot{
		index: slot
		cpu: cpu
		gpu: pool.gpu_base + offset
	}
}

// Release a slot back to its ring. Apple clears the byte when the firmware
// reports the command complete.
pub fn (mut pool G17CommandPool) release_g17_command_slot(index u32) bool {
	pool.lock.acquire()
	defer {
		pool.lock.release()
	}
	if index >= pool.slot_count || pool.in_use == unsafe { nil } {
		return false
	}
	unsafe {
		if pool.in_use[index] == 0 {
			return false
		}
		pool.in_use[index] = pool.in_use[index] - 1
	}
	return true
}

// Reproduce the address-to-slot part of AGX3DCommandDescriptor::complete,
// while adding bounds and alignment checks that Apple's trusted internal
// pointer does not need. The slot byte is decremented only after the address
// has been proven to name the start of an element in this pool.
pub fn (mut pool G17CommandPool) release_g17_command_address(command_cpu voidptr) bool {
	if command_cpu == unsafe { nil } || pool.cpu_base == unsafe { nil }
		|| pool.element_bytes == 0 || pool.slot_count == 0 {
		return false
	}
	command_address := u64(command_cpu)
	base := u64(pool.cpu_base)
	if command_address < base {
		return false
	}
	offset := command_address - base
	if offset % u64(pool.element_bytes) != 0 {
		return false
	}
	index := offset / u64(pool.element_bytes)
	if index >= u64(pool.slot_count) {
		return false
	}
	return pool.release_g17_command_slot(u32(index))
}

pub const g17_scheduler_state_size = u64(0x40)
pub const g17_default_app_gpu_role = u8(2)
pub const g17_max_app_gpu_role = u8(3)

// Per-command-queue timestamp object shared by all of its TA, 3D, and CL
// channels.  Channel state +0x10 carries this object's GPU address.  Apple
// also writes that address back into the object itself at +0x08.
@[packed]
pub struct G17TimestampState {
pub mut:
	value_000        u64
	self_gpu_address u64
	update_mode      u32
	reserved_014     u32
}

pub fn initialize_g17_timestamp_state(buffer voidptr, size u64, gpu_address u64,
	update_mode bool) bool {
	if buffer == unsafe { nil } || size != g17_timestamp_state_size || gpu_address == 0 {
		return false
	}
	unsafe {
		C.memset(buffer, 0, g17_timestamp_state_size)
		mut state := &G17TimestampState(buffer)
		state.self_gpu_address = gpu_address
		state.update_mode = if update_mode { u32(1) } else { u32(0) }
	}
	return true
}

// One element of Apple's AGFICmdQueueSchedState firmware pool. Every command
// queue owns exactly one, and its GPU address is what channel state +0x9c
// carries, which is why initialize_g17_channel takes that address as an input.
@[packed]
pub struct G17SchedulerState {
pub mut:
	sentinel_000 u16
	opaque_002   [0x03]u8
	flag_005     u8
	opaque_006   [0x1c]u8
	value_022    u32
	app_gpu_role u8
	opaque_027   [0x0c]u8
	sentinel_033 u8
	opaque_034   [0x0c]u8
}

// Reproduce the element defaults AGXCommandQueue::allocateSchedulerState
// writes after the pool hands out an element. Apple only clears the first
// 0x38 bytes there because the backing is already zeroed; clearing the whole
// element is equivalent and keeps the tail defined. The role byte is read
// from the AGXShared device, which AGXShared::init defaults to
// g17_default_app_gpu_role and set_app_gpu_role bounds to 0..3.
pub fn initialize_g17_scheduler_state(buffer voidptr, size u64, app_gpu_role u8) bool {
	if buffer == unsafe { nil } || size != g17_scheduler_state_size
		|| app_gpu_role > g17_max_app_gpu_role {
		return false
	}

	unsafe {
		C.memset(buffer, 0, g17_scheduler_state_size)
		mut state := &G17SchedulerState(buffer)
		state.sentinel_000 = 0xffff
		state.flag_005 = 1
		state.value_022 = 0
		state.app_gpu_role = app_gpu_role
		state.sentinel_033 = 0xff
	}
	return true
}

// Block geometry for the same pool. Apple rounds one page plus two elements
// down to a page multiple, then divides by the element size. The mask relies
// on the page size being a power of two, which the UAT already requires.
pub fn g17_scheduler_state_block_bytes(page_bytes u64) u64 {
	if page_bytes == 0 || page_bytes & (page_bytes - 1) != 0 {
		return 0
	}
	return (page_bytes + 2 * g17_scheduler_state_size - 1) & ~(page_bytes - 1)
}

pub fn g17_scheduler_states_per_block(page_bytes u64) u64 {
	return g17_scheduler_state_block_bytes(page_bytes) / g17_scheduler_state_size
}

pub struct G17ChannelBindings {
pub mut:
	uncached_gpu_address u64
	cached_gpu_address   u64
	context_cookie       u64
	owning_process_id    u32
	queue_address_09c    u64
	ring_entries         u32
	priority             u32
}

// Apply the canonical realtime/high/medium/low profiles exposed by the Asahi
// queue UAPI. AGXArmFirmware::setChannelPriority maps Apple context priorities
// 0/4/1/2 onto firmware data-master priorities 0/1/2/3 respectively. Its full
// state block is reproduced here with Apple's default subpriority 2.
fn initialize_g17_channel_priority(mut state G17ChannelState, priority u32) bool {
	if priority >= g17_channel_priority_count {
		return false
	}
	state.subpriority_03c = g17_channel_default_subpriority
	match priority {
		0 {
			state.mode_028 = 0
			state.mode_02c = 0
			state.threshold_030 = u64(0xffffffffffff0000)
			state.control_038 = 1
			state.qos_040 = 1
		}
		1 {
			state.mode_028 = 1
			state.mode_02c = 1
			state.threshold_030 = u64(0xffffffff00000000)
		}
		2 {
			state.mode_028 = 2
			state.mode_02c = 2
			state.threshold_030 = u64(0xffff000000000000)
			state.qos_040 = 2
		}
		3 {
			state.mode_028 = 3
			state.mode_02c = 3
		}
		else { return false }
	}
	return true
}

// Reproduce AGXChannel::resetChannelState for the checked shared fields.
// resetChannelState only copies state +0x48 and +0x9c out of its own object.
// AGXChannel::init seeds those from the owning AGXCommandQueue at +0x498 and
// +0x8b8; the first is inherited from IOGPUCommandQueue::init, which copies
// the device's process ID, and the second is the queue's scheduler-state GPU
// address. Note the runtime object also has a +0x4c/+0x50 kick-channel QoS
// pair; the matching offset is a coincidence and not this value.
pub fn initialize_g17_channel(state_buffer voidptr, state_size u64,
	uncached_buffer voidptr, uncached_size u64, cached_buffer voidptr, cached_size u64,
	bindings G17ChannelBindings) bool {
	if state_buffer == unsafe { nil } || state_size != g17_channel_state_size
		|| uncached_buffer == unsafe { nil } || uncached_size < g17_channel_control_header_size
		|| cached_buffer == unsafe { nil } || bindings.uncached_gpu_address == 0
		|| bindings.cached_gpu_address == 0 || bindings.ring_entries == 0
		|| bindings.priority >= g17_channel_priority_count
		|| u64(bindings.ring_entries) > cached_size / g17_cached_command_pointer_size {
		return false
	}

	unsafe {
		C.memset(state_buffer, 0, state_size)
		C.memset(uncached_buffer, 0, g17_channel_control_header_size)
		C.memset(cached_buffer, 0, u64(bindings.ring_entries) * g17_cached_command_pointer_size)
		mut state := &G17ChannelState(state_buffer)
		state.uncached_gpu_address = bindings.uncached_gpu_address
		state.cached_gpu_address = bindings.cached_gpu_address
		state.context_cookie = bindings.context_cookie
		state.sentinel_024 = ~u32(0)
		state.sentinel_044 = ~u32(0)
		state.owning_process_id = bindings.owning_process_id
		state.queue_address_09c = bindings.queue_address_09c
		if !initialize_g17_channel_priority(mut state, bindings.priority) {
			return false
		}
		mut control := &G17ChannelControl(uncached_buffer)
		control.sentinel_050 = ~u32(0)
		control.ring_entries = bindings.ring_entries
	}
	return true
}

// Publish one firmware work-command address using the ordering recovered from
// AGXChannel::writeChannelCommandPointer. One ring entry is deliberately kept
// empty so equal read/write indices always mean empty, never full. A full ring
// is reported to the caller rather than spinning inside the kernel.
pub fn publish_g17_channel_command(uncached_buffer voidptr, uncached_size u64,
	cached_buffer voidptr, cached_size u64, command_gpu_address u64) ?u16 {
	if uncached_buffer == unsafe { nil } || uncached_size < g17_channel_control_header_size
		|| cached_buffer == unsafe { nil } || command_gpu_address == 0 {
		return none
	}

	unsafe {
		mut control := &G17ChannelControl(uncached_buffer)
		entries := katomic.load(&control.ring_entries)
		if entries < 2 || u64(entries) > cached_size / g17_cached_command_pointer_size {
			return none
		}
		read_index := katomic.load(&control.read_index)
		write_index := katomic.load(&control.write_index)
		if read_index >= entries || write_index >= entries {
			return none
		}
		next_index := (write_index + 1) % entries
		if next_index == read_index {
			return none
		}

		mut pointer := &u64(u64(cached_buffer) + u64(write_index) * g17_cached_command_pointer_size)
		katomic.store(mut pointer, command_gpu_address)
		katomic.store(mut &control.write_index, next_index)
		return u16(next_index)
	}
}

pub fn enqueue_g17_channel_command(uncached_buffer voidptr, uncached_size u64,
	cached_buffer voidptr, cached_size u64, command_gpu_address u64) bool {
	publish_g17_channel_command(uncached_buffer, uncached_size, cached_buffer,
		cached_size, command_gpu_address) or { return false }
	return true
}

pub fn validate_g17_channel_layouts() bool {
	return sizeof(G17ChannelState) == g17_channel_state_size
		&& sizeof(G17ChannelControl) == g17_channel_control_header_size
		&& sizeof(G17CachedCommandPointer) == g17_cached_command_pointer_size
		&& sizeof(G17TimestampState) == g17_timestamp_state_size
		&& sizeof(G17ChannelCommandKnownPrefix) == g17_channel_command_known_prefix_size
		&& sizeof(G17SharedStreamParser) == g17_shared_stream_parser_size
		&& sizeof(G17ParsedHardwareCommand) == g17_parsed_hardware_command_size
		&& sizeof(G17ParsedRenderCommand) == g17_render_kernel_command_size
		&& sizeof(G17ThreeDDescriptor) == g17_3d_descriptor_size
}

// Both G17 device-control and data-master rings use three independently
// cache-line-spaced indices. All indices are range-checked against 256 entries
// by the Apple host driver.
@[packed]
pub struct G17AcceleratorRingState {
pub mut:
	read_index  u32
	opaque_004  [3]u32
	cfi_index   u32
	opaque_014  [3]u32
	write_index u32
	opaque_024  [3]u32
}

// Callback interrupt 4 drains one of these role-local firmware event rings.
// It uses the same sparse 0x30-byte index layout as the command rings,
// but its entries are fixed 0x48-byte AGFIFirmwareEventRingEntry records.
@[packed]
pub struct G17FirmwareEventRingEntry {
pub mut:
	event_type u32
	opaque_004 [0x44]u8
}

// Event type 1 signals up to 128 IOGPU event-machine stamp slots. Apple
// validates the trailing halfword before walking every set bit, then performs
// one batched all-stamps completion pass after the ring has drained.
@[packed]
pub struct G17FirmwareCompletionEvent {
pub mut:
	event_type       u32
	firing           [4]u32
	checked_halfword u16
	opaque_016       [0x32]u8
}

// Event type 4 requests GPU recovery. Apple accepts -1 as an unscoped stamp
// slot or one of the same 128 event-machine slots used by completion events.
@[packed]
pub struct G17FirmwareGpuRestartEvent {
pub mut:
	event_type u32
	opaque_004 [8]u8
	stamp_slot i32
	opaque_010 [0x38]u8
}

// Event type 6 asks the host parameter-buffer manager to grow its backing
// storage. Apple queues this record to a non-interrupt worker, calls
// AGXParameterManagement::growImmediately, then returns device-control type 8.
// Vinix names and validates the wire request but must not acknowledge it until
// it owns an equivalent parameter-buffer allocator.
@[packed]
pub struct G17FirmwarePmRequestMemory {
pub mut:
	event_type     u32
	stamp_slot     i32
	manager_index  u32
	request_value  u32
	request_kind   u32
	firmware_token u64
	opaque_01c     [0x2c]u8
}

// Event type 7 reports a channel error. The subtype and data-master limits
// are checked before Apple enters its channel-specific recovery machinery.
@[packed]
pub struct G17FirmwareChannelErrorEvent {
pub mut:
	event_type  u32
	subtype     u32
	data_master u32
	stamp_slot  i32
	opaque_010  [0x38]u8
}

// Event type 8 carries a metrology-aging result for an optional platform
// reliability monitor. With no such service, Apple returns to its drain loop.
@[packed]
pub struct G17FirmwareMetrologyAgingEvent {
pub mut:
	event_type u32
	result     u32
	opaque_008 [0x40]u8
}

// Event type 9 is copied by Apple into a private host queue and wakes
// AGXAccelerator::allocateUMAMemoryEvent. In the selected G17 driver that
// complete callback is exactly `bti c; ret`: it does not drain the queue,
// allocate memory, or send a firmware response. Vinix therefore validates
// and consumes the request without constructing the unused private queue.
@[packed]
pub struct G17FirmwareUmaAsyncAlloc {
pub mut:
	event_type         u32
	request_index      u32
	opaque_008         u32
	required_value_00c u64
	stamp_slot         i32
	request_value_018  u32
	wait_for_host_ring u32
	opaque_020         [0x28]u8
}

// Event type 10 acknowledges an Apple IOSurface shared-event signal. Vinix
// does not expose IOSurface events, but still validates the record before
// consuming it as the equivalent of Apple's empty-registry path.
@[packed]
pub struct G17FirmwareSharedEventSignalComplete {
pub mut:
	event_type              u32
	event_id                u64
	opaque_00c              [8]u8
	pre_signal_release_flag u32
	opaque_018              [0x30]u8
}

// Event type 12 removes a process object from Apple's IOGPU weak namespace.
// Vinix has no such host-object registry, making every valid ID a miss.
@[packed]
pub struct G17FirmwareProcessExitComplete {
pub mut:
	event_type u32
	object_id  u64
	opaque_00c [0x3c]u8
}

// Event type 13 completes one USC-private-memory grow request. Apple requires
// both unaligned values to be nonzero, resolves flist_index to an
// AGXUSCPrivMemFList, and calls the retained grow engine's retireGrowRequest.
@[packed]
pub struct G17FirmwareUmaGrowPool {
pub mut:
	event_type         u32
	stamp_slot         i32
	flist_index        u32
	required_value_00c u64
	required_value_014 u64
	grow_result_value  u64
	grow_result_flags  u32
	opaque_028         [0x20]u8
}

// Event type 14 is AGFIFirmwareEventRTCompletionInfo. Apple forwards its
// unaligned value only to optional IOGPU CLPC performance observers; Vinix
// has no CLPC observer layer, so the callback consumes it as advisory.
@[packed]
pub struct G17FirmwareRtCompletionEvent {
pub mut:
	event_type      u32
	completion_info u64
	opaque_00c      [0x3c]u8
}

// Event type 15 asks the host to raise the selected FList threshold and then
// return device-control command 0x21. The backing object is host-created and
// must exist before the response can be acknowledged safely.
@[packed]
pub struct G17FirmwareUmaThresholdInterrupt {
pub mut:
	event_type  u32
	flist_index u32
	opaque_008  [0x40]u8
}

pub fn validate_g17_firmware_completion_event(entry &G17FirmwareEventRingEntry) bool {
	if entry == unsafe { nil } || entry.event_type != g17_firmware_event_completion
		|| sizeof(G17FirmwareCompletionEvent) != g17_firmware_event_entry_size {
		return false
	}
	event := unsafe { &G17FirmwareCompletionEvent(entry) }
	return event.checked_halfword < g17_firmware_event_flag_limit
}

pub fn g17_firmware_completion_has_firing_stamps(entry &G17FirmwareEventRingEntry) bool {
	if !validate_g17_firmware_completion_event(entry) {
		return false
	}
	event := unsafe { &G17FirmwareCompletionEvent(entry) }
	return event.firing[0] != 0 || event.firing[1] != 0 || event.firing[2] != 0
		|| event.firing[3] != 0
}

pub fn validate_g17_firmware_gpu_restart(entry &G17FirmwareEventRingEntry) bool {
	if entry == unsafe { nil } || entry.event_type != g17_firmware_event_gpu_restart
		|| sizeof(G17FirmwareGpuRestartEvent) != g17_firmware_event_entry_size {
		return false
	}
	event := unsafe { &G17FirmwareGpuRestartEvent(entry) }
	return event.stamp_slot == -1 || u32(event.stamp_slot) < g17_firmware_event_stamp_slots
}

pub fn validate_g17_firmware_pm_request_memory(entry &G17FirmwareEventRingEntry) bool {
	if entry == unsafe { nil } || entry.event_type != g17_firmware_event_pm_request_memory
		|| sizeof(G17FirmwarePmRequestMemory) != g17_firmware_event_entry_size {
		return false
	}
	event := unsafe { &G17FirmwarePmRequestMemory(entry) }
	return (event.stamp_slot == -1 || u32(event.stamp_slot) < g17_firmware_event_stamp_slots)
		&& event.manager_index < g17_firmware_event_pm_manager_limit
		&& event.request_kind < g17_firmware_event_pm_request_kind_limit
}

pub fn validate_g17_firmware_channel_error(entry &G17FirmwareEventRingEntry) bool {
	if entry == unsafe { nil } || entry.event_type != g17_firmware_event_channel_error
		|| sizeof(G17FirmwareChannelErrorEvent) != g17_firmware_event_entry_size {
		return false
	}
	event := unsafe { &G17FirmwareChannelErrorEvent(entry) }
	return event.subtype < 5 && event.data_master < 3
		&& (event.stamp_slot == -1 || u32(event.stamp_slot) < g17_firmware_event_stamp_slots)
}

@[inline]
pub fn g17_firmware_event_is_host_noop(event_type u32) bool {
	// Accepted types 11 and 29 return directly to Apple's drain loop. Type
	// 0 calls the G17 firmware-controller vtable method, whose selected
	// implementation is exactly `bti c; ret`. Jump-table slots 2, 3 and 5
	// are also no-ops, but Apple's validator mask rejects them first.
	return event_type < 32
		&& g17_firmware_event_host_noop_mask & (u32(1) << event_type) != 0
}

@[inline]
pub fn validate_g17_firmware_metrology_aging(entry &G17FirmwareEventRingEntry) bool {
	return entry != unsafe { nil }
		&& entry.event_type == g17_firmware_event_metrology_aging
		&& sizeof(G17FirmwareMetrologyAgingEvent) == g17_firmware_event_entry_size
}

pub fn validate_g17_firmware_uma_async_alloc(entry &G17FirmwareEventRingEntry) bool {
	if entry == unsafe { nil } || entry.event_type != g17_firmware_event_uma_async_alloc
		|| sizeof(G17FirmwareUmaAsyncAlloc) != g17_firmware_event_entry_size {
		return false
	}
	event := unsafe { &G17FirmwareUmaAsyncAlloc(entry) }
	return event.request_index < g17_firmware_event_uma_flist_limit
		&& event.required_value_00c != 0
		&& (event.stamp_slot == -1 || u32(event.stamp_slot) < g17_firmware_event_stamp_slots)
}

@[inline]
pub fn validate_g17_firmware_shared_event_signal_complete(entry &G17FirmwareEventRingEntry) bool {
	if entry == unsafe { nil }
		|| entry.event_type != g17_firmware_event_shared_event_signal_complete
		|| sizeof(G17FirmwareSharedEventSignalComplete) != g17_firmware_event_entry_size {
		return false
	}
	event := unsafe { &G17FirmwareSharedEventSignalComplete(entry) }
	return event.event_id != 0
}

@[inline]
pub fn validate_g17_firmware_process_exit_complete(entry &G17FirmwareEventRingEntry) bool {
	return entry != unsafe { nil }
		&& entry.event_type == g17_firmware_event_process_exit_complete
		&& sizeof(G17FirmwareProcessExitComplete) == g17_firmware_event_entry_size
}

pub fn validate_g17_firmware_uma_grow_pool(entry &G17FirmwareEventRingEntry) bool {
	if entry == unsafe { nil } || entry.event_type != g17_firmware_event_uma_grow_pool
		|| sizeof(G17FirmwareUmaGrowPool) != g17_firmware_event_entry_size {
		return false
	}
	event := unsafe { &G17FirmwareUmaGrowPool(entry) }
	return (event.stamp_slot == -1 || u32(event.stamp_slot) < g17_firmware_event_stamp_slots)
		&& event.flist_index < g17_firmware_event_uma_flist_limit
		&& event.required_value_00c != 0 && event.required_value_014 != 0
}

@[inline]
pub fn validate_g17_firmware_rt_completion(entry &G17FirmwareEventRingEntry) bool {
	return entry != unsafe { nil } && entry.event_type == g17_firmware_event_rt_completion
		&& sizeof(G17FirmwareRtCompletionEvent) == g17_firmware_event_entry_size
}

pub fn validate_g17_firmware_uma_threshold_interrupt(entry &G17FirmwareEventRingEntry) bool {
	return entry != unsafe { nil }
		&& entry.event_type == g17_firmware_event_uma_threshold_interrupt
		&& sizeof(G17FirmwareUmaThresholdInterrupt) == g17_firmware_event_entry_size
		&& unsafe { &G17FirmwareUmaThresholdInterrupt(entry) }.flist_index <
		g17_firmware_event_uma_flist_limit
}

// Return -1 for corrupt ring state or an event outside Apple's checked mask,
// 0 when empty, and 1 after copying and consuming one complete entry. The
// acquire/release operations preserve firmware-entry-before-index ordering.
pub fn dequeue_g17_firmware_event(state_buffer voidptr, state_size u64,
	entries_buffer voidptr, entries_size u64, entry &G17FirmwareEventRingEntry) int {
	if state_buffer == unsafe { nil } || state_size != g17_accelerator_ring_state_size
		|| entries_buffer == unsafe { nil } || entries_size < g17_firmware_event_entries_size
		|| entry == unsafe { nil } || sizeof(G17FirmwareEventRingEntry) != g17_firmware_event_entry_size {
		return -1
	}

	unsafe {
		mut state := &G17AcceleratorRingState(state_buffer)
		read_index := katomic.load(&state.read_index)
		write_index := katomic.load(&state.write_index)
		if read_index >= g17_firmware_event_ring_entries
			|| write_index >= g17_firmware_event_ring_entries {
			return -1
		}
		if read_index == write_index {
			return 0
		}

		source := &G17FirmwareEventRingEntry(&u8(entries_buffer) +
			u64(read_index) * g17_firmware_event_entry_size)
		if source.event_type >= 32
			|| g17_firmware_event_type_mask & (u32(1) << source.event_type) == 0 {
			return -1
		}
		C.memcpy(entry, source, g17_firmware_event_entry_size)
		katomic.store(mut &state.read_index,
			(read_index + 1) & (g17_firmware_event_ring_entries - 1))
	}
	return 1
}

// GPU addresses published in the firmware-shared object at 0x1a0. The host
// keeps CPU and GPU addresses for the state and entry allocations separately;
// only these GPU addresses are consumed by firmware.
@[packed]
pub struct G17AcceleratorRingAddresses {
pub mut:
	read_index_address  u64
	cfi_index_address   u64
	write_index_address u64
	entries_address     u64
}

// The primary 0x79800-byte shared region begins with four priority records.
// Each record contains TA, 3D, then CL ring addresses. The two 0x4000-byte
// role-local rings in G17FirmwareSharedData are device-control rings and must
// never be used for these 0x18-byte data-master entries.
pub fn publish_g17_data_master_ring_addresses(buffer voidptr, size u64,
	priority u32, command_type u32, addresses G17AcceleratorRingAddresses) bool {
	if buffer == unsafe { nil } || priority >= g17_data_master_priorities
		|| !valid_g17_accelerator_command_type(command_type)
		|| size < g17_data_master_address_table_size
		|| addresses.read_index_address == 0 || addresses.cfi_index_address == 0
		|| addresses.write_index_address == 0 || addresses.entries_address == 0 {
		return false
	}
	offset := u64(priority) * g17_data_master_priority_record_size
		+ u64(command_type) * g17_data_master_address_record_size
	unsafe {
		C.memcpy(voidptr(u64(buffer) + offset), &addresses,
			g17_data_master_address_record_size)
	}
	return true
}

// Complete set of allocation addresses whose placements in the 0x4c0-byte
// role-specific shared object are independently recovered. T6050 reports a
// zero-sized BRN-workaround table, so that address is intentionally null. The
// optional platform address at 0x2d0 is published only when the matching
// platform flag is set; its zero value is therefore valid. The four service
// addresses at 0x2d8..0x2f0 also have explicit null paths in Apple's pinned
// producer, so a host which does not provide those services may leave them
// zero.
pub struct G17FirmwareSharedBindings {
pub mut:
	role                      u32
	hardware_config_address   u64
	brn_workaround_address    u64
	common_control_address    u64
	large_region_address      u64
	role0_bootstrap_addresses [5]u64
	optional_platform_address u64
	platform_address_2d8      u64
	platform_address_2e0      u64
	platform_address_2e8      u64
	platform_address_2f0      u64
	platform_value_300        u32
	platform_value_304        u32
	accelerator_ring          G17AcceleratorRingAddresses
	auxiliary_ring_addresses  [g17_auxiliary_ring_address_count]u64
	role1_secondary_address   u64
	calibration               [0x10]u8
}

pub fn populate_g17_firmware_shared_data(mut data G17FirmwareSharedData, bindings G17FirmwareSharedBindings) bool {
	if bindings.role > 1 || bindings.hardware_config_address == 0 || bindings.common_control_address == 0 || bindings.large_region_address == 0 {
		return false
	}
	if bindings.accelerator_ring.read_index_address == 0 || bindings.accelerator_ring.cfi_index_address == 0 || bindings.accelerator_ring.write_index_address == 0 || bindings.accelerator_ring.entries_address == 0 {
		return false
	}
	for address in bindings.auxiliary_ring_addresses {
		if address == 0 {
			return false
		}
	}
	if bindings.role == 0 {
		for address in bindings.role0_bootstrap_addresses {
			if address == 0 {
				return false
			}
		}
	} else if bindings.role1_secondary_address == 0 {
		return false
	}

	data = G17FirmwareSharedData{}
	data.address_000 = bindings.hardware_config_address
	data.address_008 = bindings.brn_workaround_address
	data.address_010 = bindings.common_control_address
	data.accelerator_ring = bindings.accelerator_ring
	data.auxiliary_ring_addresses = bindings.auxiliary_ring_addresses
	data.address_200 = bindings.large_region_address
	data.calibration_479 = bindings.calibration
	if bindings.role == 0 {
		data.addresses_254 = bindings.role0_bootstrap_addresses
		data.address_2d0 = bindings.optional_platform_address
		data.platform_address_2d8 = bindings.platform_address_2d8
		data.platform_address_2e0 = bindings.platform_address_2e0
		data.platform_address_2e8 = bindings.platform_address_2e8
		data.platform_address_2f0 = bindings.platform_address_2f0
		data.value_304 = bindings.platform_value_304
		data.state_3e0 = g17_primary_shared_state_initial
	} else {
		data.platform_address_2d8 = bindings.platform_address_2d8
		data.platform_address_2e8 = bindings.platform_address_2e8
		data.value_300 = bindings.platform_value_300
		data.secondary_address_471 = bindings.role1_secondary_address
	}
	return true
}

pub fn initialize_g17_firmware_shared_data(buffer voidptr, size u64, bindings G17FirmwareSharedBindings) bool {
	if buffer == unsafe { nil } || size != g17_firmware_shared_data_size
		|| sizeof(G17FirmwareSharedData) != g17_firmware_shared_data_size {
		return false
	}
	mut data := G17FirmwareSharedData{}
	if !populate_g17_firmware_shared_data(mut data, bindings) {
		return false
	}
	unsafe {
		C.memcpy(buffer, &data, size)
	}
	return true
}

// Scheduler submission entry written by
// AGXArmFirmware::encodeAcceleratorRingCommand. The complete 0x30-byte Apple
// encoder does not touch the first qword. Vinix clears the whole entry before
// filling the five encoded fields so the reserved word remains deterministic
// when a ring slot is reused.
@[packed]
pub struct G17DataMasterEntry {
pub mut:
	reserved_000         u64
	channel_data_address u64
	command_type         u32
	submission_index     u16
	channel_id           u8
	flags                u8
}

pub struct G17DataMasterCommand {
pub:
	channel_data_address u64
	command_type         u32
	submission_index     u16
	channel_id           u8
	channel_flag         u8
}

// Build the outer command fields that are invariant for all concrete G17
// work channels. The Apple base initializer assigns ID 0x80 and clears the
// one-byte channel flag. The work-queue path marks that flag only after its
// first outer submission succeeds, so later entries encode a different flags
// byte without exposing either value to userspace.
pub fn new_g17_data_master_command(channel_data_address u64, command_type u32,
	submission_index u16, commands_submitted bool) ?G17DataMasterCommand {
	if channel_data_address == 0 || !valid_g17_accelerator_command_type(command_type) {
		return none
	}
	return G17DataMasterCommand{
		channel_data_address: channel_data_address
		command_type: command_type
		submission_index: submission_index
		channel_id: g17_data_master_channel_id
		channel_flag: if commands_submitted { u8(1) } else { g17_data_master_channel_flag }
	}
}

@[inline]
fn valid_g17_accelerator_command_type(command_type u32) bool {
	return command_type == g17_accelerator_command_ta
		|| command_type == g17_accelerator_command_3d
		|| command_type == g17_accelerator_command_cl
}

// AGXArmFirmware sends work doorbells through the primary role transport.
// Bits 1:0 select TA/3D/CL and bits 4:2 select one of four queue priorities.
pub fn g17_data_master_doorbell_channel(priority u32, command_type u32) ?u32 {
	if priority >= g17_data_master_priorities
		|| !valid_g17_accelerator_command_type(command_type) {
		return none
	}
	return (priority << 2) | command_type
}

// Reproduce AGXArmFirmware::encodeAcceleratorRingCommand. Apple sources the
// address, ID, and flag from AGXChannel +0x80/+0x18/+0x3c; the caller passes
// those already-decoded values here. Clearing first is a Vinix invariant that
// gives the encoder-preserved qword a defined zero value on every wrap.
pub fn encode_g17_data_master_entry(entry &G17DataMasterEntry,
	command G17DataMasterCommand) bool {
	if entry == unsafe { nil } || command.channel_data_address == 0
		|| !valid_g17_accelerator_command_type(command.command_type) {
		return false
	}

	unsafe {
		C.memset(entry, 0, g17_data_master_entry_size)
		entry.channel_data_address = command.channel_data_address
		entry.command_type = command.command_type
		entry.submission_index = command.submission_index
		entry.channel_id = command.channel_id
		entry.flags = u8(1) & ~command.channel_flag
	}
	return true
}

// Reset one firmware-facing command ring. Data-master entry storage is exactly
// 0x1800 bytes; device-control rings pass their larger 0x4000-byte storage.
// Clearing the complete allocation also establishes reserved_000 == 0 for
// every data-master entry.
pub fn initialize_g17_accelerator_ring(state_buffer voidptr, state_size u64,
	entries_buffer voidptr, entries_size u64) bool {
	if state_buffer == unsafe { nil } || state_size != g17_accelerator_ring_state_size
		|| entries_buffer == unsafe { nil } || entries_size < g17_data_master_entries_bytes {
		return false
	}
	unsafe {
		C.memset(state_buffer, 0, state_size)
		C.memset(entries_buffer, 0, entries_size)
	}
	return true
}

// Reserve, encode, and publish one outer data-master entry. Apple's nextEntry
// is serialized by an IOCommandGate, compares ((write + 1) & 0xff) with the
// read index, and therefore exposes 255 of the 256 slots. Its producer executes
// dmb ish before setWriteIndex; katomic.store is a release store and provides
// the required entry-before-index publication ordering. Callers must serialize
// producers for a given ring just as Apple's command gate does.
pub fn enqueue_g17_data_master_entry(state_buffer voidptr, state_size u64,
	entries_buffer voidptr, entries_size u64, command G17DataMasterCommand) bool {
	if state_buffer == unsafe { nil } || state_size != g17_accelerator_ring_state_size
		|| entries_buffer == unsafe { nil } || entries_size < g17_data_master_entries_bytes {
		return false
	}

	unsafe {
		mut state := &G17AcceleratorRingState(state_buffer)
		read_index := katomic.load(&state.read_index)
		write_index := katomic.load(&state.write_index)
		if read_index >= g17_accelerator_ring_entries
			|| write_index >= g17_accelerator_ring_entries {
			return false
		}
		next_index := (write_index + 1) & 0xff
		if next_index == read_index {
			return false
		}

		mut entry := &G17DataMasterEntry(&u8(entries_buffer) + u64(write_index) * g17_data_master_entry_size)
		if !encode_g17_data_master_entry(entry, command) {
			return false
		}
		katomic.store(mut &state.write_index, next_index)
	}
	return true
}

// Check outer-ring capacity while the caller holds its producer lock. Firmware
// only advances read_index, so a true result cannot become false before the
// same producer publishes unless the shared state is corrupt.
pub fn g17_data_master_ring_has_space(state_buffer voidptr, state_size u64) bool {
	if state_buffer == unsafe { nil } || state_size != g17_accelerator_ring_state_size {
		return false
	}
	unsafe {
		state := &G17AcceleratorRingState(state_buffer)
		read_index := katomic.load(&state.read_index)
		write_index := katomic.load(&state.write_index)
		if read_index >= g17_accelerator_ring_entries
			|| write_index >= g17_accelerator_ring_entries {
			return false
		}
		return ((write_index + 1) & 0xff) != read_index
	}
}

// The device-control path copies a complete 0x40-byte entry into its ring.
@[packed]
pub struct G17DeviceControlEntry {
pub mut:
	command_type u32
	opaque_004   [0x3c]u8
}

// Response to firmware event type 6. request_kind is deliberately repeated:
// Apple's worker writes it at +0x04, then copies the normalized host request
// bytes +0x08..+0x1f into the same offsets in this command.
@[packed]
pub struct G17DeviceControlAllocatePmMemory {
pub mut:
	command_type      u32
	request_kind      u32
	manager_index     u32
	stamp_slot        i32
	request_value     u32
	request_kind_copy u32
	firmware_token    u64
	opaque_020        [0x20]u8
}

@[packed]
pub struct G17DeviceControlUpdateUmaThreshold {
pub mut:
	command_type u32
	flist_index  u32
	opaque_008   [0x38]u8
}

// Construct the byte-exact acknowledgement Apple emits only after its host
// parameter manager has successfully grown. This function does not publish
// the response, ring its 0x84/0x11 doorbell, or imply that Vinix can service
// the allocation request.
pub fn encode_g17_allocate_pm_memory_response(entry &G17DeviceControlEntry,
	event_entry &G17FirmwareEventRingEntry) bool {
	if entry == unsafe { nil } || !validate_g17_firmware_pm_request_memory(event_entry)
		|| sizeof(G17DeviceControlAllocatePmMemory) != g17_device_control_entry_size {
		return false
	}
	unsafe {
		C.memset(entry, 0, g17_device_control_entry_size)
		event := &G17FirmwarePmRequestMemory(event_entry)
		mut response := &G17DeviceControlAllocatePmMemory(entry)
		response.command_type = g17_device_control_allocate_pm_memory
		response.request_kind = event.request_kind
		response.manager_index = event.manager_index
		response.stamp_slot = event.stamp_slot
		response.request_value = event.request_value
		response.request_kind_copy = event.request_kind
		response.firmware_token = event.firmware_token
	}
	return true
}

// Construct the response Apple sends after halUpdateUMADesc has made the new
// FList threshold visible. As with the PM-memory response, encoding alone does
// not authorize the callback to acknowledge an unserviced request.
pub fn encode_g17_uma_threshold_response(entry &G17DeviceControlEntry,
	event_entry &G17FirmwareEventRingEntry) bool {
	if entry == unsafe { nil } || !validate_g17_firmware_uma_threshold_interrupt(event_entry)
		|| sizeof(G17DeviceControlUpdateUmaThreshold) != g17_device_control_entry_size {
		return false
	}
	unsafe {
		C.memset(entry, 0, g17_device_control_entry_size)
		event := &G17FirmwareUmaThresholdInterrupt(event_entry)
		mut response := &G17DeviceControlUpdateUmaThreshold(entry)
		response.command_type = g17_device_control_update_uma_threshold
		response.flist_index = event.flist_index
	}
	return true
}

// Publish one complete device-control entry. Callers must hold a role-local
// producer lock, and must perform the separately recovered doorbell only after
// this release publication succeeds.
pub fn enqueue_g17_device_control_entry(state_buffer voidptr, state_size u64,
	entries_buffer voidptr, entries_size u64, entry &G17DeviceControlEntry) bool {
	if state_buffer == unsafe { nil } || state_size != g17_accelerator_ring_state_size
		|| entries_buffer == unsafe { nil } || entries_size < g17_device_control_entries_size
		|| entry == unsafe { nil } || sizeof(G17DeviceControlEntry) != g17_device_control_entry_size {
		return false
	}

	unsafe {
		mut state := &G17AcceleratorRingState(state_buffer)
		read_index := katomic.load(&state.read_index)
		write_index := katomic.load(&state.write_index)
		if read_index >= g17_accelerator_ring_entries
			|| write_index >= g17_accelerator_ring_entries {
			return false
		}
		next_index := (write_index + 1) & 0xff
		if next_index == read_index {
			return false
		}

		mut target := &G17DeviceControlEntry(&u8(entries_buffer) +
			u64(write_index) * g17_device_control_entry_size)
		C.memcpy(target, entry, g17_device_control_entry_size)
		katomic.store(mut &state.write_index, next_index)
	}
	return true
}

pub fn validate_g17_accelerator_layouts() bool {
	return sizeof(G17AcceleratorRingState) == g17_accelerator_ring_state_size && sizeof(G17AcceleratorRingAddresses) == g17_accelerator_ring_addresses_size && sizeof(G17FirmwareEventRingEntry) == g17_firmware_event_entry_size && sizeof(G17FirmwareCompletionEvent) == g17_firmware_event_entry_size && sizeof(G17FirmwareGpuRestartEvent) == g17_firmware_event_entry_size && sizeof(G17FirmwarePmRequestMemory) == g17_firmware_event_entry_size && sizeof(G17FirmwareChannelErrorEvent) == g17_firmware_event_entry_size && sizeof(G17FirmwareMetrologyAgingEvent) == g17_firmware_event_entry_size && sizeof(G17FirmwareUmaAsyncAlloc) == g17_firmware_event_entry_size && sizeof(G17FirmwareSharedEventSignalComplete) == g17_firmware_event_entry_size && sizeof(G17FirmwareProcessExitComplete) == g17_firmware_event_entry_size && sizeof(G17FirmwareUmaGrowPool) == g17_firmware_event_entry_size && sizeof(G17FirmwareRtCompletionEvent) == g17_firmware_event_entry_size && sizeof(G17FirmwareUmaThresholdInterrupt) == g17_firmware_event_entry_size && sizeof(G17DataMasterEntry) == g17_data_master_entry_size && sizeof(G17DeviceControlEntry) == g17_device_control_entry_size && sizeof(G17DeviceControlAllocatePmMemory) == g17_device_control_entry_size && sizeof(G17DeviceControlUpdateUmaThreshold) == g17_device_control_entry_size && u64(g17_firmware_event_ring_entries) * g17_firmware_event_entry_size == g17_firmware_event_entries_size && u64(g17_accelerator_ring_entries) * g17_data_master_entry_size == g17_data_master_entries_bytes && u64(g17_accelerator_ring_entries) * g17_device_control_entry_size == g17_device_control_entries_size && u64(g17_data_master_priorities) * g17_data_master_priority_record_size == g17_data_master_address_table_size
}

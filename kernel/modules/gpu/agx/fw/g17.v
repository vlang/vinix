module fw

import gpu.agx.hw
import katomic

// Verified anchors for the G17C firmware shipped with macOS 26.5 (25F71),
// RTKit build 3255.120.11. This is deliberately only the root bootstrap
// header: unknown nested structures must not be represented as compatible
// with the older G13 InitData types in this module.
pub const g17_init_message = u64(0x81) << 48
pub const g17_init_address_mask = (u64(1) << 44) - 1
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
pub const g17_accelerator_ring_entries_size = u64(0x4000)
pub const g17_accelerator_ring_addresses_offset = u64(0x1a0)
pub const g17_accelerator_ring_addresses_size = u64(0x20)
pub const g17_auxiliary_ring_addresses_offset = u64(0x1c0)
pub const g17_auxiliary_ring_address_count = 8
pub const g17_data_master_entry_size = u64(0x18)
pub const g17_device_control_entry_size = u64(0x40)
pub const g17_channel_state_size = u64(0xc0)
pub const g17_channel_control_header_size = u64(0x70)
pub const g17_channel_pool_base_size = u64(0x70)
pub const g17_channel_pool_queue_stride = u64(0x80)
pub const g17_cached_command_pointer_size = u64(0x08)
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
pub const g17_fw_util_pstate_control_count = 4
pub const g17_fw_util_pstate_control_size = u64(0x06)
pub const g17_register_override_count = 16
pub const g17_register_override_size = u64(0x18)

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
	opaque_000                           [0x0c]u8
	dm_pause_mode                        u32
	opaque_010                           [0x04]u8
	dm_pause_timer                       u32
	opaque_018                           [0x08]u8
	mtr_sensor_ptd_override_mask         u64
	frg_task_timeout                     u32
	power_config_02c                     u32
	power_config_030                     u32
	smart_idle_enabled                   u32
	state_038                            u32
	opaque_03c                           [0x04]u8
	cpms_window_size                     u32
	cpms_tfca_size                       u32
	state_048                            u32
	kick_channel_qos_04c                 u32
	kick_channel_qos_050                 u32
	platform_values_054                  [3]u16
	state_05a                            u32
	state_05e                            u32
	state_062                            u32
	opaque_066                           [0x04]u8
	state_06a                            u32
	opaque_06e                           [0x0a]u8
	command_submission_enabled           u32
	opaque_07c                           [0x08]u8
	power_config_084                     u32
	opaque_088                           [0x0c]u8
	performance_controller_override      u32
	performance_state_cap                u32
	state_09c                            u32
	state_0a0                            u32
	performance_controller_target        u32
	performance_controller_dead_zone     u32
	performance_controller_transfer      u32
	performance_boost_min_util           u32
	performance_boost_ce_step            u32
	performance_controller_reset_iters   u32
	performance_boost_min_util_valid     u8
	performance_time_filter_constants    [2]u32
	performance_integral_gain_bits       [2]u32
	performance_proportional_gain_bits   [2]u32
	performance_dual_filter              u8
	performance_time_filter_valid        [2]u8
	performance_integral_gain_valid      [2]u8
	performance_proportional_gain_valid  [2]u8
	performance_dual_filter_valid        u8
	opaque_0dd                           [0x07]u8
	clpc_deadline_control_effort         u32
	clpc_deadline_control_override       u32
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
		C.memset(voidptr(u64(buffer) + g17_runtime_performance_policy_offset), 0,
			g17_runtime_performance_policy_size)
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
		C.memset(voidptr(u64(buffer) + g17_runtime_power_policy_offset), 0,
			g17_runtime_power_policy_size)
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

// Hardware/configuration allocation published at offset zero of both
// firmware-shared objects. The host producer and primary firmware consumer
// independently establish the record boundaries below. Unknown scalar and
// derived-power meanings remain opaque.
@[packed]
pub struct G17HardwareConfig {
pub mut:
	address_space_layout_000       [0x38]u8
	color_matrices_038             [g17_color_matrix_count]G17ColorMatrixRecord
	io_mapping_aux_address_638     u64
	io_mappings_640                [g17_io_mapping_count]G17IoMappingRecord
	opaque_e88                     [0x8]u8
	firmware_scalar_block_e90      [0x134]u8
	performance_state_max_fc4      u32
	frequency_table_fc8            [g17_performance_state_capacity]u32
	voltage_table_1008             [g17_performance_state_capacity]G17VoltageTableRow
	sram_voltage_table_1408        [g17_performance_state_capacity]G17VoltageTableRow
	secondary_frequency_table_1808 [g17_performance_state_capacity]u32
	firmware_table_1848            [g17_performance_state_capacity]u32
	firmware_table_1888            [g17_performance_state_capacity]u32
	firmware_table_18c8            [g17_performance_state_capacity]u32
	firmware_table_1908            [g17_performance_state_capacity]u32
	firmware_table_1948            [g17_performance_state_capacity]u32
	opaque_1988                    [0x40]u8
	firmware_block_19c8            [0x80]u8
	opaque_1a48                    [0x148]u8
	firmware_copied_block_1b90     [0x148]u8
	opaque_1cd8                    [0x868]u8
	firmware_late_controls_2540    [0x1d0]u8
}

pub fn validate_g17_bootstrap_allocations() bool {
	return sizeof(G17BootstrapPage) == g17_bootstrap_page_size && sizeof(G17InitRegisterEntry) == g17_init_register_entry_size && sizeof(G17FirmwareSharedData) == g17_firmware_shared_data_size && sizeof(G17RuntimeData) == g17_runtime_data_size && sizeof(G17FwUtilPStateControl) == g17_fw_util_pstate_control_size && sizeof(G17RegisterOverride) == g17_register_override_size && sizeof(G17SmallSharedData) == g17_small_shared_data_size && sizeof(G17PrimaryRegion) == g17_primary_region_size && sizeof(G17SecondaryRegion) == g17_secondary_region_size && sizeof(G17SecondaryAux) == g17_secondary_aux_size && sizeof(G17Role0Region254) == g17_role0_bootstrap_254_size && sizeof(G17Role0Region25c) == g17_role0_bootstrap_25c_size && sizeof(G17Role0Region264) == g17_role0_bootstrap_264_size && sizeof(G17Role0Region26c) == g17_role0_bootstrap_26c_size && sizeof(G17Role0Region274) == g17_role0_bootstrap_274_size && sizeof(G17SharedControl) == g17_common_control_size && sizeof(G17HardwareConfig) == g17_hardware_config_size && sizeof(G17ColorMatrixRecord) == g17_color_matrix_size && sizeof(G17IoMappingRecord) == g17_io_mapping_size && sizeof(G17VoltageTableRow) == g17_voltage_table_columns * sizeof(u32)
}

// Populate the table subset whose source and scale are established by both
// the Apple DeviceTree and the G17 host producer. Frequencies are converted
// from Hz to MHz exactly as the host does. Derived power tables remain zero
// until their producers have been recovered.
pub fn populate_g17_performance_tables(mut config G17HardwareConfig, hardware &hw.HwConfig) bool {
	if hardware.perf_state_count == 0 || hardware.perf_state_count > g17_performance_state_capacity || hardware.perf_state_table_count == 0 || hardware.perf_state_table_count > g17_voltage_table_columns {
		return false
	}

	config.performance_state_max_fc4 = hardware.perf_state_count - 1
	for state := u32(0); state < hardware.perf_state_count; state++ {
		config.frequency_table_fc8[state] = hardware.perf_state_frequencies[state] / 1_000_000
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
	return true
}

fn populate_g17_pio_mappings(mut config G17HardwareConfig, hardware &hw.HwConfig) bool {
	// Recovered from the G17C getPIORelativeOffsetTable virtual selected by
	// the pinned macOS 26.5 driver. Entries whose primary offset is -1 use a
	// different host-only mapping path and do not populate these records.
	indices := [u32(17), 47, 26, 29, 31, 33, 34, 28, 32, 35, 37, 43]
	offsets := [u64(0), 0x23d00, 0xd04000, 0xd10000, 0xd40000, 0xd44000,
		0xd4c000, 0xd50000, 0xd60000, 0xe00000, 0xe40000, 0xe60000]
	sizes := [u32(0x21500), 0x200, 0x8000, 0x4000, 0x4000, 0x4000, 0x200,
		0x10000, 0x20000, 0x4000, 0x4000, 0x58]

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
pub fn initialize_g17_hardware_config(buffer voidptr, size u64, hardware &hw.HwConfig) bool {
	if buffer == unsafe { nil } || size != g17_hardware_config_size
		|| sizeof(G17HardwareConfig) != g17_hardware_config_size
		|| hardware.perf_state_count == 0
		|| hardware.perf_state_count > g17_performance_state_capacity
		|| hardware.perf_state_table_count == 0
		|| hardware.perf_state_table_count > g17_voltage_table_columns {
		return false
	}

	unsafe {
		C.memset(buffer, 0, size)
		mut config := &G17HardwareConfig(buffer)
		if !populate_g17_pio_mappings(mut config, hardware) {
			return false
		}
		config.performance_state_max_fc4 = hardware.perf_state_count - 1
		for state := u32(0); state < hardware.perf_state_count; state++ {
			config.frequency_table_fc8[state] = hardware.perf_state_frequencies[state] / 1_000_000
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
	opaque_02c           [0x18]u8
	sentinel_044         u32
	value_048            u32
	opaque_04c           [0x38]u8
	flag_084             u32
	opaque_088           [0x14]u8
	address_09c          u64
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

pub struct G17ChannelBindings {
pub mut:
	uncached_gpu_address u64
	cached_gpu_address   u64
	context_cookie       u64
	value_048            u32
	address_09c          u64
	ring_entries         u32
}

// Reproduce AGXChannel::resetChannelState for the checked shared fields. The
// platform-derived value/address stay explicit so an unknown default cannot
// accidentally be submitted to firmware.
pub fn initialize_g17_channel(state_buffer voidptr, state_size u64,
	uncached_buffer voidptr, uncached_size u64, cached_buffer voidptr, cached_size u64,
	bindings G17ChannelBindings) bool {
	if state_buffer == unsafe { nil } || state_size != g17_channel_state_size
		|| uncached_buffer == unsafe { nil } || uncached_size < g17_channel_control_header_size
		|| cached_buffer == unsafe { nil } || bindings.uncached_gpu_address == 0
		|| bindings.cached_gpu_address == 0 || bindings.ring_entries == 0
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
		state.mode_028 = 4
		state.sentinel_044 = ~u32(0)
		state.value_048 = bindings.value_048
		state.address_09c = bindings.address_09c
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
pub fn enqueue_g17_channel_command(uncached_buffer voidptr, uncached_size u64,
	cached_buffer voidptr, cached_size u64, command_gpu_address u64) bool {
	if uncached_buffer == unsafe { nil } || uncached_size < g17_channel_control_header_size
		|| cached_buffer == unsafe { nil } || command_gpu_address == 0 {
		return false
	}

	unsafe {
		mut control := &G17ChannelControl(uncached_buffer)
		entries := katomic.load(&control.ring_entries)
		if entries < 2 || u64(entries) > cached_size / g17_cached_command_pointer_size {
			return false
		}
		read_index := katomic.load(&control.read_index)
		write_index := katomic.load(&control.write_index)
		if read_index >= entries || write_index >= entries {
			return false
		}
		next_index := (write_index + 1) % entries
		if next_index == read_index {
			return false
		}

		mut pointer := &u64(u64(cached_buffer) + u64(write_index) * g17_cached_command_pointer_size)
		katomic.store(mut pointer, command_gpu_address)
		katomic.store(mut &control.write_index, next_index)
	}
	return true
}

pub fn validate_g17_channel_layouts() bool {
	return sizeof(G17ChannelState) == g17_channel_state_size
		&& sizeof(G17ChannelControl) == g17_channel_control_header_size
		&& sizeof(G17CachedCommandPointer) == g17_cached_command_pointer_size
}

// G17 accelerator rings use three independently cache-line-spaced indices.
// All indices are range-checked against 256 entries by the Apple host driver.
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
// AGXArmFirmware::encodeAcceleratorRingCommand. The first word is not yet
// understood and must be initialized by the future G17 command encoder.
@[packed]
pub struct G17DataMasterEntry {
pub mut:
	opaque_000           u64
	channel_data_address u64
	command_type         u32
	submission_index     u16
	channel_id           u8
	flags                u8
}

// The device-control path copies a complete 0x40-byte entry into its ring.
// Only its command discriminator is named until individual commands have
// been recovered.
@[packed]
pub struct G17DeviceControlEntry {
pub mut:
	command_type u32
	opaque_004   [0x3c]u8
}

pub fn validate_g17_accelerator_layouts() bool {
	return sizeof(G17AcceleratorRingState) == g17_accelerator_ring_state_size && sizeof(G17AcceleratorRingAddresses) == g17_accelerator_ring_addresses_size && sizeof(G17DataMasterEntry) == g17_data_master_entry_size && sizeof(G17DeviceControlEntry) == g17_device_control_entry_size
}

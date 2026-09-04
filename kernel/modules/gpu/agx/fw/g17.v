module fw

import gpu.agx.hw

// Verified anchors for the G17C firmware shipped with macOS 26.5 (25F71),
// RTKit build 3255.120.11. This is deliberately only the root bootstrap
// header: unknown nested structures must not be represented as compatible
// with the older G13 InitData types in this module.
pub const g17_init_message = u64(0x81) << 48
pub const g17_init_address_mask = (u64(1) << 44) - 1
pub const g17_interface_magic = u64(0x0c8bc322072804c0)
pub const g17_bootstrap_header_size = u64(0xc8)
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
pub const g17_firmware_shared_data_size = u64(0x4c0)
pub const g17_runtime_data_size = u64(0x1ca0)
pub const g17_small_shared_data_size = u64(0x20)
pub const g17_primary_region_size = u64(0xe440)
pub const g17_secondary_region_size = u64(0x6f0)
pub const g17_secondary_aux_size = u64(0xa8)
pub const g17_hardware_config_size = u64(0x2710)
pub const g17_color_matrix_count = 64
pub const g17_color_matrix_size = u64(0x18)
pub const g17_io_mapping_count = 53
pub const g17_io_mapping_size = u64(0x28)
pub const g17_performance_state_capacity = 16
pub const g17_voltage_table_columns = 16

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
	opaque_030                   [0x78]u8
	small_shared_data_address    u64
	primary_region_address       u64
	secondary_region_address     u64
	secondary_aux_address        u64
}

pub fn new_g17_bootstrap_header(role u32) G17BootstrapHeader {
	return G17BootstrapHeader{
		interface_magic: g17_interface_magic
		firmware_role: role
		host_mapped_allocations: 1
	}
}

pub fn validate_g17_bootstrap_header(header &G17BootstrapHeader) bool {
	return sizeof(G17BootstrapHeader) == g17_bootstrap_header_size && header.interface_magic == g17_interface_magic && header.host_mapped_allocations != 0
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

// Allocation sizes and placements are verified even where their contents are
// not. Keeping distinct types prevents accidental reuse of G13 layouts.
@[packed]
pub struct G17RuntimeData {
pub mut:
	opaque [0x1ca0]u8
}

@[packed]
pub struct G17SmallSharedData {
pub mut:
	opaque [0x20]u8
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

@[packed]
pub struct G17ColorMatrixRecord {
pub mut:
	coefficients [12]i16
}

// Modern G17 I/O mappings are 0x28 bytes rather than the 0x20-byte records in
// older AGX firmware. Only the record boundary is currently established.
@[packed]
pub struct G17IoMappingRecord {
pub mut:
	opaque [0x28]u8
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
	return sizeof(G17FirmwareSharedData) == g17_firmware_shared_data_size && sizeof(G17RuntimeData) == g17_runtime_data_size && sizeof(G17SmallSharedData) == g17_small_shared_data_size && sizeof(G17PrimaryRegion) == g17_primary_region_size && sizeof(G17SecondaryRegion) == g17_secondary_region_size && sizeof(G17SecondaryAux) == g17_secondary_aux_size && sizeof(G17HardwareConfig) == g17_hardware_config_size && sizeof(G17ColorMatrixRecord) == g17_color_matrix_size && sizeof(G17IoMappingRecord) == g17_io_mapping_size && sizeof(G17VoltageTableRow) == g17_voltage_table_columns * sizeof(u32)
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

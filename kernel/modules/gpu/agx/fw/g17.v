module fw

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
pub const g17_data_master_entry_size = u64(0x18)
pub const g17_device_control_entry_size = u64(0x40)

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
	return sizeof(G17BootstrapHeader) == g17_bootstrap_header_size
		&& header.interface_magic == g17_interface_magic
		&& header.host_mapped_allocations != 0
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
	return sizeof(G17AcceleratorRingState) == g17_accelerator_ring_state_size
		&& sizeof(G17DataMasterEntry) == g17_data_master_entry_size
		&& sizeof(G17DeviceControlEntry) == g17_device_control_entry_size
}

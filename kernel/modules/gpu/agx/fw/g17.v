module fw

// Verified anchors for the G17C firmware shipped with macOS 26.5 (25F71),
// RTKit build 3255.120.11. This is deliberately only the root bootstrap
// header: unknown nested structures must not be represented as compatible
// with the older G13 InitData types in this module.

pub const g17_init_message = u64(0x81) << 48
pub const g17_init_address_mask = (u64(1) << 44) - 1
pub const g17_interface_magic = u64(0x0c8bc322072804c0)
pub const g17_bootstrap_header_size = u64(0xc8)
pub const g17_host_mapped_allocations_offset = u64(0x2c)

// The primary G17C firmware copies exactly 0xc8 bytes from the host-provided
// root before dereferencing any nested pointers. Its first word is an
// interface identity and offset 0x2c must enable host-mapped allocations.
@[packed]
pub struct G17BootstrapHeader {
pub mut:
	interface_magic         u64
	opaque_008              [0x24]u8
	host_mapped_allocations u32
	opaque_030              [0x98]u8
}

pub fn validate_g17_bootstrap_header(header &G17BootstrapHeader) bool {
	return sizeof(G17BootstrapHeader) == g17_bootstrap_header_size
		&& header.interface_magic == g17_interface_magic
		&& header.host_mapped_allocations != 0
}

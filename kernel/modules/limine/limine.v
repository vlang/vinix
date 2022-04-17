module limine

pub struct LimineUUID {
pub mut:
	a u32
	b u16
	c u16
	d [8]u8
}

pub struct LimineFile {
pub mut:
	revision u64
	address voidptr
	size u64
	path charptr
	cmdline charptr
	media_type u32
	unused u32
	tftp_ip u32
	tftp_port u32
	partition_index u32
	mbr_disk_id u32
	gpt_disk_uuid LimineUUID
	gpt_part_uuid LimineUUID
	part_uuid LimineUUID
}

// Boot info

pub struct LimineBootloaderInfoResponse {
pub mut:
	revision u64
	name charptr
	version charptr
}

pub struct LimineBootloaderInfoRequest {
pub mut:
	id [4]u64 = [
		u64(0xc7b1dd30df4c8b88), 0x0a82e883a194f07b,
		0xf55038d8e2a1202f, 0x279426fcf5f59740
	]!
	revision u64
	response &LimineBootloaderInfoResponse
}

// Stack size

pub struct LimineStackSizeResponse {
pub mut:
	revision u64
}

pub struct LimineStackSizeRequest {
pub mut:
	id [4]u64 = [
		u64(0xc7b1dd30df4c8b88), 0x0a82e883a194f07b,
		0x224ef0460a8e8926, 0xe1cb0fc25f46ea3d
	]!
	revision u64
	response &LimineStackSizeResponse
	stack_size u64
}

// HHDM

pub struct LimineHHDMResponse {
pub mut:
	revision u64
	offset u64
}

pub struct LimineHHDMRequest {
pub mut:
	id [4]u64 = [
		u64(0xc7b1dd30df4c8b88), 0x0a82e883a194f07b,
		0x48dcf1cb8ad2b852, 0x63984e959a98244b
	]!
	revision u64
	response &LimineHHDMResponse
}

// Framebuffer

pub struct LimineFramebuffer {
pub mut:
	address voidptr
	width u16
	height u16
	pitch u16
	bpp u16
	memory_model u8
	red_mask_size u8
	red_mask_shift u8
	green_mask_size u8
	green_mask_shift u8
	blue_mask_size u8
	blue_mask_shift u8
	unused u8
	edid_size u64
	edid voidptr
}

pub struct LimineFramebufferResponse {
pub mut:
	revision u64
	framebuffer_count u64
	framebuffers &&LimineFramebuffer
}

pub struct LimineFramebufferRequest {
pub mut:
	id [4]u64 = [
		u64(0xc7b1dd30df4c8b88), 0x0a82e883a194f07b,
		0xcbfe81d7dd2d1977, 0x063150319ebc9b71
	]!
	revision u64
	response &LimineFramebufferResponse
}

// Terminal

pub struct LimineTerminal {
pub mut:
	columns u32
	rows u32
	framebuffer &LimineFramebuffer
}

pub struct LimineTerminalResponse {
pub mut:
	revision u64
	terminal_count u64
	terminals &&LimineTerminal
	write fn(&LimineTerminal, charptr, u64)
}

pub struct LimineTerminalRequest {
pub mut:
	id [4]u64 = [
		u64(0xc7b1dd30df4c8b88), 0x0a82e883a194f07b,
		0x0785a0aea5d0750f, 0x1c1936fee0d6cf6e
	]!
	revision u64
	response &LimineTerminalResponse
	callback fn(&LimineTerminal, u64, u64, u64, u64)
}

// 5-level paging

pub struct Limine5LevelPagingResponse {
pub mut:
	revision u64
}

pub struct Limine5LevelPagingRequest {
pub mut:
	id [4]u64 = [
		u64(0xc7b1dd30df4c8b88), 0x0a82e883a194f07b,
		0x94469551da9b3192, 0xebe5e86db7382888
	]!
	revision u64
	response &Limine5LevelPagingResponse
}

// SMP

pub struct LimineSMPInfo {
pub mut:
	processor_id u32
	lapic_id u32
	reserved u64
	goto_address fn(&LimineSMPInfo)
	extra_argument u64
}

pub struct LimineSMPResponse {
pub mut:
	revision u64
	flags u32
	bsp_lapic_id u32
	cpu_count u64
	cpus &&LimineSMPInfo
}

pub struct LimineSMPRequest {
pub mut:
	id [4]u64 = [
		u64(0xc7b1dd30df4c8b88), 0x0a82e883a194f07b,
		0x95a67b819a1b857e, 0xa0b61b723b6a73e0
	]!
	revision u64
	response &LimineSMPResponse
	flags u64
}

// Memory map

pub const (
	limine_memmap_usable = 0
	limine_memmap_bootloader_reclaimable = 5
)

pub struct LimineMemmapEntry {
pub mut:
	base u64
	length u64
	@type u64
}

pub struct LimineMemmapResponse {
pub mut:
	revision u64
	entry_count u64
	entries &&LimineMemmapEntry
}

pub struct LimineMemmapRequest {
pub mut:
	id [4]u64 = [
		u64(0xc7b1dd30df4c8b88), 0x0a82e883a194f07b,
		0x67cf3d9d378a806f, 0xe304acdfc50c3c62
	]!
	revision u64
	response &LimineMemmapResponse
}

// Entry point

pub struct LimineEntryPointResponse {
pub mut:
	revision u64
}

pub struct LimineEntryPointRequest {
pub mut:
	id [4]u64 = [
		u64(0xc7b1dd30df4c8b88), 0x0a82e883a194f07b,
		0x13d86c035a1cd3e1, 0x2b0caa89d8f3026a
	]!
	revision u64
	response &LimineEntryPointResponse
	entry fn()
}

// Kernel file

pub struct LimineKernelFileResponse {
pub mut:
	revision u64
	kernel_file &LimineFile
}

pub struct LimineKernelFileRequest {
pub mut:
	id [4]u64 = [
		u64(0xc7b1dd30df4c8b88), 0x0a82e883a194f07b,
		0xad97e90e83f1ed67, 0x31eb5d1c5ff23b69
	]!
	revision u64
	response &LimineKernelFileResponse
}

// Module

pub struct LimineModuleResponse {
pub mut:
	revision u64
	module_count u64
	modules &&LimineFile
}

pub struct LimineModuleRequest {
pub mut:
	id [4]u64 = [
		u64(0xc7b1dd30df4c8b88), 0x0a82e883a194f07b,
		0x3e7e279702be32af, 0xca1c4f3bd1280cee
	]!
	revision u64
	response &LimineModuleResponse
}

// RSDP

pub struct LimineRSDPResponse {
pub mut:
	revision u64
	address voidptr
}

pub struct LimineRSDPRequest {
pub mut:
	id [4]u64 = [
		u64(0xc7b1dd30df4c8b88), 0x0a82e883a194f07b,
		0xc5e77b6b397e7b43, 0x27637845accdcf3c
	]!
	revision u64
	response &LimineRSDPResponse
}

// SMBIOS

pub struct LimineSMBIOSResponse {
pub mut:
	revision u64
	entry_32 voidptr
	entry_64 voidptr
}

pub struct LimineSMBIOSRequest {
pub mut:
	id [4]u64 = [
		u64(0xc7b1dd30df4c8b88), 0x0a82e883a194f07b,
		0x9e9046f11e095391, 0xaa4a520fefbde5ee
	]!
	revision u64
	response &LimineSMBIOSResponse
}

// EFI system table

pub struct LimineEFISystemTableResponse {
pub mut:
	revision u64
	address voidptr
}

pub struct LimineEFISystemTableRequest {
pub mut:
	id [4]u64 = [
		u64(0xc7b1dd30df4c8b88), 0x0a82e883a194f07b,
		0x5ceba5163eaaf6d6, 0x0a6981610cf65fcc
	]!
	revision u64
	response &LimineEFISystemTableResponse
}

// Boot time

pub struct LimineBootTimeResponse {
pub mut:
	revision u64
	boot_time i64
}

pub struct LimineBootTimeRequest {
pub mut:
	id [4]u64 = [
		u64(0xc7b1dd30df4c8b88), 0x0a82e883a194f07b,
		0x502746e184c088aa, 0xfbc5ec83e6327893
	]!
	revision u64
	response &LimineBootTimeResponse
}

// Kernel address

pub struct LimineKernelAddressResponse {
pub mut:
	revision u64
	physical_base u64
	virtual_base u64
}

pub struct LimineKernelAddressRequest {
pub mut:
	id [4]u64 = [
		u64(0xc7b1dd30df4c8b88), 0x0a82e883a194f07b,
		0x71ba76863cc55f63, 0xb2644a48c516a487
	]!
	revision u64
	response &LimineKernelAddressResponse
}

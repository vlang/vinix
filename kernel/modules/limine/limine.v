module limine

@[cinit]
@[_linker_section: '.requests_start_marker']
__global (
	volatile limine_requests_start_marker = [
		u64(0xf6b8f4b39de7d1ae), 0xfab91a6940fcb9cf,
		0x785c6ed015d3e316, 0x181e920a7852b9d9
	]!
)

@[cinit]
@[_linker_section: '.requests_end_marker']
__global (
	volatile limine_requests_end_marker = [
		u64(0xadc0e0531bb10d03), 0x9572709f31764c62
	]!
)

pub struct LimineBaseRevision {
pub mut:
	id [2]u64 = [ u64(0xf9562b2d5c95a6c8), 0x6a7b384944536bdc ]!
	revision u64
}

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
	width u64
	height u64
	pitch u64
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
		0x9d5827dcd881dd75, 0xa3148604f6fab11b
	]!
	revision u64
	response &LimineFramebufferResponse
}

// Paging mode

pub const (
	limine_paging_mode_x86_64_4lvl = 0
	limine_paging_mode_x86_64_5lvl = 1
)

pub struct LiminePagingModeResponse {
pub mut:
	revision u64
	mode u64
	flags u64
}

pub struct LiminePagingModeRequest {
pub mut:
	id [4]u64 = [
		u64(0xc7b1dd30df4c8b88), 0x0a82e883a194f07b,
		0x95c1a0edab0944cb, 0xa4e5cb3842f7488a
	]!
	revision u64
	response &LiminePagingModeResponse
	mode u64
	flags u64
}

// SMP

pub struct LimineSMPInfo {
pub mut:
	processor_id u32
	lapic_id u32
	reserved u64
	goto_address fn(&LimineSMPInfo) = unsafe { nil }
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
	limine_memmap_kernel_and_modules = 6
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
	entry fn() = unsafe { nil }
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

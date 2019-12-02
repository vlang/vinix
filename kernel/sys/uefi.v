module sys

pub const (
	EFI_SYSTEM_TABLE_SIGNATURE = 0x5453595320494249
)

pub struct EfiTableHeader {
pub:
	signature u64
	revision u32
	header_size u32
	crc32 u32
	reserved u32
}

pub struct EfiSystemTable {
pub:
	header EfiTableHeader
	vendor voidptr
	revision u32
	console_in_handle voidptr
	con_in voidptr
	console_out_handle voidptr
	con_out voidptr
	console_err_handle voidptr
	con_err voidptr
}
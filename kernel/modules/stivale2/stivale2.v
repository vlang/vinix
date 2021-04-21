module stivale2

import klock

pub const framebuffer_id = 0x506461d2950408fa

pub const memmap_id = 0x2187f79e8612de07

pub const terminal_id = 0xc2b3f4c3233b0974

[packed]
struct Tag {
pub:
	id   u64
	next voidptr
}

[packed]
struct Struct {
pub:
	bootloader_brand   [64]byte
	bootloader_version [64]byte
	tags               voidptr
}

[packed]
struct FBTag {
pub:
	tag              Tag
	addr             u64
	width            u16
	height           u16
	pitch            u16
	bpp              u16
	memory_model     byte
	red_mask_size    byte
	red_mask_shift   byte
	green_mask_size  byte
	green_mask_shift byte
	blue_mask_size   byte
	blue_mask_shift  byte
}

[packed]
struct TermTag {
pub:
	tag        Tag
	flags      u64
	term_write voidptr
}

[packed]
struct MemmapTag {
pub:
	tag         Tag
	entry_count u64
	entries     MemmapEntry // This is a var length array at the end.
}

[packed]
struct MemmapEntry {
pub:
	base       u64
	length     u64
	entry_type u32
	unused     u32
}

enum MemmapEntryType {
	usable = 1
	reserved = 2
	acpi_reclaimable = 3
	acpi_nvs = 4
	bad_memory = 5
	bootloader_reclaimable = 0x1000
	kernel_and_modules = 0x1001
	framebuffer = 0x1002
}

pub fn get_tag(stivale2_struct &Struct, id u64) &Tag {
	mut current_tag_ptr := stivale2_struct.tags

	for {
		if current_tag_ptr == 0 {
			break
		}

		current_tag := &Tag(current_tag_ptr)

		if current_tag.id == id {
			return current_tag
		}

		current_tag_ptr = current_tag.next
	}

	return 0
}

__global (
	terminal_print_ptr voidptr
)

pub fn terminal_init(stivale2_struct &Struct) {
	terminal_tag := unsafe { &TermTag(get_tag(stivale2_struct, stivale2.terminal_id)) }

	if terminal_tag == 0 {
		return
	}

	terminal_print_ptr = terminal_tag.term_write
}

__global (
	terminal_print_lock klock.Lock
)

pub fn terminal_print(s string) {
	mut ptr := fn (_ voidptr, _ u64) {}
	ptr = terminal_print_ptr
	klock.acquire(&terminal_print_lock)
	ptr(s.str, u64(s.len))
	klock.release(&terminal_print_lock)
}

module stivale2

pub const framebuffer_id = 0x506461d2950408fa

pub const memmap_id = 0x2187f79e8612de07

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

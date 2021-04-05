module stivale2

pub const framebuffer_id = 0x506461d2950408fa

struct Tag {
pub:
	id   u64
	next voidptr
}

struct Struct {
pub:
	bootloader_brand   [64]byte
	bootloader_version [64]byte
	tags               voidptr
}

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

struct Stivale2Tag {
    id u64
    next voidptr
}

struct Stivale2Struct {
    bootloader_brand [64]byte
    bootloader_version [64]byte
    tags voidptr
}

struct Stivale2FBTag {
    tag Stivale2Tag
    addr u64
    width u16
    height u16
    pitch u16
    bpp u16
    memory_model byte
    red_mask_size byte
    red_mask_shift byte
    green_mask_size byte
    green_mask_shift byte
    blue_mask_size byte
    blue_mask_shift byte
}

fn stivale2_get_tag(stivale2_struct &Stivale2Struct, id u64) &Stivale2Tag {
    mut current_tag_ptr := stivale2_struct.tags

    for {
        if current_tag_ptr == 0 {
            break
        }

        current_tag := &Stivale2Tag(current_tag_ptr)

        if current_tag.id == id {
            return current_tag
        }

        current_tag_ptr = current_tag.next
    }

    return 0
}

pub fn kmain(stivale2_struct &Stivale2Struct) {
    fb_tag := &Stivale2FBTag(stivale2_get_tag(stivale2_struct, 0x506461d2950408fa))

    mut framebuffer := &u32(fb_tag.addr)

    for i := 0; i < 500; i++ {
        framebuffer[i + (fb_tag.pitch / 4) * i] = 0xffffff
    }
    for { }
}

import stivale2

pub fn kmain(stivale2_struct &stivale2.Struct) {
    fb_tag := &stivale2.FBTag(stivale2.get_tag(stivale2_struct, 0x506461d2950408fa))

    mut framebuffer := &u32(fb_tag.addr)

    for i := 0; i < 500; i++ {
        framebuffer[i + (fb_tag.pitch / 4) * i] = 0xffffff
    }

    for { }
}

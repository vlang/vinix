section .stivale2hdr write

stivale2hdr:
    .entry_point:   dq 0
    .stack:         dq stack.top
    .flags:         dq 0
    .tags:          dq framebuffer_hdr_tag

section .rodata

framebuffer_hdr_tag:
    .id:            dq 0x3ecc1bc43d0f7971
    .next:          dq 0
    .width:         dw 0
    .height:        dw 0
    .bpp:           dw 0

section .bss

stack:
    resb 8192
.top:

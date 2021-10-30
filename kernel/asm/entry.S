.section .data

.set STIVALE2_HEADER_TAG_UNMAP_NULL_ID, 0x92919432b16fe7e7
.set STIVALE2_HEADER_TAG_TERMINAL_ID, 0xa85d499b1823be72
.set STIVALE2_HEADER_TAG_SMP_ID, 0x1ab015085f3273df
.set STIVALE2_HEADER_TAG_ANY_VIDEO_ID, 0xc75c9fa92a44c4db

.globl stivale_hdr
.globl stack
.globl stack_top
.extern dev__console__stivale2_term_callback

unmap_null_hdr_tag:
.quad STIVALE2_HEADER_TAG_UNMAP_NULL_ID // tag.id
.quad 0                                 // tag.next

terminal_hdr_tag:
.quad STIVALE2_HEADER_TAG_TERMINAL_ID       // tag.id
.quad unmap_null_hdr_tag                    // tag.next
.quad (1 << 0)                              // flags
.quad dev__console__stivale2_term_callback  // callback

smp_hdr_tag:
.quad STIVALE2_HEADER_TAG_SMP_ID    // tag.id
.quad terminal_hdr_tag              // tag.next
.quad 0                             // flags

any_video_hdr_tag:
.quad STIVALE2_HEADER_TAG_ANY_VIDEO_ID // tag.id
.quad smp_hdr_tag                      // tag.next
.quad 0                                // preference

.align 16
stack:
.skip 32768
stack_top:

.section .stivale2hdr

stivale_hdr:
.quad 0                     // entry_point
.quad stack_top             // stack
.quad (1 << 1) | (1 << 2) | (1 << 3)  // flags
.quad any_video_hdr_tag     // next

// Preserve the native entry frame until the synchronous V walk returns.
#ifdef VINIX_ALLOC_TRACK
#ifdef __APPLE__
#define ABI_SYMBOL(name) _##name
#else
#define ABI_SYMBOL(name) name
#endif
.text
.balign 4
.global ABI_SYMBOL(alloc_track)
#ifndef __APPLE__
.type alloc_track, %function
#endif
ABI_SYMBOL(alloc_track):
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    mov x2, x29
    bl ABI_SYMBOL(vinix_alloc_track_enter)
    ldp x29, x30, [sp], #16
    ret
#ifndef __APPLE__
.size alloc_track, .-alloc_track
.section .note.GNU-stack,"",%progbits
#endif
#endif

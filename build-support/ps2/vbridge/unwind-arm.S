/* SPDX-License-Identifier: MIT */
/* Instruction-only C++ unwinding envelope; scope state and cleanup are V. */
#ifdef __APPLE__
#define SYM(x) _##x
.section __TEXT,__text,regular,pure_instructions
#else
#define SYM(x) x
.text
#endif

.globl SYM(vinix_ps2_unwind_scope)
.p2align 2
#ifndef __APPLE__
.type vinix_ps2_unwind_scope,@function
#endif
SYM(vinix_ps2_unwind_scope):
Lvinix_ps2_unwind_scope_begin:
.cfi_startproc
#ifdef __APPLE__
.cfi_personality 155, ___gxx_personality_v0
.cfi_lsda 16, Lvinix_ps2_unwind_scope_lsda
#else
.cfi_personality 155, DW.ref.__gxx_personality_v0
.cfi_lsda 27, Lvinix_ps2_unwind_scope_lsda
#endif
 stp x24,x23,[sp,#-64]!
.cfi_def_cfa_offset 64
 stp x22,x21,[sp,#16]
 stp x20,x19,[sp,#32]
 stp x29,x30,[sp,#48]
 add x29,sp,#48
.cfi_def_cfa w29,16
.cfi_offset w19,-24
.cfi_offset w20,-32
.cfi_offset w21,-40
.cfi_offset w22,-48
.cfi_offset w23,-56
.cfi_offset w24,-64
.cfi_offset w30,-8
.cfi_offset w29,-16
 mov x19,x0
 mov x20,x2
 mov x21,x3
Lvinix_ps2_unwind_scope_body_start:
 blr x1
Lvinix_ps2_unwind_scope_body_end:
 mov w22,w0
 mov x0,x19
Lvinix_ps2_unwind_scope_normal_cleanup_start:
 blr x20
Lvinix_ps2_unwind_scope_normal_cleanup_end:
 b Lvinix_ps2_unwind_scope_return
Lvinix_ps2_unwind_scope_landing:
 mov x22,x0
 mov x23,x1
 mov x0,x19
Lvinix_ps2_unwind_scope_unwind_cleanup_start:
 blr x20
Lvinix_ps2_unwind_scope_unwind_cleanup_end:
Lvinix_ps2_unwind_scope_resume:
 mov x0,x22
 bl SYM(_Unwind_Resume)
Lvinix_ps2_unwind_scope_terminate:
 bl SYM(__cxa_begin_catch)
 bl SYM(_ZSt9terminatev)
Lvinix_ps2_unwind_scope_return:
 mov w0,w22
 ldp x29,x30,[sp,#48]
 ldp x20,x19,[sp,#32]
 ldp x22,x21,[sp,#16]
 ldp x24,x23,[sp],#64
 ret
Lvinix_ps2_unwind_scope_end:
.cfi_endproc
#ifndef __APPLE__
.size vinix_ps2_unwind_scope,Lvinix_ps2_unwind_scope_end-vinix_ps2_unwind_scope
#endif

#ifdef __APPLE__
.section __TEXT,__gcc_except_tab
#else
.section .gcc_except_table,"a",@progbits
#endif
.p2align 2
EH_except_table_vinix_ps2_unwind_scope:
Lvinix_ps2_unwind_scope_lsda:
 .byte 255
 .byte 155
 .uleb128 Lvinix_ps2_unwind_scope_ttbase-Lvinix_ps2_unwind_scope_ttref
Lvinix_ps2_unwind_scope_ttref:
 .byte 1
 .uleb128 Lvinix_ps2_unwind_scope_cend-Lvinix_ps2_unwind_scope_cbegin
Lvinix_ps2_unwind_scope_cbegin:
 .uleb128 Lvinix_ps2_unwind_scope_body_start-Lvinix_ps2_unwind_scope_begin
 .uleb128 Lvinix_ps2_unwind_scope_body_end-Lvinix_ps2_unwind_scope_body_start
 .uleb128 Lvinix_ps2_unwind_scope_landing-Lvinix_ps2_unwind_scope_begin
 .byte 0
 .uleb128 Lvinix_ps2_unwind_scope_normal_cleanup_start-Lvinix_ps2_unwind_scope_begin
 .uleb128 Lvinix_ps2_unwind_scope_normal_cleanup_end-Lvinix_ps2_unwind_scope_normal_cleanup_start
 .uleb128 Lvinix_ps2_unwind_scope_terminate-Lvinix_ps2_unwind_scope_begin
 .byte 1
 .uleb128 Lvinix_ps2_unwind_scope_unwind_cleanup_start-Lvinix_ps2_unwind_scope_begin
 .uleb128 Lvinix_ps2_unwind_scope_unwind_cleanup_end-Lvinix_ps2_unwind_scope_unwind_cleanup_start
 .uleb128 Lvinix_ps2_unwind_scope_terminate-Lvinix_ps2_unwind_scope_begin
 .byte 1
 .uleb128 Lvinix_ps2_unwind_scope_unwind_cleanup_end-Lvinix_ps2_unwind_scope_begin
 .uleb128 Lvinix_ps2_unwind_scope_end-Lvinix_ps2_unwind_scope_unwind_cleanup_end
 .byte 0
 .byte 0
Lvinix_ps2_unwind_scope_cend:
 .byte 1,0
.p2align 2
 .long 0
Lvinix_ps2_unwind_scope_ttbase:

#ifdef __APPLE__
.section __TEXT,__text,regular,pure_instructions
#else
.text
#endif

#ifndef __APPLE__
.hidden DW.ref.__gxx_personality_v0
.weak DW.ref.__gxx_personality_v0
.section .data.DW.ref.__gxx_personality_v0,"awG",@progbits,DW.ref.__gxx_personality_v0,comdat
.p2align 3
.type DW.ref.__gxx_personality_v0,@object
.size DW.ref.__gxx_personality_v0,8
DW.ref.__gxx_personality_v0:
 .quad __gxx_personality_v0
.section .note.GNU-stack,"",@progbits
#else
.subsections_via_symbols
#endif

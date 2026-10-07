/* SPDX-License-Identifier: MIT */
/* Instruction-only C++ unwinding envelope; scope state and cleanup are V. */
#ifdef __APPLE__
#define SYM(x) _##x
.section __TEXT,__text,regular,pure_instructions
#else
#define SYM(x) x
.text
#endif

.globl vinix_ps2_unwind_scope
.type vinix_ps2_unwind_scope,@function
.p2align 4
vinix_ps2_unwind_scope:
Lvinix_ps2_unwind_scope_begin:
.cfi_startproc
.cfi_personality 155,DW.ref.__gxx_personality_v0
.cfi_lsda 27,Lvinix_ps2_unwind_scope_lsda
 pushq %r15
.cfi_def_cfa_offset 16
.cfi_offset %r15,-16
 pushq %r14
.cfi_def_cfa_offset 24
.cfi_offset %r14,-24
 pushq %r13
.cfi_def_cfa_offset 32
.cfi_offset %r13,-32
 pushq %r12
.cfi_def_cfa_offset 40
.cfi_offset %r12,-40
 pushq %rbx
.cfi_def_cfa_offset 48
.cfi_offset %rbx,-48
 movq %rdi,%rbx
 movq %rdx,%r12
 movq %rcx,%r13
Lvinix_ps2_unwind_scope_body_start:
 call *%rsi
Lvinix_ps2_unwind_scope_body_end:
 movl %eax,%r14d
 movq %rbx,%rdi
Lvinix_ps2_unwind_scope_normal_cleanup_start:
 call *%r12
Lvinix_ps2_unwind_scope_normal_cleanup_end:
 jmp Lvinix_ps2_unwind_scope_return
Lvinix_ps2_unwind_scope_landing:
 movq %rax,%r14
 movq %rdx,%r15
 movq %rbx,%rdi
Lvinix_ps2_unwind_scope_unwind_cleanup_start:
 call *%r12
Lvinix_ps2_unwind_scope_unwind_cleanup_end:
Lvinix_ps2_unwind_scope_resume:
 movq %r14,%rdi
 call _Unwind_Resume
Lvinix_ps2_unwind_scope_terminate:
 movq %rax,%rdi
 call __cxa_begin_catch
 call _ZSt9terminatev
Lvinix_ps2_unwind_scope_return:
 movl %r14d,%eax
 popq %rbx
.cfi_def_cfa_offset 40
 popq %r12
.cfi_def_cfa_offset 32
 popq %r13
.cfi_def_cfa_offset 24
 popq %r14
.cfi_def_cfa_offset 16
 popq %r15
.cfi_def_cfa_offset 8
 ret
Lvinix_ps2_unwind_scope_end:
.cfi_endproc
.size vinix_ps2_unwind_scope,Lvinix_ps2_unwind_scope_end-vinix_ps2_unwind_scope

#ifdef __APPLE__
.section __TEXT,__gcc_except_tab
#else
.section .gcc_except_table,"a",@progbits
#endif
.p2align 2
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

.text

.hidden DW.ref.__gxx_personality_v0
.weak DW.ref.__gxx_personality_v0
.section .data.DW.ref.__gxx_personality_v0,"awG",@progbits,DW.ref.__gxx_personality_v0,comdat
.p2align 3
.type DW.ref.__gxx_personality_v0,@object
.size DW.ref.__gxx_personality_v0,8
DW.ref.__gxx_personality_v0:
 .quad __gxx_personality_v0
.section .note.GNU-stack,"",@progbits

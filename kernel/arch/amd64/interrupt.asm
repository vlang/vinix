section .text
bits 64

%macro pushaq 0
    ; Pushed all general purpose register into stack
    ; no pushad in long mode :/
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push rbp
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15
%endmacro

%macro popaq 0
    ; Pops all general purpose register from stack
    ; no popad in long mode :/
    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rbp
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
%endmacro

global isr_handler:
isr_handler:
    ; Interrupt Service Routine handler
    pushaq

    cld

    popaq
    iret

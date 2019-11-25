global _entry
extern vrt_main
extern _start
extern _end

; higher-half virtual memory address
KERNEL_VMA equ 0xFFFFFFFF80000000

; MSR numbers
MSR_EFER equ 0xC0000080

; EFER bitmasks
EFER_LM equ 0x100
EFER_NX equ 0x800

; CR0 bitmasks
CR0_PAGING equ 0x80000000

; CR4 bitmasks
CR4_PAE equ 0x20
CR4_PSE equ 0x10

; page flag bitmasks
PG_PRESENT  equ 0x1
PG_WRITABLE equ 0x2
PG_USER     equ 0x4
PG_BIG      equ 0x80
PG_NO_EXEC  equ 0x8000000000000000

; page and table size constants
LOG_TABLE_SIZE equ 9
LOG_PAGE_SIZE  equ 12
PAGE_SIZE  equ (1 << LOG_PAGE_SIZE)
TABLE_SIZE equ (1 << LOG_TABLE_SIZE)

; bootstrap stack size and alignment
STACK_SIZE  equ 8192
STACK_ALIGN equ 16

section .multiboot
align 8

multiboot_header:
    dd 0xE85250D6
    dd 0
    dd .hdr_end - multiboot_header
    dd -(0xE85250D6 + (.hdr_end - multiboot_header)) & 0xFFFFFFFF

.tag_fb:
align 8
    dw 5 ; MULTIBOOT_TAG_FRAMEBUFFER
    dw 1 ; MULTIBOOT_TAG_OPTIONAL
    dd .tag_fb_end - .tag_fb
    dd 1024
    dd 768
    dd 32
.tag_fb_end:
.tag_end:
align 8
    dw 0 ; MULTIBOOT_TAG_END
    dw 0
    dd 8
.hdr_end:

section .initl
align PAGE_SIZE
[global boot_pml4]
boot_pml4:
  dq (boot_pml3l + PG_PRESENT + PG_WRITABLE)
  times (TABLE_SIZE - 4) dq 0
  dq (identity_pml3 + PG_PRESENT + PG_WRITABLE)
  dq (boot_pml4 + PG_PRESENT + PG_WRITABLE + PG_NO_EXEC)
  dq (boot_pml3h + PG_PRESENT + PG_WRITABLE)

boot_pml3l:
  dq (boot_pml2 + PG_PRESENT + PG_WRITABLE)
  dq 0
  times (TABLE_SIZE - 2) dq 0

boot_pml3h:
  times (TABLE_SIZE - 2) dq 0
  dq (boot_pml2 + PG_PRESENT + PG_WRITABLE)
  dq 0

boot_pml2:
  dq (0x0 + PG_PRESENT + PG_WRITABLE + PG_BIG)
  times (TABLE_SIZE - 1) dq 0

identity_pml3:
  times (TABLE_SIZE - 5) dq 0
  dq (pmm_stack_pml2 + PG_PRESENT + PG_WRITABLE)
  dq (identity_pml2a + PG_PRESENT + PG_WRITABLE)
  dq (identity_pml2b + PG_PRESENT + PG_WRITABLE)
  dq (identity_pml2c + PG_PRESENT + PG_WRITABLE)
  dq (identity_pml2d + PG_PRESENT + PG_WRITABLE)

pmm_stack_pml2:
  times (TABLE_SIZE - 1) dq 0
  dq (pmm_stack_pml1 + PG_PRESENT + PG_WRITABLE)

pmm_stack_pml1:
  times TABLE_SIZE dq 0

identity_pml2a:
  %assign pg 0
  %rep TABLE_SIZE
    dq (pg + PG_PRESENT + PG_WRITABLE + PG_BIG + PG_NO_EXEC)
    %assign pg pg+PAGE_SIZE*TABLE_SIZE
  %endrep

identity_pml2b:
  %rep TABLE_SIZE
    dq (pg + PG_PRESENT + PG_WRITABLE + PG_BIG + PG_NO_EXEC)
    %assign pg pg+PAGE_SIZE*TABLE_SIZE
  %endrep

identity_pml2c:
  %rep TABLE_SIZE
    dq (pg + PG_PRESENT + PG_WRITABLE + PG_BIG + PG_NO_EXEC)
    %assign pg pg+PAGE_SIZE*TABLE_SIZE
  %endrep

identity_pml2d:
  %rep TABLE_SIZE
    dq (pg + PG_PRESENT + PG_WRITABLE + PG_BIG + PG_NO_EXEC)
    %assign pg pg+PAGE_SIZE*TABLE_SIZE
  %endrep

; the global descriptor table
gdt:
  ; null selector
    dq 0
  ; cs selector
    dq 0x00AF98000000FFFF
  ; ds selector
    dq 0x00CF92000000FFFF
gdt_end:
  dq 0 ; some extra padding so the gdtr is 16-byte aligned
gdtr:
  dw gdt_end - gdt - 1
  dq gdt

align 4
bits 32
_entry:
    mov esp, 0xEFFFF0
    xor ebp, ebp
    push ebx
    push eax

    mov eax, 0x10
    mov ds, eax
    mov es, eax

    ; check for cpuid extensions
    mov eax, 0x80000000
    cpuid
    cmp eax, 0x80000001
    jz near .no_long_mode

    ; check for long mode
    mov eax, 0x80000001
    cpuid
    test edx, 1 << 29
    jz near .no_long_mode

    ;call near setup_page_tables

    mov eax, cr4
    or eax, 1 << 6 | 1 << 5 ; enable PSE and PAE
    mov cr4, eax

    ; enable long mode
    mov ecx, 0xC0000080
    rdmsr
    or eax, 1 << 8 | 1 << 11; long mode and NX
    wrmsr

    ; load PML4
    mov eax, boot_pml4
    mov cr3, eax

    ;printaddr32 eax

    ; enable paging
    mov eax, cr0
    or eax, 1 << 31
    mov cr0, eax

    ;pop esi
    ;pop edi

    lgdt [gdtr]
    mov ax, 0x10
    mov ss, ax
    mov ax, 0x0
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    jmp 0x08:.trampoline

.no_long_mode:
    mov eax, nl_msg
    push eax
    call near display_error
    add esp, 4
    jmp near halt

.trampoline:
bits 64
    mov rax, qword start_kernel
    jmp rax

halt:
bits 32
    cli
.spin:
    hlt
    jmp near .spin

display_error:
bits 32
    mov edi, 0xB8000
    mov eax, 0x0C000C00
    cld
    mov ecx, 1000
    rep stosd
    mov edi, 0xB8000
    mov esi, [esp + 8]
.de_l: 
    movsb
    inc edi
    movzx eax, byte [esi]
    test eax, 0xff
    jnz near .de_l
    ret

section .inith
start_kernel:
bits 64
    ; re-load the GDTR with a virtual base address
    mov rax, [gdtr + 2]
    mov rbx, KERNEL_VMA
    add rax, rbx
    mov [gdtr + 2], rax
    mov rax, gdtr + KERNEL_VMA
    lgdt [rax]

    ; map the rest of the kernel into virtual memory
    mov rax, _start - KERNEL_VMA      ; first page number
    shr rax, LOG_PAGE_SIZE + LOG_TABLE_SIZE
    mov rbx, _end - KERNEL_VMA        ; last page number
    shr rbx, LOG_PAGE_SIZE + LOG_TABLE_SIZE
    mov rcx, boot_pml2 + KERNEL_VMA   ; pointer into pml2 table
.map_page:
    ; calculate the value of the page table entry
    mov rdx, rax
    shl rdx, LOG_PAGE_SIZE + LOG_TABLE_SIZE
    mov r8, rdx
    mov r9, KERNEL_VMA
    add r8, r9
    or rdx, PG_PRESENT + PG_WRITABLE + PG_BIG

    ; write the page table entry
    mov [rcx], rdx
    
    ; increment pml2 pointer
    add rcx, 8

    ; check if we should terminate the loop
    cmp rax, rbx
    je .map_page_end

    ; increment the counter and map the next page
    inc rax
    jmp .map_page
.map_page_end:
    ; set up the new stack (multiboot2 spec says the stack pointer could be
    ; anything - even pointing to invalid memory)
    mov rbp, 0 ; terminate stack traces here
    ;mov rsp, qword stack + STACK_SIZE
    mov rsp, 0xFFFFFEFF00000000 | 0xEFFFF0

    ; unmap the identity-mapped memory
    mov qword [boot_pml4], 0x0

    ; invalidate the TLB cache for the identity-mapped memory
    invlpg [0x0]

    ; clear the RFLAGS register
    push 0x0
    popf

    mov rax, vrt_main
    call rax

section .init_data
align 16

nl_msg: db "This kernel boots only on x86-64 CPUs.", 0

section .bss
align STACK_ALIGN
stack:
    resb STACK_SIZE
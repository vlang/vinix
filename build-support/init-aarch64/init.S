// Minimal AArch64 userspace init program
// Proves userspace works by making syscalls via SVC
//
// Syscall ABI: x8 = syscall number, x0-x5 = arguments.
// The SVC handler inserts GPRState* as C arg0, so user x0 → C arg1, etc.

.global _start
_start:
    // syscall 0 = kprint(gpr_state, buf, count)
    // User provides: x0 = buf, x1 = count
    ldr x0, =msg              // buf pointer → becomes C arg1
    mov x1, #21               // length → becomes C arg2
    mov x8, #0                // syscall number (kprint)
    svc #0

    // syscall 15 = exit(gpr_state, status)
    // User provides: x0 = status
    mov x0, #0                // status = 0 → becomes C arg1
    mov x8, #15               // syscall number (exit)
    svc #0

    // Should never reach here
    b .

.section .rodata
msg: .asciz "Hello from userland!\n"

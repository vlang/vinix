module syscall

import x86.cpu.local as cpulocal
import userland

pub fn leave(context &cpulocal.GPRState) {
	asm volatile amd64 { cli }

	userland.dispatch_a_signal(context)
}

pub fn enter() {
	asm volatile amd64 { sti }
}

[_naked]
pub fn ud_entry(gpr_state &cpulocal.GPRState) {
	asm volatile amd64 {
		cld
		sti

		mov rax, [rdi + 56]
		mov rsp, rdi

		mov rsi, [rdi + 48]
		mov rdx, [rdi + 40]
		mov rcx, [rdi + 32]
		mov r8,  [rdi + 72]
		mov r9,  [rdi + 80]

		xor rbp, rbp
		lea rbx, [rip + syscall_table]
		call [rbx + rax * 8 + 0]

		mov r8, rdx

		pop rbx
		mov ds, ebx
		pop rbx
		mov es, ebx
		// Discard saved RAX
		add rsp, 8
		pop rbx
		pop rcx
		pop rdx
		pop rsi
		pop rdi
		pop rbp
		// Discard saved R8
		add rsp, 8
		pop r9
		pop r10
		pop r11
		pop r12
		pop r13
		pop r14
		pop r15
		add rsp, 8
		iretq
		;;;memory
	}
}

[_naked]
fn sysenter_entry() {
	asm volatile amd64 {
		push 0x53
		push r10
		pushfq
		push 0x4b
		push r11
		push 0

		cld

		push rdi
		push rsi
		push rdx
		push rcx
		push r8
		push r9

		call syscall__enter

		pop r9
		pop r8
		pop rcx
		pop rdx
		pop rsi
		pop rdi

		push r15
		push r14
		push r13
		push r12
		push r11
		push r10
		push r9
		push r8
		push rbp
		push rdi
		push rsi
		push rdx
		push rcx
		push rbx
		push rax
		push 0x53
		push 0x53

		mov rax, rdi
		mov rdi, rsp

		xor rbp, rbp
		lea rbx, [rip + syscall_table]
		call [rbx + rax * 8 + 0]

		mov [rsp + 16], rax
		mov [rsp + 72], rdx

		mov rdi, rsp

		call syscall__leave

		pop rbx
		mov ds, ebx
		pop rbx
		mov es, ebx
		pop rax
		pop rbx
		pop rcx
		pop rdx
		pop rsi
		pop rdi
		pop rbp
		pop r8
		pop r9
		pop rcx
		pop rdx
		pop r12
		pop r13
		pop r14
		pop r15

		rex.w sysexit
		;;;memory
	}
}

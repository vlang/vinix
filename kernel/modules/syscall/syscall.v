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
fn syscall_entry() {
	asm volatile amd64 {
		swapgs

		// Save user stack
		mov gs:[16], rsp
		// Switch to kernel stack
		mov rsp, gs:[8]

		push 0x3b
		push gs:[16]
		push r11
		push 0x43
		push rcx

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
		mov eax, es
		push rax
		mov eax, ds
		push rax

		// Save syscall context
		mov gs:[24], rsp

		sti

		xor rbp, rbp
		lea rbx, [rip + syscall_table]
		call [rbx + rax * 8 + 0]

		mov [rsp + 16], rax

		mov rdi, rsp
		call syscall__leave

		pop rax
		mov ds, eax
		pop rax
		mov es, eax
		pop rax
		pop rbx
		pop rcx
		pop rdx
		pop rsi
		pop rdi
		pop rbp
		pop r8
		pop r9
		pop r10
		pop r11
		pop r12
		pop r13
		pop r14
		pop r15

		cli

		// Restore user stack
		mov rsp, gs:[16]

		swapgs

		rex.w sysret

		;
		;
		; memory
	}
}

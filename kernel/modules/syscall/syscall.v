module syscall

[_naked]
fn sysenter_entry() {
	asm amd64 {
		push 0x53
		push 0
		pushfq
		// workaround
		mov rax, rax
		//push 0x4b
		.byte 0x6a
		.byte 0x4b
		push 0

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
		//push 0x4b
		.byte 0x6a
		.byte 0x4b
		//push 0x4b
		.byte 0x6a
		.byte 0x4b

		cld
		sti

		mov rax, rdi
		mov rdi, rsp

		lea rbx, [rip + syscall_table]
		call [rbx + rax * 8 + 0]

		// Discard saved RAX, DS, and ES
		add rsp, 24
		pop rbx
		pop rcx
		// Discard saved errno
		add rsp, 8
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

		//rex.w sysexit
		.byte 0x48
		.byte 0x0f
		.byte 0x35
	}
}

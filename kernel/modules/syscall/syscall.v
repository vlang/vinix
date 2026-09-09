module syscall

import x86.cpu.local as cpulocal
import proc
import userland

// The x86-64 port predates Vinix's Linux-compatible arm64 ABI, so its native
// libc puts the syscall number in rdi and receives errno in rdx. Alpine uses
// the Linux register convention instead. Keep that choice on the process so
// exec can switch ABIs without breaking the existing amd64 desktop/userland.
@[export: 'syscall_is_linux']
fn syscall_is_linux() u64 {
	return if proc.current_thread().process.linux_abi { u64(1) } else { u64(0) }
}

@[markused]
fn leave(context &cpulocal.GPRState) {
	asm volatile amd64 {
		cli
	}

	userland.dispatch_a_signal(context)
}

@[_naked]
fn syscall_entry() {
	asm volatile amd64 {
		swapgs // Save user stack
		mov gs:[32], rsp // Switch to kernel stack
		mov rsp, gs:[24]
		push 0x3b
		push gs:[32]
		push r11
		push 0x43
		push rcx
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
		mov eax, es
		push rax
		mov eax, ds
		push rax
		sti
		call syscall_is_linux
		test rax, rax
		jnz f1

		// Native Vinix ABI: rdi is the syscall number and arguments start in
		// rsi. Reload everything because syscall_is_linux() may clobber it.
		xor r12, r12
		mov rbx, [rsp + 56]
		cmp rbx, 66
		jae f2
		mov rsi, [rsp + 48]
		mov rdx, [rsp + 40]
		mov rcx, [rsp + 88]
		mov r8, [rsp + 72]
		mov r9, [rsp + 80]
		mov rdi, rsp
		lea rax, [rip + syscall_table]
		call [rax + rbx * 8 + 0]
		jmp f4

		// Linux x86-64 ABI: rax is the number, followed by
		// rdi,rsi,rdx,r10,r8,r9. Vinix handlers take the saved GPR frame as
		// their first argument, so shift the six Linux arguments right once;
		// the last one is passed on the C stack.
		1:
		mov r12, 1
		mov r13, [rsp + 16]
		cmp r13, 512
		jae f3
		mov rax, rsp
		sub rsp, 16
		mov rdi, rax
		mov rsi, [rax + 56]
		mov rdx, [rax + 48]
		mov rcx, [rax + 40]
		mov r8, [rax + 88]
		mov r9, [rax + 72]
		mov rbx, [rax + 80]
		mov [rsp], rbx
		lea rbx, [rip + linux_syscall_table]
		call [rbx + r13 * 8 + 0]
		add rsp, 16
		jmp f4

		2:
		xor r12, r12
		mov rax, 0xffffffffffffffff
		mov rdx, 38
		jmp f4

		3:
		mov r12, 1
		mov rax, 38
		neg rax
		xor rdx, rdx

		4:
		// Native calls return (result, errno) in rax/rdx. Linux encodes errno
		// as a negative result and otherwise preserves the caller's rdx.
		test r12, r12
		jz f5
		test rdx, rdx
		jz f6
		neg rdx
		mov rax, rdx
		6:
		mov [rsp + 16], rax
		jmp f7
		5:
		mov [rsp + 16], rax
		mov [rsp + 40], rdx
		7:
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
		pop r15 // Restore user stack
		mov rsp, gs:[32]
		swapgs
		sysretq
		; ; ; memory
	}
}


/Users/alex/code/vinix/build/alloc-bench-integration/vinix-x86_64:	file format elf64-x86-64

Disassembly of section .text:

ffffffff800d7ab0 <memory__Slab__sfree>:
ffffffff800d7ab0: 55                   	pushq	%rbp
ffffffff800d7ab1: 48 89 e5             	movq	%rsp, %rbp
ffffffff800d7ab4: 41 57                	pushq	%r15
ffffffff800d7ab6: 41 56                	pushq	%r14
ffffffff800d7ab8: 41 55                	pushq	%r13
ffffffff800d7aba: 41 54                	pushq	%r12
ffffffff800d7abc: 53                   	pushq	%rbx
ffffffff800d7abd: 48 81 ec a8 00 00 00 	subq	$0xa8, %rsp
ffffffff800d7ac4: 48 8b 05 0d 98 0b 00 	movq	0xb980d(%rip), %rax     # 0xffffffff801912d8 <__stack_chk_guard>
ffffffff800d7acb: 48 89 45 d0          	movq	%rax, -0x30(%rbp)
ffffffff800d7acf: 48 85 f6             	testq	%rsi, %rsi
ffffffff800d7ad2: 0f 84 ea 02 00 00    	je	0xffffffff800d7dc2 <memory__Slab__sfree+0x312>
ffffffff800d7ad8: 49 89 f7             	movq	%rsi, %r15
ffffffff800d7adb: 49 89 fe             	movq	%rdi, %r14
ffffffff800d7ade: e8 ed 47 f5 ff       	callq	0xffffffff8002c2d0 <klock__Lock__acquire>
ffffffff800d7ae3: 48 8b 05 2e 95 0b 00 	movq	0xb952e(%rip), %rax     # 0xffffffff80191018 <memory__page_size>
ffffffff800d7aea: 48 89 c3             	movq	%rax, %rbx
ffffffff800d7aed: 48 f7 db             	negq	%rbx
ffffffff800d7af0: 4c 21 fb             	andq	%r15, %rbx
ffffffff800d7af3: 48 b9 42 4c 53 58 49 4e 49 56	movabsq	$0x56494e4958534c42, %rcx # imm = 0x56494E4958534C42
ffffffff800d7afd: 48 39 4b 08          	cmpq	%rcx, 0x8(%rbx)
ffffffff800d7b01: 0f 85 f0 02 00 00    	jne	0xffffffff800d7df7 <memory__Slab__sfree+0x347>
ffffffff800d7b07: 4c 39 33             	cmpq	%r14, (%rbx)
ffffffff800d7b0a: 0f 85 e7 02 00 00    	jne	0xffffffff800d7df7 <memory__Slab__sfree+0x347>
ffffffff800d7b10: 48 ff c8             	decq	%rax
ffffffff800d7b13: 4c 21 f8             	andq	%r15, %rax
ffffffff800d7b16: 48 3d b0 00 00 00    	cmpq	$0xb0, %rax
ffffffff800d7b1c: 0f 82 d5 02 00 00    	jb	0xffffffff800d7df7 <memory__Slab__sfree+0x347>
ffffffff800d7b22: 49 8b 7e 08          	movq	0x8(%r14), %rdi
ffffffff800d7b26: 48 85 ff             	testq	%rdi, %rdi
ffffffff800d7b29: 0f 84 c8 02 00 00    	je	0xffffffff800d7df7 <memory__Slab__sfree+0x347>
ffffffff800d7b2f: 48 05 50 ff ff ff    	addq	$-0xb0, %rax
ffffffff800d7b35: 48 89 c1             	movq	%rax, %rcx
ffffffff800d7b38: 48 09 f9             	orq	%rdi, %rcx
ffffffff800d7b3b: 48 c1 e9 20          	shrq	$0x20, %rcx
ffffffff800d7b3f: 74 0f                	je	0xffffffff800d7b50 <memory__Slab__sfree+0xa0>
ffffffff800d7b41: 31 d2                	xorl	%edx, %edx
ffffffff800d7b43: 48 f7 f7             	divq	%rdi
ffffffff800d7b46: 48 85 d2             	testq	%rdx, %rdx
ffffffff800d7b49: 74 12                	je	0xffffffff800d7b5d <memory__Slab__sfree+0xad>
ffffffff800d7b4b: e9 bd 02 00 00       	jmp	0xffffffff800d7e0d <memory__Slab__sfree+0x35d>
ffffffff800d7b50: 31 d2                	xorl	%edx, %edx
ffffffff800d7b52: f7 f7                	divl	%edi
ffffffff800d7b54: 48 85 d2             	testq	%rdx, %rdx
ffffffff800d7b57: 0f 85 b0 02 00 00    	jne	0xffffffff800d7e0d <memory__Slab__sfree+0x35d>
ffffffff800d7b5d: 48 8b 53 20          	movq	0x20(%rbx), %rdx
ffffffff800d7b61: 48 39 d0             	cmpq	%rdx, %rax
ffffffff800d7b64: 0f 83 a3 02 00 00    	jae	0xffffffff800d7e0d <memory__Slab__sfree+0x35d>
ffffffff800d7b6a: 48 89 c6             	movq	%rax, %rsi
ffffffff800d7b6d: 48 c1 ee 06          	shrq	$0x6, %rsi
ffffffff800d7b71: 41 b8 01 00 00 00    	movl	$0x1, %r8d
ffffffff800d7b77: 89 c1                	movl	%eax, %ecx
ffffffff800d7b79: 49 d3 e0             	shlq	%cl, %r8
ffffffff800d7b7c: 48 3d 00 04 00 00    	cmpq	$0x400, %rax            # imm = 0x400
ffffffff800d7b82: 0f 83 b6 02 00 00    	jae	0xffffffff800d7e3e <memory__Slab__sfree+0x38e>
ffffffff800d7b88: 48 8b 4c f3 30       	movq	0x30(%rbx,%rsi,8), %rcx
ffffffff800d7b8d: 4c 85 c1             	testq	%r8, %rcx
ffffffff800d7b90: 0f 84 8d 02 00 00    	je	0xffffffff800d7e23 <memory__Slab__sfree+0x373>
ffffffff800d7b96: 48 8b 43 28          	movq	0x28(%rbx), %rax
ffffffff800d7b9a: 48 85 c0             	testq	%rax, %rax
ffffffff800d7b9d: 0f 84 80 02 00 00    	je	0xffffffff800d7e23 <memory__Slab__sfree+0x373>
ffffffff800d7ba3: 49 89 c1             	movq	%rax, %r9
ffffffff800d7ba6: 48 83 ff 08          	cmpq	$0x8, %rdi
ffffffff800d7baa: 0f 82 85 00 00 00    	jb	0xffffffff800d7c35 <memory__Slab__sfree+0x185>
ffffffff800d7bb0: 48 c1 ef 03          	shrq	$0x3, %rdi
ffffffff800d7bb4: 48 b9 aa aa aa aa aa aa aa aa	movabsq	$-0x5555555555555556, %rcx # imm = 0xAAAAAAAAAAAAAAAA
ffffffff800d7bbe: 4c 8d 57 ff          	leaq	-0x1(%rdi), %r10
ffffffff800d7bc2: 41 89 f9             	movl	%edi, %r9d
ffffffff800d7bc5: 41 83 e1 07          	andl	$0x7, %r9d
ffffffff800d7bc9: 49 83 fa 07          	cmpq	$0x7, %r10
ffffffff800d7bcd: 73 05                	jae	0xffffffff800d7bd4 <memory__Slab__sfree+0x124>
ffffffff800d7bcf: 45 31 d2             	xorl	%r10d, %r10d
ffffffff800d7bd2: eb 3c                	jmp	0xffffffff800d7c10 <memory__Slab__sfree+0x160>
ffffffff800d7bd4: 48 83 e7 f8          	andq	$-0x8, %rdi
ffffffff800d7bd8: 45 31 d2             	xorl	%r10d, %r10d
ffffffff800d7bdb: 0f 1f 44 00 00       	nopl	(%rax,%rax)
ffffffff800d7be0: 4b 89 0c d7          	movq	%rcx, (%r15,%r10,8)
ffffffff800d7be4: 4b 89 4c d7 08       	movq	%rcx, 0x8(%r15,%r10,8)
ffffffff800d7be9: 4b 89 4c d7 10       	movq	%rcx, 0x10(%r15,%r10,8)
ffffffff800d7bee: 4b 89 4c d7 18       	movq	%rcx, 0x18(%r15,%r10,8)
ffffffff800d7bf3: 4b 89 4c d7 20       	movq	%rcx, 0x20(%r15,%r10,8)
ffffffff800d7bf8: 4b 89 4c d7 28       	movq	%rcx, 0x28(%r15,%r10,8)
ffffffff800d7bfd: 4b 89 4c d7 30       	movq	%rcx, 0x30(%r15,%r10,8)
ffffffff800d7c02: 4b 89 4c d7 38       	movq	%rcx, 0x38(%r15,%r10,8)
ffffffff800d7c07: 49 83 c2 08          	addq	$0x8, %r10
ffffffff800d7c0b: 4c 39 d7             	cmpq	%r10, %rdi
ffffffff800d7c0e: 75 d0                	jne	0xffffffff800d7be0 <memory__Slab__sfree+0x130>
ffffffff800d7c10: 4d 85 c9             	testq	%r9, %r9
ffffffff800d7c13: 74 17                	je	0xffffffff800d7c2c <memory__Slab__sfree+0x17c>
ffffffff800d7c15: 4b 8d 3c d7          	leaq	(%r15,%r10,8), %rdi
ffffffff800d7c19: 45 31 d2             	xorl	%r10d, %r10d
ffffffff800d7c1c: 0f 1f 40 00          	nopl	(%rax)
ffffffff800d7c20: 4a 89 0c d7          	movq	%rcx, (%rdi,%r10,8)
ffffffff800d7c24: 49 ff c2             	incq	%r10
ffffffff800d7c27: 4d 39 d1             	cmpq	%r10, %r9
ffffffff800d7c2a: 75 f4                	jne	0xffffffff800d7c20 <memory__Slab__sfree+0x170>
ffffffff800d7c2c: 48 8b 4c f3 30       	movq	0x30(%rbx,%rsi,8), %rcx
ffffffff800d7c31: 4c 8b 4b 28          	movq	0x28(%rbx), %r9
ffffffff800d7c35: 49 f7 d0             	notq	%r8
ffffffff800d7c38: 49 21 c8             	andq	%rcx, %r8
ffffffff800d7c3b: 4c 89 44 f3 30       	movq	%r8, 0x30(%rbx,%rsi,8)
ffffffff800d7c40: 49 ff c9             	decq	%r9
ffffffff800d7c43: 4c 89 4b 28          	movq	%r9, 0x28(%rbx)
ffffffff800d7c47: 49 ff 4e 28          	decq	0x28(%r14)
ffffffff800d7c4b: 48 83 7b 28 00       	cmpq	$0x0, 0x28(%rbx)
ffffffff800d7c50: 74 24                	je	0xffffffff800d7c76 <memory__Slab__sfree+0x1c6>
ffffffff800d7c52: 48 39 d0             	cmpq	%rdx, %rax
ffffffff800d7c55: 75 6f                	jne	0xffffffff800d7cc6 <memory__Slab__sfree+0x216>
ffffffff800d7c57: 48 c7 43 10 00 00 00 00      	movq	$0x0, 0x10(%rbx)
ffffffff800d7c5f: 49 8b 46 10          	movq	0x10(%r14), %rax
ffffffff800d7c63: 48 89 43 18          	movq	%rax, 0x18(%rbx)
ffffffff800d7c67: 48 85 c0             	testq	%rax, %rax
ffffffff800d7c6a: 74 04                	je	0xffffffff800d7c70 <memory__Slab__sfree+0x1c0>
ffffffff800d7c6c: 48 89 58 10          	movq	%rbx, 0x10(%rax)
ffffffff800d7c70: 49 89 5e 10          	movq	%rbx, 0x10(%r14)
ffffffff800d7c74: eb 50                	jmp	0xffffffff800d7cc6 <memory__Slab__sfree+0x216>
ffffffff800d7c76: 48 39 d0             	cmpq	%rdx, %rax
ffffffff800d7c79: 74 32                	je	0xffffffff800d7cad <memory__Slab__sfree+0x1fd>
ffffffff800d7c7b: 48 8b 4b 10          	movq	0x10(%rbx), %rcx
ffffffff800d7c7f: 48 85 c9             	testq	%rcx, %rcx
ffffffff800d7c82: 0f 84 59 01 00 00    	je	0xffffffff800d7de1 <memory__Slab__sfree+0x331>
ffffffff800d7c88: 48 8b 43 18          	movq	0x18(%rbx), %rax
ffffffff800d7c8c: 48 89 41 18          	movq	%rax, 0x18(%rcx)
ffffffff800d7c90: 48 85 c0             	testq	%rax, %rax
ffffffff800d7c93: 74 08                	je	0xffffffff800d7c9d <memory__Slab__sfree+0x1ed>
ffffffff800d7c95: 48 8b 4b 10          	movq	0x10(%rbx), %rcx
ffffffff800d7c99: 48 89 48 10          	movq	%rcx, 0x10(%rax)
ffffffff800d7c9d: 48 c7 43 10 00 00 00 00      	movq	$0x0, 0x10(%rbx)
ffffffff800d7ca5: 48 c7 43 18 00 00 00 00      	movq	$0x0, 0x18(%rbx)
ffffffff800d7cad: 49 83 7e 18 00       	cmpq	$0x0, 0x18(%r14)
ffffffff800d7cb2: 74 0e                	je	0xffffffff800d7cc2 <memory__Slab__sfree+0x212>
ffffffff800d7cb4: 48 c7 43 08 00 00 00 00      	movq	$0x0, 0x8(%rbx)
ffffffff800d7cbc: 49 ff 4e 30          	decq	0x30(%r14)
ffffffff800d7cc0: eb 06                	jmp	0xffffffff800d7cc8 <memory__Slab__sfree+0x218>
ffffffff800d7cc2: 49 89 5e 18          	movq	%rbx, 0x18(%r14)
ffffffff800d7cc6: 31 db                	xorl	%ebx, %ebx
ffffffff800d7cc8: 41 0f b6 46 01       	movzbl	0x1(%r14), %eax
ffffffff800d7ccd: 31 c9                	xorl	%ecx, %ecx
ffffffff800d7ccf: f0                   	lock
ffffffff800d7cd0: 41 86 0e             	xchgb	%cl, (%r14)
ffffffff800d7cd3: 48 c7 85 50 ff ff ff 00 00 00 00     	movq	$0x0, -0xb0(%rbp)
ffffffff800d7cde: 9c                   	pushfq
ffffffff800d7cdf: 8f 85 50 ff ff ff    	popq	-0xb0(%rbp)
ffffffff800d7ce5: 84 c0                	testb	%al, %al
ffffffff800d7ce7: 74 0b                	je	0xffffffff800d7cf4 <memory__Slab__sfree+0x244>
ffffffff800d7ce9: fb                   	sti
ffffffff800d7cea: 48 85 db             	testq	%rbx, %rbx
ffffffff800d7ced: 75 0f                	jne	0xffffffff800d7cfe <memory__Slab__sfree+0x24e>
ffffffff800d7cef: e9 ce 00 00 00       	jmp	0xffffffff800d7dc2 <memory__Slab__sfree+0x312>
ffffffff800d7cf4: fa                   	cli
ffffffff800d7cf5: 48 85 db             	testq	%rbx, %rbx
ffffffff800d7cf8: 0f 84 c4 00 00 00    	je	0xffffffff800d7dc2 <memory__Slab__sfree+0x312>
ffffffff800d7cfe: 48 83 7b 20 00       	cmpq	$0x0, 0x20(%rbx)
ffffffff800d7d03: 0f 84 a5 00 00 00    	je	0xffffffff800d7dae <memory__Slab__sfree+0x2fe>
ffffffff800d7d09: 4d 8b 76 08          	movq	0x8(%r14), %r14
ffffffff800d7d0d: 49 bf aa aa aa aa aa aa aa aa	movabsq	$-0x5555555555555556, %r15 # imm = 0xAAAAAAAAAAAAAAAA
ffffffff800d7d17: 4c 8d ab b0 00 00 00 	leaq	0xb0(%rbx), %r13
ffffffff800d7d1e: 4c 89 f7             	movq	%r14, %rdi
ffffffff800d7d21: 48 c1 ef 03          	shrq	$0x3, %rdi
ffffffff800d7d25: 45 31 e4             	xorl	%r12d, %r12d
ffffffff800d7d28: 48 89 bd 30 ff ff ff 	movq	%rdi, -0xd0(%rbp)
ffffffff800d7d2f: eb 18                	jmp	0xffffffff800d7d49 <memory__Slab__sfree+0x299>
ffffffff800d7d31: 66 66 66 66 66 66 2e 0f 1f 84 00 00 00 00 00 	nopw	%cs:(%rax,%rax)
ffffffff800d7d40: 49 ff c4             	incq	%r12
ffffffff800d7d43: 4c 3b 63 20          	cmpq	0x20(%rbx), %r12
ffffffff800d7d47: 73 65                	jae	0xffffffff800d7dae <memory__Slab__sfree+0x2fe>
ffffffff800d7d49: 49 83 fe 08          	cmpq	$0x8, %r14
ffffffff800d7d4d: 72 f1                	jb	0xffffffff800d7d40 <memory__Slab__sfree+0x290>
ffffffff800d7d4f: 4c 89 e2             	movq	%r12, %rdx
ffffffff800d7d52: 49 0f af d6          	imulq	%r14, %rdx
ffffffff800d7d56: 4c 01 ea             	addq	%r13, %rdx
ffffffff800d7d59: 48 89 f8             	movq	%rdi, %rax
ffffffff800d7d5c: 45 31 c0             	xorl	%r8d, %r8d
ffffffff800d7d5f: 90                   	nop
ffffffff800d7d60: 4a 8b 0c 02          	movq	(%rdx,%r8), %rcx
ffffffff800d7d64: 4c 39 f9             	cmpq	%r15, %rcx
ffffffff800d7d67: 75 17                	jne	0xffffffff800d7d80 <memory__Slab__sfree+0x2d0>
ffffffff800d7d69: 49 83 c0 08          	addq	$0x8, %r8
ffffffff800d7d6d: 48 ff c8             	decq	%rax
ffffffff800d7d70: 75 ee                	jne	0xffffffff800d7d60 <memory__Slab__sfree+0x2b0>
ffffffff800d7d72: eb cc                	jmp	0xffffffff800d7d40 <memory__Slab__sfree+0x290>
ffffffff800d7d74: 66 66 66 2e 0f 1f 84 00 00 00 00 00  	nopw	%cs:(%rax,%rax)
ffffffff800d7d80: b8 01 00 00 00       	movl	$0x1, %eax
ffffffff800d7d85: f0                   	lock
ffffffff800d7d86: 48 0f c1 05 02 fb 23 00      	xaddq	%rax, 0x23fb02(%rip) # 0xffffffff80317890 <memory__slab_written_after_free>
ffffffff800d7d8e: 48 83 f8 1f          	cmpq	$0x1f, %rax
ffffffff800d7d92: 77 ac                	ja	0xffffffff800d7d40 <memory__Slab__sfree+0x290>
ffffffff800d7d94: 48 c7 c7 ae 93 17 80 	movq	$-0x7fe86c52, %rdi      # imm = 0x801793AE
ffffffff800d7d9b: 4c 89 f6             	movq	%r14, %rsi
ffffffff800d7d9e: 31 c0                	xorl	%eax, %eax
ffffffff800d7da0: e8 cb 5b 07 00       	callq	0xffffffff8014d970 <kprintf>
ffffffff800d7da5: 48 8b bd 30 ff ff ff 	movq	-0xd0(%rbp), %rdi
ffffffff800d7dac: eb 92                	jmp	0xffffffff800d7d40 <memory__Slab__sfree+0x290>
ffffffff800d7dae: 48 2b 1d c3 ad 0c 00 	subq	0xcadc3(%rip), %rbx     # 0xffffffff801a2b78 <memory__higher_half>
ffffffff800d7db5: be 01 00 00 00       	movl	$0x1, %esi
ffffffff800d7dba: 48 89 df             	movq	%rbx, %rdi
ffffffff800d7dbd: e8 6e 3b f5 ff       	callq	0xffffffff8002b930 <memory__pmm_free>
ffffffff800d7dc2: 48 8b 05 0f 95 0b 00 	movq	0xb950f(%rip), %rax     # 0xffffffff801912d8 <__stack_chk_guard>
ffffffff800d7dc9: 48 3b 45 d0          	cmpq	-0x30(%rbp), %rax
ffffffff800d7dcd: 75 6a                	jne	0xffffffff800d7e39 <memory__Slab__sfree+0x389>
ffffffff800d7dcf: 48 81 c4 a8 00 00 00 	addq	$0xa8, %rsp
ffffffff800d7dd6: 5b                   	popq	%rbx
ffffffff800d7dd7: 41 5c                	popq	%r12
ffffffff800d7dd9: 41 5d                	popq	%r13
ffffffff800d7ddb: 41 5e                	popq	%r14
ffffffff800d7ddd: 41 5f                	popq	%r15
ffffffff800d7ddf: 5d                   	popq	%rbp
ffffffff800d7de0: c3                   	retq
ffffffff800d7de1: 48 8b 43 18          	movq	0x18(%rbx), %rax
ffffffff800d7de5: 49 89 46 10          	movq	%rax, 0x10(%r14)
ffffffff800d7de9: 48 85 c0             	testq	%rax, %rax
ffffffff800d7dec: 0f 85 a3 fe ff ff    	jne	0xffffffff800d7c95 <memory__Slab__sfree+0x1e5>
ffffffff800d7df2: e9 a6 fe ff ff       	jmp	0xffffffff800d7c9d <memory__Slab__sfree+0x1ed>
ffffffff800d7df7: 4c 89 f7             	movq	%r14, %rdi
ffffffff800d7dfa: e8 b1 45 f5 ff       	callq	0xffffffff8002c3b0 <klock__Lock__release>
ffffffff800d7dff: 31 ff                	xorl	%edi, %edi
ffffffff800d7e01: 48 c7 c6 26 8c 17 80 	movq	$-0x7fe873da, %rsi      # imm = 0x80178C26
ffffffff800d7e08: e8 53 5f ff ff       	callq	0xffffffff800cdd60 <lib__kpanic>
ffffffff800d7e0d: 4c 89 f7             	movq	%r14, %rdi
ffffffff800d7e10: e8 9b 45 f5 ff       	callq	0xffffffff8002c3b0 <klock__Lock__release>
ffffffff800d7e15: 31 ff                	xorl	%edi, %edi
ffffffff800d7e17: 48 c7 c6 f3 ce 17 80 	movq	$-0x7fe8310d, %rsi      # imm = 0x8017CEF3
ffffffff800d7e1e: e8 3d 5f ff ff       	callq	0xffffffff800cdd60 <lib__kpanic>
ffffffff800d7e23: 4c 89 f7             	movq	%r14, %rdi
ffffffff800d7e26: e8 85 45 f5 ff       	callq	0xffffffff8002c3b0 <klock__Lock__release>
ffffffff800d7e2b: 31 ff                	xorl	%edi, %edi
ffffffff800d7e2d: 48 c7 c6 9c 93 17 80 	movq	$-0x7fe86c64, %rsi      # imm = 0x8017939C
ffffffff800d7e34: e8 27 5f ff ff       	callq	0xffffffff800cdd60 <lib__kpanic>
ffffffff800d7e39: e8 02 5e 07 00       	callq	0xffffffff8014dc40 <__stack_chk_fail>
ffffffff800d7e3e: 48 8b 05 cb ef 0a 00 	movq	0xaefcb(%rip), %rax     # 0xffffffff80186e10 <_str_186+0x10>
ffffffff800d7e45: 48 89 85 60 ff ff ff 	movq	%rax, -0xa0(%rbp)
ffffffff800d7e4c: 48 8b 05 b5 ef 0a 00 	movq	0xaefb5(%rip), %rax     # 0xffffffff80186e08 <_str_186+0x8>
ffffffff800d7e53: 48 89 85 58 ff ff ff 	movq	%rax, -0xa8(%rbp)
ffffffff800d7e5a: 48 8b 05 9f ef 0a 00 	movq	0xaef9f(%rip), %rax     # 0xffffffff80186e00 <_str_186>
ffffffff800d7e61: 48 89 85 50 ff ff ff 	movq	%rax, -0xb0(%rbp)
ffffffff800d7e68: 48 8d bd 68 ff ff ff 	leaq	-0x98(%rbp), %rdi
ffffffff800d7e6f: e8 0c 68 f5 ff       	callq	0xffffffff8002e680 <impl_i64_to_string>
ffffffff800d7e74: 48 8b 05 ad ef 0a 00 	movq	0xaefad(%rip), %rax     # 0xffffffff80186e28 <_str_187+0x10>
ffffffff800d7e7b: 48 89 45 90          	movq	%rax, -0x70(%rbp)
ffffffff800d7e7f: 48 8b 05 9a ef 0a 00 	movq	0xaef9a(%rip), %rax     # 0xffffffff80186e20 <_str_187+0x8>
ffffffff800d7e86: 48 89 45 88          	movq	%rax, -0x78(%rbp)
ffffffff800d7e8a: 48 8b 05 87 ef 0a 00 	movq	0xaef87(%rip), %rax     # 0xffffffff80186e18 <_str_187>
ffffffff800d7e91: 48 89 45 80          	movq	%rax, -0x80(%rbp)
ffffffff800d7e95: 48 8d 7d 98          	leaq	-0x68(%rbp), %rdi
ffffffff800d7e99: be 10 00 00 00       	movl	$0x10, %esi
ffffffff800d7e9e: e8 dd 67 f5 ff       	callq	0xffffffff8002e680 <impl_i64_to_string>
ffffffff800d7ea3: 48 8b 05 6e bd 0a 00 	movq	0xabd6e(%rip), %rax     # 0xffffffff80183c18 <_str_23+0x10>
ffffffff800d7eaa: 48 89 45 c0          	movq	%rax, -0x40(%rbp)
ffffffff800d7eae: 48 8b 05 5b bd 0a 00 	movq	0xabd5b(%rip), %rax     # 0xffffffff80183c10 <_str_23+0x8>
ffffffff800d7eb5: 48 89 45 b8          	movq	%rax, -0x48(%rbp)
ffffffff800d7eb9: 48 8b 05 48 bd 0a 00 	movq	0xabd48(%rip), %rax     # 0xffffffff80183c08 <_str_23>
ffffffff800d7ec0: 48 89 45 b0          	movq	%rax, -0x50(%rbp)
ffffffff800d7ec4: 48 8d bd 38 ff ff ff 	leaq	-0xc8(%rbp), %rdi
ffffffff800d7ecb: 48 8d 95 50 ff ff ff 	leaq	-0xb0(%rbp), %rdx
ffffffff800d7ed2: be 05 00 00 00       	movl	$0x5, %esi
ffffffff800d7ed7: e8 64 b7 f4 ff       	callq	0xffffffff80023640 <string_plus_many>
ffffffff800d7edc: 48 83 ec 08          	subq	$0x8, %rsp
ffffffff800d7ee0: 48 8b 85 48 ff ff ff 	movq	-0xb8(%rbp), %rax
ffffffff800d7ee7: 48 8b 8d 38 ff ff ff 	movq	-0xc8(%rbp), %rcx
ffffffff800d7eee: 48 8b 95 40 ff ff ff 	movq	-0xc0(%rbp), %rdx
ffffffff800d7ef5: 50                   	pushq	%rax
ffffffff800d7ef6: 52                   	pushq	%rdx
ffffffff800d7ef7: 51                   	pushq	%rcx
ffffffff800d7ef8: e8 03 81 f2 ff       	callq	0xffffffff80000000 <v_panic>
ffffffff800d7efd: cc                   	int3
ffffffff800d7efe: cc                   	int3
ffffffff800d7eff: cc                   	int3

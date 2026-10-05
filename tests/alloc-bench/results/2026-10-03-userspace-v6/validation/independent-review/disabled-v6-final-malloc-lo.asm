
/Users/alex/code/vinix/third_party/useralloc-libc/build/useralloc/v6-prototype/cache/x86_64/e2aafe45791c748b1a101bcb8e017566e835e6f27fd623513503e67ee426bd6e/objects/obj/src/malloc/mallocng/malloc.lo:     file format elf64-x86-64


Disassembly of section .text.__malloc_atfork:

0000000000000000 <__malloc_atfork>:
   0:	85 ff                	test   %edi,%edi
   2:	78 0d                	js     11 <__malloc_atfork+0x11>
   4:	74 23                	je     29 <__malloc_atfork+0x29>
   6:	c7 05 00 00 00 00 00 	movl   $0x0,0x0(%rip)        # 10 <__malloc_atfork+0x10>
   d:	00 00 00 
			8: R_X86_64_PC32	__malloc_lock-0x8
  10:	c3                   	ret
  11:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 18 <__malloc_atfork+0x18>
			14: R_X86_64_PC32	__libc-0x1
  18:	84 c0                	test   %al,%al
  1a:	75 01                	jne    1d <__malloc_atfork+0x1d>
  1c:	c3                   	ret
  1d:	48 8d 3d 00 00 00 00 	lea    0x0(%rip),%rdi        # 24 <__malloc_atfork+0x24>
			20: R_X86_64_PC32	__malloc_lock-0x4
  24:	e9 00 00 00 00       	jmp    29 <__malloc_atfork+0x29>
			25: R_X86_64_PLT32	__lock-0x4
  29:	8b 05 00 00 00 00    	mov    0x0(%rip),%eax        # 2f <__malloc_atfork+0x2f>
			2b: R_X86_64_PC32	__malloc_lock-0x4
  2f:	85 c0                	test   %eax,%eax
  31:	79 e9                	jns    1c <__malloc_atfork+0x1c>
  33:	48 8d 3d 00 00 00 00 	lea    0x0(%rip),%rdi        # 3a <__malloc_atfork+0x3a>
			36: R_X86_64_PC32	__malloc_lock-0x4
  3a:	e9 00 00 00 00       	jmp    3f <__malloc_atfork+0x3f>
			3b: R_X86_64_PLT32	__unlock-0x4

Disassembly of section .text.__malloc_alloc_meta:

0000000000000000 <__malloc_alloc_meta>:
   0:	41 54                	push   %r12
   2:	55                   	push   %rbp
   3:	53                   	push   %rbx
   4:	48 83 ec 10          	sub    $0x10,%rsp
   8:	64 48 8b 04 25 28 00 	mov    %fs:0x28,%rax
   f:	00 00 
  11:	48 89 44 24 08       	mov    %rax,0x8(%rsp)
  16:	31 c0                	xor    %eax,%eax
  18:	8b 05 00 00 00 00    	mov    0x0(%rip),%eax        # 1e <__malloc_alloc_meta+0x1e>
			1a: R_X86_64_PC32	__malloc_context+0x4
  1e:	85 c0                	test   %eax,%eax
  20:	74 5e                	je     80 <__malloc_alloc_meta+0x80>
  22:	48 8b 1d 00 00 00 00 	mov    0x0(%rip),%rbx        # 29 <__malloc_alloc_meta+0x29>
			25: R_X86_64_PC32	__malloc_context+0xc
  29:	48 85 db             	test   %rbx,%rbx
  2c:	0f 84 ba 00 00 00    	je     ec <__malloc_alloc_meta+0xec>
  32:	48 8b 43 08          	mov    0x8(%rbx),%rax
  36:	48 39 c3             	cmp    %rax,%rbx
  39:	0f 84 e0 02 00 00    	je     31f <__malloc_alloc_meta+0x31f>
  3f:	48 8b 13             	mov    (%rbx),%rdx
  42:	48 89 42 08          	mov    %rax,0x8(%rdx)
  46:	48 8b 13             	mov    (%rbx),%rdx
  49:	48 89 10             	mov    %rdx,(%rax)
  4c:	48 3b 1d 00 00 00 00 	cmp    0x0(%rip),%rbx        # 53 <__malloc_alloc_meta+0x53>
			4f: R_X86_64_PC32	__malloc_context+0xc
  53:	0f 84 b6 02 00 00    	je     30f <__malloc_alloc_meta+0x30f>
  59:	66 0f ef c0          	pxor   %xmm0,%xmm0
  5d:	0f 11 03             	movups %xmm0,(%rbx)
  60:	48 8b 44 24 08       	mov    0x8(%rsp),%rax
  65:	64 48 2b 04 25 28 00 	sub    %fs:0x28,%rax
  6c:	00 00 
  6e:	0f 85 bb 02 00 00    	jne    32f <__malloc_alloc_meta+0x32f>
  74:	48 83 c4 10          	add    $0x10,%rsp
  78:	48 89 d8             	mov    %rbx,%rax
  7b:	5b                   	pop    %rbx
  7c:	5d                   	pop    %rbp
  7d:	41 5c                	pop    %r12
  7f:	c3                   	ret
  80:	48 69 c4 6d 4e c6 41 	imul   $0x41c64e6d,%rsp,%rax
  87:	48 8b 15 00 00 00 00 	mov    0x0(%rip),%rdx        # 8e <__malloc_alloc_meta+0x8e>
			8a: R_X86_64_PC32	__libc+0x4
  8e:	48 89 e5             	mov    %rsp,%rbp
  91:	31 db                	xor    %ebx,%ebx
  93:	48 89 04 24          	mov    %rax,(%rsp)
  97:	eb 0b                	jmp    a4 <__malloc_alloc_meta+0xa4>
  99:	0f 1f 80 00 00 00 00 	nopl   0x0(%rax)
  a0:	48 83 c3 10          	add    $0x10,%rbx
  a4:	48 8b 04 1a          	mov    (%rdx,%rbx,1),%rax
  a8:	48 85 c0             	test   %rax,%rax
  ab:	74 25                	je     d2 <__malloc_alloc_meta+0xd2>
  ad:	48 83 f8 19          	cmp    $0x19,%rax
  b1:	75 ed                	jne    a0 <__malloc_alloc_meta+0xa0>
  b3:	48 8b 74 1a 08       	mov    0x8(%rdx,%rbx,1),%rsi
  b8:	48 89 ef             	mov    %rbp,%rdi
  bb:	ba 08 00 00 00       	mov    $0x8,%edx
  c0:	48 83 c6 08          	add    $0x8,%rsi
  c4:	e8 00 00 00 00       	call   c9 <__malloc_alloc_meta+0xc9>
			c5: R_X86_64_PLT32	memcpy-0x4
  c9:	48 8b 15 00 00 00 00 	mov    0x0(%rip),%rdx        # d0 <__malloc_alloc_meta+0xd0>
			cc: R_X86_64_PC32	__libc+0x4
  d0:	eb ce                	jmp    a0 <__malloc_alloc_meta+0xa0>
  d2:	c7 05 00 00 00 00 01 	movl   $0x1,0x0(%rip)        # dc <__malloc_alloc_meta+0xdc>
  d9:	00 00 00 
			d4: R_X86_64_PC32	__malloc_context
  dc:	48 8b 04 24          	mov    (%rsp),%rax
  e0:	48 89 05 00 00 00 00 	mov    %rax,0x0(%rip)        # e7 <__malloc_alloc_meta+0xe7>
			e3: R_X86_64_PC32	__malloc_context-0x4
  e7:	e9 36 ff ff ff       	jmp    22 <__malloc_alloc_meta+0x22>
  ec:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # f3 <__malloc_alloc_meta+0xf3>
			ef: R_X86_64_PC32	__malloc_context+0x1c
  f3:	48 85 c0             	test   %rax,%rax
  f6:	74 29                	je     121 <__malloc_alloc_meta+0x121>
  f8:	48 8b 1d 00 00 00 00 	mov    0x0(%rip),%rbx        # ff <__malloc_alloc_meta+0xff>
			fb: R_X86_64_PC32	__malloc_context+0x14
  ff:	48 83 e8 01          	sub    $0x1,%rax
 103:	48 89 05 00 00 00 00 	mov    %rax,0x0(%rip)        # 10a <__malloc_alloc_meta+0x10a>
			106: R_X86_64_PC32	__malloc_context+0x1c
 10a:	66 0f ef c0          	pxor   %xmm0,%xmm0
 10e:	48 8d 43 28          	lea    0x28(%rbx),%rax
 112:	48 89 05 00 00 00 00 	mov    %rax,0x0(%rip)        # 119 <__malloc_alloc_meta+0x119>
			115: R_X86_64_PC32	__malloc_context+0x14
 119:	0f 11 03             	movups %xmm0,(%rbx)
 11c:	e9 3f ff ff ff       	jmp    60 <__malloc_alloc_meta+0x60>
 121:	4c 8b 25 00 00 00 00 	mov    0x0(%rip),%r12        # 128 <__malloc_alloc_meta+0x128>
			124: R_X86_64_PC32	__malloc_context+0x24
 128:	4d 85 e4             	test   %r12,%r12
 12b:	74 41                	je     16e <__malloc_alloc_meta+0x16e>
 12d:	48 8b 2d 00 00 00 00 	mov    0x0(%rip),%rbp        # 134 <__malloc_alloc_meta+0x134>
			130: R_X86_64_PC32	__malloc_context+0x44
 134:	49 83 ec 01          	sub    $0x1,%r12
 138:	f7 c5 ff 0f 00 00    	test   $0xfff,%ebp
 13e:	0f 85 df 00 00 00    	jne    223 <__malloc_alloc_meta+0x223>
 144:	ba 03 00 00 00       	mov    $0x3,%edx
 149:	be 00 10 00 00       	mov    $0x1000,%esi
 14e:	48 89 ef             	mov    %rbp,%rdi
 151:	e8 00 00 00 00       	call   156 <__malloc_alloc_meta+0x156>
			152: R_X86_64_PLT32	mprotect-0x4
 156:	85 c0                	test   %eax,%eax
 158:	0f 85 92 01 00 00    	jne    2f0 <__malloc_alloc_meta+0x2f0>
 15e:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 165 <__malloc_alloc_meta+0x165>
			161: R_X86_64_PC32	__malloc_context+0x24
 165:	4c 8d 60 ff          	lea    -0x1(%rax),%r12
 169:	e9 b5 00 00 00       	jmp    223 <__malloc_alloc_meta+0x223>
 16e:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 175 <__malloc_alloc_meta+0x175>
			171: R_X86_64_PC32	__malloc_context+0x3bc
 175:	48 83 f8 ff          	cmp    $0xffffffffffffffff,%rax
 179:	74 3e                	je     1b9 <__malloc_alloc_meta+0x1b9>
 17b:	48 85 c0             	test   %rax,%rax
 17e:	0f 84 fd 00 00 00    	je     281 <__malloc_alloc_meta+0x281>
 184:	48 8d b8 00 10 00 00 	lea    0x1000(%rax),%rdi
 18b:	b8 0c 00 00 00       	mov    $0xc,%eax
 190:	0f 05                	syscall
 192:	48 89 c5             	mov    %rax,%rbp
 195:	48 39 c7             	cmp    %rax,%rdi
 198:	0f 84 3f 01 00 00    	je     2dd <__malloc_alloc_meta+0x2dd>
 19e:	4c 8b 25 00 00 00 00 	mov    0x0(%rip),%r12        # 1a5 <__malloc_alloc_meta+0x1a5>
			1a1: R_X86_64_PC32	__malloc_context+0x24
 1a5:	48 c7 05 00 00 00 00 	movq   $0xffffffffffffffff,0x0(%rip)        # 1b0 <__malloc_alloc_meta+0x1b0>
 1ac:	ff ff ff ff 
			1a8: R_X86_64_PC32	__malloc_context+0x3b8
 1b0:	4d 85 e4             	test   %r12,%r12
 1b3:	0f 85 74 ff ff ff    	jne    12d <__malloc_alloc_meta+0x12d>
 1b9:	48 8b 0d 00 00 00 00 	mov    0x0(%rip),%rcx        # 1c0 <__malloc_alloc_meta+0x1c0>
			1bc: R_X86_64_PC32	__malloc_context+0x2c
 1c0:	45 31 c9             	xor    %r9d,%r9d
 1c3:	31 d2                	xor    %edx,%edx
 1c5:	31 ff                	xor    %edi,%edi
 1c7:	41 bc 02 00 00 00    	mov    $0x2,%r12d
 1cd:	41 b8 ff ff ff ff    	mov    $0xffffffff,%r8d
 1d3:	49 d3 e4             	shl    %cl,%r12
 1d6:	b9 22 00 00 00       	mov    $0x22,%ecx
 1db:	4c 89 e6             	mov    %r12,%rsi
 1de:	48 c1 e6 0c          	shl    $0xc,%rsi
 1e2:	e8 00 00 00 00       	call   1e7 <__malloc_alloc_meta+0x1e7>
			1e3: R_X86_64_PLT32	__mmap-0x4
 1e7:	48 83 f8 ff          	cmp    $0xffffffffffffffff,%rax
 1eb:	0f 84 6f fe ff ff    	je     60 <__malloc_alloc_meta+0x60>
 1f1:	48 8d a8 00 10 00 00 	lea    0x1000(%rax),%rbp
 1f8:	49 8d 44 24 ff       	lea    -0x1(%r12),%rax
 1fd:	48 83 05 00 00 00 00 	addq   $0x1,0x0(%rip)        # 205 <__malloc_alloc_meta+0x205>
 204:	01 
			200: R_X86_64_PC32	__malloc_context+0x2b
 205:	48 89 2d 00 00 00 00 	mov    %rbp,0x0(%rip)        # 20c <__malloc_alloc_meta+0x20c>
			208: R_X86_64_PC32	__malloc_context+0x44
 20c:	48 89 05 00 00 00 00 	mov    %rax,0x0(%rip)        # 213 <__malloc_alloc_meta+0x213>
			20f: R_X86_64_PC32	__malloc_context+0x24
 213:	f7 c5 ff 0f 00 00    	test   $0xfff,%ebp
 219:	0f 84 25 ff ff ff    	je     144 <__malloc_alloc_meta+0x144>
 21f:	49 83 ec 02          	sub    $0x2,%r12
 223:	48 8d 85 00 10 00 00 	lea    0x1000(%rbp),%rax
 22a:	4c 89 25 00 00 00 00 	mov    %r12,0x0(%rip)        # 231 <__malloc_alloc_meta+0x231>
			22d: R_X86_64_PC32	__malloc_context+0x24
 231:	48 89 05 00 00 00 00 	mov    %rax,0x0(%rip)        # 238 <__malloc_alloc_meta+0x238>
			234: R_X86_64_PC32	__malloc_context+0x44
 238:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 23f <__malloc_alloc_meta+0x23f>
			23b: R_X86_64_PC32	__malloc_context+0x3c
 23f:	48 85 c0             	test   %rax,%rax
 242:	0f 84 bb 00 00 00    	je     303 <__malloc_alloc_meta+0x303>
 248:	48 89 68 08          	mov    %rbp,0x8(%rax)
 24c:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 253 <__malloc_alloc_meta+0x253>
			24f: R_X86_64_PC32	__malloc_context-0x4
 253:	48 89 2d 00 00 00 00 	mov    %rbp,0x0(%rip)        # 25a <__malloc_alloc_meta+0x25a>
			256: R_X86_64_PC32	__malloc_context+0x3c
 25a:	48 89 45 00          	mov    %rax,0x0(%rbp)
 25e:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 265 <__malloc_alloc_meta+0x265>
			261: R_X86_64_PC32	__malloc_context+0x3c
 265:	c7 40 10 65 00 00 00 	movl   $0x65,0x10(%rax)
 26c:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 273 <__malloc_alloc_meta+0x273>
			26f: R_X86_64_PC32	__malloc_context+0x3c
 273:	48 8d 58 18          	lea    0x18(%rax),%rbx
 277:	b8 64 00 00 00       	mov    $0x64,%eax
 27c:	e9 82 fe ff ff       	jmp    103 <__malloc_alloc_meta+0x103>
 281:	ba 0c 00 00 00       	mov    $0xc,%edx
 286:	4c 89 e7             	mov    %r12,%rdi
 289:	48 89 d0             	mov    %rdx,%rax
 28c:	0f 05                	syscall
 28e:	48 89 c5             	mov    %rax,%rbp
 291:	48 f7 dd             	neg    %rbp
 294:	81 e5 ff 0f 00 00    	and    $0xfff,%ebp
 29a:	48 01 c5             	add    %rax,%rbp
 29d:	48 89 d0             	mov    %rdx,%rax
 2a0:	48 89 2d 00 00 00 00 	mov    %rbp,0x0(%rip)        # 2a7 <__malloc_alloc_meta+0x2a7>
			2a3: R_X86_64_PC32	__malloc_context+0x3bc
 2a7:	48 81 c5 00 20 00 00 	add    $0x2000,%rbp
 2ae:	48 89 ef             	mov    %rbp,%rdi
 2b1:	0f 05                	syscall
 2b3:	48 39 c5             	cmp    %rax,%rbp
 2b6:	0f 85 e2 fe ff ff    	jne    19e <__malloc_alloc_meta+0x19e>
 2bc:	45 31 c9             	xor    %r9d,%r9d
 2bf:	41 b8 ff ff ff ff    	mov    $0xffffffff,%r8d
 2c5:	b9 32 00 00 00       	mov    $0x32,%ecx
 2ca:	31 d2                	xor    %edx,%edx
 2cc:	48 8b 3d 00 00 00 00 	mov    0x0(%rip),%rdi        # 2d3 <__malloc_alloc_meta+0x2d3>
			2cf: R_X86_64_PC32	__malloc_context+0x3bc
 2d3:	be 00 10 00 00       	mov    $0x1000,%esi
 2d8:	e8 00 00 00 00       	call   2dd <__malloc_alloc_meta+0x2dd>
			2d9: R_X86_64_PLT32	__mmap-0x4
 2dd:	48 89 2d 00 00 00 00 	mov    %rbp,0x0(%rip)        # 2e4 <__malloc_alloc_meta+0x2e4>
			2e0: R_X86_64_PC32	__malloc_context+0x3bc
 2e4:	48 81 ed 00 10 00 00 	sub    $0x1000,%rbp
 2eb:	e9 33 ff ff ff       	jmp    223 <__malloc_alloc_meta+0x223>
 2f0:	e8 00 00 00 00       	call   2f5 <__malloc_alloc_meta+0x2f5>
			2f1: R_X86_64_PLT32	___errno_location-0x4
 2f5:	83 38 26             	cmpl   $0x26,(%rax)
 2f8:	0f 84 60 fe ff ff    	je     15e <__malloc_alloc_meta+0x15e>
 2fe:	e9 5d fd ff ff       	jmp    60 <__malloc_alloc_meta+0x60>
 303:	48 89 2d 00 00 00 00 	mov    %rbp,0x0(%rip)        # 30a <__malloc_alloc_meta+0x30a>
			306: R_X86_64_PC32	__malloc_context+0x34
 30a:	e9 3d ff ff ff       	jmp    24c <__malloc_alloc_meta+0x24c>
 30f:	48 8b 43 08          	mov    0x8(%rbx),%rax
 313:	48 89 05 00 00 00 00 	mov    %rax,0x0(%rip)        # 31a <__malloc_alloc_meta+0x31a>
			316: R_X86_64_PC32	__malloc_context+0xc
 31a:	e9 3a fd ff ff       	jmp    59 <__malloc_alloc_meta+0x59>
 31f:	48 c7 05 00 00 00 00 	movq   $0x0,0x0(%rip)        # 32a <__malloc_alloc_meta+0x32a>
 326:	00 00 00 00 
			322: R_X86_64_PC32	__malloc_context+0x8
 32a:	e9 2a fd ff ff       	jmp    59 <__malloc_alloc_meta+0x59>
 32f:	e8 00 00 00 00       	call   334 <__malloc_alloc_meta+0x334>
			330: R_X86_64_PLT32	__stack_chk_fail-0x4

Disassembly of section .text.unlikely.alloc_slot:

0000000000000000 <alloc_slot.cold>:
   0:	0f 0b                	ud2

Disassembly of section .text.alloc_slot:

0000000000000000 <alloc_slot>:
   0:	41 57                	push   %r15
   2:	4c 8d 3d 00 00 00 00 	lea    0x0(%rip),%r15        # 9 <alloc_slot+0x9>
			5: R_X86_64_PC32	__malloc_context-0x4
   9:	41 56                	push   %r14
   b:	4c 63 f7             	movslq %edi,%r14
   e:	48 89 f7             	mov    %rsi,%rdi
  11:	41 55                	push   %r13
  13:	49 8d 46 0a          	lea    0xa(%r14),%rax
  17:	41 54                	push   %r12
  19:	4d 89 f4             	mov    %r14,%r12
  1c:	55                   	push   %rbp
  1d:	53                   	push   %rbx
  1e:	48 83 ec 38          	sub    $0x38,%rsp
  22:	49 8b 14 c7          	mov    (%r15,%rax,8),%rdx
  26:	48 85 d2             	test   %rdx,%rdx
  29:	74 4f                	je     7a <alloc_slot+0x7a>
  2b:	8b 4a 18             	mov    0x18(%rdx),%ecx
  2e:	85 c9                	test   %ecx,%ecx
  30:	0f 85 c6 01 00 00    	jne    1fc <alloc_slot+0x1fc>
  36:	8b 72 1c             	mov    0x1c(%rdx),%esi
  39:	48 8b 4a 08          	mov    0x8(%rdx),%rcx
  3d:	85 f6                	test   %esi,%esi
  3f:	0f 85 e8 00 00 00    	jne    12d <alloc_slot+0x12d>
  45:	48 39 ca             	cmp    %rcx,%rdx
  48:	0f 84 d2 00 00 00    	je     120 <alloc_slot+0x120>
  4e:	48 8b 32             	mov    (%rdx),%rsi
  51:	48 89 4e 08          	mov    %rcx,0x8(%rsi)
  55:	48 8b 32             	mov    (%rdx),%rsi
  58:	48 89 31             	mov    %rsi,(%rcx)
  5b:	49 3b 14 c7          	cmp    (%r15,%rax,8),%rdx
  5f:	0f 84 ae 00 00 00    	je     113 <alloc_slot+0x113>
  65:	66 0f ef c0          	pxor   %xmm0,%xmm0
  69:	0f 11 02             	movups %xmm0,(%rdx)
  6c:	4b 8b 54 f7 50       	mov    0x50(%r15,%r14,8),%rdx
  71:	48 85 d2             	test   %rdx,%rdx
  74:	0f 85 ba 00 00 00    	jne    134 <alloc_slot+0x134>
  7a:	48 8d 0d 00 00 00 00 	lea    0x0(%rip),%rcx        # 81 <alloc_slot+0x81>
			7d: R_X86_64_PC32	__malloc_size_classes-0x4
  81:	48 89 7c 24 08       	mov    %rdi,0x8(%rsp)
  86:	46 0f b7 2c 71       	movzwl (%rcx,%r14,2),%r13d
  8b:	e8 00 00 00 00       	call   90 <alloc_slot+0x90>
			8c: R_X86_64_PLT32	__malloc_alloc_meta-0x4
  90:	66 48 0f 6e c8       	movq   %rax,%xmm1
  95:	41 c1 e5 04          	shl    $0x4,%r13d
  99:	48 89 c5             	mov    %rax,%rbp
  9c:	66 0f 6c c9          	punpcklqdq %xmm1,%xmm1
  a0:	4d 63 ed             	movslq %r13d,%r13
  a3:	0f 29 4c 24 10       	movaps %xmm1,0x10(%rsp)
  a8:	48 85 c0             	test   %rax,%rax
  ab:	0f 84 05 07 00 00    	je     7b6 <alloc_slot+0x7b6>
  b1:	41 83 fc 08          	cmp    $0x8,%r12d
  b5:	4b 8b b4 f7 f8 01 00 	mov    0x1f8(%r15,%r14,8),%rsi
  bc:	00 
  bd:	48 8b 7c 24 08       	mov    0x8(%rsp),%rdi
  c2:	48 8d 0d 00 00 00 00 	lea    0x0(%rip),%rcx        # c9 <alloc_slot+0xc9>
			c5: R_X86_64_PC32	__malloc_size_classes-0x4
  c9:	0f 8f 07 02 00 00    	jg     2d6 <alloc_slot+0x2d6>
  cf:	4b 8d 14 76          	lea    (%r14,%r14,2),%rdx
  d3:	48 8d 05 00 00 00 00 	lea    0x0(%rip),%rax        # da <alloc_slot+0xda>
			d6: R_X86_64_PC32	.rodata.small_cnt_tab-0x4
  da:	48 01 d0             	add    %rdx,%rax
  dd:	0f b6 18             	movzbl (%rax),%ebx
  e0:	8d 14 9d 00 00 00 00 	lea    0x0(,%rbx,4),%edx
  e7:	48 63 d2             	movslq %edx,%rdx
  ea:	48 39 d6             	cmp    %rdx,%rsi
  ed:	0f 83 3e 02 00 00    	jae    331 <alloc_slot+0x331>
  f3:	0f b6 58 01          	movzbl 0x1(%rax),%ebx
  f7:	8d 14 9d 00 00 00 00 	lea    0x0(,%rbx,4),%edx
  fe:	48 63 d2             	movslq %edx,%rdx
 101:	48 39 d6             	cmp    %rdx,%rsi
 104:	0f 83 27 02 00 00    	jae    331 <alloc_slot+0x331>
 10a:	0f b6 58 02          	movzbl 0x2(%rax),%ebx
 10e:	e9 1e 02 00 00       	jmp    331 <alloc_slot+0x331>
 113:	48 8b 4a 08          	mov    0x8(%rdx),%rcx
 117:	49 89 0c c7          	mov    %rcx,(%r15,%rax,8)
 11b:	e9 45 ff ff ff       	jmp    65 <alloc_slot+0x65>
 120:	49 c7 04 c7 00 00 00 	movq   $0x0,(%r15,%rax,8)
 127:	00 
 128:	e9 38 ff ff ff       	jmp    65 <alloc_slot+0x65>
 12d:	49 89 0c c7          	mov    %rcx,(%r15,%rax,8)
 131:	48 89 ca             	mov    %rcx,%rdx
 134:	0f b6 4a 20          	movzbl 0x20(%rdx),%ecx
 138:	b8 02 00 00 00       	mov    $0x2,%eax
 13d:	44 8b 42 1c          	mov    0x1c(%rdx),%r8d
 141:	d3 e0                	shl    %cl,%eax
 143:	83 e8 01             	sub    $0x1,%eax
 146:	41 39 c0             	cmp    %eax,%r8d
 149:	0f 84 d3 00 00 00    	je     222 <alloc_slot+0x222>
 14f:	48 8b 72 10          	mov    0x10(%rdx),%rsi
 153:	b8 02 00 00 00       	mov    $0x2,%eax
 158:	0f b6 4e 08          	movzbl 0x8(%rsi),%ecx
 15c:	d3 e0                	shl    %cl,%eax
 15e:	41 89 ca             	mov    %ecx,%r10d
 161:	83 e8 01             	sub    $0x1,%eax
 164:	41 83 e2 1f          	and    $0x1f,%r10d
 168:	44 85 c0             	test   %r8d,%eax
 16b:	75 15                	jne    182 <alloc_slot+0x182>
 16d:	4c 8b 4a 08          	mov    0x8(%rdx),%r9
 171:	4c 39 ca             	cmp    %r9,%rdx
 174:	0f 84 c3 00 00 00    	je     23d <alloc_slot+0x23d>
 17a:	4f 89 4c f7 50       	mov    %r9,0x50(%r15,%r14,8)
 17f:	4c 89 ca             	mov    %r9,%rdx
 182:	8b 42 18             	mov    0x18(%rdx),%eax
 185:	85 c0                	test   %eax,%eax
 187:	0f 85 00 00 00 00    	jne    18d <alloc_slot+0x18d>
			189: R_X86_64_PC32	.text.unlikely.alloc_slot-0x4
 18d:	48 8b 42 10          	mov    0x10(%rdx),%rax
 191:	41 b9 02 00 00 00    	mov    $0x2,%r9d
 197:	4c 8d 52 1c          	lea    0x1c(%rdx),%r10
 19b:	0f b6 48 08          	movzbl 0x8(%rax),%ecx
 19f:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 1a6 <alloc_slot+0x1a6>
			1a2: R_X86_64_PC32	__libc-0x1
 1a6:	41 d3 e1             	shl    %cl,%r9d
 1a9:	45 8d 41 ff          	lea    -0x1(%r9),%r8d
 1ad:	41 f7 d9             	neg    %r9d
 1b0:	84 c0                	test   %al,%al
 1b2:	0f 85 06 01 00 00    	jne    2be <alloc_slot+0x2be>
 1b8:	8b 4a 1c             	mov    0x1c(%rdx),%ecx
 1bb:	41 21 c9             	and    %ecx,%r9d
 1be:	44 89 4a 1c          	mov    %r9d,0x1c(%rdx)
 1c2:	44 21 c1             	and    %r8d,%ecx
 1c5:	89 4a 18             	mov    %ecx,0x18(%rdx)
 1c8:	0f 84 00 00 00 00    	je     1ce <alloc_slot+0x1ce>
			1ca: R_X86_64_PC32	.text.unlikely.alloc_slot-0x4
 1ce:	0f b7 42 20          	movzwl 0x20(%rdx),%eax
 1d2:	66 c1 e8 06          	shr    $0x6,%ax
 1d6:	83 e0 3f             	and    $0x3f,%eax
 1d9:	83 e8 07             	sub    $0x7,%eax
 1dc:	83 f8 1f             	cmp    $0x1f,%eax
 1df:	77 1b                	ja     1fc <alloc_slot+0x1fc>
 1e1:	48 98                	cltq
 1e3:	41 0f b6 b4 07 98 03 	movzbl 0x398(%r15,%rax,1),%esi
 1ea:	00 00 
 1ec:	40 84 f6             	test   %sil,%sil
 1ef:	74 0b                	je     1fc <alloc_slot+0x1fc>
 1f1:	83 ee 01             	sub    $0x1,%esi
 1f4:	41 88 b4 07 98 03 00 	mov    %sil,0x398(%r15,%rax,1)
 1fb:	00 
 1fc:	89 c8                	mov    %ecx,%eax
 1fe:	f7 d8                	neg    %eax
 200:	21 c8                	and    %ecx,%eax
 202:	29 c1                	sub    %eax,%ecx
 204:	89 4a 18             	mov    %ecx,0x18(%rdx)
 207:	85 c0                	test   %eax,%eax
 209:	0f 84 6b fe ff ff    	je     7a <alloc_slot+0x7a>
 20f:	f3 0f bc c0          	tzcnt  %eax,%eax
 213:	48 83 c4 38          	add    $0x38,%rsp
 217:	5b                   	pop    %rbx
 218:	5d                   	pop    %rbp
 219:	41 5c                	pop    %r12
 21b:	41 5d                	pop    %r13
 21d:	41 5e                	pop    %r14
 21f:	41 5f                	pop    %r15
 221:	c3                   	ret
 222:	83 e1 20             	and    $0x20,%ecx
 225:	0f 84 57 ff ff ff    	je     182 <alloc_slot+0x182>
 22b:	48 8b 52 08          	mov    0x8(%rdx),%rdx
 22f:	4b 89 54 f7 50       	mov    %rdx,0x50(%r15,%r14,8)
 234:	44 8b 42 1c          	mov    0x1c(%rdx),%r8d
 238:	e9 12 ff ff ff       	jmp    14f <alloc_slot+0x14f>
 23d:	41 0f b7 41 20       	movzwl 0x20(%r9),%eax
 242:	48 8d 15 00 00 00 00 	lea    0x0(%rip),%rdx        # 249 <alloc_slot+0x249>
			245: R_X86_64_PC32	__malloc_size_classes-0x4
 249:	41 8d 4a 02          	lea    0x2(%r10),%ecx
 24d:	66 c1 e8 06          	shr    $0x6,%ax
 251:	83 e0 3f             	and    $0x3f,%eax
 254:	44 0f b7 14 42       	movzwl (%rdx,%rax,2),%r10d
 259:	89 ca                	mov    %ecx,%edx
 25b:	41 c1 e2 04          	shl    $0x4,%r10d
 25f:	41 0f af d2          	imul   %r10d,%edx
 263:	83 c2 10             	add    $0x10,%edx
 266:	eb 1e                	jmp    286 <alloc_slot+0x286>
 268:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
 26f:	00 00 00 00 
 273:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
 27a:	00 00 00 00 
 27e:	66 90                	xchg   %ax,%ax
 280:	83 c1 01             	add    $0x1,%ecx
 283:	44 89 c2             	mov    %r8d,%edx
 286:	45 8d 04 12          	lea    (%r10,%rdx,1),%r8d
 28a:	41 8d 40 ff          	lea    -0x1(%r8),%eax
 28e:	31 d0                	xor    %edx,%eax
 290:	3d ff 0f 00 00       	cmp    $0xfff,%eax
 295:	7e e9                	jle    280 <alloc_slot+0x280>
 297:	41 0f b6 41 20       	movzbl 0x20(%r9),%eax
 29c:	0f b6 56 08          	movzbl 0x8(%rsi),%edx
 2a0:	83 e0 1f             	and    $0x1f,%eax
 2a3:	83 c0 01             	add    $0x1,%eax
 2a6:	39 c8                	cmp    %ecx,%eax
 2a8:	0f 4f c1             	cmovg  %ecx,%eax
 2ab:	83 e2 e0             	and    $0xffffffe0,%edx
 2ae:	83 e8 01             	sub    $0x1,%eax
 2b1:	83 e0 1f             	and    $0x1f,%eax
 2b4:	09 d0                	or     %edx,%eax
 2b6:	88 46 08             	mov    %al,0x8(%rsi)
 2b9:	e9 c1 fe ff ff       	jmp    17f <alloc_slot+0x17f>
 2be:	8b 4a 1c             	mov    0x1c(%rdx),%ecx
 2c1:	89 ce                	mov    %ecx,%esi
 2c3:	89 c8                	mov    %ecx,%eax
 2c5:	44 21 ce             	and    %r9d,%esi
 2c8:	f0 41 0f b1 32       	lock cmpxchg %esi,(%r10)
 2cd:	39 c1                	cmp    %eax,%ecx
 2cf:	75 ed                	jne    2be <alloc_slot+0x2be>
 2d1:	e9 ec fe ff ff       	jmp    1c2 <alloc_slot+0x1c2>
 2d6:	44 89 e0             	mov    %r12d,%eax
 2d9:	48 8d 15 00 00 00 00 	lea    0x0(%rip),%rdx        # 2e0 <alloc_slot+0x2e0>
			2dc: R_X86_64_PC32	.rodata.med_cnt_tab-0x4
 2e0:	83 e0 03             	and    $0x3,%eax
 2e3:	0f b6 1c 02          	movzbl (%rdx,%rax,1),%ebx
 2e7:	eb 19                	jmp    302 <alloc_slot+0x302>
 2e9:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
 2f0:	00 00 00 00 
 2f4:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
 2fb:	00 00 00 00 
 2ff:	90                   	nop
 300:	d1 fb                	sar    $1,%ebx
 302:	f6 c3 01             	test   $0x1,%bl
 305:	75 1b                	jne    322 <alloc_slot+0x322>
 307:	8d 04 9d 00 00 00 00 	lea    0x0(,%rbx,4),%eax
 30e:	48 98                	cltq
 310:	48 39 c6             	cmp    %rax,%rsi
 313:	72 eb                	jb     300 <alloc_slot+0x300>
 315:	eb 0b                	jmp    322 <alloc_slot+0x322>
 317:	66 0f 1f 84 00 00 00 	nopw   0x0(%rax,%rax,1)
 31e:	00 00 
 320:	d1 fb                	sar    $1,%ebx
 322:	48 63 c3             	movslq %ebx,%rax
 325:	49 0f af c5          	imul   %r13,%rax
 329:	48 3d ff ff 0f 00    	cmp    $0xfffff,%rax
 32f:	77 ef                	ja     320 <alloc_slot+0x320>
 331:	48 63 d3             	movslq %ebx,%rdx
 334:	83 fb 01             	cmp    $0x1,%ebx
 337:	74 5a                	je     393 <alloc_slot+0x393>
 339:	4d 89 e8             	mov    %r13,%r8
 33c:	4c 0f af c2          	imul   %rdx,%r8
 340:	49 8d 40 10          	lea    0x10(%r8),%rax
 344:	48 3d 00 08 00 00    	cmp    $0x800,%rax
 34a:	0f 86 8c 03 00 00    	jbe    6dc <alloc_slot+0x6dc>
 350:	44 8d 0c 9d 00 00 00 	lea    0x0(,%rbx,4),%r9d
 357:	00 
 358:	4d 63 c9             	movslq %r9d,%r9
 35b:	41 8d 44 24 f9       	lea    -0x7(%r12),%eax
 360:	0f b6 15 00 00 00 00 	movzbl 0x0(%rip),%edx        # 367 <alloc_slot+0x367>
			363: R_X86_64_PC32	__malloc_context+0x3b4
 367:	83 f8 1f             	cmp    $0x1f,%eax
 36a:	77 73                	ja     3df <alloc_slot+0x3df>
 36c:	48 98                	cltq
 36e:	41 0f b6 8c 07 78 03 	movzbl 0x378(%r15,%rax,1),%ecx
 375:	00 00 
 377:	45 0f b6 94 07 98 03 	movzbl 0x398(%r15,%rax,1),%r10d
 37e:	00 00 
 380:	85 c9                	test   %ecx,%ecx
 382:	75 32                	jne    3b6 <alloc_slot+0x3b6>
 384:	31 c9                	xor    %ecx,%ecx
 386:	41 80 fa 63          	cmp    $0x63,%r10b
 38a:	0f 97 c1             	seta   %cl
 38d:	41 0f 96 c2          	setbe  %r10b
 391:	eb 54                	jmp    3e7 <alloc_slot+0x3e7>
 393:	49 8d 45 10          	lea    0x10(%r13),%rax
 397:	48 3d 00 08 00 00    	cmp    $0x800,%rax
 39d:	77 0c                	ja     3ab <alloc_slot+0x3ab>
 39f:	ba 02 00 00 00       	mov    $0x2,%edx
 3a4:	bb 02 00 00 00       	mov    $0x2,%ebx
 3a9:	eb 8e                	jmp    339 <alloc_slot+0x339>
 3ab:	4d 89 e8             	mov    %r13,%r8
 3ae:	41 b9 04 00 00 00    	mov    $0x4,%r9d
 3b4:	eb a5                	jmp    35b <alloc_slot+0x35b>
 3b6:	44 0f b6 da          	movzbl %dl,%r11d
 3ba:	41 29 cb             	sub    %ecx,%r11d
 3bd:	41 83 fb 09          	cmp    $0x9,%r11d
 3c1:	7f c1                	jg     384 <alloc_slot+0x384>
 3c3:	41 8d 4a 01          	lea    0x1(%r10),%ecx
 3c7:	41 80 fa 63          	cmp    $0x63,%r10b
 3cb:	41 bb 96 ff ff ff    	mov    $0xffffff96,%r11d
 3d1:	41 0f 43 cb          	cmovae %r11d,%ecx
 3d5:	41 88 8c 07 98 03 00 	mov    %cl,0x398(%r15,%rax,1)
 3dc:	00 
 3dd:	eb a5                	jmp    384 <alloc_slot+0x384>
 3df:	41 ba 01 00 00 00    	mov    $0x1,%r10d
 3e5:	31 c9                	xor    %ecx,%ecx
 3e7:	8d 42 01             	lea    0x1(%rdx),%eax
 3ea:	80 fa ff             	cmp    $0xff,%dl
 3ed:	0f 84 c3 01 00 00    	je     5b6 <alloc_slot+0x5b6>
 3f3:	88 05 00 00 00 00    	mov    %al,0x0(%rip)        # 3f9 <alloc_slot+0x3f9>
			3f5: R_X86_64_PC32	__malloc_context+0x3b4
 3f9:	41 f6 c4 01          	test   $0x1,%r12b
 3fd:	0f 85 1e 02 00 00    	jne    621 <alloc_slot+0x621>
 403:	41 83 fc 1f          	cmp    $0x1f,%r12d
 407:	0f 8f dd 01 00 00    	jg     5ea <alloc_slot+0x5ea>
 40d:	41 8d 44 24 01       	lea    0x1(%r12),%eax
 412:	48 98                	cltq
 414:	49 03 b4 c7 f8 01 00 	add    0x1f8(%r15,%rax,8),%rsi
 41b:	00 
 41c:	4c 39 ce             	cmp    %r9,%rsi
 41f:	73 09                	jae    42a <alloc_slot+0x42a>
 421:	45 84 d2             	test   %r10b,%r10b
 424:	0f 85 ce 01 00 00    	jne    5f8 <alloc_slot+0x5f8>
 42a:	83 fb 07             	cmp    $0x7,%ebx
 42d:	48 63 d3             	movslq %ebx,%rdx
 430:	41 0f 9e c0          	setle  %r8b
 434:	49 0f af d5          	imul   %r13,%rdx
 438:	48 c7 c0 f0 ff ff ff 	mov    $0xfffffffffffffff0,%rax
 43f:	48 29 d0             	sub    %rdx,%rax
 442:	25 ff 0f 00 00       	and    $0xfff,%eax
 447:	4c 8d 54 02 10       	lea    0x10(%rdx,%rax,1),%r10
 44c:	85 c9                	test   %ecx,%ecx
 44e:	75 3d                	jne    48d <alloc_slot+0x48d>
 450:	45 84 c0             	test   %r8b,%r8b
 453:	74 38                	je     48d <alloc_slot+0x48d>
 455:	48 c7 c0 ec ff ff ff 	mov    $0xffffffffffffffec,%rax
 45c:	49 8d 55 10          	lea    0x10(%r13),%rdx
 460:	48 29 f8             	sub    %rdi,%rax
 463:	25 ff 0f 00 00       	and    $0xfff,%eax
 468:	48 8d 44 07 14       	lea    0x14(%rdi,%rax,1),%rax
 46d:	48 39 d0             	cmp    %rdx,%rax
 470:	72 13                	jb     485 <alloc_slot+0x485>
 472:	48 3d ff 3f 00 00    	cmp    $0x3fff,%rax
 478:	76 13                	jbe    48d <alloc_slot+0x48d>
 47a:	8d 14 1b             	lea    (%rbx,%rbx,1),%edx
 47d:	48 63 d2             	movslq %edx,%rdx
 480:	48 39 d6             	cmp    %rdx,%rsi
 483:	73 08                	jae    48d <alloc_slot+0x48d>
 485:	49 89 c2             	mov    %rax,%r10
 488:	bb 01 00 00 00       	mov    $0x1,%ebx
 48d:	4c 89 d6             	mov    %r10,%rsi
 490:	45 31 c9             	xor    %r9d,%r9d
 493:	31 ff                	xor    %edi,%edi
 495:	41 b8 ff ff ff ff    	mov    $0xffffffff,%r8d
 49b:	b9 22 00 00 00       	mov    $0x22,%ecx
 4a0:	ba 03 00 00 00       	mov    $0x3,%edx
 4a5:	4c 89 54 24 08       	mov    %r10,0x8(%rsp)
 4aa:	e8 00 00 00 00       	call   4af <alloc_slot+0x4af>
			4ab: R_X86_64_PLT32	__mmap-0x4
 4af:	4c 8b 54 24 08       	mov    0x8(%rsp),%r10
 4b4:	48 83 f8 ff          	cmp    $0xffffffffffffffff,%rax
 4b8:	48 89 c6             	mov    %rax,%rsi
 4bb:	0f 84 e1 01 00 00    	je     6a2 <alloc_slot+0x6a2>
 4c1:	48 8b 45 20          	mov    0x20(%rbp),%rax
 4c5:	49 81 e2 00 f0 ff ff 	and    $0xfffffffffffff000,%r10
 4cc:	31 d2                	xor    %edx,%edx
 4ce:	44 8d 43 ff          	lea    -0x1(%rbx),%r8d
 4d2:	25 ff 0f 00 00       	and    $0xfff,%eax
 4d7:	49 09 c2             	or     %rax,%r10
 4da:	b8 f0 0f 00 00       	mov    $0xff0,%eax
 4df:	49 f7 f5             	div    %r13
 4e2:	4c 89 55 20          	mov    %r10,0x20(%rbp)
 4e6:	83 05 00 00 00 00 01 	addl   $0x1,0x0(%rip)        # 4ed <alloc_slot+0x4ed>
			4e8: R_X86_64_PC32	__malloc_context+0x7
 4ed:	83 e8 01             	sub    $0x1,%eax
 4f0:	39 d8                	cmp    %ebx,%eax
 4f2:	41 0f 4d c0          	cmovge %r8d,%eax
 4f6:	31 d2                	xor    %edx,%edx
 4f8:	89 d7                	mov    %edx,%edi
 4fa:	48 63 d3             	movslq %ebx,%rdx
 4fd:	85 c0                	test   %eax,%eax
 4ff:	0f 49 f8             	cmovns %eax,%edi
 502:	b8 02 00 00 00       	mov    $0x2,%eax
 507:	4b 01 94 f7 f8 01 00 	add    %rdx,0x1f8(%r15,%r14,8)
 50e:	00 
 50f:	89 f9                	mov    %edi,%ecx
 511:	89 c2                	mov    %eax,%edx
 513:	48 89 75 10          	mov    %rsi,0x10(%rbp)
 517:	83 eb 01             	sub    $0x1,%ebx
 51a:	41 83 e4 3f          	and    $0x3f,%r12d
 51e:	d3 e2                	shl    %cl,%edx
 520:	44 89 c1             	mov    %r8d,%ecx
 523:	83 e3 1f             	and    $0x1f,%ebx
 526:	41 c1 e4 06          	shl    $0x6,%r12d
 52a:	83 ea 01             	sub    $0x1,%edx
 52d:	d3 e0                	shl    %cl,%eax
 52f:	83 cb 20             	or     $0x20,%ebx
 532:	89 55 18             	mov    %edx,0x18(%rbp)
 535:	8b 55 18             	mov    0x18(%rbp),%edx
 538:	44 09 e3             	or     %r12d,%ebx
 53b:	29 d0                	sub    %edx,%eax
 53d:	83 e8 01             	sub    $0x1,%eax
 540:	89 45 1c             	mov    %eax,0x1c(%rbp)
 543:	89 f8                	mov    %edi,%eax
 545:	48 89 2e             	mov    %rbp,(%rsi)
 548:	48 8b 4d 10          	mov    0x10(%rbp),%rcx
 54c:	83 e0 1f             	and    $0x1f,%eax
 54f:	0f b6 51 08          	movzbl 0x8(%rcx),%edx
 553:	83 e2 e0             	and    $0xffffffe0,%edx
 556:	09 d0                	or     %edx,%eax
 558:	88 41 08             	mov    %al,0x8(%rcx)
 55b:	0f b7 45 20          	movzwl 0x20(%rbp),%eax
 55f:	66 25 00 f0          	and    $0xf000,%ax
 563:	09 c3                	or     %eax,%ebx
 565:	8b 45 18             	mov    0x18(%rbp),%eax
 568:	66 89 5d 20          	mov    %bx,0x20(%rbp)
 56c:	83 e8 01             	sub    $0x1,%eax
 56f:	48 83 7d 08 00       	cmpq   $0x0,0x8(%rbp)
 574:	89 45 18             	mov    %eax,0x18(%rbp)
 577:	0f 85 00 00 00 00    	jne    57d <alloc_slot+0x57d>
			579: R_X86_64_PC32	.text.unlikely.alloc_slot-0x4
 57d:	48 83 7d 00 00       	cmpq   $0x0,0x0(%rbp)
 582:	0f 85 00 00 00 00    	jne    588 <alloc_slot+0x588>
			584: R_X86_64_PC32	.text.unlikely.alloc_slot-0x4
 588:	49 83 c6 0a          	add    $0xa,%r14
 58c:	4b 8b 04 f7          	mov    (%r15,%r14,8),%rax
 590:	48 85 c0             	test   %rax,%rax
 593:	0f 84 bf 03 00 00    	je     958 <alloc_slot+0x958>
 599:	48 89 45 08          	mov    %rax,0x8(%rbp)
 59d:	48 8b 00             	mov    (%rax),%rax
 5a0:	48 89 45 00          	mov    %rax,0x0(%rbp)
 5a4:	48 89 68 08          	mov    %rbp,0x8(%rax)
 5a8:	48 8b 45 08          	mov    0x8(%rbp),%rax
 5ac:	48 89 28             	mov    %rbp,(%rax)
 5af:	31 c0                	xor    %eax,%eax
 5b1:	e9 5d fc ff ff       	jmp    213 <alloc_slot+0x213>
 5b6:	48 8d 05 00 00 00 00 	lea    0x0(%rip),%rax        # 5bd <alloc_slot+0x5bd>
			5b9: R_X86_64_PC32	__malloc_context+0x374
 5bd:	48 8d 50 20          	lea    0x20(%rax),%rdx
 5c1:	eb 18                	jmp    5db <alloc_slot+0x5db>
 5c3:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
 5ca:	00 00 00 00 
 5ce:	66 90                	xchg   %ax,%ax
 5d0:	c6 00 00             	movb   $0x0,(%rax)
 5d3:	48 83 c0 02          	add    $0x2,%rax
 5d7:	c6 40 ff 00          	movb   $0x0,-0x1(%rax)
 5db:	48 39 d0             	cmp    %rdx,%rax
 5de:	75 f0                	jne    5d0 <alloc_slot+0x5d0>
 5e0:	b8 01 00 00 00       	mov    $0x1,%eax
 5e5:	e9 09 fe ff ff       	jmp    3f3 <alloc_slot+0x3f3>
 5ea:	4c 39 ce             	cmp    %r9,%rsi
 5ed:	0f 82 2e fe ff ff    	jb     421 <alloc_slot+0x421>
 5f3:	e9 32 fe ff ff       	jmp    42a <alloc_slot+0x42a>
 5f8:	44 89 e0             	mov    %r12d,%eax
 5fb:	83 e0 03             	and    $0x3,%eax
 5fe:	83 f8 02             	cmp    $0x2,%eax
 601:	74 6f                	je     672 <alloc_slot+0x672>
 603:	49 81 f8 00 80 00 00 	cmp    $0x8000,%r8
 60a:	76 74                	jbe    680 <alloc_slot+0x680>
 60c:	41 b8 01 00 00 00    	mov    $0x1,%r8d
 612:	ba 03 00 00 00       	mov    $0x3,%edx
 617:	bb 03 00 00 00       	mov    $0x3,%ebx
 61c:	e9 13 fe ff ff       	jmp    434 <alloc_slot+0x434>
 621:	4c 39 ce             	cmp    %r9,%rsi
 624:	0f 83 00 fe ff ff    	jae    42a <alloc_slot+0x42a>
 62a:	45 84 d2             	test   %r10b,%r10b
 62d:	0f 84 f7 fd ff ff    	je     42a <alloc_slot+0x42a>
 633:	44 89 e0             	mov    %r12d,%eax
 636:	83 e0 03             	and    $0x3,%eax
 639:	83 f8 01             	cmp    $0x1,%eax
 63c:	0f 85 e8 fd ff ff    	jne    42a <alloc_slot+0x42a>
 642:	49 81 f8 00 80 00 00 	cmp    $0x8000,%r8
 649:	0f 86 db fd ff ff    	jbe    42a <alloc_slot+0x42a>
 64f:	4b 8d 54 2d 00       	lea    0x0(%r13,%r13,1),%rdx
 654:	48 c7 c0 f0 ff ff ff 	mov    $0xfffffffffffffff0,%rax
 65b:	bb 02 00 00 00       	mov    $0x2,%ebx
 660:	48 29 d0             	sub    %rdx,%rax
 663:	25 ff 0f 00 00       	and    $0xfff,%eax
 668:	4c 8d 54 02 10       	lea    0x10(%rdx,%rax,1),%r10
 66d:	e9 e3 fd ff ff       	jmp    455 <alloc_slot+0x455>
 672:	49 81 f8 00 40 00 00 	cmp    $0x4000,%r8
 679:	77 91                	ja     60c <alloc_slot+0x60c>
 67b:	e9 aa fd ff ff       	jmp    42a <alloc_slot+0x42a>
 680:	49 81 f8 00 20 00 00 	cmp    $0x2000,%r8
 687:	0f 86 9d fd ff ff    	jbe    42a <alloc_slot+0x42a>
 68d:	41 b8 01 00 00 00    	mov    $0x1,%r8d
 693:	ba 05 00 00 00       	mov    $0x5,%edx
 698:	bb 05 00 00 00       	mov    $0x5,%ebx
 69d:	e9 92 fd ff ff       	jmp    434 <alloc_slot+0x434>
 6a2:	66 0f ef c0          	pxor   %xmm0,%xmm0
 6a6:	48 c7 45 20 00 00 00 	movq   $0x0,0x20(%rbp)
 6ad:	00 
 6ae:	0f 11 45 00          	movups %xmm0,0x0(%rbp)
 6b2:	0f 11 45 10          	movups %xmm0,0x10(%rbp)
 6b6:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 6bd <alloc_slot+0x6bd>
			6b9: R_X86_64_PC32	__malloc_context+0xc
 6bd:	48 85 c0             	test   %rax,%rax
 6c0:	0f 85 da 00 00 00    	jne    7a0 <alloc_slot+0x7a0>
 6c6:	66 0f 6f 5c 24 10    	movdqa 0x10(%rsp),%xmm3
 6cc:	0f 11 5d 00          	movups %xmm3,0x0(%rbp)
 6d0:	48 89 2d 00 00 00 00 	mov    %rbp,0x0(%rip)        # 6d7 <alloc_slot+0x6d7>
			6d3: R_X86_64_PC32	__malloc_context+0xc
 6d7:	e9 da 00 00 00       	jmp    7b6 <alloc_slot+0x7b6>
 6dc:	4c 89 c0             	mov    %r8,%rax
 6df:	4d 8d 48 0c          	lea    0xc(%r8),%r9
 6e3:	48 c1 e8 04          	shr    $0x4,%rax
 6e7:	89 c7                	mov    %eax,%edi
 6e9:	49 81 f8 90 00 00 00 	cmp    $0x90,%r8
 6f0:	76 2f                	jbe    721 <alloc_slot+0x721>
 6f2:	48 83 c0 01          	add    $0x1,%rax
 6f6:	0f bd f0             	bsr    %eax,%esi
 6f9:	8d 3c b5 fc ff ff ff 	lea    -0x4(,%rsi,4),%edi
 700:	8d 77 01             	lea    0x1(%rdi),%esi
 703:	48 63 f6             	movslq %esi,%rsi
 706:	44 0f b7 04 71       	movzwl (%rcx,%rsi,2),%r8d
 70b:	8d 77 02             	lea    0x2(%rdi),%esi
 70e:	49 39 c0             	cmp    %rax,%r8
 711:	0f 42 fe             	cmovb  %esi,%edi
 714:	48 63 f7             	movslq %edi,%rsi
 717:	0f b7 34 71          	movzwl (%rcx,%rsi,2),%esi
 71b:	48 39 c6             	cmp    %rax,%rsi
 71e:	83 d7 00             	adc    $0x0,%edi
 721:	4c 89 ce             	mov    %r9,%rsi
 724:	48 89 54 24 20       	mov    %rdx,0x20(%rsp)
 729:	89 7c 24 08          	mov    %edi,0x8(%rsp)
 72d:	e8 ce f8 ff ff       	call   0 <alloc_slot>
 732:	48 63 7c 24 08       	movslq 0x8(%rsp),%rdi
 737:	48 8b 54 24 20       	mov    0x20(%rsp),%rdx
 73c:	48 8d 0d 00 00 00 00 	lea    0x0(%rip),%rcx        # 743 <alloc_slot+0x743>
			73f: R_X86_64_PC32	__malloc_size_classes-0x4
 743:	83 f8 ff             	cmp    $0xffffffff,%eax
 746:	74 38                	je     780 <alloc_slot+0x780>
 748:	0f b7 34 79          	movzwl (%rcx,%rdi,2),%esi
 74c:	4d 8b 4c ff 50       	mov    0x50(%r15,%rdi,8),%r9
 751:	c1 e6 04             	shl    $0x4,%esi
 754:	8d 7e fc             	lea    -0x4(%rsi),%edi
 757:	89 7c 24 20          	mov    %edi,0x20(%rsp)
 75b:	4c 63 c7             	movslq %edi,%r8
 75e:	41 f6 41 20 1f       	testb  $0x1f,0x20(%r9)
 763:	75 6e                	jne    7d3 <alloc_slot+0x7d3>
 765:	49 81 79 20 ff 0f 00 	cmpq   $0xfff,0x20(%r9)
 76c:	00 
 76d:	76 64                	jbe    7d3 <alloc_slot+0x7d3>
 76f:	49 8b 79 20          	mov    0x20(%r9),%rdi
 773:	48 81 e7 00 f0 ff ff 	and    $0xfffffffffffff000,%rdi
 77a:	48 83 ef 10          	sub    $0x10,%rdi
 77e:	eb 69                	jmp    7e9 <alloc_slot+0x7e9>
 780:	66 0f ef c0          	pxor   %xmm0,%xmm0
 784:	48 c7 45 20 00 00 00 	movq   $0x0,0x20(%rbp)
 78b:	00 
 78c:	0f 11 45 00          	movups %xmm0,0x0(%rbp)
 790:	0f 11 45 10          	movups %xmm0,0x10(%rbp)
 794:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 79b <alloc_slot+0x79b>
			797: R_X86_64_PC32	__malloc_context+0xc
 79b:	48 85 c0             	test   %rax,%rax
 79e:	74 20                	je     7c0 <alloc_slot+0x7c0>
 7a0:	48 89 45 08          	mov    %rax,0x8(%rbp)
 7a4:	48 8b 00             	mov    (%rax),%rax
 7a7:	48 89 45 00          	mov    %rax,0x0(%rbp)
 7ab:	48 89 68 08          	mov    %rbp,0x8(%rax)
 7af:	48 8b 45 08          	mov    0x8(%rbp),%rax
 7b3:	48 89 28             	mov    %rbp,(%rax)
 7b6:	b8 ff ff ff ff       	mov    $0xffffffff,%eax
 7bb:	e9 53 fa ff ff       	jmp    213 <alloc_slot+0x213>
 7c0:	66 0f 6f 64 24 10    	movdqa 0x10(%rsp),%xmm4
 7c6:	0f 11 65 00          	movups %xmm4,0x0(%rbp)
 7ca:	48 89 2d 00 00 00 00 	mov    %rbp,0x0(%rip)        # 7d1 <alloc_slot+0x7d1>
			7cd: R_X86_64_PC32	__malloc_context+0xc
 7d1:	eb e3                	jmp    7b6 <alloc_slot+0x7b6>
 7d3:	41 0f b7 71 20       	movzwl 0x20(%r9),%esi
 7d8:	66 c1 ee 06          	shr    $0x6,%si
 7dc:	83 e6 3f             	and    $0x3f,%esi
 7df:	0f b7 3c 71          	movzwl (%rcx,%rsi,2),%edi
 7e3:	c1 e7 04             	shl    $0x4,%edi
 7e6:	48 63 ff             	movslq %edi,%rdi
 7e9:	48 89 f9             	mov    %rdi,%rcx
 7ec:	48 63 f0             	movslq %eax,%rsi
 7ef:	4c 29 c1             	sub    %r8,%rcx
 7f2:	48 0f af f7          	imul   %rdi,%rsi
 7f6:	4c 8d 51 fc          	lea    -0x4(%rcx),%r10
 7fa:	49 8b 49 10          	mov    0x10(%r9),%rcx
 7fe:	48 83 c1 10          	add    $0x10,%rcx
 802:	48 01 ce             	add    %rcx,%rsi
 805:	48 8d 7c 3e fc       	lea    -0x4(%rsi,%rdi,1),%rdi
 80a:	48 89 7c 24 08       	mov    %rdi,0x8(%rsp)
 80f:	0f b6 7e fc          	movzbl -0x4(%rsi),%edi
 813:	40 84 ff             	test   %dil,%dil
 816:	0f 85 00 00 00 00    	jne    81c <alloc_slot+0x81c>
			818: R_X86_64_PC32	.text.unlikely.alloc_slot-0x4
 81c:	49 83 fa 0f          	cmp    $0xf,%r10
 820:	0f 86 94 00 00 00    	jbe    8ba <alloc_slot+0x8ba>
 826:	80 7e fd 00          	cmpb   $0x0,-0x3(%rsi)
 82a:	0f 84 e9 00 00 00    	je     919 <alloc_slot+0x919>
 830:	44 0f b7 46 fe       	movzwl -0x2(%rsi),%r8d
 835:	41 83 c0 01          	add    $0x1,%r8d
 839:	45 0f b6 c0          	movzbl %r8b,%r8d
 83d:	4d 89 d3             	mov    %r10,%r11
 840:	49 c1 eb 04          	shr    $0x4,%r11
 844:	4c 89 5c 24 28       	mov    %r11,0x28(%rsp)
 849:	4d 63 d8             	movslq %r8d,%r11
 84c:	4c 39 5c 24 28       	cmp    %r11,0x28(%rsp)
 851:	73 43                	jae    896 <alloc_slot+0x896>
 853:	4c 8b 5c 24 28       	mov    0x28(%rsp),%r11
 858:	49 c1 ea 05          	shr    $0x5,%r10
 85c:	4d 09 da             	or     %r11,%r10
 85f:	4d 89 d3             	mov    %r10,%r11
 862:	49 c1 eb 02          	shr    $0x2,%r11
 866:	4d 09 da             	or     %r11,%r10
 869:	4d 89 d3             	mov    %r10,%r11
 86c:	49 c1 eb 04          	shr    $0x4,%r11
 870:	4d 09 da             	or     %r11,%r10
 873:	4c 8b 5c 24 28       	mov    0x28(%rsp),%r11
 878:	45 21 d0             	and    %r10d,%r8d
 87b:	4d 63 d0             	movslq %r8d,%r10
 87e:	4d 39 d3             	cmp    %r10,%r11
 881:	73 13                	jae    896 <alloc_slot+0x896>
 883:	45 29 d8             	sub    %r11d,%r8d
 886:	41 83 e8 01          	sub    $0x1,%r8d
 88a:	4d 63 d0             	movslq %r8d,%r10
 88d:	4d 39 d3             	cmp    %r10,%r11
 890:	0f 82 00 00 00 00    	jb     896 <alloc_slot+0x896>
			892: R_X86_64_PC32	.text.unlikely.alloc_slot-0x4
 896:	45 85 c0             	test   %r8d,%r8d
 899:	74 1f                	je     8ba <alloc_slot+0x8ba>
 89b:	66 44 89 46 fe       	mov    %r8w,-0x2(%rsi)
 8a0:	41 c1 e0 04          	shl    $0x4,%r8d
 8a4:	49 63 c8             	movslq %r8d,%rcx
 8a7:	c6 46 fd e0          	movb   $0xe0,-0x3(%rsi)
 8ab:	48 01 ce             	add    %rcx,%rsi
 8ae:	c6 46 fc 00          	movb   $0x0,-0x4(%rsi)
 8b2:	49 8b 49 10          	mov    0x10(%r9),%rcx
 8b6:	48 83 c1 10          	add    $0x10,%rcx
 8ba:	49 89 f0             	mov    %rsi,%r8
 8bd:	4c 8b 4c 24 08       	mov    0x8(%rsp),%r9
 8c2:	44 8b 5c 24 20       	mov    0x20(%rsp),%r11d
 8c7:	49 29 c8             	sub    %rcx,%r8
 8ca:	4c 89 c1             	mov    %r8,%rcx
 8cd:	48 c1 e9 04          	shr    $0x4,%rcx
 8d1:	66 89 4e fe          	mov    %cx,-0x2(%rsi)
 8d5:	4c 89 c9             	mov    %r9,%rcx
 8d8:	48 29 f1             	sub    %rsi,%rcx
 8db:	44 29 d9             	sub    %r11d,%ecx
 8de:	74 16                	je     8f6 <alloc_slot+0x8f6>
 8e0:	89 cf                	mov    %ecx,%edi
 8e2:	f7 df                	neg    %edi
 8e4:	48 63 ff             	movslq %edi,%rdi
 8e7:	41 c6 04 39 00       	movb   $0x0,(%r9,%rdi,1)
 8ec:	83 f9 04             	cmp    $0x4,%ecx
 8ef:	7f 35                	jg     926 <alloc_slot+0x926>
 8f1:	89 cf                	mov    %ecx,%edi
 8f3:	c1 e7 05             	shl    $0x5,%edi
 8f6:	01 c7                	add    %eax,%edi
 8f8:	48 8d 4e 0c          	lea    0xc(%rsi),%rcx
 8fc:	40 88 7e fd          	mov    %dil,-0x3(%rsi)
 900:	48 81 65 20 ff 0f 00 	andq   $0xfff,0x20(%rbp)
 907:	00 
 908:	0f b6 46 fd          	movzbl -0x3(%rsi),%eax
 90c:	83 e0 1f             	and    $0x1f,%eax
 90f:	83 c8 c0             	or     $0xffffffc0,%eax
 912:	88 46 fd             	mov    %al,-0x3(%rsi)
 915:	31 c0                	xor    %eax,%eax
 917:	eb 30                	jmp    949 <alloc_slot+0x949>
 919:	44 0f b6 05 00 00 00 	movzbl 0x0(%rip),%r8d        # 921 <alloc_slot+0x921>
 920:	00 
			91d: R_X86_64_PC32	__malloc_context+0x8
 921:	e9 17 ff ff ff       	jmp    83d <alloc_slot+0x83d>
 926:	41 89 49 fc          	mov    %ecx,-0x4(%r9)
 92a:	bf a0 ff ff ff       	mov    $0xffffffa0,%edi
 92f:	41 c6 41 fb 00       	movb   $0x0,-0x5(%r9)
 934:	eb c0                	jmp    8f6 <alloc_slot+0x8f6>
 936:	66 2e 0f 1f 84 00 00 	cs nopw 0x0(%rax,%rax,1)
 93d:	00 00 00 
 940:	c6 01 00             	movb   $0x0,(%rcx)
 943:	83 c0 01             	add    $0x1,%eax
 946:	4c 01 e9             	add    %r13,%rcx
 949:	39 c3                	cmp    %eax,%ebx
 94b:	7d f3                	jge    940 <alloc_slot+0x940>
 94d:	8d 7b ff             	lea    -0x1(%rbx),%edi
 950:	41 89 f8             	mov    %edi,%r8d
 953:	e9 aa fb ff ff       	jmp    502 <alloc_slot+0x502>
 958:	66 0f 6f 54 24 10    	movdqa 0x10(%rsp),%xmm2
 95e:	0f 11 55 00          	movups %xmm2,0x0(%rbp)
 962:	4b 89 2c f7          	mov    %rbp,(%r15,%r14,8)
 966:	e9 44 fc ff ff       	jmp    5af <alloc_slot+0x5af>

Disassembly of section .text.unlikely.malloc_slow:

0000000000000000 <malloc_slow.cold>:
   0:	0f 0b                	ud2

Disassembly of section .text.malloc_slow:

0000000000000000 <malloc_slow>:
   0:	48 b8 fe ef ff ff ff 	movabs $0x7fffffffffffeffe,%rax
   7:	ff ff 7f 
   a:	41 57                	push   %r15
   c:	41 56                	push   %r14
   e:	41 55                	push   %r13
  10:	41 54                	push   %r12
  12:	55                   	push   %rbp
  13:	53                   	push   %rbx
  14:	48 83 ec 08          	sub    $0x8,%rsp
  18:	48 39 f8             	cmp    %rdi,%rax
  1b:	0f 82 20 01 00 00    	jb     141 <malloc_slow+0x141>
  21:	48 89 fb             	mov    %rdi,%rbx
  24:	48 81 ff eb ff 01 00 	cmp    $0x1ffeb,%rdi
  2b:	0f 87 22 01 00 00    	ja     153 <malloc_slow+0x153>
  31:	48 8d 57 03          	lea    0x3(%rdi),%rdx
  35:	48 89 d0             	mov    %rdx,%rax
  38:	48 c1 e8 04          	shr    $0x4,%rax
  3c:	4c 63 f0             	movslq %eax,%r14
  3f:	4d 89 f4             	mov    %r14,%r12
  42:	48 81 fa 9f 00 00 00 	cmp    $0x9f,%rdx
  49:	76 42                	jbe    8d <malloc_slow+0x8d>
  4b:	48 83 c0 01          	add    $0x1,%rax
  4f:	48 8d 0d 00 00 00 00 	lea    0x0(%rip),%rcx        # 56 <malloc_slow+0x56>
			52: R_X86_64_PC32	__malloc_size_classes-0x4
  56:	0f bd d0             	bsr    %eax,%edx
  59:	44 8d 24 95 fc ff ff 	lea    -0x4(,%rdx,4),%r12d
  60:	ff 
  61:	41 8d 54 24 01       	lea    0x1(%r12),%edx
  66:	48 63 d2             	movslq %edx,%rdx
  69:	0f b7 34 51          	movzwl (%rcx,%rdx,2),%esi
  6d:	41 8d 54 24 02       	lea    0x2(%r12),%edx
  72:	48 39 c6             	cmp    %rax,%rsi
  75:	44 0f 42 e2          	cmovb  %edx,%r12d
  79:	4d 63 f4             	movslq %r12d,%r14
  7c:	42 0f b7 14 71       	movzwl (%rcx,%r14,2),%edx
  81:	48 39 c2             	cmp    %rax,%rdx
  84:	73 07                	jae    8d <malloc_slow+0x8d>
  86:	41 83 c4 01          	add    $0x1,%r12d
  8a:	4d 63 f4             	movslq %r12d,%r14
  8d:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 94 <malloc_slow+0x94>
			90: R_X86_64_PC32	__libc-0x1
  94:	4c 8d 2d 00 00 00 00 	lea    0x0(%rip),%r13        # 9b <malloc_slow+0x9b>
			97: R_X86_64_PC32	__malloc_lock-0x4
  9b:	84 c0                	test   %al,%al
  9d:	0f 85 bb 01 00 00    	jne    25e <malloc_slow+0x25e>
  a3:	4c 8d 3d 00 00 00 00 	lea    0x0(%rip),%r15        # aa <malloc_slow+0xaa>
			a6: R_X86_64_PC32	__malloc_context-0x4
  aa:	4b 8b 6c f7 50       	mov    0x50(%r15,%r14,8),%rbp
  af:	48 85 ed             	test   %rbp,%rbp
  b2:	0f 85 e1 01 00 00    	jne    299 <malloc_slow+0x299>
  b8:	41 83 fc 03          	cmp    $0x3,%r12d
  bc:	0f 8e ce 01 00 00    	jle    290 <malloc_slow+0x290>
  c2:	41 83 fc 1f          	cmp    $0x1f,%r12d
  c6:	7f 4b                	jg     113 <malloc_slow+0x113>
  c8:	41 83 fc 06          	cmp    $0x6,%r12d
  cc:	74 45                	je     113 <malloc_slow+0x113>
  ce:	41 f6 c4 01          	test   $0x1,%r12b
  d2:	75 3f                	jne    113 <malloc_slow+0x113>
  d4:	4b 83 bc f7 f8 01 00 	cmpq   $0x0,0x1f8(%r15,%r14,8)
  db:	00 00 
  dd:	75 34                	jne    113 <malloc_slow+0x113>
  df:	44 89 e1             	mov    %r12d,%ecx
  e2:	83 c9 01             	or     $0x1,%ecx
  e5:	48 63 c1             	movslq %ecx,%rax
  e8:	49 8b 6c c7 50       	mov    0x50(%r15,%rax,8),%rbp
  ed:	49 8b 94 c7 f8 01 00 	mov    0x1f8(%r15,%rax,8),%rdx
  f4:	00 
  f5:	48 85 ed             	test   %rbp,%rbp
  f8:	0f 84 81 01 00 00    	je     27f <malloc_slow+0x27f>
  fe:	8b 45 18             	mov    0x18(%rbp),%eax
 101:	85 c0                	test   %eax,%eax
 103:	0f 84 62 01 00 00    	je     26b <malloc_slow+0x26b>
 109:	48 83 fa 0c          	cmp    $0xc,%rdx
 10d:	0f 86 db 01 00 00    	jbe    2ee <malloc_slow+0x2ee>
 113:	48 89 de             	mov    %rbx,%rsi
 116:	44 89 e7             	mov    %r12d,%edi
 119:	e8 00 00 00 00       	call   11e <malloc_slow+0x11e>
			11a: R_X86_64_PC32	.text.alloc_slot-0x4
 11e:	41 89 c6             	mov    %eax,%r14d
 121:	83 f8 ff             	cmp    $0xffffffff,%eax
 124:	0f 84 c9 01 00 00    	je     2f3 <malloc_slow+0x2f3>
 12a:	4d 63 e4             	movslq %r12d,%r12
 12d:	4b 8b 6c e7 50       	mov    0x50(%r15,%r12,8),%rbp
 132:	44 8b 25 00 00 00 00 	mov    0x0(%rip),%r12d        # 139 <malloc_slow+0x139>
			135: R_X86_64_PC32	__malloc_context+0x8
 139:	4c 63 f8             	movslq %eax,%r15
 13c:	e9 82 01 00 00       	jmp    2c3 <malloc_slow+0x2c3>
 141:	e8 00 00 00 00       	call   146 <malloc_slow+0x146>
			142: R_X86_64_PLT32	___errno_location-0x4
 146:	c7 00 0c 00 00 00    	movl   $0xc,(%rax)
 14c:	31 c0                	xor    %eax,%eax
 14e:	e9 c5 02 00 00       	jmp    418 <malloc_slow+0x418>
 153:	4c 8d 77 14          	lea    0x14(%rdi),%r14
 157:	4c 8d a7 13 10 00 00 	lea    0x1013(%rdi),%r12
 15e:	45 31 c9             	xor    %r9d,%r9d
 161:	31 ff                	xor    %edi,%edi
 163:	41 b8 ff ff ff ff    	mov    $0xffffffff,%r8d
 169:	b9 22 00 00 00       	mov    $0x22,%ecx
 16e:	ba 03 00 00 00       	mov    $0x3,%edx
 173:	4c 89 f6             	mov    %r14,%rsi
 176:	e8 00 00 00 00       	call   17b <malloc_slow+0x17b>
			177: R_X86_64_PLT32	__mmap-0x4
 17b:	49 89 c7             	mov    %rax,%r15
 17e:	48 83 f8 ff          	cmp    $0xffffffffffffffff,%rax
 182:	74 c8                	je     14c <malloc_slow+0x14c>
 184:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 18b <malloc_slow+0x18b>
			187: R_X86_64_PC32	__libc-0x1
 18b:	4c 8d 2d 00 00 00 00 	lea    0x0(%rip),%r13        # 192 <malloc_slow+0x192>
			18e: R_X86_64_PC32	__malloc_lock-0x4
 192:	84 c0                	test   %al,%al
 194:	75 68                	jne    1fe <malloc_slow+0x1fe>
 196:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 19d <malloc_slow+0x19d>
			199: R_X86_64_PC32	__malloc_context+0x3b4
 19d:	8d 50 01             	lea    0x1(%rax),%edx
 1a0:	3c ff                	cmp    $0xff,%al
 1a2:	74 64                	je     208 <malloc_slow+0x208>
 1a4:	88 15 00 00 00 00    	mov    %dl,0x0(%rip)        # 1aa <malloc_slow+0x1aa>
			1a6: R_X86_64_PC32	__malloc_context+0x3b4
 1aa:	e8 00 00 00 00       	call   1af <malloc_slow+0x1af>
			1ab: R_X86_64_PLT32	__malloc_alloc_meta-0x4
 1af:	48 89 c5             	mov    %rax,%rbp
 1b2:	48 85 c0             	test   %rax,%rax
 1b5:	0f 84 7f 00 00 00    	je     23a <malloc_slow+0x23a>
 1bb:	49 81 e4 00 f0 ff ff 	and    $0xfffffffffffff000,%r12
 1c2:	4c 89 78 10          	mov    %r15,0x10(%rax)
 1c6:	45 31 f6             	xor    %r14d,%r14d
 1c9:	49 81 cc e0 0f 00 00 	or     $0xfe0,%r12
 1d0:	49 89 07             	mov    %rax,(%r15)
 1d3:	45 31 ff             	xor    %r15d,%r15d
 1d6:	4c 89 60 20          	mov    %r12,0x20(%rax)
 1da:	c7 40 1c 00 00 00 00 	movl   $0x0,0x1c(%rax)
 1e1:	c7 40 18 00 00 00 00 	movl   $0x0,0x18(%rax)
 1e8:	8b 05 00 00 00 00    	mov    0x0(%rip),%eax        # 1ee <malloc_slow+0x1ee>
			1ea: R_X86_64_PC32	__malloc_context+0x8
 1ee:	44 8d 60 01          	lea    0x1(%rax),%r12d
 1f2:	44 89 25 00 00 00 00 	mov    %r12d,0x0(%rip)        # 1f9 <malloc_slow+0x1f9>
			1f5: R_X86_64_PC32	__malloc_context+0x8
 1f9:	e9 c5 00 00 00       	jmp    2c3 <malloc_slow+0x2c3>
 1fe:	4c 89 ef             	mov    %r13,%rdi
 201:	e8 00 00 00 00       	call   206 <malloc_slow+0x206>
			202: R_X86_64_PLT32	__lock-0x4
 206:	eb 8e                	jmp    196 <malloc_slow+0x196>
 208:	48 8d 05 00 00 00 00 	lea    0x0(%rip),%rax        # 20f <malloc_slow+0x20f>
			20b: R_X86_64_PC32	__malloc_context+0x374
 20f:	48 8d 50 20          	lea    0x20(%rax),%rdx
 213:	eb 16                	jmp    22b <malloc_slow+0x22b>
 215:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
 21c:	00 00 00 00 
 220:	c6 00 00             	movb   $0x0,(%rax)
 223:	48 83 c0 02          	add    $0x2,%rax
 227:	c6 40 ff 00          	movb   $0x0,-0x1(%rax)
 22b:	48 39 d0             	cmp    %rdx,%rax
 22e:	75 f0                	jne    220 <malloc_slow+0x220>
 230:	ba 01 00 00 00       	mov    $0x1,%edx
 235:	e9 6a ff ff ff       	jmp    1a4 <malloc_slow+0x1a4>
 23a:	8b 05 00 00 00 00    	mov    0x0(%rip),%eax        # 240 <malloc_slow+0x240>
			23c: R_X86_64_PC32	__malloc_lock-0x4
 240:	85 c0                	test   %eax,%eax
 242:	78 10                	js     254 <malloc_slow+0x254>
 244:	4c 89 f6             	mov    %r14,%rsi
 247:	4c 89 ff             	mov    %r15,%rdi
 24a:	e8 00 00 00 00       	call   24f <malloc_slow+0x24f>
			24b: R_X86_64_PLT32	munmap-0x4
 24f:	e9 f8 fe ff ff       	jmp    14c <malloc_slow+0x14c>
 254:	4c 89 ef             	mov    %r13,%rdi
 257:	e8 00 00 00 00       	call   25c <malloc_slow+0x25c>
			258: R_X86_64_PLT32	__unlock-0x4
 25c:	eb e6                	jmp    244 <malloc_slow+0x244>
 25e:	4c 89 ef             	mov    %r13,%rdi
 261:	e8 00 00 00 00       	call   266 <malloc_slow+0x266>
			262: R_X86_64_PLT32	__lock-0x4
 266:	e9 38 fe ff ff       	jmp    a3 <malloc_slow+0xa3>
 26b:	8b 45 1c             	mov    0x1c(%rbp),%eax
 26e:	85 c0                	test   %eax,%eax
 270:	0f 85 93 fe ff ff    	jne    109 <malloc_slow+0x109>
 276:	48 83 c2 03          	add    $0x3,%rdx
 27a:	e9 8a fe ff ff       	jmp    109 <malloc_slow+0x109>
 27f:	48 83 c2 03          	add    $0x3,%rdx
 283:	48 83 fa 0c          	cmp    $0xc,%rdx
 287:	44 0f 46 e1          	cmovbe %ecx,%r12d
 28b:	e9 83 fe ff ff       	jmp    113 <malloc_slow+0x113>
 290:	48 85 ed             	test   %rbp,%rbp
 293:	0f 84 7a fe ff ff    	je     113 <malloc_slow+0x113>
 299:	8b 45 18             	mov    0x18(%rbp),%eax
 29c:	41 89 c6             	mov    %eax,%r14d
 29f:	41 f7 de             	neg    %r14d
 2a2:	41 21 c6             	and    %eax,%r14d
 2a5:	0f 84 68 fe ff ff    	je     113 <malloc_slow+0x113>
 2ab:	44 29 f0             	sub    %r14d,%eax
 2ae:	45 31 ff             	xor    %r15d,%r15d
 2b1:	44 8b 25 00 00 00 00 	mov    0x0(%rip),%r12d        # 2b8 <malloc_slow+0x2b8>
			2b4: R_X86_64_PC32	__malloc_context+0x8
 2b8:	89 45 18             	mov    %eax,0x18(%rbp)
 2bb:	f3 45 0f bc fe       	tzcnt  %r14d,%r15d
 2c0:	4d 89 fe             	mov    %r15,%r14
 2c3:	8b 15 00 00 00 00    	mov    0x0(%rip),%edx        # 2c9 <malloc_slow+0x2c9>
			2c5: R_X86_64_PC32	__malloc_lock-0x4
 2c9:	85 d2                	test   %edx,%edx
 2cb:	78 41                	js     30e <malloc_slow+0x30e>
 2cd:	f6 45 20 1f          	testb  $0x1f,0x20(%rbp)
 2d1:	75 45                	jne    318 <malloc_slow+0x318>
 2d3:	48 81 7d 20 ff 0f 00 	cmpq   $0xfff,0x20(%rbp)
 2da:	00 
 2db:	76 3b                	jbe    318 <malloc_slow+0x318>
 2dd:	48 8b 55 20          	mov    0x20(%rbp),%rdx
 2e1:	48 81 e2 00 f0 ff ff 	and    $0xfffffffffffff000,%rdx
 2e8:	48 83 ea 10          	sub    $0x10,%rdx
 2ec:	eb 46                	jmp    334 <malloc_slow+0x334>
 2ee:	41 89 cc             	mov    %ecx,%r12d
 2f1:	eb a6                	jmp    299 <malloc_slow+0x299>
 2f3:	8b 05 00 00 00 00    	mov    0x0(%rip),%eax        # 2f9 <malloc_slow+0x2f9>
			2f5: R_X86_64_PC32	__malloc_lock-0x4
 2f9:	85 c0                	test   %eax,%eax
 2fb:	0f 89 4b fe ff ff    	jns    14c <malloc_slow+0x14c>
 301:	4c 89 ef             	mov    %r13,%rdi
 304:	e8 00 00 00 00       	call   309 <malloc_slow+0x309>
			305: R_X86_64_PLT32	__unlock-0x4
 309:	e9 3e fe ff ff       	jmp    14c <malloc_slow+0x14c>
 30e:	4c 89 ef             	mov    %r13,%rdi
 311:	e8 00 00 00 00       	call   316 <malloc_slow+0x316>
			312: R_X86_64_PLT32	__unlock-0x4
 316:	eb b5                	jmp    2cd <malloc_slow+0x2cd>
 318:	0f b7 55 20          	movzwl 0x20(%rbp),%edx
 31c:	48 8d 0d 00 00 00 00 	lea    0x0(%rip),%rcx        # 323 <malloc_slow+0x323>
			31f: R_X86_64_PC32	__malloc_size_classes-0x4
 323:	66 c1 ea 06          	shr    $0x6,%dx
 327:	83 e2 3f             	and    $0x3f,%edx
 32a:	0f b7 14 51          	movzwl (%rcx,%rdx,2),%edx
 32e:	c1 e2 04             	shl    $0x4,%edx
 331:	48 63 d2             	movslq %edx,%rdx
 334:	48 89 d1             	mov    %rdx,%rcx
 337:	4c 89 f8             	mov    %r15,%rax
 33a:	48 29 d9             	sub    %rbx,%rcx
 33d:	48 0f af c2          	imul   %rdx,%rax
 341:	48 8d 79 fc          	lea    -0x4(%rcx),%rdi
 345:	48 8b 4d 10          	mov    0x10(%rbp),%rcx
 349:	48 83 c1 10          	add    $0x10,%rcx
 34d:	48 01 c8             	add    %rcx,%rax
 350:	0f b6 70 fc          	movzbl -0x4(%rax),%esi
 354:	4c 8d 44 10 fc       	lea    -0x4(%rax,%rdx,1),%r8
 359:	40 84 f6             	test   %sil,%sil
 35c:	0f 85 00 00 00 00    	jne    362 <malloc_slow+0x362>
			35e: R_X86_64_PC32	.text.unlikely.malloc_slow-0x4
 362:	48 83 ff 0f          	cmp    $0xf,%rdi
 366:	76 7b                	jbe    3e3 <malloc_slow+0x3e3>
 368:	80 78 fd 00          	cmpb   $0x0,-0x3(%rax)
 36c:	41 0f b6 d4          	movzbl %r12b,%edx
 370:	74 0a                	je     37c <malloc_slow+0x37c>
 372:	0f b7 50 fe          	movzwl -0x2(%rax),%edx
 376:	83 c2 01             	add    $0x1,%edx
 379:	0f b6 d2             	movzbl %dl,%edx
 37c:	49 89 fa             	mov    %rdi,%r10
 37f:	4c 63 ca             	movslq %edx,%r9
 382:	49 c1 ea 04          	shr    $0x4,%r10
 386:	4d 39 ca             	cmp    %r9,%r10
 389:	73 37                	jae    3c2 <malloc_slow+0x3c2>
 38b:	48 c1 ef 05          	shr    $0x5,%rdi
 38f:	4c 09 d7             	or     %r10,%rdi
 392:	49 89 f9             	mov    %rdi,%r9
 395:	49 c1 e9 02          	shr    $0x2,%r9
 399:	4c 09 cf             	or     %r9,%rdi
 39c:	49 89 f9             	mov    %rdi,%r9
 39f:	49 c1 e9 04          	shr    $0x4,%r9
 3a3:	4c 09 cf             	or     %r9,%rdi
 3a6:	21 fa                	and    %edi,%edx
 3a8:	48 63 fa             	movslq %edx,%rdi
 3ab:	49 39 fa             	cmp    %rdi,%r10
 3ae:	73 12                	jae    3c2 <malloc_slow+0x3c2>
 3b0:	44 29 d2             	sub    %r10d,%edx
 3b3:	83 ea 01             	sub    $0x1,%edx
 3b6:	48 63 fa             	movslq %edx,%rdi
 3b9:	49 39 fa             	cmp    %rdi,%r10
 3bc:	0f 82 00 00 00 00    	jb     3c2 <malloc_slow+0x3c2>
			3be: R_X86_64_PC32	.text.unlikely.malloc_slow-0x4
 3c2:	85 d2                	test   %edx,%edx
 3c4:	74 1d                	je     3e3 <malloc_slow+0x3e3>
 3c6:	66 89 50 fe          	mov    %dx,-0x2(%rax)
 3ca:	c1 e2 04             	shl    $0x4,%edx
 3cd:	48 63 d2             	movslq %edx,%rdx
 3d0:	c6 40 fd e0          	movb   $0xe0,-0x3(%rax)
 3d4:	48 01 d0             	add    %rdx,%rax
 3d7:	c6 40 fc 00          	movb   $0x0,-0x4(%rax)
 3db:	48 8b 4d 10          	mov    0x10(%rbp),%rcx
 3df:	48 83 c1 10          	add    $0x10,%rcx
 3e3:	48 89 c2             	mov    %rax,%rdx
 3e6:	48 29 ca             	sub    %rcx,%rdx
 3e9:	48 c1 ea 04          	shr    $0x4,%rdx
 3ed:	66 89 50 fe          	mov    %dx,-0x2(%rax)
 3f1:	4c 89 c2             	mov    %r8,%rdx
 3f4:	48 29 c2             	sub    %rax,%rdx
 3f7:	29 da                	sub    %ebx,%edx
 3f9:	74 16                	je     411 <malloc_slow+0x411>
 3fb:	89 d1                	mov    %edx,%ecx
 3fd:	f7 d9                	neg    %ecx
 3ff:	48 63 c9             	movslq %ecx,%rcx
 402:	41 c6 04 08 00       	movb   $0x0,(%r8,%rcx,1)
 407:	83 fa 04             	cmp    $0x4,%edx
 40a:	7f 1b                	jg     427 <malloc_slow+0x427>
 40c:	89 d6                	mov    %edx,%esi
 40e:	c1 e6 05             	shl    $0x5,%esi
 411:	44 01 f6             	add    %r14d,%esi
 414:	40 88 70 fd          	mov    %sil,-0x3(%rax)
 418:	48 83 c4 08          	add    $0x8,%rsp
 41c:	5b                   	pop    %rbx
 41d:	5d                   	pop    %rbp
 41e:	41 5c                	pop    %r12
 420:	41 5d                	pop    %r13
 422:	41 5e                	pop    %r14
 424:	41 5f                	pop    %r15
 426:	c3                   	ret
 427:	41 89 50 fc          	mov    %edx,-0x4(%r8)
 42b:	be a0 ff ff ff       	mov    $0xffffffa0,%esi
 430:	41 c6 40 fb 00       	movb   $0x0,-0x5(%r8)
 435:	eb da                	jmp    411 <malloc_slow+0x411>

Disassembly of section .text.unlikely.__libc_malloc_impl:

0000000000000000 <__libc_malloc_impl.cold>:
   0:	0f 0b                	ud2

Disassembly of section .text.__libc_malloc_impl:

0000000000000000 <__libc_malloc_impl>:
   0:	48 81 ff eb ff 01 00 	cmp    $0x1ffeb,%rdi
   7:	0f 87 9b 02 00 00    	ja     2a8 <__libc_malloc_impl+0x2a8>
   d:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 14 <__libc_malloc_impl+0x14>
			10: R_X86_64_PC32	__libc-0x1
  14:	84 c0                	test   %al,%al
  16:	0f 85 8c 02 00 00    	jne    2a8 <__libc_malloc_impl+0x2a8>
  1c:	8b 05 00 00 00 00    	mov    0x0(%rip),%eax        # 22 <__libc_malloc_impl+0x22>
			1e: R_X86_64_PC32	__malloc_lock-0x4
  22:	85 c0                	test   %eax,%eax
  24:	0f 85 7e 02 00 00    	jne    2a8 <__libc_malloc_impl+0x2a8>
  2a:	48 8d 47 03          	lea    0x3(%rdi),%rax
  2e:	48 89 c2             	mov    %rax,%rdx
  31:	48 c1 ea 04          	shr    $0x4,%rdx
  35:	48 63 ca             	movslq %edx,%rcx
  38:	48 3d 9f 00 00 00    	cmp    $0x9f,%rax
  3e:	76 3c                	jbe    7c <__libc_malloc_impl+0x7c>
  40:	48 83 c2 01          	add    $0x1,%rdx
  44:	48 8d 35 00 00 00 00 	lea    0x0(%rip),%rsi        # 4b <__libc_malloc_impl+0x4b>
			47: R_X86_64_PC32	__malloc_size_classes-0x4
  4b:	0f bd c2             	bsr    %edx,%eax
  4e:	8d 04 85 fc ff ff ff 	lea    -0x4(,%rax,4),%eax
  55:	8d 48 01             	lea    0x1(%rax),%ecx
  58:	48 63 c9             	movslq %ecx,%rcx
  5b:	44 0f b7 04 4e       	movzwl (%rsi,%rcx,2),%r8d
  60:	8d 48 02             	lea    0x2(%rax),%ecx
  63:	49 39 d0             	cmp    %rdx,%r8
  66:	0f 42 c1             	cmovb  %ecx,%eax
  69:	48 63 c8             	movslq %eax,%rcx
  6c:	83 c0 01             	add    $0x1,%eax
  6f:	0f b7 34 4e          	movzwl (%rsi,%rcx,2),%esi
  73:	48 98                	cltq
  75:	48 39 d6             	cmp    %rdx,%rsi
  78:	48 0f 42 c8          	cmovb  %rax,%rcx
  7c:	48 8d 35 00 00 00 00 	lea    0x0(%rip),%rsi        # 83 <__libc_malloc_impl+0x83>
			7f: R_X86_64_PC32	__malloc_context-0x4
  83:	48 8b 54 ce 50       	mov    0x50(%rsi,%rcx,8),%rdx
  88:	48 85 d2             	test   %rdx,%rdx
  8b:	0f 84 17 02 00 00    	je     2a8 <__libc_malloc_impl+0x2a8>
  91:	55                   	push   %rbp
  92:	53                   	push   %rbx
  93:	8b 42 18             	mov    0x18(%rdx),%eax
  96:	85 c0                	test   %eax,%eax
  98:	0f 85 93 00 00 00    	jne    131 <__libc_malloc_impl+0x131>
  9e:	48 39 52 08          	cmp    %rdx,0x8(%rdx)
  a2:	74 07                	je     ab <__libc_malloc_impl+0xab>
  a4:	5b                   	pop    %rbx
  a5:	5d                   	pop    %rbp
  a6:	e9 00 00 00 00       	jmp    ab <__libc_malloc_impl+0xab>
			a7: R_X86_64_PC32	.text.malloc_slow-0x4
  ab:	48 8b 42 10          	mov    0x10(%rdx),%rax
  af:	44 8b 42 1c          	mov    0x1c(%rdx),%r8d
  b3:	0f b6 48 08          	movzbl 0x8(%rax),%ecx
  b7:	b8 02 00 00 00       	mov    $0x2,%eax
  bc:	d3 e0                	shl    %cl,%eax
  be:	8d 48 ff             	lea    -0x1(%rax),%ecx
  c1:	41 85 c8             	test   %ecx,%r8d
  c4:	74 de                	je     a4 <__libc_malloc_impl+0xa4>
  c6:	44 8b 42 18          	mov    0x18(%rdx),%r8d
  ca:	45 85 c0             	test   %r8d,%r8d
  cd:	0f 85 00 00 00 00    	jne    d3 <__libc_malloc_impl+0xd3>
			cf: R_X86_64_PC32	.text.unlikely.__libc_malloc_impl-0x4
  d3:	44 0f b6 05 00 00 00 	movzbl 0x0(%rip),%r8d        # db <__libc_malloc_impl+0xdb>
  da:	00 
			d7: R_X86_64_PC32	__libc-0x1
  db:	f7 d8                	neg    %eax
  dd:	4c 8d 5a 1c          	lea    0x1c(%rdx),%r11
  e1:	41 89 c2             	mov    %eax,%r10d
  e4:	45 84 c0             	test   %r8b,%r8b
  e7:	75 78                	jne    161 <__libc_malloc_impl+0x161>
  e9:	44 8b 42 1c          	mov    0x1c(%rdx),%r8d
  ed:	44 21 c0             	and    %r8d,%eax
  f0:	89 42 1c             	mov    %eax,0x1c(%rdx)
  f3:	89 c8                	mov    %ecx,%eax
  f5:	44 21 c0             	and    %r8d,%eax
  f8:	89 42 18             	mov    %eax,0x18(%rdx)
  fb:	0f 84 00 00 00 00    	je     101 <__libc_malloc_impl+0x101>
			fd: R_X86_64_PC32	.text.unlikely.__libc_malloc_impl-0x4
 101:	0f b7 4a 20          	movzwl 0x20(%rdx),%ecx
 105:	66 c1 e9 06          	shr    $0x6,%cx
 109:	83 e1 3f             	and    $0x3f,%ecx
 10c:	83 e9 07             	sub    $0x7,%ecx
 10f:	83 f9 1f             	cmp    $0x1f,%ecx
 112:	77 1d                	ja     131 <__libc_malloc_impl+0x131>
 114:	48 63 c9             	movslq %ecx,%rcx
 117:	44 0f b6 84 0e 98 03 	movzbl 0x398(%rsi,%rcx,1),%r8d
 11e:	00 00 
 120:	45 84 c0             	test   %r8b,%r8b
 123:	74 0c                	je     131 <__libc_malloc_impl+0x131>
 125:	41 83 e8 01          	sub    $0x1,%r8d
 129:	44 88 84 0e 98 03 00 	mov    %r8b,0x398(%rsi,%rcx,1)
 130:	00 
 131:	89 c1                	mov    %eax,%ecx
 133:	f7 d9                	neg    %ecx
 135:	21 c1                	and    %eax,%ecx
 137:	29 c8                	sub    %ecx,%eax
 139:	f3 0f bc c9          	tzcnt  %ecx,%ecx
 13d:	89 42 18             	mov    %eax,0x18(%rdx)
 140:	f6 42 20 1f          	testb  $0x1f,0x20(%rdx)
 144:	75 37                	jne    17d <__libc_malloc_impl+0x17d>
 146:	48 81 7a 20 ff 0f 00 	cmpq   $0xfff,0x20(%rdx)
 14d:	00 
 14e:	76 2d                	jbe    17d <__libc_malloc_impl+0x17d>
 150:	48 8b 72 20          	mov    0x20(%rdx),%rsi
 154:	48 81 e6 00 f0 ff ff 	and    $0xfffffffffffff000,%rsi
 15b:	48 83 ee 10          	sub    $0x10,%rsi
 15f:	eb 38                	jmp    199 <__libc_malloc_impl+0x199>
 161:	44 8b 42 1c          	mov    0x1c(%rdx),%r8d
 165:	45 89 c1             	mov    %r8d,%r9d
 168:	44 89 c0             	mov    %r8d,%eax
 16b:	45 21 d1             	and    %r10d,%r9d
 16e:	f0 45 0f b1 0b       	lock cmpxchg %r9d,(%r11)
 173:	41 39 c0             	cmp    %eax,%r8d
 176:	75 e9                	jne    161 <__libc_malloc_impl+0x161>
 178:	e9 76 ff ff ff       	jmp    f3 <__libc_malloc_impl+0xf3>
 17d:	0f b7 42 20          	movzwl 0x20(%rdx),%eax
 181:	48 8d 35 00 00 00 00 	lea    0x0(%rip),%rsi        # 188 <__libc_malloc_impl+0x188>
			184: R_X86_64_PC32	__malloc_size_classes-0x4
 188:	66 c1 e8 06          	shr    $0x6,%ax
 18c:	83 e0 3f             	and    $0x3f,%eax
 18f:	0f b7 34 46          	movzwl (%rsi,%rax,2),%esi
 193:	c1 e6 04             	shl    $0x4,%esi
 196:	48 63 f6             	movslq %esi,%rsi
 199:	48 89 f0             	mov    %rsi,%rax
 19c:	4c 8b 42 10          	mov    0x10(%rdx),%r8
 1a0:	48 29 f8             	sub    %rdi,%rax
 1a3:	4c 8d 48 fc          	lea    -0x4(%rax),%r9
 1a7:	48 63 c1             	movslq %ecx,%rax
 1aa:	49 83 c0 10          	add    $0x10,%r8
 1ae:	48 0f af c6          	imul   %rsi,%rax
 1b2:	4c 01 c0             	add    %r8,%rax
 1b5:	4c 8d 5c 30 fc       	lea    -0x4(%rax,%rsi,1),%r11
 1ba:	0f b6 70 fc          	movzbl -0x4(%rax),%esi
 1be:	40 84 f6             	test   %sil,%sil
 1c1:	0f 85 00 00 00 00    	jne    1c7 <__libc_malloc_impl+0x1c7>
			1c3: R_X86_64_PC32	.text.unlikely.__libc_malloc_impl-0x4
 1c7:	49 83 f9 0f          	cmp    $0xf,%r9
 1cb:	0f 86 83 00 00 00    	jbe    254 <__libc_malloc_impl+0x254>
 1d1:	80 78 fd 00          	cmpb   $0x0,-0x3(%rax)
 1d5:	0f 84 b0 00 00 00    	je     28b <__libc_malloc_impl+0x28b>
 1db:	44 0f b7 50 fe       	movzwl -0x2(%rax),%r10d
 1e0:	41 83 c2 01          	add    $0x1,%r10d
 1e4:	45 0f b6 d2          	movzbl %r10b,%r10d
 1e8:	4c 89 cd             	mov    %r9,%rbp
 1eb:	49 63 da             	movslq %r10d,%rbx
 1ee:	48 c1 ed 04          	shr    $0x4,%rbp
 1f2:	48 39 dd             	cmp    %rbx,%rbp
 1f5:	73 39                	jae    230 <__libc_malloc_impl+0x230>
 1f7:	49 c1 e9 05          	shr    $0x5,%r9
 1fb:	49 09 e9             	or     %rbp,%r9
 1fe:	4c 89 cb             	mov    %r9,%rbx
 201:	48 c1 eb 02          	shr    $0x2,%rbx
 205:	49 09 d9             	or     %rbx,%r9
 208:	4c 89 cb             	mov    %r9,%rbx
 20b:	48 c1 eb 04          	shr    $0x4,%rbx
 20f:	49 09 d9             	or     %rbx,%r9
 212:	45 21 ca             	and    %r9d,%r10d
 215:	4d 63 ca             	movslq %r10d,%r9
 218:	4c 39 cd             	cmp    %r9,%rbp
 21b:	73 13                	jae    230 <__libc_malloc_impl+0x230>
 21d:	41 29 ea             	sub    %ebp,%r10d
 220:	41 83 ea 01          	sub    $0x1,%r10d
 224:	4d 63 ca             	movslq %r10d,%r9
 227:	4c 39 cd             	cmp    %r9,%rbp
 22a:	0f 82 00 00 00 00    	jb     230 <__libc_malloc_impl+0x230>
			22c: R_X86_64_PC32	.text.unlikely.__libc_malloc_impl-0x4
 230:	45 85 d2             	test   %r10d,%r10d
 233:	74 1f                	je     254 <__libc_malloc_impl+0x254>
 235:	66 44 89 50 fe       	mov    %r10w,-0x2(%rax)
 23a:	41 c1 e2 04          	shl    $0x4,%r10d
 23e:	4d 63 c2             	movslq %r10d,%r8
 241:	c6 40 fd e0          	movb   $0xe0,-0x3(%rax)
 245:	4c 01 c0             	add    %r8,%rax
 248:	c6 40 fc 00          	movb   $0x0,-0x4(%rax)
 24c:	4c 8b 42 10          	mov    0x10(%rdx),%r8
 250:	49 83 c0 10          	add    $0x10,%r8
 254:	48 89 c2             	mov    %rax,%rdx
 257:	4c 29 c2             	sub    %r8,%rdx
 25a:	48 c1 ea 04          	shr    $0x4,%rdx
 25e:	66 89 50 fe          	mov    %dx,-0x2(%rax)
 262:	4c 89 da             	mov    %r11,%rdx
 265:	48 29 c2             	sub    %rax,%rdx
 268:	29 fa                	sub    %edi,%edx
 26a:	74 16                	je     282 <__libc_malloc_impl+0x282>
 26c:	89 d6                	mov    %edx,%esi
 26e:	f7 de                	neg    %esi
 270:	48 63 f6             	movslq %esi,%rsi
 273:	41 c6 04 33 00       	movb   $0x0,(%r11,%rsi,1)
 278:	83 fa 04             	cmp    $0x4,%edx
 27b:	7f 1b                	jg     298 <__libc_malloc_impl+0x298>
 27d:	89 d6                	mov    %edx,%esi
 27f:	c1 e6 05             	shl    $0x5,%esi
 282:	01 ce                	add    %ecx,%esi
 284:	40 88 70 fd          	mov    %sil,-0x3(%rax)
 288:	5b                   	pop    %rbx
 289:	5d                   	pop    %rbp
 28a:	c3                   	ret
 28b:	44 0f b6 15 00 00 00 	movzbl 0x0(%rip),%r10d        # 293 <__libc_malloc_impl+0x293>
 292:	00 
			28f: R_X86_64_PC32	__malloc_context+0x8
 293:	e9 50 ff ff ff       	jmp    1e8 <__libc_malloc_impl+0x1e8>
 298:	41 89 53 fc          	mov    %edx,-0x4(%r11)
 29c:	be a0 ff ff ff       	mov    $0xffffffa0,%esi
 2a1:	41 c6 43 fb 00       	movb   $0x0,-0x5(%r11)
 2a6:	eb da                	jmp    282 <__libc_malloc_impl+0x282>
 2a8:	e9 00 00 00 00       	jmp    2ad <__libc_malloc_impl+0x2ad>
			2a9: R_X86_64_PC32	.text.malloc_slow-0x4

Disassembly of section .text.unlikely.__malloc_allzerop:

0000000000000000 <__malloc_allzerop.cold>:
   0:	0f 0b                	ud2

Disassembly of section .text.__malloc_allzerop:

0000000000000000 <__malloc_allzerop>:
   0:	40 f6 c7 0f          	test   $0xf,%dil
   4:	0f 85 00 00 00 00    	jne    a <__malloc_allzerop+0xa>
			6: R_X86_64_PC32	.text.unlikely.__malloc_allzerop-0x4
   a:	0f b6 57 fd          	movzbl -0x3(%rdi),%edx
   e:	0f b7 4f fe          	movzwl -0x2(%rdi),%ecx
  12:	41 89 d0             	mov    %edx,%r8d
  15:	41 89 d1             	mov    %edx,%r9d
  18:	41 83 e0 1f          	and    $0x1f,%r8d
  1c:	41 83 e1 1f          	and    $0x1f,%r9d
  20:	80 7f fc 00          	cmpb   $0x0,-0x4(%rdi)
  24:	74 18                	je     3e <__malloc_allzerop+0x3e>
  26:	85 c9                	test   %ecx,%ecx
  28:	0f 85 00 00 00 00    	jne    2e <__malloc_allzerop+0x2e>
			2a: R_X86_64_PC32	.text.unlikely.__malloc_allzerop-0x4
  2e:	48 63 4f f8          	movslq -0x8(%rdi),%rcx
  32:	81 f9 ff ff 00 00    	cmp    $0xffff,%ecx
  38:	0f 8e 00 00 00 00    	jle    3e <__malloc_allzerop+0x3e>
			3a: R_X86_64_PC32	.text.unlikely.__malloc_allzerop-0x4
  3e:	89 c8                	mov    %ecx,%eax
  40:	c1 e0 04             	shl    $0x4,%eax
  43:	48 98                	cltq
  45:	48 29 c7             	sub    %rax,%rdi
  48:	48 8b 47 f0          	mov    -0x10(%rdi),%rax
  4c:	48 8d 77 f0          	lea    -0x10(%rdi),%rsi
  50:	48 3b 70 10          	cmp    0x10(%rax),%rsi
  54:	0f 85 00 00 00 00    	jne    5a <__malloc_allzerop+0x5a>
			56: R_X86_64_PC32	.text.unlikely.__malloc_allzerop-0x4
  5a:	0f b6 70 20          	movzbl 0x20(%rax),%esi
  5e:	89 f2                	mov    %esi,%edx
  60:	89 f7                	mov    %esi,%edi
  62:	83 e2 1f             	and    $0x1f,%edx
  65:	83 e7 1f             	and    $0x1f,%edi
  68:	41 39 d1             	cmp    %edx,%r9d
  6b:	0f 8f 00 00 00 00    	jg     71 <__malloc_allzerop+0x71>
			6d: R_X86_64_PC32	.text.unlikely.__malloc_allzerop-0x4
  71:	8b 50 18             	mov    0x18(%rax),%edx
  74:	44 0f a3 c2          	bt     %r8d,%edx
  78:	0f 82 00 00 00 00    	jb     7e <__malloc_allzerop+0x7e>
			7a: R_X86_64_PC32	.text.unlikely.__malloc_allzerop-0x4
  7e:	8b 50 1c             	mov    0x1c(%rax),%edx
  81:	44 0f a3 c2          	bt     %r8d,%edx
  85:	0f 82 00 00 00 00    	jb     8b <__malloc_allzerop+0x8b>
			87: R_X86_64_PC32	.text.unlikely.__malloc_allzerop-0x4
  8b:	48 89 c2             	mov    %rax,%rdx
  8e:	4c 8b 15 00 00 00 00 	mov    0x0(%rip),%r10        # 95 <__malloc_allzerop+0x95>
			91: R_X86_64_PC32	__malloc_context-0x4
  95:	48 81 e2 00 f0 ff ff 	and    $0xfffffffffffff000,%rdx
  9c:	4c 39 12             	cmp    %r10,(%rdx)
  9f:	0f 85 00 00 00 00    	jne    a5 <__malloc_allzerop+0xa5>
			a1: R_X86_64_PC32	.text.unlikely.__malloc_allzerop-0x4
  a5:	0f b7 50 20          	movzwl 0x20(%rax),%edx
  a9:	66 c1 ea 06          	shr    $0x6,%dx
  ad:	83 e2 3f             	and    $0x3f,%edx
  b0:	83 fa 2f             	cmp    $0x2f,%edx
  b3:	7f 52                	jg     107 <__malloc_allzerop+0x107>
  b5:	48 8d 3d 00 00 00 00 	lea    0x0(%rip),%rdi        # bc <__malloc_allzerop+0xbc>
			b8: R_X86_64_PC32	__malloc_size_classes-0x4
  bc:	0f b7 3c 57          	movzwl (%rdi,%rdx,2),%edi
  c0:	44 89 ca             	mov    %r9d,%edx
  c3:	0f af d7             	imul   %edi,%edx
  c6:	39 d1                	cmp    %edx,%ecx
  c8:	0f 8c 00 00 00 00    	jl     ce <__malloc_allzerop+0xce>
			ca: R_X86_64_PC32	.text.unlikely.__malloc_allzerop-0x4
  ce:	01 fa                	add    %edi,%edx
  d0:	39 d1                	cmp    %edx,%ecx
  d2:	0f 8d 00 00 00 00    	jge    d8 <__malloc_allzerop+0xd8>
			d4: R_X86_64_PC32	.text.unlikely.__malloc_allzerop-0x4
  d8:	48 8b 50 20          	mov    0x20(%rax),%rdx
  dc:	48 c1 ea 0c          	shr    $0xc,%rdx
  e0:	75 57                	jne    139 <__malloc_allzerop+0x139>
  e2:	31 c9                	xor    %ecx,%ecx
  e4:	83 e6 1f             	and    $0x1f,%esi
  e7:	75 4d                	jne    136 <__malloc_allzerop+0x136>
  e9:	48 81 78 20 ff 0f 00 	cmpq   $0xfff,0x20(%rax)
  f0:	00 
  f1:	76 43                	jbe    136 <__malloc_allzerop+0x136>
  f3:	c1 e7 04             	shl    $0x4,%edi
  f6:	48 83 ea 10          	sub    $0x10,%rdx
  fa:	31 c9                	xor    %ecx,%ecx
  fc:	48 63 ff             	movslq %edi,%rdi
  ff:	48 39 fa             	cmp    %rdi,%rdx
 102:	0f 92 c1             	setb   %cl
 105:	eb 2f                	jmp    136 <__malloc_allzerop+0x136>
 107:	83 fa 3f             	cmp    $0x3f,%edx
 10a:	0f 85 00 00 00 00    	jne    110 <__malloc_allzerop+0x110>
			10c: R_X86_64_PC32	.text.unlikely.__malloc_allzerop-0x4
 110:	40 84 ff             	test   %dil,%dil
 113:	0f 85 00 00 00 00    	jne    119 <__malloc_allzerop+0x119>
			115: R_X86_64_PC32	.text.unlikely.__malloc_allzerop-0x4
 119:	48 81 78 20 ff 0f 00 	cmpq   $0xfff,0x20(%rax)
 120:	00 
 121:	0f 86 00 00 00 00    	jbe    127 <__malloc_allzerop+0x127>
			123: R_X86_64_PC32	.text.unlikely.__malloc_allzerop-0x4
 127:	48 8b 40 20          	mov    0x20(%rax),%rax
 12b:	48 c1 e8 0c          	shr    $0xc,%rax
 12f:	75 21                	jne    152 <__malloc_allzerop+0x152>
 131:	b9 01 00 00 00       	mov    $0x1,%ecx
 136:	89 c8                	mov    %ecx,%eax
 138:	c3                   	ret
 139:	48 c1 e2 0c          	shl    $0xc,%rdx
 13d:	49 89 d0             	mov    %rdx,%r8
 140:	49 c1 e8 04          	shr    $0x4,%r8
 144:	49 83 e8 01          	sub    $0x1,%r8
 148:	49 39 c8             	cmp    %rcx,%r8
 14b:	73 95                	jae    e2 <__malloc_allzerop+0xe2>
 14d:	e9 00 00 00 00       	jmp    152 <__malloc_allzerop+0x152>
			14e: R_X86_64_PC32	.text.unlikely.__malloc_allzerop-0x4
 152:	48 c1 e0 08          	shl    $0x8,%rax
 156:	48 8d 50 ff          	lea    -0x1(%rax),%rdx
 15a:	48 63 c1             	movslq %ecx,%rax
 15d:	48 39 c2             	cmp    %rax,%rdx
 160:	0f 82 00 00 00 00    	jb     166 <__malloc_allzerop+0x166>
			162: R_X86_64_PC32	.text.unlikely.__malloc_allzerop-0x4
 166:	eb c9                	jmp    131 <__malloc_allzerop+0x131>

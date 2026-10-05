
/Users/alex/code/vinix/third_party/useralloc-libc/build/useralloc/v6-prototype/cache/x86_64/de81a5feb72ae379cc45ec4a46be7ac78b7342fd74a987fc527187b69fe7fdaa/objects/obj/src/malloc/mallocng/malloc.lo:     file format elf64-x86-64


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
   e:	41 55                	push   %r13
  10:	49 8d 46 0a          	lea    0xa(%r14),%rax
  14:	4d 89 f5             	mov    %r14,%r13
  17:	41 54                	push   %r12
  19:	55                   	push   %rbp
  1a:	53                   	push   %rbx
  1b:	48 83 ec 38          	sub    $0x38,%rsp
  1f:	49 8b 14 c7          	mov    (%r15,%rax,8),%rdx
  23:	48 85 d2             	test   %rdx,%rdx
  26:	74 4f                	je     77 <alloc_slot+0x77>
  28:	8b 4a 18             	mov    0x18(%rdx),%ecx
  2b:	85 c9                	test   %ecx,%ecx
  2d:	0f 85 c6 01 00 00    	jne    1f9 <alloc_slot+0x1f9>
  33:	8b 7a 1c             	mov    0x1c(%rdx),%edi
  36:	48 8b 4a 08          	mov    0x8(%rdx),%rcx
  3a:	85 ff                	test   %edi,%edi
  3c:	0f 85 e8 00 00 00    	jne    12a <alloc_slot+0x12a>
  42:	48 39 ca             	cmp    %rcx,%rdx
  45:	0f 84 d2 00 00 00    	je     11d <alloc_slot+0x11d>
  4b:	48 8b 3a             	mov    (%rdx),%rdi
  4e:	48 89 4f 08          	mov    %rcx,0x8(%rdi)
  52:	48 8b 3a             	mov    (%rdx),%rdi
  55:	48 89 39             	mov    %rdi,(%rcx)
  58:	49 3b 14 c7          	cmp    (%r15,%rax,8),%rdx
  5c:	0f 84 ae 00 00 00    	je     110 <alloc_slot+0x110>
  62:	66 0f ef c0          	pxor   %xmm0,%xmm0
  66:	0f 11 02             	movups %xmm0,(%rdx)
  69:	4b 8b 54 f7 50       	mov    0x50(%r15,%r14,8),%rdx
  6e:	48 85 d2             	test   %rdx,%rdx
  71:	0f 85 ba 00 00 00    	jne    131 <alloc_slot+0x131>
  77:	4c 8d 05 00 00 00 00 	lea    0x0(%rip),%r8        # 7e <alloc_slot+0x7e>
			7a: R_X86_64_PC32	__malloc_size_classes-0x4
  7e:	48 89 74 24 08       	mov    %rsi,0x8(%rsp)
  83:	47 0f b7 24 70       	movzwl (%r8,%r14,2),%r12d
  88:	e8 00 00 00 00       	call   8d <alloc_slot+0x8d>
			89: R_X86_64_PLT32	__malloc_alloc_meta-0x4
  8d:	66 48 0f 6e c8       	movq   %rax,%xmm1
  92:	41 c1 e4 04          	shl    $0x4,%r12d
  96:	48 89 c5             	mov    %rax,%rbp
  99:	66 0f 6c c9          	punpcklqdq %xmm1,%xmm1
  9d:	4d 63 e4             	movslq %r12d,%r12
  a0:	0f 29 4c 24 10       	movaps %xmm1,0x10(%rsp)
  a5:	48 85 c0             	test   %rax,%rax
  a8:	0f 84 b0 07 00 00    	je     85e <alloc_slot+0x85e>
  ae:	41 83 fd 08          	cmp    $0x8,%r13d
  b2:	4b 8b 8c f7 f8 01 00 	mov    0x1f8(%r15,%r14,8),%rcx
  b9:	00 
  ba:	48 8b 74 24 08       	mov    0x8(%rsp),%rsi
  bf:	4c 8d 05 00 00 00 00 	lea    0x0(%rip),%r8        # c6 <alloc_slot+0xc6>
			c2: R_X86_64_PC32	__malloc_size_classes-0x4
  c6:	0f 8f 0a 02 00 00    	jg     2d6 <alloc_slot+0x2d6>
  cc:	4b 8d 14 76          	lea    (%r14,%r14,2),%rdx
  d0:	48 8d 05 00 00 00 00 	lea    0x0(%rip),%rax        # d7 <alloc_slot+0xd7>
			d3: R_X86_64_PC32	.rodata.small_cnt_tab-0x4
  d7:	48 01 d0             	add    %rdx,%rax
  da:	0f b6 18             	movzbl (%rax),%ebx
  dd:	8d 14 9d 00 00 00 00 	lea    0x0(,%rbx,4),%edx
  e4:	48 63 d2             	movslq %edx,%rdx
  e7:	48 39 d1             	cmp    %rdx,%rcx
  ea:	0f 83 41 02 00 00    	jae    331 <alloc_slot+0x331>
  f0:	0f b6 58 01          	movzbl 0x1(%rax),%ebx
  f4:	8d 14 9d 00 00 00 00 	lea    0x0(,%rbx,4),%edx
  fb:	48 63 d2             	movslq %edx,%rdx
  fe:	48 39 d1             	cmp    %rdx,%rcx
 101:	0f 83 2a 02 00 00    	jae    331 <alloc_slot+0x331>
 107:	0f b6 58 02          	movzbl 0x2(%rax),%ebx
 10b:	e9 21 02 00 00       	jmp    331 <alloc_slot+0x331>
 110:	48 8b 4a 08          	mov    0x8(%rdx),%rcx
 114:	49 89 0c c7          	mov    %rcx,(%r15,%rax,8)
 118:	e9 45 ff ff ff       	jmp    62 <alloc_slot+0x62>
 11d:	49 c7 04 c7 00 00 00 	movq   $0x0,(%r15,%rax,8)
 124:	00 
 125:	e9 38 ff ff ff       	jmp    62 <alloc_slot+0x62>
 12a:	49 89 0c c7          	mov    %rcx,(%r15,%rax,8)
 12e:	48 89 ca             	mov    %rcx,%rdx
 131:	0f b6 4a 20          	movzbl 0x20(%rdx),%ecx
 135:	b8 02 00 00 00       	mov    $0x2,%eax
 13a:	44 8b 42 1c          	mov    0x1c(%rdx),%r8d
 13e:	d3 e0                	shl    %cl,%eax
 140:	83 e8 01             	sub    $0x1,%eax
 143:	41 39 c0             	cmp    %eax,%r8d
 146:	0f 84 d3 00 00 00    	je     21f <alloc_slot+0x21f>
 14c:	48 8b 7a 10          	mov    0x10(%rdx),%rdi
 150:	b8 02 00 00 00       	mov    $0x2,%eax
 155:	0f b6 4f 08          	movzbl 0x8(%rdi),%ecx
 159:	d3 e0                	shl    %cl,%eax
 15b:	41 89 ca             	mov    %ecx,%r10d
 15e:	83 e8 01             	sub    $0x1,%eax
 161:	41 83 e2 1f          	and    $0x1f,%r10d
 165:	44 85 c0             	test   %r8d,%eax
 168:	75 15                	jne    17f <alloc_slot+0x17f>
 16a:	4c 8b 4a 08          	mov    0x8(%rdx),%r9
 16e:	4c 39 ca             	cmp    %r9,%rdx
 171:	0f 84 c3 00 00 00    	je     23a <alloc_slot+0x23a>
 177:	4f 89 4c f7 50       	mov    %r9,0x50(%r15,%r14,8)
 17c:	4c 89 ca             	mov    %r9,%rdx
 17f:	8b 42 18             	mov    0x18(%rdx),%eax
 182:	85 c0                	test   %eax,%eax
 184:	0f 85 00 00 00 00    	jne    18a <alloc_slot+0x18a>
			186: R_X86_64_PC32	.text.unlikely.alloc_slot-0x4
 18a:	48 8b 42 10          	mov    0x10(%rdx),%rax
 18e:	41 b9 02 00 00 00    	mov    $0x2,%r9d
 194:	4c 8d 52 1c          	lea    0x1c(%rdx),%r10
 198:	0f b6 48 08          	movzbl 0x8(%rax),%ecx
 19c:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 1a3 <alloc_slot+0x1a3>
			19f: R_X86_64_PC32	__libc-0x1
 1a3:	41 d3 e1             	shl    %cl,%r9d
 1a6:	45 8d 41 ff          	lea    -0x1(%r9),%r8d
 1aa:	41 f7 d9             	neg    %r9d
 1ad:	84 c0                	test   %al,%al
 1af:	0f 85 09 01 00 00    	jne    2be <alloc_slot+0x2be>
 1b5:	8b 4a 1c             	mov    0x1c(%rdx),%ecx
 1b8:	41 21 c9             	and    %ecx,%r9d
 1bb:	44 89 4a 1c          	mov    %r9d,0x1c(%rdx)
 1bf:	44 21 c1             	and    %r8d,%ecx
 1c2:	89 4a 18             	mov    %ecx,0x18(%rdx)
 1c5:	0f 84 00 00 00 00    	je     1cb <alloc_slot+0x1cb>
			1c7: R_X86_64_PC32	.text.unlikely.alloc_slot-0x4
 1cb:	0f b7 42 20          	movzwl 0x20(%rdx),%eax
 1cf:	66 c1 e8 06          	shr    $0x6,%ax
 1d3:	83 e0 3f             	and    $0x3f,%eax
 1d6:	83 e8 07             	sub    $0x7,%eax
 1d9:	83 f8 1f             	cmp    $0x1f,%eax
 1dc:	77 1b                	ja     1f9 <alloc_slot+0x1f9>
 1de:	48 98                	cltq
 1e0:	41 0f b6 bc 07 98 03 	movzbl 0x398(%r15,%rax,1),%edi
 1e7:	00 00 
 1e9:	40 84 ff             	test   %dil,%dil
 1ec:	74 0b                	je     1f9 <alloc_slot+0x1f9>
 1ee:	83 ef 01             	sub    $0x1,%edi
 1f1:	41 88 bc 07 98 03 00 	mov    %dil,0x398(%r15,%rax,1)
 1f8:	00 
 1f9:	89 c8                	mov    %ecx,%eax
 1fb:	f7 d8                	neg    %eax
 1fd:	21 c8                	and    %ecx,%eax
 1ff:	29 c1                	sub    %eax,%ecx
 201:	89 4a 18             	mov    %ecx,0x18(%rdx)
 204:	85 c0                	test   %eax,%eax
 206:	0f 84 6b fe ff ff    	je     77 <alloc_slot+0x77>
 20c:	f3 0f bc c0          	tzcnt  %eax,%eax
 210:	48 83 c4 38          	add    $0x38,%rsp
 214:	5b                   	pop    %rbx
 215:	5d                   	pop    %rbp
 216:	41 5c                	pop    %r12
 218:	41 5d                	pop    %r13
 21a:	41 5e                	pop    %r14
 21c:	41 5f                	pop    %r15
 21e:	c3                   	ret
 21f:	83 e1 20             	and    $0x20,%ecx
 222:	0f 84 57 ff ff ff    	je     17f <alloc_slot+0x17f>
 228:	48 8b 52 08          	mov    0x8(%rdx),%rdx
 22c:	4b 89 54 f7 50       	mov    %rdx,0x50(%r15,%r14,8)
 231:	44 8b 42 1c          	mov    0x1c(%rdx),%r8d
 235:	e9 12 ff ff ff       	jmp    14c <alloc_slot+0x14c>
 23a:	41 0f b7 41 20       	movzwl 0x20(%r9),%eax
 23f:	48 8d 15 00 00 00 00 	lea    0x0(%rip),%rdx        # 246 <alloc_slot+0x246>
			242: R_X86_64_PC32	__malloc_size_classes-0x4
 246:	41 8d 4a 02          	lea    0x2(%r10),%ecx
 24a:	66 c1 e8 06          	shr    $0x6,%ax
 24e:	83 e0 3f             	and    $0x3f,%eax
 251:	44 0f b7 14 42       	movzwl (%rdx,%rax,2),%r10d
 256:	89 ca                	mov    %ecx,%edx
 258:	41 c1 e2 04          	shl    $0x4,%r10d
 25c:	41 0f af d2          	imul   %r10d,%edx
 260:	83 c2 10             	add    $0x10,%edx
 263:	eb 21                	jmp    286 <alloc_slot+0x286>
 265:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
 26c:	00 00 00 00 
 270:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
 277:	00 00 00 00 
 27b:	0f 1f 44 00 00       	nopl   0x0(%rax,%rax,1)
 280:	83 c1 01             	add    $0x1,%ecx
 283:	44 89 c2             	mov    %r8d,%edx
 286:	45 8d 04 12          	lea    (%r10,%rdx,1),%r8d
 28a:	41 8d 40 ff          	lea    -0x1(%r8),%eax
 28e:	31 d0                	xor    %edx,%eax
 290:	3d ff 0f 00 00       	cmp    $0xfff,%eax
 295:	7e e9                	jle    280 <alloc_slot+0x280>
 297:	41 0f b6 41 20       	movzbl 0x20(%r9),%eax
 29c:	0f b6 57 08          	movzbl 0x8(%rdi),%edx
 2a0:	83 e0 1f             	and    $0x1f,%eax
 2a3:	83 c0 01             	add    $0x1,%eax
 2a6:	39 c8                	cmp    %ecx,%eax
 2a8:	0f 4f c1             	cmovg  %ecx,%eax
 2ab:	83 e2 e0             	and    $0xffffffe0,%edx
 2ae:	83 e8 01             	sub    $0x1,%eax
 2b1:	83 e0 1f             	and    $0x1f,%eax
 2b4:	09 d0                	or     %edx,%eax
 2b6:	88 47 08             	mov    %al,0x8(%rdi)
 2b9:	e9 be fe ff ff       	jmp    17c <alloc_slot+0x17c>
 2be:	8b 4a 1c             	mov    0x1c(%rdx),%ecx
 2c1:	89 cf                	mov    %ecx,%edi
 2c3:	89 c8                	mov    %ecx,%eax
 2c5:	44 21 cf             	and    %r9d,%edi
 2c8:	f0 41 0f b1 3a       	lock cmpxchg %edi,(%r10)
 2cd:	39 c1                	cmp    %eax,%ecx
 2cf:	75 ed                	jne    2be <alloc_slot+0x2be>
 2d1:	e9 e9 fe ff ff       	jmp    1bf <alloc_slot+0x1bf>
 2d6:	44 89 e8             	mov    %r13d,%eax
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
 310:	48 39 c1             	cmp    %rax,%rcx
 313:	72 eb                	jb     300 <alloc_slot+0x300>
 315:	eb 0b                	jmp    322 <alloc_slot+0x322>
 317:	66 0f 1f 84 00 00 00 	nopw   0x0(%rax,%rax,1)
 31e:	00 00 
 320:	d1 fb                	sar    $1,%ebx
 322:	48 63 c3             	movslq %ebx,%rax
 325:	49 0f af c4          	imul   %r12,%rax
 329:	48 3d ff ff 0f 00    	cmp    $0xfffff,%rax
 32f:	77 ef                	ja     320 <alloc_slot+0x320>
 331:	b8 f0 ff 01 00       	mov    $0x1fff0,%eax
 336:	31 d2                	xor    %edx,%edx
 338:	49 f7 f4             	div    %r12
 33b:	48 83 f8 08          	cmp    $0x8,%rax
 33f:	76 4e                	jbe    38f <alloc_slot+0x38f>
 341:	b8 08 00 00 00       	mov    $0x8,%eax
 346:	39 c3                	cmp    %eax,%ebx
 348:	0f 4c d8             	cmovl  %eax,%ebx
 34b:	4c 89 e0             	mov    %r12,%rax
 34e:	4c 63 cb             	movslq %ebx,%r9
 351:	8d 14 9d 00 00 00 00 	lea    0x0(,%rbx,4),%edx
 358:	49 0f af c1          	imul   %r9,%rax
 35c:	48 63 d2             	movslq %edx,%rdx
 35f:	48 8d 78 10          	lea    0x10(%rax),%rdi
 363:	48 81 ff 00 08 00 00 	cmp    $0x800,%rdi
 36a:	0f 86 16 04 00 00    	jbe    786 <alloc_slot+0x786>
 370:	41 8d 7d f9          	lea    -0x7(%r13),%edi
 374:	83 ff 1f             	cmp    $0x1f,%edi
 377:	0f 86 e7 02 00 00    	jbe    664 <alloc_slot+0x664>
 37d:	0f b6 3d 00 00 00 00 	movzbl 0x0(%rip),%edi        # 384 <alloc_slot+0x384>
			380: R_X86_64_PC32	__malloc_context+0x3b4
 384:	45 31 c9             	xor    %r9d,%r9d
 387:	41 b8 01 00 00 00    	mov    $0x1,%r8d
 38d:	eb 59                	jmp    3e8 <alloc_slot+0x3e8>
 38f:	39 c3                	cmp    %eax,%ebx
 391:	0f 4c d8             	cmovl  %eax,%ebx
 394:	4c 63 cb             	movslq %ebx,%r9
 397:	83 fb 01             	cmp    $0x1,%ebx
 39a:	0f 84 1e 02 00 00    	je     5be <alloc_slot+0x5be>
 3a0:	4c 89 e0             	mov    %r12,%rax
 3a3:	49 0f af c1          	imul   %r9,%rax
 3a7:	48 8d 50 10          	lea    0x10(%rax),%rdx
 3ab:	48 81 fa 00 08 00 00 	cmp    $0x800,%rdx
 3b2:	0f 86 ce 03 00 00    	jbe    786 <alloc_slot+0x786>
 3b8:	8d 14 9d 00 00 00 00 	lea    0x0(,%rbx,4),%edx
 3bf:	48 63 d2             	movslq %edx,%rdx
 3c2:	49 81 fc f0 ff 01 00 	cmp    $0x1fff0,%r12
 3c9:	76 a5                	jbe    370 <alloc_slot+0x370>
 3cb:	41 8d 7d f9          	lea    -0x7(%r13),%edi
 3cf:	83 ff 1f             	cmp    $0x1f,%edi
 3d2:	0f 86 10 02 00 00    	jbe    5e8 <alloc_slot+0x5e8>
 3d8:	0f b6 3d 00 00 00 00 	movzbl 0x0(%rip),%edi        # 3df <alloc_slot+0x3df>
			3db: R_X86_64_PC32	__malloc_context+0x3b4
 3df:	41 b9 01 00 00 00    	mov    $0x1,%r9d
 3e5:	45 31 c0             	xor    %r8d,%r8d
 3e8:	44 8d 57 01          	lea    0x1(%rdi),%r10d
 3ec:	40 80 ff ff          	cmp    $0xff,%dil
 3f0:	0f 84 79 02 00 00    	je     66f <alloc_slot+0x66f>
 3f6:	44 88 15 00 00 00 00 	mov    %r10b,0x0(%rip)        # 3fd <alloc_slot+0x3fd>
			3f9: R_X86_64_PC32	__malloc_context+0x3b4
 3fd:	41 f6 c5 01          	test   $0x1,%r13b
 401:	0f 85 c9 02 00 00    	jne    6d0 <alloc_slot+0x6d0>
 407:	41 83 fd 1f          	cmp    $0x1f,%r13d
 40b:	0f 8f 8a 02 00 00    	jg     69b <alloc_slot+0x69b>
 411:	41 8d 7d 01          	lea    0x1(%r13),%edi
 415:	48 63 ff             	movslq %edi,%rdi
 418:	49 03 8c ff f8 01 00 	add    0x1f8(%r15,%rdi,8),%rcx
 41f:	00 
 420:	48 39 d1             	cmp    %rdx,%rcx
 423:	73 09                	jae    42e <alloc_slot+0x42e>
 425:	45 84 c9             	test   %r9b,%r9b
 428:	0f 85 7b 02 00 00    	jne    6a9 <alloc_slot+0x6a9>
 42e:	83 fb 07             	cmp    $0x7,%ebx
 431:	48 63 d3             	movslq %ebx,%rdx
 434:	40 0f 9e c7          	setle  %dil
 438:	49 0f af d4          	imul   %r12,%rdx
 43c:	48 c7 c0 f0 ff ff ff 	mov    $0xfffffffffffffff0,%rax
 443:	48 29 d0             	sub    %rdx,%rax
 446:	25 ff 0f 00 00       	and    $0xfff,%eax
 44b:	4c 8d 54 02 10       	lea    0x10(%rdx,%rax,1),%r10
 450:	45 85 c0             	test   %r8d,%r8d
 453:	75 3e                	jne    493 <alloc_slot+0x493>
 455:	40 84 ff             	test   %dil,%dil
 458:	74 39                	je     493 <alloc_slot+0x493>
 45a:	48 c7 c0 ec ff ff ff 	mov    $0xffffffffffffffec,%rax
 461:	49 8d 54 24 10       	lea    0x10(%r12),%rdx
 466:	48 29 f0             	sub    %rsi,%rax
 469:	25 ff 0f 00 00       	and    $0xfff,%eax
 46e:	48 8d 44 06 14       	lea    0x14(%rsi,%rax,1),%rax
 473:	48 39 d0             	cmp    %rdx,%rax
 476:	72 13                	jb     48b <alloc_slot+0x48b>
 478:	48 3d ff 3f 00 00    	cmp    $0x3fff,%rax
 47e:	76 13                	jbe    493 <alloc_slot+0x493>
 480:	8d 14 1b             	lea    (%rbx,%rbx,1),%edx
 483:	48 63 d2             	movslq %edx,%rdx
 486:	48 39 d1             	cmp    %rdx,%rcx
 489:	73 08                	jae    493 <alloc_slot+0x493>
 48b:	49 89 c2             	mov    %rax,%r10
 48e:	bb 01 00 00 00       	mov    $0x1,%ebx
 493:	4c 89 d6             	mov    %r10,%rsi
 496:	45 31 c9             	xor    %r9d,%r9d
 499:	31 ff                	xor    %edi,%edi
 49b:	41 b8 ff ff ff ff    	mov    $0xffffffff,%r8d
 4a1:	b9 22 00 00 00       	mov    $0x22,%ecx
 4a6:	ba 03 00 00 00       	mov    $0x3,%edx
 4ab:	4c 89 54 24 08       	mov    %r10,0x8(%rsp)
 4b0:	e8 00 00 00 00       	call   4b5 <alloc_slot+0x4b5>
			4b1: R_X86_64_PLT32	__mmap-0x4
 4b5:	4c 8b 54 24 08       	mov    0x8(%rsp),%r10
 4ba:	48 83 f8 ff          	cmp    $0xffffffffffffffff,%rax
 4be:	48 89 c6             	mov    %rax,%rsi
 4c1:	0f 84 85 02 00 00    	je     74c <alloc_slot+0x74c>
 4c7:	48 8b 45 20          	mov    0x20(%rbp),%rax
 4cb:	49 81 e2 00 f0 ff ff 	and    $0xfffffffffffff000,%r10
 4d2:	31 d2                	xor    %edx,%edx
 4d4:	8d 7b ff             	lea    -0x1(%rbx),%edi
 4d7:	4c 63 cb             	movslq %ebx,%r9
 4da:	25 ff 0f 00 00       	and    $0xfff,%eax
 4df:	49 09 c2             	or     %rax,%r10
 4e2:	b8 f0 0f 00 00       	mov    $0xff0,%eax
 4e7:	49 f7 f4             	div    %r12
 4ea:	4c 89 55 20          	mov    %r10,0x20(%rbp)
 4ee:	83 05 00 00 00 00 01 	addl   $0x1,0x0(%rip)        # 4f5 <alloc_slot+0x4f5>
			4f0: R_X86_64_PC32	__malloc_context+0x7
 4f5:	83 e8 01             	sub    $0x1,%eax
 4f8:	39 d8                	cmp    %ebx,%eax
 4fa:	0f 4d c7             	cmovge %edi,%eax
 4fd:	31 d2                	xor    %edx,%edx
 4ff:	85 c0                	test   %eax,%eax
 501:	0f 49 d0             	cmovns %eax,%edx
 504:	b8 02 00 00 00       	mov    $0x2,%eax
 509:	89 d1                	mov    %edx,%ecx
 50b:	4f 01 8c f7 f8 01 00 	add    %r9,0x1f8(%r15,%r14,8)
 512:	00 
 513:	41 89 c3             	mov    %eax,%r11d
 516:	48 89 75 10          	mov    %rsi,0x10(%rbp)
 51a:	83 eb 01             	sub    $0x1,%ebx
 51d:	41 83 e5 3f          	and    $0x3f,%r13d
 521:	41 d3 e3             	shl    %cl,%r11d
 524:	83 e3 1f             	and    $0x1f,%ebx
 527:	41 c1 e5 06          	shl    $0x6,%r13d
 52b:	44 89 d9             	mov    %r11d,%ecx
 52e:	83 cb 20             	or     $0x20,%ebx
 531:	83 e9 01             	sub    $0x1,%ecx
 534:	44 09 eb             	or     %r13d,%ebx
 537:	89 4d 18             	mov    %ecx,0x18(%rbp)
 53a:	89 f9                	mov    %edi,%ecx
 53c:	44 8b 45 18          	mov    0x18(%rbp),%r8d
 540:	d3 e0                	shl    %cl,%eax
 542:	44 29 c0             	sub    %r8d,%eax
 545:	83 e8 01             	sub    $0x1,%eax
 548:	89 45 1c             	mov    %eax,0x1c(%rbp)
 54b:	89 d0                	mov    %edx,%eax
 54d:	48 89 2e             	mov    %rbp,(%rsi)
 550:	48 8b 75 10          	mov    0x10(%rbp),%rsi
 554:	83 e0 1f             	and    $0x1f,%eax
 557:	0f b6 4e 08          	movzbl 0x8(%rsi),%ecx
 55b:	83 e1 e0             	and    $0xffffffe0,%ecx
 55e:	09 c8                	or     %ecx,%eax
 560:	88 46 08             	mov    %al,0x8(%rsi)
 563:	0f b7 45 20          	movzwl 0x20(%rbp),%eax
 567:	66 25 00 f0          	and    $0xf000,%ax
 56b:	09 c3                	or     %eax,%ebx
 56d:	8b 45 18             	mov    0x18(%rbp),%eax
 570:	66 89 5d 20          	mov    %bx,0x20(%rbp)
 574:	83 e8 01             	sub    $0x1,%eax
 577:	48 83 7d 08 00       	cmpq   $0x0,0x8(%rbp)
 57c:	89 45 18             	mov    %eax,0x18(%rbp)
 57f:	0f 85 00 00 00 00    	jne    585 <alloc_slot+0x585>
			581: R_X86_64_PC32	.text.unlikely.alloc_slot-0x4
 585:	48 83 7d 00 00       	cmpq   $0x0,0x0(%rbp)
 58a:	0f 85 00 00 00 00    	jne    590 <alloc_slot+0x590>
			58c: R_X86_64_PC32	.text.unlikely.alloc_slot-0x4
 590:	49 83 c6 0a          	add    $0xa,%r14
 594:	4b 8b 04 f7          	mov    (%r15,%r14,8),%rax
 598:	48 85 c0             	test   %rax,%rax
 59b:	0f 84 52 04 00 00    	je     9f3 <alloc_slot+0x9f3>
 5a1:	48 89 45 08          	mov    %rax,0x8(%rbp)
 5a5:	48 8b 00             	mov    (%rax),%rax
 5a8:	48 89 45 00          	mov    %rax,0x0(%rbp)
 5ac:	48 89 68 08          	mov    %rbp,0x8(%rax)
 5b0:	48 8b 45 08          	mov    0x8(%rbp),%rax
 5b4:	48 89 28             	mov    %rbp,(%rax)
 5b7:	31 c0                	xor    %eax,%eax
 5b9:	e9 52 fc ff ff       	jmp    210 <alloc_slot+0x210>
 5be:	49 8d 44 24 10       	lea    0x10(%r12),%rax
 5c3:	48 3d 00 08 00 00    	cmp    $0x800,%rax
 5c9:	77 10                	ja     5db <alloc_slot+0x5db>
 5cb:	41 b9 02 00 00 00    	mov    $0x2,%r9d
 5d1:	bb 02 00 00 00       	mov    $0x2,%ebx
 5d6:	e9 c5 fd ff ff       	jmp    3a0 <alloc_slot+0x3a0>
 5db:	4c 89 e0             	mov    %r12,%rax
 5de:	ba 04 00 00 00       	mov    $0x4,%edx
 5e3:	e9 da fd ff ff       	jmp    3c2 <alloc_slot+0x3c2>
 5e8:	4c 63 c7             	movslq %edi,%r8
 5eb:	43 80 bc 07 98 03 00 	cmpb   $0x63,0x398(%r15,%r8,1)
 5f2:	00 63 
 5f4:	41 0f 97 c0          	seta   %r8b
 5f8:	41 0f 96 c1          	setbe  %r9b
 5fc:	45 0f b6 c0          	movzbl %r8b,%r8d
 600:	48 63 ff             	movslq %edi,%rdi
 603:	45 0f b6 94 3f 78 03 	movzbl 0x378(%r15,%rdi,1),%r10d
 60a:	00 00 
 60c:	48 89 7c 24 08       	mov    %rdi,0x8(%rsp)
 611:	0f b6 3d 00 00 00 00 	movzbl 0x0(%rip),%edi        # 618 <alloc_slot+0x618>
			614: R_X86_64_PC32	__malloc_context+0x3b4
 618:	45 85 d2             	test   %r10d,%r10d
 61b:	0f 84 c7 fd ff ff    	je     3e8 <alloc_slot+0x3e8>
 621:	44 0f b6 df          	movzbl %dil,%r11d
 625:	45 29 d3             	sub    %r10d,%r11d
 628:	41 83 fb 09          	cmp    $0x9,%r11d
 62c:	0f 8f b6 fd ff ff    	jg     3e8 <alloc_slot+0x3e8>
 632:	4c 8b 5c 24 08       	mov    0x8(%rsp),%r11
 637:	47 0f b6 94 1f 98 03 	movzbl 0x398(%r15,%r11,1),%r10d
 63e:	00 00 
 640:	45 8d 5a 01          	lea    0x1(%r10),%r11d
 644:	41 80 fa 63          	cmp    $0x63,%r10b
 648:	41 ba 96 ff ff ff    	mov    $0xffffff96,%r10d
 64e:	45 0f 43 da          	cmovae %r10d,%r11d
 652:	4c 8b 54 24 08       	mov    0x8(%rsp),%r10
 657:	47 88 9c 17 98 03 00 	mov    %r11b,0x398(%r15,%r10,1)
 65e:	00 
 65f:	e9 84 fd ff ff       	jmp    3e8 <alloc_slot+0x3e8>
 664:	45 31 c9             	xor    %r9d,%r9d
 667:	41 b8 01 00 00 00    	mov    $0x1,%r8d
 66d:	eb 91                	jmp    600 <alloc_slot+0x600>
 66f:	48 8d 3d 00 00 00 00 	lea    0x0(%rip),%rdi        # 676 <alloc_slot+0x676>
			672: R_X86_64_PC32	__malloc_context+0x374
 676:	4c 8d 57 20          	lea    0x20(%rdi),%r10
 67a:	eb 0f                	jmp    68b <alloc_slot+0x68b>
 67c:	0f 1f 40 00          	nopl   0x0(%rax)
 680:	c6 07 00             	movb   $0x0,(%rdi)
 683:	48 83 c7 02          	add    $0x2,%rdi
 687:	c6 47 ff 00          	movb   $0x0,-0x1(%rdi)
 68b:	4c 39 d7             	cmp    %r10,%rdi
 68e:	75 f0                	jne    680 <alloc_slot+0x680>
 690:	41 ba 01 00 00 00    	mov    $0x1,%r10d
 696:	e9 5b fd ff ff       	jmp    3f6 <alloc_slot+0x3f6>
 69b:	48 39 d1             	cmp    %rdx,%rcx
 69e:	0f 82 81 fd ff ff    	jb     425 <alloc_slot+0x425>
 6a4:	e9 85 fd ff ff       	jmp    42e <alloc_slot+0x42e>
 6a9:	44 89 ea             	mov    %r13d,%edx
 6ac:	83 e2 03             	and    $0x3,%edx
 6af:	83 fa 02             	cmp    $0x2,%edx
 6b2:	74 6b                	je     71f <alloc_slot+0x71f>
 6b4:	48 3d 00 80 00 00    	cmp    $0x8000,%rax
 6ba:	76 70                	jbe    72c <alloc_slot+0x72c>
 6bc:	bf 01 00 00 00       	mov    $0x1,%edi
 6c1:	ba 03 00 00 00       	mov    $0x3,%edx
 6c6:	bb 03 00 00 00       	mov    $0x3,%ebx
 6cb:	e9 68 fd ff ff       	jmp    438 <alloc_slot+0x438>
 6d0:	48 39 d1             	cmp    %rdx,%rcx
 6d3:	0f 83 55 fd ff ff    	jae    42e <alloc_slot+0x42e>
 6d9:	45 84 c9             	test   %r9b,%r9b
 6dc:	0f 84 4c fd ff ff    	je     42e <alloc_slot+0x42e>
 6e2:	44 89 ea             	mov    %r13d,%edx
 6e5:	83 e2 03             	and    $0x3,%edx
 6e8:	83 fa 01             	cmp    $0x1,%edx
 6eb:	0f 85 3d fd ff ff    	jne    42e <alloc_slot+0x42e>
 6f1:	48 3d 00 80 00 00    	cmp    $0x8000,%rax
 6f7:	0f 86 31 fd ff ff    	jbe    42e <alloc_slot+0x42e>
 6fd:	4b 8d 14 24          	lea    (%r12,%r12,1),%rdx
 701:	48 c7 c0 f0 ff ff ff 	mov    $0xfffffffffffffff0,%rax
 708:	bb 02 00 00 00       	mov    $0x2,%ebx
 70d:	48 29 d0             	sub    %rdx,%rax
 710:	25 ff 0f 00 00       	and    $0xfff,%eax
 715:	4c 8d 54 02 10       	lea    0x10(%rdx,%rax,1),%r10
 71a:	e9 3b fd ff ff       	jmp    45a <alloc_slot+0x45a>
 71f:	48 3d 00 40 00 00    	cmp    $0x4000,%rax
 725:	77 95                	ja     6bc <alloc_slot+0x6bc>
 727:	e9 02 fd ff ff       	jmp    42e <alloc_slot+0x42e>
 72c:	48 3d 00 20 00 00    	cmp    $0x2000,%rax
 732:	0f 86 f6 fc ff ff    	jbe    42e <alloc_slot+0x42e>
 738:	bf 01 00 00 00       	mov    $0x1,%edi
 73d:	ba 05 00 00 00       	mov    $0x5,%edx
 742:	bb 05 00 00 00       	mov    $0x5,%ebx
 747:	e9 ec fc ff ff       	jmp    438 <alloc_slot+0x438>
 74c:	66 0f ef c0          	pxor   %xmm0,%xmm0
 750:	48 c7 45 20 00 00 00 	movq   $0x0,0x20(%rbp)
 757:	00 
 758:	0f 11 45 00          	movups %xmm0,0x0(%rbp)
 75c:	0f 11 45 10          	movups %xmm0,0x10(%rbp)
 760:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 767 <alloc_slot+0x767>
			763: R_X86_64_PC32	__malloc_context+0xc
 767:	48 85 c0             	test   %rax,%rax
 76a:	0f 85 d8 00 00 00    	jne    848 <alloc_slot+0x848>
 770:	66 0f 6f 5c 24 10    	movdqa 0x10(%rsp),%xmm3
 776:	0f 11 5d 00          	movups %xmm3,0x0(%rbp)
 77a:	48 89 2d 00 00 00 00 	mov    %rbp,0x0(%rip)        # 781 <alloc_slot+0x781>
			77d: R_X86_64_PC32	__malloc_context+0xc
 781:	e9 d8 00 00 00       	jmp    85e <alloc_slot+0x85e>
 786:	48 89 c2             	mov    %rax,%rdx
 789:	48 8d 70 0c          	lea    0xc(%rax),%rsi
 78d:	48 c1 ea 04          	shr    $0x4,%rdx
 791:	48 3d 90 00 00 00    	cmp    $0x90,%rax
 797:	76 30                	jbe    7c9 <alloc_slot+0x7c9>
 799:	48 8d 42 01          	lea    0x1(%rdx),%rax
 79d:	0f bd d0             	bsr    %eax,%edx
 7a0:	8d 14 95 fc ff ff ff 	lea    -0x4(,%rdx,4),%edx
 7a7:	8d 4a 01             	lea    0x1(%rdx),%ecx
 7aa:	48 63 c9             	movslq %ecx,%rcx
 7ad:	41 0f b7 3c 48       	movzwl (%r8,%rcx,2),%edi
 7b2:	8d 4a 02             	lea    0x2(%rdx),%ecx
 7b5:	48 39 c7             	cmp    %rax,%rdi
 7b8:	0f 42 d1             	cmovb  %ecx,%edx
 7bb:	48 63 ca             	movslq %edx,%rcx
 7be:	41 0f b7 0c 48       	movzwl (%r8,%rcx,2),%ecx
 7c3:	48 39 c1             	cmp    %rax,%rcx
 7c6:	83 d2 00             	adc    $0x0,%edx
 7c9:	89 d7                	mov    %edx,%edi
 7cb:	4c 89 4c 24 20       	mov    %r9,0x20(%rsp)
 7d0:	89 54 24 08          	mov    %edx,0x8(%rsp)
 7d4:	e8 27 f8 ff ff       	call   0 <alloc_slot>
 7d9:	48 63 54 24 08       	movslq 0x8(%rsp),%rdx
 7de:	4c 8b 4c 24 20       	mov    0x20(%rsp),%r9
 7e3:	4c 8d 05 00 00 00 00 	lea    0x0(%rip),%r8        # 7ea <alloc_slot+0x7ea>
			7e6: R_X86_64_PC32	__malloc_size_classes-0x4
 7ea:	83 f8 ff             	cmp    $0xffffffff,%eax
 7ed:	74 39                	je     828 <alloc_slot+0x828>
 7ef:	4d 8b 54 d7 50       	mov    0x50(%r15,%rdx,8),%r10
 7f4:	41 0f b7 14 50       	movzwl (%r8,%rdx,2),%edx
 7f9:	c1 e2 04             	shl    $0x4,%edx
 7fc:	8d 72 fc             	lea    -0x4(%rdx),%esi
 7ff:	89 74 24 20          	mov    %esi,0x20(%rsp)
 803:	48 63 f6             	movslq %esi,%rsi
 806:	41 f6 42 20 1f       	testb  $0x1f,0x20(%r10)
 80b:	75 6e                	jne    87b <alloc_slot+0x87b>
 80d:	49 81 7a 20 ff 0f 00 	cmpq   $0xfff,0x20(%r10)
 814:	00 
 815:	76 64                	jbe    87b <alloc_slot+0x87b>
 817:	49 8b 4a 20          	mov    0x20(%r10),%rcx
 81b:	48 81 e1 00 f0 ff ff 	and    $0xfffffffffffff000,%rcx
 822:	48 83 e9 10          	sub    $0x10,%rcx
 826:	eb 6a                	jmp    892 <alloc_slot+0x892>
 828:	66 0f ef c0          	pxor   %xmm0,%xmm0
 82c:	48 c7 45 20 00 00 00 	movq   $0x0,0x20(%rbp)
 833:	00 
 834:	0f 11 45 00          	movups %xmm0,0x0(%rbp)
 838:	0f 11 45 10          	movups %xmm0,0x10(%rbp)
 83c:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 843 <alloc_slot+0x843>
			83f: R_X86_64_PC32	__malloc_context+0xc
 843:	48 85 c0             	test   %rax,%rax
 846:	74 20                	je     868 <alloc_slot+0x868>
 848:	48 89 45 08          	mov    %rax,0x8(%rbp)
 84c:	48 8b 00             	mov    (%rax),%rax
 84f:	48 89 45 00          	mov    %rax,0x0(%rbp)
 853:	48 89 68 08          	mov    %rbp,0x8(%rax)
 857:	48 8b 45 08          	mov    0x8(%rbp),%rax
 85b:	48 89 28             	mov    %rbp,(%rax)
 85e:	b8 ff ff ff ff       	mov    $0xffffffff,%eax
 863:	e9 a8 f9 ff ff       	jmp    210 <alloc_slot+0x210>
 868:	66 0f 6f 64 24 10    	movdqa 0x10(%rsp),%xmm4
 86e:	0f 11 65 00          	movups %xmm4,0x0(%rbp)
 872:	48 89 2d 00 00 00 00 	mov    %rbp,0x0(%rip)        # 879 <alloc_slot+0x879>
			875: R_X86_64_PC32	__malloc_context+0xc
 879:	eb e3                	jmp    85e <alloc_slot+0x85e>
 87b:	41 0f b7 52 20       	movzwl 0x20(%r10),%edx
 880:	66 c1 ea 06          	shr    $0x6,%dx
 884:	83 e2 3f             	and    $0x3f,%edx
 887:	41 0f b7 0c 50       	movzwl (%r8,%rdx,2),%ecx
 88c:	c1 e1 04             	shl    $0x4,%ecx
 88f:	48 63 c9             	movslq %ecx,%rcx
 892:	48 89 ca             	mov    %rcx,%rdx
 895:	48 29 f2             	sub    %rsi,%rdx
 898:	48 63 f0             	movslq %eax,%rsi
 89b:	48 0f af f1          	imul   %rcx,%rsi
 89f:	4c 8d 42 fc          	lea    -0x4(%rdx),%r8
 8a3:	49 8b 52 10          	mov    0x10(%r10),%rdx
 8a7:	48 83 c2 10          	add    $0x10,%rdx
 8ab:	48 01 d6             	add    %rdx,%rsi
 8ae:	48 8d 7c 0e fc       	lea    -0x4(%rsi,%rcx,1),%rdi
 8b3:	0f b6 4e fc          	movzbl -0x4(%rsi),%ecx
 8b7:	48 89 7c 24 08       	mov    %rdi,0x8(%rsp)
 8bc:	84 c9                	test   %cl,%cl
 8be:	0f 85 00 00 00 00    	jne    8c4 <alloc_slot+0x8c4>
			8c0: R_X86_64_PC32	.text.unlikely.alloc_slot-0x4
 8c4:	49 83 f8 0f          	cmp    $0xf,%r8
 8c8:	0f 86 8e 00 00 00    	jbe    95c <alloc_slot+0x95c>
 8ce:	80 7e fd 00          	cmpb   $0x0,-0x3(%rsi)
 8d2:	0f 84 ff 00 00 00    	je     9d7 <alloc_slot+0x9d7>
 8d8:	0f b7 7e fe          	movzwl -0x2(%rsi),%edi
 8dc:	83 c7 01             	add    $0x1,%edi
 8df:	40 0f b6 ff          	movzbl %dil,%edi
 8e3:	4d 89 c3             	mov    %r8,%r11
 8e6:	49 c1 eb 04          	shr    $0x4,%r11
 8ea:	4c 89 5c 24 28       	mov    %r11,0x28(%rsp)
 8ef:	4c 63 df             	movslq %edi,%r11
 8f2:	4c 39 5c 24 28       	cmp    %r11,0x28(%rsp)
 8f7:	73 42                	jae    93b <alloc_slot+0x93b>
 8f9:	4c 8b 5c 24 28       	mov    0x28(%rsp),%r11
 8fe:	49 c1 e8 05          	shr    $0x5,%r8
 902:	4d 09 d8             	or     %r11,%r8
 905:	4d 89 c3             	mov    %r8,%r11
 908:	49 c1 eb 02          	shr    $0x2,%r11
 90c:	4d 09 d8             	or     %r11,%r8
 90f:	4d 89 c3             	mov    %r8,%r11
 912:	49 c1 eb 04          	shr    $0x4,%r11
 916:	4d 09 d8             	or     %r11,%r8
 919:	4c 8b 5c 24 28       	mov    0x28(%rsp),%r11
 91e:	44 21 c7             	and    %r8d,%edi
 921:	4c 63 c7             	movslq %edi,%r8
 924:	4d 39 c3             	cmp    %r8,%r11
 927:	73 12                	jae    93b <alloc_slot+0x93b>
 929:	44 29 df             	sub    %r11d,%edi
 92c:	83 ef 01             	sub    $0x1,%edi
 92f:	4c 63 c7             	movslq %edi,%r8
 932:	4d 39 c3             	cmp    %r8,%r11
 935:	0f 82 00 00 00 00    	jb     93b <alloc_slot+0x93b>
			937: R_X86_64_PC32	.text.unlikely.alloc_slot-0x4
 93b:	85 ff                	test   %edi,%edi
 93d:	74 1d                	je     95c <alloc_slot+0x95c>
 93f:	66 89 7e fe          	mov    %di,-0x2(%rsi)
 943:	c1 e7 04             	shl    $0x4,%edi
 946:	48 63 d7             	movslq %edi,%rdx
 949:	c6 46 fd e0          	movb   $0xe0,-0x3(%rsi)
 94d:	48 01 d6             	add    %rdx,%rsi
 950:	c6 46 fc 00          	movb   $0x0,-0x4(%rsi)
 954:	49 8b 52 10          	mov    0x10(%r10),%rdx
 958:	48 83 c2 10          	add    $0x10,%rdx
 95c:	48 89 f7             	mov    %rsi,%rdi
 95f:	4c 8b 5c 24 08       	mov    0x8(%rsp),%r11
 964:	48 29 d7             	sub    %rdx,%rdi
 967:	48 c1 ef 04          	shr    $0x4,%rdi
 96b:	4c 89 da             	mov    %r11,%rdx
 96e:	66 89 7e fe          	mov    %di,-0x2(%rsi)
 972:	8b 7c 24 20          	mov    0x20(%rsp),%edi
 976:	48 29 f2             	sub    %rsi,%rdx
 979:	29 fa                	sub    %edi,%edx
 97b:	74 16                	je     993 <alloc_slot+0x993>
 97d:	89 d1                	mov    %edx,%ecx
 97f:	f7 d9                	neg    %ecx
 981:	48 63 c9             	movslq %ecx,%rcx
 984:	41 c6 04 0b 00       	movb   $0x0,(%r11,%rcx,1)
 989:	83 fa 04             	cmp    $0x4,%edx
 98c:	7f 55                	jg     9e3 <alloc_slot+0x9e3>
 98e:	89 d1                	mov    %edx,%ecx
 990:	c1 e1 05             	shl    $0x5,%ecx
 993:	01 c1                	add    %eax,%ecx
 995:	48 8d 56 0c          	lea    0xc(%rsi),%rdx
 999:	88 4e fd             	mov    %cl,-0x3(%rsi)
 99c:	8d 4b 01             	lea    0x1(%rbx),%ecx
 99f:	48 81 65 20 ff 0f 00 	andq   $0xfff,0x20(%rbp)
 9a6:	00 
 9a7:	0f b6 46 fd          	movzbl -0x3(%rsi),%eax
 9ab:	83 e0 1f             	and    $0x1f,%eax
 9ae:	83 c8 c0             	or     $0xffffffc0,%eax
 9b1:	88 46 fd             	mov    %al,-0x3(%rsi)
 9b4:	31 c0                	xor    %eax,%eax
 9b6:	66 2e 0f 1f 84 00 00 	cs nopw 0x0(%rax,%rax,1)
 9bd:	00 00 00 
 9c0:	83 c0 01             	add    $0x1,%eax
 9c3:	c6 02 00             	movb   $0x0,(%rdx)
 9c6:	4c 01 e2             	add    %r12,%rdx
 9c9:	39 c8                	cmp    %ecx,%eax
 9cb:	75 f3                	jne    9c0 <alloc_slot+0x9c0>
 9cd:	8d 53 ff             	lea    -0x1(%rbx),%edx
 9d0:	89 d7                	mov    %edx,%edi
 9d2:	e9 2d fb ff ff       	jmp    504 <alloc_slot+0x504>
 9d7:	0f b6 3d 00 00 00 00 	movzbl 0x0(%rip),%edi        # 9de <alloc_slot+0x9de>
			9da: R_X86_64_PC32	__malloc_context+0x8
 9de:	e9 00 ff ff ff       	jmp    8e3 <alloc_slot+0x8e3>
 9e3:	41 89 53 fc          	mov    %edx,-0x4(%r11)
 9e7:	b9 a0 ff ff ff       	mov    $0xffffffa0,%ecx
 9ec:	41 c6 43 fb 00       	movb   $0x0,-0x5(%r11)
 9f1:	eb a0                	jmp    993 <alloc_slot+0x993>
 9f3:	66 0f 6f 54 24 10    	movdqa 0x10(%rsp),%xmm2
 9f9:	0f 11 55 00          	movups %xmm2,0x0(%rbp)
 9fd:	4b 89 2c f7          	mov    %rbp,(%r15,%r14,8)
 a01:	e9 b1 fb ff ff       	jmp    5b7 <alloc_slot+0x5b7>

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
  1b:	0f 82 c0 00 00 00    	jb     e1 <malloc_slow+0xe1>
  21:	48 89 fb             	mov    %rdi,%rbx
  24:	48 81 ff eb ff 01 00 	cmp    $0x1ffeb,%rdi
  2b:	0f 87 c2 00 00 00    	ja     f3 <malloc_slow+0xf3>
  31:	48 8d 57 03          	lea    0x3(%rdi),%rdx
  35:	48 89 d0             	mov    %rdx,%rax
  38:	48 c1 e8 04          	shr    $0x4,%rax
  3c:	4c 63 f0             	movslq %eax,%r14
  3f:	4c 89 f5             	mov    %r14,%rbp
  42:	48 81 fa 9f 00 00 00 	cmp    $0x9f,%rdx
  49:	76 3b                	jbe    86 <malloc_slow+0x86>
  4b:	48 83 c0 01          	add    $0x1,%rax
  4f:	48 8d 0d 00 00 00 00 	lea    0x0(%rip),%rcx        # 56 <malloc_slow+0x56>
			52: R_X86_64_PC32	__malloc_size_classes-0x4
  56:	0f bd d0             	bsr    %eax,%edx
  59:	8d 2c 95 fc ff ff ff 	lea    -0x4(,%rdx,4),%ebp
  60:	8d 55 01             	lea    0x1(%rbp),%edx
  63:	48 63 d2             	movslq %edx,%rdx
  66:	0f b7 34 51          	movzwl (%rcx,%rdx,2),%esi
  6a:	8d 55 02             	lea    0x2(%rbp),%edx
  6d:	48 39 c6             	cmp    %rax,%rsi
  70:	0f 42 ea             	cmovb  %edx,%ebp
  73:	4c 63 f5             	movslq %ebp,%r14
  76:	42 0f b7 14 71       	movzwl (%rcx,%r14,2),%edx
  7b:	48 39 c2             	cmp    %rax,%rdx
  7e:	73 06                	jae    86 <malloc_slow+0x86>
  80:	83 c5 01             	add    $0x1,%ebp
  83:	4c 63 f5             	movslq %ebp,%r14
  86:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 8d <malloc_slow+0x8d>
			89: R_X86_64_PC32	__libc-0x1
  8d:	4c 8d 2d 00 00 00 00 	lea    0x0(%rip),%r13        # 94 <malloc_slow+0x94>
			90: R_X86_64_PC32	__malloc_lock-0x4
  94:	84 c0                	test   %al,%al
  96:	0f 85 82 02 00 00    	jne    31e <malloc_slow+0x31e>
  9c:	48 8d 15 00 00 00 00 	lea    0x0(%rip),%rdx        # a3 <malloc_slow+0xa3>
			9f: R_X86_64_PC32	__malloc_context-0x4
  a3:	4e 8b 7c f2 50       	mov    0x50(%rdx,%r14,8),%r15
  a8:	4d 85 ff             	test   %r15,%r15
  ab:	0f 84 7a 02 00 00    	je     32b <malloc_slow+0x32b>
  b1:	41 8b 47 18          	mov    0x18(%r15),%eax
  b5:	41 89 c4             	mov    %eax,%r12d
  b8:	41 f7 dc             	neg    %r12d
  bb:	41 21 c4             	and    %eax,%r12d
  be:	0f 84 67 02 00 00    	je     32b <malloc_slow+0x32b>
  c4:	45 31 f6             	xor    %r14d,%r14d
  c7:	44 29 e0             	sub    %r12d,%eax
  ca:	8b 2d 00 00 00 00    	mov    0x0(%rip),%ebp        # d0 <malloc_slow+0xd0>
			cc: R_X86_64_PC32	__malloc_context+0x8
  d0:	f3 45 0f bc f4       	tzcnt  %r12d,%r14d
  d5:	41 89 47 18          	mov    %eax,0x18(%r15)
  d9:	4d 89 f4             	mov    %r14,%r12
  dc:	e9 3d 01 00 00       	jmp    21e <malloc_slow+0x21e>
  e1:	e8 00 00 00 00       	call   e6 <malloc_slow+0xe6>
			e2: R_X86_64_PLT32	___errno_location-0x4
  e6:	c7 00 0c 00 00 00    	movl   $0xc,(%rax)
  ec:	31 c0                	xor    %eax,%eax
  ee:	e9 8c 03 00 00       	jmp    47f <malloc_slow+0x47f>
  f3:	4c 8d b7 13 10 00 00 	lea    0x1013(%rdi),%r14
  fa:	4c 8d 67 14          	lea    0x14(%rdi),%r12
  fe:	49 c1 ee 0c          	shr    $0xc,%r14
 102:	49 8d 46 e0          	lea    -0x20(%r14),%rax
 106:	48 3d e0 01 00 00    	cmp    $0x1e0,%rax
 10c:	77 6d                	ja     17b <malloc_slow+0x17b>
 10e:	b8 20 00 00 00       	mov    $0x20,%eax
 113:	31 ed                	xor    %ebp,%ebp
 115:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
 11c:	00 00 00 00 
 120:	4c 39 f0             	cmp    %r14,%rax
 123:	73 08                	jae    12d <malloc_slow+0x12d>
 125:	83 c5 01             	add    $0x1,%ebp
 128:	48 01 c0             	add    %rax,%rax
 12b:	eb f3                	jmp    120 <malloc_slow+0x120>
 12d:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 134 <malloc_slow+0x134>
			130: R_X86_64_PC32	__libc-0x1
 134:	4c 8d 2d 00 00 00 00 	lea    0x0(%rip),%r13        # 13b <malloc_slow+0x13b>
			137: R_X86_64_PC32	__malloc_lock-0x4
 13b:	84 c0                	test   %al,%al
 13d:	0f 85 16 01 00 00    	jne    259 <malloc_slow+0x259>
 143:	48 63 ed             	movslq %ebp,%rbp
 146:	48 8d 15 00 00 00 00 	lea    0x0(%rip),%rdx        # 14d <malloc_slow+0x14d>
			149: R_X86_64_PC32	__malloc_context-0x4
 14d:	48 83 c5 3a          	add    $0x3a,%rbp
 151:	4c 8b 3c ea          	mov    (%rdx,%rbp,8),%r15
 155:	4d 85 ff             	test   %r15,%r15
 158:	74 13                	je     16d <malloc_slow+0x16d>
 15a:	49 8b 47 20          	mov    0x20(%r15),%rax
 15e:	48 25 00 f0 ff ff    	and    $0xfffffffffffff000,%rax
 164:	4c 39 e0             	cmp    %r12,%rax
 167:	0f 83 f9 00 00 00    	jae    266 <malloc_slow+0x266>
 16d:	8b 05 00 00 00 00    	mov    0x0(%rip),%eax        # 173 <malloc_slow+0x173>
			16f: R_X86_64_PC32	__malloc_lock-0x4
 173:	85 c0                	test   %eax,%eax
 175:	0f 88 3c 01 00 00    	js     2b7 <malloc_slow+0x2b7>
 17b:	45 31 c9             	xor    %r9d,%r9d
 17e:	41 b8 ff ff ff ff    	mov    $0xffffffff,%r8d
 184:	b9 22 00 00 00       	mov    $0x22,%ecx
 189:	31 ff                	xor    %edi,%edi
 18b:	ba 03 00 00 00       	mov    $0x3,%edx
 190:	4c 89 e6             	mov    %r12,%rsi
 193:	e8 00 00 00 00       	call   198 <malloc_slow+0x198>
			194: R_X86_64_PLT32	__mmap-0x4
 198:	48 89 c5             	mov    %rax,%rbp
 19b:	48 83 f8 ff          	cmp    $0xffffffffffffffff,%rax
 19f:	0f 84 47 ff ff ff    	je     ec <malloc_slow+0xec>
 1a5:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 1ac <malloc_slow+0x1ac>
			1a8: R_X86_64_PC32	__libc-0x1
 1ac:	4c 8d 2d 00 00 00 00 	lea    0x0(%rip),%r13        # 1b3 <malloc_slow+0x1b3>
			1af: R_X86_64_PC32	__malloc_lock-0x4
 1b3:	84 c0                	test   %al,%al
 1b5:	0f 85 09 01 00 00    	jne    2c4 <malloc_slow+0x2c4>
 1bb:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 1c2 <malloc_slow+0x1c2>
			1be: R_X86_64_PC32	__malloc_context+0x3b4
 1c2:	8d 50 01             	lea    0x1(%rax),%edx
 1c5:	3c ff                	cmp    $0xff,%al
 1c7:	0f 84 04 01 00 00    	je     2d1 <malloc_slow+0x2d1>
 1cd:	88 15 00 00 00 00    	mov    %dl,0x0(%rip)        # 1d3 <malloc_slow+0x1d3>
			1cf: R_X86_64_PC32	__malloc_context+0x3b4
 1d3:	e8 00 00 00 00       	call   1d8 <malloc_slow+0x1d8>
			1d4: R_X86_64_PLT32	__malloc_alloc_meta-0x4
 1d8:	49 89 c7             	mov    %rax,%r15
 1db:	48 85 c0             	test   %rax,%rax
 1de:	0f 84 16 01 00 00    	je     2fa <malloc_slow+0x2fa>
 1e4:	49 c1 e6 0c          	shl    $0xc,%r14
 1e8:	48 89 68 10          	mov    %rbp,0x10(%rax)
 1ec:	49 81 ce e0 0f 00 00 	or     $0xfe0,%r14
 1f3:	48 89 45 00          	mov    %rax,0x0(%rbp)
 1f7:	c7 40 1c 00 00 00 00 	movl   $0x0,0x1c(%rax)
 1fe:	4c 89 70 20          	mov    %r14,0x20(%rax)
 202:	c7 40 18 00 00 00 00 	movl   $0x0,0x18(%rax)
 209:	8b 05 00 00 00 00    	mov    0x0(%rip),%eax        # 20f <malloc_slow+0x20f>
			20b: R_X86_64_PC32	__malloc_context+0x8
 20f:	45 31 f6             	xor    %r14d,%r14d
 212:	45 31 e4             	xor    %r12d,%r12d
 215:	8d 68 01             	lea    0x1(%rax),%ebp
 218:	89 2d 00 00 00 00    	mov    %ebp,0x0(%rip)        # 21e <malloc_slow+0x21e>
			21a: R_X86_64_PC32	__malloc_context+0x8
 21e:	8b 15 00 00 00 00    	mov    0x0(%rip),%edx        # 224 <malloc_slow+0x224>
			220: R_X86_64_PC32	__malloc_lock-0x4
 224:	85 d2                	test   %edx,%edx
 226:	0f 88 46 01 00 00    	js     372 <malloc_slow+0x372>
 22c:	41 f6 47 20 1f       	testb  $0x1f,0x20(%r15)
 231:	0f 85 48 01 00 00    	jne    37f <malloc_slow+0x37f>
 237:	49 81 7f 20 ff 0f 00 	cmpq   $0xfff,0x20(%r15)
 23e:	00 
 23f:	0f 86 3a 01 00 00    	jbe    37f <malloc_slow+0x37f>
 245:	49 8b 57 20          	mov    0x20(%r15),%rdx
 249:	48 81 e2 00 f0 ff ff 	and    $0xfffffffffffff000,%rdx
 250:	48 83 ea 10          	sub    $0x10,%rdx
 254:	e9 43 01 00 00       	jmp    39c <malloc_slow+0x39c>
 259:	4c 89 ef             	mov    %r13,%rdi
 25c:	e8 00 00 00 00       	call   261 <malloc_slow+0x261>
			25d: R_X86_64_PLT32	__lock-0x4
 261:	e9 dd fe ff ff       	jmp    143 <malloc_slow+0x143>
 266:	48 c7 04 ea 00 00 00 	movq   $0x0,(%rdx,%rbp,8)
 26d:	00 
 26e:	41 c7 47 1c 00 00 00 	movl   $0x0,0x1c(%r15)
 275:	00 
 276:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 27d <malloc_slow+0x27d>
			279: R_X86_64_PC32	__malloc_context+0x3b4
 27d:	8d 50 01             	lea    0x1(%rax),%edx
 280:	3c ff                	cmp    $0xff,%al
 282:	74 0b                	je     28f <malloc_slow+0x28f>
 284:	88 15 00 00 00 00    	mov    %dl,0x0(%rip)        # 28a <malloc_slow+0x28a>
			286: R_X86_64_PC32	__malloc_context+0x3b4
 28a:	e9 7a ff ff ff       	jmp    209 <malloc_slow+0x209>
 28f:	48 8d 05 00 00 00 00 	lea    0x0(%rip),%rax        # 296 <malloc_slow+0x296>
			292: R_X86_64_PC32	__malloc_context+0x374
 296:	48 8d 50 20          	lea    0x20(%rax),%rdx
 29a:	eb 0f                	jmp    2ab <malloc_slow+0x2ab>
 29c:	0f 1f 40 00          	nopl   0x0(%rax)
 2a0:	c6 00 00             	movb   $0x0,(%rax)
 2a3:	48 83 c0 02          	add    $0x2,%rax
 2a7:	c6 40 ff 00          	movb   $0x0,-0x1(%rax)
 2ab:	48 39 d0             	cmp    %rdx,%rax
 2ae:	75 f0                	jne    2a0 <malloc_slow+0x2a0>
 2b0:	ba 01 00 00 00       	mov    $0x1,%edx
 2b5:	eb cd                	jmp    284 <malloc_slow+0x284>
 2b7:	4c 89 ef             	mov    %r13,%rdi
 2ba:	e8 00 00 00 00       	call   2bf <malloc_slow+0x2bf>
			2bb: R_X86_64_PLT32	__unlock-0x4
 2bf:	e9 b7 fe ff ff       	jmp    17b <malloc_slow+0x17b>
 2c4:	4c 89 ef             	mov    %r13,%rdi
 2c7:	e8 00 00 00 00       	call   2cc <malloc_slow+0x2cc>
			2c8: R_X86_64_PLT32	__lock-0x4
 2cc:	e9 ea fe ff ff       	jmp    1bb <malloc_slow+0x1bb>
 2d1:	48 8d 05 00 00 00 00 	lea    0x0(%rip),%rax        # 2d8 <malloc_slow+0x2d8>
			2d4: R_X86_64_PC32	__malloc_context+0x374
 2d8:	48 8d 50 20          	lea    0x20(%rax),%rdx
 2dc:	eb 0d                	jmp    2eb <malloc_slow+0x2eb>
 2de:	66 90                	xchg   %ax,%ax
 2e0:	c6 00 00             	movb   $0x0,(%rax)
 2e3:	48 83 c0 02          	add    $0x2,%rax
 2e7:	c6 40 ff 00          	movb   $0x0,-0x1(%rax)
 2eb:	48 39 d0             	cmp    %rdx,%rax
 2ee:	75 f0                	jne    2e0 <malloc_slow+0x2e0>
 2f0:	ba 01 00 00 00       	mov    $0x1,%edx
 2f5:	e9 d3 fe ff ff       	jmp    1cd <malloc_slow+0x1cd>
 2fa:	8b 05 00 00 00 00    	mov    0x0(%rip),%eax        # 300 <malloc_slow+0x300>
			2fc: R_X86_64_PC32	__malloc_lock-0x4
 300:	85 c0                	test   %eax,%eax
 302:	78 10                	js     314 <malloc_slow+0x314>
 304:	4c 89 e6             	mov    %r12,%rsi
 307:	48 89 ef             	mov    %rbp,%rdi
 30a:	e8 00 00 00 00       	call   30f <malloc_slow+0x30f>
			30b: R_X86_64_PLT32	munmap-0x4
 30f:	e9 d8 fd ff ff       	jmp    ec <malloc_slow+0xec>
 314:	4c 89 ef             	mov    %r13,%rdi
 317:	e8 00 00 00 00       	call   31c <malloc_slow+0x31c>
			318: R_X86_64_PLT32	__unlock-0x4
 31c:	eb e6                	jmp    304 <malloc_slow+0x304>
 31e:	4c 89 ef             	mov    %r13,%rdi
 321:	e8 00 00 00 00       	call   326 <malloc_slow+0x326>
			322: R_X86_64_PLT32	__lock-0x4
 326:	e9 71 fd ff ff       	jmp    9c <malloc_slow+0x9c>
 32b:	48 89 de             	mov    %rbx,%rsi
 32e:	89 ef                	mov    %ebp,%edi
 330:	e8 00 00 00 00       	call   335 <malloc_slow+0x335>
			331: R_X86_64_PC32	.text.alloc_slot-0x4
 335:	48 8d 15 00 00 00 00 	lea    0x0(%rip),%rdx        # 33c <malloc_slow+0x33c>
			338: R_X86_64_PC32	__malloc_context-0x4
 33c:	83 f8 ff             	cmp    $0xffffffff,%eax
 33f:	41 89 c4             	mov    %eax,%r12d
 342:	74 13                	je     357 <malloc_slow+0x357>
 344:	4e 8b 7c f2 50       	mov    0x50(%rdx,%r14,8),%r15
 349:	8b 2d 00 00 00 00    	mov    0x0(%rip),%ebp        # 34f <malloc_slow+0x34f>
			34b: R_X86_64_PC32	__malloc_context+0x8
 34f:	4c 63 f0             	movslq %eax,%r14
 352:	e9 c7 fe ff ff       	jmp    21e <malloc_slow+0x21e>
 357:	8b 05 00 00 00 00    	mov    0x0(%rip),%eax        # 35d <malloc_slow+0x35d>
			359: R_X86_64_PC32	__malloc_lock-0x4
 35d:	85 c0                	test   %eax,%eax
 35f:	0f 89 87 fd ff ff    	jns    ec <malloc_slow+0xec>
 365:	4c 89 ef             	mov    %r13,%rdi
 368:	e8 00 00 00 00       	call   36d <malloc_slow+0x36d>
			369: R_X86_64_PLT32	__unlock-0x4
 36d:	e9 7a fd ff ff       	jmp    ec <malloc_slow+0xec>
 372:	4c 89 ef             	mov    %r13,%rdi
 375:	e8 00 00 00 00       	call   37a <malloc_slow+0x37a>
			376: R_X86_64_PLT32	__unlock-0x4
 37a:	e9 ad fe ff ff       	jmp    22c <malloc_slow+0x22c>
 37f:	41 0f b7 57 20       	movzwl 0x20(%r15),%edx
 384:	48 8d 0d 00 00 00 00 	lea    0x0(%rip),%rcx        # 38b <malloc_slow+0x38b>
			387: R_X86_64_PC32	__malloc_size_classes-0x4
 38b:	66 c1 ea 06          	shr    $0x6,%dx
 38f:	83 e2 3f             	and    $0x3f,%edx
 392:	0f b7 14 51          	movzwl (%rcx,%rdx,2),%edx
 396:	c1 e2 04             	shl    $0x4,%edx
 399:	48 63 d2             	movslq %edx,%rdx
 39c:	4c 89 f0             	mov    %r14,%rax
 39f:	4d 8b 47 10          	mov    0x10(%r15),%r8
 3a3:	48 89 d1             	mov    %rdx,%rcx
 3a6:	48 0f af c2          	imul   %rdx,%rax
 3aa:	48 29 d9             	sub    %rbx,%rcx
 3ad:	49 83 c0 10          	add    $0x10,%r8
 3b1:	48 83 e9 04          	sub    $0x4,%rcx
 3b5:	4c 01 c0             	add    %r8,%rax
 3b8:	0f b6 70 fc          	movzbl -0x4(%rax),%esi
 3bc:	48 8d 7c 10 fc       	lea    -0x4(%rax,%rdx,1),%rdi
 3c1:	40 84 f6             	test   %sil,%sil
 3c4:	0f 85 00 00 00 00    	jne    3ca <malloc_slow+0x3ca>
			3c6: R_X86_64_PC32	.text.unlikely.malloc_slow-0x4
 3ca:	48 83 f9 0f          	cmp    $0xf,%rcx
 3ce:	76 7b                	jbe    44b <malloc_slow+0x44b>
 3d0:	80 78 fd 00          	cmpb   $0x0,-0x3(%rax)
 3d4:	40 0f b6 d5          	movzbl %bpl,%edx
 3d8:	74 0a                	je     3e4 <malloc_slow+0x3e4>
 3da:	0f b7 50 fe          	movzwl -0x2(%rax),%edx
 3de:	83 c2 01             	add    $0x1,%edx
 3e1:	0f b6 d2             	movzbl %dl,%edx
 3e4:	49 89 ca             	mov    %rcx,%r10
 3e7:	4c 63 ca             	movslq %edx,%r9
 3ea:	49 c1 ea 04          	shr    $0x4,%r10
 3ee:	4d 39 ca             	cmp    %r9,%r10
 3f1:	73 37                	jae    42a <malloc_slow+0x42a>
 3f3:	48 c1 e9 05          	shr    $0x5,%rcx
 3f7:	4c 09 d1             	or     %r10,%rcx
 3fa:	49 89 c9             	mov    %rcx,%r9
 3fd:	49 c1 e9 02          	shr    $0x2,%r9
 401:	4c 09 c9             	or     %r9,%rcx
 404:	49 89 c9             	mov    %rcx,%r9
 407:	49 c1 e9 04          	shr    $0x4,%r9
 40b:	4c 09 c9             	or     %r9,%rcx
 40e:	21 ca                	and    %ecx,%edx
 410:	48 63 ca             	movslq %edx,%rcx
 413:	49 39 ca             	cmp    %rcx,%r10
 416:	73 12                	jae    42a <malloc_slow+0x42a>
 418:	44 29 d2             	sub    %r10d,%edx
 41b:	83 ea 01             	sub    $0x1,%edx
 41e:	48 63 ca             	movslq %edx,%rcx
 421:	49 39 ca             	cmp    %rcx,%r10
 424:	0f 82 00 00 00 00    	jb     42a <malloc_slow+0x42a>
			426: R_X86_64_PC32	.text.unlikely.malloc_slow-0x4
 42a:	85 d2                	test   %edx,%edx
 42c:	74 1d                	je     44b <malloc_slow+0x44b>
 42e:	66 89 50 fe          	mov    %dx,-0x2(%rax)
 432:	c1 e2 04             	shl    $0x4,%edx
 435:	48 63 ca             	movslq %edx,%rcx
 438:	c6 40 fd e0          	movb   $0xe0,-0x3(%rax)
 43c:	48 01 c8             	add    %rcx,%rax
 43f:	c6 40 fc 00          	movb   $0x0,-0x4(%rax)
 443:	4d 8b 47 10          	mov    0x10(%r15),%r8
 447:	49 83 c0 10          	add    $0x10,%r8
 44b:	48 89 c2             	mov    %rax,%rdx
 44e:	48 89 f9             	mov    %rdi,%rcx
 451:	4c 29 c2             	sub    %r8,%rdx
 454:	48 29 c1             	sub    %rax,%rcx
 457:	48 c1 ea 04          	shr    $0x4,%rdx
 45b:	66 89 50 fe          	mov    %dx,-0x2(%rax)
 45f:	29 d9                	sub    %ebx,%ecx
 461:	74 15                	je     478 <malloc_slow+0x478>
 463:	89 ca                	mov    %ecx,%edx
 465:	f7 da                	neg    %edx
 467:	48 63 d2             	movslq %edx,%rdx
 46a:	c6 04 17 00          	movb   $0x0,(%rdi,%rdx,1)
 46e:	83 f9 04             	cmp    $0x4,%ecx
 471:	7f 1b                	jg     48e <malloc_slow+0x48e>
 473:	89 ce                	mov    %ecx,%esi
 475:	c1 e6 05             	shl    $0x5,%esi
 478:	42 8d 14 26          	lea    (%rsi,%r12,1),%edx
 47c:	88 50 fd             	mov    %dl,-0x3(%rax)
 47f:	48 83 c4 08          	add    $0x8,%rsp
 483:	5b                   	pop    %rbx
 484:	5d                   	pop    %rbp
 485:	41 5c                	pop    %r12
 487:	41 5d                	pop    %r13
 489:	41 5e                	pop    %r14
 48b:	41 5f                	pop    %r15
 48d:	c3                   	ret
 48e:	89 4f fc             	mov    %ecx,-0x4(%rdi)
 491:	be a0 ff ff ff       	mov    $0xffffffa0,%esi
 496:	c6 47 fb 00          	movb   $0x0,-0x5(%rdi)
 49a:	eb dc                	jmp    478 <malloc_slow+0x478>

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
  e0:	75 54                	jne    136 <__malloc_allzerop+0x136>
  e2:	31 c9                	xor    %ecx,%ecx
  e4:	83 e6 1f             	and    $0x1f,%esi
  e7:	75 4a                	jne    133 <__malloc_allzerop+0x133>
  e9:	48 81 78 20 ff 0f 00 	cmpq   $0xfff,0x20(%rax)
  f0:	00 
  f1:	76 40                	jbe    133 <__malloc_allzerop+0x133>
  f3:	c1 e7 04             	shl    $0x4,%edi
  f6:	48 83 ea 10          	sub    $0x10,%rdx
  fa:	31 c9                	xor    %ecx,%ecx
  fc:	48 63 ff             	movslq %edi,%rdi
  ff:	48 39 fa             	cmp    %rdi,%rdx
 102:	0f 92 c1             	setb   %cl
 105:	eb 2c                	jmp    133 <__malloc_allzerop+0x133>
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
 12f:	75 1e                	jne    14f <__malloc_allzerop+0x14f>
 131:	31 c9                	xor    %ecx,%ecx
 133:	89 c8                	mov    %ecx,%eax
 135:	c3                   	ret
 136:	48 c1 e2 0c          	shl    $0xc,%rdx
 13a:	49 89 d0             	mov    %rdx,%r8
 13d:	49 c1 e8 04          	shr    $0x4,%r8
 141:	49 83 e8 01          	sub    $0x1,%r8
 145:	49 39 c8             	cmp    %rcx,%r8
 148:	73 98                	jae    e2 <__malloc_allzerop+0xe2>
 14a:	e9 00 00 00 00       	jmp    14f <__malloc_allzerop+0x14f>
			14b: R_X86_64_PC32	.text.unlikely.__malloc_allzerop-0x4
 14f:	48 c1 e0 08          	shl    $0x8,%rax
 153:	48 8d 50 ff          	lea    -0x1(%rax),%rdx
 157:	48 63 c1             	movslq %ecx,%rax
 15a:	48 39 c2             	cmp    %rax,%rdx
 15d:	0f 82 00 00 00 00    	jb     163 <__malloc_allzerop+0x163>
			15f: R_X86_64_PC32	.text.unlikely.__malloc_allzerop-0x4
 163:	eb cc                	jmp    131 <__malloc_allzerop+0x131>

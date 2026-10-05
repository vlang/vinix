
/Users/alex/code/vinix/third_party/useralloc-libc/build/musl/x86_64/2d7970354b905edb5dc4d022050bac166373b2b2d4ea254b78762cc89e0cf019/objects/obj/src/malloc/mallocng/malloc.lo:     file format elf64-x86-64


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
  1b:	48 83 ec 28          	sub    $0x28,%rsp
  1f:	49 8b 14 c7          	mov    (%r15,%rax,8),%rdx
  23:	48 85 d2             	test   %rdx,%rdx
  26:	74 4f                	je     77 <alloc_slot+0x77>
  28:	8b 4a 18             	mov    0x18(%rdx),%ecx
  2b:	85 c9                	test   %ecx,%ecx
  2d:	0f 85 c5 01 00 00    	jne    1f8 <alloc_slot+0x1f8>
  33:	8b 7a 1c             	mov    0x1c(%rdx),%edi
  36:	48 8b 4a 08          	mov    0x8(%rdx),%rcx
  3a:	85 ff                	test   %edi,%edi
  3c:	0f 85 e7 00 00 00    	jne    129 <alloc_slot+0x129>
  42:	48 39 ca             	cmp    %rcx,%rdx
  45:	0f 84 d1 00 00 00    	je     11c <alloc_slot+0x11c>
  4b:	48 8b 3a             	mov    (%rdx),%rdi
  4e:	48 89 4f 08          	mov    %rcx,0x8(%rdi)
  52:	48 8b 3a             	mov    (%rdx),%rdi
  55:	48 89 39             	mov    %rdi,(%rcx)
  58:	49 3b 14 c7          	cmp    (%r15,%rax,8),%rdx
  5c:	0f 84 ad 00 00 00    	je     10f <alloc_slot+0x10f>
  62:	66 0f ef c0          	pxor   %xmm0,%xmm0
  66:	0f 11 02             	movups %xmm0,(%rdx)
  69:	4b 8b 54 f7 50       	mov    0x50(%r15,%r14,8),%rdx
  6e:	48 85 d2             	test   %rdx,%rdx
  71:	0f 85 b9 00 00 00    	jne    130 <alloc_slot+0x130>
  77:	4c 8d 05 00 00 00 00 	lea    0x0(%rip),%r8        # 7e <alloc_slot+0x7e>
			7a: R_X86_64_PC32	__malloc_size_classes-0x4
  7e:	48 89 74 24 10       	mov    %rsi,0x10(%rsp)
  83:	47 0f b7 24 70       	movzwl (%r8,%r14,2),%r12d
  88:	e8 00 00 00 00       	call   8d <alloc_slot+0x8d>
			89: R_X86_64_PLT32	__malloc_alloc_meta-0x4
  8d:	66 48 0f 6e c8       	movq   %rax,%xmm1
  92:	41 c1 e4 04          	shl    $0x4,%r12d
  96:	48 89 c5             	mov    %rax,%rbp
  99:	66 0f 6c c9          	punpcklqdq %xmm1,%xmm1
  9d:	4d 63 e4             	movslq %r12d,%r12
  a0:	0f 29 0c 24          	movaps %xmm1,(%rsp)
  a4:	48 85 c0             	test   %rax,%rax
  a7:	0f 84 b2 07 00 00    	je     85f <alloc_slot+0x85f>
  ad:	41 83 fd 08          	cmp    $0x8,%r13d
  b1:	4b 8b 8c f7 f8 01 00 	mov    0x1f8(%r15,%r14,8),%rcx
  b8:	00 
  b9:	48 8b 74 24 10       	mov    0x10(%rsp),%rsi
  be:	4c 8d 05 00 00 00 00 	lea    0x0(%rip),%r8        # c5 <alloc_slot+0xc5>
			c1: R_X86_64_PC32	__malloc_size_classes-0x4
  c5:	0f 8f 0b 02 00 00    	jg     2d6 <alloc_slot+0x2d6>
  cb:	4b 8d 14 76          	lea    (%r14,%r14,2),%rdx
  cf:	48 8d 05 00 00 00 00 	lea    0x0(%rip),%rax        # d6 <alloc_slot+0xd6>
			d2: R_X86_64_PC32	.rodata.small_cnt_tab-0x4
  d6:	48 01 d0             	add    %rdx,%rax
  d9:	0f b6 18             	movzbl (%rax),%ebx
  dc:	8d 14 9d 00 00 00 00 	lea    0x0(,%rbx,4),%edx
  e3:	48 63 d2             	movslq %edx,%rdx
  e6:	48 39 d1             	cmp    %rdx,%rcx
  e9:	0f 83 42 02 00 00    	jae    331 <alloc_slot+0x331>
  ef:	0f b6 58 01          	movzbl 0x1(%rax),%ebx
  f3:	8d 14 9d 00 00 00 00 	lea    0x0(,%rbx,4),%edx
  fa:	48 63 d2             	movslq %edx,%rdx
  fd:	48 39 d1             	cmp    %rdx,%rcx
 100:	0f 83 2b 02 00 00    	jae    331 <alloc_slot+0x331>
 106:	0f b6 58 02          	movzbl 0x2(%rax),%ebx
 10a:	e9 22 02 00 00       	jmp    331 <alloc_slot+0x331>
 10f:	48 8b 4a 08          	mov    0x8(%rdx),%rcx
 113:	49 89 0c c7          	mov    %rcx,(%r15,%rax,8)
 117:	e9 46 ff ff ff       	jmp    62 <alloc_slot+0x62>
 11c:	49 c7 04 c7 00 00 00 	movq   $0x0,(%r15,%rax,8)
 123:	00 
 124:	e9 39 ff ff ff       	jmp    62 <alloc_slot+0x62>
 129:	49 89 0c c7          	mov    %rcx,(%r15,%rax,8)
 12d:	48 89 ca             	mov    %rcx,%rdx
 130:	0f b6 4a 20          	movzbl 0x20(%rdx),%ecx
 134:	b8 02 00 00 00       	mov    $0x2,%eax
 139:	44 8b 42 1c          	mov    0x1c(%rdx),%r8d
 13d:	d3 e0                	shl    %cl,%eax
 13f:	83 e8 01             	sub    $0x1,%eax
 142:	41 39 c0             	cmp    %eax,%r8d
 145:	0f 84 d3 00 00 00    	je     21e <alloc_slot+0x21e>
 14b:	48 8b 7a 10          	mov    0x10(%rdx),%rdi
 14f:	b8 02 00 00 00       	mov    $0x2,%eax
 154:	0f b6 4f 08          	movzbl 0x8(%rdi),%ecx
 158:	d3 e0                	shl    %cl,%eax
 15a:	41 89 ca             	mov    %ecx,%r10d
 15d:	83 e8 01             	sub    $0x1,%eax
 160:	41 83 e2 1f          	and    $0x1f,%r10d
 164:	44 85 c0             	test   %r8d,%eax
 167:	75 15                	jne    17e <alloc_slot+0x17e>
 169:	4c 8b 4a 08          	mov    0x8(%rdx),%r9
 16d:	4c 39 ca             	cmp    %r9,%rdx
 170:	0f 84 c3 00 00 00    	je     239 <alloc_slot+0x239>
 176:	4f 89 4c f7 50       	mov    %r9,0x50(%r15,%r14,8)
 17b:	4c 89 ca             	mov    %r9,%rdx
 17e:	8b 42 18             	mov    0x18(%rdx),%eax
 181:	85 c0                	test   %eax,%eax
 183:	0f 85 00 00 00 00    	jne    189 <alloc_slot+0x189>
			185: R_X86_64_PC32	.text.unlikely.alloc_slot-0x4
 189:	48 8b 42 10          	mov    0x10(%rdx),%rax
 18d:	41 b9 02 00 00 00    	mov    $0x2,%r9d
 193:	4c 8d 52 1c          	lea    0x1c(%rdx),%r10
 197:	0f b6 48 08          	movzbl 0x8(%rax),%ecx
 19b:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 1a2 <alloc_slot+0x1a2>
			19e: R_X86_64_PC32	__libc-0x1
 1a2:	41 d3 e1             	shl    %cl,%r9d
 1a5:	45 8d 41 ff          	lea    -0x1(%r9),%r8d
 1a9:	41 f7 d9             	neg    %r9d
 1ac:	84 c0                	test   %al,%al
 1ae:	0f 85 0a 01 00 00    	jne    2be <alloc_slot+0x2be>
 1b4:	8b 4a 1c             	mov    0x1c(%rdx),%ecx
 1b7:	41 21 c9             	and    %ecx,%r9d
 1ba:	44 89 4a 1c          	mov    %r9d,0x1c(%rdx)
 1be:	44 21 c1             	and    %r8d,%ecx
 1c1:	89 4a 18             	mov    %ecx,0x18(%rdx)
 1c4:	0f 84 00 00 00 00    	je     1ca <alloc_slot+0x1ca>
			1c6: R_X86_64_PC32	.text.unlikely.alloc_slot-0x4
 1ca:	0f b7 42 20          	movzwl 0x20(%rdx),%eax
 1ce:	66 c1 e8 06          	shr    $0x6,%ax
 1d2:	83 e0 3f             	and    $0x3f,%eax
 1d5:	83 e8 07             	sub    $0x7,%eax
 1d8:	83 f8 1f             	cmp    $0x1f,%eax
 1db:	77 1b                	ja     1f8 <alloc_slot+0x1f8>
 1dd:	48 98                	cltq
 1df:	41 0f b6 bc 07 98 03 	movzbl 0x398(%r15,%rax,1),%edi
 1e6:	00 00 
 1e8:	40 84 ff             	test   %dil,%dil
 1eb:	74 0b                	je     1f8 <alloc_slot+0x1f8>
 1ed:	83 ef 01             	sub    $0x1,%edi
 1f0:	41 88 bc 07 98 03 00 	mov    %dil,0x398(%r15,%rax,1)
 1f7:	00 
 1f8:	89 c8                	mov    %ecx,%eax
 1fa:	f7 d8                	neg    %eax
 1fc:	21 c8                	and    %ecx,%eax
 1fe:	29 c1                	sub    %eax,%ecx
 200:	89 4a 18             	mov    %ecx,0x18(%rdx)
 203:	85 c0                	test   %eax,%eax
 205:	0f 84 6c fe ff ff    	je     77 <alloc_slot+0x77>
 20b:	f3 0f bc c0          	tzcnt  %eax,%eax
 20f:	48 83 c4 28          	add    $0x28,%rsp
 213:	5b                   	pop    %rbx
 214:	5d                   	pop    %rbp
 215:	41 5c                	pop    %r12
 217:	41 5d                	pop    %r13
 219:	41 5e                	pop    %r14
 21b:	41 5f                	pop    %r15
 21d:	c3                   	ret
 21e:	83 e1 20             	and    $0x20,%ecx
 221:	0f 84 57 ff ff ff    	je     17e <alloc_slot+0x17e>
 227:	48 8b 52 08          	mov    0x8(%rdx),%rdx
 22b:	4b 89 54 f7 50       	mov    %rdx,0x50(%r15,%r14,8)
 230:	44 8b 42 1c          	mov    0x1c(%rdx),%r8d
 234:	e9 12 ff ff ff       	jmp    14b <alloc_slot+0x14b>
 239:	41 0f b7 41 20       	movzwl 0x20(%r9),%eax
 23e:	48 8d 15 00 00 00 00 	lea    0x0(%rip),%rdx        # 245 <alloc_slot+0x245>
			241: R_X86_64_PC32	__malloc_size_classes-0x4
 245:	41 8d 4a 02          	lea    0x2(%r10),%ecx
 249:	66 c1 e8 06          	shr    $0x6,%ax
 24d:	83 e0 3f             	and    $0x3f,%eax
 250:	44 0f b7 14 42       	movzwl (%rdx,%rax,2),%r10d
 255:	89 ca                	mov    %ecx,%edx
 257:	41 c1 e2 04          	shl    $0x4,%r10d
 25b:	41 0f af d2          	imul   %r10d,%edx
 25f:	83 c2 10             	add    $0x10,%edx
 262:	eb 22                	jmp    286 <alloc_slot+0x286>
 264:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
 26b:	00 00 00 00 
 26f:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
 276:	00 00 00 00 
 27a:	66 0f 1f 44 00 00    	nopw   0x0(%rax,%rax,1)
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
 2b9:	e9 bd fe ff ff       	jmp    17b <alloc_slot+0x17b>
 2be:	8b 4a 1c             	mov    0x1c(%rdx),%ecx
 2c1:	89 cf                	mov    %ecx,%edi
 2c3:	89 c8                	mov    %ecx,%eax
 2c5:	44 21 cf             	and    %r9d,%edi
 2c8:	f0 41 0f b1 3a       	lock cmpxchg %edi,(%r10)
 2cd:	39 c1                	cmp    %eax,%ecx
 2cf:	75 ed                	jne    2be <alloc_slot+0x2be>
 2d1:	e9 e8 fe ff ff       	jmp    1be <alloc_slot+0x1be>
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
 36a:	0f 86 15 04 00 00    	jbe    785 <alloc_slot+0x785>
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
 3b2:	0f 86 cd 03 00 00    	jbe    785 <alloc_slot+0x785>
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
 4ab:	4c 89 54 24 10       	mov    %r10,0x10(%rsp)
 4b0:	e8 00 00 00 00       	call   4b5 <alloc_slot+0x4b5>
			4b1: R_X86_64_PLT32	__mmap-0x4
 4b5:	4c 8b 54 24 10       	mov    0x10(%rsp),%r10
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
 59b:	0f 84 35 04 00 00    	je     9d6 <alloc_slot+0x9d6>
 5a1:	48 89 45 08          	mov    %rax,0x8(%rbp)
 5a5:	48 8b 00             	mov    (%rax),%rax
 5a8:	48 89 45 00          	mov    %rax,0x0(%rbp)
 5ac:	48 89 68 08          	mov    %rbp,0x8(%rax)
 5b0:	48 8b 45 08          	mov    0x8(%rbp),%rax
 5b4:	48 89 28             	mov    %rbp,(%rax)
 5b7:	31 c0                	xor    %eax,%eax
 5b9:	e9 51 fc ff ff       	jmp    20f <alloc_slot+0x20f>
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
 60c:	48 89 7c 24 10       	mov    %rdi,0x10(%rsp)
 611:	0f b6 3d 00 00 00 00 	movzbl 0x0(%rip),%edi        # 618 <alloc_slot+0x618>
			614: R_X86_64_PC32	__malloc_context+0x3b4
 618:	45 85 d2             	test   %r10d,%r10d
 61b:	0f 84 c7 fd ff ff    	je     3e8 <alloc_slot+0x3e8>
 621:	44 0f b6 df          	movzbl %dil,%r11d
 625:	45 29 d3             	sub    %r10d,%r11d
 628:	41 83 fb 09          	cmp    $0x9,%r11d
 62c:	0f 8f b6 fd ff ff    	jg     3e8 <alloc_slot+0x3e8>
 632:	4c 8b 5c 24 10       	mov    0x10(%rsp),%r11
 637:	47 0f b6 94 1f 98 03 	movzbl 0x398(%r15,%r11,1),%r10d
 63e:	00 00 
 640:	45 8d 5a 01          	lea    0x1(%r10),%r11d
 644:	41 80 fa 63          	cmp    $0x63,%r10b
 648:	41 ba 96 ff ff ff    	mov    $0xffffff96,%r10d
 64e:	45 0f 43 da          	cmovae %r10d,%r11d
 652:	4c 8b 54 24 10       	mov    0x10(%rsp),%r10
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
 76a:	0f 85 d9 00 00 00    	jne    849 <alloc_slot+0x849>
 770:	66 0f 6f 1c 24       	movdqa (%rsp),%xmm3
 775:	0f 11 5d 00          	movups %xmm3,0x0(%rbp)
 779:	48 89 2d 00 00 00 00 	mov    %rbp,0x0(%rip)        # 780 <alloc_slot+0x780>
			77c: R_X86_64_PC32	__malloc_context+0xc
 780:	e9 da 00 00 00       	jmp    85f <alloc_slot+0x85f>
 785:	48 89 c2             	mov    %rax,%rdx
 788:	48 8d 70 0c          	lea    0xc(%rax),%rsi
 78c:	48 c1 ea 04          	shr    $0x4,%rdx
 790:	89 d1                	mov    %edx,%ecx
 792:	48 3d 90 00 00 00    	cmp    $0x90,%rax
 798:	76 30                	jbe    7ca <alloc_slot+0x7ca>
 79a:	48 8d 42 01          	lea    0x1(%rdx),%rax
 79e:	0f bd d0             	bsr    %eax,%edx
 7a1:	8d 0c 95 fc ff ff ff 	lea    -0x4(,%rdx,4),%ecx
 7a8:	8d 51 01             	lea    0x1(%rcx),%edx
 7ab:	48 63 d2             	movslq %edx,%rdx
 7ae:	41 0f b7 3c 50       	movzwl (%r8,%rdx,2),%edi
 7b3:	8d 51 02             	lea    0x2(%rcx),%edx
 7b6:	48 39 c7             	cmp    %rax,%rdi
 7b9:	0f 42 ca             	cmovb  %edx,%ecx
 7bc:	48 63 d1             	movslq %ecx,%rdx
 7bf:	41 0f b7 14 50       	movzwl (%r8,%rdx,2),%edx
 7c4:	48 39 c2             	cmp    %rax,%rdx
 7c7:	83 d1 00             	adc    $0x0,%ecx
 7ca:	89 cf                	mov    %ecx,%edi
 7cc:	4c 89 4c 24 18       	mov    %r9,0x18(%rsp)
 7d1:	89 4c 24 10          	mov    %ecx,0x10(%rsp)
 7d5:	e8 26 f8 ff ff       	call   0 <alloc_slot>
 7da:	48 63 4c 24 10       	movslq 0x10(%rsp),%rcx
 7df:	4c 8b 4c 24 18       	mov    0x18(%rsp),%r9
 7e4:	4c 8d 05 00 00 00 00 	lea    0x0(%rip),%r8        # 7eb <alloc_slot+0x7eb>
			7e7: R_X86_64_PC32	__malloc_size_classes-0x4
 7eb:	83 f8 ff             	cmp    $0xffffffff,%eax
 7ee:	89 c2                	mov    %eax,%edx
 7f0:	74 37                	je     829 <alloc_slot+0x829>
 7f2:	41 0f b7 04 48       	movzwl (%r8,%rcx,2),%eax
 7f7:	49 8b 7c cf 50       	mov    0x50(%r15,%rcx,8),%rdi
 7fc:	c1 e0 04             	shl    $0x4,%eax
 7ff:	83 e8 04             	sub    $0x4,%eax
 802:	89 44 24 18          	mov    %eax,0x18(%rsp)
 806:	48 63 c8             	movslq %eax,%rcx
 809:	f6 47 20 1f          	testb  $0x1f,0x20(%rdi)
 80d:	75 6c                	jne    87b <alloc_slot+0x87b>
 80f:	48 81 7f 20 ff 0f 00 	cmpq   $0xfff,0x20(%rdi)
 816:	00 
 817:	76 62                	jbe    87b <alloc_slot+0x87b>
 819:	48 8b 47 20          	mov    0x20(%rdi),%rax
 81d:	48 25 00 f0 ff ff    	and    $0xfffffffffffff000,%rax
 823:	48 83 e8 10          	sub    $0x10,%rax
 827:	eb 67                	jmp    890 <alloc_slot+0x890>
 829:	66 0f ef c0          	pxor   %xmm0,%xmm0
 82d:	48 c7 45 20 00 00 00 	movq   $0x0,0x20(%rbp)
 834:	00 
 835:	0f 11 45 00          	movups %xmm0,0x0(%rbp)
 839:	0f 11 45 10          	movups %xmm0,0x10(%rbp)
 83d:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 844 <alloc_slot+0x844>
			840: R_X86_64_PC32	__malloc_context+0xc
 844:	48 85 c0             	test   %rax,%rax
 847:	74 20                	je     869 <alloc_slot+0x869>
 849:	48 89 45 08          	mov    %rax,0x8(%rbp)
 84d:	48 8b 00             	mov    (%rax),%rax
 850:	48 89 45 00          	mov    %rax,0x0(%rbp)
 854:	48 89 68 08          	mov    %rbp,0x8(%rax)
 858:	48 8b 45 08          	mov    0x8(%rbp),%rax
 85c:	48 89 28             	mov    %rbp,(%rax)
 85f:	b8 ff ff ff ff       	mov    $0xffffffff,%eax
 864:	e9 a6 f9 ff ff       	jmp    20f <alloc_slot+0x20f>
 869:	66 0f 6f 24 24       	movdqa (%rsp),%xmm4
 86e:	0f 11 65 00          	movups %xmm4,0x0(%rbp)
 872:	48 89 2d 00 00 00 00 	mov    %rbp,0x0(%rip)        # 879 <alloc_slot+0x879>
			875: R_X86_64_PC32	__malloc_context+0xc
 879:	eb e4                	jmp    85f <alloc_slot+0x85f>
 87b:	0f b7 47 20          	movzwl 0x20(%rdi),%eax
 87f:	66 c1 e8 06          	shr    $0x6,%ax
 883:	83 e0 3f             	and    $0x3f,%eax
 886:	41 0f b7 04 40       	movzwl (%r8,%rax,2),%eax
 88b:	c1 e0 04             	shl    $0x4,%eax
 88e:	48 98                	cltq
 890:	48 89 c6             	mov    %rax,%rsi
 893:	48 29 ce             	sub    %rcx,%rsi
 896:	48 8b 4f 10          	mov    0x10(%rdi),%rcx
 89a:	4c 8d 46 fc          	lea    -0x4(%rsi),%r8
 89e:	48 63 f2             	movslq %edx,%rsi
 8a1:	48 0f af f0          	imul   %rax,%rsi
 8a5:	48 83 c1 10          	add    $0x10,%rcx
 8a9:	4d 89 c2             	mov    %r8,%r10
 8ac:	49 c1 ea 04          	shr    $0x4,%r10
 8b0:	48 01 ce             	add    %rcx,%rsi
 8b3:	48 8d 44 06 fc       	lea    -0x4(%rsi,%rax,1),%rax
 8b8:	80 7e fd 00          	cmpb   $0x0,-0x3(%rsi)
 8bc:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
 8c1:	0f 84 f0 00 00 00    	je     9b7 <alloc_slot+0x9b7>
 8c7:	0f b7 46 fe          	movzwl -0x2(%rsi),%eax
 8cb:	83 c0 01             	add    $0x1,%eax
 8ce:	0f b6 c0             	movzbl %al,%eax
 8d1:	80 7e fc 00          	cmpb   $0x0,-0x4(%rsi)
 8d5:	0f 85 00 00 00 00    	jne    8db <alloc_slot+0x8db>
			8d7: R_X86_64_PC32	.text.unlikely.alloc_slot-0x4
 8db:	4c 63 d8             	movslq %eax,%r11
 8de:	4d 39 da             	cmp    %r11,%r10
 8e1:	73 38                	jae    91b <alloc_slot+0x91b>
 8e3:	49 c1 e8 05          	shr    $0x5,%r8
 8e7:	4d 09 d0             	or     %r10,%r8
 8ea:	4d 89 c3             	mov    %r8,%r11
 8ed:	49 c1 eb 02          	shr    $0x2,%r11
 8f1:	4d 09 d8             	or     %r11,%r8
 8f4:	4d 89 c3             	mov    %r8,%r11
 8f7:	49 c1 eb 04          	shr    $0x4,%r11
 8fb:	4d 09 d8             	or     %r11,%r8
 8fe:	44 21 c0             	and    %r8d,%eax
 901:	4c 63 c0             	movslq %eax,%r8
 904:	4d 39 c2             	cmp    %r8,%r10
 907:	73 12                	jae    91b <alloc_slot+0x91b>
 909:	44 29 d0             	sub    %r10d,%eax
 90c:	83 e8 01             	sub    $0x1,%eax
 90f:	4c 63 c0             	movslq %eax,%r8
 912:	4d 39 c2             	cmp    %r8,%r10
 915:	0f 82 00 00 00 00    	jb     91b <alloc_slot+0x91b>
			917: R_X86_64_PC32	.text.unlikely.alloc_slot-0x4
 91b:	85 c0                	test   %eax,%eax
 91d:	74 1c                	je     93b <alloc_slot+0x93b>
 91f:	66 89 46 fe          	mov    %ax,-0x2(%rsi)
 923:	c1 e0 04             	shl    $0x4,%eax
 926:	48 98                	cltq
 928:	c6 46 fd e0          	movb   $0xe0,-0x3(%rsi)
 92c:	48 01 c6             	add    %rax,%rsi
 92f:	c6 46 fc 00          	movb   $0x0,-0x4(%rsi)
 933:	48 8b 4f 10          	mov    0x10(%rdi),%rcx
 937:	48 83 c1 10          	add    $0x10,%rcx
 93b:	48 89 f0             	mov    %rsi,%rax
 93e:	48 8b 7c 24 10       	mov    0x10(%rsp),%rdi
 943:	88 56 fd             	mov    %dl,-0x3(%rsi)
 946:	48 29 c8             	sub    %rcx,%rax
 949:	89 d1                	mov    %edx,%ecx
 94b:	8b 54 24 18          	mov    0x18(%rsp),%edx
 94f:	48 c1 e8 04          	shr    $0x4,%rax
 953:	66 89 46 fe          	mov    %ax,-0x2(%rsi)
 957:	48 89 f8             	mov    %rdi,%rax
 95a:	48 29 f0             	sub    %rsi,%rax
 95d:	29 d0                	sub    %edx,%eax
 95f:	74 1c                	je     97d <alloc_slot+0x97d>
 961:	89 c2                	mov    %eax,%edx
 963:	f7 da                	neg    %edx
 965:	48 63 d2             	movslq %edx,%rdx
 968:	c6 04 17 00          	movb   $0x0,(%rdi,%rdx,1)
 96c:	83 f8 04             	cmp    $0x4,%eax
 96f:	7f 52                	jg     9c3 <alloc_slot+0x9c3>
 971:	0f b6 4e fd          	movzbl -0x3(%rsi),%ecx
 975:	c1 e0 05             	shl    $0x5,%eax
 978:	83 e1 1f             	and    $0x1f,%ecx
 97b:	01 c1                	add    %eax,%ecx
 97d:	88 4e fd             	mov    %cl,-0x3(%rsi)
 980:	48 8d 56 0c          	lea    0xc(%rsi),%rdx
 984:	8d 4b 01             	lea    0x1(%rbx),%ecx
 987:	48 81 65 20 ff 0f 00 	andq   $0xfff,0x20(%rbp)
 98e:	00 
 98f:	0f b6 46 fd          	movzbl -0x3(%rsi),%eax
 993:	83 e0 1f             	and    $0x1f,%eax
 996:	83 c8 c0             	or     $0xffffffc0,%eax
 999:	88 46 fd             	mov    %al,-0x3(%rsi)
 99c:	31 c0                	xor    %eax,%eax
 99e:	66 90                	xchg   %ax,%ax
 9a0:	83 c0 01             	add    $0x1,%eax
 9a3:	c6 02 00             	movb   $0x0,(%rdx)
 9a6:	4c 01 e2             	add    %r12,%rdx
 9a9:	39 c8                	cmp    %ecx,%eax
 9ab:	75 f3                	jne    9a0 <alloc_slot+0x9a0>
 9ad:	8d 53 ff             	lea    -0x1(%rbx),%edx
 9b0:	89 d7                	mov    %edx,%edi
 9b2:	e9 4d fb ff ff       	jmp    504 <alloc_slot+0x504>
 9b7:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 9be <alloc_slot+0x9be>
			9ba: R_X86_64_PC32	__malloc_context+0x8
 9be:	e9 0e ff ff ff       	jmp    8d1 <alloc_slot+0x8d1>
 9c3:	89 47 fc             	mov    %eax,-0x4(%rdi)
 9c6:	c6 47 fb 00          	movb   $0x0,-0x5(%rdi)
 9ca:	0f b6 4e fd          	movzbl -0x3(%rsi),%ecx
 9ce:	83 e1 1f             	and    $0x1f,%ecx
 9d1:	83 e9 60             	sub    $0x60,%ecx
 9d4:	eb a7                	jmp    97d <alloc_slot+0x97d>
 9d6:	66 0f 6f 14 24       	movdqa (%rsp),%xmm2
 9db:	0f 11 55 00          	movups %xmm2,0x0(%rbp)
 9df:	4b 89 2c f7          	mov    %rbp,(%r15,%r14,8)
 9e3:	e9 cf fb ff ff       	jmp    5b7 <alloc_slot+0x5b7>

Disassembly of section .text.unlikely.__libc_malloc_impl:

0000000000000000 <__libc_malloc_impl.cold>:
   0:	0f 0b                	ud2

Disassembly of section .text.__libc_malloc_impl:

0000000000000000 <__libc_malloc_impl>:
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
  1b:	0f 82 c0 00 00 00    	jb     e1 <__libc_malloc_impl+0xe1>
  21:	48 89 fd             	mov    %rdi,%rbp
  24:	48 81 ff eb ff 01 00 	cmp    $0x1ffeb,%rdi
  2b:	0f 87 c2 00 00 00    	ja     f3 <__libc_malloc_impl+0xf3>
  31:	48 8d 57 03          	lea    0x3(%rdi),%rdx
  35:	48 89 d0             	mov    %rdx,%rax
  38:	48 c1 e8 04          	shr    $0x4,%rax
  3c:	4c 63 f0             	movslq %eax,%r14
  3f:	4c 89 f3             	mov    %r14,%rbx
  42:	48 81 fa 9f 00 00 00 	cmp    $0x9f,%rdx
  49:	76 3b                	jbe    86 <__libc_malloc_impl+0x86>
  4b:	48 83 c0 01          	add    $0x1,%rax
  4f:	48 8d 0d 00 00 00 00 	lea    0x0(%rip),%rcx        # 56 <__libc_malloc_impl+0x56>
			52: R_X86_64_PC32	__malloc_size_classes-0x4
  56:	0f bd d0             	bsr    %eax,%edx
  59:	8d 1c 95 fc ff ff ff 	lea    -0x4(,%rdx,4),%ebx
  60:	8d 53 01             	lea    0x1(%rbx),%edx
  63:	48 63 d2             	movslq %edx,%rdx
  66:	0f b7 34 51          	movzwl (%rcx,%rdx,2),%esi
  6a:	8d 53 02             	lea    0x2(%rbx),%edx
  6d:	48 39 c6             	cmp    %rax,%rsi
  70:	0f 42 da             	cmovb  %edx,%ebx
  73:	4c 63 f3             	movslq %ebx,%r14
  76:	42 0f b7 14 71       	movzwl (%rcx,%r14,2),%edx
  7b:	48 39 c2             	cmp    %rax,%rdx
  7e:	73 06                	jae    86 <__libc_malloc_impl+0x86>
  80:	83 c3 01             	add    $0x1,%ebx
  83:	4c 63 f3             	movslq %ebx,%r14
  86:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 8d <__libc_malloc_impl+0x8d>
			89: R_X86_64_PC32	__libc-0x1
  8d:	4c 8d 2d 00 00 00 00 	lea    0x0(%rip),%r13        # 94 <__libc_malloc_impl+0x94>
			90: R_X86_64_PC32	__malloc_lock-0x4
  94:	84 c0                	test   %al,%al
  96:	0f 85 82 02 00 00    	jne    31e <__libc_malloc_impl+0x31e>
  9c:	48 8d 15 00 00 00 00 	lea    0x0(%rip),%rdx        # a3 <__libc_malloc_impl+0xa3>
			9f: R_X86_64_PC32	__malloc_context-0x4
  a3:	4e 8b 7c f2 50       	mov    0x50(%rdx,%r14,8),%r15
  a8:	4d 85 ff             	test   %r15,%r15
  ab:	0f 84 7a 02 00 00    	je     32b <__libc_malloc_impl+0x32b>
  b1:	41 8b 47 18          	mov    0x18(%r15),%eax
  b5:	41 89 c4             	mov    %eax,%r12d
  b8:	41 f7 dc             	neg    %r12d
  bb:	41 21 c4             	and    %eax,%r12d
  be:	0f 84 67 02 00 00    	je     32b <__libc_malloc_impl+0x32b>
  c4:	45 31 f6             	xor    %r14d,%r14d
  c7:	44 29 e0             	sub    %r12d,%eax
  ca:	8b 1d 00 00 00 00    	mov    0x0(%rip),%ebx        # d0 <__libc_malloc_impl+0xd0>
			cc: R_X86_64_PC32	__malloc_context+0x8
  d0:	f3 45 0f bc f4       	tzcnt  %r12d,%r14d
  d5:	41 89 47 18          	mov    %eax,0x18(%r15)
  d9:	4d 89 f4             	mov    %r14,%r12
  dc:	e9 3c 01 00 00       	jmp    21d <__libc_malloc_impl+0x21d>
  e1:	e8 00 00 00 00       	call   e6 <__libc_malloc_impl+0xe6>
			e2: R_X86_64_PLT32	___errno_location-0x4
  e6:	c7 00 0c 00 00 00    	movl   $0xc,(%rax)
  ec:	31 c0                	xor    %eax,%eax
  ee:	e9 8a 03 00 00       	jmp    47d <__libc_malloc_impl+0x47d>
  f3:	4c 8d b7 13 10 00 00 	lea    0x1013(%rdi),%r14
  fa:	4c 8d 67 14          	lea    0x14(%rdi),%r12
  fe:	49 c1 ee 0c          	shr    $0xc,%r14
 102:	49 8d 46 e0          	lea    -0x20(%r14),%rax
 106:	48 3d e0 01 00 00    	cmp    $0x1e0,%rax
 10c:	77 6d                	ja     17b <__libc_malloc_impl+0x17b>
 10e:	b8 20 00 00 00       	mov    $0x20,%eax
 113:	31 db                	xor    %ebx,%ebx
 115:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
 11c:	00 00 00 00 
 120:	4c 39 f0             	cmp    %r14,%rax
 123:	73 08                	jae    12d <__libc_malloc_impl+0x12d>
 125:	83 c3 01             	add    $0x1,%ebx
 128:	48 01 c0             	add    %rax,%rax
 12b:	eb f3                	jmp    120 <__libc_malloc_impl+0x120>
 12d:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 134 <__libc_malloc_impl+0x134>
			130: R_X86_64_PC32	__libc-0x1
 134:	4c 8d 2d 00 00 00 00 	lea    0x0(%rip),%r13        # 13b <__libc_malloc_impl+0x13b>
			137: R_X86_64_PC32	__malloc_lock-0x4
 13b:	84 c0                	test   %al,%al
 13d:	0f 85 15 01 00 00    	jne    258 <__libc_malloc_impl+0x258>
 143:	48 63 db             	movslq %ebx,%rbx
 146:	48 8d 15 00 00 00 00 	lea    0x0(%rip),%rdx        # 14d <__libc_malloc_impl+0x14d>
			149: R_X86_64_PC32	__malloc_context-0x4
 14d:	48 83 c3 3a          	add    $0x3a,%rbx
 151:	4c 8b 3c da          	mov    (%rdx,%rbx,8),%r15
 155:	4d 85 ff             	test   %r15,%r15
 158:	74 13                	je     16d <__libc_malloc_impl+0x16d>
 15a:	49 8b 47 20          	mov    0x20(%r15),%rax
 15e:	48 25 00 f0 ff ff    	and    $0xfffffffffffff000,%rax
 164:	4c 39 e0             	cmp    %r12,%rax
 167:	0f 83 f8 00 00 00    	jae    265 <__libc_malloc_impl+0x265>
 16d:	8b 05 00 00 00 00    	mov    0x0(%rip),%eax        # 173 <__libc_malloc_impl+0x173>
			16f: R_X86_64_PC32	__malloc_lock-0x4
 173:	85 c0                	test   %eax,%eax
 175:	0f 88 3c 01 00 00    	js     2b7 <__libc_malloc_impl+0x2b7>
 17b:	45 31 c9             	xor    %r9d,%r9d
 17e:	41 b8 ff ff ff ff    	mov    $0xffffffff,%r8d
 184:	b9 22 00 00 00       	mov    $0x22,%ecx
 189:	31 ff                	xor    %edi,%edi
 18b:	ba 03 00 00 00       	mov    $0x3,%edx
 190:	4c 89 e6             	mov    %r12,%rsi
 193:	e8 00 00 00 00       	call   198 <__libc_malloc_impl+0x198>
			194: R_X86_64_PLT32	__mmap-0x4
 198:	48 89 c3             	mov    %rax,%rbx
 19b:	48 83 f8 ff          	cmp    $0xffffffffffffffff,%rax
 19f:	0f 84 47 ff ff ff    	je     ec <__libc_malloc_impl+0xec>
 1a5:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 1ac <__libc_malloc_impl+0x1ac>
			1a8: R_X86_64_PC32	__libc-0x1
 1ac:	4c 8d 2d 00 00 00 00 	lea    0x0(%rip),%r13        # 1b3 <__libc_malloc_impl+0x1b3>
			1af: R_X86_64_PC32	__malloc_lock-0x4
 1b3:	84 c0                	test   %al,%al
 1b5:	0f 85 09 01 00 00    	jne    2c4 <__libc_malloc_impl+0x2c4>
 1bb:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 1c2 <__libc_malloc_impl+0x1c2>
			1be: R_X86_64_PC32	__malloc_context+0x3b4
 1c2:	8d 50 01             	lea    0x1(%rax),%edx
 1c5:	3c ff                	cmp    $0xff,%al
 1c7:	0f 84 04 01 00 00    	je     2d1 <__libc_malloc_impl+0x2d1>
 1cd:	88 15 00 00 00 00    	mov    %dl,0x0(%rip)        # 1d3 <__libc_malloc_impl+0x1d3>
			1cf: R_X86_64_PC32	__malloc_context+0x3b4
 1d3:	e8 00 00 00 00       	call   1d8 <__libc_malloc_impl+0x1d8>
			1d4: R_X86_64_PLT32	__malloc_alloc_meta-0x4
 1d8:	49 89 c7             	mov    %rax,%r15
 1db:	48 85 c0             	test   %rax,%rax
 1de:	0f 84 16 01 00 00    	je     2fa <__libc_malloc_impl+0x2fa>
 1e4:	49 c1 e6 0c          	shl    $0xc,%r14
 1e8:	48 89 58 10          	mov    %rbx,0x10(%rax)
 1ec:	49 81 ce e0 0f 00 00 	or     $0xfe0,%r14
 1f3:	48 89 03             	mov    %rax,(%rbx)
 1f6:	c7 40 1c 00 00 00 00 	movl   $0x0,0x1c(%rax)
 1fd:	4c 89 70 20          	mov    %r14,0x20(%rax)
 201:	c7 40 18 00 00 00 00 	movl   $0x0,0x18(%rax)
 208:	8b 05 00 00 00 00    	mov    0x0(%rip),%eax        # 20e <__libc_malloc_impl+0x20e>
			20a: R_X86_64_PC32	__malloc_context+0x8
 20e:	45 31 f6             	xor    %r14d,%r14d
 211:	45 31 e4             	xor    %r12d,%r12d
 214:	8d 58 01             	lea    0x1(%rax),%ebx
 217:	89 1d 00 00 00 00    	mov    %ebx,0x0(%rip)        # 21d <__libc_malloc_impl+0x21d>
			219: R_X86_64_PC32	__malloc_context+0x8
 21d:	8b 05 00 00 00 00    	mov    0x0(%rip),%eax        # 223 <__libc_malloc_impl+0x223>
			21f: R_X86_64_PC32	__malloc_lock-0x4
 223:	85 c0                	test   %eax,%eax
 225:	0f 88 47 01 00 00    	js     372 <__libc_malloc_impl+0x372>
 22b:	41 f6 47 20 1f       	testb  $0x1f,0x20(%r15)
 230:	0f 85 49 01 00 00    	jne    37f <__libc_malloc_impl+0x37f>
 236:	49 81 7f 20 ff 0f 00 	cmpq   $0xfff,0x20(%r15)
 23d:	00 
 23e:	0f 86 3b 01 00 00    	jbe    37f <__libc_malloc_impl+0x37f>
 244:	49 8b 57 20          	mov    0x20(%r15),%rdx
 248:	48 81 e2 00 f0 ff ff 	and    $0xfffffffffffff000,%rdx
 24f:	48 83 ea 10          	sub    $0x10,%rdx
 253:	e9 44 01 00 00       	jmp    39c <__libc_malloc_impl+0x39c>
 258:	4c 89 ef             	mov    %r13,%rdi
 25b:	e8 00 00 00 00       	call   260 <__libc_malloc_impl+0x260>
			25c: R_X86_64_PLT32	__lock-0x4
 260:	e9 de fe ff ff       	jmp    143 <__libc_malloc_impl+0x143>
 265:	48 c7 04 da 00 00 00 	movq   $0x0,(%rdx,%rbx,8)
 26c:	00 
 26d:	41 c7 47 1c 00 00 00 	movl   $0x0,0x1c(%r15)
 274:	00 
 275:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 27c <__libc_malloc_impl+0x27c>
			278: R_X86_64_PC32	__malloc_context+0x3b4
 27c:	8d 50 01             	lea    0x1(%rax),%edx
 27f:	3c ff                	cmp    $0xff,%al
 281:	74 0b                	je     28e <__libc_malloc_impl+0x28e>
 283:	88 15 00 00 00 00    	mov    %dl,0x0(%rip)        # 289 <__libc_malloc_impl+0x289>
			285: R_X86_64_PC32	__malloc_context+0x3b4
 289:	e9 7a ff ff ff       	jmp    208 <__libc_malloc_impl+0x208>
 28e:	48 8d 05 00 00 00 00 	lea    0x0(%rip),%rax        # 295 <__libc_malloc_impl+0x295>
			291: R_X86_64_PC32	__malloc_context+0x374
 295:	48 8d 50 20          	lea    0x20(%rax),%rdx
 299:	eb 10                	jmp    2ab <__libc_malloc_impl+0x2ab>
 29b:	0f 1f 44 00 00       	nopl   0x0(%rax,%rax,1)
 2a0:	c6 00 00             	movb   $0x0,(%rax)
 2a3:	48 83 c0 02          	add    $0x2,%rax
 2a7:	c6 40 ff 00          	movb   $0x0,-0x1(%rax)
 2ab:	48 39 d0             	cmp    %rdx,%rax
 2ae:	75 f0                	jne    2a0 <__libc_malloc_impl+0x2a0>
 2b0:	ba 01 00 00 00       	mov    $0x1,%edx
 2b5:	eb cc                	jmp    283 <__libc_malloc_impl+0x283>
 2b7:	4c 89 ef             	mov    %r13,%rdi
 2ba:	e8 00 00 00 00       	call   2bf <__libc_malloc_impl+0x2bf>
			2bb: R_X86_64_PLT32	__unlock-0x4
 2bf:	e9 b7 fe ff ff       	jmp    17b <__libc_malloc_impl+0x17b>
 2c4:	4c 89 ef             	mov    %r13,%rdi
 2c7:	e8 00 00 00 00       	call   2cc <__libc_malloc_impl+0x2cc>
			2c8: R_X86_64_PLT32	__lock-0x4
 2cc:	e9 ea fe ff ff       	jmp    1bb <__libc_malloc_impl+0x1bb>
 2d1:	48 8d 05 00 00 00 00 	lea    0x0(%rip),%rax        # 2d8 <__libc_malloc_impl+0x2d8>
			2d4: R_X86_64_PC32	__malloc_context+0x374
 2d8:	48 8d 50 20          	lea    0x20(%rax),%rdx
 2dc:	eb 0d                	jmp    2eb <__libc_malloc_impl+0x2eb>
 2de:	66 90                	xchg   %ax,%ax
 2e0:	c6 00 00             	movb   $0x0,(%rax)
 2e3:	48 83 c0 02          	add    $0x2,%rax
 2e7:	c6 40 ff 00          	movb   $0x0,-0x1(%rax)
 2eb:	48 39 d0             	cmp    %rdx,%rax
 2ee:	75 f0                	jne    2e0 <__libc_malloc_impl+0x2e0>
 2f0:	ba 01 00 00 00       	mov    $0x1,%edx
 2f5:	e9 d3 fe ff ff       	jmp    1cd <__libc_malloc_impl+0x1cd>
 2fa:	8b 05 00 00 00 00    	mov    0x0(%rip),%eax        # 300 <__libc_malloc_impl+0x300>
			2fc: R_X86_64_PC32	__malloc_lock-0x4
 300:	85 c0                	test   %eax,%eax
 302:	78 10                	js     314 <__libc_malloc_impl+0x314>
 304:	4c 89 e6             	mov    %r12,%rsi
 307:	48 89 df             	mov    %rbx,%rdi
 30a:	e8 00 00 00 00       	call   30f <__libc_malloc_impl+0x30f>
			30b: R_X86_64_PLT32	munmap-0x4
 30f:	e9 d8 fd ff ff       	jmp    ec <__libc_malloc_impl+0xec>
 314:	4c 89 ef             	mov    %r13,%rdi
 317:	e8 00 00 00 00       	call   31c <__libc_malloc_impl+0x31c>
			318: R_X86_64_PLT32	__unlock-0x4
 31c:	eb e6                	jmp    304 <__libc_malloc_impl+0x304>
 31e:	4c 89 ef             	mov    %r13,%rdi
 321:	e8 00 00 00 00       	call   326 <__libc_malloc_impl+0x326>
			322: R_X86_64_PLT32	__lock-0x4
 326:	e9 71 fd ff ff       	jmp    9c <__libc_malloc_impl+0x9c>
 32b:	48 89 ee             	mov    %rbp,%rsi
 32e:	89 df                	mov    %ebx,%edi
 330:	e8 00 00 00 00       	call   335 <__libc_malloc_impl+0x335>
			331: R_X86_64_PC32	.text.alloc_slot-0x4
 335:	48 8d 15 00 00 00 00 	lea    0x0(%rip),%rdx        # 33c <__libc_malloc_impl+0x33c>
			338: R_X86_64_PC32	__malloc_context-0x4
 33c:	83 f8 ff             	cmp    $0xffffffff,%eax
 33f:	41 89 c4             	mov    %eax,%r12d
 342:	74 13                	je     357 <__libc_malloc_impl+0x357>
 344:	4e 8b 7c f2 50       	mov    0x50(%rdx,%r14,8),%r15
 349:	8b 1d 00 00 00 00    	mov    0x0(%rip),%ebx        # 34f <__libc_malloc_impl+0x34f>
			34b: R_X86_64_PC32	__malloc_context+0x8
 34f:	4c 63 f0             	movslq %eax,%r14
 352:	e9 c6 fe ff ff       	jmp    21d <__libc_malloc_impl+0x21d>
 357:	8b 05 00 00 00 00    	mov    0x0(%rip),%eax        # 35d <__libc_malloc_impl+0x35d>
			359: R_X86_64_PC32	__malloc_lock-0x4
 35d:	85 c0                	test   %eax,%eax
 35f:	0f 89 87 fd ff ff    	jns    ec <__libc_malloc_impl+0xec>
 365:	4c 89 ef             	mov    %r13,%rdi
 368:	e8 00 00 00 00       	call   36d <__libc_malloc_impl+0x36d>
			369: R_X86_64_PLT32	__unlock-0x4
 36d:	e9 7a fd ff ff       	jmp    ec <__libc_malloc_impl+0xec>
 372:	4c 89 ef             	mov    %r13,%rdi
 375:	e8 00 00 00 00       	call   37a <__libc_malloc_impl+0x37a>
			376: R_X86_64_PLT32	__unlock-0x4
 37a:	e9 ac fe ff ff       	jmp    22b <__libc_malloc_impl+0x22b>
 37f:	41 0f b7 57 20       	movzwl 0x20(%r15),%edx
 384:	48 8d 05 00 00 00 00 	lea    0x0(%rip),%rax        # 38b <__libc_malloc_impl+0x38b>
			387: R_X86_64_PC32	__malloc_size_classes-0x4
 38b:	66 c1 ea 06          	shr    $0x6,%dx
 38f:	83 e2 3f             	and    $0x3f,%edx
 392:	0f b7 14 50          	movzwl (%rax,%rdx,2),%edx
 396:	c1 e2 04             	shl    $0x4,%edx
 399:	48 63 d2             	movslq %edx,%rdx
 39c:	4c 0f af f2          	imul   %rdx,%r14
 3a0:	48 89 d0             	mov    %rdx,%rax
 3a3:	49 8b 77 10          	mov    0x10(%r15),%rsi
 3a7:	48 29 e8             	sub    %rbp,%rax
 3aa:	48 8d 48 fc          	lea    -0x4(%rax),%rcx
 3ae:	48 83 c6 10          	add    $0x10,%rsi
 3b2:	4a 8d 04 36          	lea    (%rsi,%r14,1),%rax
 3b6:	49 89 c8             	mov    %rcx,%r8
 3b9:	49 c1 e8 04          	shr    $0x4,%r8
 3bd:	80 78 fd 00          	cmpb   $0x0,-0x3(%rax)
 3c1:	48 8d 7c 10 fc       	lea    -0x4(%rax,%rdx,1),%rdi
 3c6:	0f b6 d3             	movzbl %bl,%edx
 3c9:	74 0a                	je     3d5 <__libc_malloc_impl+0x3d5>
 3cb:	0f b7 50 fe          	movzwl -0x2(%rax),%edx
 3cf:	83 c2 01             	add    $0x1,%edx
 3d2:	0f b6 d2             	movzbl %dl,%edx
 3d5:	80 78 fc 00          	cmpb   $0x0,-0x4(%rax)
 3d9:	0f 85 00 00 00 00    	jne    3df <__libc_malloc_impl+0x3df>
			3db: R_X86_64_PC32	.text.unlikely.__libc_malloc_impl-0x4
 3df:	4c 63 ca             	movslq %edx,%r9
 3e2:	4d 39 c8             	cmp    %r9,%r8
 3e5:	73 37                	jae    41e <__libc_malloc_impl+0x41e>
 3e7:	48 c1 e9 05          	shr    $0x5,%rcx
 3eb:	4c 09 c1             	or     %r8,%rcx
 3ee:	49 89 c9             	mov    %rcx,%r9
 3f1:	49 c1 e9 02          	shr    $0x2,%r9
 3f5:	4c 09 c9             	or     %r9,%rcx
 3f8:	49 89 c9             	mov    %rcx,%r9
 3fb:	49 c1 e9 04          	shr    $0x4,%r9
 3ff:	4c 09 c9             	or     %r9,%rcx
 402:	21 ca                	and    %ecx,%edx
 404:	48 63 ca             	movslq %edx,%rcx
 407:	49 39 c8             	cmp    %rcx,%r8
 40a:	73 12                	jae    41e <__libc_malloc_impl+0x41e>
 40c:	44 29 c2             	sub    %r8d,%edx
 40f:	83 ea 01             	sub    $0x1,%edx
 412:	48 63 ca             	movslq %edx,%rcx
 415:	49 39 c8             	cmp    %rcx,%r8
 418:	0f 82 00 00 00 00    	jb     41e <__libc_malloc_impl+0x41e>
			41a: R_X86_64_PC32	.text.unlikely.__libc_malloc_impl-0x4
 41e:	85 d2                	test   %edx,%edx
 420:	74 1d                	je     43f <__libc_malloc_impl+0x43f>
 422:	66 89 50 fe          	mov    %dx,-0x2(%rax)
 426:	c1 e2 04             	shl    $0x4,%edx
 429:	48 63 d2             	movslq %edx,%rdx
 42c:	c6 40 fd e0          	movb   $0xe0,-0x3(%rax)
 430:	48 01 d0             	add    %rdx,%rax
 433:	c6 40 fc 00          	movb   $0x0,-0x4(%rax)
 437:	49 8b 77 10          	mov    0x10(%r15),%rsi
 43b:	48 83 c6 10          	add    $0x10,%rsi
 43f:	48 89 c2             	mov    %rax,%rdx
 442:	44 88 60 fd          	mov    %r12b,-0x3(%rax)
 446:	44 89 e1             	mov    %r12d,%ecx
 449:	48 29 f2             	sub    %rsi,%rdx
 44c:	48 c1 ea 04          	shr    $0x4,%rdx
 450:	66 89 50 fe          	mov    %dx,-0x2(%rax)
 454:	48 89 fa             	mov    %rdi,%rdx
 457:	48 29 c2             	sub    %rax,%rdx
 45a:	29 ea                	sub    %ebp,%edx
 45c:	74 1c                	je     47a <__libc_malloc_impl+0x47a>
 45e:	89 d1                	mov    %edx,%ecx
 460:	f7 d9                	neg    %ecx
 462:	48 63 c9             	movslq %ecx,%rcx
 465:	c6 04 0f 00          	movb   $0x0,(%rdi,%rcx,1)
 469:	83 fa 04             	cmp    $0x4,%edx
 46c:	7f 1e                	jg     48c <__libc_malloc_impl+0x48c>
 46e:	0f b6 48 fd          	movzbl -0x3(%rax),%ecx
 472:	c1 e2 05             	shl    $0x5,%edx
 475:	83 e1 1f             	and    $0x1f,%ecx
 478:	01 d1                	add    %edx,%ecx
 47a:	88 48 fd             	mov    %cl,-0x3(%rax)
 47d:	48 83 c4 08          	add    $0x8,%rsp
 481:	5b                   	pop    %rbx
 482:	5d                   	pop    %rbp
 483:	41 5c                	pop    %r12
 485:	41 5d                	pop    %r13
 487:	41 5e                	pop    %r14
 489:	41 5f                	pop    %r15
 48b:	c3                   	ret
 48c:	89 57 fc             	mov    %edx,-0x4(%rdi)
 48f:	c6 47 fb 00          	movb   $0x0,-0x5(%rdi)
 493:	0f b6 48 fd          	movzbl -0x3(%rax),%ecx
 497:	83 e1 1f             	and    $0x1f,%ecx
 49a:	83 e9 60             	sub    $0x60,%ecx
 49d:	eb db                	jmp    47a <__libc_malloc_impl+0x47a>

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
  12:	89 d6                	mov    %edx,%esi
  14:	41 89 d0             	mov    %edx,%r8d
  17:	83 e6 1f             	and    $0x1f,%esi
  1a:	41 83 e0 1f          	and    $0x1f,%r8d
  1e:	80 7f fc 00          	cmpb   $0x0,-0x4(%rdi)
  22:	74 18                	je     3c <__malloc_allzerop+0x3c>
  24:	85 c9                	test   %ecx,%ecx
  26:	0f 85 00 00 00 00    	jne    2c <__malloc_allzerop+0x2c>
			28: R_X86_64_PC32	.text.unlikely.__malloc_allzerop-0x4
  2c:	48 63 4f f8          	movslq -0x8(%rdi),%rcx
  30:	81 f9 ff ff 00 00    	cmp    $0xffff,%ecx
  36:	0f 8e 00 00 00 00    	jle    3c <__malloc_allzerop+0x3c>
			38: R_X86_64_PC32	.text.unlikely.__malloc_allzerop-0x4
  3c:	89 c8                	mov    %ecx,%eax
  3e:	c1 e0 04             	shl    $0x4,%eax
  41:	48 98                	cltq
  43:	48 29 c7             	sub    %rax,%rdi
  46:	48 8b 47 f0          	mov    -0x10(%rdi),%rax
  4a:	48 83 ef 10          	sub    $0x10,%rdi
  4e:	48 3b 78 10          	cmp    0x10(%rax),%rdi
  52:	0f 85 00 00 00 00    	jne    58 <__malloc_allzerop+0x58>
			54: R_X86_64_PC32	.text.unlikely.__malloc_allzerop-0x4
  58:	0f b6 78 20          	movzbl 0x20(%rax),%edi
  5c:	89 fa                	mov    %edi,%edx
  5e:	83 e2 1f             	and    $0x1f,%edx
  61:	41 39 d0             	cmp    %edx,%r8d
  64:	0f 8f 00 00 00 00    	jg     6a <__malloc_allzerop+0x6a>
			66: R_X86_64_PC32	.text.unlikely.__malloc_allzerop-0x4
  6a:	8b 50 18             	mov    0x18(%rax),%edx
  6d:	0f a3 f2             	bt     %esi,%edx
  70:	0f 82 00 00 00 00    	jb     76 <__malloc_allzerop+0x76>
			72: R_X86_64_PC32	.text.unlikely.__malloc_allzerop-0x4
  76:	8b 50 1c             	mov    0x1c(%rax),%edx
  79:	0f a3 f2             	bt     %esi,%edx
  7c:	0f 82 00 00 00 00    	jb     82 <__malloc_allzerop+0x82>
			7e: R_X86_64_PC32	.text.unlikely.__malloc_allzerop-0x4
  82:	48 89 c2             	mov    %rax,%rdx
  85:	48 8b 35 00 00 00 00 	mov    0x0(%rip),%rsi        # 8c <__malloc_allzerop+0x8c>
			88: R_X86_64_PC32	__malloc_context-0x4
  8c:	48 81 e2 00 f0 ff ff 	and    $0xfffffffffffff000,%rdx
  93:	48 39 32             	cmp    %rsi,(%rdx)
  96:	0f 85 00 00 00 00    	jne    9c <__malloc_allzerop+0x9c>
			98: R_X86_64_PC32	.text.unlikely.__malloc_allzerop-0x4
  9c:	0f b7 70 20          	movzwl 0x20(%rax),%esi
  a0:	89 f2                	mov    %esi,%edx
  a2:	66 c1 ea 06          	shr    $0x6,%dx
  a6:	83 e2 3f             	and    $0x3f,%edx
  a9:	80 fa 2f             	cmp    $0x2f,%dl
  ac:	77 34                	ja     e2 <__malloc_allzerop+0xe2>
  ae:	83 e2 3f             	and    $0x3f,%edx
  b1:	48 8d 35 00 00 00 00 	lea    0x0(%rip),%rsi        # b8 <__malloc_allzerop+0xb8>
			b4: R_X86_64_PC32	__malloc_size_classes-0x4
  b8:	0f b7 34 56          	movzwl (%rsi,%rdx,2),%esi
  bc:	44 89 c2             	mov    %r8d,%edx
  bf:	0f af d6             	imul   %esi,%edx
  c2:	39 d1                	cmp    %edx,%ecx
  c4:	0f 8c 00 00 00 00    	jl     ca <__malloc_allzerop+0xca>
			c6: R_X86_64_PC32	.text.unlikely.__malloc_allzerop-0x4
  ca:	01 f2                	add    %esi,%edx
  cc:	39 d1                	cmp    %edx,%ecx
  ce:	7d 0d                	jge    dd <__malloc_allzerop+0xdd>
  d0:	48 81 78 20 ff 0f 00 	cmpq   $0xfff,0x20(%rax)
  d7:	00 
  d8:	77 3d                	ja     117 <__malloc_allzerop+0x117>
  da:	31 c0                	xor    %eax,%eax
  dc:	c3                   	ret
  dd:	e9 00 00 00 00       	jmp    e2 <__malloc_allzerop+0xe2>
			de: R_X86_64_PC32	.text.unlikely.__malloc_allzerop-0x4
  e2:	f7 d6                	not    %esi
  e4:	66 f7 c6 c0 0f       	test   $0xfc0,%si
  e9:	75 27                	jne    112 <__malloc_allzerop+0x112>
  eb:	48 81 78 20 ff 0f 00 	cmpq   $0xfff,0x20(%rax)
  f2:	00 
  f3:	76 e5                	jbe    da <__malloc_allzerop+0xda>
  f5:	48 8b 50 20          	mov    0x20(%rax),%rdx
  f9:	48 81 e2 00 f0 ff ff 	and    $0xfffffffffffff000,%rdx
 100:	48 c1 ea 04          	shr    $0x4,%rdx
 104:	48 83 ea 01          	sub    $0x1,%rdx
 108:	48 39 ca             	cmp    %rcx,%rdx
 10b:	73 cd                	jae    da <__malloc_allzerop+0xda>
 10d:	e9 00 00 00 00       	jmp    112 <__malloc_allzerop+0x112>
			10e: R_X86_64_PC32	.text.unlikely.__malloc_allzerop-0x4
 112:	e9 00 00 00 00       	jmp    117 <__malloc_allzerop+0x117>
			113: R_X86_64_PC32	.text.unlikely.__malloc_allzerop-0x4
 117:	48 8b 50 20          	mov    0x20(%rax),%rdx
 11b:	48 63 c1             	movslq %ecx,%rax
 11e:	48 81 e2 00 f0 ff ff 	and    $0xfffffffffffff000,%rdx
 125:	48 89 d1             	mov    %rdx,%rcx
 128:	48 c1 e9 04          	shr    $0x4,%rcx
 12c:	48 83 e9 01          	sub    $0x1,%rcx
 130:	48 39 c1             	cmp    %rax,%rcx
 133:	72 1a                	jb     14f <__malloc_allzerop+0x14f>
 135:	c1 e6 04             	shl    $0x4,%esi
 138:	31 c0                	xor    %eax,%eax
 13a:	83 e7 1f             	and    $0x1f,%edi
 13d:	48 63 f6             	movslq %esi,%rsi
 140:	75 12                	jne    154 <__malloc_allzerop+0x154>
 142:	48 83 ea 10          	sub    $0x10,%rdx
 146:	31 c0                	xor    %eax,%eax
 148:	48 39 f2             	cmp    %rsi,%rdx
 14b:	0f 92 c0             	setb   %al
 14e:	c3                   	ret
 14f:	e9 00 00 00 00       	jmp    154 <__malloc_allzerop+0x154>
			150: R_X86_64_PC32	.text.unlikely.__malloc_allzerop-0x4
 154:	c3                   	ret

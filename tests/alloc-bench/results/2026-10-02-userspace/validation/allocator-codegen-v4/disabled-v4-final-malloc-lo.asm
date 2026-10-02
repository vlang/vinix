
/Users/alex/code/vinix/third_party/useralloc-libc/build/musl/x86_64/5bc37f7d5dd563a40ea61404bac87cfda4c114030933317e53acedd4328fa099/objects/obj/src/malloc/mallocng/malloc.lo:     file format elf64-x86-64


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
  1e:	48 83 ec 28          	sub    $0x28,%rsp
  22:	49 8b 14 c7          	mov    (%r15,%rax,8),%rdx
  26:	48 85 d2             	test   %rdx,%rdx
  29:	74 4f                	je     7a <alloc_slot+0x7a>
  2b:	8b 4a 18             	mov    0x18(%rdx),%ecx
  2e:	85 c9                	test   %ecx,%ecx
  30:	0f 85 c5 01 00 00    	jne    1fb <alloc_slot+0x1fb>
  36:	8b 72 1c             	mov    0x1c(%rdx),%esi
  39:	48 8b 4a 08          	mov    0x8(%rdx),%rcx
  3d:	85 f6                	test   %esi,%esi
  3f:	0f 85 e7 00 00 00    	jne    12c <alloc_slot+0x12c>
  45:	48 39 ca             	cmp    %rcx,%rdx
  48:	0f 84 d1 00 00 00    	je     11f <alloc_slot+0x11f>
  4e:	48 8b 32             	mov    (%rdx),%rsi
  51:	48 89 4e 08          	mov    %rcx,0x8(%rsi)
  55:	48 8b 32             	mov    (%rdx),%rsi
  58:	48 89 31             	mov    %rsi,(%rcx)
  5b:	49 3b 14 c7          	cmp    (%r15,%rax,8),%rdx
  5f:	0f 84 ad 00 00 00    	je     112 <alloc_slot+0x112>
  65:	66 0f ef c0          	pxor   %xmm0,%xmm0
  69:	0f 11 02             	movups %xmm0,(%rdx)
  6c:	4b 8b 54 f7 50       	mov    0x50(%r15,%r14,8),%rdx
  71:	48 85 d2             	test   %rdx,%rdx
  74:	0f 85 b9 00 00 00    	jne    133 <alloc_slot+0x133>
  7a:	4c 8d 0d 00 00 00 00 	lea    0x0(%rip),%r9        # 81 <alloc_slot+0x81>
			7d: R_X86_64_PC32	__malloc_size_classes-0x4
  81:	48 89 7c 24 10       	mov    %rdi,0x10(%rsp)
  86:	47 0f b7 2c 71       	movzwl (%r9,%r14,2),%r13d
  8b:	e8 00 00 00 00       	call   90 <alloc_slot+0x90>
			8c: R_X86_64_PLT32	__malloc_alloc_meta-0x4
  90:	66 48 0f 6e c8       	movq   %rax,%xmm1
  95:	41 c1 e5 04          	shl    $0x4,%r13d
  99:	48 89 c5             	mov    %rax,%rbp
  9c:	66 0f 6c c9          	punpcklqdq %xmm1,%xmm1
  a0:	4d 63 ed             	movslq %r13d,%r13
  a3:	0f 29 0c 24          	movaps %xmm1,(%rsp)
  a7:	48 85 c0             	test   %rax,%rax
  aa:	0f 84 05 07 00 00    	je     7b5 <alloc_slot+0x7b5>
  b0:	41 83 fc 08          	cmp    $0x8,%r12d
  b4:	4b 8b 8c f7 f8 01 00 	mov    0x1f8(%r15,%r14,8),%rcx
  bb:	00 
  bc:	48 8b 7c 24 10       	mov    0x10(%rsp),%rdi
  c1:	4c 8d 0d 00 00 00 00 	lea    0x0(%rip),%r9        # c8 <alloc_slot+0xc8>
			c4: R_X86_64_PC32	__malloc_size_classes-0x4
  c8:	0f 8f 08 02 00 00    	jg     2d6 <alloc_slot+0x2d6>
  ce:	4b 8d 14 76          	lea    (%r14,%r14,2),%rdx
  d2:	48 8d 05 00 00 00 00 	lea    0x0(%rip),%rax        # d9 <alloc_slot+0xd9>
			d5: R_X86_64_PC32	.rodata.small_cnt_tab-0x4
  d9:	48 01 d0             	add    %rdx,%rax
  dc:	0f b6 18             	movzbl (%rax),%ebx
  df:	8d 14 9d 00 00 00 00 	lea    0x0(,%rbx,4),%edx
  e6:	48 63 d2             	movslq %edx,%rdx
  e9:	48 39 d1             	cmp    %rdx,%rcx
  ec:	0f 83 3f 02 00 00    	jae    331 <alloc_slot+0x331>
  f2:	0f b6 58 01          	movzbl 0x1(%rax),%ebx
  f6:	8d 14 9d 00 00 00 00 	lea    0x0(,%rbx,4),%edx
  fd:	48 63 d2             	movslq %edx,%rdx
 100:	48 39 d1             	cmp    %rdx,%rcx
 103:	0f 83 28 02 00 00    	jae    331 <alloc_slot+0x331>
 109:	0f b6 58 02          	movzbl 0x2(%rax),%ebx
 10d:	e9 1f 02 00 00       	jmp    331 <alloc_slot+0x331>
 112:	48 8b 4a 08          	mov    0x8(%rdx),%rcx
 116:	49 89 0c c7          	mov    %rcx,(%r15,%rax,8)
 11a:	e9 46 ff ff ff       	jmp    65 <alloc_slot+0x65>
 11f:	49 c7 04 c7 00 00 00 	movq   $0x0,(%r15,%rax,8)
 126:	00 
 127:	e9 39 ff ff ff       	jmp    65 <alloc_slot+0x65>
 12c:	49 89 0c c7          	mov    %rcx,(%r15,%rax,8)
 130:	48 89 ca             	mov    %rcx,%rdx
 133:	0f b6 4a 20          	movzbl 0x20(%rdx),%ecx
 137:	b8 02 00 00 00       	mov    $0x2,%eax
 13c:	44 8b 42 1c          	mov    0x1c(%rdx),%r8d
 140:	d3 e0                	shl    %cl,%eax
 142:	83 e8 01             	sub    $0x1,%eax
 145:	41 39 c0             	cmp    %eax,%r8d
 148:	0f 84 d3 00 00 00    	je     221 <alloc_slot+0x221>
 14e:	48 8b 72 10          	mov    0x10(%rdx),%rsi
 152:	b8 02 00 00 00       	mov    $0x2,%eax
 157:	0f b6 4e 08          	movzbl 0x8(%rsi),%ecx
 15b:	d3 e0                	shl    %cl,%eax
 15d:	41 89 ca             	mov    %ecx,%r10d
 160:	83 e8 01             	sub    $0x1,%eax
 163:	41 83 e2 1f          	and    $0x1f,%r10d
 167:	44 85 c0             	test   %r8d,%eax
 16a:	75 15                	jne    181 <alloc_slot+0x181>
 16c:	4c 8b 4a 08          	mov    0x8(%rdx),%r9
 170:	4c 39 ca             	cmp    %r9,%rdx
 173:	0f 84 c3 00 00 00    	je     23c <alloc_slot+0x23c>
 179:	4f 89 4c f7 50       	mov    %r9,0x50(%r15,%r14,8)
 17e:	4c 89 ca             	mov    %r9,%rdx
 181:	8b 42 18             	mov    0x18(%rdx),%eax
 184:	85 c0                	test   %eax,%eax
 186:	0f 85 00 00 00 00    	jne    18c <alloc_slot+0x18c>
			188: R_X86_64_PC32	.text.unlikely.alloc_slot-0x4
 18c:	48 8b 42 10          	mov    0x10(%rdx),%rax
 190:	41 b9 02 00 00 00    	mov    $0x2,%r9d
 196:	4c 8d 52 1c          	lea    0x1c(%rdx),%r10
 19a:	0f b6 48 08          	movzbl 0x8(%rax),%ecx
 19e:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 1a5 <alloc_slot+0x1a5>
			1a1: R_X86_64_PC32	__libc-0x1
 1a5:	41 d3 e1             	shl    %cl,%r9d
 1a8:	45 8d 41 ff          	lea    -0x1(%r9),%r8d
 1ac:	41 f7 d9             	neg    %r9d
 1af:	84 c0                	test   %al,%al
 1b1:	0f 85 07 01 00 00    	jne    2be <alloc_slot+0x2be>
 1b7:	8b 4a 1c             	mov    0x1c(%rdx),%ecx
 1ba:	41 21 c9             	and    %ecx,%r9d
 1bd:	44 89 4a 1c          	mov    %r9d,0x1c(%rdx)
 1c1:	44 21 c1             	and    %r8d,%ecx
 1c4:	89 4a 18             	mov    %ecx,0x18(%rdx)
 1c7:	0f 84 00 00 00 00    	je     1cd <alloc_slot+0x1cd>
			1c9: R_X86_64_PC32	.text.unlikely.alloc_slot-0x4
 1cd:	0f b7 42 20          	movzwl 0x20(%rdx),%eax
 1d1:	66 c1 e8 06          	shr    $0x6,%ax
 1d5:	83 e0 3f             	and    $0x3f,%eax
 1d8:	83 e8 07             	sub    $0x7,%eax
 1db:	83 f8 1f             	cmp    $0x1f,%eax
 1de:	77 1b                	ja     1fb <alloc_slot+0x1fb>
 1e0:	48 98                	cltq
 1e2:	41 0f b6 b4 07 98 03 	movzbl 0x398(%r15,%rax,1),%esi
 1e9:	00 00 
 1eb:	40 84 f6             	test   %sil,%sil
 1ee:	74 0b                	je     1fb <alloc_slot+0x1fb>
 1f0:	83 ee 01             	sub    $0x1,%esi
 1f3:	41 88 b4 07 98 03 00 	mov    %sil,0x398(%r15,%rax,1)
 1fa:	00 
 1fb:	89 c8                	mov    %ecx,%eax
 1fd:	f7 d8                	neg    %eax
 1ff:	21 c8                	and    %ecx,%eax
 201:	29 c1                	sub    %eax,%ecx
 203:	89 4a 18             	mov    %ecx,0x18(%rdx)
 206:	85 c0                	test   %eax,%eax
 208:	0f 84 6c fe ff ff    	je     7a <alloc_slot+0x7a>
 20e:	f3 0f bc c0          	tzcnt  %eax,%eax
 212:	48 83 c4 28          	add    $0x28,%rsp
 216:	5b                   	pop    %rbx
 217:	5d                   	pop    %rbp
 218:	41 5c                	pop    %r12
 21a:	41 5d                	pop    %r13
 21c:	41 5e                	pop    %r14
 21e:	41 5f                	pop    %r15
 220:	c3                   	ret
 221:	83 e1 20             	and    $0x20,%ecx
 224:	0f 84 57 ff ff ff    	je     181 <alloc_slot+0x181>
 22a:	48 8b 52 08          	mov    0x8(%rdx),%rdx
 22e:	4b 89 54 f7 50       	mov    %rdx,0x50(%r15,%r14,8)
 233:	44 8b 42 1c          	mov    0x1c(%rdx),%r8d
 237:	e9 12 ff ff ff       	jmp    14e <alloc_slot+0x14e>
 23c:	41 0f b7 41 20       	movzwl 0x20(%r9),%eax
 241:	48 8d 15 00 00 00 00 	lea    0x0(%rip),%rdx        # 248 <alloc_slot+0x248>
			244: R_X86_64_PC32	__malloc_size_classes-0x4
 248:	41 8d 4a 02          	lea    0x2(%r10),%ecx
 24c:	66 c1 e8 06          	shr    $0x6,%ax
 250:	83 e0 3f             	and    $0x3f,%eax
 253:	44 0f b7 14 42       	movzwl (%rdx,%rax,2),%r10d
 258:	89 ca                	mov    %ecx,%edx
 25a:	41 c1 e2 04          	shl    $0x4,%r10d
 25e:	41 0f af d2          	imul   %r10d,%edx
 262:	83 c2 10             	add    $0x10,%edx
 265:	eb 1f                	jmp    286 <alloc_slot+0x286>
 267:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
 26e:	00 00 00 00 
 272:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
 279:	00 00 00 00 
 27d:	0f 1f 00             	nopl   (%rax)
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
 2b9:	e9 c0 fe ff ff       	jmp    17e <alloc_slot+0x17e>
 2be:	8b 4a 1c             	mov    0x1c(%rdx),%ecx
 2c1:	89 ce                	mov    %ecx,%esi
 2c3:	89 c8                	mov    %ecx,%eax
 2c5:	44 21 ce             	and    %r9d,%esi
 2c8:	f0 41 0f b1 32       	lock cmpxchg %esi,(%r10)
 2cd:	39 c1                	cmp    %eax,%ecx
 2cf:	75 ed                	jne    2be <alloc_slot+0x2be>
 2d1:	e9 eb fe ff ff       	jmp    1c1 <alloc_slot+0x1c1>
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
 310:	48 39 c1             	cmp    %rax,%rcx
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
 337:	74 5b                	je     394 <alloc_slot+0x394>
 339:	4d 89 e8             	mov    %r13,%r8
 33c:	4c 0f af c2          	imul   %rdx,%r8
 340:	49 8d 40 10          	lea    0x10(%r8),%rax
 344:	48 3d 00 08 00 00    	cmp    $0x800,%rax
 34a:	0f 86 8b 03 00 00    	jbe    6db <alloc_slot+0x6db>
 350:	44 8d 0c 9d 00 00 00 	lea    0x0(,%rbx,4),%r9d
 357:	00 
 358:	4d 63 c9             	movslq %r9d,%r9
 35b:	41 8d 44 24 f9       	lea    -0x7(%r12),%eax
 360:	0f b6 15 00 00 00 00 	movzbl 0x0(%rip),%edx        # 367 <alloc_slot+0x367>
			363: R_X86_64_PC32	__malloc_context+0x3b4
 367:	83 f8 1f             	cmp    $0x1f,%eax
 36a:	77 74                	ja     3e0 <alloc_slot+0x3e0>
 36c:	48 98                	cltq
 36e:	41 0f b6 b4 07 78 03 	movzbl 0x378(%r15,%rax,1),%esi
 375:	00 00 
 377:	45 0f b6 94 07 98 03 	movzbl 0x398(%r15,%rax,1),%r10d
 37e:	00 00 
 380:	85 f6                	test   %esi,%esi
 382:	75 33                	jne    3b7 <alloc_slot+0x3b7>
 384:	31 f6                	xor    %esi,%esi
 386:	41 80 fa 63          	cmp    $0x63,%r10b
 38a:	40 0f 97 c6          	seta   %sil
 38e:	41 0f 96 c2          	setbe  %r10b
 392:	eb 54                	jmp    3e8 <alloc_slot+0x3e8>
 394:	49 8d 45 10          	lea    0x10(%r13),%rax
 398:	48 3d 00 08 00 00    	cmp    $0x800,%rax
 39e:	77 0c                	ja     3ac <alloc_slot+0x3ac>
 3a0:	ba 02 00 00 00       	mov    $0x2,%edx
 3a5:	bb 02 00 00 00       	mov    $0x2,%ebx
 3aa:	eb 8d                	jmp    339 <alloc_slot+0x339>
 3ac:	4d 89 e8             	mov    %r13,%r8
 3af:	41 b9 04 00 00 00    	mov    $0x4,%r9d
 3b5:	eb a4                	jmp    35b <alloc_slot+0x35b>
 3b7:	44 0f b6 da          	movzbl %dl,%r11d
 3bb:	41 29 f3             	sub    %esi,%r11d
 3be:	41 83 fb 09          	cmp    $0x9,%r11d
 3c2:	7f c0                	jg     384 <alloc_slot+0x384>
 3c4:	41 8d 72 01          	lea    0x1(%r10),%esi
 3c8:	41 80 fa 63          	cmp    $0x63,%r10b
 3cc:	41 bb 96 ff ff ff    	mov    $0xffffff96,%r11d
 3d2:	41 0f 43 f3          	cmovae %r11d,%esi
 3d6:	41 88 b4 07 98 03 00 	mov    %sil,0x398(%r15,%rax,1)
 3dd:	00 
 3de:	eb a4                	jmp    384 <alloc_slot+0x384>
 3e0:	41 ba 01 00 00 00    	mov    $0x1,%r10d
 3e6:	31 f6                	xor    %esi,%esi
 3e8:	8d 42 01             	lea    0x1(%rdx),%eax
 3eb:	80 fa ff             	cmp    $0xff,%dl
 3ee:	0f 84 c3 01 00 00    	je     5b7 <alloc_slot+0x5b7>
 3f4:	88 05 00 00 00 00    	mov    %al,0x0(%rip)        # 3fa <alloc_slot+0x3fa>
			3f6: R_X86_64_PC32	__malloc_context+0x3b4
 3fa:	41 f6 c4 01          	test   $0x1,%r12b
 3fe:	0f 85 1d 02 00 00    	jne    621 <alloc_slot+0x621>
 404:	41 83 fc 1f          	cmp    $0x1f,%r12d
 408:	0f 8f dc 01 00 00    	jg     5ea <alloc_slot+0x5ea>
 40e:	41 8d 44 24 01       	lea    0x1(%r12),%eax
 413:	48 98                	cltq
 415:	49 03 8c c7 f8 01 00 	add    0x1f8(%r15,%rax,8),%rcx
 41c:	00 
 41d:	4c 39 c9             	cmp    %r9,%rcx
 420:	73 09                	jae    42b <alloc_slot+0x42b>
 422:	45 84 d2             	test   %r10b,%r10b
 425:	0f 85 cd 01 00 00    	jne    5f8 <alloc_slot+0x5f8>
 42b:	83 fb 07             	cmp    $0x7,%ebx
 42e:	48 63 d3             	movslq %ebx,%rdx
 431:	41 0f 9e c0          	setle  %r8b
 435:	49 0f af d5          	imul   %r13,%rdx
 439:	48 c7 c0 f0 ff ff ff 	mov    $0xfffffffffffffff0,%rax
 440:	48 29 d0             	sub    %rdx,%rax
 443:	25 ff 0f 00 00       	and    $0xfff,%eax
 448:	4c 8d 54 02 10       	lea    0x10(%rdx,%rax,1),%r10
 44d:	85 f6                	test   %esi,%esi
 44f:	75 3d                	jne    48e <alloc_slot+0x48e>
 451:	45 84 c0             	test   %r8b,%r8b
 454:	74 38                	je     48e <alloc_slot+0x48e>
 456:	48 c7 c0 ec ff ff ff 	mov    $0xffffffffffffffec,%rax
 45d:	49 8d 55 10          	lea    0x10(%r13),%rdx
 461:	48 29 f8             	sub    %rdi,%rax
 464:	25 ff 0f 00 00       	and    $0xfff,%eax
 469:	48 8d 44 07 14       	lea    0x14(%rdi,%rax,1),%rax
 46e:	48 39 d0             	cmp    %rdx,%rax
 471:	72 13                	jb     486 <alloc_slot+0x486>
 473:	48 3d ff 3f 00 00    	cmp    $0x3fff,%rax
 479:	76 13                	jbe    48e <alloc_slot+0x48e>
 47b:	8d 14 1b             	lea    (%rbx,%rbx,1),%edx
 47e:	48 63 d2             	movslq %edx,%rdx
 481:	48 39 d1             	cmp    %rdx,%rcx
 484:	73 08                	jae    48e <alloc_slot+0x48e>
 486:	49 89 c2             	mov    %rax,%r10
 489:	bb 01 00 00 00       	mov    $0x1,%ebx
 48e:	4c 89 d6             	mov    %r10,%rsi
 491:	45 31 c9             	xor    %r9d,%r9d
 494:	31 ff                	xor    %edi,%edi
 496:	41 b8 ff ff ff ff    	mov    $0xffffffff,%r8d
 49c:	b9 22 00 00 00       	mov    $0x22,%ecx
 4a1:	ba 03 00 00 00       	mov    $0x3,%edx
 4a6:	4c 89 54 24 10       	mov    %r10,0x10(%rsp)
 4ab:	e8 00 00 00 00       	call   4b0 <alloc_slot+0x4b0>
			4ac: R_X86_64_PLT32	__mmap-0x4
 4b0:	4c 8b 54 24 10       	mov    0x10(%rsp),%r10
 4b5:	48 83 f8 ff          	cmp    $0xffffffffffffffff,%rax
 4b9:	48 89 c6             	mov    %rax,%rsi
 4bc:	0f 84 e0 01 00 00    	je     6a2 <alloc_slot+0x6a2>
 4c2:	48 8b 45 20          	mov    0x20(%rbp),%rax
 4c6:	49 81 e2 00 f0 ff ff 	and    $0xfffffffffffff000,%r10
 4cd:	31 d2                	xor    %edx,%edx
 4cf:	44 8d 43 ff          	lea    -0x1(%rbx),%r8d
 4d3:	25 ff 0f 00 00       	and    $0xfff,%eax
 4d8:	49 09 c2             	or     %rax,%r10
 4db:	b8 f0 0f 00 00       	mov    $0xff0,%eax
 4e0:	49 f7 f5             	div    %r13
 4e3:	4c 89 55 20          	mov    %r10,0x20(%rbp)
 4e7:	83 05 00 00 00 00 01 	addl   $0x1,0x0(%rip)        # 4ee <alloc_slot+0x4ee>
			4e9: R_X86_64_PC32	__malloc_context+0x7
 4ee:	83 e8 01             	sub    $0x1,%eax
 4f1:	39 d8                	cmp    %ebx,%eax
 4f3:	41 0f 4d c0          	cmovge %r8d,%eax
 4f7:	31 d2                	xor    %edx,%edx
 4f9:	89 d7                	mov    %edx,%edi
 4fb:	48 63 d3             	movslq %ebx,%rdx
 4fe:	85 c0                	test   %eax,%eax
 500:	0f 49 f8             	cmovns %eax,%edi
 503:	b8 02 00 00 00       	mov    $0x2,%eax
 508:	4b 01 94 f7 f8 01 00 	add    %rdx,0x1f8(%r15,%r14,8)
 50f:	00 
 510:	89 f9                	mov    %edi,%ecx
 512:	89 c2                	mov    %eax,%edx
 514:	48 89 75 10          	mov    %rsi,0x10(%rbp)
 518:	83 eb 01             	sub    $0x1,%ebx
 51b:	41 83 e4 3f          	and    $0x3f,%r12d
 51f:	d3 e2                	shl    %cl,%edx
 521:	44 89 c1             	mov    %r8d,%ecx
 524:	83 e3 1f             	and    $0x1f,%ebx
 527:	41 c1 e4 06          	shl    $0x6,%r12d
 52b:	83 ea 01             	sub    $0x1,%edx
 52e:	d3 e0                	shl    %cl,%eax
 530:	83 cb 20             	or     $0x20,%ebx
 533:	89 55 18             	mov    %edx,0x18(%rbp)
 536:	8b 55 18             	mov    0x18(%rbp),%edx
 539:	44 09 e3             	or     %r12d,%ebx
 53c:	29 d0                	sub    %edx,%eax
 53e:	83 e8 01             	sub    $0x1,%eax
 541:	89 45 1c             	mov    %eax,0x1c(%rbp)
 544:	89 f8                	mov    %edi,%eax
 546:	48 89 2e             	mov    %rbp,(%rsi)
 549:	48 8b 4d 10          	mov    0x10(%rbp),%rcx
 54d:	83 e0 1f             	and    $0x1f,%eax
 550:	0f b6 51 08          	movzbl 0x8(%rcx),%edx
 554:	83 e2 e0             	and    $0xffffffe0,%edx
 557:	09 d0                	or     %edx,%eax
 559:	88 41 08             	mov    %al,0x8(%rcx)
 55c:	0f b7 45 20          	movzwl 0x20(%rbp),%eax
 560:	66 25 00 f0          	and    $0xf000,%ax
 564:	09 c3                	or     %eax,%ebx
 566:	8b 45 18             	mov    0x18(%rbp),%eax
 569:	66 89 5d 20          	mov    %bx,0x20(%rbp)
 56d:	83 e8 01             	sub    $0x1,%eax
 570:	48 83 7d 08 00       	cmpq   $0x0,0x8(%rbp)
 575:	89 45 18             	mov    %eax,0x18(%rbp)
 578:	0f 85 00 00 00 00    	jne    57e <alloc_slot+0x57e>
			57a: R_X86_64_PC32	.text.unlikely.alloc_slot-0x4
 57e:	48 83 7d 00 00       	cmpq   $0x0,0x0(%rbp)
 583:	0f 85 00 00 00 00    	jne    589 <alloc_slot+0x589>
			585: R_X86_64_PC32	.text.unlikely.alloc_slot-0x4
 589:	49 83 c6 0a          	add    $0xa,%r14
 58d:	4b 8b 04 f7          	mov    (%r15,%r14,8),%rax
 591:	48 85 c0             	test   %rax,%rax
 594:	0f 84 9e 03 00 00    	je     938 <alloc_slot+0x938>
 59a:	48 89 45 08          	mov    %rax,0x8(%rbp)
 59e:	48 8b 00             	mov    (%rax),%rax
 5a1:	48 89 45 00          	mov    %rax,0x0(%rbp)
 5a5:	48 89 68 08          	mov    %rbp,0x8(%rax)
 5a9:	48 8b 45 08          	mov    0x8(%rbp),%rax
 5ad:	48 89 28             	mov    %rbp,(%rax)
 5b0:	31 c0                	xor    %eax,%eax
 5b2:	e9 5b fc ff ff       	jmp    212 <alloc_slot+0x212>
 5b7:	48 8d 05 00 00 00 00 	lea    0x0(%rip),%rax        # 5be <alloc_slot+0x5be>
			5ba: R_X86_64_PC32	__malloc_context+0x374
 5be:	48 8d 50 20          	lea    0x20(%rax),%rdx
 5c2:	eb 17                	jmp    5db <alloc_slot+0x5db>
 5c4:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
 5cb:	00 00 00 00 
 5cf:	90                   	nop
 5d0:	c6 00 00             	movb   $0x0,(%rax)
 5d3:	48 83 c0 02          	add    $0x2,%rax
 5d7:	c6 40 ff 00          	movb   $0x0,-0x1(%rax)
 5db:	48 39 d0             	cmp    %rdx,%rax
 5de:	75 f0                	jne    5d0 <alloc_slot+0x5d0>
 5e0:	b8 01 00 00 00       	mov    $0x1,%eax
 5e5:	e9 0a fe ff ff       	jmp    3f4 <alloc_slot+0x3f4>
 5ea:	4c 39 c9             	cmp    %r9,%rcx
 5ed:	0f 82 2f fe ff ff    	jb     422 <alloc_slot+0x422>
 5f3:	e9 33 fe ff ff       	jmp    42b <alloc_slot+0x42b>
 5f8:	44 89 e0             	mov    %r12d,%eax
 5fb:	83 e0 03             	and    $0x3,%eax
 5fe:	83 f8 02             	cmp    $0x2,%eax
 601:	74 6f                	je     672 <alloc_slot+0x672>
 603:	49 81 f8 00 80 00 00 	cmp    $0x8000,%r8
 60a:	76 74                	jbe    680 <alloc_slot+0x680>
 60c:	41 b8 01 00 00 00    	mov    $0x1,%r8d
 612:	ba 03 00 00 00       	mov    $0x3,%edx
 617:	bb 03 00 00 00       	mov    $0x3,%ebx
 61c:	e9 14 fe ff ff       	jmp    435 <alloc_slot+0x435>
 621:	4c 39 c9             	cmp    %r9,%rcx
 624:	0f 83 01 fe ff ff    	jae    42b <alloc_slot+0x42b>
 62a:	45 84 d2             	test   %r10b,%r10b
 62d:	0f 84 f8 fd ff ff    	je     42b <alloc_slot+0x42b>
 633:	44 89 e0             	mov    %r12d,%eax
 636:	83 e0 03             	and    $0x3,%eax
 639:	83 f8 01             	cmp    $0x1,%eax
 63c:	0f 85 e9 fd ff ff    	jne    42b <alloc_slot+0x42b>
 642:	49 81 f8 00 80 00 00 	cmp    $0x8000,%r8
 649:	0f 86 dc fd ff ff    	jbe    42b <alloc_slot+0x42b>
 64f:	4b 8d 54 2d 00       	lea    0x0(%r13,%r13,1),%rdx
 654:	48 c7 c0 f0 ff ff ff 	mov    $0xfffffffffffffff0,%rax
 65b:	bb 02 00 00 00       	mov    $0x2,%ebx
 660:	48 29 d0             	sub    %rdx,%rax
 663:	25 ff 0f 00 00       	and    $0xfff,%eax
 668:	4c 8d 54 02 10       	lea    0x10(%rdx,%rax,1),%r10
 66d:	e9 e4 fd ff ff       	jmp    456 <alloc_slot+0x456>
 672:	49 81 f8 00 40 00 00 	cmp    $0x4000,%r8
 679:	77 91                	ja     60c <alloc_slot+0x60c>
 67b:	e9 ab fd ff ff       	jmp    42b <alloc_slot+0x42b>
 680:	49 81 f8 00 20 00 00 	cmp    $0x2000,%r8
 687:	0f 86 9e fd ff ff    	jbe    42b <alloc_slot+0x42b>
 68d:	41 b8 01 00 00 00    	mov    $0x1,%r8d
 693:	ba 05 00 00 00       	mov    $0x5,%edx
 698:	bb 05 00 00 00       	mov    $0x5,%ebx
 69d:	e9 93 fd ff ff       	jmp    435 <alloc_slot+0x435>
 6a2:	66 0f ef c0          	pxor   %xmm0,%xmm0
 6a6:	48 c7 45 20 00 00 00 	movq   $0x0,0x20(%rbp)
 6ad:	00 
 6ae:	0f 11 45 00          	movups %xmm0,0x0(%rbp)
 6b2:	0f 11 45 10          	movups %xmm0,0x10(%rbp)
 6b6:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 6bd <alloc_slot+0x6bd>
			6b9: R_X86_64_PC32	__malloc_context+0xc
 6bd:	48 85 c0             	test   %rax,%rax
 6c0:	0f 85 d9 00 00 00    	jne    79f <alloc_slot+0x79f>
 6c6:	66 0f 6f 1c 24       	movdqa (%rsp),%xmm3
 6cb:	0f 11 5d 00          	movups %xmm3,0x0(%rbp)
 6cf:	48 89 2d 00 00 00 00 	mov    %rbp,0x0(%rip)        # 6d6 <alloc_slot+0x6d6>
			6d2: R_X86_64_PC32	__malloc_context+0xc
 6d6:	e9 da 00 00 00       	jmp    7b5 <alloc_slot+0x7b5>
 6db:	4c 89 c0             	mov    %r8,%rax
 6de:	49 8d 70 0c          	lea    0xc(%r8),%rsi
 6e2:	48 c1 e8 04          	shr    $0x4,%rax
 6e6:	89 c7                	mov    %eax,%edi
 6e8:	49 81 f8 90 00 00 00 	cmp    $0x90,%r8
 6ef:	76 30                	jbe    721 <alloc_slot+0x721>
 6f1:	48 83 c0 01          	add    $0x1,%rax
 6f5:	0f bd c8             	bsr    %eax,%ecx
 6f8:	8d 3c 8d fc ff ff ff 	lea    -0x4(,%rcx,4),%edi
 6ff:	8d 4f 01             	lea    0x1(%rdi),%ecx
 702:	48 63 c9             	movslq %ecx,%rcx
 705:	45 0f b7 04 49       	movzwl (%r9,%rcx,2),%r8d
 70a:	8d 4f 02             	lea    0x2(%rdi),%ecx
 70d:	49 39 c0             	cmp    %rax,%r8
 710:	0f 42 f9             	cmovb  %ecx,%edi
 713:	48 63 cf             	movslq %edi,%rcx
 716:	41 0f b7 0c 49       	movzwl (%r9,%rcx,2),%ecx
 71b:	48 39 c1             	cmp    %rax,%rcx
 71e:	83 d7 00             	adc    $0x0,%edi
 721:	48 89 54 24 18       	mov    %rdx,0x18(%rsp)
 726:	89 7c 24 10          	mov    %edi,0x10(%rsp)
 72a:	e8 d1 f8 ff ff       	call   0 <alloc_slot>
 72f:	48 63 7c 24 10       	movslq 0x10(%rsp),%rdi
 734:	48 8b 54 24 18       	mov    0x18(%rsp),%rdx
 739:	4c 8d 0d 00 00 00 00 	lea    0x0(%rip),%r9        # 740 <alloc_slot+0x740>
			73c: R_X86_64_PC32	__malloc_size_classes-0x4
 740:	83 f8 ff             	cmp    $0xffffffff,%eax
 743:	89 c1                	mov    %eax,%ecx
 745:	74 38                	je     77f <alloc_slot+0x77f>
 747:	41 0f b7 04 79       	movzwl (%r9,%rdi,2),%eax
 74c:	4d 8b 44 ff 50       	mov    0x50(%r15,%rdi,8),%r8
 751:	c1 e0 04             	shl    $0x4,%eax
 754:	83 e8 04             	sub    $0x4,%eax
 757:	89 44 24 18          	mov    %eax,0x18(%rsp)
 75b:	48 63 f0             	movslq %eax,%rsi
 75e:	41 f6 40 20 1f       	testb  $0x1f,0x20(%r8)
 763:	75 6c                	jne    7d1 <alloc_slot+0x7d1>
 765:	49 81 78 20 ff 0f 00 	cmpq   $0xfff,0x20(%r8)
 76c:	00 
 76d:	76 62                	jbe    7d1 <alloc_slot+0x7d1>
 76f:	49 8b 40 20          	mov    0x20(%r8),%rax
 773:	48 25 00 f0 ff ff    	and    $0xfffffffffffff000,%rax
 779:	48 83 e8 10          	sub    $0x10,%rax
 77d:	eb 68                	jmp    7e7 <alloc_slot+0x7e7>
 77f:	66 0f ef c0          	pxor   %xmm0,%xmm0
 783:	48 c7 45 20 00 00 00 	movq   $0x0,0x20(%rbp)
 78a:	00 
 78b:	0f 11 45 00          	movups %xmm0,0x0(%rbp)
 78f:	0f 11 45 10          	movups %xmm0,0x10(%rbp)
 793:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 79a <alloc_slot+0x79a>
			796: R_X86_64_PC32	__malloc_context+0xc
 79a:	48 85 c0             	test   %rax,%rax
 79d:	74 20                	je     7bf <alloc_slot+0x7bf>
 79f:	48 89 45 08          	mov    %rax,0x8(%rbp)
 7a3:	48 8b 00             	mov    (%rax),%rax
 7a6:	48 89 45 00          	mov    %rax,0x0(%rbp)
 7aa:	48 89 68 08          	mov    %rbp,0x8(%rax)
 7ae:	48 8b 45 08          	mov    0x8(%rbp),%rax
 7b2:	48 89 28             	mov    %rbp,(%rax)
 7b5:	b8 ff ff ff ff       	mov    $0xffffffff,%eax
 7ba:	e9 53 fa ff ff       	jmp    212 <alloc_slot+0x212>
 7bf:	66 0f 6f 24 24       	movdqa (%rsp),%xmm4
 7c4:	0f 11 65 00          	movups %xmm4,0x0(%rbp)
 7c8:	48 89 2d 00 00 00 00 	mov    %rbp,0x0(%rip)        # 7cf <alloc_slot+0x7cf>
			7cb: R_X86_64_PC32	__malloc_context+0xc
 7cf:	eb e4                	jmp    7b5 <alloc_slot+0x7b5>
 7d1:	41 0f b7 40 20       	movzwl 0x20(%r8),%eax
 7d6:	66 c1 e8 06          	shr    $0x6,%ax
 7da:	83 e0 3f             	and    $0x3f,%eax
 7dd:	41 0f b7 04 41       	movzwl (%r9,%rax,2),%eax
 7e2:	c1 e0 04             	shl    $0x4,%eax
 7e5:	48 98                	cltq
 7e7:	48 89 c7             	mov    %rax,%rdi
 7ea:	48 29 f7             	sub    %rsi,%rdi
 7ed:	48 63 f1             	movslq %ecx,%rsi
 7f0:	48 0f af f0          	imul   %rax,%rsi
 7f4:	4c 8d 4f fc          	lea    -0x4(%rdi),%r9
 7f8:	49 8b 78 10          	mov    0x10(%r8),%rdi
 7fc:	4d 89 ca             	mov    %r9,%r10
 7ff:	48 83 c7 10          	add    $0x10,%rdi
 803:	49 c1 ea 04          	shr    $0x4,%r10
 807:	48 01 fe             	add    %rdi,%rsi
 80a:	48 8d 44 06 fc       	lea    -0x4(%rsi,%rax,1),%rax
 80f:	80 7e fd 00          	cmpb   $0x0,-0x3(%rsi)
 813:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
 818:	0f 84 d8 00 00 00    	je     8f6 <alloc_slot+0x8f6>
 81e:	0f b7 46 fe          	movzwl -0x2(%rsi),%eax
 822:	83 c0 01             	add    $0x1,%eax
 825:	0f b6 c0             	movzbl %al,%eax
 828:	80 7e fc 00          	cmpb   $0x0,-0x4(%rsi)
 82c:	0f 85 00 00 00 00    	jne    832 <alloc_slot+0x832>
			82e: R_X86_64_PC32	.text.unlikely.alloc_slot-0x4
 832:	4c 63 d8             	movslq %eax,%r11
 835:	4d 39 da             	cmp    %r11,%r10
 838:	73 38                	jae    872 <alloc_slot+0x872>
 83a:	49 c1 e9 05          	shr    $0x5,%r9
 83e:	4d 09 d1             	or     %r10,%r9
 841:	4d 89 cb             	mov    %r9,%r11
 844:	49 c1 eb 02          	shr    $0x2,%r11
 848:	4d 09 d9             	or     %r11,%r9
 84b:	4d 89 cb             	mov    %r9,%r11
 84e:	49 c1 eb 04          	shr    $0x4,%r11
 852:	4d 09 d9             	or     %r11,%r9
 855:	44 21 c8             	and    %r9d,%eax
 858:	4c 63 c8             	movslq %eax,%r9
 85b:	4d 39 ca             	cmp    %r9,%r10
 85e:	73 12                	jae    872 <alloc_slot+0x872>
 860:	44 29 d0             	sub    %r10d,%eax
 863:	83 e8 01             	sub    $0x1,%eax
 866:	4c 63 c8             	movslq %eax,%r9
 869:	4d 39 ca             	cmp    %r9,%r10
 86c:	0f 82 00 00 00 00    	jb     872 <alloc_slot+0x872>
			86e: R_X86_64_PC32	.text.unlikely.alloc_slot-0x4
 872:	85 c0                	test   %eax,%eax
 874:	74 1c                	je     892 <alloc_slot+0x892>
 876:	66 89 46 fe          	mov    %ax,-0x2(%rsi)
 87a:	c1 e0 04             	shl    $0x4,%eax
 87d:	48 98                	cltq
 87f:	c6 46 fd e0          	movb   $0xe0,-0x3(%rsi)
 883:	48 01 c6             	add    %rax,%rsi
 886:	c6 46 fc 00          	movb   $0x0,-0x4(%rsi)
 88a:	49 8b 78 10          	mov    0x10(%r8),%rdi
 88e:	48 83 c7 10          	add    $0x10,%rdi
 892:	48 89 f0             	mov    %rsi,%rax
 895:	4c 8b 5c 24 10       	mov    0x10(%rsp),%r11
 89a:	88 4e fd             	mov    %cl,-0x3(%rsi)
 89d:	48 29 f8             	sub    %rdi,%rax
 8a0:	89 cf                	mov    %ecx,%edi
 8a2:	8b 4c 24 18          	mov    0x18(%rsp),%ecx
 8a6:	48 c1 e8 04          	shr    $0x4,%rax
 8aa:	66 89 46 fe          	mov    %ax,-0x2(%rsi)
 8ae:	4c 89 d8             	mov    %r11,%rax
 8b1:	48 29 f0             	sub    %rsi,%rax
 8b4:	29 c8                	sub    %ecx,%eax
 8b6:	74 1d                	je     8d5 <alloc_slot+0x8d5>
 8b8:	89 c1                	mov    %eax,%ecx
 8ba:	f7 d9                	neg    %ecx
 8bc:	48 63 c9             	movslq %ecx,%rcx
 8bf:	41 c6 04 0b 00       	movb   $0x0,(%r11,%rcx,1)
 8c4:	83 f8 04             	cmp    $0x4,%eax
 8c7:	7f 39                	jg     902 <alloc_slot+0x902>
 8c9:	0f b6 7e fd          	movzbl -0x3(%rsi),%edi
 8cd:	c1 e0 05             	shl    $0x5,%eax
 8d0:	83 e7 1f             	and    $0x1f,%edi
 8d3:	01 c7                	add    %eax,%edi
 8d5:	40 88 7e fd          	mov    %dil,-0x3(%rsi)
 8d9:	48 8d 4e 0c          	lea    0xc(%rsi),%rcx
 8dd:	48 81 65 20 ff 0f 00 	andq   $0xfff,0x20(%rbp)
 8e4:	00 
 8e5:	0f b6 46 fd          	movzbl -0x3(%rsi),%eax
 8e9:	83 e0 1f             	and    $0x1f,%eax
 8ec:	83 c8 c0             	or     $0xffffffc0,%eax
 8ef:	88 46 fd             	mov    %al,-0x3(%rsi)
 8f2:	31 c0                	xor    %eax,%eax
 8f4:	eb 33                	jmp    929 <alloc_slot+0x929>
 8f6:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 8fd <alloc_slot+0x8fd>
			8f9: R_X86_64_PC32	__malloc_context+0x8
 8fd:	e9 26 ff ff ff       	jmp    828 <alloc_slot+0x828>
 902:	41 89 43 fc          	mov    %eax,-0x4(%r11)
 906:	41 c6 43 fb 00       	movb   $0x0,-0x5(%r11)
 90b:	0f b6 7e fd          	movzbl -0x3(%rsi),%edi
 90f:	83 e7 1f             	and    $0x1f,%edi
 912:	83 ef 60             	sub    $0x60,%edi
 915:	eb be                	jmp    8d5 <alloc_slot+0x8d5>
 917:	66 0f 1f 84 00 00 00 	nopw   0x0(%rax,%rax,1)
 91e:	00 00 
 920:	c6 01 00             	movb   $0x0,(%rcx)
 923:	83 c0 01             	add    $0x1,%eax
 926:	4c 01 e9             	add    %r13,%rcx
 929:	39 c3                	cmp    %eax,%ebx
 92b:	7d f3                	jge    920 <alloc_slot+0x920>
 92d:	8d 7b ff             	lea    -0x1(%rbx),%edi
 930:	41 89 f8             	mov    %edi,%r8d
 933:	e9 cb fb ff ff       	jmp    503 <alloc_slot+0x503>
 938:	66 0f 6f 14 24       	movdqa (%rsp),%xmm2
 93d:	0f 11 55 00          	movups %xmm2,0x0(%rbp)
 941:	4b 89 2c f7          	mov    %rbp,(%r15,%r14,8)
 945:	e9 66 fc ff ff       	jmp    5b0 <alloc_slot+0x5b0>

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
  1b:	0f 82 25 01 00 00    	jb     146 <__libc_malloc_impl+0x146>
  21:	48 89 fd             	mov    %rdi,%rbp
  24:	48 81 ff eb ff 01 00 	cmp    $0x1ffeb,%rdi
  2b:	0f 87 27 01 00 00    	ja     158 <__libc_malloc_impl+0x158>
  31:	48 8d 57 03          	lea    0x3(%rdi),%rdx
  35:	48 89 d0             	mov    %rdx,%rax
  38:	48 c1 e8 04          	shr    $0x4,%rax
  3c:	48 63 d8             	movslq %eax,%rbx
  3f:	49 89 df             	mov    %rbx,%r15
  42:	48 81 fa 9f 00 00 00 	cmp    $0x9f,%rdx
  49:	76 3f                	jbe    8a <__libc_malloc_impl+0x8a>
  4b:	48 83 c0 01          	add    $0x1,%rax
  4f:	48 8d 0d 00 00 00 00 	lea    0x0(%rip),%rcx        # 56 <__libc_malloc_impl+0x56>
			52: R_X86_64_PC32	__malloc_size_classes-0x4
  56:	0f bd d0             	bsr    %eax,%edx
  59:	44 8d 3c 95 fc ff ff 	lea    -0x4(,%rdx,4),%r15d
  60:	ff 
  61:	41 8d 57 01          	lea    0x1(%r15),%edx
  65:	48 63 d2             	movslq %edx,%rdx
  68:	0f b7 34 51          	movzwl (%rcx,%rdx,2),%esi
  6c:	41 8d 57 02          	lea    0x2(%r15),%edx
  70:	48 39 c6             	cmp    %rax,%rsi
  73:	44 0f 42 fa          	cmovb  %edx,%r15d
  77:	49 63 df             	movslq %r15d,%rbx
  7a:	0f b7 14 59          	movzwl (%rcx,%rbx,2),%edx
  7e:	48 39 c2             	cmp    %rax,%rdx
  81:	73 07                	jae    8a <__libc_malloc_impl+0x8a>
  83:	41 83 c7 01          	add    $0x1,%r15d
  87:	49 63 df             	movslq %r15d,%rbx
  8a:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 91 <__libc_malloc_impl+0x91>
			8d: R_X86_64_PC32	__libc-0x1
  91:	4c 8d 35 00 00 00 00 	lea    0x0(%rip),%r14        # 98 <__libc_malloc_impl+0x98>
			94: R_X86_64_PC32	__malloc_lock-0x4
  98:	84 c0                	test   %al,%al
  9a:	0f 85 be 01 00 00    	jne    25e <__libc_malloc_impl+0x25e>
  a0:	48 8d 15 00 00 00 00 	lea    0x0(%rip),%rdx        # a7 <__libc_malloc_impl+0xa7>
			a3: R_X86_64_PC32	__malloc_context-0x4
  a7:	4c 8b 64 da 50       	mov    0x50(%rdx,%rbx,8),%r12
  ac:	4d 85 e4             	test   %r12,%r12
  af:	0f 85 e6 01 00 00    	jne    29b <__libc_malloc_impl+0x29b>
  b5:	41 83 ff 03          	cmp    $0x3,%r15d
  b9:	0f 8e d3 01 00 00    	jle    292 <__libc_malloc_impl+0x292>
  bf:	41 83 ff 1f          	cmp    $0x1f,%r15d
  c3:	7f 4d                	jg     112 <__libc_malloc_impl+0x112>
  c5:	41 83 ff 06          	cmp    $0x6,%r15d
  c9:	74 47                	je     112 <__libc_malloc_impl+0x112>
  cb:	41 f6 c7 01          	test   $0x1,%r15b
  cf:	75 41                	jne    112 <__libc_malloc_impl+0x112>
  d1:	48 83 bc da f8 01 00 	cmpq   $0x0,0x1f8(%rdx,%rbx,8)
  d8:	00 00 
  da:	75 36                	jne    112 <__libc_malloc_impl+0x112>
  dc:	44 89 fe             	mov    %r15d,%esi
  df:	83 ce 01             	or     $0x1,%esi
  e2:	48 63 c6             	movslq %esi,%rax
  e5:	4c 8b 64 c2 50       	mov    0x50(%rdx,%rax,8),%r12
  ea:	48 8b 8c c2 f8 01 00 	mov    0x1f8(%rdx,%rax,8),%rcx
  f1:	00 
  f2:	4d 85 e4             	test   %r12,%r12
  f5:	0f 84 86 01 00 00    	je     281 <__libc_malloc_impl+0x281>
  fb:	41 8b 44 24 18       	mov    0x18(%r12),%eax
 100:	85 c0                	test   %eax,%eax
 102:	0f 84 63 01 00 00    	je     26b <__libc_malloc_impl+0x26b>
 108:	48 83 f9 0c          	cmp    $0xc,%rcx
 10c:	0f 86 e5 01 00 00    	jbe    2f7 <__libc_malloc_impl+0x2f7>
 112:	48 89 ee             	mov    %rbp,%rsi
 115:	44 89 ff             	mov    %r15d,%edi
 118:	e8 00 00 00 00       	call   11d <__libc_malloc_impl+0x11d>
			119: R_X86_64_PC32	.text.alloc_slot-0x4
 11d:	48 8d 15 00 00 00 00 	lea    0x0(%rip),%rdx        # 124 <__libc_malloc_impl+0x124>
			120: R_X86_64_PC32	__malloc_context-0x4
 124:	83 f8 ff             	cmp    $0xffffffff,%eax
 127:	41 89 c5             	mov    %eax,%r13d
 12a:	0f 84 cc 01 00 00    	je     2fc <__libc_malloc_impl+0x2fc>
 130:	49 63 c7             	movslq %r15d,%rax
 133:	8b 1d 00 00 00 00    	mov    0x0(%rip),%ebx        # 139 <__libc_malloc_impl+0x139>
			135: R_X86_64_PC32	__malloc_context+0x8
 139:	4d 63 fd             	movslq %r13d,%r15
 13c:	4c 8b 64 c2 50       	mov    0x50(%rdx,%rax,8),%r12
 141:	e9 82 01 00 00       	jmp    2c8 <__libc_malloc_impl+0x2c8>
 146:	e8 00 00 00 00       	call   14b <__libc_malloc_impl+0x14b>
			147: R_X86_64_PLT32	___errno_location-0x4
 14b:	c7 00 0c 00 00 00    	movl   $0xc,(%rax)
 151:	31 c0                	xor    %eax,%eax
 153:	e9 ca 02 00 00       	jmp    422 <__libc_malloc_impl+0x422>
 158:	4c 8d 6f 14          	lea    0x14(%rdi),%r13
 15c:	48 8d 9f 13 10 00 00 	lea    0x1013(%rdi),%rbx
 163:	45 31 c9             	xor    %r9d,%r9d
 166:	31 ff                	xor    %edi,%edi
 168:	41 b8 ff ff ff ff    	mov    $0xffffffff,%r8d
 16e:	b9 22 00 00 00       	mov    $0x22,%ecx
 173:	ba 03 00 00 00       	mov    $0x3,%edx
 178:	4c 89 ee             	mov    %r13,%rsi
 17b:	e8 00 00 00 00       	call   180 <__libc_malloc_impl+0x180>
			17c: R_X86_64_PLT32	__mmap-0x4
 180:	49 89 c7             	mov    %rax,%r15
 183:	48 83 f8 ff          	cmp    $0xffffffffffffffff,%rax
 187:	74 c8                	je     151 <__libc_malloc_impl+0x151>
 189:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 190 <__libc_malloc_impl+0x190>
			18c: R_X86_64_PC32	__libc-0x1
 190:	4c 8d 35 00 00 00 00 	lea    0x0(%rip),%r14        # 197 <__libc_malloc_impl+0x197>
			193: R_X86_64_PC32	__malloc_lock-0x4
 197:	84 c0                	test   %al,%al
 199:	75 62                	jne    1fd <__libc_malloc_impl+0x1fd>
 19b:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 1a2 <__libc_malloc_impl+0x1a2>
			19e: R_X86_64_PC32	__malloc_context+0x3b4
 1a2:	8d 50 01             	lea    0x1(%rax),%edx
 1a5:	3c ff                	cmp    $0xff,%al
 1a7:	74 5e                	je     207 <__libc_malloc_impl+0x207>
 1a9:	88 15 00 00 00 00    	mov    %dl,0x0(%rip)        # 1af <__libc_malloc_impl+0x1af>
			1ab: R_X86_64_PC32	__malloc_context+0x3b4
 1af:	e8 00 00 00 00       	call   1b4 <__libc_malloc_impl+0x1b4>
			1b0: R_X86_64_PLT32	__malloc_alloc_meta-0x4
 1b4:	49 89 c4             	mov    %rax,%r12
 1b7:	48 85 c0             	test   %rax,%rax
 1ba:	74 7e                	je     23a <__libc_malloc_impl+0x23a>
 1bc:	48 81 e3 00 f0 ff ff 	and    $0xfffffffffffff000,%rbx
 1c3:	4c 89 78 10          	mov    %r15,0x10(%rax)
 1c7:	45 31 ed             	xor    %r13d,%r13d
 1ca:	48 81 cb e0 0f 00 00 	or     $0xfe0,%rbx
 1d1:	49 89 07             	mov    %rax,(%r15)
 1d4:	45 31 ff             	xor    %r15d,%r15d
 1d7:	48 89 58 20          	mov    %rbx,0x20(%rax)
 1db:	c7 40 1c 00 00 00 00 	movl   $0x0,0x1c(%rax)
 1e2:	c7 40 18 00 00 00 00 	movl   $0x0,0x18(%rax)
 1e9:	8b 05 00 00 00 00    	mov    0x0(%rip),%eax        # 1ef <__libc_malloc_impl+0x1ef>
			1eb: R_X86_64_PC32	__malloc_context+0x8
 1ef:	8d 58 01             	lea    0x1(%rax),%ebx
 1f2:	89 1d 00 00 00 00    	mov    %ebx,0x0(%rip)        # 1f8 <__libc_malloc_impl+0x1f8>
			1f4: R_X86_64_PC32	__malloc_context+0x8
 1f8:	e9 cb 00 00 00       	jmp    2c8 <__libc_malloc_impl+0x2c8>
 1fd:	4c 89 f7             	mov    %r14,%rdi
 200:	e8 00 00 00 00       	call   205 <__libc_malloc_impl+0x205>
			201: R_X86_64_PLT32	__lock-0x4
 205:	eb 94                	jmp    19b <__libc_malloc_impl+0x19b>
 207:	48 8d 05 00 00 00 00 	lea    0x0(%rip),%rax        # 20e <__libc_malloc_impl+0x20e>
			20a: R_X86_64_PC32	__malloc_context+0x374
 20e:	48 8d 50 20          	lea    0x20(%rax),%rdx
 212:	eb 17                	jmp    22b <__libc_malloc_impl+0x22b>
 214:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
 21b:	00 00 00 00 
 21f:	90                   	nop
 220:	c6 00 00             	movb   $0x0,(%rax)
 223:	48 83 c0 02          	add    $0x2,%rax
 227:	c6 40 ff 00          	movb   $0x0,-0x1(%rax)
 22b:	48 39 d0             	cmp    %rdx,%rax
 22e:	75 f0                	jne    220 <__libc_malloc_impl+0x220>
 230:	ba 01 00 00 00       	mov    $0x1,%edx
 235:	e9 6f ff ff ff       	jmp    1a9 <__libc_malloc_impl+0x1a9>
 23a:	8b 05 00 00 00 00    	mov    0x0(%rip),%eax        # 240 <__libc_malloc_impl+0x240>
			23c: R_X86_64_PC32	__malloc_lock-0x4
 240:	85 c0                	test   %eax,%eax
 242:	78 10                	js     254 <__libc_malloc_impl+0x254>
 244:	4c 89 ee             	mov    %r13,%rsi
 247:	4c 89 ff             	mov    %r15,%rdi
 24a:	e8 00 00 00 00       	call   24f <__libc_malloc_impl+0x24f>
			24b: R_X86_64_PLT32	munmap-0x4
 24f:	e9 fd fe ff ff       	jmp    151 <__libc_malloc_impl+0x151>
 254:	4c 89 f7             	mov    %r14,%rdi
 257:	e8 00 00 00 00       	call   25c <__libc_malloc_impl+0x25c>
			258: R_X86_64_PLT32	__unlock-0x4
 25c:	eb e6                	jmp    244 <__libc_malloc_impl+0x244>
 25e:	4c 89 f7             	mov    %r14,%rdi
 261:	e8 00 00 00 00       	call   266 <__libc_malloc_impl+0x266>
			262: R_X86_64_PLT32	__lock-0x4
 266:	e9 35 fe ff ff       	jmp    a0 <__libc_malloc_impl+0xa0>
 26b:	41 8b 44 24 1c       	mov    0x1c(%r12),%eax
 270:	85 c0                	test   %eax,%eax
 272:	0f 85 90 fe ff ff    	jne    108 <__libc_malloc_impl+0x108>
 278:	48 83 c1 03          	add    $0x3,%rcx
 27c:	e9 87 fe ff ff       	jmp    108 <__libc_malloc_impl+0x108>
 281:	48 83 c1 03          	add    $0x3,%rcx
 285:	48 83 f9 0c          	cmp    $0xc,%rcx
 289:	44 0f 46 fe          	cmovbe %esi,%r15d
 28d:	e9 80 fe ff ff       	jmp    112 <__libc_malloc_impl+0x112>
 292:	4d 85 e4             	test   %r12,%r12
 295:	0f 84 77 fe ff ff    	je     112 <__libc_malloc_impl+0x112>
 29b:	41 8b 44 24 18       	mov    0x18(%r12),%eax
 2a0:	41 89 c5             	mov    %eax,%r13d
 2a3:	41 f7 dd             	neg    %r13d
 2a6:	41 21 c5             	and    %eax,%r13d
 2a9:	0f 84 63 fe ff ff    	je     112 <__libc_malloc_impl+0x112>
 2af:	44 29 e8             	sub    %r13d,%eax
 2b2:	45 31 ff             	xor    %r15d,%r15d
 2b5:	8b 1d 00 00 00 00    	mov    0x0(%rip),%ebx        # 2bb <__libc_malloc_impl+0x2bb>
			2b7: R_X86_64_PC32	__malloc_context+0x8
 2bb:	41 89 44 24 18       	mov    %eax,0x18(%r12)
 2c0:	f3 45 0f bc fd       	tzcnt  %r13d,%r15d
 2c5:	4d 89 fd             	mov    %r15,%r13
 2c8:	8b 05 00 00 00 00    	mov    0x0(%rip),%eax        # 2ce <__libc_malloc_impl+0x2ce>
			2ca: R_X86_64_PC32	__malloc_lock-0x4
 2ce:	85 c0                	test   %eax,%eax
 2d0:	78 45                	js     317 <__libc_malloc_impl+0x317>
 2d2:	41 f6 44 24 20 1f    	testb  $0x1f,0x20(%r12)
 2d8:	75 47                	jne    321 <__libc_malloc_impl+0x321>
 2da:	49 81 7c 24 20 ff 0f 	cmpq   $0xfff,0x20(%r12)
 2e1:	00 00 
 2e3:	76 3c                	jbe    321 <__libc_malloc_impl+0x321>
 2e5:	49 8b 54 24 20       	mov    0x20(%r12),%rdx
 2ea:	48 81 e2 00 f0 ff ff 	and    $0xfffffffffffff000,%rdx
 2f1:	48 83 ea 10          	sub    $0x10,%rdx
 2f5:	eb 48                	jmp    33f <__libc_malloc_impl+0x33f>
 2f7:	41 89 f7             	mov    %esi,%r15d
 2fa:	eb 9f                	jmp    29b <__libc_malloc_impl+0x29b>
 2fc:	8b 05 00 00 00 00    	mov    0x0(%rip),%eax        # 302 <__libc_malloc_impl+0x302>
			2fe: R_X86_64_PC32	__malloc_lock-0x4
 302:	85 c0                	test   %eax,%eax
 304:	0f 89 47 fe ff ff    	jns    151 <__libc_malloc_impl+0x151>
 30a:	4c 89 f7             	mov    %r14,%rdi
 30d:	e8 00 00 00 00       	call   312 <__libc_malloc_impl+0x312>
			30e: R_X86_64_PLT32	__unlock-0x4
 312:	e9 3a fe ff ff       	jmp    151 <__libc_malloc_impl+0x151>
 317:	4c 89 f7             	mov    %r14,%rdi
 31a:	e8 00 00 00 00       	call   31f <__libc_malloc_impl+0x31f>
			31b: R_X86_64_PLT32	__unlock-0x4
 31f:	eb b1                	jmp    2d2 <__libc_malloc_impl+0x2d2>
 321:	41 0f b7 54 24 20    	movzwl 0x20(%r12),%edx
 327:	48 8d 05 00 00 00 00 	lea    0x0(%rip),%rax        # 32e <__libc_malloc_impl+0x32e>
			32a: R_X86_64_PC32	__malloc_size_classes-0x4
 32e:	66 c1 ea 06          	shr    $0x6,%dx
 332:	83 e2 3f             	and    $0x3f,%edx
 335:	0f b7 14 50          	movzwl (%rax,%rdx,2),%edx
 339:	c1 e2 04             	shl    $0x4,%edx
 33c:	48 63 d2             	movslq %edx,%rdx
 33f:	4c 0f af fa          	imul   %rdx,%r15
 343:	48 89 d0             	mov    %rdx,%rax
 346:	49 8b 74 24 10       	mov    0x10(%r12),%rsi
 34b:	48 29 e8             	sub    %rbp,%rax
 34e:	48 8d 48 fc          	lea    -0x4(%rax),%rcx
 352:	48 83 c6 10          	add    $0x10,%rsi
 356:	4a 8d 04 3e          	lea    (%rsi,%r15,1),%rax
 35a:	49 89 c8             	mov    %rcx,%r8
 35d:	49 c1 e8 04          	shr    $0x4,%r8
 361:	80 78 fd 00          	cmpb   $0x0,-0x3(%rax)
 365:	48 8d 7c 10 fc       	lea    -0x4(%rax,%rdx,1),%rdi
 36a:	0f b6 d3             	movzbl %bl,%edx
 36d:	74 0a                	je     379 <__libc_malloc_impl+0x379>
 36f:	0f b7 50 fe          	movzwl -0x2(%rax),%edx
 373:	83 c2 01             	add    $0x1,%edx
 376:	0f b6 d2             	movzbl %dl,%edx
 379:	80 78 fc 00          	cmpb   $0x0,-0x4(%rax)
 37d:	0f 85 00 00 00 00    	jne    383 <__libc_malloc_impl+0x383>
			37f: R_X86_64_PC32	.text.unlikely.__libc_malloc_impl-0x4
 383:	4c 63 ca             	movslq %edx,%r9
 386:	4d 39 c8             	cmp    %r9,%r8
 389:	73 37                	jae    3c2 <__libc_malloc_impl+0x3c2>
 38b:	48 c1 e9 05          	shr    $0x5,%rcx
 38f:	4c 09 c1             	or     %r8,%rcx
 392:	49 89 c9             	mov    %rcx,%r9
 395:	49 c1 e9 02          	shr    $0x2,%r9
 399:	4c 09 c9             	or     %r9,%rcx
 39c:	49 89 c9             	mov    %rcx,%r9
 39f:	49 c1 e9 04          	shr    $0x4,%r9
 3a3:	4c 09 c9             	or     %r9,%rcx
 3a6:	21 ca                	and    %ecx,%edx
 3a8:	48 63 ca             	movslq %edx,%rcx
 3ab:	49 39 c8             	cmp    %rcx,%r8
 3ae:	73 12                	jae    3c2 <__libc_malloc_impl+0x3c2>
 3b0:	44 29 c2             	sub    %r8d,%edx
 3b3:	83 ea 01             	sub    $0x1,%edx
 3b6:	48 63 ca             	movslq %edx,%rcx
 3b9:	49 39 c8             	cmp    %rcx,%r8
 3bc:	0f 82 00 00 00 00    	jb     3c2 <__libc_malloc_impl+0x3c2>
			3be: R_X86_64_PC32	.text.unlikely.__libc_malloc_impl-0x4
 3c2:	85 d2                	test   %edx,%edx
 3c4:	74 1e                	je     3e4 <__libc_malloc_impl+0x3e4>
 3c6:	66 89 50 fe          	mov    %dx,-0x2(%rax)
 3ca:	c1 e2 04             	shl    $0x4,%edx
 3cd:	48 63 d2             	movslq %edx,%rdx
 3d0:	c6 40 fd e0          	movb   $0xe0,-0x3(%rax)
 3d4:	48 01 d0             	add    %rdx,%rax
 3d7:	c6 40 fc 00          	movb   $0x0,-0x4(%rax)
 3db:	49 8b 74 24 10       	mov    0x10(%r12),%rsi
 3e0:	48 83 c6 10          	add    $0x10,%rsi
 3e4:	48 89 c2             	mov    %rax,%rdx
 3e7:	44 88 68 fd          	mov    %r13b,-0x3(%rax)
 3eb:	44 89 e9             	mov    %r13d,%ecx
 3ee:	48 29 f2             	sub    %rsi,%rdx
 3f1:	48 c1 ea 04          	shr    $0x4,%rdx
 3f5:	66 89 50 fe          	mov    %dx,-0x2(%rax)
 3f9:	48 89 fa             	mov    %rdi,%rdx
 3fc:	48 29 c2             	sub    %rax,%rdx
 3ff:	29 ea                	sub    %ebp,%edx
 401:	74 1c                	je     41f <__libc_malloc_impl+0x41f>
 403:	89 d1                	mov    %edx,%ecx
 405:	f7 d9                	neg    %ecx
 407:	48 63 c9             	movslq %ecx,%rcx
 40a:	c6 04 0f 00          	movb   $0x0,(%rdi,%rcx,1)
 40e:	83 fa 04             	cmp    $0x4,%edx
 411:	7f 1e                	jg     431 <__libc_malloc_impl+0x431>
 413:	0f b6 48 fd          	movzbl -0x3(%rax),%ecx
 417:	c1 e2 05             	shl    $0x5,%edx
 41a:	83 e1 1f             	and    $0x1f,%ecx
 41d:	01 d1                	add    %edx,%ecx
 41f:	88 48 fd             	mov    %cl,-0x3(%rax)
 422:	48 83 c4 08          	add    $0x8,%rsp
 426:	5b                   	pop    %rbx
 427:	5d                   	pop    %rbp
 428:	41 5c                	pop    %r12
 42a:	41 5d                	pop    %r13
 42c:	41 5e                	pop    %r14
 42e:	41 5f                	pop    %r15
 430:	c3                   	ret
 431:	89 57 fc             	mov    %edx,-0x4(%rdi)
 434:	c6 47 fb 00          	movb   $0x0,-0x5(%rdi)
 438:	0f b6 48 fd          	movzbl -0x3(%rax),%ecx
 43c:	83 e1 1f             	and    $0x1f,%ecx
 43f:	83 e9 60             	sub    $0x60,%ecx
 442:	eb db                	jmp    41f <__libc_malloc_impl+0x41f>

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
  d8:	77 43                	ja     11d <__malloc_allzerop+0x11d>
  da:	31 c0                	xor    %eax,%eax
  dc:	c3                   	ret
  dd:	e9 00 00 00 00       	jmp    e2 <__malloc_allzerop+0xe2>
			de: R_X86_64_PC32	.text.unlikely.__malloc_allzerop-0x4
  e2:	f7 d6                	not    %esi
  e4:	66 f7 c6 c0 0f       	test   $0xfc0,%si
  e9:	75 10                	jne    fb <__malloc_allzerop+0xfb>
  eb:	48 81 78 20 ff 0f 00 	cmpq   $0xfff,0x20(%rax)
  f2:	00 
  f3:	77 0b                	ja     100 <__malloc_allzerop+0x100>
  f5:	b8 01 00 00 00       	mov    $0x1,%eax
  fa:	c3                   	ret
  fb:	e9 00 00 00 00       	jmp    100 <__malloc_allzerop+0x100>
			fc: R_X86_64_PC32	.text.unlikely.__malloc_allzerop-0x4
 100:	48 8b 50 20          	mov    0x20(%rax),%rdx
 104:	48 81 e2 00 f0 ff ff 	and    $0xfffffffffffff000,%rdx
 10b:	48 c1 ea 04          	shr    $0x4,%rdx
 10f:	48 83 ea 01          	sub    $0x1,%rdx
 113:	48 39 ca             	cmp    %rcx,%rdx
 116:	73 dd                	jae    f5 <__malloc_allzerop+0xf5>
 118:	e9 00 00 00 00       	jmp    11d <__malloc_allzerop+0x11d>
			119: R_X86_64_PC32	.text.unlikely.__malloc_allzerop-0x4
 11d:	48 8b 50 20          	mov    0x20(%rax),%rdx
 121:	48 63 c1             	movslq %ecx,%rax
 124:	48 81 e2 00 f0 ff ff 	and    $0xfffffffffffff000,%rdx
 12b:	48 89 d1             	mov    %rdx,%rcx
 12e:	48 c1 e9 04          	shr    $0x4,%rcx
 132:	48 83 e9 01          	sub    $0x1,%rcx
 136:	48 39 c1             	cmp    %rax,%rcx
 139:	72 1a                	jb     155 <__malloc_allzerop+0x155>
 13b:	c1 e6 04             	shl    $0x4,%esi
 13e:	31 c0                	xor    %eax,%eax
 140:	83 e7 1f             	and    $0x1f,%edi
 143:	48 63 f6             	movslq %esi,%rsi
 146:	75 12                	jne    15a <__malloc_allzerop+0x15a>
 148:	48 83 ea 10          	sub    $0x10,%rdx
 14c:	31 c0                	xor    %eax,%eax
 14e:	48 39 f2             	cmp    %rsi,%rdx
 151:	0f 92 c0             	setb   %al
 154:	c3                   	ret
 155:	e9 00 00 00 00       	jmp    15a <__malloc_allzerop+0x15a>
			156: R_X86_64_PC32	.text.unlikely.__malloc_allzerop-0x4
 15a:	c3                   	ret

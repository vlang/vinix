
/Users/alex/code/vinix/third_party/useralloc-libc/build/useralloc/v6-prototype/cache/x86_64/e2aafe45791c748b1a101bcb8e017566e835e6f27fd623513503e67ee426bd6e/objects/obj/src/malloc/mallocng/malloc.o:     file format elf64-x86-64


Disassembly of section .text.__malloc_atfork:

0000000000000000 <__malloc_atfork>:
   0:	85 ff                	test   %edi,%edi
   2:	78 0d                	js     11 <__malloc_atfork+0x11>
   4:	74 21                	je     27 <__malloc_atfork+0x27>
   6:	c7 05 00 00 00 00 00 	movl   $0x0,0x0(%rip)        # 10 <__malloc_atfork+0x10>
   d:	00 00 00 
			8: R_X86_64_PC32	__malloc_lock-0x8
  10:	c3                   	ret
  11:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 18 <__malloc_atfork+0x18>
			14: R_X86_64_PC32	__libc-0x1
  18:	84 c0                	test   %al,%al
  1a:	75 01                	jne    1d <__malloc_atfork+0x1d>
  1c:	c3                   	ret
  1d:	bf 00 00 00 00       	mov    $0x0,%edi
			1e: R_X86_64_32	__malloc_lock
  22:	e9 00 00 00 00       	jmp    27 <__malloc_atfork+0x27>
			23: R_X86_64_PLT32	__lock-0x4
  27:	8b 05 00 00 00 00    	mov    0x0(%rip),%eax        # 2d <__malloc_atfork+0x2d>
			29: R_X86_64_PC32	__malloc_lock-0x4
  2d:	85 c0                	test   %eax,%eax
  2f:	79 eb                	jns    1c <__malloc_atfork+0x1c>
  31:	bf 00 00 00 00       	mov    $0x0,%edi
			32: R_X86_64_32	__malloc_lock
  36:	e9 00 00 00 00       	jmp    3b <__malloc_atfork+0x3b>
			37: R_X86_64_PLT32	__unlock-0x4

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
   2:	41 56                	push   %r14
   4:	4c 63 f7             	movslq %edi,%r14
   7:	48 89 f7             	mov    %rsi,%rdi
   a:	41 55                	push   %r13
   c:	49 8d 46 0a          	lea    0xa(%r14),%rax
  10:	41 54                	push   %r12
  12:	4d 89 f4             	mov    %r14,%r12
  15:	55                   	push   %rbp
  16:	53                   	push   %rbx
  17:	48 83 ec 28          	sub    $0x28,%rsp
  1b:	48 8b 14 c5 00 00 00 	mov    0x0(,%rax,8),%rdx
  22:	00 
			1f: R_X86_64_32S	__malloc_context
  23:	48 85 d2             	test   %rdx,%rdx
  26:	74 56                	je     7e <alloc_slot+0x7e>
  28:	8b 4a 18             	mov    0x18(%rdx),%ecx
  2b:	85 c9                	test   %ecx,%ecx
  2d:	0f 85 cb 01 00 00    	jne    1fe <alloc_slot+0x1fe>
  33:	8b 72 1c             	mov    0x1c(%rdx),%esi
  36:	48 8b 4a 08          	mov    0x8(%rdx),%rcx
  3a:	85 f6                	test   %esi,%esi
  3c:	0f 85 eb 00 00 00    	jne    12d <alloc_slot+0x12d>
  42:	48 39 ca             	cmp    %rcx,%rdx
  45:	0f 84 d1 00 00 00    	je     11c <alloc_slot+0x11c>
  4b:	48 8b 32             	mov    (%rdx),%rsi
  4e:	48 89 4e 08          	mov    %rcx,0x8(%rsi)
  52:	48 8b 32             	mov    (%rdx),%rsi
  55:	48 89 31             	mov    %rsi,(%rcx)
  58:	48 3b 14 c5 00 00 00 	cmp    0x0(,%rax,8),%rdx
  5f:	00 
			5c: R_X86_64_32S	__malloc_context
  60:	0f 84 a5 00 00 00    	je     10b <alloc_slot+0x10b>
  66:	66 0f ef c0          	pxor   %xmm0,%xmm0
  6a:	0f 11 02             	movups %xmm0,(%rdx)
  6d:	4a 8b 14 f5 00 00 00 	mov    0x0(,%r14,8),%rdx
  74:	00 
			71: R_X86_64_32S	__malloc_context+0x50
  75:	48 85 d2             	test   %rdx,%rdx
  78:	0f 85 ba 00 00 00    	jne    138 <alloc_slot+0x138>
  7e:	47 0f b7 ac 36 00 00 	movzwl 0x0(%r14,%r14,1),%r13d
  85:	00 00 
			83: R_X86_64_32S	__malloc_size_classes
  87:	48 89 7c 24 10       	mov    %rdi,0x10(%rsp)
  8c:	e8 00 00 00 00       	call   91 <alloc_slot+0x91>
			8d: R_X86_64_PLT32	__malloc_alloc_meta-0x4
  91:	66 48 0f 6e c8       	movq   %rax,%xmm1
  96:	41 c1 e5 04          	shl    $0x4,%r13d
  9a:	48 89 c5             	mov    %rax,%rbp
  9d:	66 0f 6c c9          	punpcklqdq %xmm1,%xmm1
  a1:	4d 63 ed             	movslq %r13d,%r13
  a4:	0f 29 0c 24          	movaps %xmm1,(%rsp)
  a8:	48 85 c0             	test   %rax,%rax
  ab:	0f 84 f0 06 00 00    	je     7a1 <alloc_slot+0x7a1>
  b1:	41 83 fc 08          	cmp    $0x8,%r12d
  b5:	4a 8b 14 f5 00 00 00 	mov    0x0(,%r14,8),%rdx
  bc:	00 
			b9: R_X86_64_32S	__malloc_context+0x1f8
  bd:	48 8b 7c 24 10       	mov    0x10(%rsp),%rdi
  c2:	0f 8f 0e 02 00 00    	jg     2d6 <alloc_slot+0x2d6>
  c8:	4b 8d 04 76          	lea    (%r14,%r14,2),%rax
  cc:	0f b6 98 00 00 00 00 	movzbl 0x0(%rax),%ebx
			cf: R_X86_64_32S	.rodata.small_cnt_tab
  d3:	48 8d 88 00 00 00 00 	lea    0x0(%rax),%rcx
			d6: R_X86_64_32S	.rodata.small_cnt_tab
  da:	8d 04 9d 00 00 00 00 	lea    0x0(,%rbx,4),%eax
  e1:	48 98                	cltq
  e3:	48 39 c2             	cmp    %rax,%rdx
  e6:	0f 83 45 02 00 00    	jae    331 <alloc_slot+0x331>
  ec:	0f b6 59 01          	movzbl 0x1(%rcx),%ebx
  f0:	8d 04 9d 00 00 00 00 	lea    0x0(,%rbx,4),%eax
  f7:	48 98                	cltq
  f9:	48 39 c2             	cmp    %rax,%rdx
  fc:	0f 83 2f 02 00 00    	jae    331 <alloc_slot+0x331>
 102:	0f b6 59 02          	movzbl 0x2(%rcx),%ebx
 106:	e9 26 02 00 00       	jmp    331 <alloc_slot+0x331>
 10b:	48 8b 4a 08          	mov    0x8(%rdx),%rcx
 10f:	48 89 0c c5 00 00 00 	mov    %rcx,0x0(,%rax,8)
 116:	00 
			113: R_X86_64_32S	__malloc_context
 117:	e9 4a ff ff ff       	jmp    66 <alloc_slot+0x66>
 11c:	48 c7 04 c5 00 00 00 	movq   $0x0,0x0(,%rax,8)
 123:	00 00 00 00 00 
			120: R_X86_64_32S	__malloc_context
 128:	e9 39 ff ff ff       	jmp    66 <alloc_slot+0x66>
 12d:	48 89 0c c5 00 00 00 	mov    %rcx,0x0(,%rax,8)
 134:	00 
			131: R_X86_64_32S	__malloc_context
 135:	48 89 ca             	mov    %rcx,%rdx
 138:	0f b6 4a 20          	movzbl 0x20(%rdx),%ecx
 13c:	b8 02 00 00 00       	mov    $0x2,%eax
 141:	8b 72 1c             	mov    0x1c(%rdx),%esi
 144:	d3 e0                	shl    %cl,%eax
 146:	83 e8 01             	sub    $0x1,%eax
 149:	39 c6                	cmp    %eax,%esi
 14b:	0f 84 d3 00 00 00    	je     224 <alloc_slot+0x224>
 151:	4c 8b 42 10          	mov    0x10(%rdx),%r8
 155:	b8 02 00 00 00       	mov    $0x2,%eax
 15a:	41 0f b6 48 08       	movzbl 0x8(%r8),%ecx
 15f:	d3 e0                	shl    %cl,%eax
 161:	41 89 ca             	mov    %ecx,%r10d
 164:	83 e8 01             	sub    $0x1,%eax
 167:	41 83 e2 1f          	and    $0x1f,%r10d
 16b:	85 f0                	test   %esi,%eax
 16d:	75 18                	jne    187 <alloc_slot+0x187>
 16f:	4c 8b 4a 08          	mov    0x8(%rdx),%r9
 173:	4c 39 ca             	cmp    %r9,%rdx
 176:	0f 84 c5 00 00 00    	je     241 <alloc_slot+0x241>
 17c:	4e 89 0c f5 00 00 00 	mov    %r9,0x0(,%r14,8)
 183:	00 
			180: R_X86_64_32S	__malloc_context+0x50
 184:	4c 89 ca             	mov    %r9,%rdx
 187:	8b 42 18             	mov    0x18(%rdx),%eax
 18a:	85 c0                	test   %eax,%eax
 18c:	0f 85 00 00 00 00    	jne    192 <alloc_slot+0x192>
			18e: R_X86_64_PC32	.text.unlikely.alloc_slot-0x4
 192:	48 8b 42 10          	mov    0x10(%rdx),%rax
 196:	41 b9 02 00 00 00    	mov    $0x2,%r9d
 19c:	4c 8d 52 1c          	lea    0x1c(%rdx),%r10
 1a0:	0f b6 48 08          	movzbl 0x8(%rax),%ecx
 1a4:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 1ab <alloc_slot+0x1ab>
			1a7: R_X86_64_PC32	__libc-0x1
 1ab:	41 d3 e1             	shl    %cl,%r9d
 1ae:	45 8d 41 ff          	lea    -0x1(%r9),%r8d
 1b2:	41 f7 d9             	neg    %r9d
 1b5:	84 c0                	test   %al,%al
 1b7:	0f 85 01 01 00 00    	jne    2be <alloc_slot+0x2be>
 1bd:	8b 4a 1c             	mov    0x1c(%rdx),%ecx
 1c0:	41 21 c9             	and    %ecx,%r9d
 1c3:	44 89 4a 1c          	mov    %r9d,0x1c(%rdx)
 1c7:	44 21 c1             	and    %r8d,%ecx
 1ca:	89 4a 18             	mov    %ecx,0x18(%rdx)
 1cd:	0f 84 00 00 00 00    	je     1d3 <alloc_slot+0x1d3>
			1cf: R_X86_64_PC32	.text.unlikely.alloc_slot-0x4
 1d3:	0f b7 42 20          	movzwl 0x20(%rdx),%eax
 1d7:	66 c1 e8 06          	shr    $0x6,%ax
 1db:	83 e0 3f             	and    $0x3f,%eax
 1de:	83 e8 07             	sub    $0x7,%eax
 1e1:	83 f8 1f             	cmp    $0x1f,%eax
 1e4:	77 18                	ja     1fe <alloc_slot+0x1fe>
 1e6:	48 98                	cltq
 1e8:	0f b6 b0 00 00 00 00 	movzbl 0x0(%rax),%esi
			1eb: R_X86_64_32S	__malloc_context+0x398
 1ef:	40 84 f6             	test   %sil,%sil
 1f2:	74 0a                	je     1fe <alloc_slot+0x1fe>
 1f4:	83 ee 01             	sub    $0x1,%esi
 1f7:	40 88 b0 00 00 00 00 	mov    %sil,0x0(%rax)
			1fa: R_X86_64_32S	__malloc_context+0x398
 1fe:	89 c8                	mov    %ecx,%eax
 200:	f7 d8                	neg    %eax
 202:	21 c8                	and    %ecx,%eax
 204:	29 c1                	sub    %eax,%ecx
 206:	89 4a 18             	mov    %ecx,0x18(%rdx)
 209:	85 c0                	test   %eax,%eax
 20b:	0f 84 6d fe ff ff    	je     7e <alloc_slot+0x7e>
 211:	f3 0f bc c0          	tzcnt  %eax,%eax
 215:	48 83 c4 28          	add    $0x28,%rsp
 219:	5b                   	pop    %rbx
 21a:	5d                   	pop    %rbp
 21b:	41 5c                	pop    %r12
 21d:	41 5d                	pop    %r13
 21f:	41 5e                	pop    %r14
 221:	41 5f                	pop    %r15
 223:	c3                   	ret
 224:	83 e1 20             	and    $0x20,%ecx
 227:	0f 84 5a ff ff ff    	je     187 <alloc_slot+0x187>
 22d:	48 8b 52 08          	mov    0x8(%rdx),%rdx
 231:	4a 89 14 f5 00 00 00 	mov    %rdx,0x0(,%r14,8)
 238:	00 
			235: R_X86_64_32S	__malloc_context+0x50
 239:	8b 72 1c             	mov    0x1c(%rdx),%esi
 23c:	e9 10 ff ff ff       	jmp    151 <alloc_slot+0x151>
 241:	41 0f b7 41 20       	movzwl 0x20(%r9),%eax
 246:	41 8d 4a 02          	lea    0x2(%r10),%ecx
 24a:	89 ca                	mov    %ecx,%edx
 24c:	66 c1 e8 06          	shr    $0x6,%ax
 250:	83 e0 3f             	and    $0x3f,%eax
 253:	44 0f b7 94 00 00 00 	movzwl 0x0(%rax,%rax,1),%r10d
 25a:	00 00 
			258: R_X86_64_32S	__malloc_size_classes
 25c:	41 c1 e2 04          	shl    $0x4,%r10d
 260:	41 0f af d2          	imul   %r10d,%edx
 264:	83 c2 10             	add    $0x10,%edx
 267:	eb 1c                	jmp    285 <alloc_slot+0x285>
 269:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
 270:	00 00 00 00 
 274:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
 27b:	00 00 00 00 
 27f:	90                   	nop
 280:	83 c1 01             	add    $0x1,%ecx
 283:	89 f2                	mov    %esi,%edx
 285:	41 8d 34 12          	lea    (%r10,%rdx,1),%esi
 289:	8d 46 ff             	lea    -0x1(%rsi),%eax
 28c:	31 d0                	xor    %edx,%eax
 28e:	3d ff 0f 00 00       	cmp    $0xfff,%eax
 293:	7e eb                	jle    280 <alloc_slot+0x280>
 295:	41 0f b6 41 20       	movzbl 0x20(%r9),%eax
 29a:	41 0f b6 50 08       	movzbl 0x8(%r8),%edx
 29f:	83 e0 1f             	and    $0x1f,%eax
 2a2:	83 c0 01             	add    $0x1,%eax
 2a5:	39 c8                	cmp    %ecx,%eax
 2a7:	0f 4f c1             	cmovg  %ecx,%eax
 2aa:	83 e2 e0             	and    $0xffffffe0,%edx
 2ad:	83 e8 01             	sub    $0x1,%eax
 2b0:	83 e0 1f             	and    $0x1f,%eax
 2b3:	09 d0                	or     %edx,%eax
 2b5:	41 88 40 08          	mov    %al,0x8(%r8)
 2b9:	e9 c6 fe ff ff       	jmp    184 <alloc_slot+0x184>
 2be:	8b 4a 1c             	mov    0x1c(%rdx),%ecx
 2c1:	89 ce                	mov    %ecx,%esi
 2c3:	89 c8                	mov    %ecx,%eax
 2c5:	44 21 ce             	and    %r9d,%esi
 2c8:	f0 41 0f b1 32       	lock cmpxchg %esi,(%r10)
 2cd:	39 c1                	cmp    %eax,%ecx
 2cf:	75 ed                	jne    2be <alloc_slot+0x2be>
 2d1:	e9 f1 fe ff ff       	jmp    1c7 <alloc_slot+0x1c7>
 2d6:	44 89 e0             	mov    %r12d,%eax
 2d9:	83 e0 03             	and    $0x3,%eax
 2dc:	0f b6 98 00 00 00 00 	movzbl 0x0(%rax),%ebx
			2df: R_X86_64_32S	.rodata.med_cnt_tab
 2e3:	eb 1d                	jmp    302 <alloc_slot+0x302>
 2e5:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
 2ec:	00 00 00 00 
 2f0:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
 2f7:	00 00 00 00 
 2fb:	0f 1f 44 00 00       	nopl   0x0(%rax,%rax,1)
 300:	d1 fb                	sar    $1,%ebx
 302:	f6 c3 01             	test   $0x1,%bl
 305:	75 1b                	jne    322 <alloc_slot+0x322>
 307:	8d 04 9d 00 00 00 00 	lea    0x0(,%rbx,4),%eax
 30e:	48 98                	cltq
 310:	48 39 c2             	cmp    %rax,%rdx
 313:	72 eb                	jb     300 <alloc_slot+0x300>
 315:	eb 0b                	jmp    322 <alloc_slot+0x322>
 317:	66 0f 1f 84 00 00 00 	nopw   0x0(%rax,%rax,1)
 31e:	00 00 
 320:	d1 fb                	sar    $1,%ebx
 322:	48 63 c3             	movslq %ebx,%rax
 325:	49 0f af c5          	imul   %r13,%rax
 329:	48 3d ff ff 0f 00    	cmp    $0xfffff,%rax
 32f:	77 ef                	ja     320 <alloc_slot+0x320>
 331:	4c 63 fb             	movslq %ebx,%r15
 334:	83 fb 01             	cmp    $0x1,%ebx
 337:	74 59                	je     392 <alloc_slot+0x392>
 339:	4c 89 e9             	mov    %r13,%rcx
 33c:	49 0f af cf          	imul   %r15,%rcx
 340:	48 8d 41 10          	lea    0x10(%rcx),%rax
 344:	48 3d 00 08 00 00    	cmp    $0x800,%rax
 34a:	0f 86 7e 03 00 00    	jbe    6ce <alloc_slot+0x6ce>
 350:	44 8d 04 9d 00 00 00 	lea    0x0(,%rbx,4),%r8d
 357:	00 
 358:	4d 63 c0             	movslq %r8d,%r8
 35b:	41 8d 44 24 f9       	lea    -0x7(%r12),%eax
 360:	44 0f b6 0d 00 00 00 	movzbl 0x0(%rip),%r9d        # 368 <alloc_slot+0x368>
 367:	00 
			364: R_X86_64_PC32	__malloc_context+0x3b4
 368:	83 f8 1f             	cmp    $0x1f,%eax
 36b:	77 71                	ja     3de <alloc_slot+0x3de>
 36d:	48 98                	cltq
 36f:	0f b6 b0 00 00 00 00 	movzbl 0x0(%rax),%esi
			372: R_X86_64_32S	__malloc_context+0x378
 376:	44 0f b6 90 00 00 00 	movzbl 0x0(%rax),%r10d
 37d:	00 
			37a: R_X86_64_32S	__malloc_context+0x398
 37e:	85 f6                	test   %esi,%esi
 380:	75 34                	jne    3b6 <alloc_slot+0x3b6>
 382:	31 f6                	xor    %esi,%esi
 384:	41 80 fa 63          	cmp    $0x63,%r10b
 388:	40 0f 97 c6          	seta   %sil
 38c:	41 0f 96 c2          	setbe  %r10b
 390:	eb 54                	jmp    3e6 <alloc_slot+0x3e6>
 392:	49 8d 45 10          	lea    0x10(%r13),%rax
 396:	48 3d 00 08 00 00    	cmp    $0x800,%rax
 39c:	77 0d                	ja     3ab <alloc_slot+0x3ab>
 39e:	41 bf 02 00 00 00    	mov    $0x2,%r15d
 3a4:	bb 02 00 00 00       	mov    $0x2,%ebx
 3a9:	eb 8e                	jmp    339 <alloc_slot+0x339>
 3ab:	4c 89 e9             	mov    %r13,%rcx
 3ae:	41 b8 04 00 00 00    	mov    $0x4,%r8d
 3b4:	eb a5                	jmp    35b <alloc_slot+0x35b>
 3b6:	45 0f b6 d9          	movzbl %r9b,%r11d
 3ba:	41 29 f3             	sub    %esi,%r11d
 3bd:	41 83 fb 09          	cmp    $0x9,%r11d
 3c1:	7f bf                	jg     382 <alloc_slot+0x382>
 3c3:	41 8d 72 01          	lea    0x1(%r10),%esi
 3c7:	41 80 fa 63          	cmp    $0x63,%r10b
 3cb:	41 bb 96 ff ff ff    	mov    $0xffffff96,%r11d
 3d1:	41 0f 43 f3          	cmovae %r11d,%esi
 3d5:	40 88 b0 00 00 00 00 	mov    %sil,0x0(%rax)
			3d8: R_X86_64_32S	__malloc_context+0x398
 3dc:	eb a4                	jmp    382 <alloc_slot+0x382>
 3de:	41 ba 01 00 00 00    	mov    $0x1,%r10d
 3e4:	31 f6                	xor    %esi,%esi
 3e6:	41 8d 41 01          	lea    0x1(%r9),%eax
 3ea:	41 80 f9 ff          	cmp    $0xff,%r9b
 3ee:	0f 84 bf 01 00 00    	je     5b3 <alloc_slot+0x5b3>
 3f4:	88 05 00 00 00 00    	mov    %al,0x0(%rip)        # 3fa <alloc_slot+0x3fa>
			3f6: R_X86_64_PC32	__malloc_context+0x3b4
 3fa:	41 f6 c4 01          	test   $0x1,%r12b
 3fe:	0f 85 10 02 00 00    	jne    614 <alloc_slot+0x614>
 404:	41 83 fc 1f          	cmp    $0x1f,%r12d
 408:	0f 8f cf 01 00 00    	jg     5dd <alloc_slot+0x5dd>
 40e:	41 8d 44 24 01       	lea    0x1(%r12),%eax
 413:	48 98                	cltq
 415:	48 03 14 c5 00 00 00 	add    0x0(,%rax,8),%rdx
 41c:	00 
			419: R_X86_64_32S	__malloc_context+0x1f8
 41d:	4c 39 c2             	cmp    %r8,%rdx
 420:	73 09                	jae    42b <alloc_slot+0x42b>
 422:	45 84 d2             	test   %r10b,%r10b
 425:	0f 85 c0 01 00 00    	jne    5eb <alloc_slot+0x5eb>
 42b:	83 fb 07             	cmp    $0x7,%ebx
 42e:	48 63 cb             	movslq %ebx,%rcx
 431:	41 0f 9e c0          	setle  %r8b
 435:	49 0f af cd          	imul   %r13,%rcx
 439:	48 c7 c0 f0 ff ff ff 	mov    $0xfffffffffffffff0,%rax
 440:	48 29 c8             	sub    %rcx,%rax
 443:	25 ff 0f 00 00       	and    $0xfff,%eax
 448:	4c 8d 7c 01 10       	lea    0x10(%rcx,%rax,1),%r15
 44d:	85 f6                	test   %esi,%esi
 44f:	75 3d                	jne    48e <alloc_slot+0x48e>
 451:	45 84 c0             	test   %r8b,%r8b
 454:	74 38                	je     48e <alloc_slot+0x48e>
 456:	48 c7 c0 ec ff ff ff 	mov    $0xffffffffffffffec,%rax
 45d:	49 8d 4d 10          	lea    0x10(%r13),%rcx
 461:	48 29 f8             	sub    %rdi,%rax
 464:	25 ff 0f 00 00       	and    $0xfff,%eax
 469:	48 8d 44 07 14       	lea    0x14(%rdi,%rax,1),%rax
 46e:	48 39 c8             	cmp    %rcx,%rax
 471:	72 13                	jb     486 <alloc_slot+0x486>
 473:	48 3d ff 3f 00 00    	cmp    $0x3fff,%rax
 479:	76 13                	jbe    48e <alloc_slot+0x48e>
 47b:	8d 0c 1b             	lea    (%rbx,%rbx,1),%ecx
 47e:	48 63 c9             	movslq %ecx,%rcx
 481:	48 39 ca             	cmp    %rcx,%rdx
 484:	73 08                	jae    48e <alloc_slot+0x48e>
 486:	49 89 c7             	mov    %rax,%r15
 489:	bb 01 00 00 00       	mov    $0x1,%ebx
 48e:	4c 89 fe             	mov    %r15,%rsi
 491:	45 31 c9             	xor    %r9d,%r9d
 494:	41 b8 ff ff ff ff    	mov    $0xffffffff,%r8d
 49a:	31 ff                	xor    %edi,%edi
 49c:	b9 22 00 00 00       	mov    $0x22,%ecx
 4a1:	ba 03 00 00 00       	mov    $0x3,%edx
 4a6:	e8 00 00 00 00       	call   4ab <alloc_slot+0x4ab>
			4a7: R_X86_64_PLT32	__mmap-0x4
 4ab:	48 89 c6             	mov    %rax,%rsi
 4ae:	48 83 f8 ff          	cmp    $0xffffffffffffffff,%rax
 4b2:	0f 84 dd 01 00 00    	je     695 <alloc_slot+0x695>
 4b8:	48 8b 45 20          	mov    0x20(%rbp),%rax
 4bc:	49 81 e7 00 f0 ff ff 	and    $0xfffffffffffff000,%r15
 4c3:	31 d2                	xor    %edx,%edx
 4c5:	8d 7b ff             	lea    -0x1(%rbx),%edi
 4c8:	25 ff 0f 00 00       	and    $0xfff,%eax
 4cd:	4c 09 f8             	or     %r15,%rax
 4d0:	4c 63 fb             	movslq %ebx,%r15
 4d3:	48 89 45 20          	mov    %rax,0x20(%rbp)
 4d7:	b8 f0 0f 00 00       	mov    $0xff0,%eax
 4dc:	49 f7 f5             	div    %r13
 4df:	83 05 00 00 00 00 01 	addl   $0x1,0x0(%rip)        # 4e6 <alloc_slot+0x4e6>
			4e1: R_X86_64_PC32	__malloc_context+0x7
 4e6:	83 e8 01             	sub    $0x1,%eax
 4e9:	39 d8                	cmp    %ebx,%eax
 4eb:	0f 4d c7             	cmovge %edi,%eax
 4ee:	31 d2                	xor    %edx,%edx
 4f0:	85 c0                	test   %eax,%eax
 4f2:	0f 49 d0             	cmovns %eax,%edx
 4f5:	b8 02 00 00 00       	mov    $0x2,%eax
 4fa:	89 d1                	mov    %edx,%ecx
 4fc:	4e 01 3c f5 00 00 00 	add    %r15,0x0(,%r14,8)
 503:	00 
			500: R_X86_64_32S	__malloc_context+0x1f8
 504:	41 89 c3             	mov    %eax,%r11d
 507:	48 89 75 10          	mov    %rsi,0x10(%rbp)
 50b:	83 eb 01             	sub    $0x1,%ebx
 50e:	41 83 e4 3f          	and    $0x3f,%r12d
 512:	41 d3 e3             	shl    %cl,%r11d
 515:	83 e3 1f             	and    $0x1f,%ebx
 518:	41 c1 e4 06          	shl    $0x6,%r12d
 51c:	44 89 d9             	mov    %r11d,%ecx
 51f:	83 cb 20             	or     $0x20,%ebx
 522:	83 e9 01             	sub    $0x1,%ecx
 525:	44 09 e3             	or     %r12d,%ebx
 528:	89 4d 18             	mov    %ecx,0x18(%rbp)
 52b:	89 f9                	mov    %edi,%ecx
 52d:	44 8b 45 18          	mov    0x18(%rbp),%r8d
 531:	d3 e0                	shl    %cl,%eax
 533:	44 29 c0             	sub    %r8d,%eax
 536:	83 e8 01             	sub    $0x1,%eax
 539:	89 45 1c             	mov    %eax,0x1c(%rbp)
 53c:	89 d0                	mov    %edx,%eax
 53e:	48 89 2e             	mov    %rbp,(%rsi)
 541:	48 8b 75 10          	mov    0x10(%rbp),%rsi
 545:	83 e0 1f             	and    $0x1f,%eax
 548:	0f b6 4e 08          	movzbl 0x8(%rsi),%ecx
 54c:	83 e1 e0             	and    $0xffffffe0,%ecx
 54f:	09 c8                	or     %ecx,%eax
 551:	88 46 08             	mov    %al,0x8(%rsi)
 554:	0f b7 45 20          	movzwl 0x20(%rbp),%eax
 558:	66 25 00 f0          	and    $0xf000,%ax
 55c:	09 c3                	or     %eax,%ebx
 55e:	8b 45 18             	mov    0x18(%rbp),%eax
 561:	66 89 5d 20          	mov    %bx,0x20(%rbp)
 565:	83 e8 01             	sub    $0x1,%eax
 568:	48 83 7d 08 00       	cmpq   $0x0,0x8(%rbp)
 56d:	89 45 18             	mov    %eax,0x18(%rbp)
 570:	0f 85 00 00 00 00    	jne    576 <alloc_slot+0x576>
			572: R_X86_64_PC32	.text.unlikely.alloc_slot-0x4
 576:	48 83 7d 00 00       	cmpq   $0x0,0x0(%rbp)
 57b:	0f 85 00 00 00 00    	jne    581 <alloc_slot+0x581>
			57d: R_X86_64_PC32	.text.unlikely.alloc_slot-0x4
 581:	49 83 c6 0a          	add    $0xa,%r14
 585:	4a 8b 04 f5 00 00 00 	mov    0x0(,%r14,8),%rax
 58c:	00 
			589: R_X86_64_32S	__malloc_context
 58d:	48 85 c0             	test   %rax,%rax
 590:	0f 84 91 03 00 00    	je     927 <alloc_slot+0x927>
 596:	48 89 45 08          	mov    %rax,0x8(%rbp)
 59a:	48 8b 00             	mov    (%rax),%rax
 59d:	48 89 45 00          	mov    %rax,0x0(%rbp)
 5a1:	48 89 68 08          	mov    %rbp,0x8(%rax)
 5a5:	48 8b 45 08          	mov    0x8(%rbp),%rax
 5a9:	48 89 28             	mov    %rbp,(%rax)
 5ac:	31 c0                	xor    %eax,%eax
 5ae:	e9 62 fc ff ff       	jmp    215 <alloc_slot+0x215>
 5b3:	b8 00 00 00 00       	mov    $0x0,%eax
			5b4: R_X86_64_32	__malloc_context+0x378
 5b8:	eb 11                	jmp    5cb <alloc_slot+0x5cb>
 5ba:	66 0f 1f 44 00 00    	nopw   0x0(%rax,%rax,1)
 5c0:	c6 00 00             	movb   $0x0,(%rax)
 5c3:	48 83 c0 02          	add    $0x2,%rax
 5c7:	c6 40 ff 00          	movb   $0x0,-0x1(%rax)
 5cb:	48 3d 00 00 00 00    	cmp    $0x0,%rax
			5cd: R_X86_64_32S	__malloc_context+0x398
 5d1:	75 ed                	jne    5c0 <alloc_slot+0x5c0>
 5d3:	b8 01 00 00 00       	mov    $0x1,%eax
 5d8:	e9 17 fe ff ff       	jmp    3f4 <alloc_slot+0x3f4>
 5dd:	4c 39 c2             	cmp    %r8,%rdx
 5e0:	0f 82 3c fe ff ff    	jb     422 <alloc_slot+0x422>
 5e6:	e9 40 fe ff ff       	jmp    42b <alloc_slot+0x42b>
 5eb:	44 89 e0             	mov    %r12d,%eax
 5ee:	83 e0 03             	and    $0x3,%eax
 5f1:	83 f8 02             	cmp    $0x2,%eax
 5f4:	74 6f                	je     665 <alloc_slot+0x665>
 5f6:	48 81 f9 00 80 00 00 	cmp    $0x8000,%rcx
 5fd:	76 74                	jbe    673 <alloc_slot+0x673>
 5ff:	41 b8 01 00 00 00    	mov    $0x1,%r8d
 605:	b9 03 00 00 00       	mov    $0x3,%ecx
 60a:	bb 03 00 00 00       	mov    $0x3,%ebx
 60f:	e9 21 fe ff ff       	jmp    435 <alloc_slot+0x435>
 614:	4c 39 c2             	cmp    %r8,%rdx
 617:	0f 83 0e fe ff ff    	jae    42b <alloc_slot+0x42b>
 61d:	45 84 d2             	test   %r10b,%r10b
 620:	0f 84 05 fe ff ff    	je     42b <alloc_slot+0x42b>
 626:	44 89 e0             	mov    %r12d,%eax
 629:	83 e0 03             	and    $0x3,%eax
 62c:	83 f8 01             	cmp    $0x1,%eax
 62f:	0f 85 f6 fd ff ff    	jne    42b <alloc_slot+0x42b>
 635:	48 81 f9 00 80 00 00 	cmp    $0x8000,%rcx
 63c:	0f 86 e9 fd ff ff    	jbe    42b <alloc_slot+0x42b>
 642:	4b 8d 4c 2d 00       	lea    0x0(%r13,%r13,1),%rcx
 647:	48 c7 c0 f0 ff ff ff 	mov    $0xfffffffffffffff0,%rax
 64e:	bb 02 00 00 00       	mov    $0x2,%ebx
 653:	48 29 c8             	sub    %rcx,%rax
 656:	25 ff 0f 00 00       	and    $0xfff,%eax
 65b:	4c 8d 7c 01 10       	lea    0x10(%rcx,%rax,1),%r15
 660:	e9 f1 fd ff ff       	jmp    456 <alloc_slot+0x456>
 665:	48 81 f9 00 40 00 00 	cmp    $0x4000,%rcx
 66c:	77 91                	ja     5ff <alloc_slot+0x5ff>
 66e:	e9 b8 fd ff ff       	jmp    42b <alloc_slot+0x42b>
 673:	48 81 f9 00 20 00 00 	cmp    $0x2000,%rcx
 67a:	0f 86 ab fd ff ff    	jbe    42b <alloc_slot+0x42b>
 680:	41 b8 01 00 00 00    	mov    $0x1,%r8d
 686:	b9 05 00 00 00       	mov    $0x5,%ecx
 68b:	bb 05 00 00 00       	mov    $0x5,%ebx
 690:	e9 a0 fd ff ff       	jmp    435 <alloc_slot+0x435>
 695:	66 0f ef c0          	pxor   %xmm0,%xmm0
 699:	48 c7 45 20 00 00 00 	movq   $0x0,0x20(%rbp)
 6a0:	00 
 6a1:	0f 11 45 00          	movups %xmm0,0x0(%rbp)
 6a5:	0f 11 45 10          	movups %xmm0,0x10(%rbp)
 6a9:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 6b0 <alloc_slot+0x6b0>
			6ac: R_X86_64_PC32	__malloc_context+0xc
 6b0:	48 85 c0             	test   %rax,%rax
 6b3:	0f 85 d2 00 00 00    	jne    78b <alloc_slot+0x78b>
 6b9:	66 0f 6f 1c 24       	movdqa (%rsp),%xmm3
 6be:	0f 11 5d 00          	movups %xmm3,0x0(%rbp)
 6c2:	48 89 2d 00 00 00 00 	mov    %rbp,0x0(%rip)        # 6c9 <alloc_slot+0x6c9>
			6c5: R_X86_64_PC32	__malloc_context+0xc
 6c9:	e9 d3 00 00 00       	jmp    7a1 <alloc_slot+0x7a1>
 6ce:	48 89 c8             	mov    %rcx,%rax
 6d1:	48 8d 71 0c          	lea    0xc(%rcx),%rsi
 6d5:	48 c1 e8 04          	shr    $0x4,%rax
 6d9:	89 c2                	mov    %eax,%edx
 6db:	48 81 f9 90 00 00 00 	cmp    $0x90,%rcx
 6e2:	76 36                	jbe    71a <alloc_slot+0x71a>
 6e4:	48 83 c0 01          	add    $0x1,%rax
 6e8:	0f bd d0             	bsr    %eax,%edx
 6eb:	8d 14 95 fc ff ff ff 	lea    -0x4(,%rdx,4),%edx
 6f2:	8d 4a 01             	lea    0x1(%rdx),%ecx
 6f5:	48 63 c9             	movslq %ecx,%rcx
 6f8:	0f b7 bc 09 00 00 00 	movzwl 0x0(%rcx,%rcx,1),%edi
 6ff:	00 
			6fc: R_X86_64_32S	__malloc_size_classes
 700:	8d 4a 02             	lea    0x2(%rdx),%ecx
 703:	48 39 c7             	cmp    %rax,%rdi
 706:	0f 42 d1             	cmovb  %ecx,%edx
 709:	48 63 ca             	movslq %edx,%rcx
 70c:	0f b7 8c 09 00 00 00 	movzwl 0x0(%rcx,%rcx,1),%ecx
 713:	00 
			710: R_X86_64_32S	__malloc_size_classes
 714:	48 39 c1             	cmp    %rax,%rcx
 717:	83 d2 00             	adc    $0x0,%edx
 71a:	89 d7                	mov    %edx,%edi
 71c:	89 54 24 10          	mov    %edx,0x10(%rsp)
 720:	e8 db f8 ff ff       	call   0 <alloc_slot>
 725:	48 63 54 24 10       	movslq 0x10(%rsp),%rdx
 72a:	83 f8 ff             	cmp    $0xffffffff,%eax
 72d:	74 3c                	je     76b <alloc_slot+0x76b>
 72f:	4c 8b 04 d5 00 00 00 	mov    0x0(,%rdx,8),%r8
 736:	00 
			733: R_X86_64_32S	__malloc_context+0x50
 737:	0f b7 94 12 00 00 00 	movzwl 0x0(%rdx,%rdx,1),%edx
 73e:	00 
			73b: R_X86_64_32S	__malloc_size_classes
 73f:	c1 e2 04             	shl    $0x4,%edx
 742:	44 8d 5a fc          	lea    -0x4(%rdx),%r11d
 746:	49 63 f3             	movslq %r11d,%rsi
 749:	41 f6 40 20 1f       	testb  $0x1f,0x20(%r8)
 74e:	75 6d                	jne    7bd <alloc_slot+0x7bd>
 750:	49 81 78 20 ff 0f 00 	cmpq   $0xfff,0x20(%r8)
 757:	00 
 758:	76 63                	jbe    7bd <alloc_slot+0x7bd>
 75a:	49 8b 48 20          	mov    0x20(%r8),%rcx
 75e:	48 81 e1 00 f0 ff ff 	and    $0xfffffffffffff000,%rcx
 765:	48 83 e9 10          	sub    $0x10,%rcx
 769:	eb 6c                	jmp    7d7 <alloc_slot+0x7d7>
 76b:	66 0f ef c0          	pxor   %xmm0,%xmm0
 76f:	48 c7 45 20 00 00 00 	movq   $0x0,0x20(%rbp)
 776:	00 
 777:	0f 11 45 00          	movups %xmm0,0x0(%rbp)
 77b:	0f 11 45 10          	movups %xmm0,0x10(%rbp)
 77f:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 786 <alloc_slot+0x786>
			782: R_X86_64_PC32	__malloc_context+0xc
 786:	48 85 c0             	test   %rax,%rax
 789:	74 20                	je     7ab <alloc_slot+0x7ab>
 78b:	48 89 45 08          	mov    %rax,0x8(%rbp)
 78f:	48 8b 00             	mov    (%rax),%rax
 792:	48 89 45 00          	mov    %rax,0x0(%rbp)
 796:	48 89 68 08          	mov    %rbp,0x8(%rax)
 79a:	48 8b 45 08          	mov    0x8(%rbp),%rax
 79e:	48 89 28             	mov    %rbp,(%rax)
 7a1:	b8 ff ff ff ff       	mov    $0xffffffff,%eax
 7a6:	e9 6a fa ff ff       	jmp    215 <alloc_slot+0x215>
 7ab:	66 0f 6f 24 24       	movdqa (%rsp),%xmm4
 7b0:	0f 11 65 00          	movups %xmm4,0x0(%rbp)
 7b4:	48 89 2d 00 00 00 00 	mov    %rbp,0x0(%rip)        # 7bb <alloc_slot+0x7bb>
			7b7: R_X86_64_PC32	__malloc_context+0xc
 7bb:	eb e4                	jmp    7a1 <alloc_slot+0x7a1>
 7bd:	41 0f b7 50 20       	movzwl 0x20(%r8),%edx
 7c2:	66 c1 ea 06          	shr    $0x6,%dx
 7c6:	83 e2 3f             	and    $0x3f,%edx
 7c9:	0f b7 8c 12 00 00 00 	movzwl 0x0(%rdx,%rdx,1),%ecx
 7d0:	00 
			7cd: R_X86_64_32S	__malloc_size_classes
 7d1:	c1 e1 04             	shl    $0x4,%ecx
 7d4:	48 63 c9             	movslq %ecx,%rcx
 7d7:	48 89 ca             	mov    %rcx,%rdx
 7da:	48 29 f2             	sub    %rsi,%rdx
 7dd:	48 63 f0             	movslq %eax,%rsi
 7e0:	48 0f af f1          	imul   %rcx,%rsi
 7e4:	4c 8d 4a fc          	lea    -0x4(%rdx),%r9
 7e8:	49 8b 50 10          	mov    0x10(%r8),%rdx
 7ec:	48 83 c2 10          	add    $0x10,%rdx
 7f0:	48 01 d6             	add    %rdx,%rsi
 7f3:	48 8d 7c 0e fc       	lea    -0x4(%rsi,%rcx,1),%rdi
 7f8:	0f b6 4e fc          	movzbl -0x4(%rsi),%ecx
 7fc:	48 89 7c 24 10       	mov    %rdi,0x10(%rsp)
 801:	84 c9                	test   %cl,%cl
 803:	0f 85 00 00 00 00    	jne    809 <alloc_slot+0x809>
			805: R_X86_64_PC32	.text.unlikely.alloc_slot-0x4
 809:	49 83 f9 0f          	cmp    $0xf,%r9
 80d:	0f 86 8e 00 00 00    	jbe    8a1 <alloc_slot+0x8a1>
 813:	80 7e fd 00          	cmpb   $0x0,-0x3(%rsi)
 817:	0f 84 d9 00 00 00    	je     8f6 <alloc_slot+0x8f6>
 81d:	0f b7 7e fe          	movzwl -0x2(%rsi),%edi
 821:	83 c7 01             	add    $0x1,%edi
 824:	40 0f b6 ff          	movzbl %dil,%edi
 828:	4d 89 ca             	mov    %r9,%r10
 82b:	49 c1 ea 04          	shr    $0x4,%r10
 82f:	4c 89 54 24 18       	mov    %r10,0x18(%rsp)
 834:	4c 63 d7             	movslq %edi,%r10
 837:	4c 39 54 24 18       	cmp    %r10,0x18(%rsp)
 83c:	73 42                	jae    880 <alloc_slot+0x880>
 83e:	4c 8b 54 24 18       	mov    0x18(%rsp),%r10
 843:	49 c1 e9 05          	shr    $0x5,%r9
 847:	4d 09 d1             	or     %r10,%r9
 84a:	4d 89 ca             	mov    %r9,%r10
 84d:	49 c1 ea 02          	shr    $0x2,%r10
 851:	4d 09 d1             	or     %r10,%r9
 854:	4d 89 ca             	mov    %r9,%r10
 857:	49 c1 ea 04          	shr    $0x4,%r10
 85b:	4d 09 d1             	or     %r10,%r9
 85e:	4c 8b 54 24 18       	mov    0x18(%rsp),%r10
 863:	44 21 cf             	and    %r9d,%edi
 866:	4c 63 cf             	movslq %edi,%r9
 869:	4d 39 ca             	cmp    %r9,%r10
 86c:	73 12                	jae    880 <alloc_slot+0x880>
 86e:	44 29 d7             	sub    %r10d,%edi
 871:	83 ef 01             	sub    $0x1,%edi
 874:	4c 63 cf             	movslq %edi,%r9
 877:	4d 39 ca             	cmp    %r9,%r10
 87a:	0f 82 00 00 00 00    	jb     880 <alloc_slot+0x880>
			87c: R_X86_64_PC32	.text.unlikely.alloc_slot-0x4
 880:	85 ff                	test   %edi,%edi
 882:	74 1d                	je     8a1 <alloc_slot+0x8a1>
 884:	66 89 7e fe          	mov    %di,-0x2(%rsi)
 888:	c1 e7 04             	shl    $0x4,%edi
 88b:	48 63 d7             	movslq %edi,%rdx
 88e:	c6 46 fd e0          	movb   $0xe0,-0x3(%rsi)
 892:	48 01 d6             	add    %rdx,%rsi
 895:	c6 46 fc 00          	movb   $0x0,-0x4(%rsi)
 899:	49 8b 50 10          	mov    0x10(%r8),%rdx
 89d:	48 83 c2 10          	add    $0x10,%rdx
 8a1:	48 89 f7             	mov    %rsi,%rdi
 8a4:	48 29 d7             	sub    %rdx,%rdi
 8a7:	48 c1 ef 04          	shr    $0x4,%rdi
 8ab:	66 89 7e fe          	mov    %di,-0x2(%rsi)
 8af:	48 8b 7c 24 10       	mov    0x10(%rsp),%rdi
 8b4:	48 89 fa             	mov    %rdi,%rdx
 8b7:	48 29 f2             	sub    %rsi,%rdx
 8ba:	44 29 da             	sub    %r11d,%edx
 8bd:	74 15                	je     8d4 <alloc_slot+0x8d4>
 8bf:	89 d1                	mov    %edx,%ecx
 8c1:	f7 d9                	neg    %ecx
 8c3:	48 63 c9             	movslq %ecx,%rcx
 8c6:	c6 04 0f 00          	movb   $0x0,(%rdi,%rcx,1)
 8ca:	83 fa 04             	cmp    $0x4,%edx
 8cd:	7f 33                	jg     902 <alloc_slot+0x902>
 8cf:	89 d1                	mov    %edx,%ecx
 8d1:	c1 e1 05             	shl    $0x5,%ecx
 8d4:	01 c1                	add    %eax,%ecx
 8d6:	48 8d 56 0c          	lea    0xc(%rsi),%rdx
 8da:	88 4e fd             	mov    %cl,-0x3(%rsi)
 8dd:	48 81 65 20 ff 0f 00 	andq   $0xfff,0x20(%rbp)
 8e4:	00 
 8e5:	0f b6 46 fd          	movzbl -0x3(%rsi),%eax
 8e9:	83 e0 1f             	and    $0x1f,%eax
 8ec:	83 c8 c0             	or     $0xffffffc0,%eax
 8ef:	88 46 fd             	mov    %al,-0x3(%rsi)
 8f2:	31 c0                	xor    %eax,%eax
 8f4:	eb 23                	jmp    919 <alloc_slot+0x919>
 8f6:	0f b6 3d 00 00 00 00 	movzbl 0x0(%rip),%edi        # 8fd <alloc_slot+0x8fd>
			8f9: R_X86_64_PC32	__malloc_context+0x8
 8fd:	e9 26 ff ff ff       	jmp    828 <alloc_slot+0x828>
 902:	89 57 fc             	mov    %edx,-0x4(%rdi)
 905:	b9 a0 ff ff ff       	mov    $0xffffffa0,%ecx
 90a:	c6 47 fb 00          	movb   $0x0,-0x5(%rdi)
 90e:	eb c4                	jmp    8d4 <alloc_slot+0x8d4>
 910:	c6 02 00             	movb   $0x0,(%rdx)
 913:	83 c0 01             	add    $0x1,%eax
 916:	4c 01 ea             	add    %r13,%rdx
 919:	39 c3                	cmp    %eax,%ebx
 91b:	7d f3                	jge    910 <alloc_slot+0x910>
 91d:	8d 53 ff             	lea    -0x1(%rbx),%edx
 920:	89 d7                	mov    %edx,%edi
 922:	e9 ce fb ff ff       	jmp    4f5 <alloc_slot+0x4f5>
 927:	66 0f 6f 14 24       	movdqa (%rsp),%xmm2
 92c:	0f 11 55 00          	movups %xmm2,0x0(%rbp)
 930:	4a 89 2c f5 00 00 00 	mov    %rbp,0x0(,%r14,8)
 937:	00 
			934: R_X86_64_32S	__malloc_context
 938:	e9 6f fc ff ff       	jmp    5ac <alloc_slot+0x5ac>

Disassembly of section .text.unlikely.malloc_slow:

0000000000000000 <malloc_slow.cold>:
   0:	0f 0b                	ud2

Disassembly of section .text.malloc_slow:

0000000000000000 <malloc_slow>:
   0:	48 b8 fe ef ff ff ff 	movabs $0x7fffffffffffeffe,%rax
   7:	ff ff 7f 
   a:	41 56                	push   %r14
   c:	41 55                	push   %r13
   e:	41 54                	push   %r12
  10:	55                   	push   %rbp
  11:	53                   	push   %rbx
  12:	48 39 f8             	cmp    %rdi,%rax
  15:	0f 82 1c 01 00 00    	jb     137 <malloc_slow+0x137>
  1b:	48 89 fb             	mov    %rdi,%rbx
  1e:	48 81 ff eb ff 01 00 	cmp    $0x1ffeb,%rdi
  25:	0f 87 1e 01 00 00    	ja     149 <malloc_slow+0x149>
  2b:	48 8d 57 03          	lea    0x3(%rdi),%rdx
  2f:	48 89 d0             	mov    %rdx,%rax
  32:	48 c1 e8 04          	shr    $0x4,%rax
  36:	4c 63 e8             	movslq %eax,%r13
  39:	4d 89 ec             	mov    %r13,%r12
  3c:	48 81 fa 9f 00 00 00 	cmp    $0x9f,%rdx
  43:	76 43                	jbe    88 <malloc_slow+0x88>
  45:	48 83 c0 01          	add    $0x1,%rax
  49:	0f bd d0             	bsr    %eax,%edx
  4c:	44 8d 24 95 fc ff ff 	lea    -0x4(,%rdx,4),%r12d
  53:	ff 
  54:	41 8d 54 24 01       	lea    0x1(%r12),%edx
  59:	48 63 d2             	movslq %edx,%rdx
  5c:	0f b7 8c 12 00 00 00 	movzwl 0x0(%rdx,%rdx,1),%ecx
  63:	00 
			60: R_X86_64_32S	__malloc_size_classes
  64:	41 8d 54 24 02       	lea    0x2(%r12),%edx
  69:	48 39 c1             	cmp    %rax,%rcx
  6c:	44 0f 42 e2          	cmovb  %edx,%r12d
  70:	4d 63 ec             	movslq %r12d,%r13
  73:	43 0f b7 94 2d 00 00 	movzwl 0x0(%r13,%r13,1),%edx
  7a:	00 00 
			78: R_X86_64_32S	__malloc_size_classes
  7c:	48 39 c2             	cmp    %rax,%rdx
  7f:	73 07                	jae    88 <malloc_slow+0x88>
  81:	41 83 c4 01          	add    $0x1,%r12d
  85:	4d 63 ec             	movslq %r12d,%r13
  88:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 8f <malloc_slow+0x8f>
			8b: R_X86_64_PC32	__libc-0x1
  8f:	84 c0                	test   %al,%al
  91:	0f 85 ac 01 00 00    	jne    243 <malloc_slow+0x243>
  97:	4a 8b 2c ed 00 00 00 	mov    0x0(,%r13,8),%rbp
  9e:	00 
			9b: R_X86_64_32S	__malloc_context+0x50
  9f:	48 85 ed             	test   %rbp,%rbp
  a2:	0f 85 d8 01 00 00    	jne    280 <malloc_slow+0x280>
  a8:	41 83 fc 03          	cmp    $0x3,%r12d
  ac:	0f 8e c5 01 00 00    	jle    277 <malloc_slow+0x277>
  b2:	41 83 fc 1f          	cmp    $0x1f,%r12d
  b6:	7f 4e                	jg     106 <malloc_slow+0x106>
  b8:	41 83 fc 06          	cmp    $0x6,%r12d
  bc:	74 48                	je     106 <malloc_slow+0x106>
  be:	41 f6 c4 01          	test   $0x1,%r12b
  c2:	75 42                	jne    106 <malloc_slow+0x106>
  c4:	4a 83 3c ed 00 00 00 	cmpq   $0x0,0x0(,%r13,8)
  cb:	00 00 
			c8: R_X86_64_32S	__malloc_context+0x1f8
  cd:	75 37                	jne    106 <malloc_slow+0x106>
  cf:	44 89 e1             	mov    %r12d,%ecx
  d2:	83 c9 01             	or     $0x1,%ecx
  d5:	48 63 c1             	movslq %ecx,%rax
  d8:	48 8b 2c c5 00 00 00 	mov    0x0(,%rax,8),%rbp
  df:	00 
			dc: R_X86_64_32S	__malloc_context+0x50
  e0:	48 8b 14 c5 00 00 00 	mov    0x0(,%rax,8),%rdx
  e7:	00 
			e4: R_X86_64_32S	__malloc_context+0x1f8
  e8:	48 85 ed             	test   %rbp,%rbp
  eb:	0f 84 75 01 00 00    	je     266 <malloc_slow+0x266>
  f1:	8b 45 18             	mov    0x18(%rbp),%eax
  f4:	85 c0                	test   %eax,%eax
  f6:	0f 84 56 01 00 00    	je     252 <malloc_slow+0x252>
  fc:	48 83 fa 0c          	cmp    $0xc,%rdx
 100:	0f 86 cf 01 00 00    	jbe    2d5 <malloc_slow+0x2d5>
 106:	48 89 de             	mov    %rbx,%rsi
 109:	44 89 e7             	mov    %r12d,%edi
 10c:	e8 00 00 00 00       	call   111 <malloc_slow+0x111>
			10d: R_X86_64_PC32	.text.alloc_slot-0x4
 111:	41 89 c5             	mov    %eax,%r13d
 114:	83 f8 ff             	cmp    $0xffffffff,%eax
 117:	0f 84 bd 01 00 00    	je     2da <malloc_slow+0x2da>
 11d:	4d 63 e4             	movslq %r12d,%r12
 120:	4c 63 f0             	movslq %eax,%r14
 123:	4a 8b 2c e5 00 00 00 	mov    0x0(,%r12,8),%rbp
 12a:	00 
			127: R_X86_64_32S	__malloc_context+0x50
 12b:	44 8b 25 00 00 00 00 	mov    0x0(%rip),%r12d        # 132 <malloc_slow+0x132>
			12e: R_X86_64_PC32	__malloc_context+0x8
 132:	e9 73 01 00 00       	jmp    2aa <malloc_slow+0x2aa>
 137:	e8 00 00 00 00       	call   13c <malloc_slow+0x13c>
			138: R_X86_64_PLT32	___errno_location-0x4
 13c:	c7 00 0c 00 00 00    	movl   $0xc,(%rax)
 142:	31 c0                	xor    %eax,%eax
 144:	e9 b7 02 00 00       	jmp    400 <malloc_slow+0x400>
 149:	4c 8d 77 14          	lea    0x14(%rdi),%r14
 14d:	4c 8d af 13 10 00 00 	lea    0x1013(%rdi),%r13
 154:	45 31 c9             	xor    %r9d,%r9d
 157:	31 ff                	xor    %edi,%edi
 159:	41 b8 ff ff ff ff    	mov    $0xffffffff,%r8d
 15f:	b9 22 00 00 00       	mov    $0x22,%ecx
 164:	ba 03 00 00 00       	mov    $0x3,%edx
 169:	4c 89 f6             	mov    %r14,%rsi
 16c:	e8 00 00 00 00       	call   171 <malloc_slow+0x171>
			16d: R_X86_64_PLT32	__mmap-0x4
 171:	49 89 c4             	mov    %rax,%r12
 174:	48 83 f8 ff          	cmp    $0xffffffffffffffff,%rax
 178:	74 c8                	je     142 <malloc_slow+0x142>
 17a:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 181 <malloc_slow+0x181>
			17d: R_X86_64_PC32	__libc-0x1
 181:	84 c0                	test   %al,%al
 183:	75 65                	jne    1ea <malloc_slow+0x1ea>
 185:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 18c <malloc_slow+0x18c>
			188: R_X86_64_PC32	__malloc_context+0x3b4
 18c:	8d 50 01             	lea    0x1(%rax),%edx
 18f:	3c ff                	cmp    $0xff,%al
 191:	74 63                	je     1f6 <malloc_slow+0x1f6>
 193:	88 15 00 00 00 00    	mov    %dl,0x0(%rip)        # 199 <malloc_slow+0x199>
			195: R_X86_64_PC32	__malloc_context+0x3b4
 199:	e8 00 00 00 00       	call   19e <malloc_slow+0x19e>
			19a: R_X86_64_PLT32	__malloc_alloc_meta-0x4
 19e:	48 89 c5             	mov    %rax,%rbp
 1a1:	48 85 c0             	test   %rax,%rax
 1a4:	74 77                	je     21d <malloc_slow+0x21d>
 1a6:	49 81 e5 00 f0 ff ff 	and    $0xfffffffffffff000,%r13
 1ad:	4c 89 60 10          	mov    %r12,0x10(%rax)
 1b1:	45 31 f6             	xor    %r14d,%r14d
 1b4:	49 81 cd e0 0f 00 00 	or     $0xfe0,%r13
 1bb:	49 89 04 24          	mov    %rax,(%r12)
 1bf:	4c 89 68 20          	mov    %r13,0x20(%rax)
 1c3:	45 31 ed             	xor    %r13d,%r13d
 1c6:	c7 40 1c 00 00 00 00 	movl   $0x0,0x1c(%rax)
 1cd:	c7 40 18 00 00 00 00 	movl   $0x0,0x18(%rax)
 1d4:	8b 05 00 00 00 00    	mov    0x0(%rip),%eax        # 1da <malloc_slow+0x1da>
			1d6: R_X86_64_PC32	__malloc_context+0x8
 1da:	44 8d 60 01          	lea    0x1(%rax),%r12d
 1de:	44 89 25 00 00 00 00 	mov    %r12d,0x0(%rip)        # 1e5 <malloc_slow+0x1e5>
			1e1: R_X86_64_PC32	__malloc_context+0x8
 1e5:	e9 c0 00 00 00       	jmp    2aa <malloc_slow+0x2aa>
 1ea:	bf 00 00 00 00       	mov    $0x0,%edi
			1eb: R_X86_64_32	__malloc_lock
 1ef:	e8 00 00 00 00       	call   1f4 <malloc_slow+0x1f4>
			1f0: R_X86_64_PLT32	__lock-0x4
 1f4:	eb 8f                	jmp    185 <malloc_slow+0x185>
 1f6:	b8 00 00 00 00       	mov    $0x0,%eax
			1f7: R_X86_64_32	__malloc_context+0x378
 1fb:	eb 0e                	jmp    20b <malloc_slow+0x20b>
 1fd:	0f 1f 00             	nopl   (%rax)
 200:	c6 00 00             	movb   $0x0,(%rax)
 203:	48 83 c0 02          	add    $0x2,%rax
 207:	c6 40 ff 00          	movb   $0x0,-0x1(%rax)
 20b:	48 3d 00 00 00 00    	cmp    $0x0,%rax
			20d: R_X86_64_32S	__malloc_context+0x398
 211:	75 ed                	jne    200 <malloc_slow+0x200>
 213:	ba 01 00 00 00       	mov    $0x1,%edx
 218:	e9 76 ff ff ff       	jmp    193 <malloc_slow+0x193>
 21d:	8b 05 00 00 00 00    	mov    0x0(%rip),%eax        # 223 <malloc_slow+0x223>
			21f: R_X86_64_PC32	__malloc_lock-0x4
 223:	85 c0                	test   %eax,%eax
 225:	78 10                	js     237 <malloc_slow+0x237>
 227:	4c 89 f6             	mov    %r14,%rsi
 22a:	4c 89 e7             	mov    %r12,%rdi
 22d:	e8 00 00 00 00       	call   232 <malloc_slow+0x232>
			22e: R_X86_64_PLT32	munmap-0x4
 232:	e9 0b ff ff ff       	jmp    142 <malloc_slow+0x142>
 237:	bf 00 00 00 00       	mov    $0x0,%edi
			238: R_X86_64_32	__malloc_lock
 23c:	e8 00 00 00 00       	call   241 <malloc_slow+0x241>
			23d: R_X86_64_PLT32	__unlock-0x4
 241:	eb e4                	jmp    227 <malloc_slow+0x227>
 243:	bf 00 00 00 00       	mov    $0x0,%edi
			244: R_X86_64_32	__malloc_lock
 248:	e8 00 00 00 00       	call   24d <malloc_slow+0x24d>
			249: R_X86_64_PLT32	__lock-0x4
 24d:	e9 45 fe ff ff       	jmp    97 <malloc_slow+0x97>
 252:	8b 45 1c             	mov    0x1c(%rbp),%eax
 255:	85 c0                	test   %eax,%eax
 257:	0f 85 9f fe ff ff    	jne    fc <malloc_slow+0xfc>
 25d:	48 83 c2 03          	add    $0x3,%rdx
 261:	e9 96 fe ff ff       	jmp    fc <malloc_slow+0xfc>
 266:	48 83 c2 03          	add    $0x3,%rdx
 26a:	48 83 fa 0c          	cmp    $0xc,%rdx
 26e:	44 0f 46 e1          	cmovbe %ecx,%r12d
 272:	e9 8f fe ff ff       	jmp    106 <malloc_slow+0x106>
 277:	48 85 ed             	test   %rbp,%rbp
 27a:	0f 84 86 fe ff ff    	je     106 <malloc_slow+0x106>
 280:	8b 45 18             	mov    0x18(%rbp),%eax
 283:	41 89 c5             	mov    %eax,%r13d
 286:	41 f7 dd             	neg    %r13d
 289:	41 21 c5             	and    %eax,%r13d
 28c:	0f 84 74 fe ff ff    	je     106 <malloc_slow+0x106>
 292:	44 29 e8             	sub    %r13d,%eax
 295:	45 31 f6             	xor    %r14d,%r14d
 298:	44 8b 25 00 00 00 00 	mov    0x0(%rip),%r12d        # 29f <malloc_slow+0x29f>
			29b: R_X86_64_PC32	__malloc_context+0x8
 29f:	89 45 18             	mov    %eax,0x18(%rbp)
 2a2:	f3 45 0f bc f5       	tzcnt  %r13d,%r14d
 2a7:	4d 89 f5             	mov    %r14,%r13
 2aa:	8b 15 00 00 00 00    	mov    0x0(%rip),%edx        # 2b0 <malloc_slow+0x2b0>
			2ac: R_X86_64_PC32	__malloc_lock-0x4
 2b0:	85 d2                	test   %edx,%edx
 2b2:	78 43                	js     2f7 <malloc_slow+0x2f7>
 2b4:	f6 45 20 1f          	testb  $0x1f,0x20(%rbp)
 2b8:	75 49                	jne    303 <malloc_slow+0x303>
 2ba:	48 81 7d 20 ff 0f 00 	cmpq   $0xfff,0x20(%rbp)
 2c1:	00 
 2c2:	76 3f                	jbe    303 <malloc_slow+0x303>
 2c4:	48 8b 55 20          	mov    0x20(%rbp),%rdx
 2c8:	48 81 e2 00 f0 ff ff 	and    $0xfffffffffffff000,%rdx
 2cf:	48 83 ea 10          	sub    $0x10,%rdx
 2d3:	eb 47                	jmp    31c <malloc_slow+0x31c>
 2d5:	41 89 cc             	mov    %ecx,%r12d
 2d8:	eb a6                	jmp    280 <malloc_slow+0x280>
 2da:	8b 05 00 00 00 00    	mov    0x0(%rip),%eax        # 2e0 <malloc_slow+0x2e0>
			2dc: R_X86_64_PC32	__malloc_lock-0x4
 2e0:	85 c0                	test   %eax,%eax
 2e2:	0f 89 5a fe ff ff    	jns    142 <malloc_slow+0x142>
 2e8:	bf 00 00 00 00       	mov    $0x0,%edi
			2e9: R_X86_64_32	__malloc_lock
 2ed:	e8 00 00 00 00       	call   2f2 <malloc_slow+0x2f2>
			2ee: R_X86_64_PLT32	__unlock-0x4
 2f2:	e9 4b fe ff ff       	jmp    142 <malloc_slow+0x142>
 2f7:	bf 00 00 00 00       	mov    $0x0,%edi
			2f8: R_X86_64_32	__malloc_lock
 2fc:	e8 00 00 00 00       	call   301 <malloc_slow+0x301>
			2fd: R_X86_64_PLT32	__unlock-0x4
 301:	eb b1                	jmp    2b4 <malloc_slow+0x2b4>
 303:	0f b7 55 20          	movzwl 0x20(%rbp),%edx
 307:	66 c1 ea 06          	shr    $0x6,%dx
 30b:	83 e2 3f             	and    $0x3f,%edx
 30e:	0f b7 94 12 00 00 00 	movzwl 0x0(%rdx,%rdx,1),%edx
 315:	00 
			312: R_X86_64_32S	__malloc_size_classes
 316:	c1 e2 04             	shl    $0x4,%edx
 319:	48 63 d2             	movslq %edx,%rdx
 31c:	48 89 d1             	mov    %rdx,%rcx
 31f:	4c 89 f0             	mov    %r14,%rax
 322:	48 29 d9             	sub    %rbx,%rcx
 325:	48 0f af c2          	imul   %rdx,%rax
 329:	48 8d 79 fc          	lea    -0x4(%rcx),%rdi
 32d:	48 8b 4d 10          	mov    0x10(%rbp),%rcx
 331:	48 83 c1 10          	add    $0x10,%rcx
 335:	48 01 c8             	add    %rcx,%rax
 338:	0f b6 70 fc          	movzbl -0x4(%rax),%esi
 33c:	4c 8d 44 10 fc       	lea    -0x4(%rax,%rdx,1),%r8
 341:	40 84 f6             	test   %sil,%sil
 344:	0f 85 00 00 00 00    	jne    34a <malloc_slow+0x34a>
			346: R_X86_64_PC32	.text.unlikely.malloc_slow-0x4
 34a:	48 83 ff 0f          	cmp    $0xf,%rdi
 34e:	76 7b                	jbe    3cb <malloc_slow+0x3cb>
 350:	80 78 fd 00          	cmpb   $0x0,-0x3(%rax)
 354:	41 0f b6 d4          	movzbl %r12b,%edx
 358:	74 0a                	je     364 <malloc_slow+0x364>
 35a:	0f b7 50 fe          	movzwl -0x2(%rax),%edx
 35e:	83 c2 01             	add    $0x1,%edx
 361:	0f b6 d2             	movzbl %dl,%edx
 364:	49 89 fa             	mov    %rdi,%r10
 367:	4c 63 ca             	movslq %edx,%r9
 36a:	49 c1 ea 04          	shr    $0x4,%r10
 36e:	4d 39 ca             	cmp    %r9,%r10
 371:	73 37                	jae    3aa <malloc_slow+0x3aa>
 373:	48 c1 ef 05          	shr    $0x5,%rdi
 377:	4c 09 d7             	or     %r10,%rdi
 37a:	49 89 f9             	mov    %rdi,%r9
 37d:	49 c1 e9 02          	shr    $0x2,%r9
 381:	4c 09 cf             	or     %r9,%rdi
 384:	49 89 f9             	mov    %rdi,%r9
 387:	49 c1 e9 04          	shr    $0x4,%r9
 38b:	4c 09 cf             	or     %r9,%rdi
 38e:	21 fa                	and    %edi,%edx
 390:	48 63 fa             	movslq %edx,%rdi
 393:	49 39 fa             	cmp    %rdi,%r10
 396:	73 12                	jae    3aa <malloc_slow+0x3aa>
 398:	44 29 d2             	sub    %r10d,%edx
 39b:	83 ea 01             	sub    $0x1,%edx
 39e:	48 63 fa             	movslq %edx,%rdi
 3a1:	49 39 fa             	cmp    %rdi,%r10
 3a4:	0f 82 00 00 00 00    	jb     3aa <malloc_slow+0x3aa>
			3a6: R_X86_64_PC32	.text.unlikely.malloc_slow-0x4
 3aa:	85 d2                	test   %edx,%edx
 3ac:	74 1d                	je     3cb <malloc_slow+0x3cb>
 3ae:	66 89 50 fe          	mov    %dx,-0x2(%rax)
 3b2:	c1 e2 04             	shl    $0x4,%edx
 3b5:	48 63 d2             	movslq %edx,%rdx
 3b8:	c6 40 fd e0          	movb   $0xe0,-0x3(%rax)
 3bc:	48 01 d0             	add    %rdx,%rax
 3bf:	c6 40 fc 00          	movb   $0x0,-0x4(%rax)
 3c3:	48 8b 4d 10          	mov    0x10(%rbp),%rcx
 3c7:	48 83 c1 10          	add    $0x10,%rcx
 3cb:	48 89 c2             	mov    %rax,%rdx
 3ce:	48 29 ca             	sub    %rcx,%rdx
 3d1:	48 c1 ea 04          	shr    $0x4,%rdx
 3d5:	66 89 50 fe          	mov    %dx,-0x2(%rax)
 3d9:	4c 89 c2             	mov    %r8,%rdx
 3dc:	48 29 c2             	sub    %rax,%rdx
 3df:	29 da                	sub    %ebx,%edx
 3e1:	74 16                	je     3f9 <malloc_slow+0x3f9>
 3e3:	89 d1                	mov    %edx,%ecx
 3e5:	f7 d9                	neg    %ecx
 3e7:	48 63 c9             	movslq %ecx,%rcx
 3ea:	41 c6 04 08 00       	movb   $0x0,(%r8,%rcx,1)
 3ef:	83 fa 04             	cmp    $0x4,%edx
 3f2:	7f 15                	jg     409 <malloc_slow+0x409>
 3f4:	89 d6                	mov    %edx,%esi
 3f6:	c1 e6 05             	shl    $0x5,%esi
 3f9:	44 01 ee             	add    %r13d,%esi
 3fc:	40 88 70 fd          	mov    %sil,-0x3(%rax)
 400:	5b                   	pop    %rbx
 401:	5d                   	pop    %rbp
 402:	41 5c                	pop    %r12
 404:	41 5d                	pop    %r13
 406:	41 5e                	pop    %r14
 408:	c3                   	ret
 409:	41 89 50 fc          	mov    %edx,-0x4(%r8)
 40d:	be a0 ff ff ff       	mov    $0xffffffa0,%esi
 412:	41 c6 40 fb 00       	movb   $0x0,-0x5(%r8)
 417:	eb e0                	jmp    3f9 <malloc_slow+0x3f9>

Disassembly of section .text.unlikely.__libc_malloc_impl:

0000000000000000 <__libc_malloc_impl.cold>:
   0:	0f 0b                	ud2

Disassembly of section .text.__libc_malloc_impl:

0000000000000000 <__libc_malloc_impl>:
   0:	48 81 ff eb ff 01 00 	cmp    $0x1ffeb,%rdi
   7:	0f 87 82 02 00 00    	ja     28f <__libc_malloc_impl+0x28f>
   d:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 14 <__libc_malloc_impl+0x14>
			10: R_X86_64_PC32	__libc-0x1
  14:	84 c0                	test   %al,%al
  16:	0f 85 73 02 00 00    	jne    28f <__libc_malloc_impl+0x28f>
  1c:	8b 05 00 00 00 00    	mov    0x0(%rip),%eax        # 22 <__libc_malloc_impl+0x22>
			1e: R_X86_64_PC32	__malloc_lock-0x4
  22:	85 c0                	test   %eax,%eax
  24:	0f 85 65 02 00 00    	jne    28f <__libc_malloc_impl+0x28f>
  2a:	48 8d 47 03          	lea    0x3(%rdi),%rax
  2e:	48 89 c2             	mov    %rax,%rdx
  31:	48 c1 ea 04          	shr    $0x4,%rdx
  35:	48 63 ca             	movslq %edx,%rcx
  38:	48 3d 9f 00 00 00    	cmp    $0x9f,%rax
  3e:	76 3c                	jbe    7c <__libc_malloc_impl+0x7c>
  40:	48 83 c2 01          	add    $0x1,%rdx
  44:	0f bd c2             	bsr    %edx,%eax
  47:	8d 04 85 fc ff ff ff 	lea    -0x4(,%rax,4),%eax
  4e:	8d 48 01             	lea    0x1(%rax),%ecx
  51:	48 63 c9             	movslq %ecx,%rcx
  54:	0f b7 b4 09 00 00 00 	movzwl 0x0(%rcx,%rcx,1),%esi
  5b:	00 
			58: R_X86_64_32S	__malloc_size_classes
  5c:	8d 48 02             	lea    0x2(%rax),%ecx
  5f:	48 39 d6             	cmp    %rdx,%rsi
  62:	0f 42 c1             	cmovb  %ecx,%eax
  65:	48 63 c8             	movslq %eax,%rcx
  68:	83 c0 01             	add    $0x1,%eax
  6b:	0f b7 b4 09 00 00 00 	movzwl 0x0(%rcx,%rcx,1),%esi
  72:	00 
			6f: R_X86_64_32S	__malloc_size_classes
  73:	48 98                	cltq
  75:	48 39 d6             	cmp    %rdx,%rsi
  78:	48 0f 42 c8          	cmovb  %rax,%rcx
  7c:	48 8b 14 cd 00 00 00 	mov    0x0(,%rcx,8),%rdx
  83:	00 
			80: R_X86_64_32S	__malloc_context+0x50
  84:	48 85 d2             	test   %rdx,%rdx
  87:	0f 84 02 02 00 00    	je     28f <__libc_malloc_impl+0x28f>
  8d:	55                   	push   %rbp
  8e:	53                   	push   %rbx
  8f:	8b 42 18             	mov    0x18(%rdx),%eax
  92:	85 c0                	test   %eax,%eax
  94:	0f 85 87 00 00 00    	jne    121 <__libc_malloc_impl+0x121>
  9a:	48 39 52 08          	cmp    %rdx,0x8(%rdx)
  9e:	74 07                	je     a7 <__libc_malloc_impl+0xa7>
  a0:	5b                   	pop    %rbx
  a1:	5d                   	pop    %rbp
  a2:	e9 00 00 00 00       	jmp    a7 <__libc_malloc_impl+0xa7>
			a3: R_X86_64_PC32	.text.malloc_slow-0x4
  a7:	48 8b 42 10          	mov    0x10(%rdx),%rax
  ab:	8b 72 1c             	mov    0x1c(%rdx),%esi
  ae:	0f b6 48 08          	movzbl 0x8(%rax),%ecx
  b2:	b8 02 00 00 00       	mov    $0x2,%eax
  b7:	d3 e0                	shl    %cl,%eax
  b9:	8d 48 ff             	lea    -0x1(%rax),%ecx
  bc:	85 ce                	test   %ecx,%esi
  be:	74 e0                	je     a0 <__libc_malloc_impl+0xa0>
  c0:	8b 72 18             	mov    0x18(%rdx),%esi
  c3:	85 f6                	test   %esi,%esi
  c5:	0f 85 00 00 00 00    	jne    cb <__libc_malloc_impl+0xcb>
			c7: R_X86_64_PC32	.text.unlikely.__libc_malloc_impl-0x4
  cb:	0f b6 35 00 00 00 00 	movzbl 0x0(%rip),%esi        # d2 <__libc_malloc_impl+0xd2>
			ce: R_X86_64_PC32	__libc-0x1
  d2:	f7 d8                	neg    %eax
  d4:	4c 8d 52 1c          	lea    0x1c(%rdx),%r10
  d8:	41 89 c1             	mov    %eax,%r9d
  db:	40 84 f6             	test   %sil,%sil
  de:	75 71                	jne    151 <__libc_malloc_impl+0x151>
  e0:	8b 72 1c             	mov    0x1c(%rdx),%esi
  e3:	21 f0                	and    %esi,%eax
  e5:	89 42 1c             	mov    %eax,0x1c(%rdx)
  e8:	89 c8                	mov    %ecx,%eax
  ea:	21 f0                	and    %esi,%eax
  ec:	89 42 18             	mov    %eax,0x18(%rdx)
  ef:	0f 84 00 00 00 00    	je     f5 <__libc_malloc_impl+0xf5>
			f1: R_X86_64_PC32	.text.unlikely.__libc_malloc_impl-0x4
  f5:	0f b7 4a 20          	movzwl 0x20(%rdx),%ecx
  f9:	66 c1 e9 06          	shr    $0x6,%cx
  fd:	83 e1 3f             	and    $0x3f,%ecx
 100:	83 e9 07             	sub    $0x7,%ecx
 103:	83 f9 1f             	cmp    $0x1f,%ecx
 106:	77 19                	ja     121 <__libc_malloc_impl+0x121>
 108:	48 63 c9             	movslq %ecx,%rcx
 10b:	0f b6 b1 00 00 00 00 	movzbl 0x0(%rcx),%esi
			10e: R_X86_64_32S	__malloc_context+0x398
 112:	40 84 f6             	test   %sil,%sil
 115:	74 0a                	je     121 <__libc_malloc_impl+0x121>
 117:	83 ee 01             	sub    $0x1,%esi
 11a:	40 88 b1 00 00 00 00 	mov    %sil,0x0(%rcx)
			11d: R_X86_64_32S	__malloc_context+0x398
 121:	89 c1                	mov    %eax,%ecx
 123:	f7 d9                	neg    %ecx
 125:	21 c1                	and    %eax,%ecx
 127:	29 c8                	sub    %ecx,%eax
 129:	f3 0f bc c9          	tzcnt  %ecx,%ecx
 12d:	89 42 18             	mov    %eax,0x18(%rdx)
 130:	f6 42 20 1f          	testb  $0x1f,0x20(%rdx)
 134:	75 31                	jne    167 <__libc_malloc_impl+0x167>
 136:	48 81 7a 20 ff 0f 00 	cmpq   $0xfff,0x20(%rdx)
 13d:	00 
 13e:	76 27                	jbe    167 <__libc_malloc_impl+0x167>
 140:	48 8b 72 20          	mov    0x20(%rdx),%rsi
 144:	48 81 e6 00 f0 ff ff 	and    $0xfffffffffffff000,%rsi
 14b:	48 83 ee 10          	sub    $0x10,%rsi
 14f:	eb 2f                	jmp    180 <__libc_malloc_impl+0x180>
 151:	8b 72 1c             	mov    0x1c(%rdx),%esi
 154:	41 89 f0             	mov    %esi,%r8d
 157:	89 f0                	mov    %esi,%eax
 159:	45 21 c8             	and    %r9d,%r8d
 15c:	f0 45 0f b1 02       	lock cmpxchg %r8d,(%r10)
 161:	39 c6                	cmp    %eax,%esi
 163:	75 ec                	jne    151 <__libc_malloc_impl+0x151>
 165:	eb 81                	jmp    e8 <__libc_malloc_impl+0xe8>
 167:	0f b7 42 20          	movzwl 0x20(%rdx),%eax
 16b:	66 c1 e8 06          	shr    $0x6,%ax
 16f:	83 e0 3f             	and    $0x3f,%eax
 172:	0f b7 b4 00 00 00 00 	movzwl 0x0(%rax,%rax,1),%esi
 179:	00 
			176: R_X86_64_32S	__malloc_size_classes
 17a:	c1 e6 04             	shl    $0x4,%esi
 17d:	48 63 f6             	movslq %esi,%rsi
 180:	48 89 f0             	mov    %rsi,%rax
 183:	4c 8b 42 10          	mov    0x10(%rdx),%r8
 187:	48 29 f8             	sub    %rdi,%rax
 18a:	4c 8d 48 fc          	lea    -0x4(%rax),%r9
 18e:	48 63 c1             	movslq %ecx,%rax
 191:	49 83 c0 10          	add    $0x10,%r8
 195:	48 0f af c6          	imul   %rsi,%rax
 199:	4c 01 c0             	add    %r8,%rax
 19c:	4c 8d 5c 30 fc       	lea    -0x4(%rax,%rsi,1),%r11
 1a1:	0f b6 70 fc          	movzbl -0x4(%rax),%esi
 1a5:	40 84 f6             	test   %sil,%sil
 1a8:	0f 85 00 00 00 00    	jne    1ae <__libc_malloc_impl+0x1ae>
			1aa: R_X86_64_PC32	.text.unlikely.__libc_malloc_impl-0x4
 1ae:	49 83 f9 0f          	cmp    $0xf,%r9
 1b2:	0f 86 83 00 00 00    	jbe    23b <__libc_malloc_impl+0x23b>
 1b8:	80 78 fd 00          	cmpb   $0x0,-0x3(%rax)
 1bc:	0f 84 b0 00 00 00    	je     272 <__libc_malloc_impl+0x272>
 1c2:	44 0f b7 50 fe       	movzwl -0x2(%rax),%r10d
 1c7:	41 83 c2 01          	add    $0x1,%r10d
 1cb:	45 0f b6 d2          	movzbl %r10b,%r10d
 1cf:	4c 89 cd             	mov    %r9,%rbp
 1d2:	49 63 da             	movslq %r10d,%rbx
 1d5:	48 c1 ed 04          	shr    $0x4,%rbp
 1d9:	48 39 dd             	cmp    %rbx,%rbp
 1dc:	73 39                	jae    217 <__libc_malloc_impl+0x217>
 1de:	49 c1 e9 05          	shr    $0x5,%r9
 1e2:	49 09 e9             	or     %rbp,%r9
 1e5:	4c 89 cb             	mov    %r9,%rbx
 1e8:	48 c1 eb 02          	shr    $0x2,%rbx
 1ec:	49 09 d9             	or     %rbx,%r9
 1ef:	4c 89 cb             	mov    %r9,%rbx
 1f2:	48 c1 eb 04          	shr    $0x4,%rbx
 1f6:	49 09 d9             	or     %rbx,%r9
 1f9:	45 21 ca             	and    %r9d,%r10d
 1fc:	4d 63 ca             	movslq %r10d,%r9
 1ff:	4c 39 cd             	cmp    %r9,%rbp
 202:	73 13                	jae    217 <__libc_malloc_impl+0x217>
 204:	41 29 ea             	sub    %ebp,%r10d
 207:	41 83 ea 01          	sub    $0x1,%r10d
 20b:	4d 63 ca             	movslq %r10d,%r9
 20e:	4c 39 cd             	cmp    %r9,%rbp
 211:	0f 82 00 00 00 00    	jb     217 <__libc_malloc_impl+0x217>
			213: R_X86_64_PC32	.text.unlikely.__libc_malloc_impl-0x4
 217:	45 85 d2             	test   %r10d,%r10d
 21a:	74 1f                	je     23b <__libc_malloc_impl+0x23b>
 21c:	66 44 89 50 fe       	mov    %r10w,-0x2(%rax)
 221:	41 c1 e2 04          	shl    $0x4,%r10d
 225:	4d 63 c2             	movslq %r10d,%r8
 228:	c6 40 fd e0          	movb   $0xe0,-0x3(%rax)
 22c:	4c 01 c0             	add    %r8,%rax
 22f:	c6 40 fc 00          	movb   $0x0,-0x4(%rax)
 233:	4c 8b 42 10          	mov    0x10(%rdx),%r8
 237:	49 83 c0 10          	add    $0x10,%r8
 23b:	48 89 c2             	mov    %rax,%rdx
 23e:	4c 29 c2             	sub    %r8,%rdx
 241:	48 c1 ea 04          	shr    $0x4,%rdx
 245:	66 89 50 fe          	mov    %dx,-0x2(%rax)
 249:	4c 89 da             	mov    %r11,%rdx
 24c:	48 29 c2             	sub    %rax,%rdx
 24f:	29 fa                	sub    %edi,%edx
 251:	74 16                	je     269 <__libc_malloc_impl+0x269>
 253:	89 d6                	mov    %edx,%esi
 255:	f7 de                	neg    %esi
 257:	48 63 f6             	movslq %esi,%rsi
 25a:	41 c6 04 33 00       	movb   $0x0,(%r11,%rsi,1)
 25f:	83 fa 04             	cmp    $0x4,%edx
 262:	7f 1b                	jg     27f <__libc_malloc_impl+0x27f>
 264:	89 d6                	mov    %edx,%esi
 266:	c1 e6 05             	shl    $0x5,%esi
 269:	01 ce                	add    %ecx,%esi
 26b:	40 88 70 fd          	mov    %sil,-0x3(%rax)
 26f:	5b                   	pop    %rbx
 270:	5d                   	pop    %rbp
 271:	c3                   	ret
 272:	44 0f b6 15 00 00 00 	movzbl 0x0(%rip),%r10d        # 27a <__libc_malloc_impl+0x27a>
 279:	00 
			276: R_X86_64_PC32	__malloc_context+0x8
 27a:	e9 50 ff ff ff       	jmp    1cf <__libc_malloc_impl+0x1cf>
 27f:	41 89 53 fc          	mov    %edx,-0x4(%r11)
 283:	be a0 ff ff ff       	mov    $0xffffffa0,%esi
 288:	41 c6 43 fb 00       	movb   $0x0,-0x5(%r11)
 28d:	eb da                	jmp    269 <__libc_malloc_impl+0x269>
 28f:	e9 00 00 00 00       	jmp    294 <__libc_malloc_impl+0x294>
			290: R_X86_64_PC32	.text.malloc_slow-0x4

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
  b3:	7f 4f                	jg     104 <__malloc_allzerop+0x104>
  b5:	0f b7 bc 12 00 00 00 	movzwl 0x0(%rdx,%rdx,1),%edi
  bc:	00 
			b9: R_X86_64_32S	__malloc_size_classes
  bd:	44 89 ca             	mov    %r9d,%edx
  c0:	0f af d7             	imul   %edi,%edx
  c3:	39 d1                	cmp    %edx,%ecx
  c5:	0f 8c 00 00 00 00    	jl     cb <__malloc_allzerop+0xcb>
			c7: R_X86_64_PC32	.text.unlikely.__malloc_allzerop-0x4
  cb:	01 fa                	add    %edi,%edx
  cd:	39 d1                	cmp    %edx,%ecx
  cf:	0f 8d 00 00 00 00    	jge    d5 <__malloc_allzerop+0xd5>
			d1: R_X86_64_PC32	.text.unlikely.__malloc_allzerop-0x4
  d5:	48 8b 50 20          	mov    0x20(%rax),%rdx
  d9:	48 c1 ea 0c          	shr    $0xc,%rdx
  dd:	75 57                	jne    136 <__malloc_allzerop+0x136>
  df:	31 c9                	xor    %ecx,%ecx
  e1:	83 e6 1f             	and    $0x1f,%esi
  e4:	75 4d                	jne    133 <__malloc_allzerop+0x133>
  e6:	48 81 78 20 ff 0f 00 	cmpq   $0xfff,0x20(%rax)
  ed:	00 
  ee:	76 43                	jbe    133 <__malloc_allzerop+0x133>
  f0:	c1 e7 04             	shl    $0x4,%edi
  f3:	48 83 ea 10          	sub    $0x10,%rdx
  f7:	31 c9                	xor    %ecx,%ecx
  f9:	48 63 ff             	movslq %edi,%rdi
  fc:	48 39 fa             	cmp    %rdi,%rdx
  ff:	0f 92 c1             	setb   %cl
 102:	eb 2f                	jmp    133 <__malloc_allzerop+0x133>
 104:	83 fa 3f             	cmp    $0x3f,%edx
 107:	0f 85 00 00 00 00    	jne    10d <__malloc_allzerop+0x10d>
			109: R_X86_64_PC32	.text.unlikely.__malloc_allzerop-0x4
 10d:	40 84 ff             	test   %dil,%dil
 110:	0f 85 00 00 00 00    	jne    116 <__malloc_allzerop+0x116>
			112: R_X86_64_PC32	.text.unlikely.__malloc_allzerop-0x4
 116:	48 81 78 20 ff 0f 00 	cmpq   $0xfff,0x20(%rax)
 11d:	00 
 11e:	0f 86 00 00 00 00    	jbe    124 <__malloc_allzerop+0x124>
			120: R_X86_64_PC32	.text.unlikely.__malloc_allzerop-0x4
 124:	48 8b 40 20          	mov    0x20(%rax),%rax
 128:	48 c1 e8 0c          	shr    $0xc,%rax
 12c:	75 21                	jne    14f <__malloc_allzerop+0x14f>
 12e:	b9 01 00 00 00       	mov    $0x1,%ecx
 133:	89 c8                	mov    %ecx,%eax
 135:	c3                   	ret
 136:	48 c1 e2 0c          	shl    $0xc,%rdx
 13a:	49 89 d0             	mov    %rdx,%r8
 13d:	49 c1 e8 04          	shr    $0x4,%r8
 141:	49 83 e8 01          	sub    $0x1,%r8
 145:	49 39 c8             	cmp    %rcx,%r8
 148:	73 95                	jae    df <__malloc_allzerop+0xdf>
 14a:	e9 00 00 00 00       	jmp    14f <__malloc_allzerop+0x14f>
			14b: R_X86_64_PC32	.text.unlikely.__malloc_allzerop-0x4
 14f:	48 c1 e0 08          	shl    $0x8,%rax
 153:	48 8d 50 ff          	lea    -0x1(%rax),%rdx
 157:	48 63 c1             	movslq %ecx,%rax
 15a:	48 39 c2             	cmp    %rax,%rdx
 15d:	0f 82 00 00 00 00    	jb     163 <__malloc_allzerop+0x163>
			15f: R_X86_64_PC32	.text.unlikely.__malloc_allzerop-0x4
 163:	eb c9                	jmp    12e <__malloc_allzerop+0x12e>


/Users/alex/code/vinix/third_party/useralloc-libc/build/musl/x86_64/2d7970354b905edb5dc4d022050bac166373b2b2d4ea254b78762cc89e0cf019/objects/obj/src/malloc/mallocng/malloc.o:     file format elf64-x86-64


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
  10:	4d 89 f5             	mov    %r14,%r13
  13:	41 54                	push   %r12
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
  2d:	0f 85 cd 01 00 00    	jne    200 <alloc_slot+0x200>
  33:	8b 72 1c             	mov    0x1c(%rdx),%esi
  36:	48 8b 4a 08          	mov    0x8(%rdx),%rcx
  3a:	85 f6                	test   %esi,%esi
  3c:	0f 85 ec 00 00 00    	jne    12e <alloc_slot+0x12e>
  42:	48 39 ca             	cmp    %rcx,%rdx
  45:	0f 84 d2 00 00 00    	je     11d <alloc_slot+0x11d>
  4b:	48 8b 32             	mov    (%rdx),%rsi
  4e:	48 89 4e 08          	mov    %rcx,0x8(%rsi)
  52:	48 8b 32             	mov    (%rdx),%rsi
  55:	48 89 31             	mov    %rsi,(%rcx)
  58:	48 3b 14 c5 00 00 00 	cmp    0x0(,%rax,8),%rdx
  5f:	00 
			5c: R_X86_64_32S	__malloc_context
  60:	0f 84 a6 00 00 00    	je     10c <alloc_slot+0x10c>
  66:	66 0f ef c0          	pxor   %xmm0,%xmm0
  6a:	0f 11 02             	movups %xmm0,(%rdx)
  6d:	4a 8b 14 f5 00 00 00 	mov    0x0(,%r14,8),%rdx
  74:	00 
			71: R_X86_64_32S	__malloc_context+0x50
  75:	48 85 d2             	test   %rdx,%rdx
  78:	0f 85 bb 00 00 00    	jne    139 <alloc_slot+0x139>
  7e:	47 0f b7 a4 36 00 00 	movzwl 0x0(%r14,%r14,1),%r12d
  85:	00 00 
			83: R_X86_64_32S	__malloc_size_classes
  87:	48 89 7c 24 08       	mov    %rdi,0x8(%rsp)
  8c:	e8 00 00 00 00       	call   91 <alloc_slot+0x91>
			8d: R_X86_64_PLT32	__malloc_alloc_meta-0x4
  91:	66 48 0f 6e c8       	movq   %rax,%xmm1
  96:	41 c1 e4 04          	shl    $0x4,%r12d
  9a:	48 89 c5             	mov    %rax,%rbp
  9d:	66 0f 6c c9          	punpcklqdq %xmm1,%xmm1
  a1:	4d 63 e4             	movslq %r12d,%r12
  a4:	0f 29 4c 24 10       	movaps %xmm1,0x10(%rsp)
  a9:	48 85 c0             	test   %rax,%rax
  ac:	0f 84 92 07 00 00    	je     844 <alloc_slot+0x844>
  b2:	41 83 fd 08          	cmp    $0x8,%r13d
  b6:	4a 8b 0c f5 00 00 00 	mov    0x0(,%r14,8),%rcx
  bd:	00 
			ba: R_X86_64_32S	__malloc_context+0x1f8
  be:	48 8b 7c 24 08       	mov    0x8(%rsp),%rdi
  c3:	0f 8f 0d 02 00 00    	jg     2d6 <alloc_slot+0x2d6>
  c9:	4b 8d 04 76          	lea    (%r14,%r14,2),%rax
  cd:	0f b6 98 00 00 00 00 	movzbl 0x0(%rax),%ebx
			d0: R_X86_64_32S	.rodata.small_cnt_tab
  d4:	48 8d 90 00 00 00 00 	lea    0x0(%rax),%rdx
			d7: R_X86_64_32S	.rodata.small_cnt_tab
  db:	8d 04 9d 00 00 00 00 	lea    0x0(,%rbx,4),%eax
  e2:	48 98                	cltq
  e4:	48 39 c1             	cmp    %rax,%rcx
  e7:	0f 83 44 02 00 00    	jae    331 <alloc_slot+0x331>
  ed:	0f b6 5a 01          	movzbl 0x1(%rdx),%ebx
  f1:	8d 04 9d 00 00 00 00 	lea    0x0(,%rbx,4),%eax
  f8:	48 98                	cltq
  fa:	48 39 c1             	cmp    %rax,%rcx
  fd:	0f 83 2e 02 00 00    	jae    331 <alloc_slot+0x331>
 103:	0f b6 5a 02          	movzbl 0x2(%rdx),%ebx
 107:	e9 25 02 00 00       	jmp    331 <alloc_slot+0x331>
 10c:	48 8b 4a 08          	mov    0x8(%rdx),%rcx
 110:	48 89 0c c5 00 00 00 	mov    %rcx,0x0(,%rax,8)
 117:	00 
			114: R_X86_64_32S	__malloc_context
 118:	e9 49 ff ff ff       	jmp    66 <alloc_slot+0x66>
 11d:	48 c7 04 c5 00 00 00 	movq   $0x0,0x0(,%rax,8)
 124:	00 00 00 00 00 
			121: R_X86_64_32S	__malloc_context
 129:	e9 38 ff ff ff       	jmp    66 <alloc_slot+0x66>
 12e:	48 89 0c c5 00 00 00 	mov    %rcx,0x0(,%rax,8)
 135:	00 
			132: R_X86_64_32S	__malloc_context
 136:	48 89 ca             	mov    %rcx,%rdx
 139:	0f b6 4a 20          	movzbl 0x20(%rdx),%ecx
 13d:	b8 02 00 00 00       	mov    $0x2,%eax
 142:	44 8b 4a 1c          	mov    0x1c(%rdx),%r9d
 146:	d3 e0                	shl    %cl,%eax
 148:	83 e8 01             	sub    $0x1,%eax
 14b:	41 39 c1             	cmp    %eax,%r9d
 14e:	0f 84 d2 00 00 00    	je     226 <alloc_slot+0x226>
 154:	4c 8b 42 10          	mov    0x10(%rdx),%r8
 158:	b8 02 00 00 00       	mov    $0x2,%eax
 15d:	41 0f b6 48 08       	movzbl 0x8(%r8),%ecx
 162:	d3 e0                	shl    %cl,%eax
 164:	89 ce                	mov    %ecx,%esi
 166:	83 e8 01             	sub    $0x1,%eax
 169:	83 e6 1f             	and    $0x1f,%esi
 16c:	44 85 c8             	test   %r9d,%eax
 16f:	75 18                	jne    189 <alloc_slot+0x189>
 171:	4c 8b 4a 08          	mov    0x8(%rdx),%r9
 175:	4c 39 ca             	cmp    %r9,%rdx
 178:	0f 84 c6 00 00 00    	je     244 <alloc_slot+0x244>
 17e:	4e 89 0c f5 00 00 00 	mov    %r9,0x0(,%r14,8)
 185:	00 
			182: R_X86_64_32S	__malloc_context+0x50
 186:	4c 89 ca             	mov    %r9,%rdx
 189:	8b 42 18             	mov    0x18(%rdx),%eax
 18c:	85 c0                	test   %eax,%eax
 18e:	0f 85 00 00 00 00    	jne    194 <alloc_slot+0x194>
			190: R_X86_64_PC32	.text.unlikely.alloc_slot-0x4
 194:	48 8b 42 10          	mov    0x10(%rdx),%rax
 198:	41 b9 02 00 00 00    	mov    $0x2,%r9d
 19e:	4c 8d 52 1c          	lea    0x1c(%rdx),%r10
 1a2:	0f b6 48 08          	movzbl 0x8(%rax),%ecx
 1a6:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 1ad <alloc_slot+0x1ad>
			1a9: R_X86_64_PC32	__libc-0x1
 1ad:	41 d3 e1             	shl    %cl,%r9d
 1b0:	45 8d 41 ff          	lea    -0x1(%r9),%r8d
 1b4:	41 f7 d9             	neg    %r9d
 1b7:	84 c0                	test   %al,%al
 1b9:	0f 85 ff 00 00 00    	jne    2be <alloc_slot+0x2be>
 1bf:	8b 4a 1c             	mov    0x1c(%rdx),%ecx
 1c2:	41 21 c9             	and    %ecx,%r9d
 1c5:	44 89 4a 1c          	mov    %r9d,0x1c(%rdx)
 1c9:	44 21 c1             	and    %r8d,%ecx
 1cc:	89 4a 18             	mov    %ecx,0x18(%rdx)
 1cf:	0f 84 00 00 00 00    	je     1d5 <alloc_slot+0x1d5>
			1d1: R_X86_64_PC32	.text.unlikely.alloc_slot-0x4
 1d5:	0f b7 42 20          	movzwl 0x20(%rdx),%eax
 1d9:	66 c1 e8 06          	shr    $0x6,%ax
 1dd:	83 e0 3f             	and    $0x3f,%eax
 1e0:	83 e8 07             	sub    $0x7,%eax
 1e3:	83 f8 1f             	cmp    $0x1f,%eax
 1e6:	77 18                	ja     200 <alloc_slot+0x200>
 1e8:	48 98                	cltq
 1ea:	0f b6 b0 00 00 00 00 	movzbl 0x0(%rax),%esi
			1ed: R_X86_64_32S	__malloc_context+0x398
 1f1:	40 84 f6             	test   %sil,%sil
 1f4:	74 0a                	je     200 <alloc_slot+0x200>
 1f6:	83 ee 01             	sub    $0x1,%esi
 1f9:	40 88 b0 00 00 00 00 	mov    %sil,0x0(%rax)
			1fc: R_X86_64_32S	__malloc_context+0x398
 200:	89 c8                	mov    %ecx,%eax
 202:	f7 d8                	neg    %eax
 204:	21 c8                	and    %ecx,%eax
 206:	29 c1                	sub    %eax,%ecx
 208:	89 4a 18             	mov    %ecx,0x18(%rdx)
 20b:	85 c0                	test   %eax,%eax
 20d:	0f 84 6b fe ff ff    	je     7e <alloc_slot+0x7e>
 213:	f3 0f bc c0          	tzcnt  %eax,%eax
 217:	48 83 c4 28          	add    $0x28,%rsp
 21b:	5b                   	pop    %rbx
 21c:	5d                   	pop    %rbp
 21d:	41 5c                	pop    %r12
 21f:	41 5d                	pop    %r13
 221:	41 5e                	pop    %r14
 223:	41 5f                	pop    %r15
 225:	c3                   	ret
 226:	83 e1 20             	and    $0x20,%ecx
 229:	0f 84 5a ff ff ff    	je     189 <alloc_slot+0x189>
 22f:	48 8b 52 08          	mov    0x8(%rdx),%rdx
 233:	4a 89 14 f5 00 00 00 	mov    %rdx,0x0(,%r14,8)
 23a:	00 
			237: R_X86_64_32S	__malloc_context+0x50
 23b:	44 8b 4a 1c          	mov    0x1c(%rdx),%r9d
 23f:	e9 10 ff ff ff       	jmp    154 <alloc_slot+0x154>
 244:	41 0f b7 41 20       	movzwl 0x20(%r9),%eax
 249:	83 c6 02             	add    $0x2,%esi
 24c:	89 f2                	mov    %esi,%edx
 24e:	66 c1 e8 06          	shr    $0x6,%ax
 252:	83 e0 3f             	and    $0x3f,%eax
 255:	44 0f b7 94 00 00 00 	movzwl 0x0(%rax,%rax,1),%r10d
 25c:	00 00 
			25a: R_X86_64_32S	__malloc_size_classes
 25e:	41 c1 e2 04          	shl    $0x4,%r10d
 262:	41 0f af d2          	imul   %r10d,%edx
 266:	83 c2 10             	add    $0x10,%edx
 269:	eb 1a                	jmp    285 <alloc_slot+0x285>
 26b:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
 272:	00 00 00 00 
 276:	66 2e 0f 1f 84 00 00 	cs nopw 0x0(%rax,%rax,1)
 27d:	00 00 00 
 280:	83 c6 01             	add    $0x1,%esi
 283:	89 ca                	mov    %ecx,%edx
 285:	41 8d 0c 12          	lea    (%r10,%rdx,1),%ecx
 289:	8d 41 ff             	lea    -0x1(%rcx),%eax
 28c:	31 d0                	xor    %edx,%eax
 28e:	3d ff 0f 00 00       	cmp    $0xfff,%eax
 293:	7e eb                	jle    280 <alloc_slot+0x280>
 295:	41 0f b6 41 20       	movzbl 0x20(%r9),%eax
 29a:	41 0f b6 50 08       	movzbl 0x8(%r8),%edx
 29f:	83 e0 1f             	and    $0x1f,%eax
 2a2:	83 c0 01             	add    $0x1,%eax
 2a5:	39 f0                	cmp    %esi,%eax
 2a7:	0f 4f c6             	cmovg  %esi,%eax
 2aa:	83 e2 e0             	and    $0xffffffe0,%edx
 2ad:	83 e8 01             	sub    $0x1,%eax
 2b0:	83 e0 1f             	and    $0x1f,%eax
 2b3:	09 d0                	or     %edx,%eax
 2b5:	41 88 40 08          	mov    %al,0x8(%r8)
 2b9:	e9 c8 fe ff ff       	jmp    186 <alloc_slot+0x186>
 2be:	8b 4a 1c             	mov    0x1c(%rdx),%ecx
 2c1:	89 ce                	mov    %ecx,%esi
 2c3:	89 c8                	mov    %ecx,%eax
 2c5:	44 21 ce             	and    %r9d,%esi
 2c8:	f0 41 0f b1 32       	lock cmpxchg %esi,(%r10)
 2cd:	39 c1                	cmp    %eax,%ecx
 2cf:	75 ed                	jne    2be <alloc_slot+0x2be>
 2d1:	e9 f3 fe ff ff       	jmp    1c9 <alloc_slot+0x1c9>
 2d6:	44 89 e8             	mov    %r13d,%eax
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
 346:	4c 89 e2             	mov    %r12,%rdx
 349:	39 c3                	cmp    %eax,%ebx
 34b:	0f 4c d8             	cmovl  %eax,%ebx
 34e:	4c 63 fb             	movslq %ebx,%r15
 351:	44 8d 04 9d 00 00 00 	lea    0x0(,%rbx,4),%r8d
 358:	00 
 359:	49 0f af d7          	imul   %r15,%rdx
 35d:	4d 63 c0             	movslq %r8d,%r8
 360:	48 8d 42 10          	lea    0x10(%rdx),%rax
 364:	48 3d 00 08 00 00    	cmp    $0x800,%rax
 36a:	0f 86 fe 03 00 00    	jbe    76e <alloc_slot+0x76e>
 370:	41 8d 45 f9          	lea    -0x7(%r13),%eax
 374:	83 f8 1f             	cmp    $0x1f,%eax
 377:	0f 86 cb 02 00 00    	jbe    648 <alloc_slot+0x648>
 37d:	44 0f b6 0d 00 00 00 	movzbl 0x0(%rip),%r9d        # 385 <alloc_slot+0x385>
 384:	00 
			381: R_X86_64_PC32	__malloc_context+0x3b4
 385:	45 31 d2             	xor    %r10d,%r10d
 388:	be 01 00 00 00       	mov    $0x1,%esi
 38d:	eb 59                	jmp    3e8 <alloc_slot+0x3e8>
 38f:	39 c3                	cmp    %eax,%ebx
 391:	0f 4c d8             	cmovl  %eax,%ebx
 394:	4c 63 fb             	movslq %ebx,%r15
 397:	83 fb 01             	cmp    $0x1,%ebx
 39a:	0f 84 15 02 00 00    	je     5b5 <alloc_slot+0x5b5>
 3a0:	4c 89 e2             	mov    %r12,%rdx
 3a3:	49 0f af d7          	imul   %r15,%rdx
 3a7:	48 8d 42 10          	lea    0x10(%rdx),%rax
 3ab:	48 3d 00 08 00 00    	cmp    $0x800,%rax
 3b1:	0f 86 b7 03 00 00    	jbe    76e <alloc_slot+0x76e>
 3b7:	44 8d 04 9d 00 00 00 	lea    0x0(,%rbx,4),%r8d
 3be:	00 
 3bf:	4d 63 c0             	movslq %r8d,%r8
 3c2:	49 81 fc f0 ff 01 00 	cmp    $0x1fff0,%r12
 3c9:	76 a5                	jbe    370 <alloc_slot+0x370>
 3cb:	41 8d 45 f9          	lea    -0x7(%r13),%eax
 3cf:	83 f8 1f             	cmp    $0x1f,%eax
 3d2:	0f 86 08 02 00 00    	jbe    5e0 <alloc_slot+0x5e0>
 3d8:	44 0f b6 0d 00 00 00 	movzbl 0x0(%rip),%r9d        # 3e0 <alloc_slot+0x3e0>
 3df:	00 
			3dc: R_X86_64_PC32	__malloc_context+0x3b4
 3e0:	41 ba 01 00 00 00    	mov    $0x1,%r10d
 3e6:	31 f6                	xor    %esi,%esi
 3e8:	41 8d 41 01          	lea    0x1(%r9),%eax
 3ec:	41 80 f9 ff          	cmp    $0xff,%r9b
 3f0:	0f 84 5c 02 00 00    	je     652 <alloc_slot+0x652>
 3f6:	88 05 00 00 00 00    	mov    %al,0x0(%rip)        # 3fc <alloc_slot+0x3fc>
			3f8: R_X86_64_PC32	__malloc_context+0x3b4
 3fc:	41 f6 c5 01          	test   $0x1,%r13b
 400:	0f 85 ae 02 00 00    	jne    6b4 <alloc_slot+0x6b4>
 406:	41 83 fd 1f          	cmp    $0x1f,%r13d
 40a:	0f 8f 6d 02 00 00    	jg     67d <alloc_slot+0x67d>
 410:	41 8d 45 01          	lea    0x1(%r13),%eax
 414:	48 98                	cltq
 416:	48 03 0c c5 00 00 00 	add    0x0(,%rax,8),%rcx
 41d:	00 
			41a: R_X86_64_32S	__malloc_context+0x1f8
 41e:	4c 39 c1             	cmp    %r8,%rcx
 421:	73 09                	jae    42c <alloc_slot+0x42c>
 423:	45 84 d2             	test   %r10b,%r10b
 426:	0f 85 5f 02 00 00    	jne    68b <alloc_slot+0x68b>
 42c:	83 fb 07             	cmp    $0x7,%ebx
 42f:	48 63 d3             	movslq %ebx,%rdx
 432:	41 0f 9e c0          	setle  %r8b
 436:	49 0f af d4          	imul   %r12,%rdx
 43a:	48 c7 c0 f0 ff ff ff 	mov    $0xfffffffffffffff0,%rax
 441:	48 29 d0             	sub    %rdx,%rax
 444:	25 ff 0f 00 00       	and    $0xfff,%eax
 449:	4c 8d 7c 02 10       	lea    0x10(%rdx,%rax,1),%r15
 44e:	85 f6                	test   %esi,%esi
 450:	75 3e                	jne    490 <alloc_slot+0x490>
 452:	45 84 c0             	test   %r8b,%r8b
 455:	74 39                	je     490 <alloc_slot+0x490>
 457:	48 c7 c0 ec ff ff ff 	mov    $0xffffffffffffffec,%rax
 45e:	49 8d 54 24 10       	lea    0x10(%r12),%rdx
 463:	48 29 f8             	sub    %rdi,%rax
 466:	25 ff 0f 00 00       	and    $0xfff,%eax
 46b:	48 8d 44 07 14       	lea    0x14(%rdi,%rax,1),%rax
 470:	48 39 d0             	cmp    %rdx,%rax
 473:	72 13                	jb     488 <alloc_slot+0x488>
 475:	48 3d ff 3f 00 00    	cmp    $0x3fff,%rax
 47b:	76 13                	jbe    490 <alloc_slot+0x490>
 47d:	8d 14 1b             	lea    (%rbx,%rbx,1),%edx
 480:	48 63 d2             	movslq %edx,%rdx
 483:	48 39 d1             	cmp    %rdx,%rcx
 486:	73 08                	jae    490 <alloc_slot+0x490>
 488:	49 89 c7             	mov    %rax,%r15
 48b:	bb 01 00 00 00       	mov    $0x1,%ebx
 490:	4c 89 fe             	mov    %r15,%rsi
 493:	45 31 c9             	xor    %r9d,%r9d
 496:	41 b8 ff ff ff ff    	mov    $0xffffffff,%r8d
 49c:	31 ff                	xor    %edi,%edi
 49e:	b9 22 00 00 00       	mov    $0x22,%ecx
 4a3:	ba 03 00 00 00       	mov    $0x3,%edx
 4a8:	e8 00 00 00 00       	call   4ad <alloc_slot+0x4ad>
			4a9: R_X86_64_PLT32	__mmap-0x4
 4ad:	48 89 c6             	mov    %rax,%rsi
 4b0:	48 83 f8 ff          	cmp    $0xffffffffffffffff,%rax
 4b4:	0f 84 7a 02 00 00    	je     734 <alloc_slot+0x734>
 4ba:	48 8b 45 20          	mov    0x20(%rbp),%rax
 4be:	49 81 e7 00 f0 ff ff 	and    $0xfffffffffffff000,%r15
 4c5:	31 d2                	xor    %edx,%edx
 4c7:	8d 7b ff             	lea    -0x1(%rbx),%edi
 4ca:	25 ff 0f 00 00       	and    $0xfff,%eax
 4cf:	4c 09 f8             	or     %r15,%rax
 4d2:	4c 63 fb             	movslq %ebx,%r15
 4d5:	48 89 45 20          	mov    %rax,0x20(%rbp)
 4d9:	b8 f0 0f 00 00       	mov    $0xff0,%eax
 4de:	49 f7 f4             	div    %r12
 4e1:	83 05 00 00 00 00 01 	addl   $0x1,0x0(%rip)        # 4e8 <alloc_slot+0x4e8>
			4e3: R_X86_64_PC32	__malloc_context+0x7
 4e8:	83 e8 01             	sub    $0x1,%eax
 4eb:	39 d8                	cmp    %ebx,%eax
 4ed:	0f 4d c7             	cmovge %edi,%eax
 4f0:	31 d2                	xor    %edx,%edx
 4f2:	85 c0                	test   %eax,%eax
 4f4:	0f 49 d0             	cmovns %eax,%edx
 4f7:	b8 02 00 00 00       	mov    $0x2,%eax
 4fc:	89 d1                	mov    %edx,%ecx
 4fe:	4e 01 3c f5 00 00 00 	add    %r15,0x0(,%r14,8)
 505:	00 
			502: R_X86_64_32S	__malloc_context+0x1f8
 506:	41 89 c3             	mov    %eax,%r11d
 509:	48 89 75 10          	mov    %rsi,0x10(%rbp)
 50d:	83 eb 01             	sub    $0x1,%ebx
 510:	41 83 e5 3f          	and    $0x3f,%r13d
 514:	41 d3 e3             	shl    %cl,%r11d
 517:	83 e3 1f             	and    $0x1f,%ebx
 51a:	41 c1 e5 06          	shl    $0x6,%r13d
 51e:	44 89 d9             	mov    %r11d,%ecx
 521:	83 cb 20             	or     $0x20,%ebx
 524:	83 e9 01             	sub    $0x1,%ecx
 527:	44 09 eb             	or     %r13d,%ebx
 52a:	89 4d 18             	mov    %ecx,0x18(%rbp)
 52d:	89 f9                	mov    %edi,%ecx
 52f:	44 8b 45 18          	mov    0x18(%rbp),%r8d
 533:	d3 e0                	shl    %cl,%eax
 535:	44 29 c0             	sub    %r8d,%eax
 538:	83 e8 01             	sub    $0x1,%eax
 53b:	89 45 1c             	mov    %eax,0x1c(%rbp)
 53e:	89 d0                	mov    %edx,%eax
 540:	48 89 2e             	mov    %rbp,(%rsi)
 543:	48 8b 75 10          	mov    0x10(%rbp),%rsi
 547:	83 e0 1f             	and    $0x1f,%eax
 54a:	0f b6 4e 08          	movzbl 0x8(%rsi),%ecx
 54e:	83 e1 e0             	and    $0xffffffe0,%ecx
 551:	09 c8                	or     %ecx,%eax
 553:	88 46 08             	mov    %al,0x8(%rsi)
 556:	0f b7 45 20          	movzwl 0x20(%rbp),%eax
 55a:	66 25 00 f0          	and    $0xf000,%ax
 55e:	09 c3                	or     %eax,%ebx
 560:	8b 45 18             	mov    0x18(%rbp),%eax
 563:	66 89 5d 20          	mov    %bx,0x20(%rbp)
 567:	83 e8 01             	sub    $0x1,%eax
 56a:	48 83 7d 08 00       	cmpq   $0x0,0x8(%rbp)
 56f:	89 45 18             	mov    %eax,0x18(%rbp)
 572:	0f 85 00 00 00 00    	jne    578 <alloc_slot+0x578>
			574: R_X86_64_PC32	.text.unlikely.alloc_slot-0x4
 578:	48 83 7d 00 00       	cmpq   $0x0,0x0(%rbp)
 57d:	0f 85 00 00 00 00    	jne    583 <alloc_slot+0x583>
			57f: R_X86_64_PC32	.text.unlikely.alloc_slot-0x4
 583:	49 83 c6 0a          	add    $0xa,%r14
 587:	4a 8b 04 f5 00 00 00 	mov    0x0(,%r14,8),%rax
 58e:	00 
			58b: R_X86_64_32S	__malloc_context
 58f:	48 85 c0             	test   %rax,%rax
 592:	0f 84 20 04 00 00    	je     9b8 <alloc_slot+0x9b8>
 598:	48 89 45 08          	mov    %rax,0x8(%rbp)
 59c:	48 8b 00             	mov    (%rax),%rax
 59f:	48 89 45 00          	mov    %rax,0x0(%rbp)
 5a3:	48 89 68 08          	mov    %rbp,0x8(%rax)
 5a7:	48 8b 45 08          	mov    0x8(%rbp),%rax
 5ab:	48 89 28             	mov    %rbp,(%rax)
 5ae:	31 c0                	xor    %eax,%eax
 5b0:	e9 62 fc ff ff       	jmp    217 <alloc_slot+0x217>
 5b5:	49 8d 44 24 10       	lea    0x10(%r12),%rax
 5ba:	48 3d 00 08 00 00    	cmp    $0x800,%rax
 5c0:	77 10                	ja     5d2 <alloc_slot+0x5d2>
 5c2:	41 bf 02 00 00 00    	mov    $0x2,%r15d
 5c8:	bb 02 00 00 00       	mov    $0x2,%ebx
 5cd:	e9 ce fd ff ff       	jmp    3a0 <alloc_slot+0x3a0>
 5d2:	4c 89 e2             	mov    %r12,%rdx
 5d5:	41 b8 04 00 00 00    	mov    $0x4,%r8d
 5db:	e9 e2 fd ff ff       	jmp    3c2 <alloc_slot+0x3c2>
 5e0:	48 63 f0             	movslq %eax,%rsi
 5e3:	80 be 00 00 00 00 63 	cmpb   $0x63,0x0(%rsi)
			5e5: R_X86_64_32S	__malloc_context+0x398
 5ea:	40 0f 97 c6          	seta   %sil
 5ee:	41 0f 96 c2          	setbe  %r10b
 5f2:	40 0f b6 f6          	movzbl %sil,%esi
 5f6:	48 98                	cltq
 5f8:	44 0f b6 0d 00 00 00 	movzbl 0x0(%rip),%r9d        # 600 <alloc_slot+0x600>
 5ff:	00 
			5fc: R_X86_64_PC32	__malloc_context+0x3b4
 600:	44 0f b6 98 00 00 00 	movzbl 0x0(%rax),%r11d
 607:	00 
			604: R_X86_64_32S	__malloc_context+0x378
 608:	45 85 db             	test   %r11d,%r11d
 60b:	0f 84 d7 fd ff ff    	je     3e8 <alloc_slot+0x3e8>
 611:	45 0f b6 f9          	movzbl %r9b,%r15d
 615:	45 29 df             	sub    %r11d,%r15d
 618:	41 83 ff 09          	cmp    $0x9,%r15d
 61c:	0f 8f c6 fd ff ff    	jg     3e8 <alloc_slot+0x3e8>
 622:	44 0f b6 b8 00 00 00 	movzbl 0x0(%rax),%r15d
 629:	00 
			626: R_X86_64_32S	__malloc_context+0x398
 62a:	45 8d 5f 01          	lea    0x1(%r15),%r11d
 62e:	41 80 ff 63          	cmp    $0x63,%r15b
 632:	41 bf 96 ff ff ff    	mov    $0xffffff96,%r15d
 638:	45 0f 43 df          	cmovae %r15d,%r11d
 63c:	44 88 98 00 00 00 00 	mov    %r11b,0x0(%rax)
			63f: R_X86_64_32S	__malloc_context+0x398
 643:	e9 a0 fd ff ff       	jmp    3e8 <alloc_slot+0x3e8>
 648:	45 31 d2             	xor    %r10d,%r10d
 64b:	be 01 00 00 00       	mov    $0x1,%esi
 650:	eb a4                	jmp    5f6 <alloc_slot+0x5f6>
 652:	b8 00 00 00 00       	mov    $0x0,%eax
			653: R_X86_64_32	__malloc_context+0x378
 657:	eb 12                	jmp    66b <alloc_slot+0x66b>
 659:	0f 1f 80 00 00 00 00 	nopl   0x0(%rax)
 660:	c6 00 00             	movb   $0x0,(%rax)
 663:	48 83 c0 02          	add    $0x2,%rax
 667:	c6 40 ff 00          	movb   $0x0,-0x1(%rax)
 66b:	48 3d 00 00 00 00    	cmp    $0x0,%rax
			66d: R_X86_64_32S	__malloc_context+0x398
 671:	75 ed                	jne    660 <alloc_slot+0x660>
 673:	b8 01 00 00 00       	mov    $0x1,%eax
 678:	e9 79 fd ff ff       	jmp    3f6 <alloc_slot+0x3f6>
 67d:	4c 39 c1             	cmp    %r8,%rcx
 680:	0f 82 9d fd ff ff    	jb     423 <alloc_slot+0x423>
 686:	e9 a1 fd ff ff       	jmp    42c <alloc_slot+0x42c>
 68b:	44 89 e8             	mov    %r13d,%eax
 68e:	83 e0 03             	and    $0x3,%eax
 691:	83 f8 02             	cmp    $0x2,%eax
 694:	74 6e                	je     704 <alloc_slot+0x704>
 696:	48 81 fa 00 80 00 00 	cmp    $0x8000,%rdx
 69d:	76 73                	jbe    712 <alloc_slot+0x712>
 69f:	41 b8 01 00 00 00    	mov    $0x1,%r8d
 6a5:	ba 03 00 00 00       	mov    $0x3,%edx
 6aa:	bb 03 00 00 00       	mov    $0x3,%ebx
 6af:	e9 82 fd ff ff       	jmp    436 <alloc_slot+0x436>
 6b4:	4c 39 c1             	cmp    %r8,%rcx
 6b7:	0f 83 6f fd ff ff    	jae    42c <alloc_slot+0x42c>
 6bd:	45 84 d2             	test   %r10b,%r10b
 6c0:	0f 84 66 fd ff ff    	je     42c <alloc_slot+0x42c>
 6c6:	44 89 e8             	mov    %r13d,%eax
 6c9:	83 e0 03             	and    $0x3,%eax
 6cc:	83 f8 01             	cmp    $0x1,%eax
 6cf:	0f 85 57 fd ff ff    	jne    42c <alloc_slot+0x42c>
 6d5:	48 81 fa 00 80 00 00 	cmp    $0x8000,%rdx
 6dc:	0f 86 4a fd ff ff    	jbe    42c <alloc_slot+0x42c>
 6e2:	4b 8d 14 24          	lea    (%r12,%r12,1),%rdx
 6e6:	48 c7 c0 f0 ff ff ff 	mov    $0xfffffffffffffff0,%rax
 6ed:	bb 02 00 00 00       	mov    $0x2,%ebx
 6f2:	48 29 d0             	sub    %rdx,%rax
 6f5:	25 ff 0f 00 00       	and    $0xfff,%eax
 6fa:	4c 8d 7c 02 10       	lea    0x10(%rdx,%rax,1),%r15
 6ff:	e9 53 fd ff ff       	jmp    457 <alloc_slot+0x457>
 704:	48 81 fa 00 40 00 00 	cmp    $0x4000,%rdx
 70b:	77 92                	ja     69f <alloc_slot+0x69f>
 70d:	e9 1a fd ff ff       	jmp    42c <alloc_slot+0x42c>
 712:	48 81 fa 00 20 00 00 	cmp    $0x2000,%rdx
 719:	0f 86 0d fd ff ff    	jbe    42c <alloc_slot+0x42c>
 71f:	41 b8 01 00 00 00    	mov    $0x1,%r8d
 725:	ba 05 00 00 00       	mov    $0x5,%edx
 72a:	bb 05 00 00 00       	mov    $0x5,%ebx
 72f:	e9 02 fd ff ff       	jmp    436 <alloc_slot+0x436>
 734:	66 0f ef c0          	pxor   %xmm0,%xmm0
 738:	48 c7 45 20 00 00 00 	movq   $0x0,0x20(%rbp)
 73f:	00 
 740:	0f 11 45 00          	movups %xmm0,0x0(%rbp)
 744:	0f 11 45 10          	movups %xmm0,0x10(%rbp)
 748:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 74f <alloc_slot+0x74f>
			74b: R_X86_64_PC32	__malloc_context+0xc
 74f:	48 85 c0             	test   %rax,%rax
 752:	0f 85 d6 00 00 00    	jne    82e <alloc_slot+0x82e>
 758:	66 0f 6f 5c 24 10    	movdqa 0x10(%rsp),%xmm3
 75e:	0f 11 5d 00          	movups %xmm3,0x0(%rbp)
 762:	48 89 2d 00 00 00 00 	mov    %rbp,0x0(%rip)        # 769 <alloc_slot+0x769>
			765: R_X86_64_PC32	__malloc_context+0xc
 769:	e9 d6 00 00 00       	jmp    844 <alloc_slot+0x844>
 76e:	48 89 d0             	mov    %rdx,%rax
 771:	48 8d 72 0c          	lea    0xc(%rdx),%rsi
 775:	48 c1 e8 04          	shr    $0x4,%rax
 779:	89 c1                	mov    %eax,%ecx
 77b:	48 81 fa 90 00 00 00 	cmp    $0x90,%rdx
 782:	76 36                	jbe    7ba <alloc_slot+0x7ba>
 784:	48 83 c0 01          	add    $0x1,%rax
 788:	0f bd d0             	bsr    %eax,%edx
 78b:	8d 0c 95 fc ff ff ff 	lea    -0x4(,%rdx,4),%ecx
 792:	8d 51 01             	lea    0x1(%rcx),%edx
 795:	48 63 d2             	movslq %edx,%rdx
 798:	0f b7 bc 12 00 00 00 	movzwl 0x0(%rdx,%rdx,1),%edi
 79f:	00 
			79c: R_X86_64_32S	__malloc_size_classes
 7a0:	8d 51 02             	lea    0x2(%rcx),%edx
 7a3:	48 39 c7             	cmp    %rax,%rdi
 7a6:	0f 42 ca             	cmovb  %edx,%ecx
 7a9:	48 63 d1             	movslq %ecx,%rdx
 7ac:	0f b7 94 12 00 00 00 	movzwl 0x0(%rdx,%rdx,1),%edx
 7b3:	00 
			7b0: R_X86_64_32S	__malloc_size_classes
 7b4:	48 39 c2             	cmp    %rax,%rdx
 7b7:	83 d1 00             	adc    $0x0,%ecx
 7ba:	89 cf                	mov    %ecx,%edi
 7bc:	89 4c 24 08          	mov    %ecx,0x8(%rsp)
 7c0:	e8 3b f8 ff ff       	call   0 <alloc_slot>
 7c5:	48 63 4c 24 08       	movslq 0x8(%rsp),%rcx
 7ca:	83 f8 ff             	cmp    $0xffffffff,%eax
 7cd:	89 c2                	mov    %eax,%edx
 7cf:	74 3d                	je     80e <alloc_slot+0x80e>
 7d1:	0f b7 84 09 00 00 00 	movzwl 0x0(%rcx,%rcx,1),%eax
 7d8:	00 
			7d5: R_X86_64_32S	__malloc_size_classes
 7d9:	48 8b 3c cd 00 00 00 	mov    0x0(,%rcx,8),%rdi
 7e0:	00 
			7dd: R_X86_64_32S	__malloc_context+0x50
 7e1:	c1 e0 04             	shl    $0x4,%eax
 7e4:	83 e8 04             	sub    $0x4,%eax
 7e7:	89 44 24 08          	mov    %eax,0x8(%rsp)
 7eb:	48 63 c8             	movslq %eax,%rcx
 7ee:	f6 47 20 1f          	testb  $0x1f,0x20(%rdi)
 7f2:	75 6d                	jne    861 <alloc_slot+0x861>
 7f4:	48 81 7f 20 ff 0f 00 	cmpq   $0xfff,0x20(%rdi)
 7fb:	00 
 7fc:	76 63                	jbe    861 <alloc_slot+0x861>
 7fe:	48 8b 47 20          	mov    0x20(%rdi),%rax
 802:	48 25 00 f0 ff ff    	and    $0xfffffffffffff000,%rax
 808:	48 83 e8 10          	sub    $0x10,%rax
 80c:	eb 6b                	jmp    879 <alloc_slot+0x879>
 80e:	66 0f ef c0          	pxor   %xmm0,%xmm0
 812:	48 c7 45 20 00 00 00 	movq   $0x0,0x20(%rbp)
 819:	00 
 81a:	0f 11 45 00          	movups %xmm0,0x0(%rbp)
 81e:	0f 11 45 10          	movups %xmm0,0x10(%rbp)
 822:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 829 <alloc_slot+0x829>
			825: R_X86_64_PC32	__malloc_context+0xc
 829:	48 85 c0             	test   %rax,%rax
 82c:	74 20                	je     84e <alloc_slot+0x84e>
 82e:	48 89 45 08          	mov    %rax,0x8(%rbp)
 832:	48 8b 00             	mov    (%rax),%rax
 835:	48 89 45 00          	mov    %rax,0x0(%rbp)
 839:	48 89 68 08          	mov    %rbp,0x8(%rax)
 83d:	48 8b 45 08          	mov    0x8(%rbp),%rax
 841:	48 89 28             	mov    %rbp,(%rax)
 844:	b8 ff ff ff ff       	mov    $0xffffffff,%eax
 849:	e9 c9 f9 ff ff       	jmp    217 <alloc_slot+0x217>
 84e:	66 0f 6f 64 24 10    	movdqa 0x10(%rsp),%xmm4
 854:	0f 11 65 00          	movups %xmm4,0x0(%rbp)
 858:	48 89 2d 00 00 00 00 	mov    %rbp,0x0(%rip)        # 85f <alloc_slot+0x85f>
			85b: R_X86_64_PC32	__malloc_context+0xc
 85f:	eb e3                	jmp    844 <alloc_slot+0x844>
 861:	0f b7 47 20          	movzwl 0x20(%rdi),%eax
 865:	66 c1 e8 06          	shr    $0x6,%ax
 869:	83 e0 3f             	and    $0x3f,%eax
 86c:	0f b7 84 00 00 00 00 	movzwl 0x0(%rax,%rax,1),%eax
 873:	00 
			870: R_X86_64_32S	__malloc_size_classes
 874:	c1 e0 04             	shl    $0x4,%eax
 877:	48 98                	cltq
 879:	48 89 c6             	mov    %rax,%rsi
 87c:	48 29 ce             	sub    %rcx,%rsi
 87f:	48 8b 4f 10          	mov    0x10(%rdi),%rcx
 883:	4c 8d 46 fc          	lea    -0x4(%rsi),%r8
 887:	48 63 f2             	movslq %edx,%rsi
 88a:	48 0f af f0          	imul   %rax,%rsi
 88e:	48 83 c1 10          	add    $0x10,%rcx
 892:	4d 89 c1             	mov    %r8,%r9
 895:	49 c1 e9 04          	shr    $0x4,%r9
 899:	48 01 ce             	add    %rcx,%rsi
 89c:	80 7e fd 00          	cmpb   $0x0,-0x3(%rsi)
 8a0:	4c 8d 54 06 fc       	lea    -0x4(%rsi,%rax,1),%r10
 8a5:	0f 84 ec 00 00 00    	je     997 <alloc_slot+0x997>
 8ab:	0f b7 46 fe          	movzwl -0x2(%rsi),%eax
 8af:	83 c0 01             	add    $0x1,%eax
 8b2:	0f b6 c0             	movzbl %al,%eax
 8b5:	80 7e fc 00          	cmpb   $0x0,-0x4(%rsi)
 8b9:	0f 85 00 00 00 00    	jne    8bf <alloc_slot+0x8bf>
			8bb: R_X86_64_PC32	.text.unlikely.alloc_slot-0x4
 8bf:	4c 63 d8             	movslq %eax,%r11
 8c2:	4d 39 d9             	cmp    %r11,%r9
 8c5:	73 38                	jae    8ff <alloc_slot+0x8ff>
 8c7:	49 c1 e8 05          	shr    $0x5,%r8
 8cb:	4d 09 c8             	or     %r9,%r8
 8ce:	4d 89 c3             	mov    %r8,%r11
 8d1:	49 c1 eb 02          	shr    $0x2,%r11
 8d5:	4d 09 d8             	or     %r11,%r8
 8d8:	4d 89 c3             	mov    %r8,%r11
 8db:	49 c1 eb 04          	shr    $0x4,%r11
 8df:	4d 09 d8             	or     %r11,%r8
 8e2:	44 21 c0             	and    %r8d,%eax
 8e5:	4c 63 c0             	movslq %eax,%r8
 8e8:	4d 39 c1             	cmp    %r8,%r9
 8eb:	73 12                	jae    8ff <alloc_slot+0x8ff>
 8ed:	44 29 c8             	sub    %r9d,%eax
 8f0:	83 e8 01             	sub    $0x1,%eax
 8f3:	4c 63 c0             	movslq %eax,%r8
 8f6:	4d 39 c1             	cmp    %r8,%r9
 8f9:	0f 82 00 00 00 00    	jb     8ff <alloc_slot+0x8ff>
			8fb: R_X86_64_PC32	.text.unlikely.alloc_slot-0x4
 8ff:	85 c0                	test   %eax,%eax
 901:	74 1c                	je     91f <alloc_slot+0x91f>
 903:	66 89 46 fe          	mov    %ax,-0x2(%rsi)
 907:	c1 e0 04             	shl    $0x4,%eax
 90a:	48 98                	cltq
 90c:	c6 46 fd e0          	movb   $0xe0,-0x3(%rsi)
 910:	48 01 c6             	add    %rax,%rsi
 913:	c6 46 fc 00          	movb   $0x0,-0x4(%rsi)
 917:	48 8b 4f 10          	mov    0x10(%rdi),%rcx
 91b:	48 83 c1 10          	add    $0x10,%rcx
 91f:	48 89 f0             	mov    %rsi,%rax
 922:	8b 7c 24 08          	mov    0x8(%rsp),%edi
 926:	88 56 fd             	mov    %dl,-0x3(%rsi)
 929:	48 29 c8             	sub    %rcx,%rax
 92c:	89 d1                	mov    %edx,%ecx
 92e:	48 c1 e8 04          	shr    $0x4,%rax
 932:	66 89 46 fe          	mov    %ax,-0x2(%rsi)
 936:	4c 89 d0             	mov    %r10,%rax
 939:	48 29 f0             	sub    %rsi,%rax
 93c:	29 f8                	sub    %edi,%eax
 93e:	74 1d                	je     95d <alloc_slot+0x95d>
 940:	89 c2                	mov    %eax,%edx
 942:	f7 da                	neg    %edx
 944:	48 63 d2             	movslq %edx,%rdx
 947:	41 c6 04 12 00       	movb   $0x0,(%r10,%rdx,1)
 94c:	83 f8 04             	cmp    $0x4,%eax
 94f:	7f 52                	jg     9a3 <alloc_slot+0x9a3>
 951:	0f b6 4e fd          	movzbl -0x3(%rsi),%ecx
 955:	c1 e0 05             	shl    $0x5,%eax
 958:	83 e1 1f             	and    $0x1f,%ecx
 95b:	01 c1                	add    %eax,%ecx
 95d:	88 4e fd             	mov    %cl,-0x3(%rsi)
 960:	48 8d 56 0c          	lea    0xc(%rsi),%rdx
 964:	8d 4b 01             	lea    0x1(%rbx),%ecx
 967:	48 81 65 20 ff 0f 00 	andq   $0xfff,0x20(%rbp)
 96e:	00 
 96f:	0f b6 46 fd          	movzbl -0x3(%rsi),%eax
 973:	83 e0 1f             	and    $0x1f,%eax
 976:	83 c8 c0             	or     $0xffffffc0,%eax
 979:	88 46 fd             	mov    %al,-0x3(%rsi)
 97c:	31 c0                	xor    %eax,%eax
 97e:	66 90                	xchg   %ax,%ax
 980:	83 c0 01             	add    $0x1,%eax
 983:	c6 02 00             	movb   $0x0,(%rdx)
 986:	4c 01 e2             	add    %r12,%rdx
 989:	39 c8                	cmp    %ecx,%eax
 98b:	75 f3                	jne    980 <alloc_slot+0x980>
 98d:	8d 53 ff             	lea    -0x1(%rbx),%edx
 990:	89 d7                	mov    %edx,%edi
 992:	e9 60 fb ff ff       	jmp    4f7 <alloc_slot+0x4f7>
 997:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 99e <alloc_slot+0x99e>
			99a: R_X86_64_PC32	__malloc_context+0x8
 99e:	e9 12 ff ff ff       	jmp    8b5 <alloc_slot+0x8b5>
 9a3:	41 89 42 fc          	mov    %eax,-0x4(%r10)
 9a7:	41 c6 42 fb 00       	movb   $0x0,-0x5(%r10)
 9ac:	0f b6 4e fd          	movzbl -0x3(%rsi),%ecx
 9b0:	83 e1 1f             	and    $0x1f,%ecx
 9b3:	83 e9 60             	sub    $0x60,%ecx
 9b6:	eb a5                	jmp    95d <alloc_slot+0x95d>
 9b8:	66 0f 6f 54 24 10    	movdqa 0x10(%rsp),%xmm2
 9be:	0f 11 55 00          	movups %xmm2,0x0(%rbp)
 9c2:	4a 89 2c f5 00 00 00 	mov    %rbp,0x0(,%r14,8)
 9c9:	00 
			9c6: R_X86_64_32S	__malloc_context
 9ca:	e9 df fb ff ff       	jmp    5ae <alloc_slot+0x5ae>

Disassembly of section .text.unlikely.__libc_malloc_impl:

0000000000000000 <__libc_malloc_impl.cold>:
   0:	0f 0b                	ud2

Disassembly of section .text.__libc_malloc_impl:

0000000000000000 <__libc_malloc_impl>:
   0:	48 b8 fe ef ff ff ff 	movabs $0x7fffffffffffeffe,%rax
   7:	ff ff 7f 
   a:	41 56                	push   %r14
   c:	41 55                	push   %r13
   e:	41 54                	push   %r12
  10:	55                   	push   %rbp
  11:	53                   	push   %rbx
  12:	48 39 f8             	cmp    %rdi,%rax
  15:	0f 82 b6 00 00 00    	jb     d1 <__libc_malloc_impl+0xd1>
  1b:	48 89 fd             	mov    %rdi,%rbp
  1e:	48 81 ff eb ff 01 00 	cmp    $0x1ffeb,%rdi
  25:	0f 87 b8 00 00 00    	ja     e3 <__libc_malloc_impl+0xe3>
  2b:	48 8d 57 03          	lea    0x3(%rdi),%rdx
  2f:	48 89 d0             	mov    %rdx,%rax
  32:	48 c1 e8 04          	shr    $0x4,%rax
  36:	4c 63 e8             	movslq %eax,%r13
  39:	4c 89 eb             	mov    %r13,%rbx
  3c:	48 81 fa 9f 00 00 00 	cmp    $0x9f,%rdx
  43:	76 3c                	jbe    81 <__libc_malloc_impl+0x81>
  45:	48 83 c0 01          	add    $0x1,%rax
  49:	0f bd d0             	bsr    %eax,%edx
  4c:	8d 1c 95 fc ff ff ff 	lea    -0x4(,%rdx,4),%ebx
  53:	8d 53 01             	lea    0x1(%rbx),%edx
  56:	48 63 d2             	movslq %edx,%rdx
  59:	0f b7 8c 12 00 00 00 	movzwl 0x0(%rdx,%rdx,1),%ecx
  60:	00 
			5d: R_X86_64_32S	__malloc_size_classes
  61:	8d 53 02             	lea    0x2(%rbx),%edx
  64:	48 39 c1             	cmp    %rax,%rcx
  67:	0f 42 da             	cmovb  %edx,%ebx
  6a:	4c 63 eb             	movslq %ebx,%r13
  6d:	43 0f b7 94 2d 00 00 	movzwl 0x0(%r13,%r13,1),%edx
  74:	00 00 
			72: R_X86_64_32S	__malloc_size_classes
  76:	48 39 c2             	cmp    %rax,%rdx
  79:	73 06                	jae    81 <__libc_malloc_impl+0x81>
  7b:	83 c3 01             	add    $0x1,%ebx
  7e:	4c 63 eb             	movslq %ebx,%r13
  81:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 88 <__libc_malloc_impl+0x88>
			84: R_X86_64_PC32	__libc-0x1
  88:	84 c0                	test   %al,%al
  8a:	0f 85 73 02 00 00    	jne    303 <__libc_malloc_impl+0x303>
  90:	4e 8b 34 ed 00 00 00 	mov    0x0(,%r13,8),%r14
  97:	00 
			94: R_X86_64_32S	__malloc_context+0x50
  98:	4d 85 f6             	test   %r14,%r14
  9b:	0f 84 71 02 00 00    	je     312 <__libc_malloc_impl+0x312>
  a1:	41 8b 46 18          	mov    0x18(%r14),%eax
  a5:	41 89 c4             	mov    %eax,%r12d
  a8:	41 f7 dc             	neg    %r12d
  ab:	41 21 c4             	and    %eax,%r12d
  ae:	0f 84 5e 02 00 00    	je     312 <__libc_malloc_impl+0x312>
  b4:	45 31 ed             	xor    %r13d,%r13d
  b7:	44 29 e0             	sub    %r12d,%eax
  ba:	8b 1d 00 00 00 00    	mov    0x0(%rip),%ebx        # c0 <__libc_malloc_impl+0xc0>
			bc: R_X86_64_PC32	__malloc_context+0x8
  c0:	f3 45 0f bc ec       	tzcnt  %r12d,%r13d
  c5:	41 89 46 18          	mov    %eax,0x18(%r14)
  c9:	4d 89 ec             	mov    %r13,%r12
  cc:	e9 2b 01 00 00       	jmp    1fc <__libc_malloc_impl+0x1fc>
  d1:	e8 00 00 00 00       	call   d6 <__libc_malloc_impl+0xd6>
			d2: R_X86_64_PLT32	___errno_location-0x4
  d6:	c7 00 0c 00 00 00    	movl   $0xc,(%rax)
  dc:	31 c0                	xor    %eax,%eax
  de:	e9 80 03 00 00       	jmp    463 <__libc_malloc_impl+0x463>
  e3:	4c 8d af 13 10 00 00 	lea    0x1013(%rdi),%r13
  ea:	4c 8d 67 14          	lea    0x14(%rdi),%r12
  ee:	49 c1 ed 0c          	shr    $0xc,%r13
  f2:	49 8d 45 e0          	lea    -0x20(%r13),%rax
  f6:	48 3d e0 01 00 00    	cmp    $0x1e0,%rax
  fc:	77 63                	ja     161 <__libc_malloc_impl+0x161>
  fe:	b8 20 00 00 00       	mov    $0x20,%eax
 103:	31 db                	xor    %ebx,%ebx
 105:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
 10c:	00 00 00 00 
 110:	4c 39 e8             	cmp    %r13,%rax
 113:	73 08                	jae    11d <__libc_malloc_impl+0x11d>
 115:	83 c3 01             	add    $0x1,%ebx
 118:	48 01 c0             	add    %rax,%rax
 11b:	eb f3                	jmp    110 <__libc_malloc_impl+0x110>
 11d:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 124 <__libc_malloc_impl+0x124>
			120: R_X86_64_PC32	__libc-0x1
 124:	84 c0                	test   %al,%al
 126:	0f 85 0b 01 00 00    	jne    237 <__libc_malloc_impl+0x237>
 12c:	48 63 db             	movslq %ebx,%rbx
 12f:	48 83 c3 3a          	add    $0x3a,%rbx
 133:	4c 8b 34 dd 00 00 00 	mov    0x0(,%rbx,8),%r14
 13a:	00 
			137: R_X86_64_32S	__malloc_context
 13b:	4d 85 f6             	test   %r14,%r14
 13e:	74 13                	je     153 <__libc_malloc_impl+0x153>
 140:	49 8b 46 20          	mov    0x20(%r14),%rax
 144:	48 25 00 f0 ff ff    	and    $0xfffffffffffff000,%rax
 14a:	4c 39 e0             	cmp    %r12,%rax
 14d:	0f 83 f3 00 00 00    	jae    246 <__libc_malloc_impl+0x246>
 153:	8b 05 00 00 00 00    	mov    0x0(%rip),%eax        # 159 <__libc_malloc_impl+0x159>
			155: R_X86_64_PC32	__malloc_lock-0x4
 159:	85 c0                	test   %eax,%eax
 15b:	0f 88 39 01 00 00    	js     29a <__libc_malloc_impl+0x29a>
 161:	45 31 c9             	xor    %r9d,%r9d
 164:	41 b8 ff ff ff ff    	mov    $0xffffffff,%r8d
 16a:	b9 22 00 00 00       	mov    $0x22,%ecx
 16f:	31 ff                	xor    %edi,%edi
 171:	ba 03 00 00 00       	mov    $0x3,%edx
 176:	4c 89 e6             	mov    %r12,%rsi
 179:	e8 00 00 00 00       	call   17e <__libc_malloc_impl+0x17e>
			17a: R_X86_64_PLT32	__mmap-0x4
 17e:	48 89 c3             	mov    %rax,%rbx
 181:	48 83 f8 ff          	cmp    $0xffffffffffffffff,%rax
 185:	0f 84 51 ff ff ff    	je     dc <__libc_malloc_impl+0xdc>
 18b:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 192 <__libc_malloc_impl+0x192>
			18e: R_X86_64_PC32	__libc-0x1
 192:	84 c0                	test   %al,%al
 194:	0f 85 0f 01 00 00    	jne    2a9 <__libc_malloc_impl+0x2a9>
 19a:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 1a1 <__libc_malloc_impl+0x1a1>
			19d: R_X86_64_PC32	__malloc_context+0x3b4
 1a1:	8d 50 01             	lea    0x1(%rax),%edx
 1a4:	3c ff                	cmp    $0xff,%al
 1a6:	0f 84 0c 01 00 00    	je     2b8 <__libc_malloc_impl+0x2b8>
 1ac:	88 15 00 00 00 00    	mov    %dl,0x0(%rip)        # 1b2 <__libc_malloc_impl+0x1b2>
			1ae: R_X86_64_PC32	__malloc_context+0x3b4
 1b2:	e8 00 00 00 00       	call   1b7 <__libc_malloc_impl+0x1b7>
			1b3: R_X86_64_PLT32	__malloc_alloc_meta-0x4
 1b7:	49 89 c6             	mov    %rax,%r14
 1ba:	48 85 c0             	test   %rax,%rax
 1bd:	0f 84 1a 01 00 00    	je     2dd <__libc_malloc_impl+0x2dd>
 1c3:	49 c1 e5 0c          	shl    $0xc,%r13
 1c7:	48 89 58 10          	mov    %rbx,0x10(%rax)
 1cb:	49 81 cd e0 0f 00 00 	or     $0xfe0,%r13
 1d2:	48 89 03             	mov    %rax,(%rbx)
 1d5:	c7 40 1c 00 00 00 00 	movl   $0x0,0x1c(%rax)
 1dc:	4c 89 68 20          	mov    %r13,0x20(%rax)
 1e0:	c7 40 18 00 00 00 00 	movl   $0x0,0x18(%rax)
 1e7:	8b 05 00 00 00 00    	mov    0x0(%rip),%eax        # 1ed <__libc_malloc_impl+0x1ed>
			1e9: R_X86_64_PC32	__malloc_context+0x8
 1ed:	45 31 ed             	xor    %r13d,%r13d
 1f0:	45 31 e4             	xor    %r12d,%r12d
 1f3:	8d 58 01             	lea    0x1(%rax),%ebx
 1f6:	89 1d 00 00 00 00    	mov    %ebx,0x0(%rip)        # 1fc <__libc_malloc_impl+0x1fc>
			1f8: R_X86_64_PC32	__malloc_context+0x8
 1fc:	8b 15 00 00 00 00    	mov    0x0(%rip),%edx        # 202 <__libc_malloc_impl+0x202>
			1fe: R_X86_64_PC32	__malloc_lock-0x4
 202:	85 d2                	test   %edx,%edx
 204:	0f 88 4d 01 00 00    	js     357 <__libc_malloc_impl+0x357>
 20a:	41 f6 46 20 1f       	testb  $0x1f,0x20(%r14)
 20f:	0f 85 51 01 00 00    	jne    366 <__libc_malloc_impl+0x366>
 215:	49 81 7e 20 ff 0f 00 	cmpq   $0xfff,0x20(%r14)
 21c:	00 
 21d:	0f 86 43 01 00 00    	jbe    366 <__libc_malloc_impl+0x366>
 223:	49 8b 56 20          	mov    0x20(%r14),%rdx
 227:	48 81 e2 00 f0 ff ff 	and    $0xfffffffffffff000,%rdx
 22e:	48 83 ea 10          	sub    $0x10,%rdx
 232:	e9 49 01 00 00       	jmp    380 <__libc_malloc_impl+0x380>
 237:	bf 00 00 00 00       	mov    $0x0,%edi
			238: R_X86_64_32	__malloc_lock
 23c:	e8 00 00 00 00       	call   241 <__libc_malloc_impl+0x241>
			23d: R_X86_64_PLT32	__lock-0x4
 241:	e9 e6 fe ff ff       	jmp    12c <__libc_malloc_impl+0x12c>
 246:	48 c7 04 dd 00 00 00 	movq   $0x0,0x0(,%rbx,8)
 24d:	00 00 00 00 00 
			24a: R_X86_64_32S	__malloc_context
 252:	41 c7 46 1c 00 00 00 	movl   $0x0,0x1c(%r14)
 259:	00 
 25a:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 261 <__libc_malloc_impl+0x261>
			25d: R_X86_64_PC32	__malloc_context+0x3b4
 261:	8d 50 01             	lea    0x1(%rax),%edx
 264:	3c ff                	cmp    $0xff,%al
 266:	74 0b                	je     273 <__libc_malloc_impl+0x273>
 268:	88 15 00 00 00 00    	mov    %dl,0x0(%rip)        # 26e <__libc_malloc_impl+0x26e>
			26a: R_X86_64_PC32	__malloc_context+0x3b4
 26e:	e9 74 ff ff ff       	jmp    1e7 <__libc_malloc_impl+0x1e7>
 273:	b8 00 00 00 00       	mov    $0x0,%eax
			274: R_X86_64_32	__malloc_context+0x378
 278:	eb 11                	jmp    28b <__libc_malloc_impl+0x28b>
 27a:	66 0f 1f 44 00 00    	nopw   0x0(%rax,%rax,1)
 280:	c6 00 00             	movb   $0x0,(%rax)
 283:	48 83 c0 02          	add    $0x2,%rax
 287:	c6 40 ff 00          	movb   $0x0,-0x1(%rax)
 28b:	48 3d 00 00 00 00    	cmp    $0x0,%rax
			28d: R_X86_64_32S	__malloc_context+0x398
 291:	75 ed                	jne    280 <__libc_malloc_impl+0x280>
 293:	ba 01 00 00 00       	mov    $0x1,%edx
 298:	eb ce                	jmp    268 <__libc_malloc_impl+0x268>
 29a:	bf 00 00 00 00       	mov    $0x0,%edi
			29b: R_X86_64_32	__malloc_lock
 29f:	e8 00 00 00 00       	call   2a4 <__libc_malloc_impl+0x2a4>
			2a0: R_X86_64_PLT32	__unlock-0x4
 2a4:	e9 b8 fe ff ff       	jmp    161 <__libc_malloc_impl+0x161>
 2a9:	bf 00 00 00 00       	mov    $0x0,%edi
			2aa: R_X86_64_32	__malloc_lock
 2ae:	e8 00 00 00 00       	call   2b3 <__libc_malloc_impl+0x2b3>
			2af: R_X86_64_PLT32	__lock-0x4
 2b3:	e9 e2 fe ff ff       	jmp    19a <__libc_malloc_impl+0x19a>
 2b8:	b8 00 00 00 00       	mov    $0x0,%eax
			2b9: R_X86_64_32	__malloc_context+0x378
 2bd:	eb 0c                	jmp    2cb <__libc_malloc_impl+0x2cb>
 2bf:	90                   	nop
 2c0:	c6 00 00             	movb   $0x0,(%rax)
 2c3:	48 83 c0 02          	add    $0x2,%rax
 2c7:	c6 40 ff 00          	movb   $0x0,-0x1(%rax)
 2cb:	48 3d 00 00 00 00    	cmp    $0x0,%rax
			2cd: R_X86_64_32S	__malloc_context+0x398
 2d1:	75 ed                	jne    2c0 <__libc_malloc_impl+0x2c0>
 2d3:	ba 01 00 00 00       	mov    $0x1,%edx
 2d8:	e9 cf fe ff ff       	jmp    1ac <__libc_malloc_impl+0x1ac>
 2dd:	8b 05 00 00 00 00    	mov    0x0(%rip),%eax        # 2e3 <__libc_malloc_impl+0x2e3>
			2df: R_X86_64_PC32	__malloc_lock-0x4
 2e3:	85 c0                	test   %eax,%eax
 2e5:	78 10                	js     2f7 <__libc_malloc_impl+0x2f7>
 2e7:	4c 89 e6             	mov    %r12,%rsi
 2ea:	48 89 df             	mov    %rbx,%rdi
 2ed:	e8 00 00 00 00       	call   2f2 <__libc_malloc_impl+0x2f2>
			2ee: R_X86_64_PLT32	munmap-0x4
 2f2:	e9 e5 fd ff ff       	jmp    dc <__libc_malloc_impl+0xdc>
 2f7:	bf 00 00 00 00       	mov    $0x0,%edi
			2f8: R_X86_64_32	__malloc_lock
 2fc:	e8 00 00 00 00       	call   301 <__libc_malloc_impl+0x301>
			2fd: R_X86_64_PLT32	__unlock-0x4
 301:	eb e4                	jmp    2e7 <__libc_malloc_impl+0x2e7>
 303:	bf 00 00 00 00       	mov    $0x0,%edi
			304: R_X86_64_32	__malloc_lock
 308:	e8 00 00 00 00       	call   30d <__libc_malloc_impl+0x30d>
			309: R_X86_64_PLT32	__lock-0x4
 30d:	e9 7e fd ff ff       	jmp    90 <__libc_malloc_impl+0x90>
 312:	48 89 ee             	mov    %rbp,%rsi
 315:	89 df                	mov    %ebx,%edi
 317:	e8 00 00 00 00       	call   31c <__libc_malloc_impl+0x31c>
			318: R_X86_64_PC32	.text.alloc_slot-0x4
 31c:	41 89 c4             	mov    %eax,%r12d
 31f:	83 f8 ff             	cmp    $0xffffffff,%eax
 322:	74 16                	je     33a <__libc_malloc_impl+0x33a>
 324:	4e 8b 34 ed 00 00 00 	mov    0x0(,%r13,8),%r14
 32b:	00 
			328: R_X86_64_32S	__malloc_context+0x50
 32c:	8b 1d 00 00 00 00    	mov    0x0(%rip),%ebx        # 332 <__libc_malloc_impl+0x332>
			32e: R_X86_64_PC32	__malloc_context+0x8
 332:	4c 63 e8             	movslq %eax,%r13
 335:	e9 c2 fe ff ff       	jmp    1fc <__libc_malloc_impl+0x1fc>
 33a:	8b 05 00 00 00 00    	mov    0x0(%rip),%eax        # 340 <__libc_malloc_impl+0x340>
			33c: R_X86_64_PC32	__malloc_lock-0x4
 340:	85 c0                	test   %eax,%eax
 342:	0f 89 94 fd ff ff    	jns    dc <__libc_malloc_impl+0xdc>
 348:	bf 00 00 00 00       	mov    $0x0,%edi
			349: R_X86_64_32	__malloc_lock
 34d:	e8 00 00 00 00       	call   352 <__libc_malloc_impl+0x352>
			34e: R_X86_64_PLT32	__unlock-0x4
 352:	e9 85 fd ff ff       	jmp    dc <__libc_malloc_impl+0xdc>
 357:	bf 00 00 00 00       	mov    $0x0,%edi
			358: R_X86_64_32	__malloc_lock
 35c:	e8 00 00 00 00       	call   361 <__libc_malloc_impl+0x361>
			35d: R_X86_64_PLT32	__unlock-0x4
 361:	e9 a4 fe ff ff       	jmp    20a <__libc_malloc_impl+0x20a>
 366:	41 0f b7 56 20       	movzwl 0x20(%r14),%edx
 36b:	66 c1 ea 06          	shr    $0x6,%dx
 36f:	83 e2 3f             	and    $0x3f,%edx
 372:	0f b7 94 12 00 00 00 	movzwl 0x0(%rdx,%rdx,1),%edx
 379:	00 
			376: R_X86_64_32S	__malloc_size_classes
 37a:	c1 e2 04             	shl    $0x4,%edx
 37d:	48 63 d2             	movslq %edx,%rdx
 380:	4c 89 e8             	mov    %r13,%rax
 383:	48 89 d1             	mov    %rdx,%rcx
 386:	49 8b 76 10          	mov    0x10(%r14),%rsi
 38a:	48 0f af c2          	imul   %rdx,%rax
 38e:	48 29 e9             	sub    %rbp,%rcx
 391:	48 83 e9 04          	sub    $0x4,%rcx
 395:	48 83 c6 10          	add    $0x10,%rsi
 399:	49 89 c8             	mov    %rcx,%r8
 39c:	48 01 f0             	add    %rsi,%rax
 39f:	49 c1 e8 04          	shr    $0x4,%r8
 3a3:	80 78 fd 00          	cmpb   $0x0,-0x3(%rax)
 3a7:	48 8d 7c 10 fc       	lea    -0x4(%rax,%rdx,1),%rdi
 3ac:	0f b6 d3             	movzbl %bl,%edx
 3af:	74 0a                	je     3bb <__libc_malloc_impl+0x3bb>
 3b1:	0f b7 50 fe          	movzwl -0x2(%rax),%edx
 3b5:	83 c2 01             	add    $0x1,%edx
 3b8:	0f b6 d2             	movzbl %dl,%edx
 3bb:	80 78 fc 00          	cmpb   $0x0,-0x4(%rax)
 3bf:	0f 85 00 00 00 00    	jne    3c5 <__libc_malloc_impl+0x3c5>
			3c1: R_X86_64_PC32	.text.unlikely.__libc_malloc_impl-0x4
 3c5:	4c 63 ca             	movslq %edx,%r9
 3c8:	4d 39 c8             	cmp    %r9,%r8
 3cb:	73 37                	jae    404 <__libc_malloc_impl+0x404>
 3cd:	48 c1 e9 05          	shr    $0x5,%rcx
 3d1:	4c 09 c1             	or     %r8,%rcx
 3d4:	49 89 c9             	mov    %rcx,%r9
 3d7:	49 c1 e9 02          	shr    $0x2,%r9
 3db:	4c 09 c9             	or     %r9,%rcx
 3de:	49 89 c9             	mov    %rcx,%r9
 3e1:	49 c1 e9 04          	shr    $0x4,%r9
 3e5:	4c 09 c9             	or     %r9,%rcx
 3e8:	21 ca                	and    %ecx,%edx
 3ea:	48 63 ca             	movslq %edx,%rcx
 3ed:	49 39 c8             	cmp    %rcx,%r8
 3f0:	73 12                	jae    404 <__libc_malloc_impl+0x404>
 3f2:	44 29 c2             	sub    %r8d,%edx
 3f5:	83 ea 01             	sub    $0x1,%edx
 3f8:	48 63 ca             	movslq %edx,%rcx
 3fb:	49 39 c8             	cmp    %rcx,%r8
 3fe:	0f 82 00 00 00 00    	jb     404 <__libc_malloc_impl+0x404>
			400: R_X86_64_PC32	.text.unlikely.__libc_malloc_impl-0x4
 404:	85 d2                	test   %edx,%edx
 406:	74 1d                	je     425 <__libc_malloc_impl+0x425>
 408:	66 89 50 fe          	mov    %dx,-0x2(%rax)
 40c:	c1 e2 04             	shl    $0x4,%edx
 40f:	48 63 d2             	movslq %edx,%rdx
 412:	c6 40 fd e0          	movb   $0xe0,-0x3(%rax)
 416:	48 01 d0             	add    %rdx,%rax
 419:	c6 40 fc 00          	movb   $0x0,-0x4(%rax)
 41d:	49 8b 76 10          	mov    0x10(%r14),%rsi
 421:	48 83 c6 10          	add    $0x10,%rsi
 425:	48 89 c2             	mov    %rax,%rdx
 428:	44 88 60 fd          	mov    %r12b,-0x3(%rax)
 42c:	44 89 e1             	mov    %r12d,%ecx
 42f:	48 29 f2             	sub    %rsi,%rdx
 432:	48 c1 ea 04          	shr    $0x4,%rdx
 436:	66 89 50 fe          	mov    %dx,-0x2(%rax)
 43a:	48 89 fa             	mov    %rdi,%rdx
 43d:	48 29 c2             	sub    %rax,%rdx
 440:	29 ea                	sub    %ebp,%edx
 442:	74 1c                	je     460 <__libc_malloc_impl+0x460>
 444:	89 d1                	mov    %edx,%ecx
 446:	f7 d9                	neg    %ecx
 448:	48 63 c9             	movslq %ecx,%rcx
 44b:	c6 04 0f 00          	movb   $0x0,(%rdi,%rcx,1)
 44f:	83 fa 04             	cmp    $0x4,%edx
 452:	7f 18                	jg     46c <__libc_malloc_impl+0x46c>
 454:	0f b6 48 fd          	movzbl -0x3(%rax),%ecx
 458:	c1 e2 05             	shl    $0x5,%edx
 45b:	83 e1 1f             	and    $0x1f,%ecx
 45e:	01 d1                	add    %edx,%ecx
 460:	88 48 fd             	mov    %cl,-0x3(%rax)
 463:	5b                   	pop    %rbx
 464:	5d                   	pop    %rbp
 465:	41 5c                	pop    %r12
 467:	41 5d                	pop    %r13
 469:	41 5e                	pop    %r14
 46b:	c3                   	ret
 46c:	89 57 fc             	mov    %edx,-0x4(%rdi)
 46f:	c6 47 fb 00          	movb   $0x0,-0x5(%rdi)
 473:	0f b6 48 fd          	movzbl -0x3(%rax),%ecx
 477:	83 e1 1f             	and    $0x1f,%ecx
 47a:	83 e9 60             	sub    $0x60,%ecx
 47d:	eb e1                	jmp    460 <__libc_malloc_impl+0x460>

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
  ac:	77 31                	ja     df <__malloc_allzerop+0xdf>
  ae:	83 e2 3f             	and    $0x3f,%edx
  b1:	0f b7 b4 12 00 00 00 	movzwl 0x0(%rdx,%rdx,1),%esi
  b8:	00 
			b5: R_X86_64_32S	__malloc_size_classes
  b9:	44 89 c2             	mov    %r8d,%edx
  bc:	0f af d6             	imul   %esi,%edx
  bf:	39 d1                	cmp    %edx,%ecx
  c1:	0f 8c 00 00 00 00    	jl     c7 <__malloc_allzerop+0xc7>
			c3: R_X86_64_PC32	.text.unlikely.__malloc_allzerop-0x4
  c7:	01 f2                	add    %esi,%edx
  c9:	39 d1                	cmp    %edx,%ecx
  cb:	7d 0d                	jge    da <__malloc_allzerop+0xda>
  cd:	48 81 78 20 ff 0f 00 	cmpq   $0xfff,0x20(%rax)
  d4:	00 
  d5:	77 3d                	ja     114 <__malloc_allzerop+0x114>
  d7:	31 c0                	xor    %eax,%eax
  d9:	c3                   	ret
  da:	e9 00 00 00 00       	jmp    df <__malloc_allzerop+0xdf>
			db: R_X86_64_PC32	.text.unlikely.__malloc_allzerop-0x4
  df:	f7 d6                	not    %esi
  e1:	66 f7 c6 c0 0f       	test   $0xfc0,%si
  e6:	75 27                	jne    10f <__malloc_allzerop+0x10f>
  e8:	48 81 78 20 ff 0f 00 	cmpq   $0xfff,0x20(%rax)
  ef:	00 
  f0:	76 e5                	jbe    d7 <__malloc_allzerop+0xd7>
  f2:	48 8b 50 20          	mov    0x20(%rax),%rdx
  f6:	48 81 e2 00 f0 ff ff 	and    $0xfffffffffffff000,%rdx
  fd:	48 c1 ea 04          	shr    $0x4,%rdx
 101:	48 83 ea 01          	sub    $0x1,%rdx
 105:	48 39 ca             	cmp    %rcx,%rdx
 108:	73 cd                	jae    d7 <__malloc_allzerop+0xd7>
 10a:	e9 00 00 00 00       	jmp    10f <__malloc_allzerop+0x10f>
			10b: R_X86_64_PC32	.text.unlikely.__malloc_allzerop-0x4
 10f:	e9 00 00 00 00       	jmp    114 <__malloc_allzerop+0x114>
			110: R_X86_64_PC32	.text.unlikely.__malloc_allzerop-0x4
 114:	48 8b 50 20          	mov    0x20(%rax),%rdx
 118:	48 63 c1             	movslq %ecx,%rax
 11b:	48 81 e2 00 f0 ff ff 	and    $0xfffffffffffff000,%rdx
 122:	48 89 d1             	mov    %rdx,%rcx
 125:	48 c1 e9 04          	shr    $0x4,%rcx
 129:	48 83 e9 01          	sub    $0x1,%rcx
 12d:	48 39 c1             	cmp    %rax,%rcx
 130:	72 1a                	jb     14c <__malloc_allzerop+0x14c>
 132:	c1 e6 04             	shl    $0x4,%esi
 135:	31 c0                	xor    %eax,%eax
 137:	83 e7 1f             	and    $0x1f,%edi
 13a:	48 63 f6             	movslq %esi,%rsi
 13d:	75 12                	jne    151 <__malloc_allzerop+0x151>
 13f:	48 83 ea 10          	sub    $0x10,%rdx
 143:	31 c0                	xor    %eax,%eax
 145:	48 39 f2             	cmp    %rsi,%rdx
 148:	0f 92 c0             	setb   %al
 14b:	c3                   	ret
 14c:	e9 00 00 00 00       	jmp    151 <__malloc_allzerop+0x151>
			14d: R_X86_64_PC32	.text.unlikely.__malloc_allzerop-0x4
 151:	c3                   	ret

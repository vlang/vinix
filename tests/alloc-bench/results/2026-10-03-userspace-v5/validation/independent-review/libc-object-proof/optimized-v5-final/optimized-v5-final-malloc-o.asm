
/Users/alex/code/vinix/third_party/useralloc-libc/build/musl/x86_64/c97687ce9e5ca67f3acb8947bf28d3def2b044abf977e9e91ab8e8c767083b1c/objects/obj/src/malloc/mallocng/malloc.o:     file format elf64-x86-64


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
  2d:	0f 85 cc 01 00 00    	jne    1ff <alloc_slot+0x1ff>
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
  7e:	47 0f b7 a4 36 00 00 	movzwl 0x0(%r14,%r14,1),%r12d
  85:	00 00 
			83: R_X86_64_32S	__malloc_size_classes
  87:	48 89 7c 24 10       	mov    %rdi,0x10(%rsp)
  8c:	e8 00 00 00 00       	call   91 <alloc_slot+0x91>
			8d: R_X86_64_PLT32	__malloc_alloc_meta-0x4
  91:	66 48 0f 6e c8       	movq   %rax,%xmm1
  96:	41 c1 e4 04          	shl    $0x4,%r12d
  9a:	48 89 c5             	mov    %rax,%rbp
  9d:	66 0f 6c c9          	punpcklqdq %xmm1,%xmm1
  a1:	4d 63 e4             	movslq %r12d,%r12
  a4:	0f 29 0c 24          	movaps %xmm1,(%rsp)
  a8:	48 85 c0             	test   %rax,%rax
  ab:	0f 84 95 07 00 00    	je     846 <alloc_slot+0x846>
  b1:	41 83 fd 08          	cmp    $0x8,%r13d
  b5:	4a 8b 0c f5 00 00 00 	mov    0x0(,%r14,8),%rcx
  bc:	00 
			b9: R_X86_64_32S	__malloc_context+0x1f8
  bd:	48 8b 7c 24 10       	mov    0x10(%rsp),%rdi
  c2:	0f 8f 0e 02 00 00    	jg     2d6 <alloc_slot+0x2d6>
  c8:	4b 8d 04 76          	lea    (%r14,%r14,2),%rax
  cc:	0f b6 98 00 00 00 00 	movzbl 0x0(%rax),%ebx
			cf: R_X86_64_32S	.rodata.small_cnt_tab
  d3:	48 8d 90 00 00 00 00 	lea    0x0(%rax),%rdx
			d6: R_X86_64_32S	.rodata.small_cnt_tab
  da:	8d 04 9d 00 00 00 00 	lea    0x0(,%rbx,4),%eax
  e1:	48 98                	cltq
  e3:	48 39 c1             	cmp    %rax,%rcx
  e6:	0f 83 45 02 00 00    	jae    331 <alloc_slot+0x331>
  ec:	0f b6 5a 01          	movzbl 0x1(%rdx),%ebx
  f0:	8d 04 9d 00 00 00 00 	lea    0x0(,%rbx,4),%eax
  f7:	48 98                	cltq
  f9:	48 39 c1             	cmp    %rax,%rcx
  fc:	0f 83 2f 02 00 00    	jae    331 <alloc_slot+0x331>
 102:	0f b6 5a 02          	movzbl 0x2(%rdx),%ebx
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
 141:	44 8b 4a 1c          	mov    0x1c(%rdx),%r9d
 145:	d3 e0                	shl    %cl,%eax
 147:	83 e8 01             	sub    $0x1,%eax
 14a:	41 39 c1             	cmp    %eax,%r9d
 14d:	0f 84 d2 00 00 00    	je     225 <alloc_slot+0x225>
 153:	4c 8b 42 10          	mov    0x10(%rdx),%r8
 157:	b8 02 00 00 00       	mov    $0x2,%eax
 15c:	41 0f b6 48 08       	movzbl 0x8(%r8),%ecx
 161:	d3 e0                	shl    %cl,%eax
 163:	89 ce                	mov    %ecx,%esi
 165:	83 e8 01             	sub    $0x1,%eax
 168:	83 e6 1f             	and    $0x1f,%esi
 16b:	44 85 c8             	test   %r9d,%eax
 16e:	75 18                	jne    188 <alloc_slot+0x188>
 170:	4c 8b 4a 08          	mov    0x8(%rdx),%r9
 174:	4c 39 ca             	cmp    %r9,%rdx
 177:	0f 84 c6 00 00 00    	je     243 <alloc_slot+0x243>
 17d:	4e 89 0c f5 00 00 00 	mov    %r9,0x0(,%r14,8)
 184:	00 
			181: R_X86_64_32S	__malloc_context+0x50
 185:	4c 89 ca             	mov    %r9,%rdx
 188:	8b 42 18             	mov    0x18(%rdx),%eax
 18b:	85 c0                	test   %eax,%eax
 18d:	0f 85 00 00 00 00    	jne    193 <alloc_slot+0x193>
			18f: R_X86_64_PC32	.text.unlikely.alloc_slot-0x4
 193:	48 8b 42 10          	mov    0x10(%rdx),%rax
 197:	41 b9 02 00 00 00    	mov    $0x2,%r9d
 19d:	4c 8d 52 1c          	lea    0x1c(%rdx),%r10
 1a1:	0f b6 48 08          	movzbl 0x8(%rax),%ecx
 1a5:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 1ac <alloc_slot+0x1ac>
			1a8: R_X86_64_PC32	__libc-0x1
 1ac:	41 d3 e1             	shl    %cl,%r9d
 1af:	45 8d 41 ff          	lea    -0x1(%r9),%r8d
 1b3:	41 f7 d9             	neg    %r9d
 1b6:	84 c0                	test   %al,%al
 1b8:	0f 85 00 01 00 00    	jne    2be <alloc_slot+0x2be>
 1be:	8b 4a 1c             	mov    0x1c(%rdx),%ecx
 1c1:	41 21 c9             	and    %ecx,%r9d
 1c4:	44 89 4a 1c          	mov    %r9d,0x1c(%rdx)
 1c8:	44 21 c1             	and    %r8d,%ecx
 1cb:	89 4a 18             	mov    %ecx,0x18(%rdx)
 1ce:	0f 84 00 00 00 00    	je     1d4 <alloc_slot+0x1d4>
			1d0: R_X86_64_PC32	.text.unlikely.alloc_slot-0x4
 1d4:	0f b7 42 20          	movzwl 0x20(%rdx),%eax
 1d8:	66 c1 e8 06          	shr    $0x6,%ax
 1dc:	83 e0 3f             	and    $0x3f,%eax
 1df:	83 e8 07             	sub    $0x7,%eax
 1e2:	83 f8 1f             	cmp    $0x1f,%eax
 1e5:	77 18                	ja     1ff <alloc_slot+0x1ff>
 1e7:	48 98                	cltq
 1e9:	0f b6 b0 00 00 00 00 	movzbl 0x0(%rax),%esi
			1ec: R_X86_64_32S	__malloc_context+0x398
 1f0:	40 84 f6             	test   %sil,%sil
 1f3:	74 0a                	je     1ff <alloc_slot+0x1ff>
 1f5:	83 ee 01             	sub    $0x1,%esi
 1f8:	40 88 b0 00 00 00 00 	mov    %sil,0x0(%rax)
			1fb: R_X86_64_32S	__malloc_context+0x398
 1ff:	89 c8                	mov    %ecx,%eax
 201:	f7 d8                	neg    %eax
 203:	21 c8                	and    %ecx,%eax
 205:	29 c1                	sub    %eax,%ecx
 207:	89 4a 18             	mov    %ecx,0x18(%rdx)
 20a:	85 c0                	test   %eax,%eax
 20c:	0f 84 6c fe ff ff    	je     7e <alloc_slot+0x7e>
 212:	f3 0f bc c0          	tzcnt  %eax,%eax
 216:	48 83 c4 28          	add    $0x28,%rsp
 21a:	5b                   	pop    %rbx
 21b:	5d                   	pop    %rbp
 21c:	41 5c                	pop    %r12
 21e:	41 5d                	pop    %r13
 220:	41 5e                	pop    %r14
 222:	41 5f                	pop    %r15
 224:	c3                   	ret
 225:	83 e1 20             	and    $0x20,%ecx
 228:	0f 84 5a ff ff ff    	je     188 <alloc_slot+0x188>
 22e:	48 8b 52 08          	mov    0x8(%rdx),%rdx
 232:	4a 89 14 f5 00 00 00 	mov    %rdx,0x0(,%r14,8)
 239:	00 
			236: R_X86_64_32S	__malloc_context+0x50
 23a:	44 8b 4a 1c          	mov    0x1c(%rdx),%r9d
 23e:	e9 10 ff ff ff       	jmp    153 <alloc_slot+0x153>
 243:	41 0f b7 41 20       	movzwl 0x20(%r9),%eax
 248:	83 c6 02             	add    $0x2,%esi
 24b:	89 f2                	mov    %esi,%edx
 24d:	66 c1 e8 06          	shr    $0x6,%ax
 251:	83 e0 3f             	and    $0x3f,%eax
 254:	44 0f b7 94 00 00 00 	movzwl 0x0(%rax,%rax,1),%r10d
 25b:	00 00 
			259: R_X86_64_32S	__malloc_size_classes
 25d:	41 c1 e2 04          	shl    $0x4,%r10d
 261:	41 0f af d2          	imul   %r10d,%edx
 265:	83 c2 10             	add    $0x10,%edx
 268:	eb 1b                	jmp    285 <alloc_slot+0x285>
 26a:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
 271:	00 00 00 00 
 275:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
 27c:	00 00 00 00 
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
 2b9:	e9 c7 fe ff ff       	jmp    185 <alloc_slot+0x185>
 2be:	8b 4a 1c             	mov    0x1c(%rdx),%ecx
 2c1:	89 ce                	mov    %ecx,%esi
 2c3:	89 c8                	mov    %ecx,%eax
 2c5:	44 21 ce             	and    %r9d,%esi
 2c8:	f0 41 0f b1 32       	lock cmpxchg %esi,(%r10)
 2cd:	39 c1                	cmp    %eax,%ecx
 2cf:	75 ed                	jne    2be <alloc_slot+0x2be>
 2d1:	e9 f2 fe ff ff       	jmp    1c8 <alloc_slot+0x1c8>
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
 36a:	0f 86 fd 03 00 00    	jbe    76d <alloc_slot+0x76d>
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
 3b1:	0f 86 b6 03 00 00    	jbe    76d <alloc_slot+0x76d>
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
 592:	0f 84 39 04 00 00    	je     9d1 <alloc_slot+0x9d1>
 598:	48 89 45 08          	mov    %rax,0x8(%rbp)
 59c:	48 8b 00             	mov    (%rax),%rax
 59f:	48 89 45 00          	mov    %rax,0x0(%rbp)
 5a3:	48 89 68 08          	mov    %rbp,0x8(%rax)
 5a7:	48 8b 45 08          	mov    0x8(%rbp),%rax
 5ab:	48 89 28             	mov    %rbp,(%rax)
 5ae:	31 c0                	xor    %eax,%eax
 5b0:	e9 61 fc ff ff       	jmp    216 <alloc_slot+0x216>
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
 752:	0f 85 d8 00 00 00    	jne    830 <alloc_slot+0x830>
 758:	66 0f 6f 1c 24       	movdqa (%rsp),%xmm3
 75d:	0f 11 5d 00          	movups %xmm3,0x0(%rbp)
 761:	48 89 2d 00 00 00 00 	mov    %rbp,0x0(%rip)        # 768 <alloc_slot+0x768>
			764: R_X86_64_PC32	__malloc_context+0xc
 768:	e9 d9 00 00 00       	jmp    846 <alloc_slot+0x846>
 76d:	48 89 d0             	mov    %rdx,%rax
 770:	48 8d 72 0c          	lea    0xc(%rdx),%rsi
 774:	48 c1 e8 04          	shr    $0x4,%rax
 778:	48 81 fa 90 00 00 00 	cmp    $0x90,%rdx
 77f:	0f 86 87 00 00 00    	jbe    80c <alloc_slot+0x80c>
 785:	48 83 c0 01          	add    $0x1,%rax
 789:	0f bd d0             	bsr    %eax,%edx
 78c:	8d 14 95 fc ff ff ff 	lea    -0x4(,%rdx,4),%edx
 793:	8d 4a 01             	lea    0x1(%rdx),%ecx
 796:	48 63 c9             	movslq %ecx,%rcx
 799:	0f b7 bc 09 00 00 00 	movzwl 0x0(%rcx,%rcx,1),%edi
 7a0:	00 
			79d: R_X86_64_32S	__malloc_size_classes
 7a1:	8d 4a 02             	lea    0x2(%rdx),%ecx
 7a4:	48 39 c7             	cmp    %rax,%rdi
 7a7:	0f 42 d1             	cmovb  %ecx,%edx
 7aa:	48 63 ca             	movslq %edx,%rcx
 7ad:	0f b7 8c 09 00 00 00 	movzwl 0x0(%rcx,%rcx,1),%ecx
 7b4:	00 
			7b1: R_X86_64_32S	__malloc_size_classes
 7b5:	48 39 c1             	cmp    %rax,%rcx
 7b8:	83 d2 00             	adc    $0x0,%edx
 7bb:	89 d7                	mov    %edx,%edi
 7bd:	89 54 24 10          	mov    %edx,0x10(%rsp)
 7c1:	e8 3a f8 ff ff       	call   0 <alloc_slot>
 7c6:	48 63 54 24 10       	movslq 0x10(%rsp),%rdx
 7cb:	83 f8 ff             	cmp    $0xffffffff,%eax
 7ce:	74 40                	je     810 <alloc_slot+0x810>
 7d0:	4c 8b 04 d5 00 00 00 	mov    0x0(,%rdx,8),%r8
 7d7:	00 
			7d4: R_X86_64_32S	__malloc_context+0x50
 7d8:	0f b7 94 12 00 00 00 	movzwl 0x0(%rdx,%rdx,1),%edx
 7df:	00 
			7dc: R_X86_64_32S	__malloc_size_classes
 7e0:	c1 e2 04             	shl    $0x4,%edx
 7e3:	44 8d 5a fc          	lea    -0x4(%rdx),%r11d
 7e7:	49 63 f3             	movslq %r11d,%rsi
 7ea:	41 f6 40 20 1f       	testb  $0x1f,0x20(%r8)
 7ef:	75 71                	jne    862 <alloc_slot+0x862>
 7f1:	49 81 78 20 ff 0f 00 	cmpq   $0xfff,0x20(%r8)
 7f8:	00 
 7f9:	76 67                	jbe    862 <alloc_slot+0x862>
 7fb:	49 8b 48 20          	mov    0x20(%r8),%rcx
 7ff:	48 81 e1 00 f0 ff ff 	and    $0xfffffffffffff000,%rcx
 806:	48 83 e9 10          	sub    $0x10,%rcx
 80a:	eb 70                	jmp    87c <alloc_slot+0x87c>
 80c:	89 c2                	mov    %eax,%edx
 80e:	eb ab                	jmp    7bb <alloc_slot+0x7bb>
 810:	66 0f ef c0          	pxor   %xmm0,%xmm0
 814:	48 c7 45 20 00 00 00 	movq   $0x0,0x20(%rbp)
 81b:	00 
 81c:	0f 11 45 00          	movups %xmm0,0x0(%rbp)
 820:	0f 11 45 10          	movups %xmm0,0x10(%rbp)
 824:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 82b <alloc_slot+0x82b>
			827: R_X86_64_PC32	__malloc_context+0xc
 82b:	48 85 c0             	test   %rax,%rax
 82e:	74 20                	je     850 <alloc_slot+0x850>
 830:	48 89 45 08          	mov    %rax,0x8(%rbp)
 834:	48 8b 00             	mov    (%rax),%rax
 837:	48 89 45 00          	mov    %rax,0x0(%rbp)
 83b:	48 89 68 08          	mov    %rbp,0x8(%rax)
 83f:	48 8b 45 08          	mov    0x8(%rbp),%rax
 843:	48 89 28             	mov    %rbp,(%rax)
 846:	b8 ff ff ff ff       	mov    $0xffffffff,%eax
 84b:	e9 c6 f9 ff ff       	jmp    216 <alloc_slot+0x216>
 850:	66 0f 6f 24 24       	movdqa (%rsp),%xmm4
 855:	0f 11 65 00          	movups %xmm4,0x0(%rbp)
 859:	48 89 2d 00 00 00 00 	mov    %rbp,0x0(%rip)        # 860 <alloc_slot+0x860>
			85c: R_X86_64_PC32	__malloc_context+0xc
 860:	eb e4                	jmp    846 <alloc_slot+0x846>
 862:	41 0f b7 50 20       	movzwl 0x20(%r8),%edx
 867:	66 c1 ea 06          	shr    $0x6,%dx
 86b:	83 e2 3f             	and    $0x3f,%edx
 86e:	0f b7 8c 12 00 00 00 	movzwl 0x0(%rdx,%rdx,1),%ecx
 875:	00 
			872: R_X86_64_32S	__malloc_size_classes
 876:	c1 e1 04             	shl    $0x4,%ecx
 879:	48 63 c9             	movslq %ecx,%rcx
 87c:	48 89 ca             	mov    %rcx,%rdx
 87f:	48 29 f2             	sub    %rsi,%rdx
 882:	48 63 f0             	movslq %eax,%rsi
 885:	48 0f af f1          	imul   %rcx,%rsi
 889:	4c 8d 4a fc          	lea    -0x4(%rdx),%r9
 88d:	49 8b 50 10          	mov    0x10(%r8),%rdx
 891:	48 83 c2 10          	add    $0x10,%rdx
 895:	48 01 d6             	add    %rdx,%rsi
 898:	48 8d 7c 0e fc       	lea    -0x4(%rsi,%rcx,1),%rdi
 89d:	0f b6 4e fc          	movzbl -0x4(%rsi),%ecx
 8a1:	48 89 7c 24 10       	mov    %rdi,0x10(%rsp)
 8a6:	84 c9                	test   %cl,%cl
 8a8:	0f 85 00 00 00 00    	jne    8ae <alloc_slot+0x8ae>
			8aa: R_X86_64_PC32	.text.unlikely.alloc_slot-0x4
 8ae:	49 83 f9 0f          	cmp    $0xf,%r9
 8b2:	0f 86 8e 00 00 00    	jbe    946 <alloc_slot+0x946>
 8b8:	80 7e fd 00          	cmpb   $0x0,-0x3(%rsi)
 8bc:	0f 84 f5 00 00 00    	je     9b7 <alloc_slot+0x9b7>
 8c2:	0f b7 7e fe          	movzwl -0x2(%rsi),%edi
 8c6:	83 c7 01             	add    $0x1,%edi
 8c9:	40 0f b6 ff          	movzbl %dil,%edi
 8cd:	4d 89 ca             	mov    %r9,%r10
 8d0:	49 c1 ea 04          	shr    $0x4,%r10
 8d4:	4c 89 54 24 18       	mov    %r10,0x18(%rsp)
 8d9:	4c 63 d7             	movslq %edi,%r10
 8dc:	4c 39 54 24 18       	cmp    %r10,0x18(%rsp)
 8e1:	73 42                	jae    925 <alloc_slot+0x925>
 8e3:	4c 8b 54 24 18       	mov    0x18(%rsp),%r10
 8e8:	49 c1 e9 05          	shr    $0x5,%r9
 8ec:	4d 09 d1             	or     %r10,%r9
 8ef:	4d 89 ca             	mov    %r9,%r10
 8f2:	49 c1 ea 02          	shr    $0x2,%r10
 8f6:	4d 09 d1             	or     %r10,%r9
 8f9:	4d 89 ca             	mov    %r9,%r10
 8fc:	49 c1 ea 04          	shr    $0x4,%r10
 900:	4d 09 d1             	or     %r10,%r9
 903:	4c 8b 54 24 18       	mov    0x18(%rsp),%r10
 908:	44 21 cf             	and    %r9d,%edi
 90b:	4c 63 cf             	movslq %edi,%r9
 90e:	4d 39 ca             	cmp    %r9,%r10
 911:	73 12                	jae    925 <alloc_slot+0x925>
 913:	44 29 d7             	sub    %r10d,%edi
 916:	83 ef 01             	sub    $0x1,%edi
 919:	4c 63 cf             	movslq %edi,%r9
 91c:	4d 39 ca             	cmp    %r9,%r10
 91f:	0f 82 00 00 00 00    	jb     925 <alloc_slot+0x925>
			921: R_X86_64_PC32	.text.unlikely.alloc_slot-0x4
 925:	85 ff                	test   %edi,%edi
 927:	74 1d                	je     946 <alloc_slot+0x946>
 929:	66 89 7e fe          	mov    %di,-0x2(%rsi)
 92d:	c1 e7 04             	shl    $0x4,%edi
 930:	48 63 d7             	movslq %edi,%rdx
 933:	c6 46 fd e0          	movb   $0xe0,-0x3(%rsi)
 937:	48 01 d6             	add    %rdx,%rsi
 93a:	c6 46 fc 00          	movb   $0x0,-0x4(%rsi)
 93e:	49 8b 50 10          	mov    0x10(%r8),%rdx
 942:	48 83 c2 10          	add    $0x10,%rdx
 946:	48 89 f7             	mov    %rsi,%rdi
 949:	48 29 d7             	sub    %rdx,%rdi
 94c:	48 c1 ef 04          	shr    $0x4,%rdi
 950:	66 89 7e fe          	mov    %di,-0x2(%rsi)
 954:	48 8b 7c 24 10       	mov    0x10(%rsp),%rdi
 959:	48 89 fa             	mov    %rdi,%rdx
 95c:	48 29 f2             	sub    %rsi,%rdx
 95f:	44 29 da             	sub    %r11d,%edx
 962:	74 15                	je     979 <alloc_slot+0x979>
 964:	89 d1                	mov    %edx,%ecx
 966:	f7 d9                	neg    %ecx
 968:	48 63 c9             	movslq %ecx,%rcx
 96b:	c6 04 0f 00          	movb   $0x0,(%rdi,%rcx,1)
 96f:	83 fa 04             	cmp    $0x4,%edx
 972:	7f 4f                	jg     9c3 <alloc_slot+0x9c3>
 974:	89 d1                	mov    %edx,%ecx
 976:	c1 e1 05             	shl    $0x5,%ecx
 979:	01 c1                	add    %eax,%ecx
 97b:	48 8d 56 0c          	lea    0xc(%rsi),%rdx
 97f:	88 4e fd             	mov    %cl,-0x3(%rsi)
 982:	8d 4b 01             	lea    0x1(%rbx),%ecx
 985:	48 81 65 20 ff 0f 00 	andq   $0xfff,0x20(%rbp)
 98c:	00 
 98d:	0f b6 46 fd          	movzbl -0x3(%rsi),%eax
 991:	83 e0 1f             	and    $0x1f,%eax
 994:	83 c8 c0             	or     $0xffffffc0,%eax
 997:	88 46 fd             	mov    %al,-0x3(%rsi)
 99a:	31 c0                	xor    %eax,%eax
 99c:	0f 1f 40 00          	nopl   0x0(%rax)
 9a0:	83 c0 01             	add    $0x1,%eax
 9a3:	c6 02 00             	movb   $0x0,(%rdx)
 9a6:	4c 01 e2             	add    %r12,%rdx
 9a9:	39 c8                	cmp    %ecx,%eax
 9ab:	75 f3                	jne    9a0 <alloc_slot+0x9a0>
 9ad:	8d 53 ff             	lea    -0x1(%rbx),%edx
 9b0:	89 d7                	mov    %edx,%edi
 9b2:	e9 40 fb ff ff       	jmp    4f7 <alloc_slot+0x4f7>
 9b7:	0f b6 3d 00 00 00 00 	movzbl 0x0(%rip),%edi        # 9be <alloc_slot+0x9be>
			9ba: R_X86_64_PC32	__malloc_context+0x8
 9be:	e9 0a ff ff ff       	jmp    8cd <alloc_slot+0x8cd>
 9c3:	89 57 fc             	mov    %edx,-0x4(%rdi)
 9c6:	b9 a0 ff ff ff       	mov    $0xffffffa0,%ecx
 9cb:	c6 47 fb 00          	movb   $0x0,-0x5(%rdi)
 9cf:	eb a8                	jmp    979 <alloc_slot+0x979>
 9d1:	66 0f 6f 14 24       	movdqa (%rsp),%xmm2
 9d6:	0f 11 55 00          	movups %xmm2,0x0(%rbp)
 9da:	4a 89 2c f5 00 00 00 	mov    %rbp,0x0(,%r14,8)
 9e1:	00 
			9de: R_X86_64_32S	__malloc_context
 9e2:	e9 c7 fb ff ff       	jmp    5ae <alloc_slot+0x5ae>

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
  15:	0f 82 ba 00 00 00    	jb     d5 <__libc_malloc_impl+0xd5>
  1b:	48 89 fb             	mov    %rdi,%rbx
  1e:	48 81 ff eb ff 01 00 	cmp    $0x1ffeb,%rdi
  25:	0f 87 bc 00 00 00    	ja     e7 <__libc_malloc_impl+0xe7>
  2b:	48 8d 57 03          	lea    0x3(%rdi),%rdx
  2f:	48 89 d0             	mov    %rdx,%rax
  32:	48 c1 e8 04          	shr    $0x4,%rax
  36:	48 63 e8             	movslq %eax,%rbp
  39:	49 89 ed             	mov    %rbp,%r13
  3c:	48 81 fa 9f 00 00 00 	cmp    $0x9f,%rdx
  43:	76 40                	jbe    85 <__libc_malloc_impl+0x85>
  45:	48 83 c0 01          	add    $0x1,%rax
  49:	0f bd d0             	bsr    %eax,%edx
  4c:	44 8d 2c 95 fc ff ff 	lea    -0x4(,%rdx,4),%r13d
  53:	ff 
  54:	41 8d 55 01          	lea    0x1(%r13),%edx
  58:	48 63 d2             	movslq %edx,%rdx
  5b:	0f b7 8c 12 00 00 00 	movzwl 0x0(%rdx,%rdx,1),%ecx
  62:	00 
			5f: R_X86_64_32S	__malloc_size_classes
  63:	41 8d 55 02          	lea    0x2(%r13),%edx
  67:	48 39 c1             	cmp    %rax,%rcx
  6a:	44 0f 42 ea          	cmovb  %edx,%r13d
  6e:	49 63 ed             	movslq %r13d,%rbp
  71:	0f b7 94 2d 00 00 00 	movzwl 0x0(%rbp,%rbp,1),%edx
  78:	00 
			75: R_X86_64_32S	__malloc_size_classes
  79:	48 39 c2             	cmp    %rax,%rdx
  7c:	73 07                	jae    85 <__libc_malloc_impl+0x85>
  7e:	41 83 c5 01          	add    $0x1,%r13d
  82:	49 63 ed             	movslq %r13d,%rbp
  85:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 8c <__libc_malloc_impl+0x8c>
			88: R_X86_64_PC32	__libc-0x1
  8c:	84 c0                	test   %al,%al
  8e:	0f 85 6f 02 00 00    	jne    303 <__libc_malloc_impl+0x303>
  94:	4c 8b 34 ed 00 00 00 	mov    0x0(,%rbp,8),%r14
  9b:	00 
			98: R_X86_64_32S	__malloc_context+0x50
  9c:	4d 85 f6             	test   %r14,%r14
  9f:	0f 84 6d 02 00 00    	je     312 <__libc_malloc_impl+0x312>
  a5:	41 8b 46 18          	mov    0x18(%r14),%eax
  a9:	41 89 c4             	mov    %eax,%r12d
  ac:	41 f7 dc             	neg    %r12d
  af:	41 21 c4             	and    %eax,%r12d
  b2:	0f 84 5a 02 00 00    	je     312 <__libc_malloc_impl+0x312>
  b8:	45 31 ed             	xor    %r13d,%r13d
  bb:	44 29 e0             	sub    %r12d,%eax
  be:	8b 2d 00 00 00 00    	mov    0x0(%rip),%ebp        # c4 <__libc_malloc_impl+0xc4>
			c0: R_X86_64_PC32	__malloc_context+0x8
  c4:	f3 45 0f bc ec       	tzcnt  %r12d,%r13d
  c9:	41 89 46 18          	mov    %eax,0x18(%r14)
  cd:	4d 89 ec             	mov    %r13,%r12
  d0:	e9 28 01 00 00       	jmp    1fd <__libc_malloc_impl+0x1fd>
  d5:	e8 00 00 00 00       	call   da <__libc_malloc_impl+0xda>
			d6: R_X86_64_PLT32	___errno_location-0x4
  da:	c7 00 0c 00 00 00    	movl   $0xc,(%rax)
  e0:	31 c0                	xor    %eax,%eax
  e2:	e9 7d 03 00 00       	jmp    464 <__libc_malloc_impl+0x464>
  e7:	4c 8d af 13 10 00 00 	lea    0x1013(%rdi),%r13
  ee:	4c 8d 67 14          	lea    0x14(%rdi),%r12
  f2:	49 c1 ed 0c          	shr    $0xc,%r13
  f6:	49 8d 45 e0          	lea    -0x20(%r13),%rax
  fa:	48 3d e0 01 00 00    	cmp    $0x1e0,%rax
 100:	77 5f                	ja     161 <__libc_malloc_impl+0x161>
 102:	b8 20 00 00 00       	mov    $0x20,%eax
 107:	31 ed                	xor    %ebp,%ebp
 109:	0f 1f 80 00 00 00 00 	nopl   0x0(%rax)
 110:	4c 39 e8             	cmp    %r13,%rax
 113:	73 08                	jae    11d <__libc_malloc_impl+0x11d>
 115:	83 c5 01             	add    $0x1,%ebp
 118:	48 01 c0             	add    %rax,%rax
 11b:	eb f3                	jmp    110 <__libc_malloc_impl+0x110>
 11d:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 124 <__libc_malloc_impl+0x124>
			120: R_X86_64_PC32	__libc-0x1
 124:	84 c0                	test   %al,%al
 126:	0f 85 0c 01 00 00    	jne    238 <__libc_malloc_impl+0x238>
 12c:	48 63 ed             	movslq %ebp,%rbp
 12f:	48 83 c5 3a          	add    $0x3a,%rbp
 133:	4c 8b 34 ed 00 00 00 	mov    0x0(,%rbp,8),%r14
 13a:	00 
			137: R_X86_64_32S	__malloc_context
 13b:	4d 85 f6             	test   %r14,%r14
 13e:	74 13                	je     153 <__libc_malloc_impl+0x153>
 140:	49 8b 46 20          	mov    0x20(%r14),%rax
 144:	48 25 00 f0 ff ff    	and    $0xfffffffffffff000,%rax
 14a:	4c 39 e0             	cmp    %r12,%rax
 14d:	0f 83 f4 00 00 00    	jae    247 <__libc_malloc_impl+0x247>
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
 17e:	48 89 c5             	mov    %rax,%rbp
 181:	48 83 f8 ff          	cmp    $0xffffffffffffffff,%rax
 185:	0f 84 55 ff ff ff    	je     e0 <__libc_malloc_impl+0xe0>
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
 1c7:	48 89 68 10          	mov    %rbp,0x10(%rax)
 1cb:	49 81 cd e0 0f 00 00 	or     $0xfe0,%r13
 1d2:	48 89 45 00          	mov    %rax,0x0(%rbp)
 1d6:	c7 40 1c 00 00 00 00 	movl   $0x0,0x1c(%rax)
 1dd:	4c 89 68 20          	mov    %r13,0x20(%rax)
 1e1:	c7 40 18 00 00 00 00 	movl   $0x0,0x18(%rax)
 1e8:	8b 05 00 00 00 00    	mov    0x0(%rip),%eax        # 1ee <__libc_malloc_impl+0x1ee>
			1ea: R_X86_64_PC32	__malloc_context+0x8
 1ee:	45 31 ed             	xor    %r13d,%r13d
 1f1:	45 31 e4             	xor    %r12d,%r12d
 1f4:	8d 68 01             	lea    0x1(%rax),%ebp
 1f7:	89 2d 00 00 00 00    	mov    %ebp,0x0(%rip)        # 1fd <__libc_malloc_impl+0x1fd>
			1f9: R_X86_64_PC32	__malloc_context+0x8
 1fd:	8b 15 00 00 00 00    	mov    0x0(%rip),%edx        # 203 <__libc_malloc_impl+0x203>
			1ff: R_X86_64_PC32	__malloc_lock-0x4
 203:	85 d2                	test   %edx,%edx
 205:	0f 88 4d 01 00 00    	js     358 <__libc_malloc_impl+0x358>
 20b:	41 f6 46 20 1f       	testb  $0x1f,0x20(%r14)
 210:	0f 85 51 01 00 00    	jne    367 <__libc_malloc_impl+0x367>
 216:	49 81 7e 20 ff 0f 00 	cmpq   $0xfff,0x20(%r14)
 21d:	00 
 21e:	0f 86 43 01 00 00    	jbe    367 <__libc_malloc_impl+0x367>
 224:	49 8b 56 20          	mov    0x20(%r14),%rdx
 228:	48 81 e2 00 f0 ff ff 	and    $0xfffffffffffff000,%rdx
 22f:	48 83 ea 10          	sub    $0x10,%rdx
 233:	e9 49 01 00 00       	jmp    381 <__libc_malloc_impl+0x381>
 238:	bf 00 00 00 00       	mov    $0x0,%edi
			239: R_X86_64_32	__malloc_lock
 23d:	e8 00 00 00 00       	call   242 <__libc_malloc_impl+0x242>
			23e: R_X86_64_PLT32	__lock-0x4
 242:	e9 e5 fe ff ff       	jmp    12c <__libc_malloc_impl+0x12c>
 247:	48 c7 04 ed 00 00 00 	movq   $0x0,0x0(,%rbp,8)
 24e:	00 00 00 00 00 
			24b: R_X86_64_32S	__malloc_context
 253:	41 c7 46 1c 00 00 00 	movl   $0x0,0x1c(%r14)
 25a:	00 
 25b:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 262 <__libc_malloc_impl+0x262>
			25e: R_X86_64_PC32	__malloc_context+0x3b4
 262:	8d 50 01             	lea    0x1(%rax),%edx
 265:	3c ff                	cmp    $0xff,%al
 267:	74 0b                	je     274 <__libc_malloc_impl+0x274>
 269:	88 15 00 00 00 00    	mov    %dl,0x0(%rip)        # 26f <__libc_malloc_impl+0x26f>
			26b: R_X86_64_PC32	__malloc_context+0x3b4
 26f:	e9 74 ff ff ff       	jmp    1e8 <__libc_malloc_impl+0x1e8>
 274:	b8 00 00 00 00       	mov    $0x0,%eax
			275: R_X86_64_32	__malloc_context+0x378
 279:	eb 10                	jmp    28b <__libc_malloc_impl+0x28b>
 27b:	0f 1f 44 00 00       	nopl   0x0(%rax,%rax,1)
 280:	c6 00 00             	movb   $0x0,(%rax)
 283:	48 83 c0 02          	add    $0x2,%rax
 287:	c6 40 ff 00          	movb   $0x0,-0x1(%rax)
 28b:	48 3d 00 00 00 00    	cmp    $0x0,%rax
			28d: R_X86_64_32S	__malloc_context+0x398
 291:	75 ed                	jne    280 <__libc_malloc_impl+0x280>
 293:	ba 01 00 00 00       	mov    $0x1,%edx
 298:	eb cf                	jmp    269 <__libc_malloc_impl+0x269>
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
 2ea:	48 89 ef             	mov    %rbp,%rdi
 2ed:	e8 00 00 00 00       	call   2f2 <__libc_malloc_impl+0x2f2>
			2ee: R_X86_64_PLT32	munmap-0x4
 2f2:	e9 e9 fd ff ff       	jmp    e0 <__libc_malloc_impl+0xe0>
 2f7:	bf 00 00 00 00       	mov    $0x0,%edi
			2f8: R_X86_64_32	__malloc_lock
 2fc:	e8 00 00 00 00       	call   301 <__libc_malloc_impl+0x301>
			2fd: R_X86_64_PLT32	__unlock-0x4
 301:	eb e4                	jmp    2e7 <__libc_malloc_impl+0x2e7>
 303:	bf 00 00 00 00       	mov    $0x0,%edi
			304: R_X86_64_32	__malloc_lock
 308:	e8 00 00 00 00       	call   30d <__libc_malloc_impl+0x30d>
			309: R_X86_64_PLT32	__lock-0x4
 30d:	e9 82 fd ff ff       	jmp    94 <__libc_malloc_impl+0x94>
 312:	48 89 de             	mov    %rbx,%rsi
 315:	44 89 ef             	mov    %r13d,%edi
 318:	e8 00 00 00 00       	call   31d <__libc_malloc_impl+0x31d>
			319: R_X86_64_PC32	.text.alloc_slot-0x4
 31d:	41 89 c4             	mov    %eax,%r12d
 320:	83 f8 ff             	cmp    $0xffffffff,%eax
 323:	74 16                	je     33b <__libc_malloc_impl+0x33b>
 325:	4c 8b 34 ed 00 00 00 	mov    0x0(,%rbp,8),%r14
 32c:	00 
			329: R_X86_64_32S	__malloc_context+0x50
 32d:	4c 63 e8             	movslq %eax,%r13
 330:	8b 2d 00 00 00 00    	mov    0x0(%rip),%ebp        # 336 <__libc_malloc_impl+0x336>
			332: R_X86_64_PC32	__malloc_context+0x8
 336:	e9 c2 fe ff ff       	jmp    1fd <__libc_malloc_impl+0x1fd>
 33b:	8b 05 00 00 00 00    	mov    0x0(%rip),%eax        # 341 <__libc_malloc_impl+0x341>
			33d: R_X86_64_PC32	__malloc_lock-0x4
 341:	85 c0                	test   %eax,%eax
 343:	0f 89 97 fd ff ff    	jns    e0 <__libc_malloc_impl+0xe0>
 349:	bf 00 00 00 00       	mov    $0x0,%edi
			34a: R_X86_64_32	__malloc_lock
 34e:	e8 00 00 00 00       	call   353 <__libc_malloc_impl+0x353>
			34f: R_X86_64_PLT32	__unlock-0x4
 353:	e9 88 fd ff ff       	jmp    e0 <__libc_malloc_impl+0xe0>
 358:	bf 00 00 00 00       	mov    $0x0,%edi
			359: R_X86_64_32	__malloc_lock
 35d:	e8 00 00 00 00       	call   362 <__libc_malloc_impl+0x362>
			35e: R_X86_64_PLT32	__unlock-0x4
 362:	e9 a4 fe ff ff       	jmp    20b <__libc_malloc_impl+0x20b>
 367:	41 0f b7 56 20       	movzwl 0x20(%r14),%edx
 36c:	66 c1 ea 06          	shr    $0x6,%dx
 370:	83 e2 3f             	and    $0x3f,%edx
 373:	0f b7 94 12 00 00 00 	movzwl 0x0(%rdx,%rdx,1),%edx
 37a:	00 
			377: R_X86_64_32S	__malloc_size_classes
 37b:	c1 e2 04             	shl    $0x4,%edx
 37e:	48 63 d2             	movslq %edx,%rdx
 381:	4c 89 e8             	mov    %r13,%rax
 384:	4d 8b 46 10          	mov    0x10(%r14),%r8
 388:	48 89 d1             	mov    %rdx,%rcx
 38b:	48 0f af c2          	imul   %rdx,%rax
 38f:	48 29 d9             	sub    %rbx,%rcx
 392:	49 83 c0 10          	add    $0x10,%r8
 396:	48 83 e9 04          	sub    $0x4,%rcx
 39a:	4c 01 c0             	add    %r8,%rax
 39d:	0f b6 70 fc          	movzbl -0x4(%rax),%esi
 3a1:	48 8d 7c 10 fc       	lea    -0x4(%rax,%rdx,1),%rdi
 3a6:	40 84 f6             	test   %sil,%sil
 3a9:	0f 85 00 00 00 00    	jne    3af <__libc_malloc_impl+0x3af>
			3ab: R_X86_64_PC32	.text.unlikely.__libc_malloc_impl-0x4
 3af:	48 83 f9 0f          	cmp    $0xf,%rcx
 3b3:	76 7b                	jbe    430 <__libc_malloc_impl+0x430>
 3b5:	80 78 fd 00          	cmpb   $0x0,-0x3(%rax)
 3b9:	40 0f b6 d5          	movzbl %bpl,%edx
 3bd:	74 0a                	je     3c9 <__libc_malloc_impl+0x3c9>
 3bf:	0f b7 50 fe          	movzwl -0x2(%rax),%edx
 3c3:	83 c2 01             	add    $0x1,%edx
 3c6:	0f b6 d2             	movzbl %dl,%edx
 3c9:	49 89 ca             	mov    %rcx,%r10
 3cc:	4c 63 ca             	movslq %edx,%r9
 3cf:	49 c1 ea 04          	shr    $0x4,%r10
 3d3:	4d 39 ca             	cmp    %r9,%r10
 3d6:	73 37                	jae    40f <__libc_malloc_impl+0x40f>
 3d8:	48 c1 e9 05          	shr    $0x5,%rcx
 3dc:	4c 09 d1             	or     %r10,%rcx
 3df:	49 89 c9             	mov    %rcx,%r9
 3e2:	49 c1 e9 02          	shr    $0x2,%r9
 3e6:	4c 09 c9             	or     %r9,%rcx
 3e9:	49 89 c9             	mov    %rcx,%r9
 3ec:	49 c1 e9 04          	shr    $0x4,%r9
 3f0:	4c 09 c9             	or     %r9,%rcx
 3f3:	21 ca                	and    %ecx,%edx
 3f5:	48 63 ca             	movslq %edx,%rcx
 3f8:	49 39 ca             	cmp    %rcx,%r10
 3fb:	73 12                	jae    40f <__libc_malloc_impl+0x40f>
 3fd:	44 29 d2             	sub    %r10d,%edx
 400:	83 ea 01             	sub    $0x1,%edx
 403:	48 63 ca             	movslq %edx,%rcx
 406:	49 39 ca             	cmp    %rcx,%r10
 409:	0f 82 00 00 00 00    	jb     40f <__libc_malloc_impl+0x40f>
			40b: R_X86_64_PC32	.text.unlikely.__libc_malloc_impl-0x4
 40f:	85 d2                	test   %edx,%edx
 411:	74 1d                	je     430 <__libc_malloc_impl+0x430>
 413:	66 89 50 fe          	mov    %dx,-0x2(%rax)
 417:	c1 e2 04             	shl    $0x4,%edx
 41a:	48 63 ca             	movslq %edx,%rcx
 41d:	c6 40 fd e0          	movb   $0xe0,-0x3(%rax)
 421:	48 01 c8             	add    %rcx,%rax
 424:	c6 40 fc 00          	movb   $0x0,-0x4(%rax)
 428:	4d 8b 46 10          	mov    0x10(%r14),%r8
 42c:	49 83 c0 10          	add    $0x10,%r8
 430:	48 89 c2             	mov    %rax,%rdx
 433:	48 89 f9             	mov    %rdi,%rcx
 436:	4c 29 c2             	sub    %r8,%rdx
 439:	48 29 c1             	sub    %rax,%rcx
 43c:	48 c1 ea 04          	shr    $0x4,%rdx
 440:	66 89 50 fe          	mov    %dx,-0x2(%rax)
 444:	29 d9                	sub    %ebx,%ecx
 446:	74 15                	je     45d <__libc_malloc_impl+0x45d>
 448:	89 ca                	mov    %ecx,%edx
 44a:	f7 da                	neg    %edx
 44c:	48 63 d2             	movslq %edx,%rdx
 44f:	c6 04 17 00          	movb   $0x0,(%rdi,%rdx,1)
 453:	83 f9 04             	cmp    $0x4,%ecx
 456:	7f 15                	jg     46d <__libc_malloc_impl+0x46d>
 458:	89 ce                	mov    %ecx,%esi
 45a:	c1 e6 05             	shl    $0x5,%esi
 45d:	42 8d 14 26          	lea    (%rsi,%r12,1),%edx
 461:	88 50 fd             	mov    %dl,-0x3(%rax)
 464:	5b                   	pop    %rbx
 465:	5d                   	pop    %rbp
 466:	41 5c                	pop    %r12
 468:	41 5d                	pop    %r13
 46a:	41 5e                	pop    %r14
 46c:	c3                   	ret
 46d:	89 4f fc             	mov    %ecx,-0x4(%rdi)
 470:	be a0 ff ff ff       	mov    $0xffffffa0,%esi
 475:	c6 47 fb 00          	movb   $0x0,-0x5(%rdi)
 479:	eb e2                	jmp    45d <__libc_malloc_impl+0x45d>

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

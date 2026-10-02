
/Users/alex/code/vinix/third_party/useralloc-libc/build/musl/x86_64/5bc37f7d5dd563a40ea61404bac87cfda4c114030933317e53acedd4328fa099/objects/obj/src/malloc/mallocng/malloc.o:     file format elf64-x86-64


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
  2d:	0f 85 cc 01 00 00    	jne    1ff <alloc_slot+0x1ff>
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
  7e:	47 0f b7 ac 36 00 00 	movzwl 0x0(%r14,%r14,1),%r13d
  85:	00 00 
			83: R_X86_64_32S	__malloc_size_classes
  87:	48 89 7c 24 08       	mov    %rdi,0x8(%rsp)
  8c:	e8 00 00 00 00       	call   91 <alloc_slot+0x91>
			8d: R_X86_64_PLT32	__malloc_alloc_meta-0x4
  91:	66 48 0f 6e c8       	movq   %rax,%xmm1
  96:	41 c1 e5 04          	shl    $0x4,%r13d
  9a:	48 89 c5             	mov    %rax,%rbp
  9d:	66 0f 6c c9          	punpcklqdq %xmm1,%xmm1
  a1:	4d 63 ed             	movslq %r13d,%r13
  a4:	0f 29 4c 24 10       	movaps %xmm1,0x10(%rsp)
  a9:	48 85 c0             	test   %rax,%rax
  ac:	0f 84 f9 06 00 00    	je     7ab <alloc_slot+0x7ab>
  b2:	41 83 fc 08          	cmp    $0x8,%r12d
  b6:	4a 8b 14 f5 00 00 00 	mov    0x0(,%r14,8),%rdx
  bd:	00 
			ba: R_X86_64_32S	__malloc_context+0x1f8
  be:	48 8b 7c 24 08       	mov    0x8(%rsp),%rdi
  c3:	0f 8f 0d 02 00 00    	jg     2d6 <alloc_slot+0x2d6>
  c9:	4b 8d 04 76          	lea    (%r14,%r14,2),%rax
  cd:	0f b6 98 00 00 00 00 	movzbl 0x0(%rax),%ebx
			d0: R_X86_64_32S	.rodata.small_cnt_tab
  d4:	48 8d 88 00 00 00 00 	lea    0x0(%rax),%rcx
			d7: R_X86_64_32S	.rodata.small_cnt_tab
  db:	8d 04 9d 00 00 00 00 	lea    0x0(,%rbx,4),%eax
  e2:	48 98                	cltq
  e4:	48 39 c2             	cmp    %rax,%rdx
  e7:	0f 83 44 02 00 00    	jae    331 <alloc_slot+0x331>
  ed:	0f b6 59 01          	movzbl 0x1(%rcx),%ebx
  f1:	8d 04 9d 00 00 00 00 	lea    0x0(,%rbx,4),%eax
  f8:	48 98                	cltq
  fa:	48 39 c2             	cmp    %rax,%rdx
  fd:	0f 83 2e 02 00 00    	jae    331 <alloc_slot+0x331>
 103:	0f b6 59 02          	movzbl 0x2(%rcx),%ebx
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
 142:	8b 72 1c             	mov    0x1c(%rdx),%esi
 145:	d3 e0                	shl    %cl,%eax
 147:	83 e8 01             	sub    $0x1,%eax
 14a:	39 c6                	cmp    %eax,%esi
 14c:	0f 84 d3 00 00 00    	je     225 <alloc_slot+0x225>
 152:	4c 8b 42 10          	mov    0x10(%rdx),%r8
 156:	b8 02 00 00 00       	mov    $0x2,%eax
 15b:	41 0f b6 48 08       	movzbl 0x8(%r8),%ecx
 160:	d3 e0                	shl    %cl,%eax
 162:	41 89 ca             	mov    %ecx,%r10d
 165:	83 e8 01             	sub    $0x1,%eax
 168:	41 83 e2 1f          	and    $0x1f,%r10d
 16c:	85 f0                	test   %esi,%eax
 16e:	75 18                	jne    188 <alloc_slot+0x188>
 170:	4c 8b 4a 08          	mov    0x8(%rdx),%r9
 174:	4c 39 ca             	cmp    %r9,%rdx
 177:	0f 84 c5 00 00 00    	je     242 <alloc_slot+0x242>
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
 23a:	8b 72 1c             	mov    0x1c(%rdx),%esi
 23d:	e9 10 ff ff ff       	jmp    152 <alloc_slot+0x152>
 242:	41 0f b7 41 20       	movzwl 0x20(%r9),%eax
 247:	41 8d 4a 02          	lea    0x2(%r10),%ecx
 24b:	89 ca                	mov    %ecx,%edx
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
 2b9:	e9 c7 fe ff ff       	jmp    185 <alloc_slot+0x185>
 2be:	8b 4a 1c             	mov    0x1c(%rdx),%ecx
 2c1:	89 ce                	mov    %ecx,%esi
 2c3:	89 c8                	mov    %ecx,%eax
 2c5:	44 21 ce             	and    %r9d,%esi
 2c8:	f0 41 0f b1 32       	lock cmpxchg %esi,(%r10)
 2cd:	39 c1                	cmp    %eax,%ecx
 2cf:	75 ed                	jne    2be <alloc_slot+0x2be>
 2d1:	e9 f2 fe ff ff       	jmp    1c8 <alloc_slot+0x1c8>
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
 34a:	0f 86 7f 03 00 00    	jbe    6cf <alloc_slot+0x6cf>
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
 5ae:	e9 63 fc ff ff       	jmp    216 <alloc_slot+0x216>
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
 6b3:	0f 85 dc 00 00 00    	jne    795 <alloc_slot+0x795>
 6b9:	66 0f 6f 5c 24 10    	movdqa 0x10(%rsp),%xmm3
 6bf:	0f 11 5d 00          	movups %xmm3,0x0(%rbp)
 6c3:	48 89 2d 00 00 00 00 	mov    %rbp,0x0(%rip)        # 6ca <alloc_slot+0x6ca>
			6c6: R_X86_64_PC32	__malloc_context+0xc
 6ca:	e9 dc 00 00 00       	jmp    7ab <alloc_slot+0x7ab>
 6cf:	48 89 c8             	mov    %rcx,%rax
 6d2:	48 8d 71 0c          	lea    0xc(%rcx),%rsi
 6d6:	48 c1 e8 04          	shr    $0x4,%rax
 6da:	48 81 f9 90 00 00 00 	cmp    $0x90,%rcx
 6e1:	0f 86 8a 00 00 00    	jbe    771 <alloc_slot+0x771>
 6e7:	48 83 c0 01          	add    $0x1,%rax
 6eb:	0f bd d0             	bsr    %eax,%edx
 6ee:	8d 0c 95 fc ff ff ff 	lea    -0x4(,%rdx,4),%ecx
 6f5:	8d 51 01             	lea    0x1(%rcx),%edx
 6f8:	48 63 d2             	movslq %edx,%rdx
 6fb:	0f b7 bc 12 00 00 00 	movzwl 0x0(%rdx,%rdx,1),%edi
 702:	00 
			6ff: R_X86_64_32S	__malloc_size_classes
 703:	8d 51 02             	lea    0x2(%rcx),%edx
 706:	48 39 c7             	cmp    %rax,%rdi
 709:	0f 42 ca             	cmovb  %edx,%ecx
 70c:	48 63 d1             	movslq %ecx,%rdx
 70f:	0f b7 94 12 00 00 00 	movzwl 0x0(%rdx,%rdx,1),%edx
 716:	00 
			713: R_X86_64_32S	__malloc_size_classes
 717:	48 39 c2             	cmp    %rax,%rdx
 71a:	83 d1 00             	adc    $0x0,%ecx
 71d:	89 cf                	mov    %ecx,%edi
 71f:	89 4c 24 08          	mov    %ecx,0x8(%rsp)
 723:	e8 d8 f8 ff ff       	call   0 <alloc_slot>
 728:	48 63 4c 24 08       	movslq 0x8(%rsp),%rcx
 72d:	83 f8 ff             	cmp    $0xffffffff,%eax
 730:	89 c2                	mov    %eax,%edx
 732:	74 41                	je     775 <alloc_slot+0x775>
 734:	0f b7 84 09 00 00 00 	movzwl 0x0(%rcx,%rcx,1),%eax
 73b:	00 
			738: R_X86_64_32S	__malloc_size_classes
 73c:	48 8b 3c cd 00 00 00 	mov    0x0(,%rcx,8),%rdi
 743:	00 
			740: R_X86_64_32S	__malloc_context+0x50
 744:	c1 e0 04             	shl    $0x4,%eax
 747:	83 e8 04             	sub    $0x4,%eax
 74a:	89 44 24 08          	mov    %eax,0x8(%rsp)
 74e:	48 63 c8             	movslq %eax,%rcx
 751:	f6 47 20 1f          	testb  $0x1f,0x20(%rdi)
 755:	75 71                	jne    7c8 <alloc_slot+0x7c8>
 757:	48 81 7f 20 ff 0f 00 	cmpq   $0xfff,0x20(%rdi)
 75e:	00 
 75f:	76 67                	jbe    7c8 <alloc_slot+0x7c8>
 761:	48 8b 47 20          	mov    0x20(%rdi),%rax
 765:	48 25 00 f0 ff ff    	and    $0xfffffffffffff000,%rax
 76b:	48 83 e8 10          	sub    $0x10,%rax
 76f:	eb 6f                	jmp    7e0 <alloc_slot+0x7e0>
 771:	89 c1                	mov    %eax,%ecx
 773:	eb a8                	jmp    71d <alloc_slot+0x71d>
 775:	66 0f ef c0          	pxor   %xmm0,%xmm0
 779:	48 c7 45 20 00 00 00 	movq   $0x0,0x20(%rbp)
 780:	00 
 781:	0f 11 45 00          	movups %xmm0,0x0(%rbp)
 785:	0f 11 45 10          	movups %xmm0,0x10(%rbp)
 789:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 790 <alloc_slot+0x790>
			78c: R_X86_64_PC32	__malloc_context+0xc
 790:	48 85 c0             	test   %rax,%rax
 793:	74 20                	je     7b5 <alloc_slot+0x7b5>
 795:	48 89 45 08          	mov    %rax,0x8(%rbp)
 799:	48 8b 00             	mov    (%rax),%rax
 79c:	48 89 45 00          	mov    %rax,0x0(%rbp)
 7a0:	48 89 68 08          	mov    %rbp,0x8(%rax)
 7a4:	48 8b 45 08          	mov    0x8(%rbp),%rax
 7a8:	48 89 28             	mov    %rbp,(%rax)
 7ab:	b8 ff ff ff ff       	mov    $0xffffffff,%eax
 7b0:	e9 61 fa ff ff       	jmp    216 <alloc_slot+0x216>
 7b5:	66 0f 6f 64 24 10    	movdqa 0x10(%rsp),%xmm4
 7bb:	0f 11 65 00          	movups %xmm4,0x0(%rbp)
 7bf:	48 89 2d 00 00 00 00 	mov    %rbp,0x0(%rip)        # 7c6 <alloc_slot+0x7c6>
			7c2: R_X86_64_PC32	__malloc_context+0xc
 7c6:	eb e3                	jmp    7ab <alloc_slot+0x7ab>
 7c8:	0f b7 47 20          	movzwl 0x20(%rdi),%eax
 7cc:	66 c1 e8 06          	shr    $0x6,%ax
 7d0:	83 e0 3f             	and    $0x3f,%eax
 7d3:	0f b7 84 00 00 00 00 	movzwl 0x0(%rax,%rax,1),%eax
 7da:	00 
			7d7: R_X86_64_32S	__malloc_size_classes
 7db:	c1 e0 04             	shl    $0x4,%eax
 7de:	48 98                	cltq
 7e0:	48 89 c6             	mov    %rax,%rsi
 7e3:	48 29 ce             	sub    %rcx,%rsi
 7e6:	48 8b 4f 10          	mov    0x10(%rdi),%rcx
 7ea:	4c 8d 46 fc          	lea    -0x4(%rsi),%r8
 7ee:	48 63 f2             	movslq %edx,%rsi
 7f1:	48 0f af f0          	imul   %rax,%rsi
 7f5:	48 83 c1 10          	add    $0x10,%rcx
 7f9:	4d 89 c1             	mov    %r8,%r9
 7fc:	49 c1 e9 04          	shr    $0x4,%r9
 800:	48 01 ce             	add    %rcx,%rsi
 803:	80 7e fd 00          	cmpb   $0x0,-0x3(%rsi)
 807:	4c 8d 54 06 fc       	lea    -0x4(%rsi,%rax,1),%r10
 80c:	0f 84 d2 00 00 00    	je     8e4 <alloc_slot+0x8e4>
 812:	0f b7 46 fe          	movzwl -0x2(%rsi),%eax
 816:	83 c0 01             	add    $0x1,%eax
 819:	0f b6 c0             	movzbl %al,%eax
 81c:	80 7e fc 00          	cmpb   $0x0,-0x4(%rsi)
 820:	0f 85 00 00 00 00    	jne    826 <alloc_slot+0x826>
			822: R_X86_64_PC32	.text.unlikely.alloc_slot-0x4
 826:	4c 63 d8             	movslq %eax,%r11
 829:	4d 39 d9             	cmp    %r11,%r9
 82c:	73 38                	jae    866 <alloc_slot+0x866>
 82e:	49 c1 e8 05          	shr    $0x5,%r8
 832:	4d 09 c8             	or     %r9,%r8
 835:	4d 89 c3             	mov    %r8,%r11
 838:	49 c1 eb 02          	shr    $0x2,%r11
 83c:	4d 09 d8             	or     %r11,%r8
 83f:	4d 89 c3             	mov    %r8,%r11
 842:	49 c1 eb 04          	shr    $0x4,%r11
 846:	4d 09 d8             	or     %r11,%r8
 849:	44 21 c0             	and    %r8d,%eax
 84c:	4c 63 c0             	movslq %eax,%r8
 84f:	4d 39 c1             	cmp    %r8,%r9
 852:	73 12                	jae    866 <alloc_slot+0x866>
 854:	44 29 c8             	sub    %r9d,%eax
 857:	83 e8 01             	sub    $0x1,%eax
 85a:	4c 63 c0             	movslq %eax,%r8
 85d:	4d 39 c1             	cmp    %r8,%r9
 860:	0f 82 00 00 00 00    	jb     866 <alloc_slot+0x866>
			862: R_X86_64_PC32	.text.unlikely.alloc_slot-0x4
 866:	85 c0                	test   %eax,%eax
 868:	74 1c                	je     886 <alloc_slot+0x886>
 86a:	66 89 46 fe          	mov    %ax,-0x2(%rsi)
 86e:	c1 e0 04             	shl    $0x4,%eax
 871:	48 98                	cltq
 873:	c6 46 fd e0          	movb   $0xe0,-0x3(%rsi)
 877:	48 01 c6             	add    %rax,%rsi
 87a:	c6 46 fc 00          	movb   $0x0,-0x4(%rsi)
 87e:	48 8b 4f 10          	mov    0x10(%rdi),%rcx
 882:	48 83 c1 10          	add    $0x10,%rcx
 886:	48 89 f0             	mov    %rsi,%rax
 889:	8b 7c 24 08          	mov    0x8(%rsp),%edi
 88d:	88 56 fd             	mov    %dl,-0x3(%rsi)
 890:	48 29 c8             	sub    %rcx,%rax
 893:	89 d1                	mov    %edx,%ecx
 895:	48 c1 e8 04          	shr    $0x4,%rax
 899:	66 89 46 fe          	mov    %ax,-0x2(%rsi)
 89d:	4c 89 d0             	mov    %r10,%rax
 8a0:	48 29 f0             	sub    %rsi,%rax
 8a3:	29 f8                	sub    %edi,%eax
 8a5:	74 1d                	je     8c4 <alloc_slot+0x8c4>
 8a7:	89 c2                	mov    %eax,%edx
 8a9:	f7 da                	neg    %edx
 8ab:	48 63 d2             	movslq %edx,%rdx
 8ae:	41 c6 04 12 00       	movb   $0x0,(%r10,%rdx,1)
 8b3:	83 f8 04             	cmp    $0x4,%eax
 8b6:	7f 38                	jg     8f0 <alloc_slot+0x8f0>
 8b8:	0f b6 4e fd          	movzbl -0x3(%rsi),%ecx
 8bc:	c1 e0 05             	shl    $0x5,%eax
 8bf:	83 e1 1f             	and    $0x1f,%ecx
 8c2:	01 c1                	add    %eax,%ecx
 8c4:	88 4e fd             	mov    %cl,-0x3(%rsi)
 8c7:	48 8d 56 0c          	lea    0xc(%rsi),%rdx
 8cb:	48 81 65 20 ff 0f 00 	andq   $0xfff,0x20(%rbp)
 8d2:	00 
 8d3:	0f b6 46 fd          	movzbl -0x3(%rsi),%eax
 8d7:	83 e0 1f             	and    $0x1f,%eax
 8da:	83 c8 c0             	or     $0xffffffc0,%eax
 8dd:	88 46 fd             	mov    %al,-0x3(%rsi)
 8e0:	31 c0                	xor    %eax,%eax
 8e2:	eb 35                	jmp    919 <alloc_slot+0x919>
 8e4:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 8eb <alloc_slot+0x8eb>
			8e7: R_X86_64_PC32	__malloc_context+0x8
 8eb:	e9 2c ff ff ff       	jmp    81c <alloc_slot+0x81c>
 8f0:	41 89 42 fc          	mov    %eax,-0x4(%r10)
 8f4:	41 c6 42 fb 00       	movb   $0x0,-0x5(%r10)
 8f9:	0f b6 4e fd          	movzbl -0x3(%rsi),%ecx
 8fd:	83 e1 1f             	and    $0x1f,%ecx
 900:	83 e9 60             	sub    $0x60,%ecx
 903:	eb bf                	jmp    8c4 <alloc_slot+0x8c4>
 905:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
 90c:	00 00 00 00 
 910:	c6 02 00             	movb   $0x0,(%rdx)
 913:	83 c0 01             	add    $0x1,%eax
 916:	4c 01 ea             	add    %r13,%rdx
 919:	39 c3                	cmp    %eax,%ebx
 91b:	7d f3                	jge    910 <alloc_slot+0x910>
 91d:	8d 53 ff             	lea    -0x1(%rbx),%edx
 920:	89 d7                	mov    %edx,%edi
 922:	e9 ce fb ff ff       	jmp    4f5 <alloc_slot+0x4f5>
 927:	66 0f 6f 54 24 10    	movdqa 0x10(%rsp),%xmm2
 92d:	0f 11 55 00          	movups %xmm2,0x0(%rbp)
 931:	4a 89 2c f5 00 00 00 	mov    %rbp,0x0(,%r14,8)
 938:	00 
			935: R_X86_64_32S	__malloc_context
 939:	e9 6e fc ff ff       	jmp    5ac <alloc_slot+0x5ac>

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
  15:	0f 82 10 01 00 00    	jb     12b <__libc_malloc_impl+0x12b>
  1b:	48 89 fd             	mov    %rdi,%rbp
  1e:	48 81 ff eb ff 01 00 	cmp    $0x1ffeb,%rdi
  25:	0f 87 12 01 00 00    	ja     13d <__libc_malloc_impl+0x13d>
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
  8a:	0f 85 b3 01 00 00    	jne    243 <__libc_malloc_impl+0x243>
  90:	4e 8b 24 ed 00 00 00 	mov    0x0(,%r13,8),%r12
  97:	00 
			94: R_X86_64_32S	__malloc_context+0x50
  98:	4d 85 e4             	test   %r12,%r12
  9b:	0f 85 e0 01 00 00    	jne    281 <__libc_malloc_impl+0x281>
  a1:	83 fb 03             	cmp    $0x3,%ebx
  a4:	0f 8e ce 01 00 00    	jle    278 <__libc_malloc_impl+0x278>
  aa:	83 fb 1f             	cmp    $0x1f,%ebx
  ad:	7f 4d                	jg     fc <__libc_malloc_impl+0xfc>
  af:	83 fb 06             	cmp    $0x6,%ebx
  b2:	74 48                	je     fc <__libc_malloc_impl+0xfc>
  b4:	f6 c3 01             	test   $0x1,%bl
  b7:	75 43                	jne    fc <__libc_malloc_impl+0xfc>
  b9:	4a 83 3c ed 00 00 00 	cmpq   $0x0,0x0(,%r13,8)
  c0:	00 00 
			bd: R_X86_64_32S	__malloc_context+0x1f8
  c2:	75 38                	jne    fc <__libc_malloc_impl+0xfc>
  c4:	89 d9                	mov    %ebx,%ecx
  c6:	83 c9 01             	or     $0x1,%ecx
  c9:	48 63 c1             	movslq %ecx,%rax
  cc:	4c 8b 24 c5 00 00 00 	mov    0x0(,%rax,8),%r12
  d3:	00 
			d0: R_X86_64_32S	__malloc_context+0x50
  d4:	48 8b 14 c5 00 00 00 	mov    0x0(,%rax,8),%rdx
  db:	00 
			d8: R_X86_64_32S	__malloc_context+0x1f8
  dc:	4d 85 e4             	test   %r12,%r12
  df:	0f 84 83 01 00 00    	je     268 <__libc_malloc_impl+0x268>
  e5:	41 8b 44 24 18       	mov    0x18(%r12),%eax
  ea:	85 c0                	test   %eax,%eax
  ec:	0f 84 60 01 00 00    	je     252 <__libc_malloc_impl+0x252>
  f2:	48 83 fa 0c          	cmp    $0xc,%rdx
  f6:	0f 86 e1 01 00 00    	jbe    2dd <__libc_malloc_impl+0x2dd>
  fc:	48 89 ee             	mov    %rbp,%rsi
  ff:	89 df                	mov    %ebx,%edi
 101:	e8 00 00 00 00       	call   106 <__libc_malloc_impl+0x106>
			102: R_X86_64_PC32	.text.alloc_slot-0x4
 106:	41 89 c5             	mov    %eax,%r13d
 109:	83 f8 ff             	cmp    $0xffffffff,%eax
 10c:	0f 84 cf 01 00 00    	je     2e1 <__libc_malloc_impl+0x2e1>
 112:	48 63 db             	movslq %ebx,%rbx
 115:	4c 63 f0             	movslq %eax,%r14
 118:	4c 8b 24 dd 00 00 00 	mov    0x0(,%rbx,8),%r12
 11f:	00 
			11c: R_X86_64_32S	__malloc_context+0x50
 120:	8b 1d 00 00 00 00    	mov    0x0(%rip),%ebx        # 126 <__libc_malloc_impl+0x126>
			122: R_X86_64_PC32	__malloc_context+0x8
 126:	e9 83 01 00 00       	jmp    2ae <__libc_malloc_impl+0x2ae>
 12b:	e8 00 00 00 00       	call   130 <__libc_malloc_impl+0x130>
			12c: R_X86_64_PLT32	___errno_location-0x4
 130:	c7 00 0c 00 00 00    	movl   $0xc,(%rax)
 136:	31 c0                	xor    %eax,%eax
 138:	e9 cd 02 00 00       	jmp    40a <__libc_malloc_impl+0x40a>
 13d:	4c 8d 77 14          	lea    0x14(%rdi),%r14
 141:	4c 8d af 13 10 00 00 	lea    0x1013(%rdi),%r13
 148:	45 31 c9             	xor    %r9d,%r9d
 14b:	31 ff                	xor    %edi,%edi
 14d:	41 b8 ff ff ff ff    	mov    $0xffffffff,%r8d
 153:	b9 22 00 00 00       	mov    $0x22,%ecx
 158:	ba 03 00 00 00       	mov    $0x3,%edx
 15d:	4c 89 f6             	mov    %r14,%rsi
 160:	e8 00 00 00 00       	call   165 <__libc_malloc_impl+0x165>
			161: R_X86_64_PLT32	__mmap-0x4
 165:	48 89 c3             	mov    %rax,%rbx
 168:	48 83 f8 ff          	cmp    $0xffffffffffffffff,%rax
 16c:	74 c8                	je     136 <__libc_malloc_impl+0x136>
 16e:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 175 <__libc_malloc_impl+0x175>
			171: R_X86_64_PC32	__libc-0x1
 175:	84 c0                	test   %al,%al
 177:	75 66                	jne    1df <__libc_malloc_impl+0x1df>
 179:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 180 <__libc_malloc_impl+0x180>
			17c: R_X86_64_PC32	__malloc_context+0x3b4
 180:	8d 50 01             	lea    0x1(%rax),%edx
 183:	3c ff                	cmp    $0xff,%al
 185:	74 64                	je     1eb <__libc_malloc_impl+0x1eb>
 187:	88 15 00 00 00 00    	mov    %dl,0x0(%rip)        # 18d <__libc_malloc_impl+0x18d>
			189: R_X86_64_PC32	__malloc_context+0x3b4
 18d:	e8 00 00 00 00       	call   192 <__libc_malloc_impl+0x192>
			18e: R_X86_64_PLT32	__malloc_alloc_meta-0x4
 192:	49 89 c4             	mov    %rax,%r12
 195:	48 85 c0             	test   %rax,%rax
 198:	0f 84 7f 00 00 00    	je     21d <__libc_malloc_impl+0x21d>
 19e:	49 81 e5 00 f0 ff ff 	and    $0xfffffffffffff000,%r13
 1a5:	48 89 58 10          	mov    %rbx,0x10(%rax)
 1a9:	45 31 f6             	xor    %r14d,%r14d
 1ac:	49 81 cd e0 0f 00 00 	or     $0xfe0,%r13
 1b3:	48 89 03             	mov    %rax,(%rbx)
 1b6:	4c 89 68 20          	mov    %r13,0x20(%rax)
 1ba:	45 31 ed             	xor    %r13d,%r13d
 1bd:	c7 40 1c 00 00 00 00 	movl   $0x0,0x1c(%rax)
 1c4:	c7 40 18 00 00 00 00 	movl   $0x0,0x18(%rax)
 1cb:	8b 05 00 00 00 00    	mov    0x0(%rip),%eax        # 1d1 <__libc_malloc_impl+0x1d1>
			1cd: R_X86_64_PC32	__malloc_context+0x8
 1d1:	8d 58 01             	lea    0x1(%rax),%ebx
 1d4:	89 1d 00 00 00 00    	mov    %ebx,0x0(%rip)        # 1da <__libc_malloc_impl+0x1da>
			1d6: R_X86_64_PC32	__malloc_context+0x8
 1da:	e9 cf 00 00 00       	jmp    2ae <__libc_malloc_impl+0x2ae>
 1df:	bf 00 00 00 00       	mov    $0x0,%edi
			1e0: R_X86_64_32	__malloc_lock
 1e4:	e8 00 00 00 00       	call   1e9 <__libc_malloc_impl+0x1e9>
			1e5: R_X86_64_PLT32	__lock-0x4
 1e9:	eb 8e                	jmp    179 <__libc_malloc_impl+0x179>
 1eb:	b8 00 00 00 00       	mov    $0x0,%eax
			1ec: R_X86_64_32	__malloc_context+0x378
 1f0:	eb 19                	jmp    20b <__libc_malloc_impl+0x20b>
 1f2:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
 1f9:	00 00 00 00 
 1fd:	0f 1f 00             	nopl   (%rax)
 200:	c6 00 00             	movb   $0x0,(%rax)
 203:	48 83 c0 02          	add    $0x2,%rax
 207:	c6 40 ff 00          	movb   $0x0,-0x1(%rax)
 20b:	48 3d 00 00 00 00    	cmp    $0x0,%rax
			20d: R_X86_64_32S	__malloc_context+0x398
 211:	75 ed                	jne    200 <__libc_malloc_impl+0x200>
 213:	ba 01 00 00 00       	mov    $0x1,%edx
 218:	e9 6a ff ff ff       	jmp    187 <__libc_malloc_impl+0x187>
 21d:	8b 05 00 00 00 00    	mov    0x0(%rip),%eax        # 223 <__libc_malloc_impl+0x223>
			21f: R_X86_64_PC32	__malloc_lock-0x4
 223:	85 c0                	test   %eax,%eax
 225:	78 10                	js     237 <__libc_malloc_impl+0x237>
 227:	4c 89 f6             	mov    %r14,%rsi
 22a:	48 89 df             	mov    %rbx,%rdi
 22d:	e8 00 00 00 00       	call   232 <__libc_malloc_impl+0x232>
			22e: R_X86_64_PLT32	munmap-0x4
 232:	e9 ff fe ff ff       	jmp    136 <__libc_malloc_impl+0x136>
 237:	bf 00 00 00 00       	mov    $0x0,%edi
			238: R_X86_64_32	__malloc_lock
 23c:	e8 00 00 00 00       	call   241 <__libc_malloc_impl+0x241>
			23d: R_X86_64_PLT32	__unlock-0x4
 241:	eb e4                	jmp    227 <__libc_malloc_impl+0x227>
 243:	bf 00 00 00 00       	mov    $0x0,%edi
			244: R_X86_64_32	__malloc_lock
 248:	e8 00 00 00 00       	call   24d <__libc_malloc_impl+0x24d>
			249: R_X86_64_PLT32	__lock-0x4
 24d:	e9 3e fe ff ff       	jmp    90 <__libc_malloc_impl+0x90>
 252:	41 8b 44 24 1c       	mov    0x1c(%r12),%eax
 257:	85 c0                	test   %eax,%eax
 259:	0f 85 93 fe ff ff    	jne    f2 <__libc_malloc_impl+0xf2>
 25f:	48 83 c2 03          	add    $0x3,%rdx
 263:	e9 8a fe ff ff       	jmp    f2 <__libc_malloc_impl+0xf2>
 268:	48 83 c2 03          	add    $0x3,%rdx
 26c:	48 83 fa 0c          	cmp    $0xc,%rdx
 270:	0f 46 d9             	cmovbe %ecx,%ebx
 273:	e9 84 fe ff ff       	jmp    fc <__libc_malloc_impl+0xfc>
 278:	4d 85 e4             	test   %r12,%r12
 27b:	0f 84 7b fe ff ff    	je     fc <__libc_malloc_impl+0xfc>
 281:	41 8b 44 24 18       	mov    0x18(%r12),%eax
 286:	41 89 c5             	mov    %eax,%r13d
 289:	41 f7 dd             	neg    %r13d
 28c:	41 21 c5             	and    %eax,%r13d
 28f:	0f 84 67 fe ff ff    	je     fc <__libc_malloc_impl+0xfc>
 295:	44 29 e8             	sub    %r13d,%eax
 298:	45 31 f6             	xor    %r14d,%r14d
 29b:	8b 1d 00 00 00 00    	mov    0x0(%rip),%ebx        # 2a1 <__libc_malloc_impl+0x2a1>
			29d: R_X86_64_PC32	__malloc_context+0x8
 2a1:	41 89 44 24 18       	mov    %eax,0x18(%r12)
 2a6:	f3 45 0f bc f5       	tzcnt  %r13d,%r14d
 2ab:	4d 89 f5             	mov    %r14,%r13
 2ae:	8b 15 00 00 00 00    	mov    0x0(%rip),%edx        # 2b4 <__libc_malloc_impl+0x2b4>
			2b0: R_X86_64_PC32	__malloc_lock-0x4
 2b4:	85 d2                	test   %edx,%edx
 2b6:	78 46                	js     2fe <__libc_malloc_impl+0x2fe>
 2b8:	41 f6 44 24 20 1f    	testb  $0x1f,0x20(%r12)
 2be:	75 4a                	jne    30a <__libc_malloc_impl+0x30a>
 2c0:	49 81 7c 24 20 ff 0f 	cmpq   $0xfff,0x20(%r12)
 2c7:	00 00 
 2c9:	76 3f                	jbe    30a <__libc_malloc_impl+0x30a>
 2cb:	49 8b 54 24 20       	mov    0x20(%r12),%rdx
 2d0:	48 81 e2 00 f0 ff ff 	and    $0xfffffffffffff000,%rdx
 2d7:	48 83 ea 10          	sub    $0x10,%rdx
 2db:	eb 48                	jmp    325 <__libc_malloc_impl+0x325>
 2dd:	89 cb                	mov    %ecx,%ebx
 2df:	eb a0                	jmp    281 <__libc_malloc_impl+0x281>
 2e1:	8b 05 00 00 00 00    	mov    0x0(%rip),%eax        # 2e7 <__libc_malloc_impl+0x2e7>
			2e3: R_X86_64_PC32	__malloc_lock-0x4
 2e7:	85 c0                	test   %eax,%eax
 2e9:	0f 89 47 fe ff ff    	jns    136 <__libc_malloc_impl+0x136>
 2ef:	bf 00 00 00 00       	mov    $0x0,%edi
			2f0: R_X86_64_32	__malloc_lock
 2f4:	e8 00 00 00 00       	call   2f9 <__libc_malloc_impl+0x2f9>
			2f5: R_X86_64_PLT32	__unlock-0x4
 2f9:	e9 38 fe ff ff       	jmp    136 <__libc_malloc_impl+0x136>
 2fe:	bf 00 00 00 00       	mov    $0x0,%edi
			2ff: R_X86_64_32	__malloc_lock
 303:	e8 00 00 00 00       	call   308 <__libc_malloc_impl+0x308>
			304: R_X86_64_PLT32	__unlock-0x4
 308:	eb ae                	jmp    2b8 <__libc_malloc_impl+0x2b8>
 30a:	41 0f b7 54 24 20    	movzwl 0x20(%r12),%edx
 310:	66 c1 ea 06          	shr    $0x6,%dx
 314:	83 e2 3f             	and    $0x3f,%edx
 317:	0f b7 94 12 00 00 00 	movzwl 0x0(%rdx,%rdx,1),%edx
 31e:	00 
			31b: R_X86_64_32S	__malloc_size_classes
 31f:	c1 e2 04             	shl    $0x4,%edx
 322:	48 63 d2             	movslq %edx,%rdx
 325:	4c 89 f0             	mov    %r14,%rax
 328:	48 89 d1             	mov    %rdx,%rcx
 32b:	49 8b 74 24 10       	mov    0x10(%r12),%rsi
 330:	48 0f af c2          	imul   %rdx,%rax
 334:	48 29 e9             	sub    %rbp,%rcx
 337:	48 83 e9 04          	sub    $0x4,%rcx
 33b:	48 83 c6 10          	add    $0x10,%rsi
 33f:	49 89 c8             	mov    %rcx,%r8
 342:	48 01 f0             	add    %rsi,%rax
 345:	49 c1 e8 04          	shr    $0x4,%r8
 349:	80 78 fd 00          	cmpb   $0x0,-0x3(%rax)
 34d:	48 8d 7c 10 fc       	lea    -0x4(%rax,%rdx,1),%rdi
 352:	0f b6 d3             	movzbl %bl,%edx
 355:	74 0a                	je     361 <__libc_malloc_impl+0x361>
 357:	0f b7 50 fe          	movzwl -0x2(%rax),%edx
 35b:	83 c2 01             	add    $0x1,%edx
 35e:	0f b6 d2             	movzbl %dl,%edx
 361:	80 78 fc 00          	cmpb   $0x0,-0x4(%rax)
 365:	0f 85 00 00 00 00    	jne    36b <__libc_malloc_impl+0x36b>
			367: R_X86_64_PC32	.text.unlikely.__libc_malloc_impl-0x4
 36b:	4c 63 ca             	movslq %edx,%r9
 36e:	4d 39 c8             	cmp    %r9,%r8
 371:	73 37                	jae    3aa <__libc_malloc_impl+0x3aa>
 373:	48 c1 e9 05          	shr    $0x5,%rcx
 377:	4c 09 c1             	or     %r8,%rcx
 37a:	49 89 c9             	mov    %rcx,%r9
 37d:	49 c1 e9 02          	shr    $0x2,%r9
 381:	4c 09 c9             	or     %r9,%rcx
 384:	49 89 c9             	mov    %rcx,%r9
 387:	49 c1 e9 04          	shr    $0x4,%r9
 38b:	4c 09 c9             	or     %r9,%rcx
 38e:	21 ca                	and    %ecx,%edx
 390:	48 63 ca             	movslq %edx,%rcx
 393:	49 39 c8             	cmp    %rcx,%r8
 396:	73 12                	jae    3aa <__libc_malloc_impl+0x3aa>
 398:	44 29 c2             	sub    %r8d,%edx
 39b:	83 ea 01             	sub    $0x1,%edx
 39e:	48 63 ca             	movslq %edx,%rcx
 3a1:	49 39 c8             	cmp    %rcx,%r8
 3a4:	0f 82 00 00 00 00    	jb     3aa <__libc_malloc_impl+0x3aa>
			3a6: R_X86_64_PC32	.text.unlikely.__libc_malloc_impl-0x4
 3aa:	85 d2                	test   %edx,%edx
 3ac:	74 1e                	je     3cc <__libc_malloc_impl+0x3cc>
 3ae:	66 89 50 fe          	mov    %dx,-0x2(%rax)
 3b2:	c1 e2 04             	shl    $0x4,%edx
 3b5:	48 63 d2             	movslq %edx,%rdx
 3b8:	c6 40 fd e0          	movb   $0xe0,-0x3(%rax)
 3bc:	48 01 d0             	add    %rdx,%rax
 3bf:	c6 40 fc 00          	movb   $0x0,-0x4(%rax)
 3c3:	49 8b 74 24 10       	mov    0x10(%r12),%rsi
 3c8:	48 83 c6 10          	add    $0x10,%rsi
 3cc:	48 89 c2             	mov    %rax,%rdx
 3cf:	44 88 68 fd          	mov    %r13b,-0x3(%rax)
 3d3:	44 89 e9             	mov    %r13d,%ecx
 3d6:	48 29 f2             	sub    %rsi,%rdx
 3d9:	48 c1 ea 04          	shr    $0x4,%rdx
 3dd:	66 89 50 fe          	mov    %dx,-0x2(%rax)
 3e1:	48 89 fa             	mov    %rdi,%rdx
 3e4:	48 29 c2             	sub    %rax,%rdx
 3e7:	29 ea                	sub    %ebp,%edx
 3e9:	74 1c                	je     407 <__libc_malloc_impl+0x407>
 3eb:	89 d1                	mov    %edx,%ecx
 3ed:	f7 d9                	neg    %ecx
 3ef:	48 63 c9             	movslq %ecx,%rcx
 3f2:	c6 04 0f 00          	movb   $0x0,(%rdi,%rcx,1)
 3f6:	83 fa 04             	cmp    $0x4,%edx
 3f9:	7f 18                	jg     413 <__libc_malloc_impl+0x413>
 3fb:	0f b6 48 fd          	movzbl -0x3(%rax),%ecx
 3ff:	c1 e2 05             	shl    $0x5,%edx
 402:	83 e1 1f             	and    $0x1f,%ecx
 405:	01 d1                	add    %edx,%ecx
 407:	88 48 fd             	mov    %cl,-0x3(%rax)
 40a:	5b                   	pop    %rbx
 40b:	5d                   	pop    %rbp
 40c:	41 5c                	pop    %r12
 40e:	41 5d                	pop    %r13
 410:	41 5e                	pop    %r14
 412:	c3                   	ret
 413:	89 57 fc             	mov    %edx,-0x4(%rdi)
 416:	c6 47 fb 00          	movb   $0x0,-0x5(%rdi)
 41a:	0f b6 48 fd          	movzbl -0x3(%rax),%ecx
 41e:	83 e1 1f             	and    $0x1f,%ecx
 421:	83 e9 60             	sub    $0x60,%ecx
 424:	eb e1                	jmp    407 <__libc_malloc_impl+0x407>

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
  d5:	77 43                	ja     11a <__malloc_allzerop+0x11a>
  d7:	31 c0                	xor    %eax,%eax
  d9:	c3                   	ret
  da:	e9 00 00 00 00       	jmp    df <__malloc_allzerop+0xdf>
			db: R_X86_64_PC32	.text.unlikely.__malloc_allzerop-0x4
  df:	f7 d6                	not    %esi
  e1:	66 f7 c6 c0 0f       	test   $0xfc0,%si
  e6:	75 10                	jne    f8 <__malloc_allzerop+0xf8>
  e8:	48 81 78 20 ff 0f 00 	cmpq   $0xfff,0x20(%rax)
  ef:	00 
  f0:	77 0b                	ja     fd <__malloc_allzerop+0xfd>
  f2:	b8 01 00 00 00       	mov    $0x1,%eax
  f7:	c3                   	ret
  f8:	e9 00 00 00 00       	jmp    fd <__malloc_allzerop+0xfd>
			f9: R_X86_64_PC32	.text.unlikely.__malloc_allzerop-0x4
  fd:	48 8b 50 20          	mov    0x20(%rax),%rdx
 101:	48 81 e2 00 f0 ff ff 	and    $0xfffffffffffff000,%rdx
 108:	48 c1 ea 04          	shr    $0x4,%rdx
 10c:	48 83 ea 01          	sub    $0x1,%rdx
 110:	48 39 ca             	cmp    %rcx,%rdx
 113:	73 dd                	jae    f2 <__malloc_allzerop+0xf2>
 115:	e9 00 00 00 00       	jmp    11a <__malloc_allzerop+0x11a>
			116: R_X86_64_PC32	.text.unlikely.__malloc_allzerop-0x4
 11a:	48 8b 50 20          	mov    0x20(%rax),%rdx
 11e:	48 63 c1             	movslq %ecx,%rax
 121:	48 81 e2 00 f0 ff ff 	and    $0xfffffffffffff000,%rdx
 128:	48 89 d1             	mov    %rdx,%rcx
 12b:	48 c1 e9 04          	shr    $0x4,%rcx
 12f:	48 83 e9 01          	sub    $0x1,%rcx
 133:	48 39 c1             	cmp    %rax,%rcx
 136:	72 1a                	jb     152 <__malloc_allzerop+0x152>
 138:	c1 e6 04             	shl    $0x4,%esi
 13b:	31 c0                	xor    %eax,%eax
 13d:	83 e7 1f             	and    $0x1f,%edi
 140:	48 63 f6             	movslq %esi,%rsi
 143:	75 12                	jne    157 <__malloc_allzerop+0x157>
 145:	48 83 ea 10          	sub    $0x10,%rdx
 149:	31 c0                	xor    %eax,%eax
 14b:	48 39 f2             	cmp    %rsi,%rdx
 14e:	0f 92 c0             	setb   %al
 151:	c3                   	ret
 152:	e9 00 00 00 00       	jmp    157 <__malloc_allzerop+0x157>
			153: R_X86_64_PC32	.text.unlikely.__malloc_allzerop-0x4
 157:	c3                   	ret

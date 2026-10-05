
/Users/alex/code/vinix/third_party/useralloc-libc/build/musl/x86_64/c97687ce9e5ca67f3acb8947bf28d3def2b044abf977e9e91ab8e8c767083b1c/objects/obj/src/malloc/mallocng/realloc.lo:     file format elf64-x86-64


Disassembly of section .text.unlikely.__libc_realloc:

0000000000000000 <__libc_realloc.cold>:
   0:	0f 0b                	ud2

Disassembly of section .text.__libc_realloc:

0000000000000000 <__libc_realloc>:
   0:	41 57                	push   %r15
   2:	41 56                	push   %r14
   4:	41 55                	push   %r13
   6:	41 54                	push   %r12
   8:	55                   	push   %rbp
   9:	48 89 f5             	mov    %rsi,%rbp
   c:	53                   	push   %rbx
   d:	48 83 ec 18          	sub    $0x18,%rsp
  11:	48 85 ff             	test   %rdi,%rdi
  14:	0f 84 4f 02 00 00    	je     269 <__libc_realloc+0x269>
  1a:	48 b8 fe ef ff ff ff 	movabs $0x7fffffffffffeffe,%rax
  21:	ff ff 7f 
  24:	48 39 f0             	cmp    %rsi,%rax
  27:	0f 82 6b 02 00 00    	jb     298 <__libc_realloc+0x298>
  2d:	48 89 fb             	mov    %rdi,%rbx
  30:	40 f6 c7 0f          	test   $0xf,%dil
  34:	0f 85 00 00 00 00    	jne    3a <__libc_realloc+0x3a>
			36: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
  3a:	0f b6 57 fd          	movzbl -0x3(%rdi),%edx
  3e:	0f b7 77 fe          	movzwl -0x2(%rdi),%esi
  42:	41 89 d1             	mov    %edx,%r9d
  45:	89 d0                	mov    %edx,%eax
  47:	41 83 e1 1f          	and    $0x1f,%r9d
  4b:	83 e0 1f             	and    $0x1f,%eax
  4e:	80 7f fc 00          	cmpb   $0x0,-0x4(%rdi)
  52:	74 18                	je     6c <__libc_realloc+0x6c>
  54:	85 f6                	test   %esi,%esi
  56:	0f 85 00 00 00 00    	jne    5c <__libc_realloc+0x5c>
			58: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
  5c:	48 63 77 f8          	movslq -0x8(%rdi),%rsi
  60:	81 fe ff ff 00 00    	cmp    $0xffff,%esi
  66:	0f 8e 00 00 00 00    	jle    6c <__libc_realloc+0x6c>
			68: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
  6c:	89 f1                	mov    %esi,%ecx
  6e:	48 89 df             	mov    %rbx,%rdi
  71:	c1 e1 04             	shl    $0x4,%ecx
  74:	48 63 c9             	movslq %ecx,%rcx
  77:	48 29 cf             	sub    %rcx,%rdi
  7a:	4c 8b 67 f0          	mov    -0x10(%rdi),%r12
  7e:	48 8d 4f f0          	lea    -0x10(%rdi),%rcx
  82:	49 8b 7c 24 10       	mov    0x10(%r12),%rdi
  87:	48 39 f9             	cmp    %rdi,%rcx
  8a:	0f 85 00 00 00 00    	jne    90 <__libc_realloc+0x90>
			8c: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
  90:	45 0f b6 54 24 20    	movzbl 0x20(%r12),%r10d
  96:	44 89 d1             	mov    %r10d,%ecx
  99:	83 e1 1f             	and    $0x1f,%ecx
  9c:	39 c8                	cmp    %ecx,%eax
  9e:	0f 8f 00 00 00 00    	jg     a4 <__libc_realloc+0xa4>
			a0: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
  a4:	41 8b 4c 24 18       	mov    0x18(%r12),%ecx
  a9:	0f a3 c1             	bt     %eax,%ecx
  ac:	0f 82 00 00 00 00    	jb     b2 <__libc_realloc+0xb2>
			ae: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
  b2:	41 8b 4c 24 1c       	mov    0x1c(%r12),%ecx
  b7:	0f a3 c1             	bt     %eax,%ecx
  ba:	0f 82 00 00 00 00    	jb     c0 <__libc_realloc+0xc0>
			bc: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
  c0:	4c 89 e1             	mov    %r12,%rcx
  c3:	4c 8b 35 00 00 00 00 	mov    0x0(%rip),%r14        # ca <__libc_realloc+0xca>
			c6: R_X86_64_PC32	__malloc_context-0x4
  ca:	48 81 e1 00 f0 ff ff 	and    $0xfffffffffffff000,%rcx
  d1:	4c 39 31             	cmp    %r14,(%rcx)
  d4:	0f 85 00 00 00 00    	jne    da <__libc_realloc+0xda>
			d6: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
  da:	45 0f b7 44 24 20    	movzwl 0x20(%r12),%r8d
  e0:	44 89 c1             	mov    %r8d,%ecx
  e3:	66 c1 e9 06          	shr    $0x6,%cx
  e7:	83 e1 3f             	and    $0x3f,%ecx
  ea:	80 f9 2f             	cmp    $0x2f,%cl
  ed:	0f 87 91 01 00 00    	ja     284 <__libc_realloc+0x284>
  f3:	49 89 cd             	mov    %rcx,%r13
  f6:	4c 8d 1d 00 00 00 00 	lea    0x0(%rip),%r11        # fd <__libc_realloc+0xfd>
			f9: R_X86_64_PC32	__malloc_size_classes-0x4
  fd:	41 83 e5 3f          	and    $0x3f,%r13d
 101:	47 0f b7 1c 6b       	movzwl (%r11,%r13,2),%r11d
 106:	41 0f af c3          	imul   %r11d,%eax
 10a:	39 c6                	cmp    %eax,%esi
 10c:	0f 8c 00 00 00 00    	jl     112 <__libc_realloc+0x112>
			10e: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
 112:	41 01 c3             	add    %eax,%r11d
 115:	44 39 de             	cmp    %r11d,%esi
 118:	0f 8d 61 01 00 00    	jge    27f <__libc_realloc+0x27f>
 11e:	49 81 7c 24 20 ff 0f 	cmpq   $0xfff,0x20(%r12)
 125:	00 00 
 127:	76 29                	jbe    152 <__libc_realloc+0x152>
 129:	49 8b 44 24 20       	mov    0x20(%r12),%rax
 12e:	48 25 00 f0 ff ff    	and    $0xfffffffffffff000,%rax
 134:	49 89 c3             	mov    %rax,%r11
 137:	49 c1 eb 04          	shr    $0x4,%r11
 13b:	49 83 eb 01          	sub    $0x1,%r11
 13f:	49 39 f3             	cmp    %rsi,%r11
 142:	0f 82 00 00 00 00    	jb     148 <__libc_realloc+0x148>
			144: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
 148:	48 83 e8 10          	sub    $0x10,%rax
 14c:	41 83 e2 1f          	and    $0x1f,%r10d
 150:	74 16                	je     168 <__libc_realloc+0x168>
 152:	48 89 ce             	mov    %rcx,%rsi
 155:	48 8d 05 00 00 00 00 	lea    0x0(%rip),%rax        # 15c <__libc_realloc+0x15c>
			158: R_X86_64_PC32	__malloc_size_classes-0x4
 15c:	83 e6 3f             	and    $0x3f,%esi
 15f:	0f b7 04 70          	movzwl (%rax,%rsi,2),%eax
 163:	c1 e0 04             	shl    $0x4,%eax
 166:	48 98                	cltq
 168:	41 0f b6 f1          	movzbl %r9b,%esi
 16c:	4c 8d 57 10          	lea    0x10(%rdi),%r10
 170:	48 0f af f0          	imul   %rax,%rsi
 174:	4c 01 d6             	add    %r10,%rsi
 177:	4c 8d 5c 06 fc       	lea    -0x4(%rsi,%rax,1),%r11
 17c:	89 d0                	mov    %edx,%eax
 17e:	c0 e8 05             	shr    $0x5,%al
 181:	80 fa 9f             	cmp    $0x9f,%dl
 184:	0f 87 1e 01 00 00    	ja     2a8 <__libc_realloc+0x2a8>
 18a:	0f b6 c0             	movzbl %al,%eax
 18d:	4c 89 da             	mov    %r11,%rdx
 190:	48 29 da             	sub    %rbx,%rdx
 193:	48 39 c2             	cmp    %rax,%rdx
 196:	0f 82 00 00 00 00    	jb     19c <__libc_realloc+0x19c>
			198: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
 19c:	4d 89 dd             	mov    %r11,%r13
 19f:	49 29 c5             	sub    %rax,%r13
 1a2:	41 80 7d 00 00       	cmpb   $0x0,0x0(%r13)
 1a7:	0f 85 00 00 00 00    	jne    1ad <__libc_realloc+0x1ad>
			1a9: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
 1ad:	41 80 3b 00          	cmpb   $0x0,(%r11)
 1b1:	0f 85 00 00 00 00    	jne    1b7 <__libc_realloc+0x1b7>
			1b3: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
 1b7:	b8 eb ff 01 00       	mov    $0x1ffeb,%eax
 1bc:	48 39 c2             	cmp    %rax,%rdx
 1bf:	48 0f 46 c2          	cmovbe %rdx,%rax
 1c3:	48 39 e8             	cmp    %rbp,%rax
 1c6:	0f 82 37 01 00 00    	jb     303 <__libc_realloc+0x303>
 1cc:	48 8d 75 03          	lea    0x3(%rbp),%rsi
 1d0:	48 89 f0             	mov    %rsi,%rax
 1d3:	48 c1 e8 04          	shr    $0x4,%rax
 1d7:	8d 78 01             	lea    0x1(%rax),%edi
 1da:	48 81 fe 9f 00 00 00 	cmp    $0x9f,%rsi
 1e1:	76 39                	jbe    21c <__libc_realloc+0x21c>
 1e3:	48 83 c0 01          	add    $0x1,%rax
 1e7:	4c 8d 05 00 00 00 00 	lea    0x0(%rip),%r8        # 1ee <__libc_realloc+0x1ee>
			1ea: R_X86_64_PC32	__malloc_size_classes-0x4
 1ee:	0f bd f0             	bsr    %eax,%esi
 1f1:	8d 34 b5 fc ff ff ff 	lea    -0x4(,%rsi,4),%esi
 1f8:	8d 7e 01             	lea    0x1(%rsi),%edi
 1fb:	4c 63 d7             	movslq %edi,%r10
 1fe:	47 0f b7 14 50       	movzwl (%r8,%r10,2),%r10d
 203:	49 39 c2             	cmp    %rax,%r10
 206:	73 06                	jae    20e <__libc_realloc+0x20e>
 208:	8d 7e 03             	lea    0x3(%rsi),%edi
 20b:	83 c6 02             	add    $0x2,%esi
 20e:	48 63 f6             	movslq %esi,%rsi
 211:	41 0f b7 34 70       	movzwl (%r8,%rsi,2),%esi
 216:	48 39 c6             	cmp    %rax,%rsi
 219:	83 d7 00             	adc    $0x0,%edi
 21c:	0f b6 c9             	movzbl %cl,%ecx
 21f:	39 f9                	cmp    %edi,%ecx
 221:	0f 8e a7 00 00 00    	jle    2ce <__libc_realloc+0x2ce>
 227:	48 89 ef             	mov    %rbp,%rdi
 22a:	e8 00 00 00 00       	call   22f <__libc_realloc+0x22f>
			22b: R_X86_64_PLT32	__libc_malloc_impl-0x4
 22f:	49 89 c4             	mov    %rax,%r12
 232:	48 85 c0             	test   %rax,%rax
 235:	74 20                	je     257 <__libc_realloc+0x257>
 237:	49 29 dd             	sub    %rbx,%r13
 23a:	48 89 ea             	mov    %rbp,%rdx
 23d:	48 89 c7             	mov    %rax,%rdi
 240:	48 89 de             	mov    %rbx,%rsi
 243:	49 39 ed             	cmp    %rbp,%r13
 246:	49 0f 46 d5          	cmovbe %r13,%rdx
 24a:	e8 00 00 00 00       	call   24f <__libc_realloc+0x24f>
			24b: R_X86_64_PLT32	memcpy-0x4
 24f:	48 89 df             	mov    %rbx,%rdi
 252:	e8 00 00 00 00       	call   257 <__libc_realloc+0x257>
			253: R_X86_64_PLT32	__libc_free-0x4
 257:	48 83 c4 18          	add    $0x18,%rsp
 25b:	4c 89 e0             	mov    %r12,%rax
 25e:	5b                   	pop    %rbx
 25f:	5d                   	pop    %rbp
 260:	41 5c                	pop    %r12
 262:	41 5d                	pop    %r13
 264:	41 5e                	pop    %r14
 266:	41 5f                	pop    %r15
 268:	c3                   	ret
 269:	48 83 c4 18          	add    $0x18,%rsp
 26d:	48 89 f7             	mov    %rsi,%rdi
 270:	5b                   	pop    %rbx
 271:	5d                   	pop    %rbp
 272:	41 5c                	pop    %r12
 274:	41 5d                	pop    %r13
 276:	41 5e                	pop    %r14
 278:	41 5f                	pop    %r15
 27a:	e9 00 00 00 00       	jmp    27f <__libc_realloc+0x27f>
			27b: R_X86_64_PLT32	__libc_malloc_impl-0x4
 27f:	e9 00 00 00 00       	jmp    284 <__libc_realloc+0x284>
			280: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
 284:	44 89 c0             	mov    %r8d,%eax
 287:	f7 d0                	not    %eax
 289:	66 a9 c0 0f          	test   $0xfc0,%ax
 28d:	0f 84 8b fe ff ff    	je     11e <__libc_realloc+0x11e>
 293:	e9 00 00 00 00       	jmp    298 <__libc_realloc+0x298>
			294: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
 298:	e8 00 00 00 00       	call   29d <__libc_realloc+0x29d>
			299: R_X86_64_PLT32	___errno_location-0x4
 29d:	45 31 e4             	xor    %r12d,%r12d
 2a0:	c7 00 0c 00 00 00    	movl   $0xc,(%rax)
 2a6:	eb af                	jmp    257 <__libc_realloc+0x257>
 2a8:	3c 05                	cmp    $0x5,%al
 2aa:	0f 85 00 00 00 00    	jne    2b0 <__libc_realloc+0x2b0>
			2ac: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
 2b0:	41 8b 43 fc          	mov    -0x4(%r11),%eax
 2b4:	48 83 f8 04          	cmp    $0x4,%rax
 2b8:	0f 86 00 00 00 00    	jbe    2be <__libc_realloc+0x2be>
			2ba: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
 2be:	41 80 7b fb 00       	cmpb   $0x0,-0x5(%r11)
 2c3:	0f 84 c4 fe ff ff    	je     18d <__libc_realloc+0x18d>
 2c9:	e9 00 00 00 00       	jmp    2ce <__libc_realloc+0x2ce>
			2ca: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
 2ce:	29 ea                	sub    %ebp,%edx
 2d0:	74 16                	je     2e8 <__libc_realloc+0x2e8>
 2d2:	89 d0                	mov    %edx,%eax
 2d4:	f7 d8                	neg    %eax
 2d6:	48 98                	cltq
 2d8:	41 c6 04 03 00       	movb   $0x0,(%r11,%rax,1)
 2dd:	83 fa 04             	cmp    $0x4,%edx
 2e0:	7f 12                	jg     2f4 <__libc_realloc+0x2f4>
 2e2:	c1 e2 05             	shl    $0x5,%edx
 2e5:	41 01 d1             	add    %edx,%r9d
 2e8:	44 88 4b fd          	mov    %r9b,-0x3(%rbx)
 2ec:	49 89 dc             	mov    %rbx,%r12
 2ef:	e9 63 ff ff ff       	jmp    257 <__libc_realloc+0x257>
 2f4:	41 89 53 fc          	mov    %edx,-0x4(%r11)
 2f8:	41 83 e9 60          	sub    $0x60,%r9d
 2fc:	41 c6 43 fb 00       	movb   $0x0,-0x5(%r11)
 301:	eb e5                	jmp    2e8 <__libc_realloc+0x2e8>
 303:	48 81 fd eb ff 01 00 	cmp    $0x1ffeb,%rbp
 30a:	0f 86 17 ff ff ff    	jbe    227 <__libc_realloc+0x227>
 310:	80 f9 2f             	cmp    $0x2f,%cl
 313:	0f 86 0e ff ff ff    	jbe    227 <__libc_realloc+0x227>
 319:	41 f7 d0             	not    %r8d
 31c:	66 41 f7 c0 c0 0f    	test   $0xfc0,%r8w
 322:	0f 85 00 00 00 00    	jne    328 <__libc_realloc+0x328>
			324: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
 328:	49 89 de             	mov    %rbx,%r14
 32b:	49 29 f6             	sub    %rsi,%r14
 32e:	49 8b 74 24 20       	mov    0x20(%r12),%rsi
 333:	4d 8d 84 2e 13 10 00 	lea    0x1013(%r14,%rbp,1),%r8
 33a:	00 
 33b:	4d 89 c7             	mov    %r8,%r15
 33e:	48 81 e6 00 f0 ff ff 	and    $0xfffffffffffff000,%rsi
 345:	49 81 e7 00 f0 ff ff 	and    $0xfffffffffffff000,%r15
 34c:	4c 39 fe             	cmp    %r15,%rsi
 34f:	75 62                	jne    3b3 <__libc_realloc+0x3b3>
 351:	49 8b 44 24 20       	mov    0x20(%r12),%rax
 356:	49 81 e0 00 f0 ff ff 	and    $0xfffffffffffff000,%r8
 35d:	49 83 ef 14          	sub    $0x14,%r15
 361:	49 89 7c 24 10       	mov    %rdi,0x10(%r12)
 366:	25 ff 0f 00 00       	and    $0xfff,%eax
 36b:	4c 09 c0             	or     %r8,%rax
 36e:	49 89 44 24 20       	mov    %rax,0x20(%r12)
 373:	4f 8d 24 32          	lea    (%r10,%r14,1),%r12
 377:	4d 01 fa             	add    %r15,%r10
 37a:	4d 29 f7             	sub    %r14,%r15
 37d:	41 c6 02 00          	movb   $0x0,(%r10)
 381:	41 0f b6 44 24 fd    	movzbl -0x3(%r12),%eax
 387:	83 e0 1f             	and    $0x1f,%eax
 38a:	41 29 ef             	sub    %ebp,%r15d
 38d:	74 1a                	je     3a9 <__libc_realloc+0x3a9>
 38f:	44 89 fa             	mov    %r15d,%edx
 392:	f7 da                	neg    %edx
 394:	48 63 d2             	movslq %edx,%rdx
 397:	41 c6 04 12 00       	movb   $0x0,(%r10,%rdx,1)
 39c:	41 83 ff 04          	cmp    $0x4,%r15d
 3a0:	7f 40                	jg     3e2 <__libc_realloc+0x3e2>
 3a2:	41 c1 e7 05          	shl    $0x5,%r15d
 3a6:	44 01 f8             	add    %r15d,%eax
 3a9:	41 88 44 24 fd       	mov    %al,-0x3(%r12)
 3ae:	e9 a4 fe ff ff       	jmp    257 <__libc_realloc+0x257>
 3b3:	31 c0                	xor    %eax,%eax
 3b5:	b9 01 00 00 00       	mov    $0x1,%ecx
 3ba:	4c 89 fa             	mov    %r15,%rdx
 3bd:	4c 89 44 24 08       	mov    %r8,0x8(%rsp)
 3c2:	e8 00 00 00 00       	call   3c7 <__libc_realloc+0x3c7>
			3c3: R_X86_64_PLT32	__mremap-0x4
 3c7:	4c 8b 44 24 08       	mov    0x8(%rsp),%r8
 3cc:	48 83 f8 ff          	cmp    $0xffffffffffffffff,%rax
 3d0:	48 89 c7             	mov    %rax,%rdi
 3d3:	0f 84 4e fe ff ff    	je     227 <__libc_realloc+0x227>
 3d9:	4c 8d 50 10          	lea    0x10(%rax),%r10
 3dd:	e9 6f ff ff ff       	jmp    351 <__libc_realloc+0x351>
 3e2:	45 89 7a fc          	mov    %r15d,-0x4(%r10)
 3e6:	83 e8 60             	sub    $0x60,%eax
 3e9:	41 c6 42 fb 00       	movb   $0x0,-0x5(%r10)
 3ee:	eb b9                	jmp    3a9 <__libc_realloc+0x3a9>

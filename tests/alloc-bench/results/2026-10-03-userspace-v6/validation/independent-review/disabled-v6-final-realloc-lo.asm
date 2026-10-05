
/Users/alex/code/vinix/third_party/useralloc-libc/build/useralloc/v6-prototype/cache/x86_64/e2aafe45791c748b1a101bcb8e017566e835e6f27fd623513503e67ee426bd6e/objects/obj/src/malloc/mallocng/realloc.lo:     file format elf64-x86-64


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
  14:	0f 84 41 02 00 00    	je     25b <__libc_realloc+0x25b>
  1a:	48 b8 fe ef ff ff ff 	movabs $0x7fffffffffffeffe,%rax
  21:	ff ff 7f 
  24:	48 39 f0             	cmp    %rsi,%rax
  27:	0f 82 b3 02 00 00    	jb     2e0 <__libc_realloc+0x2e0>
  2d:	48 89 fb             	mov    %rdi,%rbx
  30:	40 f6 c7 0f          	test   $0xf,%dil
  34:	0f 85 00 00 00 00    	jne    3a <__libc_realloc+0x3a>
			36: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
  3a:	44 0f b6 5f fd       	movzbl -0x3(%rdi),%r11d
  3f:	0f b7 4f fe          	movzwl -0x2(%rdi),%ecx
  43:	45 89 d9             	mov    %r11d,%r9d
  46:	44 89 da             	mov    %r11d,%edx
  49:	41 83 e1 1f          	and    $0x1f,%r9d
  4d:	83 e2 1f             	and    $0x1f,%edx
  50:	80 7f fc 00          	cmpb   $0x0,-0x4(%rdi)
  54:	74 18                	je     6e <__libc_realloc+0x6e>
  56:	85 c9                	test   %ecx,%ecx
  58:	0f 85 00 00 00 00    	jne    5e <__libc_realloc+0x5e>
			5a: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
  5e:	48 63 4f f8          	movslq -0x8(%rdi),%rcx
  62:	81 f9 ff ff 00 00    	cmp    $0xffff,%ecx
  68:	0f 8e 00 00 00 00    	jle    6e <__libc_realloc+0x6e>
			6a: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
  6e:	89 c8                	mov    %ecx,%eax
  70:	48 89 de             	mov    %rbx,%rsi
  73:	c1 e0 04             	shl    $0x4,%eax
  76:	48 98                	cltq
  78:	48 29 c6             	sub    %rax,%rsi
  7b:	4c 8b 66 f0          	mov    -0x10(%rsi),%r12
  7f:	48 8d 46 f0          	lea    -0x10(%rsi),%rax
  83:	49 8b 7c 24 10       	mov    0x10(%r12),%rdi
  88:	48 39 f8             	cmp    %rdi,%rax
  8b:	0f 85 00 00 00 00    	jne    91 <__libc_realloc+0x91>
			8d: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
  91:	45 0f b6 6c 24 20    	movzbl 0x20(%r12),%r13d
  97:	44 89 e8             	mov    %r13d,%eax
  9a:	44 89 ee             	mov    %r13d,%esi
  9d:	83 e0 1f             	and    $0x1f,%eax
  a0:	83 e6 1f             	and    $0x1f,%esi
  a3:	39 c2                	cmp    %eax,%edx
  a5:	0f 8f 00 00 00 00    	jg     ab <__libc_realloc+0xab>
			a7: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
  ab:	41 8b 44 24 18       	mov    0x18(%r12),%eax
  b0:	0f a3 d0             	bt     %edx,%eax
  b3:	0f 82 00 00 00 00    	jb     b9 <__libc_realloc+0xb9>
			b5: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
  b9:	41 8b 44 24 1c       	mov    0x1c(%r12),%eax
  be:	0f a3 d0             	bt     %edx,%eax
  c1:	0f 82 00 00 00 00    	jb     c7 <__libc_realloc+0xc7>
			c3: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
  c7:	4c 89 e0             	mov    %r12,%rax
  ca:	4c 8b 15 00 00 00 00 	mov    0x0(%rip),%r10        # d1 <__libc_realloc+0xd1>
			cd: R_X86_64_PC32	__malloc_context-0x4
  d1:	48 25 00 f0 ff ff    	and    $0xfffffffffffff000,%rax
  d7:	4c 39 10             	cmp    %r10,(%rax)
  da:	0f 85 00 00 00 00    	jne    e0 <__libc_realloc+0xe0>
			dc: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
  e0:	45 0f b7 44 24 20    	movzwl 0x20(%r12),%r8d
  e6:	44 89 c0             	mov    %r8d,%eax
  e9:	66 c1 e8 06          	shr    $0x6,%ax
  ed:	41 89 c2             	mov    %eax,%r10d
  f0:	83 e0 3f             	and    $0x3f,%eax
  f3:	41 83 e2 3f          	and    $0x3f,%r10d
  f7:	83 f8 2f             	cmp    $0x2f,%eax
  fa:	0f 8f 76 01 00 00    	jg     276 <__libc_realloc+0x276>
 100:	4c 8d 35 00 00 00 00 	lea    0x0(%rip),%r14        # 107 <__libc_realloc+0x107>
			103: R_X86_64_PC32	__malloc_size_classes-0x4
 107:	4c 63 f8             	movslq %eax,%r15
 10a:	43 0f b7 34 7e       	movzwl (%r14,%r15,2),%esi
 10f:	0f af d6             	imul   %esi,%edx
 112:	39 d1                	cmp    %edx,%ecx
 114:	0f 8c 00 00 00 00    	jl     11a <__libc_realloc+0x11a>
			116: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
 11a:	01 d6                	add    %edx,%esi
 11c:	39 f1                	cmp    %esi,%ecx
 11e:	0f 8d 4d 01 00 00    	jge    271 <__libc_realloc+0x271>
 124:	49 8b 74 24 20       	mov    0x20(%r12),%rsi
 129:	48 c1 ee 0c          	shr    $0xc,%rsi
 12d:	74 14                	je     143 <__libc_realloc+0x143>
 12f:	48 89 f2             	mov    %rsi,%rdx
 132:	48 c1 e2 08          	shl    $0x8,%rdx
 136:	48 83 ea 01          	sub    $0x1,%rdx
 13a:	48 39 ca             	cmp    %rcx,%rdx
 13d:	0f 82 00 00 00 00    	jb     143 <__libc_realloc+0x143>
			13f: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
 143:	41 83 e5 1f          	and    $0x1f,%r13d
 147:	0f 84 65 01 00 00    	je     2b2 <__libc_realloc+0x2b2>
 14d:	43 0f b7 14 7e       	movzwl (%r14,%r15,2),%edx
 152:	c1 e2 04             	shl    $0x4,%edx
 155:	48 63 d2             	movslq %edx,%rdx
 158:	41 0f b6 c9          	movzbl %r9b,%ecx
 15c:	4c 8d 77 10          	lea    0x10(%rdi),%r14
 160:	45 89 df             	mov    %r11d,%r15d
 163:	48 0f af ca          	imul   %rdx,%rcx
 167:	41 c0 ef 05          	shr    $0x5,%r15b
 16b:	4c 01 f1             	add    %r14,%rcx
 16e:	48 8d 54 11 fc       	lea    -0x4(%rcx,%rdx,1),%rdx
 173:	41 80 fb 9f          	cmp    $0x9f,%r11b
 177:	0f 87 76 01 00 00    	ja     2f3 <__libc_realloc+0x2f3>
 17d:	45 0f b6 ff          	movzbl %r15b,%r15d
 181:	49 89 d3             	mov    %rdx,%r11
 184:	49 29 db             	sub    %rbx,%r11
 187:	4d 39 fb             	cmp    %r15,%r11
 18a:	0f 82 00 00 00 00    	jb     190 <__libc_realloc+0x190>
			18c: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
 190:	49 89 d5             	mov    %rdx,%r13
 193:	4d 29 fd             	sub    %r15,%r13
 196:	41 80 7d 00 00       	cmpb   $0x0,0x0(%r13)
 19b:	0f 85 00 00 00 00    	jne    1a1 <__libc_realloc+0x1a1>
			19d: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
 1a1:	80 3a 00             	cmpb   $0x0,(%rdx)
 1a4:	0f 85 00 00 00 00    	jne    1aa <__libc_realloc+0x1aa>
			1a6: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
 1aa:	41 bf eb ff 01 00    	mov    $0x1ffeb,%r15d
 1b0:	4d 39 fb             	cmp    %r15,%r11
 1b3:	4d 0f 46 fb          	cmovbe %r11,%r15
 1b7:	49 39 ef             	cmp    %rbp,%r15
 1ba:	0f 82 99 01 00 00    	jb     359 <__libc_realloc+0x359>
 1c0:	48 8d 75 03          	lea    0x3(%rbp),%rsi
 1c4:	48 89 f1             	mov    %rsi,%rcx
 1c7:	48 c1 e9 04          	shr    $0x4,%rcx
 1cb:	48 81 fe 9f 00 00 00 	cmp    $0x9f,%rsi
 1d2:	0f 86 42 01 00 00    	jbe    31a <__libc_realloc+0x31a>
 1d8:	48 8d 79 01          	lea    0x1(%rcx),%rdi
 1dc:	4c 8d 35 00 00 00 00 	lea    0x0(%rip),%r14        # 1e3 <__libc_realloc+0x1e3>
			1df: R_X86_64_PC32	__malloc_size_classes-0x4
 1e3:	0f bd cf             	bsr    %edi,%ecx
 1e6:	8d 34 8d fc ff ff ff 	lea    -0x4(,%rcx,4),%esi
 1ed:	8d 4e 01             	lea    0x1(%rsi),%ecx
 1f0:	4c 63 c1             	movslq %ecx,%r8
 1f3:	47 0f b7 04 46       	movzwl (%r14,%r8,2),%r8d
 1f8:	49 39 f8             	cmp    %rdi,%r8
 1fb:	73 06                	jae    203 <__libc_realloc+0x203>
 1fd:	8d 4e 03             	lea    0x3(%rsi),%ecx
 200:	83 c6 02             	add    $0x2,%esi
 203:	48 63 f6             	movslq %esi,%rsi
 206:	41 0f b7 34 76       	movzwl (%r14,%rsi,2),%esi
 20b:	48 39 fe             	cmp    %rdi,%rsi
 20e:	83 d1 00             	adc    $0x0,%ecx
 211:	39 c8                	cmp    %ecx,%eax
 213:	0f 8e 09 01 00 00    	jle    322 <__libc_realloc+0x322>
 219:	48 89 ef             	mov    %rbp,%rdi
 21c:	e8 00 00 00 00       	call   221 <__libc_realloc+0x221>
			21d: R_X86_64_PLT32	__libc_malloc_impl-0x4
 221:	49 89 c4             	mov    %rax,%r12
 224:	48 85 c0             	test   %rax,%rax
 227:	74 20                	je     249 <__libc_realloc+0x249>
 229:	49 29 dd             	sub    %rbx,%r13
 22c:	48 89 ea             	mov    %rbp,%rdx
 22f:	48 89 c7             	mov    %rax,%rdi
 232:	48 89 de             	mov    %rbx,%rsi
 235:	49 39 ed             	cmp    %rbp,%r13
 238:	49 0f 46 d5          	cmovbe %r13,%rdx
 23c:	e8 00 00 00 00       	call   241 <__libc_realloc+0x241>
			23d: R_X86_64_PLT32	memcpy-0x4
 241:	48 89 df             	mov    %rbx,%rdi
 244:	e8 00 00 00 00       	call   249 <__libc_realloc+0x249>
			245: R_X86_64_PLT32	__libc_free-0x4
 249:	48 83 c4 18          	add    $0x18,%rsp
 24d:	4c 89 e0             	mov    %r12,%rax
 250:	5b                   	pop    %rbx
 251:	5d                   	pop    %rbp
 252:	41 5c                	pop    %r12
 254:	41 5d                	pop    %r13
 256:	41 5e                	pop    %r14
 258:	41 5f                	pop    %r15
 25a:	c3                   	ret
 25b:	48 83 c4 18          	add    $0x18,%rsp
 25f:	48 89 f7             	mov    %rsi,%rdi
 262:	5b                   	pop    %rbx
 263:	5d                   	pop    %rbp
 264:	41 5c                	pop    %r12
 266:	41 5d                	pop    %r13
 268:	41 5e                	pop    %r14
 26a:	41 5f                	pop    %r15
 26c:	e9 00 00 00 00       	jmp    271 <__libc_realloc+0x271>
			26d: R_X86_64_PLT32	__libc_malloc_impl-0x4
 271:	e9 00 00 00 00       	jmp    276 <__libc_realloc+0x276>
			272: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
 276:	83 f8 3f             	cmp    $0x3f,%eax
 279:	0f 85 00 00 00 00    	jne    27f <__libc_realloc+0x27f>
			27b: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
 27f:	40 84 f6             	test   %sil,%sil
 282:	0f 85 00 00 00 00    	jne    288 <__libc_realloc+0x288>
			284: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
 288:	49 81 7c 24 20 ff 0f 	cmpq   $0xfff,0x20(%r12)
 28f:	00 00 
 291:	76 48                	jbe    2db <__libc_realloc+0x2db>
 293:	49 8b 74 24 20       	mov    0x20(%r12),%rsi
 298:	48 c1 ee 0c          	shr    $0xc,%rsi
 29c:	74 2d                	je     2cb <__libc_realloc+0x2cb>
 29e:	48 89 f2             	mov    %rsi,%rdx
 2a1:	48 c1 e2 08          	shl    $0x8,%rdx
 2a5:	48 83 ea 01          	sub    $0x1,%rdx
 2a9:	48 39 ca             	cmp    %rcx,%rdx
 2ac:	0f 82 8d 01 00 00    	jb     43f <__libc_realloc+0x43f>
 2b2:	49 81 7c 24 20 ff 0f 	cmpq   $0xfff,0x20(%r12)
 2b9:	00 00 
 2bb:	4c 8d 35 00 00 00 00 	lea    0x0(%rip),%r14        # 2c2 <__libc_realloc+0x2c2>
			2be: R_X86_64_PC32	__malloc_size_classes-0x4
 2c2:	4c 63 f8             	movslq %eax,%r15
 2c5:	0f 86 82 fe ff ff    	jbe    14d <__libc_realloc+0x14d>
 2cb:	48 89 f2             	mov    %rsi,%rdx
 2ce:	48 c1 e2 0c          	shl    $0xc,%rdx
 2d2:	48 83 ea 10          	sub    $0x10,%rdx
 2d6:	e9 7d fe ff ff       	jmp    158 <__libc_realloc+0x158>
 2db:	e9 00 00 00 00       	jmp    2e0 <__libc_realloc+0x2e0>
			2dc: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
 2e0:	e8 00 00 00 00       	call   2e5 <__libc_realloc+0x2e5>
			2e1: R_X86_64_PLT32	___errno_location-0x4
 2e5:	45 31 e4             	xor    %r12d,%r12d
 2e8:	c7 00 0c 00 00 00    	movl   $0xc,(%rax)
 2ee:	e9 56 ff ff ff       	jmp    249 <__libc_realloc+0x249>
 2f3:	41 80 ff 05          	cmp    $0x5,%r15b
 2f7:	0f 85 00 00 00 00    	jne    2fd <__libc_realloc+0x2fd>
			2f9: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
 2fd:	44 8b 7a fc          	mov    -0x4(%rdx),%r15d
 301:	49 83 ff 04          	cmp    $0x4,%r15
 305:	0f 86 00 00 00 00    	jbe    30b <__libc_realloc+0x30b>
			307: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
 30b:	80 7a fb 00          	cmpb   $0x0,-0x5(%rdx)
 30f:	0f 84 6c fe ff ff    	je     181 <__libc_realloc+0x181>
 315:	e9 00 00 00 00       	jmp    31a <__libc_realloc+0x31a>
			316: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
 31a:	83 c1 01             	add    $0x1,%ecx
 31d:	e9 ef fe ff ff       	jmp    211 <__libc_realloc+0x211>
 322:	41 29 eb             	sub    %ebp,%r11d
 325:	74 18                	je     33f <__libc_realloc+0x33f>
 327:	44 89 d8             	mov    %r11d,%eax
 32a:	f7 d8                	neg    %eax
 32c:	48 98                	cltq
 32e:	c6 04 02 00          	movb   $0x0,(%rdx,%rax,1)
 332:	41 83 fb 04          	cmp    $0x4,%r11d
 336:	7f 13                	jg     34b <__libc_realloc+0x34b>
 338:	41 c1 e3 05          	shl    $0x5,%r11d
 33c:	45 01 d9             	add    %r11d,%r9d
 33f:	44 88 4b fd          	mov    %r9b,-0x3(%rbx)
 343:	49 89 dc             	mov    %rbx,%r12
 346:	e9 fe fe ff ff       	jmp    249 <__libc_realloc+0x249>
 34b:	44 89 5a fc          	mov    %r11d,-0x4(%rdx)
 34f:	41 83 e9 60          	sub    $0x60,%r9d
 353:	c6 42 fb 00          	movb   $0x0,-0x5(%rdx)
 357:	eb e6                	jmp    33f <__libc_realloc+0x33f>
 359:	48 81 fd eb ff 01 00 	cmp    $0x1ffeb,%rbp
 360:	0f 86 b3 fe ff ff    	jbe    219 <__libc_realloc+0x219>
 366:	41 80 fa 2f          	cmp    $0x2f,%r10b
 36a:	0f 86 a9 fe ff ff    	jbe    219 <__libc_realloc+0x219>
 370:	41 f7 d0             	not    %r8d
 373:	66 41 f7 c0 c0 0f    	test   $0xfc0,%r8w
 379:	0f 85 00 00 00 00    	jne    37f <__libc_realloc+0x37f>
			37b: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
 37f:	49 89 df             	mov    %rbx,%r15
 382:	48 c1 e6 0c          	shl    $0xc,%rsi
 386:	49 29 cf             	sub    %rcx,%r15
 389:	4d 8d 84 2f 13 10 00 	lea    0x1013(%r15,%rbp,1),%r8
 390:	00 
 391:	4c 89 c2             	mov    %r8,%rdx
 394:	48 81 e2 00 f0 ff ff 	and    $0xfffffffffffff000,%rdx
 39b:	48 39 d6             	cmp    %rdx,%rsi
 39e:	75 5d                	jne    3fd <__libc_realloc+0x3fd>
 3a0:	49 8b 44 24 20       	mov    0x20(%r12),%rax
 3a5:	49 81 e0 00 f0 ff ff 	and    $0xfffffffffffff000,%r8
 3ac:	48 83 ea 14          	sub    $0x14,%rdx
 3b0:	49 89 7c 24 10       	mov    %rdi,0x10(%r12)
 3b5:	25 ff 0f 00 00       	and    $0xfff,%eax
 3ba:	4c 09 c0             	or     %r8,%rax
 3bd:	49 89 44 24 20       	mov    %rax,0x20(%r12)
 3c2:	4f 8d 24 3e          	lea    (%r14,%r15,1),%r12
 3c6:	49 01 d6             	add    %rdx,%r14
 3c9:	4c 29 fa             	sub    %r15,%rdx
 3cc:	41 c6 06 00          	movb   $0x0,(%r14)
 3d0:	41 0f b6 44 24 fd    	movzbl -0x3(%r12),%eax
 3d6:	83 e0 1f             	and    $0x1f,%eax
 3d9:	29 ea                	sub    %ebp,%edx
 3db:	74 16                	je     3f3 <__libc_realloc+0x3f3>
 3dd:	89 d1                	mov    %edx,%ecx
 3df:	f7 d9                	neg    %ecx
 3e1:	48 63 c9             	movslq %ecx,%rcx
 3e4:	41 c6 04 0e 00       	movb   $0x0,(%r14,%rcx,1)
 3e9:	83 fa 04             	cmp    $0x4,%edx
 3ec:	7f 43                	jg     431 <__libc_realloc+0x431>
 3ee:	c1 e2 05             	shl    $0x5,%edx
 3f1:	01 d0                	add    %edx,%eax
 3f3:	41 88 44 24 fd       	mov    %al,-0x3(%r12)
 3f8:	e9 4c fe ff ff       	jmp    249 <__libc_realloc+0x249>
 3fd:	31 c0                	xor    %eax,%eax
 3ff:	b9 01 00 00 00       	mov    $0x1,%ecx
 404:	4c 89 44 24 08       	mov    %r8,0x8(%rsp)
 409:	48 89 14 24          	mov    %rdx,(%rsp)
 40d:	e8 00 00 00 00       	call   412 <__libc_realloc+0x412>
			40e: R_X86_64_PLT32	__mremap-0x4
 412:	48 8b 14 24          	mov    (%rsp),%rdx
 416:	4c 8b 44 24 08       	mov    0x8(%rsp),%r8
 41b:	48 83 f8 ff          	cmp    $0xffffffffffffffff,%rax
 41f:	48 89 c7             	mov    %rax,%rdi
 422:	0f 84 f1 fd ff ff    	je     219 <__libc_realloc+0x219>
 428:	4c 8d 70 10          	lea    0x10(%rax),%r14
 42c:	e9 6f ff ff ff       	jmp    3a0 <__libc_realloc+0x3a0>
 431:	41 89 56 fc          	mov    %edx,-0x4(%r14)
 435:	83 e8 60             	sub    $0x60,%eax
 438:	41 c6 46 fb 00       	movb   $0x0,-0x5(%r14)
 43d:	eb b4                	jmp    3f3 <__libc_realloc+0x3f3>
 43f:	e9 00 00 00 00       	jmp    444 <__libc_realloc+0x444>
			440: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4

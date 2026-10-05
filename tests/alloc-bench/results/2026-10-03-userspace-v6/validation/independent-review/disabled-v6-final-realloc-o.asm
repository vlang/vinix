
/Users/alex/code/vinix/third_party/useralloc-libc/build/useralloc/v6-prototype/cache/x86_64/e2aafe45791c748b1a101bcb8e017566e835e6f27fd623513503e67ee426bd6e/objects/obj/src/malloc/mallocng/realloc.o:     file format elf64-x86-64


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
  14:	0f 84 3f 02 00 00    	je     259 <__libc_realloc+0x259>
  1a:	48 b8 fe ef ff ff ff 	movabs $0x7fffffffffffeffe,%rax
  21:	ff ff 7f 
  24:	48 39 f0             	cmp    %rsi,%rax
  27:	0f 82 aa 02 00 00    	jb     2d7 <__libc_realloc+0x2d7>
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
  ca:	4c 8b 05 00 00 00 00 	mov    0x0(%rip),%r8        # d1 <__libc_realloc+0xd1>
			cd: R_X86_64_PC32	__malloc_context-0x4
  d1:	48 25 00 f0 ff ff    	and    $0xfffffffffffff000,%rax
  d7:	4c 39 00             	cmp    %r8,(%rax)
  da:	0f 85 00 00 00 00    	jne    e0 <__libc_realloc+0xe0>
			dc: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
  e0:	45 0f b7 44 24 20    	movzwl 0x20(%r12),%r8d
  e6:	44 89 c0             	mov    %r8d,%eax
  e9:	66 c1 e8 06          	shr    $0x6,%ax
  ed:	41 89 c2             	mov    %eax,%r10d
  f0:	83 e0 3f             	and    $0x3f,%eax
  f3:	41 83 e2 3f          	and    $0x3f,%r10d
  f7:	83 f8 2f             	cmp    $0x2f,%eax
  fa:	0f 8f 74 01 00 00    	jg     274 <__libc_realloc+0x274>
 100:	4c 63 f0             	movslq %eax,%r14
 103:	43 0f b7 b4 36 00 00 	movzwl 0x0(%r14,%r14,1),%esi
 10a:	00 00 
			108: R_X86_64_32S	__malloc_size_classes
 10c:	0f af d6             	imul   %esi,%edx
 10f:	39 d1                	cmp    %edx,%ecx
 111:	0f 8c 00 00 00 00    	jl     117 <__libc_realloc+0x117>
			113: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
 117:	01 d6                	add    %edx,%esi
 119:	39 f1                	cmp    %esi,%ecx
 11b:	0f 8d 4e 01 00 00    	jge    26f <__libc_realloc+0x26f>
 121:	49 8b 74 24 20       	mov    0x20(%r12),%rsi
 126:	48 c1 ee 0c          	shr    $0xc,%rsi
 12a:	74 14                	je     140 <__libc_realloc+0x140>
 12c:	48 89 f2             	mov    %rsi,%rdx
 12f:	48 c1 e2 08          	shl    $0x8,%rdx
 133:	48 83 ea 01          	sub    $0x1,%rdx
 137:	48 39 ca             	cmp    %rcx,%rdx
 13a:	0f 82 00 00 00 00    	jb     140 <__libc_realloc+0x140>
			13c: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
 140:	41 83 e5 1f          	and    $0x1f,%r13d
 144:	0f 84 66 01 00 00    	je     2b0 <__libc_realloc+0x2b0>
 14a:	43 0f b7 94 36 00 00 	movzwl 0x0(%r14,%r14,1),%edx
 151:	00 00 
			14f: R_X86_64_32S	__malloc_size_classes
 153:	c1 e2 04             	shl    $0x4,%edx
 156:	48 63 d2             	movslq %edx,%rdx
 159:	41 0f b6 c9          	movzbl %r9b,%ecx
 15d:	4c 8d 77 10          	lea    0x10(%rdi),%r14
 161:	48 0f af ca          	imul   %rdx,%rcx
 165:	4c 01 f1             	add    %r14,%rcx
 168:	4c 8d 7c 11 fc       	lea    -0x4(%rcx,%rdx,1),%r15
 16d:	44 89 da             	mov    %r11d,%edx
 170:	c0 ea 05             	shr    $0x5,%dl
 173:	41 80 fb 9f          	cmp    $0x9f,%r11b
 177:	0f 87 6d 01 00 00    	ja     2ea <__libc_realloc+0x2ea>
 17d:	0f b6 d2             	movzbl %dl,%edx
 180:	4d 89 fb             	mov    %r15,%r11
 183:	49 29 db             	sub    %rbx,%r11
 186:	49 39 d3             	cmp    %rdx,%r11
 189:	0f 82 00 00 00 00    	jb     18f <__libc_realloc+0x18f>
			18b: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
 18f:	4d 89 fd             	mov    %r15,%r13
 192:	49 29 d5             	sub    %rdx,%r13
 195:	41 80 7d 00 00       	cmpb   $0x0,0x0(%r13)
 19a:	0f 85 00 00 00 00    	jne    1a0 <__libc_realloc+0x1a0>
			19c: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
 1a0:	41 80 3f 00          	cmpb   $0x0,(%r15)
 1a4:	0f 85 00 00 00 00    	jne    1aa <__libc_realloc+0x1aa>
			1a6: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
 1aa:	ba eb ff 01 00       	mov    $0x1ffeb,%edx
 1af:	49 39 d3             	cmp    %rdx,%r11
 1b2:	49 0f 46 d3          	cmovbe %r11,%rdx
 1b6:	48 39 ea             	cmp    %rbp,%rdx
 1b9:	0f 82 93 01 00 00    	jb     352 <__libc_realloc+0x352>
 1bf:	48 8d 4d 03          	lea    0x3(%rbp),%rcx
 1c3:	48 89 ca             	mov    %rcx,%rdx
 1c6:	48 c1 ea 04          	shr    $0x4,%rdx
 1ca:	48 81 f9 9f 00 00 00 	cmp    $0x9f,%rcx
 1d1:	0f 86 3a 01 00 00    	jbe    311 <__libc_realloc+0x311>
 1d7:	48 83 c2 01          	add    $0x1,%rdx
 1db:	0f bd ca             	bsr    %edx,%ecx
 1de:	8d 34 8d fc ff ff ff 	lea    -0x4(,%rcx,4),%esi
 1e5:	8d 4e 01             	lea    0x1(%rsi),%ecx
 1e8:	48 63 f9             	movslq %ecx,%rdi
 1eb:	0f b7 bc 3f 00 00 00 	movzwl 0x0(%rdi,%rdi,1),%edi
 1f2:	00 
			1ef: R_X86_64_32S	__malloc_size_classes
 1f3:	48 39 d7             	cmp    %rdx,%rdi
 1f6:	73 06                	jae    1fe <__libc_realloc+0x1fe>
 1f8:	8d 4e 03             	lea    0x3(%rsi),%ecx
 1fb:	83 c6 02             	add    $0x2,%esi
 1fe:	48 63 f6             	movslq %esi,%rsi
 201:	0f b7 b4 36 00 00 00 	movzwl 0x0(%rsi,%rsi,1),%esi
 208:	00 
			205: R_X86_64_32S	__malloc_size_classes
 209:	48 39 d6             	cmp    %rdx,%rsi
 20c:	83 d1 00             	adc    $0x0,%ecx
 20f:	39 c8                	cmp    %ecx,%eax
 211:	0f 8e 02 01 00 00    	jle    319 <__libc_realloc+0x319>
 217:	48 89 ef             	mov    %rbp,%rdi
 21a:	e8 00 00 00 00       	call   21f <__libc_realloc+0x21f>
			21b: R_X86_64_PLT32	__libc_malloc_impl-0x4
 21f:	49 89 c4             	mov    %rax,%r12
 222:	48 85 c0             	test   %rax,%rax
 225:	74 20                	je     247 <__libc_realloc+0x247>
 227:	49 29 dd             	sub    %rbx,%r13
 22a:	48 89 ea             	mov    %rbp,%rdx
 22d:	48 89 c7             	mov    %rax,%rdi
 230:	48 89 de             	mov    %rbx,%rsi
 233:	49 39 ed             	cmp    %rbp,%r13
 236:	49 0f 46 d5          	cmovbe %r13,%rdx
 23a:	e8 00 00 00 00       	call   23f <__libc_realloc+0x23f>
			23b: R_X86_64_PLT32	memcpy-0x4
 23f:	48 89 df             	mov    %rbx,%rdi
 242:	e8 00 00 00 00       	call   247 <__libc_realloc+0x247>
			243: R_X86_64_PLT32	__libc_free-0x4
 247:	48 83 c4 18          	add    $0x18,%rsp
 24b:	4c 89 e0             	mov    %r12,%rax
 24e:	5b                   	pop    %rbx
 24f:	5d                   	pop    %rbp
 250:	41 5c                	pop    %r12
 252:	41 5d                	pop    %r13
 254:	41 5e                	pop    %r14
 256:	41 5f                	pop    %r15
 258:	c3                   	ret
 259:	48 83 c4 18          	add    $0x18,%rsp
 25d:	48 89 f7             	mov    %rsi,%rdi
 260:	5b                   	pop    %rbx
 261:	5d                   	pop    %rbp
 262:	41 5c                	pop    %r12
 264:	41 5d                	pop    %r13
 266:	41 5e                	pop    %r14
 268:	41 5f                	pop    %r15
 26a:	e9 00 00 00 00       	jmp    26f <__libc_realloc+0x26f>
			26b: R_X86_64_PLT32	__libc_malloc_impl-0x4
 26f:	e9 00 00 00 00       	jmp    274 <__libc_realloc+0x274>
			270: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
 274:	83 f8 3f             	cmp    $0x3f,%eax
 277:	0f 85 00 00 00 00    	jne    27d <__libc_realloc+0x27d>
			279: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
 27d:	40 84 f6             	test   %sil,%sil
 280:	0f 85 00 00 00 00    	jne    286 <__libc_realloc+0x286>
			282: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
 286:	49 81 7c 24 20 ff 0f 	cmpq   $0xfff,0x20(%r12)
 28d:	00 00 
 28f:	76 41                	jbe    2d2 <__libc_realloc+0x2d2>
 291:	49 8b 74 24 20       	mov    0x20(%r12),%rsi
 296:	48 c1 ee 0c          	shr    $0xc,%rsi
 29a:	74 26                	je     2c2 <__libc_realloc+0x2c2>
 29c:	48 89 f2             	mov    %rsi,%rdx
 29f:	48 c1 e2 08          	shl    $0x8,%rdx
 2a3:	48 83 ea 01          	sub    $0x1,%rdx
 2a7:	48 39 ca             	cmp    %rcx,%rdx
 2aa:	0f 82 88 01 00 00    	jb     438 <__libc_realloc+0x438>
 2b0:	49 81 7c 24 20 ff 0f 	cmpq   $0xfff,0x20(%r12)
 2b7:	00 00 
 2b9:	4c 63 f0             	movslq %eax,%r14
 2bc:	0f 86 88 fe ff ff    	jbe    14a <__libc_realloc+0x14a>
 2c2:	48 89 f2             	mov    %rsi,%rdx
 2c5:	48 c1 e2 0c          	shl    $0xc,%rdx
 2c9:	48 83 ea 10          	sub    $0x10,%rdx
 2cd:	e9 87 fe ff ff       	jmp    159 <__libc_realloc+0x159>
 2d2:	e9 00 00 00 00       	jmp    2d7 <__libc_realloc+0x2d7>
			2d3: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
 2d7:	e8 00 00 00 00       	call   2dc <__libc_realloc+0x2dc>
			2d8: R_X86_64_PLT32	___errno_location-0x4
 2dc:	45 31 e4             	xor    %r12d,%r12d
 2df:	c7 00 0c 00 00 00    	movl   $0xc,(%rax)
 2e5:	e9 5d ff ff ff       	jmp    247 <__libc_realloc+0x247>
 2ea:	80 fa 05             	cmp    $0x5,%dl
 2ed:	0f 85 00 00 00 00    	jne    2f3 <__libc_realloc+0x2f3>
			2ef: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
 2f3:	41 8b 57 fc          	mov    -0x4(%r15),%edx
 2f7:	48 83 fa 04          	cmp    $0x4,%rdx
 2fb:	0f 86 00 00 00 00    	jbe    301 <__libc_realloc+0x301>
			2fd: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
 301:	41 80 7f fb 00       	cmpb   $0x0,-0x5(%r15)
 306:	0f 84 74 fe ff ff    	je     180 <__libc_realloc+0x180>
 30c:	e9 00 00 00 00       	jmp    311 <__libc_realloc+0x311>
			30d: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
 311:	8d 4a 01             	lea    0x1(%rdx),%ecx
 314:	e9 f6 fe ff ff       	jmp    20f <__libc_realloc+0x20f>
 319:	41 29 eb             	sub    %ebp,%r11d
 31c:	74 19                	je     337 <__libc_realloc+0x337>
 31e:	44 89 d8             	mov    %r11d,%eax
 321:	f7 d8                	neg    %eax
 323:	48 98                	cltq
 325:	41 c6 04 07 00       	movb   $0x0,(%r15,%rax,1)
 32a:	41 83 fb 04          	cmp    $0x4,%r11d
 32e:	7f 13                	jg     343 <__libc_realloc+0x343>
 330:	41 c1 e3 05          	shl    $0x5,%r11d
 334:	45 01 d9             	add    %r11d,%r9d
 337:	44 88 4b fd          	mov    %r9b,-0x3(%rbx)
 33b:	49 89 dc             	mov    %rbx,%r12
 33e:	e9 04 ff ff ff       	jmp    247 <__libc_realloc+0x247>
 343:	45 89 5f fc          	mov    %r11d,-0x4(%r15)
 347:	41 83 e9 60          	sub    $0x60,%r9d
 34b:	41 c6 47 fb 00       	movb   $0x0,-0x5(%r15)
 350:	eb e5                	jmp    337 <__libc_realloc+0x337>
 352:	48 81 fd eb ff 01 00 	cmp    $0x1ffeb,%rbp
 359:	0f 86 b8 fe ff ff    	jbe    217 <__libc_realloc+0x217>
 35f:	41 80 fa 2f          	cmp    $0x2f,%r10b
 363:	0f 86 ae fe ff ff    	jbe    217 <__libc_realloc+0x217>
 369:	41 f7 d0             	not    %r8d
 36c:	66 41 f7 c0 c0 0f    	test   $0xfc0,%r8w
 372:	0f 85 00 00 00 00    	jne    378 <__libc_realloc+0x378>
			374: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
 378:	49 89 df             	mov    %rbx,%r15
 37b:	48 c1 e6 0c          	shl    $0xc,%rsi
 37f:	49 29 cf             	sub    %rcx,%r15
 382:	4d 8d 84 2f 13 10 00 	lea    0x1013(%r15,%rbp,1),%r8
 389:	00 
 38a:	4c 89 c2             	mov    %r8,%rdx
 38d:	48 81 e2 00 f0 ff ff 	and    $0xfffffffffffff000,%rdx
 394:	48 39 d6             	cmp    %rdx,%rsi
 397:	75 5d                	jne    3f6 <__libc_realloc+0x3f6>
 399:	49 8b 44 24 20       	mov    0x20(%r12),%rax
 39e:	49 81 e0 00 f0 ff ff 	and    $0xfffffffffffff000,%r8
 3a5:	48 83 ea 14          	sub    $0x14,%rdx
 3a9:	49 89 7c 24 10       	mov    %rdi,0x10(%r12)
 3ae:	25 ff 0f 00 00       	and    $0xfff,%eax
 3b3:	4c 09 c0             	or     %r8,%rax
 3b6:	49 89 44 24 20       	mov    %rax,0x20(%r12)
 3bb:	4f 8d 24 3e          	lea    (%r14,%r15,1),%r12
 3bf:	49 01 d6             	add    %rdx,%r14
 3c2:	4c 29 fa             	sub    %r15,%rdx
 3c5:	41 c6 06 00          	movb   $0x0,(%r14)
 3c9:	41 0f b6 44 24 fd    	movzbl -0x3(%r12),%eax
 3cf:	83 e0 1f             	and    $0x1f,%eax
 3d2:	29 ea                	sub    %ebp,%edx
 3d4:	74 16                	je     3ec <__libc_realloc+0x3ec>
 3d6:	89 d1                	mov    %edx,%ecx
 3d8:	f7 d9                	neg    %ecx
 3da:	48 63 c9             	movslq %ecx,%rcx
 3dd:	41 c6 04 0e 00       	movb   $0x0,(%r14,%rcx,1)
 3e2:	83 fa 04             	cmp    $0x4,%edx
 3e5:	7f 43                	jg     42a <__libc_realloc+0x42a>
 3e7:	c1 e2 05             	shl    $0x5,%edx
 3ea:	01 d0                	add    %edx,%eax
 3ec:	41 88 44 24 fd       	mov    %al,-0x3(%r12)
 3f1:	e9 51 fe ff ff       	jmp    247 <__libc_realloc+0x247>
 3f6:	31 c0                	xor    %eax,%eax
 3f8:	b9 01 00 00 00       	mov    $0x1,%ecx
 3fd:	4c 89 44 24 08       	mov    %r8,0x8(%rsp)
 402:	48 89 14 24          	mov    %rdx,(%rsp)
 406:	e8 00 00 00 00       	call   40b <__libc_realloc+0x40b>
			407: R_X86_64_PLT32	__mremap-0x4
 40b:	48 8b 14 24          	mov    (%rsp),%rdx
 40f:	4c 8b 44 24 08       	mov    0x8(%rsp),%r8
 414:	48 83 f8 ff          	cmp    $0xffffffffffffffff,%rax
 418:	48 89 c7             	mov    %rax,%rdi
 41b:	0f 84 f6 fd ff ff    	je     217 <__libc_realloc+0x217>
 421:	4c 8d 70 10          	lea    0x10(%rax),%r14
 425:	e9 6f ff ff ff       	jmp    399 <__libc_realloc+0x399>
 42a:	41 89 56 fc          	mov    %edx,-0x4(%r14)
 42e:	83 e8 60             	sub    $0x60,%eax
 431:	41 c6 46 fb 00       	movb   $0x0,-0x5(%r14)
 436:	eb b4                	jmp    3ec <__libc_realloc+0x3ec>
 438:	e9 00 00 00 00       	jmp    43d <__libc_realloc+0x43d>
			439: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4

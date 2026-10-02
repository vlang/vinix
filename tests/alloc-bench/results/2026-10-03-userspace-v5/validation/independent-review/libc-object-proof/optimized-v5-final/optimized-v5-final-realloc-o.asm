
/Users/alex/code/vinix/third_party/useralloc-libc/build/musl/x86_64/c97687ce9e5ca67f3acb8947bf28d3def2b044abf977e9e91ab8e8c767083b1c/objects/obj/src/malloc/mallocng/realloc.o:     file format elf64-x86-64


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
  14:	0f 84 4a 02 00 00    	je     264 <__libc_realloc+0x264>
  1a:	48 b8 fe ef ff ff ff 	movabs $0x7fffffffffffeffe,%rax
  21:	ff ff 7f 
  24:	48 39 f0             	cmp    %rsi,%rax
  27:	0f 82 66 02 00 00    	jb     293 <__libc_realloc+0x293>
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
  ed:	0f 87 8c 01 00 00    	ja     27f <__libc_realloc+0x27f>
  f3:	49 89 cb             	mov    %rcx,%r11
  f6:	41 83 e3 3f          	and    $0x3f,%r11d
  fa:	47 0f b7 9c 1b 00 00 	movzwl 0x0(%r11,%r11,1),%r11d
 101:	00 00 
			ff: R_X86_64_32S	__malloc_size_classes
 103:	41 0f af c3          	imul   %r11d,%eax
 107:	39 c6                	cmp    %eax,%esi
 109:	0f 8c 00 00 00 00    	jl     10f <__libc_realloc+0x10f>
			10b: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
 10f:	41 01 c3             	add    %eax,%r11d
 112:	44 39 de             	cmp    %r11d,%esi
 115:	0f 8d 5f 01 00 00    	jge    27a <__libc_realloc+0x27a>
 11b:	49 81 7c 24 20 ff 0f 	cmpq   $0xfff,0x20(%r12)
 122:	00 00 
 124:	76 29                	jbe    14f <__libc_realloc+0x14f>
 126:	49 8b 44 24 20       	mov    0x20(%r12),%rax
 12b:	48 25 00 f0 ff ff    	and    $0xfffffffffffff000,%rax
 131:	49 89 c3             	mov    %rax,%r11
 134:	49 c1 eb 04          	shr    $0x4,%r11
 138:	49 83 eb 01          	sub    $0x1,%r11
 13c:	49 39 f3             	cmp    %rsi,%r11
 13f:	0f 82 00 00 00 00    	jb     145 <__libc_realloc+0x145>
			141: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
 145:	48 83 e8 10          	sub    $0x10,%rax
 149:	41 83 e2 1f          	and    $0x1f,%r10d
 14d:	74 13                	je     162 <__libc_realloc+0x162>
 14f:	48 89 c8             	mov    %rcx,%rax
 152:	83 e0 3f             	and    $0x3f,%eax
 155:	0f b7 84 00 00 00 00 	movzwl 0x0(%rax,%rax,1),%eax
 15c:	00 
			159: R_X86_64_32S	__malloc_size_classes
 15d:	c1 e0 04             	shl    $0x4,%eax
 160:	48 98                	cltq
 162:	41 0f b6 f1          	movzbl %r9b,%esi
 166:	4c 8d 57 10          	lea    0x10(%rdi),%r10
 16a:	48 0f af f0          	imul   %rax,%rsi
 16e:	4c 01 d6             	add    %r10,%rsi
 171:	4c 8d 5c 06 fc       	lea    -0x4(%rsi,%rax,1),%r11
 176:	89 d0                	mov    %edx,%eax
 178:	c0 e8 05             	shr    $0x5,%al
 17b:	80 fa 9f             	cmp    $0x9f,%dl
 17e:	0f 87 1f 01 00 00    	ja     2a3 <__libc_realloc+0x2a3>
 184:	0f b6 c0             	movzbl %al,%eax
 187:	4c 89 da             	mov    %r11,%rdx
 18a:	48 29 da             	sub    %rbx,%rdx
 18d:	48 39 c2             	cmp    %rax,%rdx
 190:	0f 82 00 00 00 00    	jb     196 <__libc_realloc+0x196>
			192: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
 196:	4d 89 dd             	mov    %r11,%r13
 199:	49 29 c5             	sub    %rax,%r13
 19c:	41 80 7d 00 00       	cmpb   $0x0,0x0(%r13)
 1a1:	0f 85 00 00 00 00    	jne    1a7 <__libc_realloc+0x1a7>
			1a3: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
 1a7:	41 80 3b 00          	cmpb   $0x0,(%r11)
 1ab:	0f 85 00 00 00 00    	jne    1b1 <__libc_realloc+0x1b1>
			1ad: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
 1b1:	b8 eb ff 01 00       	mov    $0x1ffeb,%eax
 1b6:	48 39 c2             	cmp    %rax,%rdx
 1b9:	48 0f 46 c2          	cmovbe %rdx,%rax
 1bd:	48 39 e8             	cmp    %rbp,%rax
 1c0:	0f 82 40 01 00 00    	jb     306 <__libc_realloc+0x306>
 1c6:	48 8d 75 03          	lea    0x3(%rbp),%rsi
 1ca:	48 89 f0             	mov    %rsi,%rax
 1cd:	48 c1 e8 04          	shr    $0x4,%rax
 1d1:	48 81 fe 9f 00 00 00 	cmp    $0x9f,%rsi
 1d8:	0f 86 eb 00 00 00    	jbe    2c9 <__libc_realloc+0x2c9>
 1de:	48 83 c0 01          	add    $0x1,%rax
 1e2:	0f bd f0             	bsr    %eax,%esi
 1e5:	8d 3c b5 fc ff ff ff 	lea    -0x4(,%rsi,4),%edi
 1ec:	8d 77 01             	lea    0x1(%rdi),%esi
 1ef:	4c 63 c6             	movslq %esi,%r8
 1f2:	47 0f b7 84 00 00 00 	movzwl 0x0(%r8,%r8,1),%r8d
 1f9:	00 00 
			1f7: R_X86_64_32S	__malloc_size_classes
 1fb:	49 39 c0             	cmp    %rax,%r8
 1fe:	73 06                	jae    206 <__libc_realloc+0x206>
 200:	8d 77 03             	lea    0x3(%rdi),%esi
 203:	83 c7 02             	add    $0x2,%edi
 206:	48 63 ff             	movslq %edi,%rdi
 209:	0f b7 bc 3f 00 00 00 	movzwl 0x0(%rdi,%rdi,1),%edi
 210:	00 
			20d: R_X86_64_32S	__malloc_size_classes
 211:	48 39 c7             	cmp    %rax,%rdi
 214:	83 d6 00             	adc    $0x0,%esi
 217:	0f b6 c9             	movzbl %cl,%ecx
 21a:	39 f1                	cmp    %esi,%ecx
 21c:	0f 8e af 00 00 00    	jle    2d1 <__libc_realloc+0x2d1>
 222:	48 89 ef             	mov    %rbp,%rdi
 225:	e8 00 00 00 00       	call   22a <__libc_realloc+0x22a>
			226: R_X86_64_PLT32	__libc_malloc_impl-0x4
 22a:	49 89 c4             	mov    %rax,%r12
 22d:	48 85 c0             	test   %rax,%rax
 230:	74 20                	je     252 <__libc_realloc+0x252>
 232:	49 29 dd             	sub    %rbx,%r13
 235:	48 89 ea             	mov    %rbp,%rdx
 238:	48 89 c7             	mov    %rax,%rdi
 23b:	48 89 de             	mov    %rbx,%rsi
 23e:	49 39 ed             	cmp    %rbp,%r13
 241:	49 0f 46 d5          	cmovbe %r13,%rdx
 245:	e8 00 00 00 00       	call   24a <__libc_realloc+0x24a>
			246: R_X86_64_PLT32	memcpy-0x4
 24a:	48 89 df             	mov    %rbx,%rdi
 24d:	e8 00 00 00 00       	call   252 <__libc_realloc+0x252>
			24e: R_X86_64_PLT32	__libc_free-0x4
 252:	48 83 c4 18          	add    $0x18,%rsp
 256:	4c 89 e0             	mov    %r12,%rax
 259:	5b                   	pop    %rbx
 25a:	5d                   	pop    %rbp
 25b:	41 5c                	pop    %r12
 25d:	41 5d                	pop    %r13
 25f:	41 5e                	pop    %r14
 261:	41 5f                	pop    %r15
 263:	c3                   	ret
 264:	48 83 c4 18          	add    $0x18,%rsp
 268:	48 89 f7             	mov    %rsi,%rdi
 26b:	5b                   	pop    %rbx
 26c:	5d                   	pop    %rbp
 26d:	41 5c                	pop    %r12
 26f:	41 5d                	pop    %r13
 271:	41 5e                	pop    %r14
 273:	41 5f                	pop    %r15
 275:	e9 00 00 00 00       	jmp    27a <__libc_realloc+0x27a>
			276: R_X86_64_PLT32	__libc_malloc_impl-0x4
 27a:	e9 00 00 00 00       	jmp    27f <__libc_realloc+0x27f>
			27b: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
 27f:	44 89 c0             	mov    %r8d,%eax
 282:	f7 d0                	not    %eax
 284:	66 a9 c0 0f          	test   $0xfc0,%ax
 288:	0f 84 8d fe ff ff    	je     11b <__libc_realloc+0x11b>
 28e:	e9 00 00 00 00       	jmp    293 <__libc_realloc+0x293>
			28f: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
 293:	e8 00 00 00 00       	call   298 <__libc_realloc+0x298>
			294: R_X86_64_PLT32	___errno_location-0x4
 298:	45 31 e4             	xor    %r12d,%r12d
 29b:	c7 00 0c 00 00 00    	movl   $0xc,(%rax)
 2a1:	eb af                	jmp    252 <__libc_realloc+0x252>
 2a3:	3c 05                	cmp    $0x5,%al
 2a5:	0f 85 00 00 00 00    	jne    2ab <__libc_realloc+0x2ab>
			2a7: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
 2ab:	41 8b 43 fc          	mov    -0x4(%r11),%eax
 2af:	48 83 f8 04          	cmp    $0x4,%rax
 2b3:	0f 86 00 00 00 00    	jbe    2b9 <__libc_realloc+0x2b9>
			2b5: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
 2b9:	41 80 7b fb 00       	cmpb   $0x0,-0x5(%r11)
 2be:	0f 84 c3 fe ff ff    	je     187 <__libc_realloc+0x187>
 2c4:	e9 00 00 00 00       	jmp    2c9 <__libc_realloc+0x2c9>
			2c5: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
 2c9:	8d 70 01             	lea    0x1(%rax),%esi
 2cc:	e9 46 ff ff ff       	jmp    217 <__libc_realloc+0x217>
 2d1:	29 ea                	sub    %ebp,%edx
 2d3:	74 16                	je     2eb <__libc_realloc+0x2eb>
 2d5:	89 d0                	mov    %edx,%eax
 2d7:	f7 d8                	neg    %eax
 2d9:	48 98                	cltq
 2db:	41 c6 04 03 00       	movb   $0x0,(%r11,%rax,1)
 2e0:	83 fa 04             	cmp    $0x4,%edx
 2e3:	7f 12                	jg     2f7 <__libc_realloc+0x2f7>
 2e5:	c1 e2 05             	shl    $0x5,%edx
 2e8:	41 01 d1             	add    %edx,%r9d
 2eb:	44 88 4b fd          	mov    %r9b,-0x3(%rbx)
 2ef:	49 89 dc             	mov    %rbx,%r12
 2f2:	e9 5b ff ff ff       	jmp    252 <__libc_realloc+0x252>
 2f7:	41 89 53 fc          	mov    %edx,-0x4(%r11)
 2fb:	41 83 e9 60          	sub    $0x60,%r9d
 2ff:	41 c6 43 fb 00       	movb   $0x0,-0x5(%r11)
 304:	eb e5                	jmp    2eb <__libc_realloc+0x2eb>
 306:	48 81 fd eb ff 01 00 	cmp    $0x1ffeb,%rbp
 30d:	0f 86 0f ff ff ff    	jbe    222 <__libc_realloc+0x222>
 313:	80 f9 2f             	cmp    $0x2f,%cl
 316:	0f 86 06 ff ff ff    	jbe    222 <__libc_realloc+0x222>
 31c:	41 f7 d0             	not    %r8d
 31f:	66 41 f7 c0 c0 0f    	test   $0xfc0,%r8w
 325:	0f 85 00 00 00 00    	jne    32b <__libc_realloc+0x32b>
			327: R_X86_64_PC32	.text.unlikely.__libc_realloc-0x4
 32b:	49 89 de             	mov    %rbx,%r14
 32e:	49 29 f6             	sub    %rsi,%r14
 331:	49 8b 74 24 20       	mov    0x20(%r12),%rsi
 336:	4d 8d 84 2e 13 10 00 	lea    0x1013(%r14,%rbp,1),%r8
 33d:	00 
 33e:	4d 89 c7             	mov    %r8,%r15
 341:	48 81 e6 00 f0 ff ff 	and    $0xfffffffffffff000,%rsi
 348:	49 81 e7 00 f0 ff ff 	and    $0xfffffffffffff000,%r15
 34f:	4c 39 fe             	cmp    %r15,%rsi
 352:	75 62                	jne    3b6 <__libc_realloc+0x3b6>
 354:	49 8b 44 24 20       	mov    0x20(%r12),%rax
 359:	49 81 e0 00 f0 ff ff 	and    $0xfffffffffffff000,%r8
 360:	49 83 ef 14          	sub    $0x14,%r15
 364:	49 89 7c 24 10       	mov    %rdi,0x10(%r12)
 369:	25 ff 0f 00 00       	and    $0xfff,%eax
 36e:	4c 09 c0             	or     %r8,%rax
 371:	49 89 44 24 20       	mov    %rax,0x20(%r12)
 376:	4f 8d 24 32          	lea    (%r10,%r14,1),%r12
 37a:	4d 01 fa             	add    %r15,%r10
 37d:	4d 29 f7             	sub    %r14,%r15
 380:	41 c6 02 00          	movb   $0x0,(%r10)
 384:	41 0f b6 44 24 fd    	movzbl -0x3(%r12),%eax
 38a:	83 e0 1f             	and    $0x1f,%eax
 38d:	41 29 ef             	sub    %ebp,%r15d
 390:	74 1a                	je     3ac <__libc_realloc+0x3ac>
 392:	44 89 fa             	mov    %r15d,%edx
 395:	f7 da                	neg    %edx
 397:	48 63 d2             	movslq %edx,%rdx
 39a:	41 c6 04 12 00       	movb   $0x0,(%r10,%rdx,1)
 39f:	41 83 ff 04          	cmp    $0x4,%r15d
 3a3:	7f 40                	jg     3e5 <__libc_realloc+0x3e5>
 3a5:	41 c1 e7 05          	shl    $0x5,%r15d
 3a9:	44 01 f8             	add    %r15d,%eax
 3ac:	41 88 44 24 fd       	mov    %al,-0x3(%r12)
 3b1:	e9 9c fe ff ff       	jmp    252 <__libc_realloc+0x252>
 3b6:	31 c0                	xor    %eax,%eax
 3b8:	b9 01 00 00 00       	mov    $0x1,%ecx
 3bd:	4c 89 fa             	mov    %r15,%rdx
 3c0:	4c 89 44 24 08       	mov    %r8,0x8(%rsp)
 3c5:	e8 00 00 00 00       	call   3ca <__libc_realloc+0x3ca>
			3c6: R_X86_64_PLT32	__mremap-0x4
 3ca:	4c 8b 44 24 08       	mov    0x8(%rsp),%r8
 3cf:	48 83 f8 ff          	cmp    $0xffffffffffffffff,%rax
 3d3:	48 89 c7             	mov    %rax,%rdi
 3d6:	0f 84 46 fe ff ff    	je     222 <__libc_realloc+0x222>
 3dc:	4c 8d 50 10          	lea    0x10(%rax),%r10
 3e0:	e9 6f ff ff ff       	jmp    354 <__libc_realloc+0x354>
 3e5:	45 89 7a fc          	mov    %r15d,-0x4(%r10)
 3e9:	83 e8 60             	sub    $0x60,%eax
 3ec:	41 c6 42 fb 00       	movb   $0x0,-0x5(%r10)
 3f1:	eb b9                	jmp    3ac <__libc_realloc+0x3ac>

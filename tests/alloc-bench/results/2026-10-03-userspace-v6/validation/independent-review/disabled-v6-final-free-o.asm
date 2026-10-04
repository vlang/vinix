
/Users/alex/code/vinix/third_party/useralloc-libc/build/useralloc/v6-prototype/cache/x86_64/e2aafe45791c748b1a101bcb8e017566e835e6f27fd623513503e67ee426bd6e/objects/obj/src/malloc/mallocng/free.o:     file format elf64-x86-64


Disassembly of section .text.unlikely.nontrivial_free:

0000000000000000 <nontrivial_free.cold>:
   0:	0f 0b                	ud2

Disassembly of section .text.nontrivial_free:

0000000000000000 <nontrivial_free>:
   0:	44 0f b6 47 20       	movzbl 0x20(%rdi),%r8d
   5:	89 f1                	mov    %esi,%ecx
   7:	b8 01 00 00 00       	mov    $0x1,%eax
   c:	8b 77 1c             	mov    0x1c(%rdi),%esi
   f:	8b 57 18             	mov    0x18(%rdi),%edx
  12:	d3 e0                	shl    %cl,%eax
  14:	44 89 c1             	mov    %r8d,%ecx
  17:	41 89 c2             	mov    %eax,%r10d
  1a:	0f b7 47 20          	movzwl 0x20(%rdi),%eax
  1e:	45 89 c3             	mov    %r8d,%r11d
  21:	09 d6                	or     %edx,%esi
  23:	83 e1 1f             	and    $0x1f,%ecx
  26:	ba 02 00 00 00       	mov    $0x2,%edx
  2b:	41 83 e3 1f          	and    $0x1f,%r11d
  2f:	d3 e2                	shl    %cl,%edx
  31:	66 c1 e8 06          	shr    $0x6,%ax
  35:	45 8d 0c 32          	lea    (%r10,%rsi,1),%r9d
  39:	83 ea 01             	sub    $0x1,%edx
  3c:	83 e0 3f             	and    $0x3f,%eax
  3f:	41 39 d1             	cmp    %edx,%r9d
  42:	74 6e                	je     b2 <nontrivial_free+0xb2>
  44:	85 f6                	test   %esi,%esi
  46:	75 4d                	jne    95 <nontrivial_free+0x95>
  48:	83 f8 2f             	cmp    $0x2f,%eax
  4b:	0f 8f 00 00 00 00    	jg     51 <nontrivial_free+0x51>
			4d: R_X86_64_PC32	.text.unlikely.nontrivial_free-0x4
  51:	48 8d 50 0a          	lea    0xa(%rax),%rdx
  55:	48 8b 04 d5 00 00 00 	mov    0x0(,%rdx,8),%rax
  5c:	00 
			59: R_X86_64_32S	__malloc_context
  5d:	48 39 f8             	cmp    %rdi,%rax
  60:	74 33                	je     95 <nontrivial_free+0x95>
  62:	48 83 7f 08 00       	cmpq   $0x0,0x8(%rdi)
  67:	0f 85 00 00 00 00    	jne    6d <nontrivial_free+0x6d>
			69: R_X86_64_PC32	.text.unlikely.nontrivial_free-0x4
  6d:	48 83 3f 00          	cmpq   $0x0,(%rdi)
  71:	0f 85 00 00 00 00    	jne    77 <nontrivial_free+0x77>
			73: R_X86_64_PC32	.text.unlikely.nontrivial_free-0x4
  77:	48 85 c0             	test   %rax,%rax
  7a:	0f 84 e7 01 00 00    	je     267 <nontrivial_free+0x267>
  80:	48 89 47 08          	mov    %rax,0x8(%rdi)
  84:	48 8b 00             	mov    (%rax),%rax
  87:	48 89 07             	mov    %rax,(%rdi)
  8a:	48 89 78 08          	mov    %rdi,0x8(%rax)
  8e:	48 8b 47 08          	mov    0x8(%rdi),%rax
  92:	48 89 38             	mov    %rdi,(%rax)
  95:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 9c <nontrivial_free+0x9c>
			98: R_X86_64_PC32	__libc-0x1
  9c:	84 c0                	test   %al,%al
  9e:	0f 85 dc 01 00 00    	jne    280 <nontrivial_free+0x280>
  a4:	8b 47 1c             	mov    0x1c(%rdi),%eax
  a7:	44 09 d0             	or     %r10d,%eax
  aa:	89 47 1c             	mov    %eax,0x1c(%rdi)
  ad:	31 c0                	xor    %eax,%eax
  af:	31 d2                	xor    %edx,%edx
  b1:	c3                   	ret
  b2:	41 83 e0 20          	and    $0x20,%r8d
  b6:	74 8c                	je     44 <nontrivial_free+0x44>
  b8:	48 8b 57 08          	mov    0x8(%rdi),%rdx
  bc:	83 f8 2f             	cmp    $0x2f,%eax
  bf:	0f 8f 15 01 00 00    	jg     1da <nontrivial_free+0x1da>
  c5:	4c 8b 47 20          	mov    0x20(%rdi),%r8
  c9:	84 c9                	test   %cl,%cl
  cb:	75 76                	jne    143 <nontrivial_free+0x143>
  cd:	49 81 f8 ff 0f 00 00 	cmp    $0xfff,%r8
  d4:	0f 86 ef 00 00 00    	jbe    1c9 <nontrivial_free+0x1c9>
  da:	48 63 c8             	movslq %eax,%rcx
  dd:	49 81 e0 00 f0 ff ff 	and    $0xfffffffffffff000,%r8
  e4:	44 0f b7 8c 09 00 00 	movzwl 0x0(%rcx,%rcx,1),%r9d
  eb:	00 00 
			e9: R_X86_64_32S	__malloc_size_classes
  ed:	49 83 e8 10          	sub    $0x10,%r8
  f1:	41 c1 e1 04          	shl    $0x4,%r9d
  f5:	4d 63 c9             	movslq %r9d,%r9
  f8:	4d 39 c8             	cmp    %r9,%r8
  fb:	73 4f                	jae    14c <nontrivial_free+0x14c>
  fd:	48 85 d2             	test   %rdx,%rdx
 100:	74 3c                	je     13e <nontrivial_free+0x13e>
 102:	48 8b 04 cd 00 00 00 	mov    0x0(,%rcx,8),%rax
 109:	00 
			106: R_X86_64_32S	__malloc_context+0x50
 10a:	48 39 d7             	cmp    %rdx,%rdi
 10d:	74 67                	je     176 <nontrivial_free+0x176>
 10f:	48 8b 37             	mov    (%rdi),%rsi
 112:	48 89 56 08          	mov    %rdx,0x8(%rsi)
 116:	48 8b 37             	mov    (%rdi),%rsi
 119:	48 89 32             	mov    %rsi,(%rdx)
 11c:	48 8d 51 0a          	lea    0xa(%rcx),%rdx
 120:	48 3b 3c cd 00 00 00 	cmp    0x0(,%rcx,8),%rdi
 127:	00 
			124: R_X86_64_32S	__malloc_context+0x50
 128:	0f 84 ba 00 00 00    	je     1e8 <nontrivial_free+0x1e8>
 12e:	66 0f ef c0          	pxor   %xmm0,%xmm0
 132:	0f 11 07             	movups %xmm0,(%rdi)
 135:	48 39 c7             	cmp    %rax,%rdi
 138:	0f 84 bb 00 00 00    	je     1f9 <nontrivial_free+0x1f9>
 13e:	e9 00 00 00 00       	jmp    143 <nontrivial_free+0x143>
			13f: R_X86_64_PC32	.text.free_group-0x4
 143:	49 81 f8 ff 0f 00 00 	cmp    $0xfff,%r8
 14a:	76 7d                	jbe    1c9 <nontrivial_free+0x1c9>
 14c:	48 39 d7             	cmp    %rdx,%rdi
 14f:	74 12                	je     163 <nontrivial_free+0x163>
 151:	48 85 d2             	test   %rdx,%rdx
 154:	74 e8                	je     13e <nontrivial_free+0x13e>
 156:	48 63 c8             	movslq %eax,%rcx
 159:	48 8b 04 cd 00 00 00 	mov    0x0(,%rcx,8),%rax
 160:	00 
			15d: R_X86_64_32S	__malloc_context+0x50
 161:	eb ac                	jmp    10f <nontrivial_free+0x10f>
 163:	8d 48 f9             	lea    -0x7(%rax),%ecx
 166:	83 f9 1f             	cmp    $0x1f,%ecx
 169:	76 19                	jbe    184 <nontrivial_free+0x184>
 16b:	48 63 c8             	movslq %eax,%rcx
 16e:	48 8b 04 cd 00 00 00 	mov    0x0(,%rcx,8),%rax
 175:	00 
			172: R_X86_64_32S	__malloc_context+0x50
 176:	48 c7 04 cd 00 00 00 	movq   $0x0,0x0(,%rcx,8)
 17d:	00 00 00 00 00 
			17a: R_X86_64_32S	__malloc_context+0x50
 182:	eb aa                	jmp    12e <nontrivial_free+0x12e>
 184:	48 63 c9             	movslq %ecx,%rcx
 187:	80 b9 00 00 00 00 63 	cmpb   $0x63,0x0(%rcx)
			189: R_X86_64_32S	__malloc_context+0x398
 18e:	76 db                	jbe    16b <nontrivial_free+0x16b>
 190:	41 83 c3 01          	add    $0x1,%r11d
 194:	48 63 c8             	movslq %eax,%rcx
 197:	49 63 c3             	movslq %r11d,%rax
 19a:	48 8d 04 c0          	lea    (%rax,%rax,8),%rax
 19e:	48 39 04 cd 00 00 00 	cmp    %rax,0x0(,%rcx,8)
 1a5:	00 
			1a2: R_X86_64_32S	__malloc_context+0x1f8
 1a6:	72 06                	jb     1ae <nontrivial_free+0x1ae>
 1a8:	41 83 fb 13          	cmp    $0x13,%r11d
 1ac:	7e c0                	jle    16e <nontrivial_free+0x16e>
 1ae:	85 f6                	test   %esi,%esi
 1b0:	0f 85 df fe ff ff    	jne    95 <nontrivial_free+0x95>
 1b6:	48 39 14 cd 00 00 00 	cmp    %rdx,0x0(,%rcx,8)
 1bd:	00 
			1ba: R_X86_64_32S	__malloc_context+0x50
 1be:	0f 84 d1 fe ff ff    	je     95 <nontrivial_free+0x95>
 1c4:	e9 00 00 00 00       	jmp    1c9 <nontrivial_free+0x1c9>
			1c5: R_X86_64_PC32	.text.unlikely.nontrivial_free-0x4
 1c9:	48 63 c8             	movslq %eax,%rcx
 1cc:	48 85 d2             	test   %rdx,%rdx
 1cf:	0f 85 2d ff ff ff    	jne    102 <nontrivial_free+0x102>
 1d5:	e9 64 ff ff ff       	jmp    13e <nontrivial_free+0x13e>
 1da:	48 85 d2             	test   %rdx,%rdx
 1dd:	0f 85 00 00 00 00    	jne    1e3 <nontrivial_free+0x1e3>
			1df: R_X86_64_PC32	.text.unlikely.nontrivial_free-0x4
 1e3:	e9 56 ff ff ff       	jmp    13e <nontrivial_free+0x13e>
 1e8:	48 8b 77 08          	mov    0x8(%rdi),%rsi
 1ec:	48 89 34 d5 00 00 00 	mov    %rsi,0x0(,%rdx,8)
 1f3:	00 
			1f0: R_X86_64_32S	__malloc_context
 1f4:	e9 35 ff ff ff       	jmp    12e <nontrivial_free+0x12e>
 1f9:	48 8b 34 cd 00 00 00 	mov    0x0(,%rcx,8),%rsi
 200:	00 
			1fd: R_X86_64_32S	__malloc_context+0x50
 201:	48 85 f6             	test   %rsi,%rsi
 204:	0f 84 34 ff ff ff    	je     13e <nontrivial_free+0x13e>
 20a:	8b 46 18             	mov    0x18(%rsi),%eax
 20d:	85 c0                	test   %eax,%eax
 20f:	0f 85 00 00 00 00    	jne    215 <nontrivial_free+0x215>
			211: R_X86_64_PC32	.text.unlikely.nontrivial_free-0x4
 215:	48 8b 46 10          	mov    0x10(%rsi),%rax
 219:	41 b8 02 00 00 00    	mov    $0x2,%r8d
 21f:	4c 8d 4e 1c          	lea    0x1c(%rsi),%r9
 223:	0f b6 48 08          	movzbl 0x8(%rax),%ecx
 227:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 22e <nontrivial_free+0x22e>
			22a: R_X86_64_PC32	__libc-0x1
 22e:	41 d3 e0             	shl    %cl,%r8d
 231:	45 8d 50 ff          	lea    -0x1(%r8),%r10d
 235:	41 f7 d8             	neg    %r8d
 238:	84 c0                	test   %al,%al
 23a:	75 16                	jne    252 <nontrivial_free+0x252>
 23c:	8b 56 1c             	mov    0x1c(%rsi),%edx
 23f:	41 21 d0             	and    %edx,%r8d
 242:	44 89 46 1c          	mov    %r8d,0x1c(%rsi)
 246:	41 21 d2             	and    %edx,%r10d
 249:	44 89 56 18          	mov    %r10d,0x18(%rsi)
 24d:	e9 ec fe ff ff       	jmp    13e <nontrivial_free+0x13e>
 252:	8b 56 1c             	mov    0x1c(%rsi),%edx
 255:	44 89 c1             	mov    %r8d,%ecx
 258:	21 d1                	and    %edx,%ecx
 25a:	89 d0                	mov    %edx,%eax
 25c:	f0 41 0f b1 09       	lock cmpxchg %ecx,(%r9)
 261:	39 c2                	cmp    %eax,%edx
 263:	75 ed                	jne    252 <nontrivial_free+0x252>
 265:	eb df                	jmp    246 <nontrivial_free+0x246>
 267:	66 48 0f 6e c7       	movq   %rdi,%xmm0
 26c:	66 0f 6c c0          	punpcklqdq %xmm0,%xmm0
 270:	0f 11 07             	movups %xmm0,(%rdi)
 273:	48 89 3c d5 00 00 00 	mov    %rdi,0x0(,%rdx,8)
 27a:	00 
			277: R_X86_64_32S	__malloc_context
 27b:	e9 15 fe ff ff       	jmp    95 <nontrivial_free+0x95>
 280:	f0 44 09 57 1c       	lock or %r10d,0x1c(%rdi)
 285:	e9 23 fe ff ff       	jmp    ad <nontrivial_free+0xad>

Disassembly of section .text.unlikely.free_group:

0000000000000000 <free_group.cold>:
   0:	0f 0b                	ud2

Disassembly of section .text.free_group:

0000000000000000 <free_group>:
   0:	53                   	push   %rbx
   1:	0f b7 57 20          	movzwl 0x20(%rdi),%edx
   5:	48 89 fb             	mov    %rdi,%rbx
   8:	66 c1 ea 06          	shr    $0x6,%dx
   c:	83 e2 3f             	and    $0x3f,%edx
   f:	83 fa 2f             	cmp    $0x2f,%edx
  12:	7e 7c                	jle    90 <free_group+0x90>
  14:	48 81 7b 20 ff 0f 00 	cmpq   $0xfff,0x20(%rbx)
  1b:	00 
  1c:	0f 86 bb 00 00 00    	jbe    dd <free_group+0xdd>
  22:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 29 <free_group+0x29>
			25: R_X86_64_PC32	__malloc_context+0x3b4
  29:	8d 48 01             	lea    0x1(%rax),%ecx
  2c:	3c ff                	cmp    $0xff,%al
  2e:	74 7a                	je     aa <free_group+0xaa>
  30:	83 ea 07             	sub    $0x7,%edx
  33:	88 0d 00 00 00 00    	mov    %cl,0x0(%rip)        # 39 <free_group+0x39>
			35: R_X86_64_PC32	__malloc_context+0x3b4
  39:	83 fa 1f             	cmp    $0x1f,%edx
  3c:	77 09                	ja     47 <free_group+0x47>
  3e:	48 63 d2             	movslq %edx,%rdx
  41:	88 8a 00 00 00 00    	mov    %cl,0x0(%rdx)
			43: R_X86_64_32S	__malloc_context+0x378
  47:	48 8b 53 20          	mov    0x20(%rbx),%rdx
  4b:	48 8b 43 10          	mov    0x10(%rbx),%rax
  4f:	48 81 e2 00 f0 ff ff 	and    $0xfffffffffffff000,%rdx
  56:	66 0f ef c0          	pxor   %xmm0,%xmm0
  5a:	48 c7 43 20 00 00 00 	movq   $0x0,0x20(%rbx)
  61:	00 
  62:	0f 11 03             	movups %xmm0,(%rbx)
  65:	0f 11 43 10          	movups %xmm0,0x10(%rbx)
  69:	48 8b 0d 00 00 00 00 	mov    0x0(%rip),%rcx        # 70 <free_group+0x70>
			6c: R_X86_64_PC32	__malloc_context+0xc
  70:	48 85 c9             	test   %rcx,%rcx
  73:	0f 84 8a 01 00 00    	je     203 <free_group+0x203>
  79:	48 89 4b 08          	mov    %rcx,0x8(%rbx)
  7d:	48 8b 09             	mov    (%rcx),%rcx
  80:	48 89 0b             	mov    %rcx,(%rbx)
  83:	48 89 59 08          	mov    %rbx,0x8(%rcx)
  87:	48 8b 4b 08          	mov    0x8(%rbx),%rcx
  8b:	48 89 19             	mov    %rbx,(%rcx)
  8e:	5b                   	pop    %rbx
  8f:	c3                   	ret
  90:	0f b6 47 20          	movzbl 0x20(%rdi),%eax
  94:	48 63 ca             	movslq %edx,%rcx
  97:	83 e0 1f             	and    $0x1f,%eax
  9a:	48 f7 d0             	not    %rax
  9d:	48 01 04 cd 00 00 00 	add    %rax,0x0(,%rcx,8)
  a4:	00 
			a1: R_X86_64_32S	__malloc_context+0x1f8
  a5:	e9 6a ff ff ff       	jmp    14 <free_group+0x14>
  aa:	b8 00 00 00 00       	mov    $0x0,%eax
			ab: R_X86_64_32	__malloc_context+0x378
  af:	eb 1a                	jmp    cb <free_group+0xcb>
  b1:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
  b8:	00 00 00 00 
  bc:	0f 1f 40 00          	nopl   0x0(%rax)
  c0:	c6 00 00             	movb   $0x0,(%rax)
  c3:	48 83 c0 02          	add    $0x2,%rax
  c7:	c6 40 ff 00          	movb   $0x0,-0x1(%rax)
  cb:	48 3d 00 00 00 00    	cmp    $0x0,%rax
			cd: R_X86_64_32S	__malloc_context+0x398
  d1:	75 ed                	jne    c0 <free_group+0xc0>
  d3:	b9 01 00 00 00       	mov    $0x1,%ecx
  d8:	e9 53 ff ff ff       	jmp    30 <free_group+0x30>
  dd:	48 8b 53 10          	mov    0x10(%rbx),%rdx
  e1:	f6 c2 0f             	test   $0xf,%dl
  e4:	0f 85 00 00 00 00    	jne    ea <free_group+0xea>
			e6: R_X86_64_PC32	.text.unlikely.free_group-0x4
  ea:	0f b6 72 fd          	movzbl -0x3(%rdx),%esi
  ee:	0f b7 4a fe          	movzwl -0x2(%rdx),%ecx
  f2:	41 89 f0             	mov    %esi,%r8d
  f5:	83 e6 1f             	and    $0x1f,%esi
  f8:	41 83 e0 1f          	and    $0x1f,%r8d
  fc:	80 7a fc 00          	cmpb   $0x0,-0x4(%rdx)
 100:	74 18                	je     11a <free_group+0x11a>
 102:	85 c9                	test   %ecx,%ecx
 104:	0f 85 00 00 00 00    	jne    10a <free_group+0x10a>
			106: R_X86_64_PC32	.text.unlikely.free_group-0x4
 10a:	48 63 4a f8          	movslq -0x8(%rdx),%rcx
 10e:	81 f9 ff ff 00 00    	cmp    $0xffff,%ecx
 114:	0f 8e 00 00 00 00    	jle    11a <free_group+0x11a>
			116: R_X86_64_PC32	.text.unlikely.free_group-0x4
 11a:	89 c8                	mov    %ecx,%eax
 11c:	48 89 d7             	mov    %rdx,%rdi
 11f:	c1 e0 04             	shl    $0x4,%eax
 122:	48 98                	cltq
 124:	48 29 c7             	sub    %rax,%rdi
 127:	48 8d 47 f0          	lea    -0x10(%rdi),%rax
 12b:	48 8b 7f f0          	mov    -0x10(%rdi),%rdi
 12f:	48 3b 47 10          	cmp    0x10(%rdi),%rax
 133:	0f 85 00 00 00 00    	jne    139 <free_group+0x139>
			135: R_X86_64_PC32	.text.unlikely.free_group-0x4
 139:	0f b6 47 20          	movzbl 0x20(%rdi),%eax
 13d:	41 89 c1             	mov    %eax,%r9d
 140:	83 e0 1f             	and    $0x1f,%eax
 143:	41 83 e1 1f          	and    $0x1f,%r9d
 147:	39 c6                	cmp    %eax,%esi
 149:	0f 8f 00 00 00 00    	jg     14f <free_group+0x14f>
			14b: R_X86_64_PC32	.text.unlikely.free_group-0x4
 14f:	8b 47 18             	mov    0x18(%rdi),%eax
 152:	44 0f a3 c0          	bt     %r8d,%eax
 156:	0f 82 00 00 00 00    	jb     15c <free_group+0x15c>
			158: R_X86_64_PC32	.text.unlikely.free_group-0x4
 15c:	8b 47 1c             	mov    0x1c(%rdi),%eax
 15f:	44 0f a3 c0          	bt     %r8d,%eax
 163:	0f 82 00 00 00 00    	jb     169 <free_group+0x169>
			165: R_X86_64_PC32	.text.unlikely.free_group-0x4
 169:	48 89 f8             	mov    %rdi,%rax
 16c:	4c 8b 15 00 00 00 00 	mov    0x0(%rip),%r10        # 173 <free_group+0x173>
			16f: R_X86_64_PC32	__malloc_context-0x4
 173:	48 25 00 f0 ff ff    	and    $0xfffffffffffff000,%rax
 179:	4c 39 10             	cmp    %r10,(%rax)
 17c:	0f 85 00 00 00 00    	jne    182 <free_group+0x182>
			17e: R_X86_64_PC32	.text.unlikely.free_group-0x4
 182:	0f b7 47 20          	movzwl 0x20(%rdi),%eax
 186:	66 c1 e8 06          	shr    $0x6,%ax
 18a:	83 e0 3f             	and    $0x3f,%eax
 18d:	83 f8 2f             	cmp    $0x2f,%eax
 190:	7f 50                	jg     1e2 <free_group+0x1e2>
 192:	0f b7 84 00 00 00 00 	movzwl 0x0(%rax,%rax,1),%eax
 199:	00 
			196: R_X86_64_32S	__malloc_size_classes
 19a:	41 89 f0             	mov    %esi,%r8d
 19d:	44 0f af c0          	imul   %eax,%r8d
 1a1:	44 39 c1             	cmp    %r8d,%ecx
 1a4:	0f 8c 00 00 00 00    	jl     1aa <free_group+0x1aa>
			1a6: R_X86_64_PC32	.text.unlikely.free_group-0x4
 1aa:	44 01 c0             	add    %r8d,%eax
 1ad:	39 c1                	cmp    %eax,%ecx
 1af:	7d 2c                	jge    1dd <free_group+0x1dd>
 1b1:	48 8b 47 20          	mov    0x20(%rdi),%rax
 1b5:	48 c1 e8 0c          	shr    $0xc,%rax
 1b9:	74 11                	je     1cc <free_group+0x1cc>
 1bb:	48 c1 e0 08          	shl    $0x8,%rax
 1bf:	48 83 e8 01          	sub    $0x1,%rax
 1c3:	48 39 c8             	cmp    %rcx,%rax
 1c6:	0f 82 00 00 00 00    	jb     1cc <free_group+0x1cc>
			1c8: R_X86_64_PC32	.text.unlikely.free_group-0x4
 1cc:	48 c7 02 00 00 00 00 	movq   $0x0,(%rdx)
 1d3:	e8 00 00 00 00       	call   1d8 <free_group+0x1d8>
			1d4: R_X86_64_PC32	.text.nontrivial_free-0x4
 1d8:	e9 79 fe ff ff       	jmp    56 <free_group+0x56>
 1dd:	e9 00 00 00 00       	jmp    1e2 <free_group+0x1e2>
			1de: R_X86_64_PC32	.text.unlikely.free_group-0x4
 1e2:	83 f8 3f             	cmp    $0x3f,%eax
 1e5:	0f 85 00 00 00 00    	jne    1eb <free_group+0x1eb>
			1e7: R_X86_64_PC32	.text.unlikely.free_group-0x4
 1eb:	45 84 c9             	test   %r9b,%r9b
 1ee:	0f 85 00 00 00 00    	jne    1f4 <free_group+0x1f4>
			1f0: R_X86_64_PC32	.text.unlikely.free_group-0x4
 1f4:	48 81 7f 20 ff 0f 00 	cmpq   $0xfff,0x20(%rdi)
 1fb:	00 
 1fc:	77 b3                	ja     1b1 <free_group+0x1b1>
 1fe:	e9 00 00 00 00       	jmp    203 <free_group+0x203>
			1ff: R_X86_64_PC32	.text.unlikely.free_group-0x4
 203:	66 48 0f 6e c3       	movq   %rbx,%xmm0
 208:	66 0f 6c c0          	punpcklqdq %xmm0,%xmm0
 20c:	0f 11 03             	movups %xmm0,(%rbx)
 20f:	48 89 1d 00 00 00 00 	mov    %rbx,0x0(%rip)        # 216 <free_group+0x216>
			212: R_X86_64_PC32	__malloc_context+0xc
 216:	e9 73 fe ff ff       	jmp    8e <free_group+0x8e>

Disassembly of section .text.unlikely.__libc_free:

0000000000000000 <__libc_free.cold>:
   0:	0f 0b                	ud2

Disassembly of section .text.__libc_free:

0000000000000000 <__libc_free>:
   0:	48 85 ff             	test   %rdi,%rdi
   3:	0f 84 80 02 00 00    	je     289 <__libc_free+0x289>
   9:	41 55                	push   %r13
   b:	48 89 fe             	mov    %rdi,%rsi
   e:	48 89 f8             	mov    %rdi,%rax
  11:	41 54                	push   %r12
  13:	55                   	push   %rbp
  14:	53                   	push   %rbx
  15:	48 83 ec 08          	sub    $0x8,%rsp
  19:	83 e6 0f             	and    $0xf,%esi
  1c:	0f 85 00 00 00 00    	jne    22 <__libc_free+0x22>
			1e: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
  22:	44 0f b7 5f fe       	movzwl -0x2(%rdi),%r11d
  27:	0f b6 7f fd          	movzbl -0x3(%rdi),%edi
  2b:	89 f9                	mov    %edi,%ecx
  2d:	89 fd                	mov    %edi,%ebp
  2f:	83 e1 1f             	and    $0x1f,%ecx
  32:	83 e5 1f             	and    $0x1f,%ebp
  35:	80 78 fc 00          	cmpb   $0x0,-0x4(%rax)
  39:	74 1a                	je     55 <__libc_free+0x55>
  3b:	45 85 db             	test   %r11d,%r11d
  3e:	0f 85 00 00 00 00    	jne    44 <__libc_free+0x44>
			40: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
  44:	4c 63 58 f8          	movslq -0x8(%rax),%r11
  48:	41 81 fb ff ff 00 00 	cmp    $0xffff,%r11d
  4f:	0f 8e 00 00 00 00    	jle    55 <__libc_free+0x55>
			51: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
  55:	44 89 da             	mov    %r11d,%edx
  58:	49 89 c0             	mov    %rax,%r8
  5b:	c1 e2 04             	shl    $0x4,%edx
  5e:	48 63 d2             	movslq %edx,%rdx
  61:	49 29 d0             	sub    %rdx,%r8
  64:	49 8b 58 f0          	mov    -0x10(%r8),%rbx
  68:	49 8d 50 f0          	lea    -0x10(%r8),%rdx
  6c:	4c 8b 53 10          	mov    0x10(%rbx),%r10
  70:	4c 39 d2             	cmp    %r10,%rdx
  73:	0f 85 00 00 00 00    	jne    79 <__libc_free+0x79>
			75: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
  79:	44 0f b6 4b 20       	movzbl 0x20(%rbx),%r9d
  7e:	44 89 ca             	mov    %r9d,%edx
  81:	45 89 c8             	mov    %r9d,%r8d
  84:	83 e2 1f             	and    $0x1f,%edx
  87:	41 83 e0 1f          	and    $0x1f,%r8d
  8b:	39 d5                	cmp    %edx,%ebp
  8d:	0f 8f 00 00 00 00    	jg     93 <__libc_free+0x93>
			8f: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
  93:	8b 53 18             	mov    0x18(%rbx),%edx
  96:	0f a3 ca             	bt     %ecx,%edx
  99:	0f 82 00 00 00 00    	jb     9f <__libc_free+0x9f>
			9b: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
  9f:	8b 53 1c             	mov    0x1c(%rbx),%edx
  a2:	0f a3 ca             	bt     %ecx,%edx
  a5:	0f 82 00 00 00 00    	jb     ab <__libc_free+0xab>
			a7: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
  ab:	48 89 da             	mov    %rbx,%rdx
  ae:	4c 8b 2d 00 00 00 00 	mov    0x0(%rip),%r13        # b5 <__libc_free+0xb5>
			b1: R_X86_64_PC32	__malloc_context-0x4
  b5:	48 81 e2 00 f0 ff ff 	and    $0xfffffffffffff000,%rdx
  bc:	4c 39 2a             	cmp    %r13,(%rdx)
  bf:	0f 85 00 00 00 00    	jne    c5 <__libc_free+0xc5>
			c1: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
  c5:	0f b7 53 20          	movzwl 0x20(%rbx),%edx
  c9:	66 c1 ea 06          	shr    $0x6,%dx
  cd:	83 e2 3f             	and    $0x3f,%edx
  d0:	83 fa 2f             	cmp    $0x2f,%edx
  d3:	0f 8f fc 00 00 00    	jg     1d5 <__libc_free+0x1d5>
  d9:	0f b7 b4 12 00 00 00 	movzwl 0x0(%rdx,%rdx,1),%esi
  e0:	00 
			dd: R_X86_64_32S	__malloc_size_classes
  e1:	89 ea                	mov    %ebp,%edx
  e3:	0f af d6             	imul   %esi,%edx
  e6:	41 39 d3             	cmp    %edx,%r11d
  e9:	0f 8c 00 00 00 00    	jl     ef <__libc_free+0xef>
			eb: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
  ef:	01 f2                	add    %esi,%edx
  f1:	41 39 d3             	cmp    %edx,%r11d
  f4:	0f 8d 00 00 00 00    	jge    fa <__libc_free+0xfa>
			f6: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
  fa:	c1 e6 04             	shl    $0x4,%esi
  fd:	48 63 f6             	movslq %esi,%rsi
 100:	48 8b 53 20          	mov    0x20(%rbx),%rdx
 104:	48 c1 ea 0c          	shr    $0xc,%rdx
 108:	74 25                	je     12f <__libc_free+0x12f>
 10a:	49 89 d4             	mov    %rdx,%r12
 10d:	48 c1 e2 08          	shl    $0x8,%rdx
 111:	48 83 ea 01          	sub    $0x1,%rdx
 115:	49 c1 e4 0c          	shl    $0xc,%r12
 119:	4c 39 da             	cmp    %r11,%rdx
 11c:	0f 82 00 00 00 00    	jb     122 <__libc_free+0x122>
			11e: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 122:	49 8d 54 24 f0       	lea    -0x10(%r12),%rdx
 127:	41 83 e1 1f          	and    $0x1f,%r9d
 12b:	48 0f 44 f2          	cmove  %rdx,%rsi
 12f:	0f b6 d1             	movzbl %cl,%edx
 132:	48 0f af d6          	imul   %rsi,%rdx
 136:	48 8d 54 16 fc       	lea    -0x4(%rsi,%rdx,1),%rdx
 13b:	49 8d 74 12 10       	lea    0x10(%r10,%rdx,1),%rsi
 140:	89 fa                	mov    %edi,%edx
 142:	c0 ea 05             	shr    $0x5,%dl
 145:	40 80 ff 9f          	cmp    $0x9f,%dil
 149:	0f 87 ab 00 00 00    	ja     1fa <__libc_free+0x1fa>
 14f:	0f b6 d2             	movzbl %dl,%edx
 152:	48 89 f7             	mov    %rsi,%rdi
 155:	48 29 c7             	sub    %rax,%rdi
 158:	48 39 d7             	cmp    %rdx,%rdi
 15b:	0f 82 00 00 00 00    	jb     161 <__libc_free+0x161>
			15d: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 161:	48 89 f7             	mov    %rsi,%rdi
 164:	48 29 d7             	sub    %rdx,%rdi
 167:	80 3f 00             	cmpb   $0x0,(%rdi)
 16a:	0f 85 00 00 00 00    	jne    170 <__libc_free+0x170>
			16c: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 170:	80 3e 00             	cmpb   $0x0,(%rsi)
 173:	0f 85 00 00 00 00    	jne    179 <__libc_free+0x179>
			175: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 179:	be 01 00 00 00       	mov    $0x1,%esi
 17e:	31 d2                	xor    %edx,%edx
 180:	bf 02 00 00 00       	mov    $0x2,%edi
 185:	c6 40 fd ff          	movb   $0xff,-0x3(%rax)
 189:	d3 e6                	shl    %cl,%esi
 18b:	66 89 50 fe          	mov    %dx,-0x2(%rax)
 18f:	44 89 c1             	mov    %r8d,%ecx
 192:	d3 e7                	shl    %cl,%edi
 194:	83 ef 01             	sub    $0x1,%edi
 197:	8b 53 1c             	mov    0x1c(%rbx),%edx
 19a:	8b 43 18             	mov    0x18(%rbx),%eax
 19d:	09 d0                	or     %edx,%eax
 19f:	85 c6                	test   %eax,%esi
 1a1:	0f 85 00 00 00 00    	jne    1a7 <__libc_free+0x1a7>
			1a3: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 1a7:	85 d2                	test   %edx,%edx
 1a9:	74 79                	je     224 <__libc_free+0x224>
 1ab:	01 f0                	add    %esi,%eax
 1ad:	39 f8                	cmp    %edi,%eax
 1af:	74 73                	je     224 <__libc_free+0x224>
 1b1:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 1b8 <__libc_free+0x1b8>
			1b4: R_X86_64_PC32	__libc-0x1
 1b8:	8d 0c 16             	lea    (%rsi,%rdx,1),%ecx
 1bb:	84 c0                	test   %al,%al
 1bd:	74 60                	je     21f <__libc_free+0x21f>
 1bf:	89 d0                	mov    %edx,%eax
 1c1:	f0 0f b1 4b 1c       	lock cmpxchg %ecx,0x1c(%rbx)
 1c6:	39 c2                	cmp    %eax,%edx
 1c8:	75 cd                	jne    197 <__libc_free+0x197>
 1ca:	48 83 c4 08          	add    $0x8,%rsp
 1ce:	5b                   	pop    %rbx
 1cf:	5d                   	pop    %rbp
 1d0:	41 5c                	pop    %r12
 1d2:	41 5d                	pop    %r13
 1d4:	c3                   	ret
 1d5:	83 fa 3f             	cmp    $0x3f,%edx
 1d8:	0f 85 00 00 00 00    	jne    1de <__libc_free+0x1de>
			1da: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 1de:	45 84 c0             	test   %r8b,%r8b
 1e1:	0f 85 00 00 00 00    	jne    1e7 <__libc_free+0x1e7>
			1e3: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 1e7:	48 81 7b 20 ff 0f 00 	cmpq   $0xfff,0x20(%rbx)
 1ee:	00 
 1ef:	0f 87 0b ff ff ff    	ja     100 <__libc_free+0x100>
 1f5:	e9 00 00 00 00       	jmp    1fa <__libc_free+0x1fa>
			1f6: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 1fa:	80 fa 05             	cmp    $0x5,%dl
 1fd:	0f 85 00 00 00 00    	jne    203 <__libc_free+0x203>
			1ff: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 203:	8b 56 fc             	mov    -0x4(%rsi),%edx
 206:	48 83 fa 04          	cmp    $0x4,%rdx
 20a:	0f 86 00 00 00 00    	jbe    210 <__libc_free+0x210>
			20c: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 210:	80 7e fb 00          	cmpb   $0x0,-0x5(%rsi)
 214:	0f 84 38 ff ff ff    	je     152 <__libc_free+0x152>
 21a:	e9 00 00 00 00       	jmp    21f <__libc_free+0x21f>
			21b: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 21f:	89 4b 1c             	mov    %ecx,0x1c(%rbx)
 222:	eb a6                	jmp    1ca <__libc_free+0x1ca>
 224:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 22b <__libc_free+0x22b>
			227: R_X86_64_PC32	__libc-0x1
 22b:	84 c0                	test   %al,%al
 22d:	75 42                	jne    271 <__libc_free+0x271>
 22f:	89 ee                	mov    %ebp,%esi
 231:	48 89 df             	mov    %rbx,%rdi
 234:	e8 00 00 00 00       	call   239 <__libc_free+0x239>
			235: R_X86_64_PC32	.text.nontrivial_free-0x4
 239:	48 89 c5             	mov    %rax,%rbp
 23c:	8b 05 00 00 00 00    	mov    0x0(%rip),%eax        # 242 <__libc_free+0x242>
			23e: R_X86_64_PC32	__malloc_lock-0x4
 242:	48 89 d3             	mov    %rdx,%rbx
 245:	85 c0                	test   %eax,%eax
 247:	78 34                	js     27d <__libc_free+0x27d>
 249:	48 85 db             	test   %rbx,%rbx
 24c:	0f 84 78 ff ff ff    	je     1ca <__libc_free+0x1ca>
 252:	e8 00 00 00 00       	call   257 <__libc_free+0x257>
			253: R_X86_64_PLT32	___errno_location-0x4
 257:	48 89 de             	mov    %rbx,%rsi
 25a:	48 89 ef             	mov    %rbp,%rdi
 25d:	44 8b 28             	mov    (%rax),%r13d
 260:	49 89 c4             	mov    %rax,%r12
 263:	e8 00 00 00 00       	call   268 <__libc_free+0x268>
			264: R_X86_64_PLT32	munmap-0x4
 268:	45 89 2c 24          	mov    %r13d,(%r12)
 26c:	e9 59 ff ff ff       	jmp    1ca <__libc_free+0x1ca>
 271:	bf 00 00 00 00       	mov    $0x0,%edi
			272: R_X86_64_32	__malloc_lock
 276:	e8 00 00 00 00       	call   27b <__libc_free+0x27b>
			277: R_X86_64_PLT32	__lock-0x4
 27b:	eb b2                	jmp    22f <__libc_free+0x22f>
 27d:	bf 00 00 00 00       	mov    $0x0,%edi
			27e: R_X86_64_32	__malloc_lock
 282:	e8 00 00 00 00       	call   287 <__libc_free+0x287>
			283: R_X86_64_PLT32	__unlock-0x4
 287:	eb c0                	jmp    249 <__libc_free+0x249>
 289:	c3                   	ret

Disassembly of section .text.unlikely.malloc_trim:

0000000000000000 <malloc_trim.cold>:
   0:	0f 0b                	ud2

Disassembly of section .text.malloc_trim:

0000000000000000 <malloc_trim>:
   0:	41 56                	push   %r14
   2:	41 55                	push   %r13
   4:	41 54                	push   %r12
   6:	55                   	push   %rbp
   7:	53                   	push   %rbx
   8:	e8 00 00 00 00       	call   d <malloc_trim+0xd>
			9: R_X86_64_PLT32	___errno_location-0x4
   d:	44 8b 20             	mov    (%rax),%r12d
  10:	48 89 c5             	mov    %rax,%rbp
  13:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 1a <malloc_trim+0x1a>
			16: R_X86_64_PC32	__libc-0x1
  1a:	84 c0                	test   %al,%al
  1c:	75 0e                	jne    2c <malloc_trim+0x2c>
  1e:	41 bd 00 00 00 00    	mov    $0x0,%r13d
			20: R_X86_64_32	__malloc_context+0x1d0
  24:	31 db                	xor    %ebx,%ebx
  26:	66 0f ef c0          	pxor   %xmm0,%xmm0
  2a:	eb 36                	jmp    62 <malloc_trim+0x62>
  2c:	bf 00 00 00 00       	mov    $0x0,%edi
			2d: R_X86_64_32	__malloc_lock
  31:	e8 00 00 00 00       	call   36 <malloc_trim+0x36>
			32: R_X86_64_PLT32	__lock-0x4
  36:	eb e6                	jmp    1e <malloc_trim+0x1e>
  38:	66 48 0f 6e c8       	movq   %rax,%xmm1
  3d:	66 0f 6c c9          	punpcklqdq %xmm1,%xmm1
  41:	0f 11 08             	movups %xmm1,(%rax)
  44:	48 89 05 00 00 00 00 	mov    %rax,0x0(%rip)        # 4b <malloc_trim+0x4b>
			47: R_X86_64_PC32	__malloc_context+0xc
  4b:	e8 00 00 00 00       	call   50 <malloc_trim+0x50>
			4c: R_X86_64_PLT32	munmap-0x4
  50:	66 0f ef c0          	pxor   %xmm0,%xmm0
  54:	85 c0                	test   %eax,%eax
  56:	0f 94 c0             	sete   %al
  59:	0f b6 c0             	movzbl %al,%eax
  5c:	09 c3                	or     %eax,%ebx
  5e:	49 83 c5 08          	add    $0x8,%r13
  62:	49 81 fd 00 00 00 00 	cmp    $0x0,%r13
			65: R_X86_64_32S	__malloc_context+0x1f8
  69:	74 52                	je     bd <malloc_trim+0xbd>
  6b:	49 8b 45 00          	mov    0x0(%r13),%rax
  6f:	48 85 c0             	test   %rax,%rax
  72:	74 ea                	je     5e <malloc_trim+0x5e>
  74:	49 c7 45 00 00 00 00 	movq   $0x0,0x0(%r13)
  7b:	00 
  7c:	48 8b 70 20          	mov    0x20(%rax),%rsi
  80:	48 8b 78 10          	mov    0x10(%rax),%rdi
  84:	0f 11 00             	movups %xmm0,(%rax)
  87:	0f 11 40 10          	movups %xmm0,0x10(%rax)
  8b:	48 8b 15 00 00 00 00 	mov    0x0(%rip),%rdx        # 92 <malloc_trim+0x92>
			8e: R_X86_64_PC32	__malloc_context+0xc
  92:	48 81 e6 00 f0 ff ff 	and    $0xfffffffffffff000,%rsi
  99:	48 c7 40 20 00 00 00 	movq   $0x0,0x20(%rax)
  a0:	00 
  a1:	48 85 d2             	test   %rdx,%rdx
  a4:	74 92                	je     38 <malloc_trim+0x38>
  a6:	48 89 50 08          	mov    %rdx,0x8(%rax)
  aa:	48 8b 12             	mov    (%rdx),%rdx
  ad:	48 89 10             	mov    %rdx,(%rax)
  b0:	48 89 42 08          	mov    %rax,0x8(%rdx)
  b4:	48 8b 50 08          	mov    0x8(%rax),%rdx
  b8:	48 89 02             	mov    %rax,(%rdx)
  bb:	eb 8e                	jmp    4b <malloc_trim+0x4b>
  bd:	41 be 00 00 00 00    	mov    $0x0,%r14d
			bf: R_X86_64_32	__malloc_context+0x50
  c3:	41 bd 02 00 00 00    	mov    $0x2,%r13d
  c9:	e9 36 01 00 00       	jmp    204 <malloc_trim+0x204>
  ce:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
  d5:	00 00 00 00 
  d9:	0f 1f 80 00 00 00 00 	nopl   0x0(%rax)
  e0:	48 8b 7f 08          	mov    0x8(%rdi),%rdi
  e4:	48 39 fe             	cmp    %rdi,%rsi
  e7:	74 1f                	je     108 <malloc_trim+0x108>
  e9:	0f b6 4f 20          	movzbl 0x20(%rdi),%ecx
  ed:	f6 c1 20             	test   $0x20,%cl
  f0:	74 ee                	je     e0 <malloc_trim+0xe0>
  f2:	8b 57 18             	mov    0x18(%rdi),%edx
  f5:	8b 47 1c             	mov    0x1c(%rdi),%eax
  f8:	09 c2                	or     %eax,%edx
  fa:	44 89 e8             	mov    %r13d,%eax
  fd:	d3 e0                	shl    %cl,%eax
  ff:	83 e8 01             	sub    $0x1,%eax
 102:	39 c2                	cmp    %eax,%edx
 104:	75 da                	jne    e0 <malloc_trim+0xe0>
 106:	eb 0a                	jmp    112 <malloc_trim+0x112>
 108:	f6 47 20 20          	testb  $0x20,0x20(%rdi)
 10c:	0f 84 ee 00 00 00    	je     200 <malloc_trim+0x200>
 112:	8b 57 18             	mov    0x18(%rdi),%edx
 115:	8b 47 1c             	mov    0x1c(%rdi),%eax
 118:	0f b6 4f 20          	movzbl 0x20(%rdi),%ecx
 11c:	09 c2                	or     %eax,%edx
 11e:	44 89 e8             	mov    %r13d,%eax
 121:	d3 e0                	shl    %cl,%eax
 123:	83 e8 01             	sub    $0x1,%eax
 126:	39 c2                	cmp    %eax,%edx
 128:	0f 85 d2 00 00 00    	jne    200 <malloc_trim+0x200>
 12e:	48 8b 47 08          	mov    0x8(%rdi),%rax
 132:	48 39 c7             	cmp    %rax,%rdi
 135:	74 4f                	je     186 <malloc_trim+0x186>
 137:	48 8b 17             	mov    (%rdi),%rdx
 13a:	48 89 42 08          	mov    %rax,0x8(%rdx)
 13e:	48 8b 17             	mov    (%rdi),%rdx
 141:	48 89 10             	mov    %rdx,(%rax)
 144:	49 3b 3e             	cmp    (%r14),%rdi
 147:	74 34                	je     17d <malloc_trim+0x17d>
 149:	66 0f ef c0          	pxor   %xmm0,%xmm0
 14d:	0f 11 07             	movups %xmm0,(%rdi)
 150:	49 8b 36             	mov    (%r14),%rsi
 153:	48 85 f6             	test   %rsi,%rsi
 156:	74 07                	je     15f <malloc_trim+0x15f>
 158:	8b 46 18             	mov    0x18(%rsi),%eax
 15b:	85 c0                	test   %eax,%eax
 15d:	74 30                	je     18f <malloc_trim+0x18f>
 15f:	e8 00 00 00 00       	call   164 <malloc_trim+0x164>
			160: R_X86_64_PC32	.text.free_group-0x4
 164:	48 85 d2             	test   %rdx,%rdx
 167:	75 7d                	jne    1e6 <malloc_trim+0x1e6>
 169:	49 8b 36             	mov    (%r14),%rsi
 16c:	48 85 f6             	test   %rsi,%rsi
 16f:	0f 84 8b 00 00 00    	je     200 <malloc_trim+0x200>
 175:	48 89 f7             	mov    %rsi,%rdi
 178:	e9 6c ff ff ff       	jmp    e9 <malloc_trim+0xe9>
 17d:	48 8b 47 08          	mov    0x8(%rdi),%rax
 181:	49 89 06             	mov    %rax,(%r14)
 184:	eb c3                	jmp    149 <malloc_trim+0x149>
 186:	49 c7 06 00 00 00 00 	movq   $0x0,(%r14)
 18d:	eb ba                	jmp    149 <malloc_trim+0x149>
 18f:	8b 46 18             	mov    0x18(%rsi),%eax
 192:	85 c0                	test   %eax,%eax
 194:	0f 85 00 00 00 00    	jne    19a <malloc_trim+0x19a>
			196: R_X86_64_PC32	.text.unlikely.malloc_trim-0x4
 19a:	48 8b 46 10          	mov    0x10(%rsi),%rax
 19e:	45 89 e8             	mov    %r13d,%r8d
 1a1:	4c 8d 56 1c          	lea    0x1c(%rsi),%r10
 1a5:	0f b6 48 08          	movzbl 0x8(%rax),%ecx
 1a9:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 1b0 <malloc_trim+0x1b0>
			1ac: R_X86_64_PC32	__libc-0x1
 1b0:	41 d3 e0             	shl    %cl,%r8d
 1b3:	45 8d 48 ff          	lea    -0x1(%r8),%r9d
 1b7:	41 f7 d8             	neg    %r8d
 1ba:	84 c0                	test   %al,%al
 1bc:	75 13                	jne    1d1 <malloc_trim+0x1d1>
 1be:	8b 56 1c             	mov    0x1c(%rsi),%edx
 1c1:	41 21 d0             	and    %edx,%r8d
 1c4:	44 89 46 1c          	mov    %r8d,0x1c(%rsi)
 1c8:	41 21 d1             	and    %edx,%r9d
 1cb:	44 89 4e 18          	mov    %r9d,0x18(%rsi)
 1cf:	eb 8e                	jmp    15f <malloc_trim+0x15f>
 1d1:	8b 56 1c             	mov    0x1c(%rsi),%edx
 1d4:	89 d1                	mov    %edx,%ecx
 1d6:	89 d0                	mov    %edx,%eax
 1d8:	44 21 c1             	and    %r8d,%ecx
 1db:	f0 41 0f b1 0a       	lock cmpxchg %ecx,(%r10)
 1e0:	39 c2                	cmp    %eax,%edx
 1e2:	75 ed                	jne    1d1 <malloc_trim+0x1d1>
 1e4:	eb e2                	jmp    1c8 <malloc_trim+0x1c8>
 1e6:	48 89 d6             	mov    %rdx,%rsi
 1e9:	48 89 c7             	mov    %rax,%rdi
 1ec:	e8 00 00 00 00       	call   1f1 <malloc_trim+0x1f1>
			1ed: R_X86_64_PLT32	munmap-0x4
 1f1:	85 c0                	test   %eax,%eax
 1f3:	0f 94 c0             	sete   %al
 1f6:	0f b6 c0             	movzbl %al,%eax
 1f9:	09 c3                	or     %eax,%ebx
 1fb:	e9 69 ff ff ff       	jmp    169 <malloc_trim+0x169>
 200:	49 83 c6 08          	add    $0x8,%r14
 204:	49 81 fe 00 00 00 00 	cmp    $0x0,%r14
			207: R_X86_64_32S	__malloc_context+0x1d0
 20b:	0f 85 58 ff ff ff    	jne    169 <malloc_trim+0x169>
 211:	8b 05 00 00 00 00    	mov    0x0(%rip),%eax        # 217 <malloc_trim+0x217>
			213: R_X86_64_PC32	__malloc_lock-0x4
 217:	85 c0                	test   %eax,%eax
 219:	78 0f                	js     22a <malloc_trim+0x22a>
 21b:	44 89 65 00          	mov    %r12d,0x0(%rbp)
 21f:	89 d8                	mov    %ebx,%eax
 221:	5b                   	pop    %rbx
 222:	5d                   	pop    %rbp
 223:	41 5c                	pop    %r12
 225:	41 5d                	pop    %r13
 227:	41 5e                	pop    %r14
 229:	c3                   	ret
 22a:	bf 00 00 00 00       	mov    $0x0,%edi
			22b: R_X86_64_32	__malloc_lock
 22f:	e8 00 00 00 00       	call   234 <malloc_trim+0x234>
			230: R_X86_64_PLT32	__unlock-0x4
 234:	eb e5                	jmp    21b <malloc_trim+0x21b>

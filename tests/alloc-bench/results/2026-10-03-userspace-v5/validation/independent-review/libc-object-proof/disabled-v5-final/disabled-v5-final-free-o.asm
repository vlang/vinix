
/Users/alex/code/vinix/third_party/useralloc-libc/build/musl/x86_64/cd7e18f1889e62892a88526d44f09cb82b303437e0b02e71db4da7b0c79450ca/objects/obj/src/malloc/mallocng/free.o:     file format elf64-x86-64


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
  73:	0f 84 85 01 00 00    	je     1fe <free_group+0x1fe>
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
  dd:	48 8b 43 10          	mov    0x10(%rbx),%rax
  e1:	a8 0f                	test   $0xf,%al
  e3:	0f 85 00 00 00 00    	jne    e9 <free_group+0xe9>
			e5: R_X86_64_PC32	.text.unlikely.free_group-0x4
  e9:	0f b6 70 fd          	movzbl -0x3(%rax),%esi
  ed:	0f b7 50 fe          	movzwl -0x2(%rax),%edx
  f1:	41 89 f0             	mov    %esi,%r8d
  f4:	83 e6 1f             	and    $0x1f,%esi
  f7:	41 83 e0 1f          	and    $0x1f,%r8d
  fb:	80 78 fc 00          	cmpb   $0x0,-0x4(%rax)
  ff:	74 18                	je     119 <free_group+0x119>
 101:	85 d2                	test   %edx,%edx
 103:	0f 85 00 00 00 00    	jne    109 <free_group+0x109>
			105: R_X86_64_PC32	.text.unlikely.free_group-0x4
 109:	48 63 50 f8          	movslq -0x8(%rax),%rdx
 10d:	81 fa ff ff 00 00    	cmp    $0xffff,%edx
 113:	0f 8e 00 00 00 00    	jle    119 <free_group+0x119>
			115: R_X86_64_PC32	.text.unlikely.free_group-0x4
 119:	89 d1                	mov    %edx,%ecx
 11b:	48 89 c7             	mov    %rax,%rdi
 11e:	c1 e1 04             	shl    $0x4,%ecx
 121:	48 63 c9             	movslq %ecx,%rcx
 124:	48 29 cf             	sub    %rcx,%rdi
 127:	48 8d 4f f0          	lea    -0x10(%rdi),%rcx
 12b:	48 8b 7f f0          	mov    -0x10(%rdi),%rdi
 12f:	48 3b 4f 10          	cmp    0x10(%rdi),%rcx
 133:	0f 85 00 00 00 00    	jne    139 <free_group+0x139>
			135: R_X86_64_PC32	.text.unlikely.free_group-0x4
 139:	0f b6 4f 20          	movzbl 0x20(%rdi),%ecx
 13d:	83 e1 1f             	and    $0x1f,%ecx
 140:	39 ce                	cmp    %ecx,%esi
 142:	0f 8f 00 00 00 00    	jg     148 <free_group+0x148>
			144: R_X86_64_PC32	.text.unlikely.free_group-0x4
 148:	8b 4f 18             	mov    0x18(%rdi),%ecx
 14b:	44 0f a3 c1          	bt     %r8d,%ecx
 14f:	0f 82 00 00 00 00    	jb     155 <free_group+0x155>
			151: R_X86_64_PC32	.text.unlikely.free_group-0x4
 155:	8b 4f 1c             	mov    0x1c(%rdi),%ecx
 158:	44 0f a3 c1          	bt     %r8d,%ecx
 15c:	0f 82 00 00 00 00    	jb     162 <free_group+0x162>
			15e: R_X86_64_PC32	.text.unlikely.free_group-0x4
 162:	48 89 f9             	mov    %rdi,%rcx
 165:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # 16c <free_group+0x16c>
			168: R_X86_64_PC32	__malloc_context-0x4
 16c:	48 81 e1 00 f0 ff ff 	and    $0xfffffffffffff000,%rcx
 173:	4c 39 09             	cmp    %r9,(%rcx)
 176:	0f 85 00 00 00 00    	jne    17c <free_group+0x17c>
			178: R_X86_64_PC32	.text.unlikely.free_group-0x4
 17c:	44 0f b7 47 20       	movzwl 0x20(%rdi),%r8d
 181:	44 89 c1             	mov    %r8d,%ecx
 184:	66 c1 e9 06          	shr    $0x6,%cx
 188:	83 e1 3f             	and    $0x3f,%ecx
 18b:	80 f9 2f             	cmp    $0x2f,%cl
 18e:	77 5e                	ja     1ee <free_group+0x1ee>
 190:	83 e1 3f             	and    $0x3f,%ecx
 193:	41 89 f0             	mov    %esi,%r8d
 196:	0f b7 8c 09 00 00 00 	movzwl 0x0(%rcx,%rcx,1),%ecx
 19d:	00 
			19a: R_X86_64_32S	__malloc_size_classes
 19e:	44 0f af c1          	imul   %ecx,%r8d
 1a2:	44 39 c2             	cmp    %r8d,%edx
 1a5:	0f 8c 00 00 00 00    	jl     1ab <free_group+0x1ab>
			1a7: R_X86_64_PC32	.text.unlikely.free_group-0x4
 1ab:	44 01 c1             	add    %r8d,%ecx
 1ae:	39 ca                	cmp    %ecx,%edx
 1b0:	7d 37                	jge    1e9 <free_group+0x1e9>
 1b2:	48 81 7f 20 ff 0f 00 	cmpq   $0xfff,0x20(%rdi)
 1b9:	00 
 1ba:	76 1c                	jbe    1d8 <free_group+0x1d8>
 1bc:	48 8b 4f 20          	mov    0x20(%rdi),%rcx
 1c0:	48 81 e1 00 f0 ff ff 	and    $0xfffffffffffff000,%rcx
 1c7:	48 c1 e9 04          	shr    $0x4,%rcx
 1cb:	48 83 e9 01          	sub    $0x1,%rcx
 1cf:	48 39 d1             	cmp    %rdx,%rcx
 1d2:	0f 82 00 00 00 00    	jb     1d8 <free_group+0x1d8>
			1d4: R_X86_64_PC32	.text.unlikely.free_group-0x4
 1d8:	48 c7 00 00 00 00 00 	movq   $0x0,(%rax)
 1df:	e8 00 00 00 00       	call   1e4 <free_group+0x1e4>
			1e0: R_X86_64_PC32	.text.nontrivial_free-0x4
 1e4:	e9 6d fe ff ff       	jmp    56 <free_group+0x56>
 1e9:	e9 00 00 00 00       	jmp    1ee <free_group+0x1ee>
			1ea: R_X86_64_PC32	.text.unlikely.free_group-0x4
 1ee:	41 f7 d0             	not    %r8d
 1f1:	66 41 f7 c0 c0 0f    	test   $0xfc0,%r8w
 1f7:	74 b9                	je     1b2 <free_group+0x1b2>
 1f9:	e9 00 00 00 00       	jmp    1fe <free_group+0x1fe>
			1fa: R_X86_64_PC32	.text.unlikely.free_group-0x4
 1fe:	66 48 0f 6e c3       	movq   %rbx,%xmm0
 203:	66 0f 6c c0          	punpcklqdq %xmm0,%xmm0
 207:	0f 11 03             	movups %xmm0,(%rbx)
 20a:	48 89 1d 00 00 00 00 	mov    %rbx,0x0(%rip)        # 211 <free_group+0x211>
			20d: R_X86_64_PC32	__malloc_context+0xc
 211:	e9 78 fe ff ff       	jmp    8e <free_group+0x8e>

Disassembly of section .text.unlikely.__libc_free:

0000000000000000 <__libc_free.cold>:
   0:	0f 0b                	ud2

Disassembly of section .text.__libc_free:

0000000000000000 <__libc_free>:
   0:	48 85 ff             	test   %rdi,%rdi
   3:	0f 84 79 02 00 00    	je     282 <__libc_free+0x282>
   9:	41 55                	push   %r13
   b:	48 89 f8             	mov    %rdi,%rax
   e:	41 54                	push   %r12
  10:	55                   	push   %rbp
  11:	53                   	push   %rbx
  12:	48 83 ec 08          	sub    $0x8,%rsp
  16:	40 f6 c7 0f          	test   $0xf,%dil
  1a:	0f 85 00 00 00 00    	jne    20 <__libc_free+0x20>
			1c: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
  20:	44 0f b6 48 fd       	movzbl -0x3(%rax),%r9d
  25:	0f b7 7f fe          	movzwl -0x2(%rdi),%edi
  29:	44 89 c9             	mov    %r9d,%ecx
  2c:	44 89 cd             	mov    %r9d,%ebp
  2f:	83 e1 1f             	and    $0x1f,%ecx
  32:	83 e5 1f             	and    $0x1f,%ebp
  35:	80 78 fc 00          	cmpb   $0x0,-0x4(%rax)
  39:	74 18                	je     53 <__libc_free+0x53>
  3b:	85 ff                	test   %edi,%edi
  3d:	0f 85 00 00 00 00    	jne    43 <__libc_free+0x43>
			3f: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
  43:	48 63 78 f8          	movslq -0x8(%rax),%rdi
  47:	81 ff ff ff 00 00    	cmp    $0xffff,%edi
  4d:	0f 8e 00 00 00 00    	jle    53 <__libc_free+0x53>
			4f: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
  53:	89 fa                	mov    %edi,%edx
  55:	48 89 c6             	mov    %rax,%rsi
  58:	c1 e2 04             	shl    $0x4,%edx
  5b:	48 63 d2             	movslq %edx,%rdx
  5e:	48 29 d6             	sub    %rdx,%rsi
  61:	48 8b 5e f0          	mov    -0x10(%rsi),%rbx
  65:	48 8d 56 f0          	lea    -0x10(%rsi),%rdx
  69:	4c 8b 53 10          	mov    0x10(%rbx),%r10
  6d:	4c 39 d2             	cmp    %r10,%rdx
  70:	0f 85 00 00 00 00    	jne    76 <__libc_free+0x76>
			72: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
  76:	44 0f b6 5b 20       	movzbl 0x20(%rbx),%r11d
  7b:	44 89 da             	mov    %r11d,%edx
  7e:	45 89 d8             	mov    %r11d,%r8d
  81:	83 e2 1f             	and    $0x1f,%edx
  84:	41 83 e0 1f          	and    $0x1f,%r8d
  88:	39 d5                	cmp    %edx,%ebp
  8a:	0f 8f 00 00 00 00    	jg     90 <__libc_free+0x90>
			8c: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
  90:	8b 53 18             	mov    0x18(%rbx),%edx
  93:	0f a3 ca             	bt     %ecx,%edx
  96:	0f 82 00 00 00 00    	jb     9c <__libc_free+0x9c>
			98: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
  9c:	8b 53 1c             	mov    0x1c(%rbx),%edx
  9f:	0f a3 ca             	bt     %ecx,%edx
  a2:	0f 82 00 00 00 00    	jb     a8 <__libc_free+0xa8>
			a4: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
  a8:	48 89 da             	mov    %rbx,%rdx
  ab:	48 8b 35 00 00 00 00 	mov    0x0(%rip),%rsi        # b2 <__libc_free+0xb2>
			ae: R_X86_64_PC32	__malloc_context-0x4
  b2:	48 81 e2 00 f0 ff ff 	and    $0xfffffffffffff000,%rdx
  b9:	48 39 32             	cmp    %rsi,(%rdx)
  bc:	0f 85 00 00 00 00    	jne    c2 <__libc_free+0xc2>
			be: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
  c2:	0f b7 53 20          	movzwl 0x20(%rbx),%edx
  c6:	89 d6                	mov    %edx,%esi
  c8:	66 c1 ee 06          	shr    $0x6,%si
  cc:	83 e6 3f             	and    $0x3f,%esi
  cf:	40 80 fe 2f          	cmp    $0x2f,%sil
  d3:	77 5f                	ja     134 <__libc_free+0x134>
  d5:	48 89 f2             	mov    %rsi,%rdx
  d8:	41 89 ec             	mov    %ebp,%r12d
  db:	83 e2 3f             	and    $0x3f,%edx
  de:	0f b7 94 12 00 00 00 	movzwl 0x0(%rdx,%rdx,1),%edx
  e5:	00 
			e2: R_X86_64_32S	__malloc_size_classes
  e6:	44 0f af e2          	imul   %edx,%r12d
  ea:	44 39 e7             	cmp    %r12d,%edi
  ed:	0f 8c 00 00 00 00    	jl     f3 <__libc_free+0xf3>
			ef: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
  f3:	44 01 e2             	add    %r12d,%edx
  f6:	39 d7                	cmp    %edx,%edi
  f8:	7d 35                	jge    12f <__libc_free+0x12f>
  fa:	48 81 7b 20 ff 0f 00 	cmpq   $0xfff,0x20(%rbx)
 101:	00 
 102:	76 3e                	jbe    142 <__libc_free+0x142>
 104:	48 8b 53 20          	mov    0x20(%rbx),%rdx
 108:	48 81 e2 00 f0 ff ff 	and    $0xfffffffffffff000,%rdx
 10f:	49 89 d4             	mov    %rdx,%r12
 112:	49 c1 ec 04          	shr    $0x4,%r12
 116:	49 83 ec 01          	sub    $0x1,%r12
 11a:	49 39 fc             	cmp    %rdi,%r12
 11d:	0f 82 00 00 00 00    	jb     123 <__libc_free+0x123>
			11f: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 123:	41 83 e3 1f          	and    $0x1f,%r11d
 127:	75 19                	jne    142 <__libc_free+0x142>
 129:	48 83 ea 10          	sub    $0x10,%rdx
 12d:	eb 24                	jmp    153 <__libc_free+0x153>
 12f:	e9 00 00 00 00       	jmp    134 <__libc_free+0x134>
			130: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 134:	f7 d2                	not    %edx
 136:	66 f7 c2 c0 0f       	test   $0xfc0,%dx
 13b:	74 bd                	je     fa <__libc_free+0xfa>
 13d:	e9 00 00 00 00       	jmp    142 <__libc_free+0x142>
			13e: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 142:	83 e6 3f             	and    $0x3f,%esi
 145:	0f b7 94 36 00 00 00 	movzwl 0x0(%rsi,%rsi,1),%edx
 14c:	00 
			149: R_X86_64_32S	__malloc_size_classes
 14d:	c1 e2 04             	shl    $0x4,%edx
 150:	48 63 d2             	movslq %edx,%rdx
 153:	0f b6 f1             	movzbl %cl,%esi
 156:	48 0f af f2          	imul   %rdx,%rsi
 15a:	48 8d 54 32 fc       	lea    -0x4(%rdx,%rsi,1),%rdx
 15f:	49 8d 74 12 10       	lea    0x10(%r10,%rdx,1),%rsi
 164:	44 89 ca             	mov    %r9d,%edx
 167:	c0 ea 05             	shr    $0x5,%dl
 16a:	41 80 f9 9f          	cmp    $0x9f,%r9b
 16e:	0f 87 86 00 00 00    	ja     1fa <__libc_free+0x1fa>
 174:	0f b6 d2             	movzbl %dl,%edx
 177:	48 89 f7             	mov    %rsi,%rdi
 17a:	48 29 c7             	sub    %rax,%rdi
 17d:	48 39 d7             	cmp    %rdx,%rdi
 180:	0f 82 00 00 00 00    	jb     186 <__libc_free+0x186>
			182: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 186:	48 89 f7             	mov    %rsi,%rdi
 189:	48 29 d7             	sub    %rdx,%rdi
 18c:	80 3f 00             	cmpb   $0x0,(%rdi)
 18f:	0f 85 00 00 00 00    	jne    195 <__libc_free+0x195>
			191: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 195:	80 3e 00             	cmpb   $0x0,(%rsi)
 198:	0f 85 00 00 00 00    	jne    19e <__libc_free+0x19e>
			19a: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 19e:	be 01 00 00 00       	mov    $0x1,%esi
 1a3:	31 d2                	xor    %edx,%edx
 1a5:	bf 02 00 00 00       	mov    $0x2,%edi
 1aa:	c6 40 fd ff          	movb   $0xff,-0x3(%rax)
 1ae:	d3 e6                	shl    %cl,%esi
 1b0:	66 89 50 fe          	mov    %dx,-0x2(%rax)
 1b4:	44 89 c1             	mov    %r8d,%ecx
 1b7:	d3 e7                	shl    %cl,%edi
 1b9:	83 ef 01             	sub    $0x1,%edi
 1bc:	8b 53 1c             	mov    0x1c(%rbx),%edx
 1bf:	8b 43 18             	mov    0x18(%rbx),%eax
 1c2:	09 d0                	or     %edx,%eax
 1c4:	85 c6                	test   %eax,%esi
 1c6:	0f 85 00 00 00 00    	jne    1cc <__libc_free+0x1cc>
			1c8: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 1cc:	85 d2                	test   %edx,%edx
 1ce:	74 54                	je     224 <__libc_free+0x224>
 1d0:	01 f0                	add    %esi,%eax
 1d2:	39 f8                	cmp    %edi,%eax
 1d4:	74 4e                	je     224 <__libc_free+0x224>
 1d6:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 1dd <__libc_free+0x1dd>
			1d9: R_X86_64_PC32	__libc-0x1
 1dd:	8d 0c 16             	lea    (%rsi,%rdx,1),%ecx
 1e0:	84 c0                	test   %al,%al
 1e2:	74 3b                	je     21f <__libc_free+0x21f>
 1e4:	89 d0                	mov    %edx,%eax
 1e6:	f0 0f b1 4b 1c       	lock cmpxchg %ecx,0x1c(%rbx)
 1eb:	39 c2                	cmp    %eax,%edx
 1ed:	75 cd                	jne    1bc <__libc_free+0x1bc>
 1ef:	48 83 c4 08          	add    $0x8,%rsp
 1f3:	5b                   	pop    %rbx
 1f4:	5d                   	pop    %rbp
 1f5:	41 5c                	pop    %r12
 1f7:	41 5d                	pop    %r13
 1f9:	c3                   	ret
 1fa:	80 fa 05             	cmp    $0x5,%dl
 1fd:	0f 85 00 00 00 00    	jne    203 <__libc_free+0x203>
			1ff: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 203:	8b 56 fc             	mov    -0x4(%rsi),%edx
 206:	48 83 fa 04          	cmp    $0x4,%rdx
 20a:	0f 86 00 00 00 00    	jbe    210 <__libc_free+0x210>
			20c: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 210:	80 7e fb 00          	cmpb   $0x0,-0x5(%rsi)
 214:	0f 84 5d ff ff ff    	je     177 <__libc_free+0x177>
 21a:	e9 00 00 00 00       	jmp    21f <__libc_free+0x21f>
			21b: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 21f:	89 4b 1c             	mov    %ecx,0x1c(%rbx)
 222:	eb cb                	jmp    1ef <__libc_free+0x1ef>
 224:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 22b <__libc_free+0x22b>
			227: R_X86_64_PC32	__libc-0x1
 22b:	84 c0                	test   %al,%al
 22d:	75 3b                	jne    26a <__libc_free+0x26a>
 22f:	89 ee                	mov    %ebp,%esi
 231:	48 89 df             	mov    %rbx,%rdi
 234:	e8 00 00 00 00       	call   239 <__libc_free+0x239>
			235: R_X86_64_PC32	.text.nontrivial_free-0x4
 239:	48 89 c5             	mov    %rax,%rbp
 23c:	8b 05 00 00 00 00    	mov    0x0(%rip),%eax        # 242 <__libc_free+0x242>
			23e: R_X86_64_PC32	__malloc_lock-0x4
 242:	48 89 d3             	mov    %rdx,%rbx
 245:	85 c0                	test   %eax,%eax
 247:	78 2d                	js     276 <__libc_free+0x276>
 249:	48 85 db             	test   %rbx,%rbx
 24c:	74 a1                	je     1ef <__libc_free+0x1ef>
 24e:	e8 00 00 00 00       	call   253 <__libc_free+0x253>
			24f: R_X86_64_PLT32	___errno_location-0x4
 253:	48 89 de             	mov    %rbx,%rsi
 256:	48 89 ef             	mov    %rbp,%rdi
 259:	44 8b 28             	mov    (%rax),%r13d
 25c:	49 89 c4             	mov    %rax,%r12
 25f:	e8 00 00 00 00       	call   264 <__libc_free+0x264>
			260: R_X86_64_PLT32	munmap-0x4
 264:	45 89 2c 24          	mov    %r13d,(%r12)
 268:	eb 85                	jmp    1ef <__libc_free+0x1ef>
 26a:	bf 00 00 00 00       	mov    $0x0,%edi
			26b: R_X86_64_32	__malloc_lock
 26f:	e8 00 00 00 00       	call   274 <__libc_free+0x274>
			270: R_X86_64_PLT32	__lock-0x4
 274:	eb b9                	jmp    22f <__libc_free+0x22f>
 276:	bf 00 00 00 00       	mov    $0x0,%edi
			277: R_X86_64_32	__malloc_lock
 27b:	e8 00 00 00 00       	call   280 <__libc_free+0x280>
			27c: R_X86_64_PLT32	__unlock-0x4
 280:	eb c7                	jmp    249 <__libc_free+0x249>
 282:	c3                   	ret

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

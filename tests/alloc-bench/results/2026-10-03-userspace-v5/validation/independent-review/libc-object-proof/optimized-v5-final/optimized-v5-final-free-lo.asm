
/Users/alex/code/vinix/third_party/useralloc-libc/build/musl/x86_64/c97687ce9e5ca67f3acb8947bf28d3def2b044abf977e9e91ab8e8c767083b1c/objects/obj/src/malloc/mallocng/free.lo:     file format elf64-x86-64


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
   f:	83 fa 3f             	cmp    $0x3f,%edx
  12:	0f 84 ae 00 00 00    	je     c6 <free_group+0xc6>
  18:	83 fa 2f             	cmp    $0x2f,%edx
  1b:	7f 1c                	jg     39 <free_group+0x39>
  1d:	0f b6 47 20          	movzbl 0x20(%rdi),%eax
  21:	48 8d 35 00 00 00 00 	lea    0x0(%rip),%rsi        # 28 <free_group+0x28>
			24: R_X86_64_PC32	__malloc_context-0x4
  28:	48 63 ca             	movslq %edx,%rcx
  2b:	83 e0 1f             	and    $0x1f,%eax
  2e:	48 f7 d0             	not    %rax
  31:	48 01 84 ce f8 01 00 	add    %rax,0x1f8(%rsi,%rcx,8)
  38:	00 
  39:	48 81 7b 20 ff 0f 00 	cmpq   $0xfff,0x20(%rbx)
  40:	00 
  41:	0f 86 73 01 00 00    	jbe    1ba <free_group+0x1ba>
  47:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 4e <free_group+0x4e>
			4a: R_X86_64_PC32	__malloc_context+0x3b4
  4e:	8d 48 01             	lea    0x1(%rax),%ecx
  51:	3c ff                	cmp    $0xff,%al
  53:	0f 84 36 01 00 00    	je     18f <free_group+0x18f>
  59:	83 ea 07             	sub    $0x7,%edx
  5c:	88 0d 00 00 00 00    	mov    %cl,0x0(%rip)        # 62 <free_group+0x62>
			5e: R_X86_64_PC32	__malloc_context+0x3b4
  62:	83 fa 1f             	cmp    $0x1f,%edx
  65:	77 11                	ja     78 <free_group+0x78>
  67:	48 63 d2             	movslq %edx,%rdx
  6a:	48 8d 05 00 00 00 00 	lea    0x0(%rip),%rax        # 71 <free_group+0x71>
			6d: R_X86_64_PC32	__malloc_context-0x4
  71:	88 8c 10 78 03 00 00 	mov    %cl,0x378(%rax,%rdx,1)
  78:	48 8b 43 20          	mov    0x20(%rbx),%rax
  7c:	48 8b 7b 10          	mov    0x10(%rbx),%rdi
  80:	48 25 00 f0 ff ff    	and    $0xfffffffffffff000,%rax
  86:	66 0f ef c0          	pxor   %xmm0,%xmm0
  8a:	48 c7 43 20 00 00 00 	movq   $0x0,0x20(%rbx)
  91:	00 
  92:	0f 11 03             	movups %xmm0,(%rbx)
  95:	0f 11 43 10          	movups %xmm0,0x10(%rbx)
  99:	48 8b 15 00 00 00 00 	mov    0x0(%rip),%rdx        # a0 <free_group+0xa0>
			9c: R_X86_64_PC32	__malloc_context+0xc
  a0:	48 85 d2             	test   %rdx,%rdx
  a3:	0f 84 3c 02 00 00    	je     2e5 <free_group+0x2e5>
  a9:	48 89 53 08          	mov    %rdx,0x8(%rbx)
  ad:	48 8b 12             	mov    (%rdx),%rdx
  b0:	48 89 13             	mov    %rdx,(%rbx)
  b3:	48 89 5a 08          	mov    %rbx,0x8(%rdx)
  b7:	48 8b 53 08          	mov    0x8(%rbx),%rdx
  bb:	48 89 1a             	mov    %rbx,(%rdx)
  be:	48 89 c2             	mov    %rax,%rdx
  c1:	5b                   	pop    %rbx
  c2:	48 89 f8             	mov    %rdi,%rax
  c5:	c3                   	ret
  c6:	48 8b 77 20          	mov    0x20(%rdi),%rsi
  ca:	48 c1 ee 0c          	shr    $0xc,%rsi
  ce:	48 8d 46 e0          	lea    -0x20(%rsi),%rax
  d2:	48 3d e0 01 00 00    	cmp    $0x1e0,%rax
  d8:	0f 87 5b ff ff ff    	ja     39 <free_group+0x39>
  de:	b8 20 00 00 00       	mov    $0x20,%eax
  e3:	31 c9                	xor    %ecx,%ecx
  e5:	eb 0f                	jmp    f6 <free_group+0xf6>
  e7:	66 0f 1f 84 00 00 00 	nopw   0x0(%rax,%rax,1)
  ee:	00 00 
  f0:	83 c1 01             	add    $0x1,%ecx
  f3:	48 01 c0             	add    %rax,%rax
  f6:	48 39 f0             	cmp    %rsi,%rax
  f9:	72 f5                	jb     f0 <free_group+0xf0>
  fb:	4c 8d 05 00 00 00 00 	lea    0x0(%rip),%r8        # 102 <free_group+0x102>
			fe: R_X86_64_PC32	__malloc_context-0x4
 102:	48 63 c9             	movslq %ecx,%rcx
 105:	49 8b bc c8 d0 01 00 	mov    0x1d0(%r8,%rcx,8),%rdi
 10c:	00 
 10d:	48 85 ff             	test   %rdi,%rdi
 110:	74 67                	je     179 <free_group+0x179>
 112:	48 8b 47 20          	mov    0x20(%rdi),%rax
 116:	48 c1 e8 0c          	shr    $0xc,%rax
 11a:	48 39 f0             	cmp    %rsi,%rax
 11d:	0f 83 16 ff ff ff    	jae    39 <free_group+0x39>
 123:	66 0f ef c0          	pxor   %xmm0,%xmm0
 127:	48 8b 77 10          	mov    0x10(%rdi),%rsi
 12b:	48 c7 47 20 00 00 00 	movq   $0x0,0x20(%rdi)
 132:	00 
 133:	0f 11 07             	movups %xmm0,(%rdi)
 136:	0f 11 47 10          	movups %xmm0,0x10(%rdi)
 13a:	48 8b 15 00 00 00 00 	mov    0x0(%rip),%rdx        # 141 <free_group+0x141>
			13d: R_X86_64_PC32	__malloc_context+0xc
 141:	48 85 d2             	test   %rdx,%rdx
 144:	74 1e                	je     164 <free_group+0x164>
 146:	48 89 57 08          	mov    %rdx,0x8(%rdi)
 14a:	48 8b 12             	mov    (%rdx),%rdx
 14d:	48 89 17             	mov    %rdx,(%rdi)
 150:	48 89 7a 08          	mov    %rdi,0x8(%rdx)
 154:	48 8b 57 08          	mov    0x8(%rdi),%rdx
 158:	48 89 3a             	mov    %rdi,(%rdx)
 15b:	48 c1 e0 0c          	shl    $0xc,%rax
 15f:	48 89 f7             	mov    %rsi,%rdi
 162:	eb 17                	jmp    17b <free_group+0x17b>
 164:	66 48 0f 6e c7       	movq   %rdi,%xmm0
 169:	66 0f 6c c0          	punpcklqdq %xmm0,%xmm0
 16d:	0f 11 07             	movups %xmm0,(%rdi)
 170:	48 89 3d 00 00 00 00 	mov    %rdi,0x0(%rip)        # 177 <free_group+0x177>
			173: R_X86_64_PC32	__malloc_context+0xc
 177:	eb e2                	jmp    15b <free_group+0x15b>
 179:	31 c0                	xor    %eax,%eax
 17b:	c7 43 1c 01 00 00 00 	movl   $0x1,0x1c(%rbx)
 182:	49 89 9c c8 d0 01 00 	mov    %rbx,0x1d0(%r8,%rcx,8)
 189:	00 
 18a:	e9 2f ff ff ff       	jmp    be <free_group+0xbe>
 18f:	48 8d 05 00 00 00 00 	lea    0x0(%rip),%rax        # 196 <free_group+0x196>
			192: R_X86_64_PC32	__malloc_context+0x374
 196:	48 8d 48 20          	lea    0x20(%rax),%rcx
 19a:	eb 0f                	jmp    1ab <free_group+0x1ab>
 19c:	0f 1f 40 00          	nopl   0x0(%rax)
 1a0:	c6 00 00             	movb   $0x0,(%rax)
 1a3:	48 83 c0 02          	add    $0x2,%rax
 1a7:	c6 40 ff 00          	movb   $0x0,-0x1(%rax)
 1ab:	48 39 c8             	cmp    %rcx,%rax
 1ae:	75 f0                	jne    1a0 <free_group+0x1a0>
 1b0:	b9 01 00 00 00       	mov    $0x1,%ecx
 1b5:	e9 9f fe ff ff       	jmp    59 <free_group+0x59>
 1ba:	48 8b 43 10          	mov    0x10(%rbx),%rax
 1be:	a8 0f                	test   $0xf,%al
 1c0:	0f 85 00 00 00 00    	jne    1c6 <free_group+0x1c6>
			1c2: R_X86_64_PC32	.text.unlikely.free_group-0x4
 1c6:	0f b6 70 fd          	movzbl -0x3(%rax),%esi
 1ca:	0f b7 50 fe          	movzwl -0x2(%rax),%edx
 1ce:	41 89 f0             	mov    %esi,%r8d
 1d1:	83 e6 1f             	and    $0x1f,%esi
 1d4:	41 83 e0 1f          	and    $0x1f,%r8d
 1d8:	80 78 fc 00          	cmpb   $0x0,-0x4(%rax)
 1dc:	74 18                	je     1f6 <free_group+0x1f6>
 1de:	85 d2                	test   %edx,%edx
 1e0:	0f 85 00 00 00 00    	jne    1e6 <free_group+0x1e6>
			1e2: R_X86_64_PC32	.text.unlikely.free_group-0x4
 1e6:	48 63 50 f8          	movslq -0x8(%rax),%rdx
 1ea:	81 fa ff ff 00 00    	cmp    $0xffff,%edx
 1f0:	0f 8e 00 00 00 00    	jle    1f6 <free_group+0x1f6>
			1f2: R_X86_64_PC32	.text.unlikely.free_group-0x4
 1f6:	89 d1                	mov    %edx,%ecx
 1f8:	48 89 c7             	mov    %rax,%rdi
 1fb:	c1 e1 04             	shl    $0x4,%ecx
 1fe:	48 63 c9             	movslq %ecx,%rcx
 201:	48 29 cf             	sub    %rcx,%rdi
 204:	48 8d 4f f0          	lea    -0x10(%rdi),%rcx
 208:	48 8b 7f f0          	mov    -0x10(%rdi),%rdi
 20c:	48 3b 4f 10          	cmp    0x10(%rdi),%rcx
 210:	0f 85 00 00 00 00    	jne    216 <free_group+0x216>
			212: R_X86_64_PC32	.text.unlikely.free_group-0x4
 216:	0f b6 4f 20          	movzbl 0x20(%rdi),%ecx
 21a:	83 e1 1f             	and    $0x1f,%ecx
 21d:	39 ce                	cmp    %ecx,%esi
 21f:	0f 8f 00 00 00 00    	jg     225 <free_group+0x225>
			221: R_X86_64_PC32	.text.unlikely.free_group-0x4
 225:	8b 4f 18             	mov    0x18(%rdi),%ecx
 228:	44 0f a3 c1          	bt     %r8d,%ecx
 22c:	0f 82 00 00 00 00    	jb     232 <free_group+0x232>
			22e: R_X86_64_PC32	.text.unlikely.free_group-0x4
 232:	8b 4f 1c             	mov    0x1c(%rdi),%ecx
 235:	44 0f a3 c1          	bt     %r8d,%ecx
 239:	0f 82 00 00 00 00    	jb     23f <free_group+0x23f>
			23b: R_X86_64_PC32	.text.unlikely.free_group-0x4
 23f:	48 89 f9             	mov    %rdi,%rcx
 242:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # 249 <free_group+0x249>
			245: R_X86_64_PC32	__malloc_context-0x4
 249:	48 81 e1 00 f0 ff ff 	and    $0xfffffffffffff000,%rcx
 250:	4c 39 09             	cmp    %r9,(%rcx)
 253:	0f 85 00 00 00 00    	jne    259 <free_group+0x259>
			255: R_X86_64_PC32	.text.unlikely.free_group-0x4
 259:	44 0f b7 47 20       	movzwl 0x20(%rdi),%r8d
 25e:	44 89 c1             	mov    %r8d,%ecx
 261:	66 c1 e9 06          	shr    $0x6,%cx
 265:	83 e1 3f             	and    $0x3f,%ecx
 268:	80 f9 2f             	cmp    $0x2f,%cl
 26b:	77 68                	ja     2d5 <free_group+0x2d5>
 26d:	4c 8d 05 00 00 00 00 	lea    0x0(%rip),%r8        # 274 <free_group+0x274>
			270: R_X86_64_PC32	__malloc_size_classes-0x4
 274:	83 e1 3f             	and    $0x3f,%ecx
 277:	41 0f b7 0c 48       	movzwl (%r8,%rcx,2),%ecx
 27c:	41 89 f0             	mov    %esi,%r8d
 27f:	44 0f af c1          	imul   %ecx,%r8d
 283:	44 39 c2             	cmp    %r8d,%edx
 286:	0f 8c 00 00 00 00    	jl     28c <free_group+0x28c>
			288: R_X86_64_PC32	.text.unlikely.free_group-0x4
 28c:	44 01 c1             	add    %r8d,%ecx
 28f:	39 ca                	cmp    %ecx,%edx
 291:	7d 3d                	jge    2d0 <free_group+0x2d0>
 293:	48 81 7f 20 ff 0f 00 	cmpq   $0xfff,0x20(%rdi)
 29a:	00 
 29b:	76 1c                	jbe    2b9 <free_group+0x2b9>
 29d:	48 8b 4f 20          	mov    0x20(%rdi),%rcx
 2a1:	48 81 e1 00 f0 ff ff 	and    $0xfffffffffffff000,%rcx
 2a8:	48 c1 e9 04          	shr    $0x4,%rcx
 2ac:	48 83 e9 01          	sub    $0x1,%rcx
 2b0:	48 39 d1             	cmp    %rdx,%rcx
 2b3:	0f 82 00 00 00 00    	jb     2b9 <free_group+0x2b9>
			2b5: R_X86_64_PC32	.text.unlikely.free_group-0x4
 2b9:	48 c7 00 00 00 00 00 	movq   $0x0,(%rax)
 2c0:	e8 00 00 00 00       	call   2c5 <free_group+0x2c5>
			2c1: R_X86_64_PC32	.text.nontrivial_free-0x4
 2c5:	48 89 c7             	mov    %rax,%rdi
 2c8:	48 89 d0             	mov    %rdx,%rax
 2cb:	e9 b6 fd ff ff       	jmp    86 <free_group+0x86>
 2d0:	e9 00 00 00 00       	jmp    2d5 <free_group+0x2d5>
			2d1: R_X86_64_PC32	.text.unlikely.free_group-0x4
 2d5:	41 f7 d0             	not    %r8d
 2d8:	66 41 f7 c0 c0 0f    	test   $0xfc0,%r8w
 2de:	74 b3                	je     293 <free_group+0x293>
 2e0:	e9 00 00 00 00       	jmp    2e5 <free_group+0x2e5>
			2e1: R_X86_64_PC32	.text.unlikely.free_group-0x4
 2e5:	66 48 0f 6e c3       	movq   %rbx,%xmm0
 2ea:	66 0f 6c c0          	punpcklqdq %xmm0,%xmm0
 2ee:	0f 11 03             	movups %xmm0,(%rbx)
 2f1:	48 89 1d 00 00 00 00 	mov    %rbx,0x0(%rip)        # 2f8 <free_group+0x2f8>
			2f4: R_X86_64_PC32	__malloc_context+0xc
 2f8:	e9 c1 fd ff ff       	jmp    be <free_group+0xbe>

Disassembly of section .text.unlikely.nontrivial_free:

0000000000000000 <nontrivial_free.cold>:
   0:	0f 0b                	ud2

Disassembly of section .text.nontrivial_free:

0000000000000000 <nontrivial_free>:
   0:	44 0f b6 4f 20       	movzbl 0x20(%rdi),%r9d
   5:	89 f1                	mov    %esi,%ecx
   7:	41 b8 01 00 00 00    	mov    $0x1,%r8d
   d:	8b 77 1c             	mov    0x1c(%rdi),%esi
  10:	8b 57 18             	mov    0x18(%rdi),%edx
  13:	41 d3 e0             	shl    %cl,%r8d
  16:	0f b7 47 20          	movzwl 0x20(%rdi),%eax
  1a:	53                   	push   %rbx
  1b:	44 89 c9             	mov    %r9d,%ecx
  1e:	45 89 cb             	mov    %r9d,%r11d
  21:	09 d6                	or     %edx,%esi
  23:	83 e1 1f             	and    $0x1f,%ecx
  26:	ba 02 00 00 00       	mov    $0x2,%edx
  2b:	66 c1 e8 06          	shr    $0x6,%ax
  2f:	d3 e2                	shl    %cl,%edx
  31:	45 8d 14 30          	lea    (%r8,%rsi,1),%r10d
  35:	83 e0 3f             	and    $0x3f,%eax
  38:	41 83 e3 1f          	and    $0x1f,%r11d
  3c:	83 ea 01             	sub    $0x1,%edx
  3f:	41 39 d2             	cmp    %edx,%r10d
  42:	74 75                	je     b9 <nontrivial_free+0xb9>
  44:	85 f6                	test   %esi,%esi
  46:	75 53                	jne    9b <nontrivial_free+0x9b>
  48:	83 f8 2f             	cmp    $0x2f,%eax
  4b:	0f 8f 00 00 00 00    	jg     51 <nontrivial_free+0x51>
			4d: R_X86_64_PC32	.text.unlikely.nontrivial_free-0x4
  51:	48 63 d0             	movslq %eax,%rdx
  54:	48 8d 0d 00 00 00 00 	lea    0x0(%rip),%rcx        # 5b <nontrivial_free+0x5b>
			57: R_X86_64_PC32	__malloc_context-0x4
  5b:	48 83 c2 0a          	add    $0xa,%rdx
  5f:	48 8b 04 d1          	mov    (%rcx,%rdx,8),%rax
  63:	48 39 f8             	cmp    %rdi,%rax
  66:	74 33                	je     9b <nontrivial_free+0x9b>
  68:	48 83 7f 08 00       	cmpq   $0x0,0x8(%rdi)
  6d:	0f 85 00 00 00 00    	jne    73 <nontrivial_free+0x73>
			6f: R_X86_64_PC32	.text.unlikely.nontrivial_free-0x4
  73:	48 83 3f 00          	cmpq   $0x0,(%rdi)
  77:	0f 85 00 00 00 00    	jne    7d <nontrivial_free+0x7d>
			79: R_X86_64_PC32	.text.unlikely.nontrivial_free-0x4
  7d:	48 85 c0             	test   %rax,%rax
  80:	0f 84 5f 02 00 00    	je     2e5 <nontrivial_free+0x2e5>
  86:	48 89 47 08          	mov    %rax,0x8(%rdi)
  8a:	48 8b 00             	mov    (%rax),%rax
  8d:	48 89 07             	mov    %rax,(%rdi)
  90:	48 89 78 08          	mov    %rdi,0x8(%rax)
  94:	48 8b 47 08          	mov    0x8(%rdi),%rax
  98:	48 89 38             	mov    %rdi,(%rax)
  9b:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # a2 <nontrivial_free+0xa2>
			9e: R_X86_64_PC32	__libc-0x1
  a2:	84 c0                	test   %al,%al
  a4:	0f 85 50 02 00 00    	jne    2fa <nontrivial_free+0x2fa>
  aa:	8b 47 1c             	mov    0x1c(%rdi),%eax
  ad:	44 09 c0             	or     %r8d,%eax
  b0:	89 47 1c             	mov    %eax,0x1c(%rdi)
  b3:	31 c0                	xor    %eax,%eax
  b5:	31 d2                	xor    %edx,%edx
  b7:	5b                   	pop    %rbx
  b8:	c3                   	ret
  b9:	41 83 e1 20          	and    $0x20,%r9d
  bd:	74 85                	je     44 <nontrivial_free+0x44>
  bf:	4c 8b 4f 08          	mov    0x8(%rdi),%r9
  c3:	83 f8 2f             	cmp    $0x2f,%eax
  c6:	0f 8f 86 01 00 00    	jg     252 <nontrivial_free+0x252>
  cc:	48 63 d0             	movslq %eax,%rdx
  cf:	4c 8d 15 00 00 00 00 	lea    0x0(%rip),%r10        # d6 <nontrivial_free+0xd6>
			d2: R_X86_64_PC32	__malloc_size_classes-0x4
  d6:	45 0f b7 14 52       	movzwl (%r10,%rdx,2),%r10d
  db:	84 c9                	test   %cl,%cl
  dd:	75 76                	jne    155 <nontrivial_free+0x155>
  df:	48 81 7f 20 ff 0f 00 	cmpq   $0xfff,0x20(%rdi)
  e6:	00 
  e7:	76 6c                	jbe    155 <nontrivial_free+0x155>
  e9:	48 8b 4f 20          	mov    0x20(%rdi),%rcx
  ed:	44 89 d3             	mov    %r10d,%ebx
  f0:	c1 e3 04             	shl    $0x4,%ebx
  f3:	48 81 e1 00 f0 ff ff 	and    $0xfffffffffffff000,%rcx
  fa:	48 63 db             	movslq %ebx,%rbx
  fd:	48 83 e9 10          	sub    $0x10,%rcx
 101:	48 39 d9             	cmp    %rbx,%rcx
 104:	73 4f                	jae    155 <nontrivial_free+0x155>
 106:	48 8d 0d 00 00 00 00 	lea    0x0(%rip),%rcx        # 10d <nontrivial_free+0x10d>
			109: R_X86_64_PC32	__malloc_context-0x4
 10d:	4d 85 c9             	test   %r9,%r9
 110:	74 3d                	je     14f <nontrivial_free+0x14f>
 112:	48 8d 72 0a          	lea    0xa(%rdx),%rsi
 116:	48 8b 04 f1          	mov    (%rcx,%rsi,8),%rax
 11a:	4c 39 cf             	cmp    %r9,%rdi
 11d:	0f 84 4a 01 00 00    	je     26d <nontrivial_free+0x26d>
 123:	48 8b 37             	mov    (%rdi),%rsi
 126:	4c 89 4e 08          	mov    %r9,0x8(%rsi)
 12a:	48 8b 37             	mov    (%rdi),%rsi
 12d:	49 89 31             	mov    %rsi,(%r9)
 130:	48 8d 72 0a          	lea    0xa(%rdx),%rsi
 134:	48 3b 7c d1 50       	cmp    0x50(%rcx,%rdx,8),%rdi
 139:	0f 84 21 01 00 00    	je     260 <nontrivial_free+0x260>
 13f:	66 0f ef c0          	pxor   %xmm0,%xmm0
 143:	0f 11 07             	movups %xmm0,(%rdi)
 146:	48 39 c7             	cmp    %rax,%rdi
 149:	0f 84 2b 01 00 00    	je     27a <nontrivial_free+0x27a>
 14f:	5b                   	pop    %rbx
 150:	e9 00 00 00 00       	jmp    155 <nontrivial_free+0x155>
			151: R_X86_64_PC32	.text.free_group-0x4
 155:	4c 39 cf             	cmp    %r9,%rdi
 158:	74 39                	je     193 <nontrivial_free+0x193>
 15a:	48 8d 0d 00 00 00 00 	lea    0x0(%rip),%rcx        # 161 <nontrivial_free+0x161>
			15d: R_X86_64_PC32	__malloc_context-0x4
 161:	4d 85 c9             	test   %r9,%r9
 164:	74 07                	je     16d <nontrivial_free+0x16d>
 166:	48 8b 44 d1 50       	mov    0x50(%rcx,%rdx,8),%rax
 16b:	eb b6                	jmp    123 <nontrivial_free+0x123>
 16d:	48 83 7c d1 50 00    	cmpq   $0x0,0x50(%rcx,%rdx,8)
 173:	75 da                	jne    14f <nontrivial_free+0x14f>
 175:	48 81 7f 20 ff 0f 00 	cmpq   $0xfff,0x20(%rdi)
 17c:	00 
 17d:	76 74                	jbe    1f3 <nontrivial_free+0x1f3>
 17f:	48 8b 47 20          	mov    0x20(%rdi),%rax
 183:	48 25 00 f0 ff ff    	and    $0xfffffffffffff000,%rax
 189:	48 3d 00 00 02 00    	cmp    $0x20000,%rax
 18f:	77 be                	ja     14f <nontrivial_free+0x14f>
 191:	eb 72                	jmp    205 <nontrivial_free+0x205>
 193:	48 81 7f 20 ff 0f 00 	cmpq   $0xfff,0x20(%rdi)
 19a:	00 
 19b:	76 56                	jbe    1f3 <nontrivial_free+0x1f3>
 19d:	48 8b 4f 20          	mov    0x20(%rdi),%rcx
 1a1:	48 81 e1 00 f0 ff ff 	and    $0xfffffffffffff000,%rcx
 1a8:	48 81 f9 00 00 02 00 	cmp    $0x20000,%rcx
 1af:	76 54                	jbe    205 <nontrivial_free+0x205>
 1b1:	83 e8 07             	sub    $0x7,%eax
 1b4:	83 f8 1f             	cmp    $0x1f,%eax
 1b7:	77 6b                	ja     224 <nontrivial_free+0x224>
 1b9:	48 8d 0d 00 00 00 00 	lea    0x0(%rip),%rcx        # 1c0 <nontrivial_free+0x1c0>
			1bc: R_X86_64_PC32	__malloc_context-0x4
 1c0:	48 98                	cltq
 1c2:	80 bc 01 98 03 00 00 	cmpb   $0x63,0x398(%rcx,%rax,1)
 1c9:	63 
 1ca:	76 46                	jbe    212 <nontrivial_free+0x212>
 1cc:	41 8d 43 01          	lea    0x1(%r11),%eax
 1d0:	4c 63 c8             	movslq %eax,%r9
 1d3:	4f 8d 0c c9          	lea    (%r9,%r9,8),%r9
 1d7:	4c 39 8c d1 f8 01 00 	cmp    %r9,0x1f8(%rcx,%rdx,8)
 1de:	00 
 1df:	72 05                	jb     1e6 <nontrivial_free+0x1e6>
 1e1:	83 f8 13             	cmp    $0x13,%eax
 1e4:	7e 2c                	jle    212 <nontrivial_free+0x212>
 1e6:	85 f6                	test   %esi,%esi
 1e8:	0f 84 6d fe ff ff    	je     5b <nontrivial_free+0x5b>
 1ee:	e9 a8 fe ff ff       	jmp    9b <nontrivial_free+0x9b>
 1f3:	41 8d 43 01          	lea    0x1(%r11),%eax
 1f7:	41 0f af c2          	imul   %r10d,%eax
 1fb:	83 c0 01             	add    $0x1,%eax
 1fe:	3d 00 20 00 00       	cmp    $0x2000,%eax
 203:	7f 38                	jg     23d <nontrivial_free+0x23d>
 205:	85 f6                	test   %esi,%esi
 207:	0f 85 8e fe ff ff    	jne    9b <nontrivial_free+0x9b>
 20d:	e9 42 fe ff ff       	jmp    54 <nontrivial_free+0x54>
 212:	4c 8b 4f 08          	mov    0x8(%rdi),%r9
 216:	4d 85 c9             	test   %r9,%r9
 219:	0f 85 f3 fe ff ff    	jne    112 <nontrivial_free+0x112>
 21f:	e9 2b ff ff ff       	jmp    14f <nontrivial_free+0x14f>
 224:	4c 8b 4f 08          	mov    0x8(%rdi),%r9
 228:	48 8d 0d 00 00 00 00 	lea    0x0(%rip),%rcx        # 22f <nontrivial_free+0x22f>
			22b: R_X86_64_PC32	__malloc_context-0x4
 22f:	4d 85 c9             	test   %r9,%r9
 232:	0f 85 da fe ff ff    	jne    112 <nontrivial_free+0x112>
 238:	e9 12 ff ff ff       	jmp    14f <nontrivial_free+0x14f>
 23d:	4d 85 c9             	test   %r9,%r9
 240:	0f 84 09 ff ff ff    	je     14f <nontrivial_free+0x14f>
 246:	48 8d 0d 00 00 00 00 	lea    0x0(%rip),%rcx        # 24d <nontrivial_free+0x24d>
			249: R_X86_64_PC32	__malloc_context-0x4
 24d:	e9 c0 fe ff ff       	jmp    112 <nontrivial_free+0x112>
 252:	4d 85 c9             	test   %r9,%r9
 255:	0f 85 00 00 00 00    	jne    25b <nontrivial_free+0x25b>
			257: R_X86_64_PC32	.text.unlikely.nontrivial_free-0x4
 25b:	e9 ef fe ff ff       	jmp    14f <nontrivial_free+0x14f>
 260:	4c 8b 47 08          	mov    0x8(%rdi),%r8
 264:	4c 89 04 f1          	mov    %r8,(%rcx,%rsi,8)
 268:	e9 d2 fe ff ff       	jmp    13f <nontrivial_free+0x13f>
 26d:	48 c7 04 f1 00 00 00 	movq   $0x0,(%rcx,%rsi,8)
 274:	00 
 275:	e9 c5 fe ff ff       	jmp    13f <nontrivial_free+0x13f>
 27a:	48 8b 74 d1 50       	mov    0x50(%rcx,%rdx,8),%rsi
 27f:	48 85 f6             	test   %rsi,%rsi
 282:	0f 84 c7 fe ff ff    	je     14f <nontrivial_free+0x14f>
 288:	8b 46 18             	mov    0x18(%rsi),%eax
 28b:	85 c0                	test   %eax,%eax
 28d:	0f 85 00 00 00 00    	jne    293 <nontrivial_free+0x293>
			28f: R_X86_64_PC32	.text.unlikely.nontrivial_free-0x4
 293:	48 8b 46 10          	mov    0x10(%rsi),%rax
 297:	41 b8 02 00 00 00    	mov    $0x2,%r8d
 29d:	4c 8d 4e 1c          	lea    0x1c(%rsi),%r9
 2a1:	0f b6 48 08          	movzbl 0x8(%rax),%ecx
 2a5:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 2ac <nontrivial_free+0x2ac>
			2a8: R_X86_64_PC32	__libc-0x1
 2ac:	41 d3 e0             	shl    %cl,%r8d
 2af:	45 8d 50 ff          	lea    -0x1(%r8),%r10d
 2b3:	41 f7 d8             	neg    %r8d
 2b6:	84 c0                	test   %al,%al
 2b8:	75 16                	jne    2d0 <nontrivial_free+0x2d0>
 2ba:	8b 56 1c             	mov    0x1c(%rsi),%edx
 2bd:	41 21 d0             	and    %edx,%r8d
 2c0:	44 89 46 1c          	mov    %r8d,0x1c(%rsi)
 2c4:	41 21 d2             	and    %edx,%r10d
 2c7:	44 89 56 18          	mov    %r10d,0x18(%rsi)
 2cb:	e9 7f fe ff ff       	jmp    14f <nontrivial_free+0x14f>
 2d0:	8b 56 1c             	mov    0x1c(%rsi),%edx
 2d3:	44 89 c1             	mov    %r8d,%ecx
 2d6:	21 d1                	and    %edx,%ecx
 2d8:	89 d0                	mov    %edx,%eax
 2da:	f0 41 0f b1 09       	lock cmpxchg %ecx,(%r9)
 2df:	39 c2                	cmp    %eax,%edx
 2e1:	75 ed                	jne    2d0 <nontrivial_free+0x2d0>
 2e3:	eb df                	jmp    2c4 <nontrivial_free+0x2c4>
 2e5:	66 48 0f 6e c7       	movq   %rdi,%xmm0
 2ea:	66 0f 6c c0          	punpcklqdq %xmm0,%xmm0
 2ee:	0f 11 07             	movups %xmm0,(%rdi)
 2f1:	48 89 3c d1          	mov    %rdi,(%rcx,%rdx,8)
 2f5:	e9 a1 fd ff ff       	jmp    9b <nontrivial_free+0x9b>
 2fa:	f0 44 09 47 1c       	lock or %r8d,0x1c(%rdi)
 2ff:	e9 af fd ff ff       	jmp    b3 <nontrivial_free+0xb3>

Disassembly of section .text.unlikely.__libc_free:

0000000000000000 <__libc_free.cold>:
   0:	0f 0b                	ud2

Disassembly of section .text.__libc_free:

0000000000000000 <__libc_free>:
   0:	48 85 ff             	test   %rdi,%rdi
   3:	0f 84 29 03 00 00    	je     332 <__libc_free+0x332>
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
  69:	4c 8b 5b 10          	mov    0x10(%rbx),%r11
  6d:	4c 39 da             	cmp    %r11,%rdx
  70:	0f 85 00 00 00 00    	jne    76 <__libc_free+0x76>
			72: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
  76:	44 0f b6 53 20       	movzbl 0x20(%rbx),%r10d
  7b:	44 89 d2             	mov    %r10d,%edx
  7e:	45 89 d0             	mov    %r10d,%r8d
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
  d3:	77 64                	ja     139 <__libc_free+0x139>
  d5:	49 89 f4             	mov    %rsi,%r12
  d8:	48 8d 15 00 00 00 00 	lea    0x0(%rip),%rdx        # df <__libc_free+0xdf>
			db: R_X86_64_PC32	__malloc_size_classes-0x4
  df:	41 83 e4 3f          	and    $0x3f,%r12d
  e3:	42 0f b7 14 62       	movzwl (%rdx,%r12,2),%edx
  e8:	41 89 ec             	mov    %ebp,%r12d
  eb:	44 0f af e2          	imul   %edx,%r12d
  ef:	44 39 e7             	cmp    %r12d,%edi
  f2:	0f 8c 00 00 00 00    	jl     f8 <__libc_free+0xf8>
			f4: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
  f8:	44 01 e2             	add    %r12d,%edx
  fb:	39 d7                	cmp    %edx,%edi
  fd:	7d 35                	jge    134 <__libc_free+0x134>
  ff:	48 81 7b 20 ff 0f 00 	cmpq   $0xfff,0x20(%rbx)
 106:	00 
 107:	76 3e                	jbe    147 <__libc_free+0x147>
 109:	48 8b 53 20          	mov    0x20(%rbx),%rdx
 10d:	48 81 e2 00 f0 ff ff 	and    $0xfffffffffffff000,%rdx
 114:	49 89 d4             	mov    %rdx,%r12
 117:	49 c1 ec 04          	shr    $0x4,%r12
 11b:	49 83 ec 01          	sub    $0x1,%r12
 11f:	49 39 fc             	cmp    %rdi,%r12
 122:	0f 82 00 00 00 00    	jb     128 <__libc_free+0x128>
			124: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 128:	41 83 e2 1f          	and    $0x1f,%r10d
 12c:	75 19                	jne    147 <__libc_free+0x147>
 12e:	48 83 ea 10          	sub    $0x10,%rdx
 132:	eb 27                	jmp    15b <__libc_free+0x15b>
 134:	e9 00 00 00 00       	jmp    139 <__libc_free+0x139>
			135: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 139:	f7 d2                	not    %edx
 13b:	66 f7 c2 c0 0f       	test   $0xfc0,%dx
 140:	74 bd                	je     ff <__libc_free+0xff>
 142:	e9 00 00 00 00       	jmp    147 <__libc_free+0x147>
			143: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 147:	83 e6 3f             	and    $0x3f,%esi
 14a:	48 8d 15 00 00 00 00 	lea    0x0(%rip),%rdx        # 151 <__libc_free+0x151>
			14d: R_X86_64_PC32	__malloc_size_classes-0x4
 151:	0f b7 14 72          	movzwl (%rdx,%rsi,2),%edx
 155:	c1 e2 04             	shl    $0x4,%edx
 158:	48 63 d2             	movslq %edx,%rdx
 15b:	0f b6 f1             	movzbl %cl,%esi
 15e:	48 0f af f2          	imul   %rdx,%rsi
 162:	48 8d 74 32 fc       	lea    -0x4(%rdx,%rsi,1),%rsi
 167:	49 8d 7c 33 10       	lea    0x10(%r11,%rsi,1),%rdi
 16c:	44 89 ce             	mov    %r9d,%esi
 16f:	40 c0 ee 05          	shr    $0x5,%sil
 173:	41 80 f9 9f          	cmp    $0x9f,%r9b
 177:	0f 87 b4 00 00 00    	ja     231 <__libc_free+0x231>
 17d:	40 0f b6 f6          	movzbl %sil,%esi
 181:	49 89 f9             	mov    %rdi,%r9
 184:	49 29 c1             	sub    %rax,%r9
 187:	49 39 f1             	cmp    %rsi,%r9
 18a:	0f 82 00 00 00 00    	jb     190 <__libc_free+0x190>
			18c: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 190:	49 89 f9             	mov    %rdi,%r9
 193:	49 29 f1             	sub    %rsi,%r9
 196:	41 80 39 00          	cmpb   $0x0,(%r9)
 19a:	0f 85 00 00 00 00    	jne    1a0 <__libc_free+0x1a0>
			19c: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 1a0:	80 3f 00             	cmpb   $0x0,(%rdi)
 1a3:	0f 85 00 00 00 00    	jne    1a9 <__libc_free+0x1a9>
			1a5: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 1a9:	be 01 00 00 00       	mov    $0x1,%esi
 1ae:	bf 02 00 00 00       	mov    $0x2,%edi
 1b3:	c6 40 fd ff          	movb   $0xff,-0x3(%rax)
 1b7:	d3 e6                	shl    %cl,%esi
 1b9:	44 89 c1             	mov    %r8d,%ecx
 1bc:	d3 e7                	shl    %cl,%edi
 1be:	31 c9                	xor    %ecx,%ecx
 1c0:	66 89 48 fe          	mov    %cx,-0x2(%rax)
 1c4:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 1cb <__libc_free+0x1cb>
			1c7: R_X86_64_PC32	__libc-0x1
 1cb:	83 ef 01             	sub    $0x1,%edi
 1ce:	84 c0                	test   %al,%al
 1d0:	75 15                	jne    1e7 <__libc_free+0x1e7>
 1d2:	0f b7 43 20          	movzwl 0x20(%rbx),%eax
 1d6:	66 c1 e8 06          	shr    $0x6,%ax
 1da:	83 e0 3f             	and    $0x3f,%eax
 1dd:	3c 2f                	cmp    $0x2f,%al
 1df:	77 06                	ja     1e7 <__libc_free+0x1e7>
 1e1:	48 39 5b 08          	cmp    %rbx,0x8(%rbx)
 1e5:	74 70                	je     257 <__libc_free+0x257>
 1e7:	8b 53 1c             	mov    0x1c(%rbx),%edx
 1ea:	8b 43 18             	mov    0x18(%rbx),%eax
 1ed:	09 d0                	or     %edx,%eax
 1ef:	85 c6                	test   %eax,%esi
 1f1:	0f 85 00 00 00 00    	jne    1f7 <__libc_free+0x1f7>
			1f3: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 1f7:	85 d2                	test   %edx,%edx
 1f9:	0f 84 ca 00 00 00    	je     2c9 <__libc_free+0x2c9>
 1ff:	01 f0                	add    %esi,%eax
 201:	39 f8                	cmp    %edi,%eax
 203:	0f 84 c0 00 00 00    	je     2c9 <__libc_free+0x2c9>
 209:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 210 <__libc_free+0x210>
			20c: R_X86_64_PC32	__libc-0x1
 210:	8d 0c 16             	lea    (%rsi,%rdx,1),%ecx
 213:	84 c0                	test   %al,%al
 215:	0f 84 a6 00 00 00    	je     2c1 <__libc_free+0x2c1>
 21b:	89 d0                	mov    %edx,%eax
 21d:	f0 0f b1 4b 1c       	lock cmpxchg %ecx,0x1c(%rbx)
 222:	39 c2                	cmp    %eax,%edx
 224:	75 c1                	jne    1e7 <__libc_free+0x1e7>
 226:	48 83 c4 08          	add    $0x8,%rsp
 22a:	5b                   	pop    %rbx
 22b:	5d                   	pop    %rbp
 22c:	41 5c                	pop    %r12
 22e:	41 5d                	pop    %r13
 230:	c3                   	ret
 231:	40 80 fe 05          	cmp    $0x5,%sil
 235:	0f 85 00 00 00 00    	jne    23b <__libc_free+0x23b>
			237: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 23b:	8b 77 fc             	mov    -0x4(%rdi),%esi
 23e:	48 83 fe 04          	cmp    $0x4,%rsi
 242:	0f 86 00 00 00 00    	jbe    248 <__libc_free+0x248>
			244: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 248:	80 7f fb 00          	cmpb   $0x0,-0x5(%rdi)
 24c:	0f 84 2f ff ff ff    	je     181 <__libc_free+0x181>
 252:	e9 00 00 00 00       	jmp    257 <__libc_free+0x257>
			253: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 257:	83 e0 3f             	and    $0x3f,%eax
 25a:	48 8d 0d 00 00 00 00 	lea    0x0(%rip),%rcx        # 261 <__libc_free+0x261>
			25d: R_X86_64_PC32	__malloc_size_classes-0x4
 261:	0f b7 04 41          	movzwl (%rcx,%rax,2),%eax
 265:	c1 e0 04             	shl    $0x4,%eax
 268:	48 98                	cltq
 26a:	48 39 c2             	cmp    %rax,%rdx
 26d:	0f 82 74 ff ff ff    	jb     1e7 <__libc_free+0x1e7>
 273:	48 81 7b 20 ff 0f 00 	cmpq   $0xfff,0x20(%rbx)
 27a:	00 
 27b:	76 18                	jbe    295 <__libc_free+0x295>
 27d:	48 8b 43 20          	mov    0x20(%rbx),%rax
 281:	48 25 00 f0 ff ff    	and    $0xfffffffffffff000,%rax
 287:	48 3d 00 00 02 00    	cmp    $0x20000,%rax
 28d:	0f 87 54 ff ff ff    	ja     1e7 <__libc_free+0x1e7>
 293:	eb 1f                	jmp    2b4 <__libc_free+0x2b4>
 295:	0f b6 43 20          	movzbl 0x20(%rbx),%eax
 299:	83 e0 1f             	and    $0x1f,%eax
 29c:	48 83 c0 01          	add    $0x1,%rax
 2a0:	48 0f af c2          	imul   %rdx,%rax
 2a4:	48 83 c0 10          	add    $0x10,%rax
 2a8:	48 3d 00 00 02 00    	cmp    $0x20000,%rax
 2ae:	0f 87 33 ff ff ff    	ja     1e7 <__libc_free+0x1e7>
 2b4:	8b 43 1c             	mov    0x1c(%rbx),%eax
 2b7:	09 f0                	or     %esi,%eax
 2b9:	89 43 1c             	mov    %eax,0x1c(%rbx)
 2bc:	e9 65 ff ff ff       	jmp    226 <__libc_free+0x226>
 2c1:	89 4b 1c             	mov    %ecx,0x1c(%rbx)
 2c4:	e9 5d ff ff ff       	jmp    226 <__libc_free+0x226>
 2c9:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 2d0 <__libc_free+0x2d0>
			2cc: R_X86_64_PC32	__libc-0x1
 2d0:	84 c0                	test   %al,%al
 2d2:	75 42                	jne    316 <__libc_free+0x316>
 2d4:	89 ee                	mov    %ebp,%esi
 2d6:	48 89 df             	mov    %rbx,%rdi
 2d9:	e8 00 00 00 00       	call   2de <__libc_free+0x2de>
			2da: R_X86_64_PC32	.text.nontrivial_free-0x4
 2de:	48 89 c5             	mov    %rax,%rbp
 2e1:	8b 05 00 00 00 00    	mov    0x0(%rip),%eax        # 2e7 <__libc_free+0x2e7>
			2e3: R_X86_64_PC32	__malloc_lock-0x4
 2e7:	48 89 d3             	mov    %rdx,%rbx
 2ea:	85 c0                	test   %eax,%eax
 2ec:	78 36                	js     324 <__libc_free+0x324>
 2ee:	48 85 db             	test   %rbx,%rbx
 2f1:	0f 84 2f ff ff ff    	je     226 <__libc_free+0x226>
 2f7:	e8 00 00 00 00       	call   2fc <__libc_free+0x2fc>
			2f8: R_X86_64_PLT32	___errno_location-0x4
 2fc:	48 89 de             	mov    %rbx,%rsi
 2ff:	48 89 ef             	mov    %rbp,%rdi
 302:	44 8b 28             	mov    (%rax),%r13d
 305:	49 89 c4             	mov    %rax,%r12
 308:	e8 00 00 00 00       	call   30d <__libc_free+0x30d>
			309: R_X86_64_PLT32	munmap-0x4
 30d:	45 89 2c 24          	mov    %r13d,(%r12)
 311:	e9 10 ff ff ff       	jmp    226 <__libc_free+0x226>
 316:	48 8d 3d 00 00 00 00 	lea    0x0(%rip),%rdi        # 31d <__libc_free+0x31d>
			319: R_X86_64_PC32	__malloc_lock-0x4
 31d:	e8 00 00 00 00       	call   322 <__libc_free+0x322>
			31e: R_X86_64_PLT32	__lock-0x4
 322:	eb b0                	jmp    2d4 <__libc_free+0x2d4>
 324:	48 8d 3d 00 00 00 00 	lea    0x0(%rip),%rdi        # 32b <__libc_free+0x32b>
			327: R_X86_64_PC32	__malloc_lock-0x4
 32b:	e8 00 00 00 00       	call   330 <__libc_free+0x330>
			32c: R_X86_64_PLT32	__unlock-0x4
 330:	eb bc                	jmp    2ee <__libc_free+0x2ee>
 332:	c3                   	ret

Disassembly of section .text.unlikely.malloc_trim:

0000000000000000 <malloc_trim.cold>:
   0:	0f 0b                	ud2

Disassembly of section .text.malloc_trim:

0000000000000000 <malloc_trim>:
   0:	41 57                	push   %r15
   2:	41 56                	push   %r14
   4:	41 55                	push   %r13
   6:	41 54                	push   %r12
   8:	55                   	push   %rbp
   9:	53                   	push   %rbx
   a:	48 83 ec 08          	sub    $0x8,%rsp
   e:	e8 00 00 00 00       	call   13 <malloc_trim+0x13>
			f: R_X86_64_PLT32	___errno_location-0x4
  13:	44 8b 28             	mov    (%rax),%r13d
  16:	49 89 c4             	mov    %rax,%r12
  19:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 20 <malloc_trim+0x20>
			1c: R_X86_64_PC32	__libc-0x1
  20:	84 c0                	test   %al,%al
  22:	75 13                	jne    37 <malloc_trim+0x37>
  24:	4c 8d 35 00 00 00 00 	lea    0x0(%rip),%r14        # 2b <malloc_trim+0x2b>
			27: R_X86_64_PC32	__malloc_context+0x24
  2b:	31 db                	xor    %ebx,%ebx
  2d:	66 0f ef c0          	pxor   %xmm0,%xmm0
  31:	49 8d 6e d8          	lea    -0x28(%r14),%rbp
  35:	eb 3d                	jmp    74 <malloc_trim+0x74>
  37:	48 8d 3d 00 00 00 00 	lea    0x0(%rip),%rdi        # 3e <malloc_trim+0x3e>
			3a: R_X86_64_PC32	__malloc_lock-0x4
  3e:	e8 00 00 00 00       	call   43 <malloc_trim+0x43>
			3f: R_X86_64_PLT32	__lock-0x4
  43:	eb df                	jmp    24 <malloc_trim+0x24>
  45:	66 48 0f 6e c8       	movq   %rax,%xmm1
  4a:	66 0f 6c c9          	punpcklqdq %xmm1,%xmm1
  4e:	0f 11 08             	movups %xmm1,(%rax)
  51:	48 89 05 00 00 00 00 	mov    %rax,0x0(%rip)        # 58 <malloc_trim+0x58>
			54: R_X86_64_PC32	__malloc_context+0xc
  58:	e8 00 00 00 00       	call   5d <malloc_trim+0x5d>
			59: R_X86_64_PLT32	munmap-0x4
  5d:	66 0f ef c0          	pxor   %xmm0,%xmm0
  61:	85 c0                	test   %eax,%eax
  63:	0f 94 c0             	sete   %al
  66:	0f b6 c0             	movzbl %al,%eax
  69:	09 c3                	or     %eax,%ebx
  6b:	48 83 c5 08          	add    $0x8,%rbp
  6f:	4c 39 f5             	cmp    %r14,%rbp
  72:	74 58                	je     cc <malloc_trim+0xcc>
  74:	48 8b 85 d0 01 00 00 	mov    0x1d0(%rbp),%rax
  7b:	48 85 c0             	test   %rax,%rax
  7e:	74 eb                	je     6b <malloc_trim+0x6b>
  80:	48 c7 85 d0 01 00 00 	movq   $0x0,0x1d0(%rbp)
  87:	00 00 00 00 
  8b:	48 8b 70 20          	mov    0x20(%rax),%rsi
  8f:	48 8b 78 10          	mov    0x10(%rax),%rdi
  93:	0f 11 00             	movups %xmm0,(%rax)
  96:	0f 11 40 10          	movups %xmm0,0x10(%rax)
  9a:	48 8b 15 00 00 00 00 	mov    0x0(%rip),%rdx        # a1 <malloc_trim+0xa1>
			9d: R_X86_64_PC32	__malloc_context+0xc
  a1:	48 81 e6 00 f0 ff ff 	and    $0xfffffffffffff000,%rsi
  a8:	48 c7 40 20 00 00 00 	movq   $0x0,0x20(%rax)
  af:	00 
  b0:	48 85 d2             	test   %rdx,%rdx
  b3:	74 90                	je     45 <malloc_trim+0x45>
  b5:	48 89 50 08          	mov    %rdx,0x8(%rax)
  b9:	48 8b 12             	mov    (%rdx),%rdx
  bc:	48 89 10             	mov    %rdx,(%rax)
  bf:	48 89 42 08          	mov    %rax,0x8(%rdx)
  c3:	48 8b 50 08          	mov    0x8(%rax),%rdx
  c7:	48 89 02             	mov    %rax,(%rdx)
  ca:	eb 8c                	jmp    58 <malloc_trim+0x58>
  cc:	4c 8d 3d 00 00 00 00 	lea    0x0(%rip),%r15        # d3 <malloc_trim+0xd3>
			cf: R_X86_64_PC32	__malloc_context+0x4c
  d3:	41 be 02 00 00 00    	mov    $0x2,%r14d
  d9:	49 8d af 80 01 00 00 	lea    0x180(%r15),%rbp
  e0:	e9 3f 01 00 00       	jmp    224 <malloc_trim+0x224>
  e5:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
  ec:	00 00 00 00 
  f0:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
  f7:	00 00 00 00 
  fb:	0f 1f 44 00 00       	nopl   0x0(%rax,%rax,1)
 100:	48 8b 7f 08          	mov    0x8(%rdi),%rdi
 104:	48 39 fe             	cmp    %rdi,%rsi
 107:	74 1f                	je     128 <malloc_trim+0x128>
 109:	0f b6 4f 20          	movzbl 0x20(%rdi),%ecx
 10d:	f6 c1 20             	test   $0x20,%cl
 110:	74 ee                	je     100 <malloc_trim+0x100>
 112:	8b 57 18             	mov    0x18(%rdi),%edx
 115:	8b 47 1c             	mov    0x1c(%rdi),%eax
 118:	09 c2                	or     %eax,%edx
 11a:	44 89 f0             	mov    %r14d,%eax
 11d:	d3 e0                	shl    %cl,%eax
 11f:	83 e8 01             	sub    $0x1,%eax
 122:	39 c2                	cmp    %eax,%edx
 124:	75 da                	jne    100 <malloc_trim+0x100>
 126:	eb 0a                	jmp    132 <malloc_trim+0x132>
 128:	f6 47 20 20          	testb  $0x20,0x20(%rdi)
 12c:	0f 84 ee 00 00 00    	je     220 <malloc_trim+0x220>
 132:	8b 57 18             	mov    0x18(%rdi),%edx
 135:	8b 47 1c             	mov    0x1c(%rdi),%eax
 138:	0f b6 4f 20          	movzbl 0x20(%rdi),%ecx
 13c:	09 c2                	or     %eax,%edx
 13e:	44 89 f0             	mov    %r14d,%eax
 141:	d3 e0                	shl    %cl,%eax
 143:	83 e8 01             	sub    $0x1,%eax
 146:	39 c2                	cmp    %eax,%edx
 148:	0f 85 d2 00 00 00    	jne    220 <malloc_trim+0x220>
 14e:	48 8b 47 08          	mov    0x8(%rdi),%rax
 152:	48 39 c7             	cmp    %rax,%rdi
 155:	74 4f                	je     1a6 <malloc_trim+0x1a6>
 157:	48 8b 17             	mov    (%rdi),%rdx
 15a:	48 89 42 08          	mov    %rax,0x8(%rdx)
 15e:	48 8b 17             	mov    (%rdi),%rdx
 161:	48 89 10             	mov    %rdx,(%rax)
 164:	49 3b 3f             	cmp    (%r15),%rdi
 167:	74 34                	je     19d <malloc_trim+0x19d>
 169:	66 0f ef c0          	pxor   %xmm0,%xmm0
 16d:	0f 11 07             	movups %xmm0,(%rdi)
 170:	49 8b 37             	mov    (%r15),%rsi
 173:	48 85 f6             	test   %rsi,%rsi
 176:	74 07                	je     17f <malloc_trim+0x17f>
 178:	8b 46 18             	mov    0x18(%rsi),%eax
 17b:	85 c0                	test   %eax,%eax
 17d:	74 30                	je     1af <malloc_trim+0x1af>
 17f:	e8 00 00 00 00       	call   184 <malloc_trim+0x184>
			180: R_X86_64_PC32	.text.free_group-0x4
 184:	48 85 d2             	test   %rdx,%rdx
 187:	75 7d                	jne    206 <malloc_trim+0x206>
 189:	49 8b 37             	mov    (%r15),%rsi
 18c:	48 85 f6             	test   %rsi,%rsi
 18f:	0f 84 8b 00 00 00    	je     220 <malloc_trim+0x220>
 195:	48 89 f7             	mov    %rsi,%rdi
 198:	e9 6c ff ff ff       	jmp    109 <malloc_trim+0x109>
 19d:	48 8b 47 08          	mov    0x8(%rdi),%rax
 1a1:	49 89 07             	mov    %rax,(%r15)
 1a4:	eb c3                	jmp    169 <malloc_trim+0x169>
 1a6:	49 c7 07 00 00 00 00 	movq   $0x0,(%r15)
 1ad:	eb ba                	jmp    169 <malloc_trim+0x169>
 1af:	8b 46 18             	mov    0x18(%rsi),%eax
 1b2:	85 c0                	test   %eax,%eax
 1b4:	0f 85 00 00 00 00    	jne    1ba <malloc_trim+0x1ba>
			1b6: R_X86_64_PC32	.text.unlikely.malloc_trim-0x4
 1ba:	48 8b 46 10          	mov    0x10(%rsi),%rax
 1be:	45 89 f0             	mov    %r14d,%r8d
 1c1:	4c 8d 4e 1c          	lea    0x1c(%rsi),%r9
 1c5:	0f b6 48 08          	movzbl 0x8(%rax),%ecx
 1c9:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 1d0 <malloc_trim+0x1d0>
			1cc: R_X86_64_PC32	__libc-0x1
 1d0:	41 d3 e0             	shl    %cl,%r8d
 1d3:	45 8d 50 ff          	lea    -0x1(%r8),%r10d
 1d7:	41 f7 d8             	neg    %r8d
 1da:	84 c0                	test   %al,%al
 1dc:	75 13                	jne    1f1 <malloc_trim+0x1f1>
 1de:	8b 56 1c             	mov    0x1c(%rsi),%edx
 1e1:	41 21 d0             	and    %edx,%r8d
 1e4:	44 89 46 1c          	mov    %r8d,0x1c(%rsi)
 1e8:	41 21 d2             	and    %edx,%r10d
 1eb:	44 89 56 18          	mov    %r10d,0x18(%rsi)
 1ef:	eb 8e                	jmp    17f <malloc_trim+0x17f>
 1f1:	8b 56 1c             	mov    0x1c(%rsi),%edx
 1f4:	89 d1                	mov    %edx,%ecx
 1f6:	89 d0                	mov    %edx,%eax
 1f8:	44 21 c1             	and    %r8d,%ecx
 1fb:	f0 41 0f b1 09       	lock cmpxchg %ecx,(%r9)
 200:	39 c2                	cmp    %eax,%edx
 202:	75 ed                	jne    1f1 <malloc_trim+0x1f1>
 204:	eb e2                	jmp    1e8 <malloc_trim+0x1e8>
 206:	48 89 d6             	mov    %rdx,%rsi
 209:	48 89 c7             	mov    %rax,%rdi
 20c:	e8 00 00 00 00       	call   211 <malloc_trim+0x211>
			20d: R_X86_64_PLT32	munmap-0x4
 211:	85 c0                	test   %eax,%eax
 213:	0f 94 c0             	sete   %al
 216:	0f b6 c0             	movzbl %al,%eax
 219:	09 c3                	or     %eax,%ebx
 21b:	e9 69 ff ff ff       	jmp    189 <malloc_trim+0x189>
 220:	49 83 c7 08          	add    $0x8,%r15
 224:	49 39 ef             	cmp    %rbp,%r15
 227:	0f 85 5c ff ff ff    	jne    189 <malloc_trim+0x189>
 22d:	8b 05 00 00 00 00    	mov    0x0(%rip),%eax        # 233 <malloc_trim+0x233>
			22f: R_X86_64_PC32	__malloc_lock-0x4
 233:	85 c0                	test   %eax,%eax
 235:	78 15                	js     24c <malloc_trim+0x24c>
 237:	45 89 2c 24          	mov    %r13d,(%r12)
 23b:	48 83 c4 08          	add    $0x8,%rsp
 23f:	89 d8                	mov    %ebx,%eax
 241:	5b                   	pop    %rbx
 242:	5d                   	pop    %rbp
 243:	41 5c                	pop    %r12
 245:	41 5d                	pop    %r13
 247:	41 5e                	pop    %r14
 249:	41 5f                	pop    %r15
 24b:	c3                   	ret
 24c:	48 8d 3d 00 00 00 00 	lea    0x0(%rip),%rdi        # 253 <malloc_trim+0x253>
			24f: R_X86_64_PC32	__malloc_lock-0x4
 253:	e8 00 00 00 00       	call   258 <malloc_trim+0x258>
			254: R_X86_64_PLT32	__unlock-0x4
 258:	eb dd                	jmp    237 <malloc_trim+0x237>

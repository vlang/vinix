
/Users/alex/code/vinix/third_party/useralloc-libc/build/musl/x86_64/c97687ce9e5ca67f3acb8947bf28d3def2b044abf977e9e91ab8e8c767083b1c/objects/obj/src/malloc/mallocng/free.o:     file format elf64-x86-64


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
  12:	0f 84 9f 00 00 00    	je     b7 <free_group+0xb7>
  18:	83 fa 2f             	cmp    $0x2f,%edx
  1b:	7f 15                	jg     32 <free_group+0x32>
  1d:	0f b6 47 20          	movzbl 0x20(%rdi),%eax
  21:	48 63 ca             	movslq %edx,%rcx
  24:	83 e0 1f             	and    $0x1f,%eax
  27:	48 f7 d0             	not    %rax
  2a:	48 01 04 cd 00 00 00 	add    %rax,0x0(,%rcx,8)
  31:	00 
			2e: R_X86_64_32S	__malloc_context+0x1f8
  32:	48 81 7b 20 ff 0f 00 	cmpq   $0xfff,0x20(%rbx)
  39:	00 
  3a:	0f 86 5d 01 00 00    	jbe    19d <free_group+0x19d>
  40:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 47 <free_group+0x47>
			43: R_X86_64_PC32	__malloc_context+0x3b4
  47:	8d 48 01             	lea    0x1(%rax),%ecx
  4a:	3c ff                	cmp    $0xff,%al
  4c:	0f 84 26 01 00 00    	je     178 <free_group+0x178>
  52:	83 ea 07             	sub    $0x7,%edx
  55:	88 0d 00 00 00 00    	mov    %cl,0x0(%rip)        # 5b <free_group+0x5b>
			57: R_X86_64_PC32	__malloc_context+0x3b4
  5b:	83 fa 1f             	cmp    $0x1f,%edx
  5e:	77 09                	ja     69 <free_group+0x69>
  60:	48 63 d2             	movslq %edx,%rdx
  63:	88 8a 00 00 00 00    	mov    %cl,0x0(%rdx)
			65: R_X86_64_32S	__malloc_context+0x378
  69:	48 8b 43 20          	mov    0x20(%rbx),%rax
  6d:	48 8b 7b 10          	mov    0x10(%rbx),%rdi
  71:	48 25 00 f0 ff ff    	and    $0xfffffffffffff000,%rax
  77:	66 0f ef c0          	pxor   %xmm0,%xmm0
  7b:	48 c7 43 20 00 00 00 	movq   $0x0,0x20(%rbx)
  82:	00 
  83:	0f 11 03             	movups %xmm0,(%rbx)
  86:	0f 11 43 10          	movups %xmm0,0x10(%rbx)
  8a:	48 8b 15 00 00 00 00 	mov    0x0(%rip),%rdx        # 91 <free_group+0x91>
			8d: R_X86_64_PC32	__malloc_context+0xc
  91:	48 85 d2             	test   %rdx,%rdx
  94:	0f 84 2a 02 00 00    	je     2c4 <free_group+0x2c4>
  9a:	48 89 53 08          	mov    %rdx,0x8(%rbx)
  9e:	48 8b 12             	mov    (%rdx),%rdx
  a1:	48 89 13             	mov    %rdx,(%rbx)
  a4:	48 89 5a 08          	mov    %rbx,0x8(%rdx)
  a8:	48 8b 53 08          	mov    0x8(%rbx),%rdx
  ac:	48 89 1a             	mov    %rbx,(%rdx)
  af:	48 89 c2             	mov    %rax,%rdx
  b2:	5b                   	pop    %rbx
  b3:	48 89 f8             	mov    %rdi,%rax
  b6:	c3                   	ret
  b7:	48 8b 77 20          	mov    0x20(%rdi),%rsi
  bb:	48 c1 ee 0c          	shr    $0xc,%rsi
  bf:	48 8d 46 e0          	lea    -0x20(%rsi),%rax
  c3:	48 3d e0 01 00 00    	cmp    $0x1e0,%rax
  c9:	0f 87 63 ff ff ff    	ja     32 <free_group+0x32>
  cf:	b8 20 00 00 00       	mov    $0x20,%eax
  d4:	31 c9                	xor    %ecx,%ecx
  d6:	eb 0e                	jmp    e6 <free_group+0xe6>
  d8:	0f 1f 84 00 00 00 00 	nopl   0x0(%rax,%rax,1)
  df:	00 
  e0:	83 c1 01             	add    $0x1,%ecx
  e3:	48 01 c0             	add    %rax,%rax
  e6:	48 39 f0             	cmp    %rsi,%rax
  e9:	72 f5                	jb     e0 <free_group+0xe0>
  eb:	48 63 c9             	movslq %ecx,%rcx
  ee:	48 8b 3c cd 00 00 00 	mov    0x0(,%rcx,8),%rdi
  f5:	00 
			f2: R_X86_64_32S	__malloc_context+0x1d0
  f6:	48 85 ff             	test   %rdi,%rdi
  f9:	74 67                	je     162 <free_group+0x162>
  fb:	48 8b 47 20          	mov    0x20(%rdi),%rax
  ff:	48 c1 e8 0c          	shr    $0xc,%rax
 103:	48 39 f0             	cmp    %rsi,%rax
 106:	0f 83 26 ff ff ff    	jae    32 <free_group+0x32>
 10c:	66 0f ef c0          	pxor   %xmm0,%xmm0
 110:	48 8b 77 10          	mov    0x10(%rdi),%rsi
 114:	48 c7 47 20 00 00 00 	movq   $0x0,0x20(%rdi)
 11b:	00 
 11c:	0f 11 07             	movups %xmm0,(%rdi)
 11f:	0f 11 47 10          	movups %xmm0,0x10(%rdi)
 123:	48 8b 15 00 00 00 00 	mov    0x0(%rip),%rdx        # 12a <free_group+0x12a>
			126: R_X86_64_PC32	__malloc_context+0xc
 12a:	48 85 d2             	test   %rdx,%rdx
 12d:	74 1e                	je     14d <free_group+0x14d>
 12f:	48 89 57 08          	mov    %rdx,0x8(%rdi)
 133:	48 8b 12             	mov    (%rdx),%rdx
 136:	48 89 17             	mov    %rdx,(%rdi)
 139:	48 89 7a 08          	mov    %rdi,0x8(%rdx)
 13d:	48 8b 57 08          	mov    0x8(%rdi),%rdx
 141:	48 89 3a             	mov    %rdi,(%rdx)
 144:	48 c1 e0 0c          	shl    $0xc,%rax
 148:	48 89 f7             	mov    %rsi,%rdi
 14b:	eb 17                	jmp    164 <free_group+0x164>
 14d:	66 48 0f 6e c7       	movq   %rdi,%xmm0
 152:	66 0f 6c c0          	punpcklqdq %xmm0,%xmm0
 156:	0f 11 07             	movups %xmm0,(%rdi)
 159:	48 89 3d 00 00 00 00 	mov    %rdi,0x0(%rip)        # 160 <free_group+0x160>
			15c: R_X86_64_PC32	__malloc_context+0xc
 160:	eb e2                	jmp    144 <free_group+0x144>
 162:	31 c0                	xor    %eax,%eax
 164:	c7 43 1c 01 00 00 00 	movl   $0x1,0x1c(%rbx)
 16b:	48 89 1c cd 00 00 00 	mov    %rbx,0x0(,%rcx,8)
 172:	00 
			16f: R_X86_64_32S	__malloc_context+0x1d0
 173:	e9 37 ff ff ff       	jmp    af <free_group+0xaf>
 178:	b8 00 00 00 00       	mov    $0x0,%eax
			179: R_X86_64_32	__malloc_context+0x378
 17d:	eb 0c                	jmp    18b <free_group+0x18b>
 17f:	90                   	nop
 180:	c6 00 00             	movb   $0x0,(%rax)
 183:	48 83 c0 02          	add    $0x2,%rax
 187:	c6 40 ff 00          	movb   $0x0,-0x1(%rax)
 18b:	48 3d 00 00 00 00    	cmp    $0x0,%rax
			18d: R_X86_64_32S	__malloc_context+0x398
 191:	75 ed                	jne    180 <free_group+0x180>
 193:	b9 01 00 00 00       	mov    $0x1,%ecx
 198:	e9 b5 fe ff ff       	jmp    52 <free_group+0x52>
 19d:	48 8b 43 10          	mov    0x10(%rbx),%rax
 1a1:	a8 0f                	test   $0xf,%al
 1a3:	0f 85 00 00 00 00    	jne    1a9 <free_group+0x1a9>
			1a5: R_X86_64_PC32	.text.unlikely.free_group-0x4
 1a9:	0f b6 70 fd          	movzbl -0x3(%rax),%esi
 1ad:	0f b7 50 fe          	movzwl -0x2(%rax),%edx
 1b1:	41 89 f0             	mov    %esi,%r8d
 1b4:	83 e6 1f             	and    $0x1f,%esi
 1b7:	41 83 e0 1f          	and    $0x1f,%r8d
 1bb:	80 78 fc 00          	cmpb   $0x0,-0x4(%rax)
 1bf:	74 18                	je     1d9 <free_group+0x1d9>
 1c1:	85 d2                	test   %edx,%edx
 1c3:	0f 85 00 00 00 00    	jne    1c9 <free_group+0x1c9>
			1c5: R_X86_64_PC32	.text.unlikely.free_group-0x4
 1c9:	48 63 50 f8          	movslq -0x8(%rax),%rdx
 1cd:	81 fa ff ff 00 00    	cmp    $0xffff,%edx
 1d3:	0f 8e 00 00 00 00    	jle    1d9 <free_group+0x1d9>
			1d5: R_X86_64_PC32	.text.unlikely.free_group-0x4
 1d9:	89 d1                	mov    %edx,%ecx
 1db:	48 89 c7             	mov    %rax,%rdi
 1de:	c1 e1 04             	shl    $0x4,%ecx
 1e1:	48 63 c9             	movslq %ecx,%rcx
 1e4:	48 29 cf             	sub    %rcx,%rdi
 1e7:	48 8d 4f f0          	lea    -0x10(%rdi),%rcx
 1eb:	48 8b 7f f0          	mov    -0x10(%rdi),%rdi
 1ef:	48 3b 4f 10          	cmp    0x10(%rdi),%rcx
 1f3:	0f 85 00 00 00 00    	jne    1f9 <free_group+0x1f9>
			1f5: R_X86_64_PC32	.text.unlikely.free_group-0x4
 1f9:	0f b6 4f 20          	movzbl 0x20(%rdi),%ecx
 1fd:	83 e1 1f             	and    $0x1f,%ecx
 200:	39 ce                	cmp    %ecx,%esi
 202:	0f 8f 00 00 00 00    	jg     208 <free_group+0x208>
			204: R_X86_64_PC32	.text.unlikely.free_group-0x4
 208:	8b 4f 18             	mov    0x18(%rdi),%ecx
 20b:	44 0f a3 c1          	bt     %r8d,%ecx
 20f:	0f 82 00 00 00 00    	jb     215 <free_group+0x215>
			211: R_X86_64_PC32	.text.unlikely.free_group-0x4
 215:	8b 4f 1c             	mov    0x1c(%rdi),%ecx
 218:	44 0f a3 c1          	bt     %r8d,%ecx
 21c:	0f 82 00 00 00 00    	jb     222 <free_group+0x222>
			21e: R_X86_64_PC32	.text.unlikely.free_group-0x4
 222:	48 89 f9             	mov    %rdi,%rcx
 225:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # 22c <free_group+0x22c>
			228: R_X86_64_PC32	__malloc_context-0x4
 22c:	48 81 e1 00 f0 ff ff 	and    $0xfffffffffffff000,%rcx
 233:	4c 39 09             	cmp    %r9,(%rcx)
 236:	0f 85 00 00 00 00    	jne    23c <free_group+0x23c>
			238: R_X86_64_PC32	.text.unlikely.free_group-0x4
 23c:	44 0f b7 47 20       	movzwl 0x20(%rdi),%r8d
 241:	44 89 c1             	mov    %r8d,%ecx
 244:	66 c1 e9 06          	shr    $0x6,%cx
 248:	83 e1 3f             	and    $0x3f,%ecx
 24b:	80 f9 2f             	cmp    $0x2f,%cl
 24e:	77 64                	ja     2b4 <free_group+0x2b4>
 250:	83 e1 3f             	and    $0x3f,%ecx
 253:	41 89 f0             	mov    %esi,%r8d
 256:	0f b7 8c 09 00 00 00 	movzwl 0x0(%rcx,%rcx,1),%ecx
 25d:	00 
			25a: R_X86_64_32S	__malloc_size_classes
 25e:	44 0f af c1          	imul   %ecx,%r8d
 262:	44 39 c2             	cmp    %r8d,%edx
 265:	0f 8c 00 00 00 00    	jl     26b <free_group+0x26b>
			267: R_X86_64_PC32	.text.unlikely.free_group-0x4
 26b:	44 01 c1             	add    %r8d,%ecx
 26e:	39 ca                	cmp    %ecx,%edx
 270:	7d 3d                	jge    2af <free_group+0x2af>
 272:	48 81 7f 20 ff 0f 00 	cmpq   $0xfff,0x20(%rdi)
 279:	00 
 27a:	76 1c                	jbe    298 <free_group+0x298>
 27c:	48 8b 4f 20          	mov    0x20(%rdi),%rcx
 280:	48 81 e1 00 f0 ff ff 	and    $0xfffffffffffff000,%rcx
 287:	48 c1 e9 04          	shr    $0x4,%rcx
 28b:	48 83 e9 01          	sub    $0x1,%rcx
 28f:	48 39 d1             	cmp    %rdx,%rcx
 292:	0f 82 00 00 00 00    	jb     298 <free_group+0x298>
			294: R_X86_64_PC32	.text.unlikely.free_group-0x4
 298:	48 c7 00 00 00 00 00 	movq   $0x0,(%rax)
 29f:	e8 00 00 00 00       	call   2a4 <free_group+0x2a4>
			2a0: R_X86_64_PC32	.text.nontrivial_free-0x4
 2a4:	48 89 c7             	mov    %rax,%rdi
 2a7:	48 89 d0             	mov    %rdx,%rax
 2aa:	e9 c8 fd ff ff       	jmp    77 <free_group+0x77>
 2af:	e9 00 00 00 00       	jmp    2b4 <free_group+0x2b4>
			2b0: R_X86_64_PC32	.text.unlikely.free_group-0x4
 2b4:	41 f7 d0             	not    %r8d
 2b7:	66 41 f7 c0 c0 0f    	test   $0xfc0,%r8w
 2bd:	74 b3                	je     272 <free_group+0x272>
 2bf:	e9 00 00 00 00       	jmp    2c4 <free_group+0x2c4>
			2c0: R_X86_64_PC32	.text.unlikely.free_group-0x4
 2c4:	66 48 0f 6e c3       	movq   %rbx,%xmm0
 2c9:	66 0f 6c c0          	punpcklqdq %xmm0,%xmm0
 2cd:	0f 11 03             	movups %xmm0,(%rbx)
 2d0:	48 89 1d 00 00 00 00 	mov    %rbx,0x0(%rip)        # 2d7 <free_group+0x2d7>
			2d3: R_X86_64_PC32	__malloc_context+0xc
 2d7:	e9 d3 fd ff ff       	jmp    af <free_group+0xaf>

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
  42:	74 72                	je     b6 <nontrivial_free+0xb6>
  44:	85 f6                	test   %esi,%esi
  46:	75 50                	jne    98 <nontrivial_free+0x98>
  48:	83 f8 2f             	cmp    $0x2f,%eax
  4b:	0f 8f 00 00 00 00    	jg     51 <nontrivial_free+0x51>
			4d: R_X86_64_PC32	.text.unlikely.nontrivial_free-0x4
  51:	48 63 d0             	movslq %eax,%rdx
  54:	48 83 c2 0a          	add    $0xa,%rdx
  58:	48 8b 04 d5 00 00 00 	mov    0x0(,%rdx,8),%rax
  5f:	00 
			5c: R_X86_64_32S	__malloc_context
  60:	48 39 f8             	cmp    %rdi,%rax
  63:	74 33                	je     98 <nontrivial_free+0x98>
  65:	48 83 7f 08 00       	cmpq   $0x0,0x8(%rdi)
  6a:	0f 85 00 00 00 00    	jne    70 <nontrivial_free+0x70>
			6c: R_X86_64_PC32	.text.unlikely.nontrivial_free-0x4
  70:	48 83 3f 00          	cmpq   $0x0,(%rdi)
  74:	0f 85 00 00 00 00    	jne    7a <nontrivial_free+0x7a>
			76: R_X86_64_PC32	.text.unlikely.nontrivial_free-0x4
  7a:	48 85 c0             	test   %rax,%rax
  7d:	0f 84 27 02 00 00    	je     2aa <nontrivial_free+0x2aa>
  83:	48 89 47 08          	mov    %rax,0x8(%rdi)
  87:	48 8b 00             	mov    (%rax),%rax
  8a:	48 89 07             	mov    %rax,(%rdi)
  8d:	48 89 78 08          	mov    %rdi,0x8(%rax)
  91:	48 8b 47 08          	mov    0x8(%rdi),%rax
  95:	48 89 38             	mov    %rdi,(%rax)
  98:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 9f <nontrivial_free+0x9f>
			9b: R_X86_64_PC32	__libc-0x1
  9f:	84 c0                	test   %al,%al
  a1:	0f 85 1c 02 00 00    	jne    2c3 <nontrivial_free+0x2c3>
  a7:	8b 47 1c             	mov    0x1c(%rdi),%eax
  aa:	44 09 c0             	or     %r8d,%eax
  ad:	89 47 1c             	mov    %eax,0x1c(%rdi)
  b0:	31 c0                	xor    %eax,%eax
  b2:	31 d2                	xor    %edx,%edx
  b4:	5b                   	pop    %rbx
  b5:	c3                   	ret
  b6:	41 83 e1 20          	and    $0x20,%r9d
  ba:	74 88                	je     44 <nontrivial_free+0x44>
  bc:	4c 8b 4f 08          	mov    0x8(%rdi),%r9
  c0:	83 f8 2f             	cmp    $0x2f,%eax
  c3:	0f 8f 43 01 00 00    	jg     20c <nontrivial_free+0x20c>
  c9:	48 63 d0             	movslq %eax,%rdx
  cc:	44 0f b7 94 12 00 00 	movzwl 0x0(%rdx,%rdx,1),%r10d
  d3:	00 00 
			d1: R_X86_64_32S	__malloc_size_classes
  d5:	84 c9                	test   %cl,%cl
  d7:	75 76                	jne    14f <nontrivial_free+0x14f>
  d9:	48 81 7f 20 ff 0f 00 	cmpq   $0xfff,0x20(%rdi)
  e0:	00 
  e1:	76 6c                	jbe    14f <nontrivial_free+0x14f>
  e3:	48 8b 4f 20          	mov    0x20(%rdi),%rcx
  e7:	44 89 d3             	mov    %r10d,%ebx
  ea:	c1 e3 04             	shl    $0x4,%ebx
  ed:	48 81 e1 00 f0 ff ff 	and    $0xfffffffffffff000,%rcx
  f4:	48 63 db             	movslq %ebx,%rbx
  f7:	48 83 e9 10          	sub    $0x10,%rcx
  fb:	48 39 d9             	cmp    %rbx,%rcx
  fe:	73 4f                	jae    14f <nontrivial_free+0x14f>
 100:	4d 85 c9             	test   %r9,%r9
 103:	74 44                	je     149 <nontrivial_free+0x149>
 105:	48 8d 4a 0a          	lea    0xa(%rdx),%rcx
 109:	48 8b 04 cd 00 00 00 	mov    0x0(,%rcx,8),%rax
 110:	00 
			10d: R_X86_64_32S	__malloc_context
 111:	4c 39 cf             	cmp    %r9,%rdi
 114:	0f 84 11 01 00 00    	je     22b <nontrivial_free+0x22b>
 11a:	48 8b 0f             	mov    (%rdi),%rcx
 11d:	4c 89 49 08          	mov    %r9,0x8(%rcx)
 121:	48 8b 0f             	mov    (%rdi),%rcx
 124:	49 89 09             	mov    %rcx,(%r9)
 127:	48 8d 4a 0a          	lea    0xa(%rdx),%rcx
 12b:	48 3b 3c d5 00 00 00 	cmp    0x0(,%rdx,8),%rdi
 132:	00 
			12f: R_X86_64_32S	__malloc_context+0x50
 133:	0f 84 e1 00 00 00    	je     21a <nontrivial_free+0x21a>
 139:	66 0f ef c0          	pxor   %xmm0,%xmm0
 13d:	0f 11 07             	movups %xmm0,(%rdi)
 140:	48 39 c7             	cmp    %rax,%rdi
 143:	0f 84 f3 00 00 00    	je     23c <nontrivial_free+0x23c>
 149:	5b                   	pop    %rbx
 14a:	e9 00 00 00 00       	jmp    14f <nontrivial_free+0x14f>
			14b: R_X86_64_PC32	.text.free_group-0x4
 14f:	4c 39 cf             	cmp    %r9,%rdi
 152:	74 38                	je     18c <nontrivial_free+0x18c>
 154:	4d 85 c9             	test   %r9,%r9
 157:	74 0a                	je     163 <nontrivial_free+0x163>
 159:	48 8b 04 d5 00 00 00 	mov    0x0(,%rdx,8),%rax
 160:	00 
			15d: R_X86_64_32S	__malloc_context+0x50
 161:	eb b7                	jmp    11a <nontrivial_free+0x11a>
 163:	48 83 3c d5 00 00 00 	cmpq   $0x0,0x0(,%rdx,8)
 16a:	00 00 
			167: R_X86_64_32S	__malloc_context+0x50
 16c:	75 db                	jne    149 <nontrivial_free+0x149>
 16e:	48 81 7f 20 ff 0f 00 	cmpq   $0xfff,0x20(%rdi)
 175:	00 
 176:	76 71                	jbe    1e9 <nontrivial_free+0x1e9>
 178:	48 8b 47 20          	mov    0x20(%rdi),%rax
 17c:	48 25 00 f0 ff ff    	and    $0xfffffffffffff000,%rax
 182:	48 3d 00 00 02 00    	cmp    $0x20000,%rax
 188:	77 bf                	ja     149 <nontrivial_free+0x149>
 18a:	eb 73                	jmp    1ff <nontrivial_free+0x1ff>
 18c:	48 81 7f 20 ff 0f 00 	cmpq   $0xfff,0x20(%rdi)
 193:	00 
 194:	76 53                	jbe    1e9 <nontrivial_free+0x1e9>
 196:	48 8b 4f 20          	mov    0x20(%rdi),%rcx
 19a:	48 81 e1 00 f0 ff ff 	and    $0xfffffffffffff000,%rcx
 1a1:	48 81 f9 00 00 02 00 	cmp    $0x20000,%rcx
 1a8:	76 55                	jbe    1ff <nontrivial_free+0x1ff>
 1aa:	83 e8 07             	sub    $0x7,%eax
 1ad:	83 f8 1f             	cmp    $0x1f,%eax
 1b0:	77 25                	ja     1d7 <nontrivial_free+0x1d7>
 1b2:	48 98                	cltq
 1b4:	80 b8 00 00 00 00 63 	cmpb   $0x63,0x0(%rax)
			1b6: R_X86_64_32S	__malloc_context+0x398
 1bb:	76 1a                	jbe    1d7 <nontrivial_free+0x1d7>
 1bd:	41 8d 43 01          	lea    0x1(%r11),%eax
 1c1:	48 63 c8             	movslq %eax,%rcx
 1c4:	48 8d 0c c9          	lea    (%rcx,%rcx,8),%rcx
 1c8:	48 39 0c d5 00 00 00 	cmp    %rcx,0x0(,%rdx,8)
 1cf:	00 
			1cc: R_X86_64_32S	__malloc_context+0x1f8
 1d0:	72 2d                	jb     1ff <nontrivial_free+0x1ff>
 1d2:	83 f8 13             	cmp    $0x13,%eax
 1d5:	7f 28                	jg     1ff <nontrivial_free+0x1ff>
 1d7:	4c 8b 4f 08          	mov    0x8(%rdi),%r9
 1db:	4d 85 c9             	test   %r9,%r9
 1de:	0f 85 21 ff ff ff    	jne    105 <nontrivial_free+0x105>
 1e4:	e9 60 ff ff ff       	jmp    149 <nontrivial_free+0x149>
 1e9:	41 8d 43 01          	lea    0x1(%r11),%eax
 1ed:	41 0f af c2          	imul   %r10d,%eax
 1f1:	83 c0 01             	add    $0x1,%eax
 1f4:	3d 00 20 00 00       	cmp    $0x2000,%eax
 1f9:	0f 8f 01 ff ff ff    	jg     100 <nontrivial_free+0x100>
 1ff:	85 f6                	test   %esi,%esi
 201:	0f 84 4d fe ff ff    	je     54 <nontrivial_free+0x54>
 207:	e9 8c fe ff ff       	jmp    98 <nontrivial_free+0x98>
 20c:	4d 85 c9             	test   %r9,%r9
 20f:	0f 85 00 00 00 00    	jne    215 <nontrivial_free+0x215>
			211: R_X86_64_PC32	.text.unlikely.nontrivial_free-0x4
 215:	e9 2f ff ff ff       	jmp    149 <nontrivial_free+0x149>
 21a:	48 8b 77 08          	mov    0x8(%rdi),%rsi
 21e:	48 89 34 cd 00 00 00 	mov    %rsi,0x0(,%rcx,8)
 225:	00 
			222: R_X86_64_32S	__malloc_context
 226:	e9 0e ff ff ff       	jmp    139 <nontrivial_free+0x139>
 22b:	48 c7 04 cd 00 00 00 	movq   $0x0,0x0(,%rcx,8)
 232:	00 00 00 00 00 
			22f: R_X86_64_32S	__malloc_context
 237:	e9 fd fe ff ff       	jmp    139 <nontrivial_free+0x139>
 23c:	48 8b 34 d5 00 00 00 	mov    0x0(,%rdx,8),%rsi
 243:	00 
			240: R_X86_64_32S	__malloc_context+0x50
 244:	48 85 f6             	test   %rsi,%rsi
 247:	0f 84 fc fe ff ff    	je     149 <nontrivial_free+0x149>
 24d:	8b 46 18             	mov    0x18(%rsi),%eax
 250:	85 c0                	test   %eax,%eax
 252:	0f 85 00 00 00 00    	jne    258 <nontrivial_free+0x258>
			254: R_X86_64_PC32	.text.unlikely.nontrivial_free-0x4
 258:	48 8b 46 10          	mov    0x10(%rsi),%rax
 25c:	41 b8 02 00 00 00    	mov    $0x2,%r8d
 262:	4c 8d 4e 1c          	lea    0x1c(%rsi),%r9
 266:	0f b6 48 08          	movzbl 0x8(%rax),%ecx
 26a:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 271 <nontrivial_free+0x271>
			26d: R_X86_64_PC32	__libc-0x1
 271:	41 d3 e0             	shl    %cl,%r8d
 274:	45 8d 50 ff          	lea    -0x1(%r8),%r10d
 278:	41 f7 d8             	neg    %r8d
 27b:	84 c0                	test   %al,%al
 27d:	75 16                	jne    295 <nontrivial_free+0x295>
 27f:	8b 56 1c             	mov    0x1c(%rsi),%edx
 282:	41 21 d0             	and    %edx,%r8d
 285:	44 89 46 1c          	mov    %r8d,0x1c(%rsi)
 289:	41 21 d2             	and    %edx,%r10d
 28c:	44 89 56 18          	mov    %r10d,0x18(%rsi)
 290:	e9 b4 fe ff ff       	jmp    149 <nontrivial_free+0x149>
 295:	8b 56 1c             	mov    0x1c(%rsi),%edx
 298:	44 89 c1             	mov    %r8d,%ecx
 29b:	21 d1                	and    %edx,%ecx
 29d:	89 d0                	mov    %edx,%eax
 29f:	f0 41 0f b1 09       	lock cmpxchg %ecx,(%r9)
 2a4:	39 c2                	cmp    %eax,%edx
 2a6:	75 ed                	jne    295 <nontrivial_free+0x295>
 2a8:	eb df                	jmp    289 <nontrivial_free+0x289>
 2aa:	66 48 0f 6e c7       	movq   %rdi,%xmm0
 2af:	66 0f 6c c0          	punpcklqdq %xmm0,%xmm0
 2b3:	0f 11 07             	movups %xmm0,(%rdi)
 2b6:	48 89 3c d5 00 00 00 	mov    %rdi,0x0(,%rdx,8)
 2bd:	00 
			2ba: R_X86_64_32S	__malloc_context
 2be:	e9 d5 fd ff ff       	jmp    98 <nontrivial_free+0x98>
 2c3:	f0 44 09 47 1c       	lock or %r8d,0x1c(%rdi)
 2c8:	e9 e3 fd ff ff       	jmp    b0 <nontrivial_free+0xb0>

Disassembly of section .text.unlikely.__libc_free:

0000000000000000 <__libc_free.cold>:
   0:	0f 0b                	ud2

Disassembly of section .text.__libc_free:

0000000000000000 <__libc_free>:
   0:	48 85 ff             	test   %rdi,%rdi
   3:	0f 84 1a 03 00 00    	je     323 <__libc_free+0x323>
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
 123:	41 83 e2 1f          	and    $0x1f,%r10d
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
 15a:	48 8d 74 32 fc       	lea    -0x4(%rdx,%rsi,1),%rsi
 15f:	49 8d 7c 33 10       	lea    0x10(%r11,%rsi,1),%rdi
 164:	44 89 ce             	mov    %r9d,%esi
 167:	40 c0 ee 05          	shr    $0x5,%sil
 16b:	41 80 f9 9f          	cmp    $0x9f,%r9b
 16f:	0f 87 b4 00 00 00    	ja     229 <__libc_free+0x229>
 175:	40 0f b6 f6          	movzbl %sil,%esi
 179:	49 89 f9             	mov    %rdi,%r9
 17c:	49 29 c1             	sub    %rax,%r9
 17f:	49 39 f1             	cmp    %rsi,%r9
 182:	0f 82 00 00 00 00    	jb     188 <__libc_free+0x188>
			184: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 188:	49 89 f9             	mov    %rdi,%r9
 18b:	49 29 f1             	sub    %rsi,%r9
 18e:	41 80 39 00          	cmpb   $0x0,(%r9)
 192:	0f 85 00 00 00 00    	jne    198 <__libc_free+0x198>
			194: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 198:	80 3f 00             	cmpb   $0x0,(%rdi)
 19b:	0f 85 00 00 00 00    	jne    1a1 <__libc_free+0x1a1>
			19d: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 1a1:	be 01 00 00 00       	mov    $0x1,%esi
 1a6:	bf 02 00 00 00       	mov    $0x2,%edi
 1ab:	c6 40 fd ff          	movb   $0xff,-0x3(%rax)
 1af:	d3 e6                	shl    %cl,%esi
 1b1:	44 89 c1             	mov    %r8d,%ecx
 1b4:	d3 e7                	shl    %cl,%edi
 1b6:	31 c9                	xor    %ecx,%ecx
 1b8:	66 89 48 fe          	mov    %cx,-0x2(%rax)
 1bc:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 1c3 <__libc_free+0x1c3>
			1bf: R_X86_64_PC32	__libc-0x1
 1c3:	83 ef 01             	sub    $0x1,%edi
 1c6:	84 c0                	test   %al,%al
 1c8:	75 15                	jne    1df <__libc_free+0x1df>
 1ca:	0f b7 43 20          	movzwl 0x20(%rbx),%eax
 1ce:	66 c1 e8 06          	shr    $0x6,%ax
 1d2:	83 e0 3f             	and    $0x3f,%eax
 1d5:	3c 2f                	cmp    $0x2f,%al
 1d7:	77 06                	ja     1df <__libc_free+0x1df>
 1d9:	48 39 5b 08          	cmp    %rbx,0x8(%rbx)
 1dd:	74 70                	je     24f <__libc_free+0x24f>
 1df:	8b 53 1c             	mov    0x1c(%rbx),%edx
 1e2:	8b 43 18             	mov    0x18(%rbx),%eax
 1e5:	09 d0                	or     %edx,%eax
 1e7:	85 c6                	test   %eax,%esi
 1e9:	0f 85 00 00 00 00    	jne    1ef <__libc_free+0x1ef>
			1eb: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 1ef:	85 d2                	test   %edx,%edx
 1f1:	0f 84 c7 00 00 00    	je     2be <__libc_free+0x2be>
 1f7:	01 f0                	add    %esi,%eax
 1f9:	39 f8                	cmp    %edi,%eax
 1fb:	0f 84 bd 00 00 00    	je     2be <__libc_free+0x2be>
 201:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 208 <__libc_free+0x208>
			204: R_X86_64_PC32	__libc-0x1
 208:	8d 0c 16             	lea    (%rsi,%rdx,1),%ecx
 20b:	84 c0                	test   %al,%al
 20d:	0f 84 a3 00 00 00    	je     2b6 <__libc_free+0x2b6>
 213:	89 d0                	mov    %edx,%eax
 215:	f0 0f b1 4b 1c       	lock cmpxchg %ecx,0x1c(%rbx)
 21a:	39 c2                	cmp    %eax,%edx
 21c:	75 c1                	jne    1df <__libc_free+0x1df>
 21e:	48 83 c4 08          	add    $0x8,%rsp
 222:	5b                   	pop    %rbx
 223:	5d                   	pop    %rbp
 224:	41 5c                	pop    %r12
 226:	41 5d                	pop    %r13
 228:	c3                   	ret
 229:	40 80 fe 05          	cmp    $0x5,%sil
 22d:	0f 85 00 00 00 00    	jne    233 <__libc_free+0x233>
			22f: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 233:	8b 77 fc             	mov    -0x4(%rdi),%esi
 236:	48 83 fe 04          	cmp    $0x4,%rsi
 23a:	0f 86 00 00 00 00    	jbe    240 <__libc_free+0x240>
			23c: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 240:	80 7f fb 00          	cmpb   $0x0,-0x5(%rdi)
 244:	0f 84 2f ff ff ff    	je     179 <__libc_free+0x179>
 24a:	e9 00 00 00 00       	jmp    24f <__libc_free+0x24f>
			24b: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 24f:	83 e0 3f             	and    $0x3f,%eax
 252:	0f b7 84 00 00 00 00 	movzwl 0x0(%rax,%rax,1),%eax
 259:	00 
			256: R_X86_64_32S	__malloc_size_classes
 25a:	c1 e0 04             	shl    $0x4,%eax
 25d:	48 98                	cltq
 25f:	48 39 c2             	cmp    %rax,%rdx
 262:	0f 82 77 ff ff ff    	jb     1df <__libc_free+0x1df>
 268:	48 81 7b 20 ff 0f 00 	cmpq   $0xfff,0x20(%rbx)
 26f:	00 
 270:	76 18                	jbe    28a <__libc_free+0x28a>
 272:	48 8b 43 20          	mov    0x20(%rbx),%rax
 276:	48 25 00 f0 ff ff    	and    $0xfffffffffffff000,%rax
 27c:	48 3d 00 00 02 00    	cmp    $0x20000,%rax
 282:	0f 87 57 ff ff ff    	ja     1df <__libc_free+0x1df>
 288:	eb 1f                	jmp    2a9 <__libc_free+0x2a9>
 28a:	0f b6 43 20          	movzbl 0x20(%rbx),%eax
 28e:	83 e0 1f             	and    $0x1f,%eax
 291:	48 83 c0 01          	add    $0x1,%rax
 295:	48 0f af c2          	imul   %rdx,%rax
 299:	48 83 c0 10          	add    $0x10,%rax
 29d:	48 3d 00 00 02 00    	cmp    $0x20000,%rax
 2a3:	0f 87 36 ff ff ff    	ja     1df <__libc_free+0x1df>
 2a9:	8b 43 1c             	mov    0x1c(%rbx),%eax
 2ac:	09 f0                	or     %esi,%eax
 2ae:	89 43 1c             	mov    %eax,0x1c(%rbx)
 2b1:	e9 68 ff ff ff       	jmp    21e <__libc_free+0x21e>
 2b6:	89 4b 1c             	mov    %ecx,0x1c(%rbx)
 2b9:	e9 60 ff ff ff       	jmp    21e <__libc_free+0x21e>
 2be:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 2c5 <__libc_free+0x2c5>
			2c1: R_X86_64_PC32	__libc-0x1
 2c5:	84 c0                	test   %al,%al
 2c7:	75 42                	jne    30b <__libc_free+0x30b>
 2c9:	89 ee                	mov    %ebp,%esi
 2cb:	48 89 df             	mov    %rbx,%rdi
 2ce:	e8 00 00 00 00       	call   2d3 <__libc_free+0x2d3>
			2cf: R_X86_64_PC32	.text.nontrivial_free-0x4
 2d3:	48 89 c5             	mov    %rax,%rbp
 2d6:	8b 05 00 00 00 00    	mov    0x0(%rip),%eax        # 2dc <__libc_free+0x2dc>
			2d8: R_X86_64_PC32	__malloc_lock-0x4
 2dc:	48 89 d3             	mov    %rdx,%rbx
 2df:	85 c0                	test   %eax,%eax
 2e1:	78 34                	js     317 <__libc_free+0x317>
 2e3:	48 85 db             	test   %rbx,%rbx
 2e6:	0f 84 32 ff ff ff    	je     21e <__libc_free+0x21e>
 2ec:	e8 00 00 00 00       	call   2f1 <__libc_free+0x2f1>
			2ed: R_X86_64_PLT32	___errno_location-0x4
 2f1:	48 89 de             	mov    %rbx,%rsi
 2f4:	48 89 ef             	mov    %rbp,%rdi
 2f7:	44 8b 28             	mov    (%rax),%r13d
 2fa:	49 89 c4             	mov    %rax,%r12
 2fd:	e8 00 00 00 00       	call   302 <__libc_free+0x302>
			2fe: R_X86_64_PLT32	munmap-0x4
 302:	45 89 2c 24          	mov    %r13d,(%r12)
 306:	e9 13 ff ff ff       	jmp    21e <__libc_free+0x21e>
 30b:	bf 00 00 00 00       	mov    $0x0,%edi
			30c: R_X86_64_32	__malloc_lock
 310:	e8 00 00 00 00       	call   315 <__libc_free+0x315>
			311: R_X86_64_PLT32	__lock-0x4
 315:	eb b2                	jmp    2c9 <__libc_free+0x2c9>
 317:	bf 00 00 00 00       	mov    $0x0,%edi
			318: R_X86_64_32	__malloc_lock
 31c:	e8 00 00 00 00       	call   321 <__libc_free+0x321>
			31d: R_X86_64_PLT32	__unlock-0x4
 321:	eb c0                	jmp    2e3 <__libc_free+0x2e3>
 323:	c3                   	ret

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

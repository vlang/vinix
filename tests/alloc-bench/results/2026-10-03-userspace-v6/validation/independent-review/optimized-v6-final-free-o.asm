
/Users/alex/code/vinix/third_party/useralloc-libc/build/useralloc/v6-prototype/cache/x86_64/de81a5feb72ae379cc45ec4a46be7ac78b7342fd74a987fc527187b69fe7fdaa/objects/obj/src/malloc/mallocng/free.o:     file format elf64-x86-64


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
  94:	0f 84 2f 02 00 00    	je     2c9 <free_group+0x2c9>
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
 19d:	48 8b 53 10          	mov    0x10(%rbx),%rdx
 1a1:	f6 c2 0f             	test   $0xf,%dl
 1a4:	0f 85 00 00 00 00    	jne    1aa <free_group+0x1aa>
			1a6: R_X86_64_PC32	.text.unlikely.free_group-0x4
 1aa:	0f b6 72 fd          	movzbl -0x3(%rdx),%esi
 1ae:	0f b7 4a fe          	movzwl -0x2(%rdx),%ecx
 1b2:	41 89 f0             	mov    %esi,%r8d
 1b5:	83 e6 1f             	and    $0x1f,%esi
 1b8:	41 83 e0 1f          	and    $0x1f,%r8d
 1bc:	80 7a fc 00          	cmpb   $0x0,-0x4(%rdx)
 1c0:	74 18                	je     1da <free_group+0x1da>
 1c2:	85 c9                	test   %ecx,%ecx
 1c4:	0f 85 00 00 00 00    	jne    1ca <free_group+0x1ca>
			1c6: R_X86_64_PC32	.text.unlikely.free_group-0x4
 1ca:	48 63 4a f8          	movslq -0x8(%rdx),%rcx
 1ce:	81 f9 ff ff 00 00    	cmp    $0xffff,%ecx
 1d4:	0f 8e 00 00 00 00    	jle    1da <free_group+0x1da>
			1d6: R_X86_64_PC32	.text.unlikely.free_group-0x4
 1da:	89 c8                	mov    %ecx,%eax
 1dc:	48 89 d7             	mov    %rdx,%rdi
 1df:	c1 e0 04             	shl    $0x4,%eax
 1e2:	48 98                	cltq
 1e4:	48 29 c7             	sub    %rax,%rdi
 1e7:	48 8d 47 f0          	lea    -0x10(%rdi),%rax
 1eb:	48 8b 7f f0          	mov    -0x10(%rdi),%rdi
 1ef:	48 3b 47 10          	cmp    0x10(%rdi),%rax
 1f3:	0f 85 00 00 00 00    	jne    1f9 <free_group+0x1f9>
			1f5: R_X86_64_PC32	.text.unlikely.free_group-0x4
 1f9:	0f b6 47 20          	movzbl 0x20(%rdi),%eax
 1fd:	41 89 c1             	mov    %eax,%r9d
 200:	83 e0 1f             	and    $0x1f,%eax
 203:	41 83 e1 1f          	and    $0x1f,%r9d
 207:	39 c6                	cmp    %eax,%esi
 209:	0f 8f 00 00 00 00    	jg     20f <free_group+0x20f>
			20b: R_X86_64_PC32	.text.unlikely.free_group-0x4
 20f:	8b 47 18             	mov    0x18(%rdi),%eax
 212:	44 0f a3 c0          	bt     %r8d,%eax
 216:	0f 82 00 00 00 00    	jb     21c <free_group+0x21c>
			218: R_X86_64_PC32	.text.unlikely.free_group-0x4
 21c:	8b 47 1c             	mov    0x1c(%rdi),%eax
 21f:	44 0f a3 c0          	bt     %r8d,%eax
 223:	0f 82 00 00 00 00    	jb     229 <free_group+0x229>
			225: R_X86_64_PC32	.text.unlikely.free_group-0x4
 229:	48 89 f8             	mov    %rdi,%rax
 22c:	4c 8b 15 00 00 00 00 	mov    0x0(%rip),%r10        # 233 <free_group+0x233>
			22f: R_X86_64_PC32	__malloc_context-0x4
 233:	48 25 00 f0 ff ff    	and    $0xfffffffffffff000,%rax
 239:	4c 39 10             	cmp    %r10,(%rax)
 23c:	0f 85 00 00 00 00    	jne    242 <free_group+0x242>
			23e: R_X86_64_PC32	.text.unlikely.free_group-0x4
 242:	0f b7 47 20          	movzwl 0x20(%rdi),%eax
 246:	66 c1 e8 06          	shr    $0x6,%ax
 24a:	83 e0 3f             	and    $0x3f,%eax
 24d:	83 f8 2f             	cmp    $0x2f,%eax
 250:	7f 56                	jg     2a8 <free_group+0x2a8>
 252:	0f b7 84 00 00 00 00 	movzwl 0x0(%rax,%rax,1),%eax
 259:	00 
			256: R_X86_64_32S	__malloc_size_classes
 25a:	41 89 f0             	mov    %esi,%r8d
 25d:	44 0f af c0          	imul   %eax,%r8d
 261:	44 39 c1             	cmp    %r8d,%ecx
 264:	0f 8c 00 00 00 00    	jl     26a <free_group+0x26a>
			266: R_X86_64_PC32	.text.unlikely.free_group-0x4
 26a:	44 01 c0             	add    %r8d,%eax
 26d:	39 c1                	cmp    %eax,%ecx
 26f:	7d 32                	jge    2a3 <free_group+0x2a3>
 271:	48 8b 47 20          	mov    0x20(%rdi),%rax
 275:	48 c1 e8 0c          	shr    $0xc,%rax
 279:	74 11                	je     28c <free_group+0x28c>
 27b:	48 c1 e0 08          	shl    $0x8,%rax
 27f:	48 83 e8 01          	sub    $0x1,%rax
 283:	48 39 c8             	cmp    %rcx,%rax
 286:	0f 82 00 00 00 00    	jb     28c <free_group+0x28c>
			288: R_X86_64_PC32	.text.unlikely.free_group-0x4
 28c:	48 c7 02 00 00 00 00 	movq   $0x0,(%rdx)
 293:	e8 00 00 00 00       	call   298 <free_group+0x298>
			294: R_X86_64_PC32	.text.nontrivial_free-0x4
 298:	48 89 c7             	mov    %rax,%rdi
 29b:	48 89 d0             	mov    %rdx,%rax
 29e:	e9 d4 fd ff ff       	jmp    77 <free_group+0x77>
 2a3:	e9 00 00 00 00       	jmp    2a8 <free_group+0x2a8>
			2a4: R_X86_64_PC32	.text.unlikely.free_group-0x4
 2a8:	83 f8 3f             	cmp    $0x3f,%eax
 2ab:	0f 85 00 00 00 00    	jne    2b1 <free_group+0x2b1>
			2ad: R_X86_64_PC32	.text.unlikely.free_group-0x4
 2b1:	45 84 c9             	test   %r9b,%r9b
 2b4:	0f 85 00 00 00 00    	jne    2ba <free_group+0x2ba>
			2b6: R_X86_64_PC32	.text.unlikely.free_group-0x4
 2ba:	48 81 7f 20 ff 0f 00 	cmpq   $0xfff,0x20(%rdi)
 2c1:	00 
 2c2:	77 ad                	ja     271 <free_group+0x271>
 2c4:	e9 00 00 00 00       	jmp    2c9 <free_group+0x2c9>
			2c5: R_X86_64_PC32	.text.unlikely.free_group-0x4
 2c9:	66 48 0f 6e c3       	movq   %rbx,%xmm0
 2ce:	66 0f 6c c0          	punpcklqdq %xmm0,%xmm0
 2d2:	0f 11 03             	movups %xmm0,(%rbx)
 2d5:	48 89 1d 00 00 00 00 	mov    %rbx,0x0(%rip)        # 2dc <free_group+0x2dc>
			2d8: R_X86_64_PC32	__malloc_context+0xc
 2dc:	e9 ce fd ff ff       	jmp    af <free_group+0xaf>

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
   3:	0f 84 14 03 00 00    	je     31d <__libc_free+0x31d>
   9:	41 55                	push   %r13
   b:	49 89 f8             	mov    %rdi,%r8
   e:	48 89 f8             	mov    %rdi,%rax
  11:	41 54                	push   %r12
  13:	55                   	push   %rbp
  14:	53                   	push   %rbx
  15:	48 83 ec 08          	sub    $0x8,%rsp
  19:	41 83 e0 0f          	and    $0xf,%r8d
  1d:	0f 85 00 00 00 00    	jne    23 <__libc_free+0x23>
			1f: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
  23:	0f b6 77 fd          	movzbl -0x3(%rdi),%esi
  27:	44 0f b7 5f fe       	movzwl -0x2(%rdi),%r11d
  2c:	89 f1                	mov    %esi,%ecx
  2e:	89 f5                	mov    %esi,%ebp
  30:	83 e1 1f             	and    $0x1f,%ecx
  33:	83 e5 1f             	and    $0x1f,%ebp
  36:	80 7f fc 00          	cmpb   $0x0,-0x4(%rdi)
  3a:	74 1a                	je     56 <__libc_free+0x56>
  3c:	45 85 db             	test   %r11d,%r11d
  3f:	0f 85 00 00 00 00    	jne    45 <__libc_free+0x45>
			41: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
  45:	4c 63 5f f8          	movslq -0x8(%rdi),%r11
  49:	41 81 fb ff ff 00 00 	cmp    $0xffff,%r11d
  50:	0f 8e 00 00 00 00    	jle    56 <__libc_free+0x56>
			52: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
  56:	44 89 da             	mov    %r11d,%edx
  59:	48 89 c7             	mov    %rax,%rdi
  5c:	c1 e2 04             	shl    $0x4,%edx
  5f:	48 63 d2             	movslq %edx,%rdx
  62:	48 29 d7             	sub    %rdx,%rdi
  65:	48 8b 5f f0          	mov    -0x10(%rdi),%rbx
  69:	48 8d 57 f0          	lea    -0x10(%rdi),%rdx
  6d:	4c 8b 53 10          	mov    0x10(%rbx),%r10
  71:	4c 39 d2             	cmp    %r10,%rdx
  74:	0f 85 00 00 00 00    	jne    7a <__libc_free+0x7a>
			76: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
  7a:	0f b6 7b 20          	movzbl 0x20(%rbx),%edi
  7e:	89 fa                	mov    %edi,%edx
  80:	41 89 f9             	mov    %edi,%r9d
  83:	83 e2 1f             	and    $0x1f,%edx
  86:	41 83 e1 1f          	and    $0x1f,%r9d
  8a:	39 d5                	cmp    %edx,%ebp
  8c:	0f 8f 00 00 00 00    	jg     92 <__libc_free+0x92>
			8e: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
  92:	8b 53 18             	mov    0x18(%rbx),%edx
  95:	0f a3 ca             	bt     %ecx,%edx
  98:	0f 82 00 00 00 00    	jb     9e <__libc_free+0x9e>
			9a: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
  9e:	8b 53 1c             	mov    0x1c(%rbx),%edx
  a1:	0f a3 ca             	bt     %ecx,%edx
  a4:	0f 82 00 00 00 00    	jb     aa <__libc_free+0xaa>
			a6: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
  aa:	48 89 da             	mov    %rbx,%rdx
  ad:	4c 8b 2d 00 00 00 00 	mov    0x0(%rip),%r13        # b4 <__libc_free+0xb4>
			b0: R_X86_64_PC32	__malloc_context-0x4
  b4:	48 81 e2 00 f0 ff ff 	and    $0xfffffffffffff000,%rdx
  bb:	4c 39 2a             	cmp    %r13,(%rdx)
  be:	0f 85 00 00 00 00    	jne    c4 <__libc_free+0xc4>
			c0: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
  c4:	0f b7 53 20          	movzwl 0x20(%rbx),%edx
  c8:	66 c1 ea 06          	shr    $0x6,%dx
  cc:	83 e2 3f             	and    $0x3f,%edx
  cf:	83 fa 2f             	cmp    $0x2f,%edx
  d2:	0f 8f 38 01 00 00    	jg     210 <__libc_free+0x210>
  d8:	44 0f b7 84 12 00 00 	movzwl 0x0(%rdx,%rdx,1),%r8d
  df:	00 00 
			dd: R_X86_64_32S	__malloc_size_classes
  e1:	89 ea                	mov    %ebp,%edx
  e3:	41 0f af d0          	imul   %r8d,%edx
  e7:	41 39 d3             	cmp    %edx,%r11d
  ea:	0f 8c 00 00 00 00    	jl     f0 <__libc_free+0xf0>
			ec: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
  f0:	44 01 c2             	add    %r8d,%edx
  f3:	41 39 d3             	cmp    %edx,%r11d
  f6:	0f 8d 00 00 00 00    	jge    fc <__libc_free+0xfc>
			f8: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
  fc:	41 c1 e0 04          	shl    $0x4,%r8d
 100:	4d 63 c0             	movslq %r8d,%r8
 103:	48 8b 53 20          	mov    0x20(%rbx),%rdx
 107:	48 c1 ea 0c          	shr    $0xc,%rdx
 10b:	0f 84 24 01 00 00    	je     235 <__libc_free+0x235>
 111:	49 89 d4             	mov    %rdx,%r12
 114:	48 c1 e2 08          	shl    $0x8,%rdx
 118:	48 83 ea 01          	sub    $0x1,%rdx
 11c:	49 c1 e4 0c          	shl    $0xc,%r12
 120:	4c 39 da             	cmp    %r11,%rdx
 123:	0f 82 00 00 00 00    	jb     129 <__libc_free+0x129>
			125: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 129:	4d 8d 5c 24 f0       	lea    -0x10(%r12),%r11
 12e:	83 e7 1f             	and    $0x1f,%edi
 131:	4d 0f 45 d8          	cmovne %r8,%r11
 135:	0f b6 d1             	movzbl %cl,%edx
 138:	49 0f af d3          	imul   %r11,%rdx
 13c:	49 8d 54 13 fc       	lea    -0x4(%r11,%rdx,1),%rdx
 141:	49 8d 7c 12 10       	lea    0x10(%r10,%rdx,1),%rdi
 146:	89 f2                	mov    %esi,%edx
 148:	c0 ea 05             	shr    $0x5,%dl
 14b:	40 80 fe 9f          	cmp    $0x9f,%sil
 14f:	0f 87 e8 00 00 00    	ja     23d <__libc_free+0x23d>
 155:	0f b6 d2             	movzbl %dl,%edx
 158:	48 89 fe             	mov    %rdi,%rsi
 15b:	48 29 c6             	sub    %rax,%rsi
 15e:	48 39 d6             	cmp    %rdx,%rsi
 161:	0f 82 00 00 00 00    	jb     167 <__libc_free+0x167>
			163: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 167:	48 89 fe             	mov    %rdi,%rsi
 16a:	48 29 d6             	sub    %rdx,%rsi
 16d:	80 3e 00             	cmpb   $0x0,(%rsi)
 170:	0f 85 00 00 00 00    	jne    176 <__libc_free+0x176>
			172: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 176:	80 3f 00             	cmpb   $0x0,(%rdi)
 179:	0f 85 00 00 00 00    	jne    17f <__libc_free+0x17f>
			17b: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 17f:	be 01 00 00 00       	mov    $0x1,%esi
 184:	31 d2                	xor    %edx,%edx
 186:	c6 40 fd ff          	movb   $0xff,-0x3(%rax)
 18a:	bf 02 00 00 00       	mov    $0x2,%edi
 18f:	66 89 50 fe          	mov    %dx,-0x2(%rax)
 193:	d3 e6                	shl    %cl,%esi
 195:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 19c <__libc_free+0x19c>
			198: R_X86_64_PC32	__libc-0x1
 19c:	44 89 c9             	mov    %r9d,%ecx
 19f:	d3 e7                	shl    %cl,%edi
 1a1:	83 ef 01             	sub    $0x1,%edi
 1a4:	84 c0                	test   %al,%al
 1a6:	75 1e                	jne    1c6 <__libc_free+0x1c6>
 1a8:	0f b7 43 20          	movzwl 0x20(%rbx),%eax
 1ac:	66 c1 e8 06          	shr    $0x6,%ax
 1b0:	83 e0 3f             	and    $0x3f,%eax
 1b3:	3c 2f                	cmp    $0x2f,%al
 1b5:	77 0f                	ja     1c6 <__libc_free+0x1c6>
 1b7:	48 39 5b 08          	cmp    %rbx,0x8(%rbx)
 1bb:	75 09                	jne    1c6 <__libc_free+0x1c6>
 1bd:	4d 39 c3             	cmp    %r8,%r11
 1c0:	0f 83 9c 00 00 00    	jae    262 <__libc_free+0x262>
 1c6:	8b 53 1c             	mov    0x1c(%rbx),%edx
 1c9:	8b 43 18             	mov    0x18(%rbx),%eax
 1cc:	09 d0                	or     %edx,%eax
 1ce:	85 c6                	test   %eax,%esi
 1d0:	0f 85 00 00 00 00    	jne    1d6 <__libc_free+0x1d6>
			1d2: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 1d6:	85 d2                	test   %edx,%edx
 1d8:	0f 84 da 00 00 00    	je     2b8 <__libc_free+0x2b8>
 1de:	01 f0                	add    %esi,%eax
 1e0:	39 f8                	cmp    %edi,%eax
 1e2:	0f 84 d0 00 00 00    	je     2b8 <__libc_free+0x2b8>
 1e8:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 1ef <__libc_free+0x1ef>
			1eb: R_X86_64_PC32	__libc-0x1
 1ef:	8d 0c 16             	lea    (%rsi,%rdx,1),%ecx
 1f2:	84 c0                	test   %al,%al
 1f4:	0f 84 b6 00 00 00    	je     2b0 <__libc_free+0x2b0>
 1fa:	89 d0                	mov    %edx,%eax
 1fc:	f0 0f b1 4b 1c       	lock cmpxchg %ecx,0x1c(%rbx)
 201:	39 c2                	cmp    %eax,%edx
 203:	75 c1                	jne    1c6 <__libc_free+0x1c6>
 205:	48 83 c4 08          	add    $0x8,%rsp
 209:	5b                   	pop    %rbx
 20a:	5d                   	pop    %rbp
 20b:	41 5c                	pop    %r12
 20d:	41 5d                	pop    %r13
 20f:	c3                   	ret
 210:	83 fa 3f             	cmp    $0x3f,%edx
 213:	0f 85 00 00 00 00    	jne    219 <__libc_free+0x219>
			215: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 219:	45 84 c9             	test   %r9b,%r9b
 21c:	0f 85 00 00 00 00    	jne    222 <__libc_free+0x222>
			21e: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 222:	48 81 7b 20 ff 0f 00 	cmpq   $0xfff,0x20(%rbx)
 229:	00 
 22a:	0f 87 d3 fe ff ff    	ja     103 <__libc_free+0x103>
 230:	e9 00 00 00 00       	jmp    235 <__libc_free+0x235>
			231: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 235:	4d 89 c3             	mov    %r8,%r11
 238:	e9 f8 fe ff ff       	jmp    135 <__libc_free+0x135>
 23d:	80 fa 05             	cmp    $0x5,%dl
 240:	0f 85 00 00 00 00    	jne    246 <__libc_free+0x246>
			242: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 246:	8b 57 fc             	mov    -0x4(%rdi),%edx
 249:	48 83 fa 04          	cmp    $0x4,%rdx
 24d:	0f 86 00 00 00 00    	jbe    253 <__libc_free+0x253>
			24f: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 253:	80 7f fb 00          	cmpb   $0x0,-0x5(%rdi)
 257:	0f 84 fb fe ff ff    	je     158 <__libc_free+0x158>
 25d:	e9 00 00 00 00       	jmp    262 <__libc_free+0x262>
			25e: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 262:	48 81 7b 20 ff 0f 00 	cmpq   $0xfff,0x20(%rbx)
 269:	00 
 26a:	76 18                	jbe    284 <__libc_free+0x284>
 26c:	48 8b 43 20          	mov    0x20(%rbx),%rax
 270:	48 25 00 f0 ff ff    	and    $0xfffffffffffff000,%rax
 276:	48 3d 00 00 02 00    	cmp    $0x20000,%rax
 27c:	0f 87 44 ff ff ff    	ja     1c6 <__libc_free+0x1c6>
 282:	eb 1f                	jmp    2a3 <__libc_free+0x2a3>
 284:	0f b6 43 20          	movzbl 0x20(%rbx),%eax
 288:	83 e0 1f             	and    $0x1f,%eax
 28b:	48 83 c0 01          	add    $0x1,%rax
 28f:	49 0f af c3          	imul   %r11,%rax
 293:	48 83 c0 10          	add    $0x10,%rax
 297:	48 3d 00 00 02 00    	cmp    $0x20000,%rax
 29d:	0f 87 23 ff ff ff    	ja     1c6 <__libc_free+0x1c6>
 2a3:	8b 43 1c             	mov    0x1c(%rbx),%eax
 2a6:	09 f0                	or     %esi,%eax
 2a8:	89 43 1c             	mov    %eax,0x1c(%rbx)
 2ab:	e9 55 ff ff ff       	jmp    205 <__libc_free+0x205>
 2b0:	89 4b 1c             	mov    %ecx,0x1c(%rbx)
 2b3:	e9 4d ff ff ff       	jmp    205 <__libc_free+0x205>
 2b8:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 2bf <__libc_free+0x2bf>
			2bb: R_X86_64_PC32	__libc-0x1
 2bf:	84 c0                	test   %al,%al
 2c1:	75 42                	jne    305 <__libc_free+0x305>
 2c3:	89 ee                	mov    %ebp,%esi
 2c5:	48 89 df             	mov    %rbx,%rdi
 2c8:	e8 00 00 00 00       	call   2cd <__libc_free+0x2cd>
			2c9: R_X86_64_PC32	.text.nontrivial_free-0x4
 2cd:	48 89 c5             	mov    %rax,%rbp
 2d0:	8b 05 00 00 00 00    	mov    0x0(%rip),%eax        # 2d6 <__libc_free+0x2d6>
			2d2: R_X86_64_PC32	__malloc_lock-0x4
 2d6:	48 89 d3             	mov    %rdx,%rbx
 2d9:	85 c0                	test   %eax,%eax
 2db:	78 34                	js     311 <__libc_free+0x311>
 2dd:	48 85 db             	test   %rbx,%rbx
 2e0:	0f 84 1f ff ff ff    	je     205 <__libc_free+0x205>
 2e6:	e8 00 00 00 00       	call   2eb <__libc_free+0x2eb>
			2e7: R_X86_64_PLT32	___errno_location-0x4
 2eb:	48 89 de             	mov    %rbx,%rsi
 2ee:	48 89 ef             	mov    %rbp,%rdi
 2f1:	44 8b 28             	mov    (%rax),%r13d
 2f4:	49 89 c4             	mov    %rax,%r12
 2f7:	e8 00 00 00 00       	call   2fc <__libc_free+0x2fc>
			2f8: R_X86_64_PLT32	munmap-0x4
 2fc:	45 89 2c 24          	mov    %r13d,(%r12)
 300:	e9 00 ff ff ff       	jmp    205 <__libc_free+0x205>
 305:	bf 00 00 00 00       	mov    $0x0,%edi
			306: R_X86_64_32	__malloc_lock
 30a:	e8 00 00 00 00       	call   30f <__libc_free+0x30f>
			30b: R_X86_64_PLT32	__lock-0x4
 30f:	eb b2                	jmp    2c3 <__libc_free+0x2c3>
 311:	bf 00 00 00 00       	mov    $0x0,%edi
			312: R_X86_64_32	__malloc_lock
 316:	e8 00 00 00 00       	call   31b <__libc_free+0x31b>
			317: R_X86_64_PLT32	__unlock-0x4
 31b:	eb c0                	jmp    2dd <__libc_free+0x2dd>
 31d:	c3                   	ret

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

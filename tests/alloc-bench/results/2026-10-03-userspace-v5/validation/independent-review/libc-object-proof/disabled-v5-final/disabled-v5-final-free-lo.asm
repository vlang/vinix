
/Users/alex/code/vinix/third_party/useralloc-libc/build/musl/x86_64/cd7e18f1889e62892a88526d44f09cb82b303437e0b02e71db4da7b0c79450ca/objects/obj/src/malloc/mallocng/free.lo:     file format elf64-x86-64


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
  42:	74 71                	je     b5 <nontrivial_free+0xb5>
  44:	85 f6                	test   %esi,%esi
  46:	75 50                	jne    98 <nontrivial_free+0x98>
  48:	83 f8 2f             	cmp    $0x2f,%eax
  4b:	0f 8f 00 00 00 00    	jg     51 <nontrivial_free+0x51>
			4d: R_X86_64_PC32	.text.unlikely.nontrivial_free-0x4
  51:	48 8d 0d 00 00 00 00 	lea    0x0(%rip),%rcx        # 58 <nontrivial_free+0x58>
			54: R_X86_64_PC32	__malloc_context-0x4
  58:	48 8d 50 0a          	lea    0xa(%rax),%rdx
  5c:	48 8b 04 d1          	mov    (%rcx,%rdx,8),%rax
  60:	48 39 f8             	cmp    %rdi,%rax
  63:	74 33                	je     98 <nontrivial_free+0x98>
  65:	48 83 7f 08 00       	cmpq   $0x0,0x8(%rdi)
  6a:	0f 85 00 00 00 00    	jne    70 <nontrivial_free+0x70>
			6c: R_X86_64_PC32	.text.unlikely.nontrivial_free-0x4
  70:	48 83 3f 00          	cmpq   $0x0,(%rdi)
  74:	0f 85 00 00 00 00    	jne    7a <nontrivial_free+0x7a>
			76: R_X86_64_PC32	.text.unlikely.nontrivial_free-0x4
  7a:	48 85 c0             	test   %rax,%rax
  7d:	0f 84 f8 01 00 00    	je     27b <nontrivial_free+0x27b>
  83:	48 89 47 08          	mov    %rax,0x8(%rdi)
  87:	48 8b 00             	mov    (%rax),%rax
  8a:	48 89 07             	mov    %rax,(%rdi)
  8d:	48 89 78 08          	mov    %rdi,0x8(%rax)
  91:	48 8b 47 08          	mov    0x8(%rdi),%rax
  95:	48 89 38             	mov    %rdi,(%rax)
  98:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 9f <nontrivial_free+0x9f>
			9b: R_X86_64_PC32	__libc-0x1
  9f:	84 c0                	test   %al,%al
  a1:	0f 85 e9 01 00 00    	jne    290 <nontrivial_free+0x290>
  a7:	8b 47 1c             	mov    0x1c(%rdi),%eax
  aa:	44 09 d0             	or     %r10d,%eax
  ad:	89 47 1c             	mov    %eax,0x1c(%rdi)
  b0:	31 c0                	xor    %eax,%eax
  b2:	31 d2                	xor    %edx,%edx
  b4:	c3                   	ret
  b5:	41 83 e0 20          	and    $0x20,%r8d
  b9:	74 89                	je     44 <nontrivial_free+0x44>
  bb:	48 8b 57 08          	mov    0x8(%rdi),%rdx
  bf:	83 f8 2f             	cmp    $0x2f,%eax
  c2:	0f 8f 2d 01 00 00    	jg     1f5 <nontrivial_free+0x1f5>
  c8:	4c 8b 47 20          	mov    0x20(%rdi),%r8
  cc:	84 c9                	test   %cl,%cl
  ce:	75 7a                	jne    14a <nontrivial_free+0x14a>
  d0:	49 81 f8 ff 0f 00 00 	cmp    $0xfff,%r8
  d7:	0f 86 07 01 00 00    	jbe    1e4 <nontrivial_free+0x1e4>
  dd:	48 63 c8             	movslq %eax,%rcx
  e0:	4c 8d 0d 00 00 00 00 	lea    0x0(%rip),%r9        # e7 <nontrivial_free+0xe7>
			e3: R_X86_64_PC32	__malloc_size_classes-0x4
  e7:	49 81 e0 00 f0 ff ff 	and    $0xfffffffffffff000,%r8
  ee:	45 0f b7 0c 49       	movzwl (%r9,%rcx,2),%r9d
  f3:	49 83 e8 10          	sub    $0x10,%r8
  f7:	41 c1 e1 04          	shl    $0x4,%r9d
  fb:	4d 63 c9             	movslq %r9d,%r9
  fe:	4d 39 c8             	cmp    %r9,%r8
 101:	73 54                	jae    157 <nontrivial_free+0x157>
 103:	48 85 d2             	test   %rdx,%rdx
 106:	74 3d                	je     145 <nontrivial_free+0x145>
 108:	4c 8d 05 00 00 00 00 	lea    0x0(%rip),%r8        # 10f <nontrivial_free+0x10f>
			10b: R_X86_64_PC32	__malloc_context-0x4
 10f:	49 8b 44 c8 50       	mov    0x50(%r8,%rcx,8),%rax
 114:	48 39 d7             	cmp    %rdx,%rdi
 117:	74 70                	je     189 <nontrivial_free+0x189>
 119:	48 8b 37             	mov    (%rdi),%rsi
 11c:	48 89 56 08          	mov    %rdx,0x8(%rsi)
 120:	48 8b 37             	mov    (%rdi),%rsi
 123:	48 89 32             	mov    %rsi,(%rdx)
 126:	48 8d 51 0a          	lea    0xa(%rcx),%rdx
 12a:	49 3b 7c c8 50       	cmp    0x50(%r8,%rcx,8),%rdi
 12f:	0f 84 ce 00 00 00    	je     203 <nontrivial_free+0x203>
 135:	66 0f ef c0          	pxor   %xmm0,%xmm0
 139:	0f 11 07             	movups %xmm0,(%rdi)
 13c:	48 39 c7             	cmp    %rax,%rdi
 13f:	0f 84 cb 00 00 00    	je     210 <nontrivial_free+0x210>
 145:	e9 00 00 00 00       	jmp    14a <nontrivial_free+0x14a>
			146: R_X86_64_PC32	.text.free_group-0x4
 14a:	49 81 f8 ff 0f 00 00 	cmp    $0xfff,%r8
 151:	0f 86 8d 00 00 00    	jbe    1e4 <nontrivial_free+0x1e4>
 157:	48 39 d7             	cmp    %rdx,%rdi
 15a:	74 16                	je     172 <nontrivial_free+0x172>
 15c:	48 85 d2             	test   %rdx,%rdx
 15f:	74 e4                	je     145 <nontrivial_free+0x145>
 161:	4c 8d 05 00 00 00 00 	lea    0x0(%rip),%r8        # 168 <nontrivial_free+0x168>
			164: R_X86_64_PC32	__malloc_context-0x4
 168:	48 63 c8             	movslq %eax,%rcx
 16b:	49 8b 44 c8 50       	mov    0x50(%r8,%rcx,8),%rax
 170:	eb a7                	jmp    119 <nontrivial_free+0x119>
 172:	8d 48 f9             	lea    -0x7(%rax),%ecx
 175:	83 f9 1f             	cmp    $0x1f,%ecx
 178:	76 1a                	jbe    194 <nontrivial_free+0x194>
 17a:	48 63 c8             	movslq %eax,%rcx
 17d:	4c 8d 05 00 00 00 00 	lea    0x0(%rip),%r8        # 184 <nontrivial_free+0x184>
			180: R_X86_64_PC32	__malloc_context-0x4
 184:	49 8b 44 c8 50       	mov    0x50(%r8,%rcx,8),%rax
 189:	49 c7 44 c8 50 00 00 	movq   $0x0,0x50(%r8,%rcx,8)
 190:	00 00 
 192:	eb a1                	jmp    135 <nontrivial_free+0x135>
 194:	4c 8d 05 00 00 00 00 	lea    0x0(%rip),%r8        # 19b <nontrivial_free+0x19b>
			197: R_X86_64_PC32	__malloc_context-0x4
 19b:	48 63 c9             	movslq %ecx,%rcx
 19e:	41 80 bc 08 98 03 00 	cmpb   $0x63,0x398(%r8,%rcx,1)
 1a5:	00 63 
 1a7:	77 05                	ja     1ae <nontrivial_free+0x1ae>
 1a9:	48 63 c8             	movslq %eax,%rcx
 1ac:	eb d6                	jmp    184 <nontrivial_free+0x184>
 1ae:	41 83 c3 01          	add    $0x1,%r11d
 1b2:	48 63 c8             	movslq %eax,%rcx
 1b5:	49 63 c3             	movslq %r11d,%rax
 1b8:	48 8d 04 c0          	lea    (%rax,%rax,8),%rax
 1bc:	49 39 84 c8 f8 01 00 	cmp    %rax,0x1f8(%r8,%rcx,8)
 1c3:	00 
 1c4:	72 06                	jb     1cc <nontrivial_free+0x1cc>
 1c6:	41 83 fb 13          	cmp    $0x13,%r11d
 1ca:	7e b8                	jle    184 <nontrivial_free+0x184>
 1cc:	85 f6                	test   %esi,%esi
 1ce:	0f 85 c4 fe ff ff    	jne    98 <nontrivial_free+0x98>
 1d4:	49 39 54 c8 50       	cmp    %rdx,0x50(%r8,%rcx,8)
 1d9:	0f 84 b9 fe ff ff    	je     98 <nontrivial_free+0x98>
 1df:	e9 00 00 00 00       	jmp    1e4 <nontrivial_free+0x1e4>
			1e0: R_X86_64_PC32	.text.unlikely.nontrivial_free-0x4
 1e4:	48 63 c8             	movslq %eax,%rcx
 1e7:	48 85 d2             	test   %rdx,%rdx
 1ea:	0f 85 18 ff ff ff    	jne    108 <nontrivial_free+0x108>
 1f0:	e9 50 ff ff ff       	jmp    145 <nontrivial_free+0x145>
 1f5:	48 85 d2             	test   %rdx,%rdx
 1f8:	0f 85 00 00 00 00    	jne    1fe <nontrivial_free+0x1fe>
			1fa: R_X86_64_PC32	.text.unlikely.nontrivial_free-0x4
 1fe:	e9 42 ff ff ff       	jmp    145 <nontrivial_free+0x145>
 203:	48 8b 77 08          	mov    0x8(%rdi),%rsi
 207:	49 89 34 d0          	mov    %rsi,(%r8,%rdx,8)
 20b:	e9 25 ff ff ff       	jmp    135 <nontrivial_free+0x135>
 210:	49 8b 74 c8 50       	mov    0x50(%r8,%rcx,8),%rsi
 215:	48 85 f6             	test   %rsi,%rsi
 218:	0f 84 27 ff ff ff    	je     145 <nontrivial_free+0x145>
 21e:	8b 46 18             	mov    0x18(%rsi),%eax
 221:	85 c0                	test   %eax,%eax
 223:	0f 85 00 00 00 00    	jne    229 <nontrivial_free+0x229>
			225: R_X86_64_PC32	.text.unlikely.nontrivial_free-0x4
 229:	48 8b 46 10          	mov    0x10(%rsi),%rax
 22d:	41 b8 02 00 00 00    	mov    $0x2,%r8d
 233:	4c 8d 4e 1c          	lea    0x1c(%rsi),%r9
 237:	0f b6 48 08          	movzbl 0x8(%rax),%ecx
 23b:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 242 <nontrivial_free+0x242>
			23e: R_X86_64_PC32	__libc-0x1
 242:	41 d3 e0             	shl    %cl,%r8d
 245:	45 8d 50 ff          	lea    -0x1(%r8),%r10d
 249:	41 f7 d8             	neg    %r8d
 24c:	84 c0                	test   %al,%al
 24e:	75 16                	jne    266 <nontrivial_free+0x266>
 250:	8b 56 1c             	mov    0x1c(%rsi),%edx
 253:	41 21 d0             	and    %edx,%r8d
 256:	44 89 46 1c          	mov    %r8d,0x1c(%rsi)
 25a:	41 21 d2             	and    %edx,%r10d
 25d:	44 89 56 18          	mov    %r10d,0x18(%rsi)
 261:	e9 df fe ff ff       	jmp    145 <nontrivial_free+0x145>
 266:	8b 56 1c             	mov    0x1c(%rsi),%edx
 269:	44 89 c1             	mov    %r8d,%ecx
 26c:	21 d1                	and    %edx,%ecx
 26e:	89 d0                	mov    %edx,%eax
 270:	f0 41 0f b1 09       	lock cmpxchg %ecx,(%r9)
 275:	39 c2                	cmp    %eax,%edx
 277:	75 ed                	jne    266 <nontrivial_free+0x266>
 279:	eb df                	jmp    25a <nontrivial_free+0x25a>
 27b:	66 48 0f 6e c7       	movq   %rdi,%xmm0
 280:	66 0f 6c c0          	punpcklqdq %xmm0,%xmm0
 284:	0f 11 07             	movups %xmm0,(%rdi)
 287:	48 89 3c d1          	mov    %rdi,(%rcx,%rdx,8)
 28b:	e9 08 fe ff ff       	jmp    98 <nontrivial_free+0x98>
 290:	f0 44 09 57 1c       	lock or %r10d,0x1c(%rdi)
 295:	e9 16 fe ff ff       	jmp    b0 <nontrivial_free+0xb0>

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
  12:	0f 8e 88 00 00 00    	jle    a0 <free_group+0xa0>
  18:	48 81 7b 20 ff 0f 00 	cmpq   $0xfff,0x20(%rbx)
  1f:	00 
  20:	0f 86 c4 00 00 00    	jbe    ea <free_group+0xea>
  26:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 2d <free_group+0x2d>
			29: R_X86_64_PC32	__malloc_context+0x3b4
  2d:	8d 48 01             	lea    0x1(%rax),%ecx
  30:	3c ff                	cmp    $0xff,%al
  32:	0f 84 89 00 00 00    	je     c1 <free_group+0xc1>
  38:	83 ea 07             	sub    $0x7,%edx
  3b:	88 0d 00 00 00 00    	mov    %cl,0x0(%rip)        # 41 <free_group+0x41>
			3d: R_X86_64_PC32	__malloc_context+0x3b4
  41:	83 fa 1f             	cmp    $0x1f,%edx
  44:	77 11                	ja     57 <free_group+0x57>
  46:	48 63 d2             	movslq %edx,%rdx
  49:	48 8d 05 00 00 00 00 	lea    0x0(%rip),%rax        # 50 <free_group+0x50>
			4c: R_X86_64_PC32	__malloc_context-0x4
  50:	88 8c 10 78 03 00 00 	mov    %cl,0x378(%rax,%rdx,1)
  57:	48 8b 53 20          	mov    0x20(%rbx),%rdx
  5b:	48 8b 43 10          	mov    0x10(%rbx),%rax
  5f:	48 81 e2 00 f0 ff ff 	and    $0xfffffffffffff000,%rdx
  66:	66 0f ef c0          	pxor   %xmm0,%xmm0
  6a:	48 c7 43 20 00 00 00 	movq   $0x0,0x20(%rbx)
  71:	00 
  72:	0f 11 03             	movups %xmm0,(%rbx)
  75:	0f 11 43 10          	movups %xmm0,0x10(%rbx)
  79:	48 8b 0d 00 00 00 00 	mov    0x0(%rip),%rcx        # 80 <free_group+0x80>
			7c: R_X86_64_PC32	__malloc_context+0xc
  80:	48 85 c9             	test   %rcx,%rcx
  83:	0f 84 86 01 00 00    	je     20f <free_group+0x20f>
  89:	48 89 4b 08          	mov    %rcx,0x8(%rbx)
  8d:	48 8b 09             	mov    (%rcx),%rcx
  90:	48 89 0b             	mov    %rcx,(%rbx)
  93:	48 89 59 08          	mov    %rbx,0x8(%rcx)
  97:	48 8b 4b 08          	mov    0x8(%rbx),%rcx
  9b:	48 89 19             	mov    %rbx,(%rcx)
  9e:	5b                   	pop    %rbx
  9f:	c3                   	ret
  a0:	0f b6 47 20          	movzbl 0x20(%rdi),%eax
  a4:	48 8d 35 00 00 00 00 	lea    0x0(%rip),%rsi        # ab <free_group+0xab>
			a7: R_X86_64_PC32	__malloc_context-0x4
  ab:	48 63 ca             	movslq %edx,%rcx
  ae:	83 e0 1f             	and    $0x1f,%eax
  b1:	48 f7 d0             	not    %rax
  b4:	48 01 84 ce f8 01 00 	add    %rax,0x1f8(%rsi,%rcx,8)
  bb:	00 
  bc:	e9 57 ff ff ff       	jmp    18 <free_group+0x18>
  c1:	48 8d 05 00 00 00 00 	lea    0x0(%rip),%rax        # c8 <free_group+0xc8>
			c4: R_X86_64_PC32	__malloc_context+0x374
  c8:	48 8d 48 20          	lea    0x20(%rax),%rcx
  cc:	eb 0d                	jmp    db <free_group+0xdb>
  ce:	66 90                	xchg   %ax,%ax
  d0:	c6 00 00             	movb   $0x0,(%rax)
  d3:	48 83 c0 02          	add    $0x2,%rax
  d7:	c6 40 ff 00          	movb   $0x0,-0x1(%rax)
  db:	48 39 c8             	cmp    %rcx,%rax
  de:	75 f0                	jne    d0 <free_group+0xd0>
  e0:	b9 01 00 00 00       	mov    $0x1,%ecx
  e5:	e9 4e ff ff ff       	jmp    38 <free_group+0x38>
  ea:	48 8b 43 10          	mov    0x10(%rbx),%rax
  ee:	a8 0f                	test   $0xf,%al
  f0:	0f 85 00 00 00 00    	jne    f6 <free_group+0xf6>
			f2: R_X86_64_PC32	.text.unlikely.free_group-0x4
  f6:	0f b6 70 fd          	movzbl -0x3(%rax),%esi
  fa:	0f b7 50 fe          	movzwl -0x2(%rax),%edx
  fe:	41 89 f0             	mov    %esi,%r8d
 101:	83 e6 1f             	and    $0x1f,%esi
 104:	41 83 e0 1f          	and    $0x1f,%r8d
 108:	80 78 fc 00          	cmpb   $0x0,-0x4(%rax)
 10c:	74 18                	je     126 <free_group+0x126>
 10e:	85 d2                	test   %edx,%edx
 110:	0f 85 00 00 00 00    	jne    116 <free_group+0x116>
			112: R_X86_64_PC32	.text.unlikely.free_group-0x4
 116:	48 63 50 f8          	movslq -0x8(%rax),%rdx
 11a:	81 fa ff ff 00 00    	cmp    $0xffff,%edx
 120:	0f 8e 00 00 00 00    	jle    126 <free_group+0x126>
			122: R_X86_64_PC32	.text.unlikely.free_group-0x4
 126:	89 d1                	mov    %edx,%ecx
 128:	48 89 c7             	mov    %rax,%rdi
 12b:	c1 e1 04             	shl    $0x4,%ecx
 12e:	48 63 c9             	movslq %ecx,%rcx
 131:	48 29 cf             	sub    %rcx,%rdi
 134:	48 8d 4f f0          	lea    -0x10(%rdi),%rcx
 138:	48 8b 7f f0          	mov    -0x10(%rdi),%rdi
 13c:	48 3b 4f 10          	cmp    0x10(%rdi),%rcx
 140:	0f 85 00 00 00 00    	jne    146 <free_group+0x146>
			142: R_X86_64_PC32	.text.unlikely.free_group-0x4
 146:	0f b6 4f 20          	movzbl 0x20(%rdi),%ecx
 14a:	83 e1 1f             	and    $0x1f,%ecx
 14d:	39 ce                	cmp    %ecx,%esi
 14f:	0f 8f 00 00 00 00    	jg     155 <free_group+0x155>
			151: R_X86_64_PC32	.text.unlikely.free_group-0x4
 155:	8b 4f 18             	mov    0x18(%rdi),%ecx
 158:	44 0f a3 c1          	bt     %r8d,%ecx
 15c:	0f 82 00 00 00 00    	jb     162 <free_group+0x162>
			15e: R_X86_64_PC32	.text.unlikely.free_group-0x4
 162:	8b 4f 1c             	mov    0x1c(%rdi),%ecx
 165:	44 0f a3 c1          	bt     %r8d,%ecx
 169:	0f 82 00 00 00 00    	jb     16f <free_group+0x16f>
			16b: R_X86_64_PC32	.text.unlikely.free_group-0x4
 16f:	48 89 f9             	mov    %rdi,%rcx
 172:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # 179 <free_group+0x179>
			175: R_X86_64_PC32	__malloc_context-0x4
 179:	48 81 e1 00 f0 ff ff 	and    $0xfffffffffffff000,%rcx
 180:	4c 39 09             	cmp    %r9,(%rcx)
 183:	0f 85 00 00 00 00    	jne    189 <free_group+0x189>
			185: R_X86_64_PC32	.text.unlikely.free_group-0x4
 189:	44 0f b7 47 20       	movzwl 0x20(%rdi),%r8d
 18e:	44 89 c1             	mov    %r8d,%ecx
 191:	66 c1 e9 06          	shr    $0x6,%cx
 195:	83 e1 3f             	and    $0x3f,%ecx
 198:	80 f9 2f             	cmp    $0x2f,%cl
 19b:	77 62                	ja     1ff <free_group+0x1ff>
 19d:	4c 8d 05 00 00 00 00 	lea    0x0(%rip),%r8        # 1a4 <free_group+0x1a4>
			1a0: R_X86_64_PC32	__malloc_size_classes-0x4
 1a4:	83 e1 3f             	and    $0x3f,%ecx
 1a7:	41 0f b7 0c 48       	movzwl (%r8,%rcx,2),%ecx
 1ac:	41 89 f0             	mov    %esi,%r8d
 1af:	44 0f af c1          	imul   %ecx,%r8d
 1b3:	44 39 c2             	cmp    %r8d,%edx
 1b6:	0f 8c 00 00 00 00    	jl     1bc <free_group+0x1bc>
			1b8: R_X86_64_PC32	.text.unlikely.free_group-0x4
 1bc:	44 01 c1             	add    %r8d,%ecx
 1bf:	39 ca                	cmp    %ecx,%edx
 1c1:	7d 37                	jge    1fa <free_group+0x1fa>
 1c3:	48 81 7f 20 ff 0f 00 	cmpq   $0xfff,0x20(%rdi)
 1ca:	00 
 1cb:	76 1c                	jbe    1e9 <free_group+0x1e9>
 1cd:	48 8b 4f 20          	mov    0x20(%rdi),%rcx
 1d1:	48 81 e1 00 f0 ff ff 	and    $0xfffffffffffff000,%rcx
 1d8:	48 c1 e9 04          	shr    $0x4,%rcx
 1dc:	48 83 e9 01          	sub    $0x1,%rcx
 1e0:	48 39 d1             	cmp    %rdx,%rcx
 1e3:	0f 82 00 00 00 00    	jb     1e9 <free_group+0x1e9>
			1e5: R_X86_64_PC32	.text.unlikely.free_group-0x4
 1e9:	48 c7 00 00 00 00 00 	movq   $0x0,(%rax)
 1f0:	e8 00 00 00 00       	call   1f5 <free_group+0x1f5>
			1f1: R_X86_64_PC32	.text.nontrivial_free-0x4
 1f5:	e9 6c fe ff ff       	jmp    66 <free_group+0x66>
 1fa:	e9 00 00 00 00       	jmp    1ff <free_group+0x1ff>
			1fb: R_X86_64_PC32	.text.unlikely.free_group-0x4
 1ff:	41 f7 d0             	not    %r8d
 202:	66 41 f7 c0 c0 0f    	test   $0xfc0,%r8w
 208:	74 b9                	je     1c3 <free_group+0x1c3>
 20a:	e9 00 00 00 00       	jmp    20f <free_group+0x20f>
			20b: R_X86_64_PC32	.text.unlikely.free_group-0x4
 20f:	66 48 0f 6e c3       	movq   %rbx,%xmm0
 214:	66 0f 6c c0          	punpcklqdq %xmm0,%xmm0
 218:	0f 11 03             	movups %xmm0,(%rbx)
 21b:	48 89 1d 00 00 00 00 	mov    %rbx,0x0(%rip)        # 222 <free_group+0x222>
			21e: R_X86_64_PC32	__malloc_context+0xc
 222:	e9 77 fe ff ff       	jmp    9e <free_group+0x9e>

Disassembly of section .text.unlikely.__libc_free:

0000000000000000 <__libc_free.cold>:
   0:	0f 0b                	ud2

Disassembly of section .text.__libc_free:

0000000000000000 <__libc_free>:
   0:	48 85 ff             	test   %rdi,%rdi
   3:	0f 84 85 02 00 00    	je     28e <__libc_free+0x28e>
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
 128:	41 83 e3 1f          	and    $0x1f,%r11d
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
 162:	48 8d 54 32 fc       	lea    -0x4(%rdx,%rsi,1),%rdx
 167:	49 8d 74 12 10       	lea    0x10(%r10,%rdx,1),%rsi
 16c:	44 89 ca             	mov    %r9d,%edx
 16f:	c0 ea 05             	shr    $0x5,%dl
 172:	41 80 f9 9f          	cmp    $0x9f,%r9b
 176:	0f 87 86 00 00 00    	ja     202 <__libc_free+0x202>
 17c:	0f b6 d2             	movzbl %dl,%edx
 17f:	48 89 f7             	mov    %rsi,%rdi
 182:	48 29 c7             	sub    %rax,%rdi
 185:	48 39 d7             	cmp    %rdx,%rdi
 188:	0f 82 00 00 00 00    	jb     18e <__libc_free+0x18e>
			18a: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 18e:	48 89 f7             	mov    %rsi,%rdi
 191:	48 29 d7             	sub    %rdx,%rdi
 194:	80 3f 00             	cmpb   $0x0,(%rdi)
 197:	0f 85 00 00 00 00    	jne    19d <__libc_free+0x19d>
			199: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 19d:	80 3e 00             	cmpb   $0x0,(%rsi)
 1a0:	0f 85 00 00 00 00    	jne    1a6 <__libc_free+0x1a6>
			1a2: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 1a6:	be 01 00 00 00       	mov    $0x1,%esi
 1ab:	31 d2                	xor    %edx,%edx
 1ad:	bf 02 00 00 00       	mov    $0x2,%edi
 1b2:	c6 40 fd ff          	movb   $0xff,-0x3(%rax)
 1b6:	d3 e6                	shl    %cl,%esi
 1b8:	66 89 50 fe          	mov    %dx,-0x2(%rax)
 1bc:	44 89 c1             	mov    %r8d,%ecx
 1bf:	d3 e7                	shl    %cl,%edi
 1c1:	83 ef 01             	sub    $0x1,%edi
 1c4:	8b 53 1c             	mov    0x1c(%rbx),%edx
 1c7:	8b 43 18             	mov    0x18(%rbx),%eax
 1ca:	09 d0                	or     %edx,%eax
 1cc:	85 c6                	test   %eax,%esi
 1ce:	0f 85 00 00 00 00    	jne    1d4 <__libc_free+0x1d4>
			1d0: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 1d4:	85 d2                	test   %edx,%edx
 1d6:	74 54                	je     22c <__libc_free+0x22c>
 1d8:	01 f0                	add    %esi,%eax
 1da:	39 f8                	cmp    %edi,%eax
 1dc:	74 4e                	je     22c <__libc_free+0x22c>
 1de:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 1e5 <__libc_free+0x1e5>
			1e1: R_X86_64_PC32	__libc-0x1
 1e5:	8d 0c 16             	lea    (%rsi,%rdx,1),%ecx
 1e8:	84 c0                	test   %al,%al
 1ea:	74 3b                	je     227 <__libc_free+0x227>
 1ec:	89 d0                	mov    %edx,%eax
 1ee:	f0 0f b1 4b 1c       	lock cmpxchg %ecx,0x1c(%rbx)
 1f3:	39 c2                	cmp    %eax,%edx
 1f5:	75 cd                	jne    1c4 <__libc_free+0x1c4>
 1f7:	48 83 c4 08          	add    $0x8,%rsp
 1fb:	5b                   	pop    %rbx
 1fc:	5d                   	pop    %rbp
 1fd:	41 5c                	pop    %r12
 1ff:	41 5d                	pop    %r13
 201:	c3                   	ret
 202:	80 fa 05             	cmp    $0x5,%dl
 205:	0f 85 00 00 00 00    	jne    20b <__libc_free+0x20b>
			207: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 20b:	8b 56 fc             	mov    -0x4(%rsi),%edx
 20e:	48 83 fa 04          	cmp    $0x4,%rdx
 212:	0f 86 00 00 00 00    	jbe    218 <__libc_free+0x218>
			214: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 218:	80 7e fb 00          	cmpb   $0x0,-0x5(%rsi)
 21c:	0f 84 5d ff ff ff    	je     17f <__libc_free+0x17f>
 222:	e9 00 00 00 00       	jmp    227 <__libc_free+0x227>
			223: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 227:	89 4b 1c             	mov    %ecx,0x1c(%rbx)
 22a:	eb cb                	jmp    1f7 <__libc_free+0x1f7>
 22c:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 233 <__libc_free+0x233>
			22f: R_X86_64_PC32	__libc-0x1
 233:	84 c0                	test   %al,%al
 235:	75 3b                	jne    272 <__libc_free+0x272>
 237:	89 ee                	mov    %ebp,%esi
 239:	48 89 df             	mov    %rbx,%rdi
 23c:	e8 00 00 00 00       	call   241 <__libc_free+0x241>
			23d: R_X86_64_PC32	.text.nontrivial_free-0x4
 241:	48 89 c5             	mov    %rax,%rbp
 244:	8b 05 00 00 00 00    	mov    0x0(%rip),%eax        # 24a <__libc_free+0x24a>
			246: R_X86_64_PC32	__malloc_lock-0x4
 24a:	48 89 d3             	mov    %rdx,%rbx
 24d:	85 c0                	test   %eax,%eax
 24f:	78 2f                	js     280 <__libc_free+0x280>
 251:	48 85 db             	test   %rbx,%rbx
 254:	74 a1                	je     1f7 <__libc_free+0x1f7>
 256:	e8 00 00 00 00       	call   25b <__libc_free+0x25b>
			257: R_X86_64_PLT32	___errno_location-0x4
 25b:	48 89 de             	mov    %rbx,%rsi
 25e:	48 89 ef             	mov    %rbp,%rdi
 261:	44 8b 28             	mov    (%rax),%r13d
 264:	49 89 c4             	mov    %rax,%r12
 267:	e8 00 00 00 00       	call   26c <__libc_free+0x26c>
			268: R_X86_64_PLT32	munmap-0x4
 26c:	45 89 2c 24          	mov    %r13d,(%r12)
 270:	eb 85                	jmp    1f7 <__libc_free+0x1f7>
 272:	48 8d 3d 00 00 00 00 	lea    0x0(%rip),%rdi        # 279 <__libc_free+0x279>
			275: R_X86_64_PC32	__malloc_lock-0x4
 279:	e8 00 00 00 00       	call   27e <__libc_free+0x27e>
			27a: R_X86_64_PLT32	__lock-0x4
 27e:	eb b7                	jmp    237 <__libc_free+0x237>
 280:	48 8d 3d 00 00 00 00 	lea    0x0(%rip),%rdi        # 287 <__libc_free+0x287>
			283: R_X86_64_PC32	__malloc_lock-0x4
 287:	e8 00 00 00 00       	call   28c <__libc_free+0x28c>
			288: R_X86_64_PLT32	__unlock-0x4
 28c:	eb c3                	jmp    251 <__libc_free+0x251>
 28e:	c3                   	ret

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

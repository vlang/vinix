
/Users/alex/code/vinix/third_party/useralloc-libc/build/useralloc/v6-prototype/cache/x86_64/e2aafe45791c748b1a101bcb8e017566e835e6f27fd623513503e67ee426bd6e/objects/obj/src/malloc/mallocng/free.lo:     file format elf64-x86-64


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
  83:	0f 84 8b 01 00 00    	je     214 <free_group+0x214>
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
  ea:	48 8b 53 10          	mov    0x10(%rbx),%rdx
  ee:	f6 c2 0f             	test   $0xf,%dl
  f1:	0f 85 00 00 00 00    	jne    f7 <free_group+0xf7>
			f3: R_X86_64_PC32	.text.unlikely.free_group-0x4
  f7:	0f b6 72 fd          	movzbl -0x3(%rdx),%esi
  fb:	0f b7 4a fe          	movzwl -0x2(%rdx),%ecx
  ff:	41 89 f0             	mov    %esi,%r8d
 102:	83 e6 1f             	and    $0x1f,%esi
 105:	41 83 e0 1f          	and    $0x1f,%r8d
 109:	80 7a fc 00          	cmpb   $0x0,-0x4(%rdx)
 10d:	74 18                	je     127 <free_group+0x127>
 10f:	85 c9                	test   %ecx,%ecx
 111:	0f 85 00 00 00 00    	jne    117 <free_group+0x117>
			113: R_X86_64_PC32	.text.unlikely.free_group-0x4
 117:	48 63 4a f8          	movslq -0x8(%rdx),%rcx
 11b:	81 f9 ff ff 00 00    	cmp    $0xffff,%ecx
 121:	0f 8e 00 00 00 00    	jle    127 <free_group+0x127>
			123: R_X86_64_PC32	.text.unlikely.free_group-0x4
 127:	89 c8                	mov    %ecx,%eax
 129:	48 89 d7             	mov    %rdx,%rdi
 12c:	c1 e0 04             	shl    $0x4,%eax
 12f:	48 98                	cltq
 131:	48 29 c7             	sub    %rax,%rdi
 134:	48 8d 47 f0          	lea    -0x10(%rdi),%rax
 138:	48 8b 7f f0          	mov    -0x10(%rdi),%rdi
 13c:	48 3b 47 10          	cmp    0x10(%rdi),%rax
 140:	0f 85 00 00 00 00    	jne    146 <free_group+0x146>
			142: R_X86_64_PC32	.text.unlikely.free_group-0x4
 146:	0f b6 47 20          	movzbl 0x20(%rdi),%eax
 14a:	41 89 c1             	mov    %eax,%r9d
 14d:	83 e0 1f             	and    $0x1f,%eax
 150:	41 83 e1 1f          	and    $0x1f,%r9d
 154:	39 c6                	cmp    %eax,%esi
 156:	0f 8f 00 00 00 00    	jg     15c <free_group+0x15c>
			158: R_X86_64_PC32	.text.unlikely.free_group-0x4
 15c:	8b 47 18             	mov    0x18(%rdi),%eax
 15f:	44 0f a3 c0          	bt     %r8d,%eax
 163:	0f 82 00 00 00 00    	jb     169 <free_group+0x169>
			165: R_X86_64_PC32	.text.unlikely.free_group-0x4
 169:	8b 47 1c             	mov    0x1c(%rdi),%eax
 16c:	44 0f a3 c0          	bt     %r8d,%eax
 170:	0f 82 00 00 00 00    	jb     176 <free_group+0x176>
			172: R_X86_64_PC32	.text.unlikely.free_group-0x4
 176:	48 89 f8             	mov    %rdi,%rax
 179:	4c 8b 15 00 00 00 00 	mov    0x0(%rip),%r10        # 180 <free_group+0x180>
			17c: R_X86_64_PC32	__malloc_context-0x4
 180:	48 25 00 f0 ff ff    	and    $0xfffffffffffff000,%rax
 186:	4c 39 10             	cmp    %r10,(%rax)
 189:	0f 85 00 00 00 00    	jne    18f <free_group+0x18f>
			18b: R_X86_64_PC32	.text.unlikely.free_group-0x4
 18f:	0f b7 47 20          	movzwl 0x20(%rdi),%eax
 193:	66 c1 e8 06          	shr    $0x6,%ax
 197:	83 e0 3f             	and    $0x3f,%eax
 19a:	83 f8 2f             	cmp    $0x2f,%eax
 19d:	7f 54                	jg     1f3 <free_group+0x1f3>
 19f:	4c 8d 05 00 00 00 00 	lea    0x0(%rip),%r8        # 1a6 <free_group+0x1a6>
			1a2: R_X86_64_PC32	__malloc_size_classes-0x4
 1a6:	41 0f b7 04 40       	movzwl (%r8,%rax,2),%eax
 1ab:	41 89 f0             	mov    %esi,%r8d
 1ae:	44 0f af c0          	imul   %eax,%r8d
 1b2:	44 39 c1             	cmp    %r8d,%ecx
 1b5:	0f 8c 00 00 00 00    	jl     1bb <free_group+0x1bb>
			1b7: R_X86_64_PC32	.text.unlikely.free_group-0x4
 1bb:	44 01 c0             	add    %r8d,%eax
 1be:	39 c1                	cmp    %eax,%ecx
 1c0:	7d 2c                	jge    1ee <free_group+0x1ee>
 1c2:	48 8b 47 20          	mov    0x20(%rdi),%rax
 1c6:	48 c1 e8 0c          	shr    $0xc,%rax
 1ca:	74 11                	je     1dd <free_group+0x1dd>
 1cc:	48 c1 e0 08          	shl    $0x8,%rax
 1d0:	48 83 e8 01          	sub    $0x1,%rax
 1d4:	48 39 c8             	cmp    %rcx,%rax
 1d7:	0f 82 00 00 00 00    	jb     1dd <free_group+0x1dd>
			1d9: R_X86_64_PC32	.text.unlikely.free_group-0x4
 1dd:	48 c7 02 00 00 00 00 	movq   $0x0,(%rdx)
 1e4:	e8 00 00 00 00       	call   1e9 <free_group+0x1e9>
			1e5: R_X86_64_PC32	.text.nontrivial_free-0x4
 1e9:	e9 78 fe ff ff       	jmp    66 <free_group+0x66>
 1ee:	e9 00 00 00 00       	jmp    1f3 <free_group+0x1f3>
			1ef: R_X86_64_PC32	.text.unlikely.free_group-0x4
 1f3:	83 f8 3f             	cmp    $0x3f,%eax
 1f6:	0f 85 00 00 00 00    	jne    1fc <free_group+0x1fc>
			1f8: R_X86_64_PC32	.text.unlikely.free_group-0x4
 1fc:	45 84 c9             	test   %r9b,%r9b
 1ff:	0f 85 00 00 00 00    	jne    205 <free_group+0x205>
			201: R_X86_64_PC32	.text.unlikely.free_group-0x4
 205:	48 81 7f 20 ff 0f 00 	cmpq   $0xfff,0x20(%rdi)
 20c:	00 
 20d:	77 b3                	ja     1c2 <free_group+0x1c2>
 20f:	e9 00 00 00 00       	jmp    214 <free_group+0x214>
			210: R_X86_64_PC32	.text.unlikely.free_group-0x4
 214:	66 48 0f 6e c3       	movq   %rbx,%xmm0
 219:	66 0f 6c c0          	punpcklqdq %xmm0,%xmm0
 21d:	0f 11 03             	movups %xmm0,(%rbx)
 220:	48 89 1d 00 00 00 00 	mov    %rbx,0x0(%rip)        # 227 <free_group+0x227>
			223: R_X86_64_PC32	__malloc_context+0xc
 227:	e9 72 fe ff ff       	jmp    9e <free_group+0x9e>

Disassembly of section .text.unlikely.__libc_free:

0000000000000000 <__libc_free.cold>:
   0:	0f 0b                	ud2

Disassembly of section .text.__libc_free:

0000000000000000 <__libc_free>:
   0:	48 85 ff             	test   %rdi,%rdi
   3:	0f 84 87 02 00 00    	je     290 <__libc_free+0x290>
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
  d3:	0f 8f ff 00 00 00    	jg     1d8 <__libc_free+0x1d8>
  d9:	48 8d 35 00 00 00 00 	lea    0x0(%rip),%rsi        # e0 <__libc_free+0xe0>
			dc: R_X86_64_PC32	__malloc_size_classes-0x4
  e0:	0f b7 34 56          	movzwl (%rsi,%rdx,2),%esi
  e4:	89 ea                	mov    %ebp,%edx
  e6:	0f af d6             	imul   %esi,%edx
  e9:	41 39 d3             	cmp    %edx,%r11d
  ec:	0f 8c 00 00 00 00    	jl     f2 <__libc_free+0xf2>
			ee: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
  f2:	01 f2                	add    %esi,%edx
  f4:	41 39 d3             	cmp    %edx,%r11d
  f7:	0f 8d 00 00 00 00    	jge    fd <__libc_free+0xfd>
			f9: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
  fd:	c1 e6 04             	shl    $0x4,%esi
 100:	48 63 f6             	movslq %esi,%rsi
 103:	48 8b 53 20          	mov    0x20(%rbx),%rdx
 107:	48 c1 ea 0c          	shr    $0xc,%rdx
 10b:	74 25                	je     132 <__libc_free+0x132>
 10d:	49 89 d4             	mov    %rdx,%r12
 110:	48 c1 e2 08          	shl    $0x8,%rdx
 114:	48 83 ea 01          	sub    $0x1,%rdx
 118:	49 c1 e4 0c          	shl    $0xc,%r12
 11c:	4c 39 da             	cmp    %r11,%rdx
 11f:	0f 82 00 00 00 00    	jb     125 <__libc_free+0x125>
			121: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 125:	49 8d 54 24 f0       	lea    -0x10(%r12),%rdx
 12a:	41 83 e1 1f          	and    $0x1f,%r9d
 12e:	48 0f 44 f2          	cmove  %rdx,%rsi
 132:	0f b6 d1             	movzbl %cl,%edx
 135:	48 0f af d6          	imul   %rsi,%rdx
 139:	48 8d 54 16 fc       	lea    -0x4(%rsi,%rdx,1),%rdx
 13e:	49 8d 74 12 10       	lea    0x10(%r10,%rdx,1),%rsi
 143:	89 fa                	mov    %edi,%edx
 145:	c0 ea 05             	shr    $0x5,%dl
 148:	40 80 ff 9f          	cmp    $0x9f,%dil
 14c:	0f 87 ab 00 00 00    	ja     1fd <__libc_free+0x1fd>
 152:	0f b6 d2             	movzbl %dl,%edx
 155:	48 89 f7             	mov    %rsi,%rdi
 158:	48 29 c7             	sub    %rax,%rdi
 15b:	48 39 d7             	cmp    %rdx,%rdi
 15e:	0f 82 00 00 00 00    	jb     164 <__libc_free+0x164>
			160: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 164:	48 89 f7             	mov    %rsi,%rdi
 167:	48 29 d7             	sub    %rdx,%rdi
 16a:	80 3f 00             	cmpb   $0x0,(%rdi)
 16d:	0f 85 00 00 00 00    	jne    173 <__libc_free+0x173>
			16f: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 173:	80 3e 00             	cmpb   $0x0,(%rsi)
 176:	0f 85 00 00 00 00    	jne    17c <__libc_free+0x17c>
			178: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 17c:	be 01 00 00 00       	mov    $0x1,%esi
 181:	31 d2                	xor    %edx,%edx
 183:	bf 02 00 00 00       	mov    $0x2,%edi
 188:	c6 40 fd ff          	movb   $0xff,-0x3(%rax)
 18c:	d3 e6                	shl    %cl,%esi
 18e:	66 89 50 fe          	mov    %dx,-0x2(%rax)
 192:	44 89 c1             	mov    %r8d,%ecx
 195:	d3 e7                	shl    %cl,%edi
 197:	83 ef 01             	sub    $0x1,%edi
 19a:	8b 53 1c             	mov    0x1c(%rbx),%edx
 19d:	8b 43 18             	mov    0x18(%rbx),%eax
 1a0:	09 d0                	or     %edx,%eax
 1a2:	85 c6                	test   %eax,%esi
 1a4:	0f 85 00 00 00 00    	jne    1aa <__libc_free+0x1aa>
			1a6: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 1aa:	85 d2                	test   %edx,%edx
 1ac:	74 79                	je     227 <__libc_free+0x227>
 1ae:	01 f0                	add    %esi,%eax
 1b0:	39 f8                	cmp    %edi,%eax
 1b2:	74 73                	je     227 <__libc_free+0x227>
 1b4:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 1bb <__libc_free+0x1bb>
			1b7: R_X86_64_PC32	__libc-0x1
 1bb:	8d 0c 16             	lea    (%rsi,%rdx,1),%ecx
 1be:	84 c0                	test   %al,%al
 1c0:	74 60                	je     222 <__libc_free+0x222>
 1c2:	89 d0                	mov    %edx,%eax
 1c4:	f0 0f b1 4b 1c       	lock cmpxchg %ecx,0x1c(%rbx)
 1c9:	39 c2                	cmp    %eax,%edx
 1cb:	75 cd                	jne    19a <__libc_free+0x19a>
 1cd:	48 83 c4 08          	add    $0x8,%rsp
 1d1:	5b                   	pop    %rbx
 1d2:	5d                   	pop    %rbp
 1d3:	41 5c                	pop    %r12
 1d5:	41 5d                	pop    %r13
 1d7:	c3                   	ret
 1d8:	83 fa 3f             	cmp    $0x3f,%edx
 1db:	0f 85 00 00 00 00    	jne    1e1 <__libc_free+0x1e1>
			1dd: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 1e1:	45 84 c0             	test   %r8b,%r8b
 1e4:	0f 85 00 00 00 00    	jne    1ea <__libc_free+0x1ea>
			1e6: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 1ea:	48 81 7b 20 ff 0f 00 	cmpq   $0xfff,0x20(%rbx)
 1f1:	00 
 1f2:	0f 87 0b ff ff ff    	ja     103 <__libc_free+0x103>
 1f8:	e9 00 00 00 00       	jmp    1fd <__libc_free+0x1fd>
			1f9: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 1fd:	80 fa 05             	cmp    $0x5,%dl
 200:	0f 85 00 00 00 00    	jne    206 <__libc_free+0x206>
			202: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 206:	8b 56 fc             	mov    -0x4(%rsi),%edx
 209:	48 83 fa 04          	cmp    $0x4,%rdx
 20d:	0f 86 00 00 00 00    	jbe    213 <__libc_free+0x213>
			20f: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 213:	80 7e fb 00          	cmpb   $0x0,-0x5(%rsi)
 217:	0f 84 38 ff ff ff    	je     155 <__libc_free+0x155>
 21d:	e9 00 00 00 00       	jmp    222 <__libc_free+0x222>
			21e: R_X86_64_PC32	.text.unlikely.__libc_free-0x4
 222:	89 4b 1c             	mov    %ecx,0x1c(%rbx)
 225:	eb a6                	jmp    1cd <__libc_free+0x1cd>
 227:	0f b6 05 00 00 00 00 	movzbl 0x0(%rip),%eax        # 22e <__libc_free+0x22e>
			22a: R_X86_64_PC32	__libc-0x1
 22e:	84 c0                	test   %al,%al
 230:	75 42                	jne    274 <__libc_free+0x274>
 232:	89 ee                	mov    %ebp,%esi
 234:	48 89 df             	mov    %rbx,%rdi
 237:	e8 00 00 00 00       	call   23c <__libc_free+0x23c>
			238: R_X86_64_PC32	.text.nontrivial_free-0x4
 23c:	48 89 c5             	mov    %rax,%rbp
 23f:	8b 05 00 00 00 00    	mov    0x0(%rip),%eax        # 245 <__libc_free+0x245>
			241: R_X86_64_PC32	__malloc_lock-0x4
 245:	48 89 d3             	mov    %rdx,%rbx
 248:	85 c0                	test   %eax,%eax
 24a:	78 36                	js     282 <__libc_free+0x282>
 24c:	48 85 db             	test   %rbx,%rbx
 24f:	0f 84 78 ff ff ff    	je     1cd <__libc_free+0x1cd>
 255:	e8 00 00 00 00       	call   25a <__libc_free+0x25a>
			256: R_X86_64_PLT32	___errno_location-0x4
 25a:	48 89 de             	mov    %rbx,%rsi
 25d:	48 89 ef             	mov    %rbp,%rdi
 260:	44 8b 28             	mov    (%rax),%r13d
 263:	49 89 c4             	mov    %rax,%r12
 266:	e8 00 00 00 00       	call   26b <__libc_free+0x26b>
			267: R_X86_64_PLT32	munmap-0x4
 26b:	45 89 2c 24          	mov    %r13d,(%r12)
 26f:	e9 59 ff ff ff       	jmp    1cd <__libc_free+0x1cd>
 274:	48 8d 3d 00 00 00 00 	lea    0x0(%rip),%rdi        # 27b <__libc_free+0x27b>
			277: R_X86_64_PC32	__malloc_lock-0x4
 27b:	e8 00 00 00 00       	call   280 <__libc_free+0x280>
			27c: R_X86_64_PLT32	__lock-0x4
 280:	eb b0                	jmp    232 <__libc_free+0x232>
 282:	48 8d 3d 00 00 00 00 	lea    0x0(%rip),%rdi        # 289 <__libc_free+0x289>
			285: R_X86_64_PC32	__malloc_lock-0x4
 289:	e8 00 00 00 00       	call   28e <__libc_free+0x28e>
			28a: R_X86_64_PLT32	__unlock-0x4
 28e:	eb bc                	jmp    24c <__libc_free+0x24c>
 290:	c3                   	ret

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

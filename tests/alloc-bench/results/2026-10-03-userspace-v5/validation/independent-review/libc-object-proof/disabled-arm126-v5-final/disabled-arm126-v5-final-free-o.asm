
/Users/alex/code/vinix/third_party/useralloc-libc/build/musl/aarch64/45e591e09bed5a7f37f2a259e8135213cdbcff073604a7239878a1169ec7dae3/objects/obj/src/malloc/mallocng/free.o:     file format elf64-littleaarch64


Disassembly of section .text.nontrivial_free:

0000000000000000 <nontrivial_free>:
   0:	52800023 	mov	w3, #0x1                   	// #1
   4:	b9401c04 	ldr	w4, [x0, #28]
   8:	1ac12061 	lsl	w1, w3, w1
   c:	b9401807 	ldr	w7, [x0, #24]
  10:	f9401003 	ldr	x3, [x0, #32]
  14:	2a070084 	orr	w4, w4, w7
  18:	52800042 	mov	w2, #0x2                   	// #2
  1c:	12001068 	and	w8, w3, #0x1f
  20:	d3401066 	ubfx	x6, x3, #0, #5
  24:	53062c65 	ubfx	w5, w3, #6, #6
  28:	1ac62042 	lsl	w2, w2, w6
  2c:	0b040026 	add	w6, w1, w4
  30:	51000442 	sub	w2, w2, #0x1
  34:	6b0200df 	cmp	w6, w2
  38:	54000420 	b.eq	bc <nontrivial_free+0xbc>  // b.none
  3c:	350002a4 	cbnz	w4, 90 <nontrivial_free+0x90>
  40:	7100bcbf 	cmp	w5, #0x2f
  44:	54000dec 	b.gt	200 <nontrivial_free+0x200>
  48:	93407ca5 	sxtw	x5, w5
  4c:	90000002 	adrp	x2, 0 <__malloc_context>
			4c: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
  50:	910028a5 	add	x5, x5, #0xa
  54:	91000042 	add	x2, x2, #0x0
			54: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
  58:	f8657843 	ldr	x3, [x2, x5, lsl #3]
  5c:	eb00007f 	cmp	x3, x0
  60:	54000180 	b.eq	90 <nontrivial_free+0x90>  // b.none
  64:	f9400404 	ldr	x4, [x0, #8]
  68:	b5000cc4 	cbnz	x4, 200 <nontrivial_free+0x200>
  6c:	f9400004 	ldr	x4, [x0]
  70:	b5000c84 	cbnz	x4, 200 <nontrivial_free+0x200>
  74:	b4001123 	cbz	x3, 298 <nontrivial_free+0x298>
  78:	f9000403 	str	x3, [x0, #8]
  7c:	f9400062 	ldr	x2, [x3]
  80:	f9000002 	str	x2, [x0]
  84:	f9000440 	str	x0, [x2, #8]
  88:	f9400402 	ldr	x2, [x0, #8]
  8c:	f9000040 	str	x0, [x2]
  90:	90000002 	adrp	x2, 0 <__libc>
			90: R_AARCH64_ADR_PREL_PG_HI21	__libc
  94:	91000042 	add	x2, x2, #0x0
			94: R_AARCH64_ADD_ABS_LO12_NC	__libc
  98:	39400c42 	ldrb	w2, [x2, #3]
  9c:	72001c5f 	tst	w2, #0xff
  a0:	54001021 	b.ne	2a4 <nontrivial_free+0x2a4>  // b.any
  a4:	b9401c02 	ldr	w2, [x0, #28]
  a8:	2a010041 	orr	w1, w2, w1
  ac:	b9001c01 	str	w1, [x0, #28]
  b0:	d2800000 	mov	x0, #0x0                   	// #0
  b4:	d2800001 	mov	x1, #0x0                   	// #0
  b8:	d65f03c0 	ret
  bc:	362ffc03 	tbz	w3, #5, 3c <nontrivial_free+0x3c>
  c0:	f9400406 	ldr	x6, [x0, #8]
  c4:	7100bcbf 	cmp	w5, #0x2f
  c8:	540009ac 	b.gt	1fc <nontrivial_free+0x1fc>
  cc:	f240107f 	tst	x3, #0x1f
  d0:	540003e1 	b.ne	14c <nontrivial_free+0x14c>  // b.any
  d4:	f13ffc7f 	cmp	x3, #0xfff
  d8:	54000129 	b.ls	fc <nontrivial_free+0xfc>  // b.plast
  dc:	90000007 	adrp	x7, 0 <__malloc_size_classes>
			dc: R_AARCH64_ADR_PREL_PG_HI21	__malloc_size_classes
  e0:	910000e7 	add	x7, x7, #0x0
			e0: R_AARCH64_ADD_ABS_LO12_NC	__malloc_size_classes
  e4:	9274cc62 	and	x2, x3, #0xfffffffffffff000
  e8:	d1004042 	sub	x2, x2, #0x10
  ec:	7865d8e3 	ldrh	w3, [x7, w5, sxtw #1]
  f0:	d37c3c63 	ubfiz	x3, x3, #4, #16
  f4:	eb03005f 	cmp	x2, x3
  f8:	540002e2 	b.cs	154 <nontrivial_free+0x154>  // b.hs, b.nlast
  fc:	b4000266 	cbz	x6, 148 <nontrivial_free+0x148>
 100:	93407ca5 	sxtw	x5, w5
 104:	90000002 	adrp	x2, 0 <__malloc_context>
			104: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
 108:	910028a1 	add	x1, x5, #0xa
 10c:	91000042 	add	x2, x2, #0x0
			10c: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 110:	f8617841 	ldr	x1, [x2, x1, lsl #3]
 114:	eb06001f 	cmp	x0, x6
 118:	54000400 	b.eq	198 <nontrivial_free+0x198>  // b.none
 11c:	f9400004 	ldr	x4, [x0]
 120:	910028a3 	add	x3, x5, #0xa
 124:	f9000486 	str	x6, [x4, #8]
 128:	f9400004 	ldr	x4, [x0]
 12c:	f90000c4 	str	x4, [x6]
 130:	f8637844 	ldr	x4, [x2, x3, lsl #3]
 134:	eb04001f 	cmp	x0, x4
 138:	54000660 	b.eq	204 <nontrivial_free+0x204>  // b.none
 13c:	a9007c1f 	stp	xzr, xzr, [x0]
 140:	eb01001f 	cmp	x0, x1
 144:	54000660 	b.eq	210 <nontrivial_free+0x210>  // b.none
 148:	14000000 	b	0 <nontrivial_free>
			148: R_AARCH64_JUMP26	.text.free_group
 14c:	f13ffc7f 	cmp	x3, #0xfff
 150:	54fffd69 	b.ls	fc <nontrivial_free+0xfc>  // b.plast
 154:	eb06001f 	cmp	x0, x6
 158:	54000100 	b.eq	178 <nontrivial_free+0x178>  // b.none
 15c:	b4ffff66 	cbz	x6, 148 <nontrivial_free+0x148>
 160:	93407ca5 	sxtw	x5, w5
 164:	90000002 	adrp	x2, 0 <__malloc_context>
			164: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
 168:	910028a1 	add	x1, x5, #0xa
 16c:	91000042 	add	x2, x2, #0x0
			16c: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 170:	f8617841 	ldr	x1, [x2, x1, lsl #3]
 174:	17ffffea 	b	11c <nontrivial_free+0x11c>
 178:	51001ca3 	sub	w3, w5, #0x7
 17c:	71007c7f 	cmp	w3, #0x1f
 180:	54000129 	b.ls	1a4 <nontrivial_free+0x1a4>  // b.plast
 184:	90000002 	adrp	x2, 0 <__malloc_context>
			184: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
 188:	93407ca5 	sxtw	x5, w5
 18c:	91000042 	add	x2, x2, #0x0
			18c: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 190:	910028a1 	add	x1, x5, #0xa
 194:	f8617841 	ldr	x1, [x2, x1, lsl #3]
 198:	910028a3 	add	x3, x5, #0xa
 19c:	f823785f 	str	xzr, [x2, x3, lsl #3]
 1a0:	17ffffe7 	b	13c <nontrivial_free+0x13c>
 1a4:	90000002 	adrp	x2, 0 <__malloc_context>
			1a4: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
 1a8:	91000042 	add	x2, x2, #0x0
			1a8: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 1ac:	8b23c043 	add	x3, x2, w3, sxtw
 1b0:	93407ca5 	sxtw	x5, w5
 1b4:	394e6063 	ldrb	w3, [x3, #920]
 1b8:	71018c7f 	cmp	w3, #0x63
 1bc:	54fffea9 	b.ls	190 <nontrivial_free+0x190>  // b.plast
 1c0:	8b050c47 	add	x7, x2, x5, lsl #3
 1c4:	11000509 	add	w9, w8, #0x1
 1c8:	d37d1523 	ubfiz	x3, x9, #3, #6
 1cc:	f940fce7 	ldr	x7, [x7, #504]
 1d0:	8b090063 	add	x3, x3, x9
 1d4:	eb0300ff 	cmp	x7, x3
 1d8:	54000063 	b.cc	1e4 <nontrivial_free+0x1e4>  // b.lo, b.ul, b.last
 1dc:	71004d3f 	cmp	w9, #0x13
 1e0:	54fffd8d 	b.le	190 <nontrivial_free+0x190>
 1e4:	35fff564 	cbnz	w4, 90 <nontrivial_free+0x90>
 1e8:	910028a5 	add	x5, x5, #0xa
 1ec:	f8657842 	ldr	x2, [x2, x5, lsl #3]
 1f0:	eb06005f 	cmp	x2, x6
 1f4:	54fff4e0 	b.eq	90 <nontrivial_free+0x90>  // b.none
 1f8:	14000002 	b	200 <nontrivial_free+0x200>
 1fc:	b4fffa66 	cbz	x6, 148 <nontrivial_free+0x148>
 200:	d4207d00 	brk	#0x3e8
 204:	f9400404 	ldr	x4, [x0, #8]
 208:	f8237844 	str	x4, [x2, x3, lsl #3]
 20c:	17ffffcc 	b	13c <nontrivial_free+0x13c>
 210:	910028a5 	add	x5, x5, #0xa
 214:	f8657845 	ldr	x5, [x2, x5, lsl #3]
 218:	b4fff985 	cbz	x5, 148 <nontrivial_free+0x148>
 21c:	b94018a1 	ldr	w1, [x5, #24]
 220:	35ffff01 	cbnz	w1, 200 <nontrivial_free+0x200>
 224:	f94008a1 	ldr	x1, [x5, #16]
 228:	90000002 	adrp	x2, 0 <__libc>
			228: R_AARCH64_ADR_PREL_PG_HI21	__libc
 22c:	91000042 	add	x2, x2, #0x0
			22c: R_AARCH64_ADD_ABS_LO12_NC	__libc
 230:	52800046 	mov	w6, #0x2                   	// #2
 234:	910070a3 	add	x3, x5, #0x1c
 238:	f9400421 	ldr	x1, [x1, #8]
 23c:	39400c42 	ldrb	w2, [x2, #3]
 240:	d3401021 	ubfx	x1, x1, #0, #5
 244:	1ac120c6 	lsl	w6, w6, w1
 248:	510004c8 	sub	w8, w6, #0x1
 24c:	4b0603e6 	neg	w6, w6
 250:	72001c5f 	tst	w2, #0xff
 254:	540000c1 	b.ne	26c <nontrivial_free+0x26c>  // b.any
 258:	b9401ca7 	ldr	w7, [x5, #28]
 25c:	0a0600e6 	and	w6, w7, w6
 260:	b9001ca6 	str	w6, [x5, #28]
 264:	1400000a 	b	28c <nontrivial_free+0x28c>
 268:	d5033bbf 	dmb	ish
 26c:	b9401ca4 	ldr	w4, [x5, #28]
 270:	2a0403e7 	mov	w7, w4
 274:	0a060082 	and	w2, w4, w6
 278:	885ffc61 	ldaxr	w1, [x3]
 27c:	6b01009f 	cmp	w4, w1
 280:	54ffff41 	b.ne	268 <nontrivial_free+0x268>  // b.any
 284:	8801fc62 	stlxr	w1, w2, [x3]
 288:	35ffff81 	cbnz	w1, 278 <nontrivial_free+0x278>
 28c:	0a070101 	and	w1, w8, w7
 290:	b90018a1 	str	w1, [x5, #24]
 294:	17ffffad 	b	148 <nontrivial_free+0x148>
 298:	a9000000 	stp	x0, x0, [x0]
 29c:	f8257840 	str	x0, [x2, x5, lsl #3]
 2a0:	17ffff7c 	b	90 <nontrivial_free+0x90>
 2a4:	91007002 	add	x2, x0, #0x1c
 2a8:	885ffc40 	ldaxr	w0, [x2]
 2ac:	2a010000 	orr	w0, w0, w1
 2b0:	8803fc40 	stlxr	w3, w0, [x2]
 2b4:	35ffffa3 	cbnz	w3, 2a8 <nontrivial_free+0x2a8>
 2b8:	17ffff7e 	b	b0 <nontrivial_free+0xb0>

Disassembly of section .text.free_group:

0000000000000000 <free_group>:
   0:	a9bf4ffe 	stp	x30, x19, [sp, #-16]!
   4:	aa0003f3 	mov	x19, x0
   8:	f9401000 	ldr	x0, [x0, #32]
   c:	53062c03 	ubfx	w3, w0, #6, #6
  10:	7100bc7f 	cmp	w3, #0x2f
  14:	5400040d 	b.le	94 <free_group+0x94>
  18:	f13ffc1f 	cmp	x0, #0xfff
  1c:	54000669 	b.ls	e8 <free_group+0xe8>  // b.plast
  20:	90000002 	adrp	x2, 0 <__malloc_context>
			20: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
  24:	91000042 	add	x2, x2, #0x0
			24: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
  28:	394ee041 	ldrb	w1, [x2, #952]
  2c:	11000420 	add	w0, w1, #0x1
  30:	12001c00 	and	w0, w0, #0xff
  34:	7103fc3f 	cmp	w1, #0xff
  38:	54000460 	b.eq	c4 <free_group+0xc4>  // b.none
  3c:	51001c63 	sub	w3, w3, #0x7
  40:	390ee040 	strb	w0, [x2, #952]
  44:	71007c7f 	cmp	w3, #0x1f
  48:	54000068 	b.hi	54 <free_group+0x54>  // b.pmore
  4c:	8b23c043 	add	x3, x2, w3, sxtw
  50:	390de060 	strb	w0, [x3, #888]
  54:	f9401261 	ldr	x1, [x19, #32]
  58:	f9400a60 	ldr	x0, [x19, #16]
  5c:	9274cc21 	and	x1, x1, #0xfffffffffffff000
  60:	a9007e7f 	stp	xzr, xzr, [x19]
  64:	a9017e7f 	stp	xzr, xzr, [x19, #16]
  68:	f9400843 	ldr	x3, [x2, #16]
  6c:	f900127f 	str	xzr, [x19, #32]
  70:	b4000be3 	cbz	x3, 1ec <free_group+0x1ec>
  74:	f9000663 	str	x3, [x19, #8]
  78:	f9400062 	ldr	x2, [x3]
  7c:	f9000262 	str	x2, [x19]
  80:	f9000453 	str	x19, [x2, #8]
  84:	f9400662 	ldr	x2, [x19, #8]
  88:	f9000053 	str	x19, [x2]
  8c:	a8c14ffe 	ldp	x30, x19, [sp], #16
  90:	d65f03c0 	ret
  94:	d37d1461 	ubfiz	x1, x3, #3, #6
  98:	90000002 	adrp	x2, 0 <__malloc_context>
			98: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
  9c:	9107c021 	add	x1, x1, #0x1f0
  a0:	91000042 	add	x2, x2, #0x0
			a0: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
  a4:	8b010042 	add	x2, x2, x1
  a8:	92401000 	and	x0, x0, #0x1f
  ac:	91000400 	add	x0, x0, #0x1
  b0:	f9400441 	ldr	x1, [x2, #8]
  b4:	cb000020 	sub	x0, x1, x0
  b8:	f9000440 	str	x0, [x2, #8]
  bc:	f9401260 	ldr	x0, [x19, #32]
  c0:	17ffffd6 	b	18 <free_group+0x18>
  c4:	90000001 	adrp	x1, 0 <__malloc_context>
			c4: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context+0x378
  c8:	910e6040 	add	x0, x2, #0x398
  cc:	91000021 	add	x1, x1, #0x0
			cc: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context+0x378
  d0:	14000002 	b	d8 <free_group+0xd8>
  d4:	3800143f 	strb	wzr, [x1], #1
  d8:	eb00003f 	cmp	x1, x0
  dc:	54ffffc1 	b.ne	d4 <free_group+0xd4>  // b.any
  e0:	52800020 	mov	w0, #0x1                   	// #1
  e4:	17ffffd6 	b	3c <free_group+0x3c>
  e8:	f9400a63 	ldr	x3, [x19, #16]
  ec:	f2400c7f 	tst	x3, #0xf
  f0:	540007c1 	b.ne	1e8 <free_group+0x1e8>  // b.any
  f4:	385fc060 	ldurb	w0, [x3, #-4]
  f8:	385fd061 	ldurb	w1, [x3, #-3]
  fc:	785fe067 	ldurh	w7, [x3, #-2]
 100:	12001021 	and	w1, w1, #0x1f
 104:	340000c0 	cbz	w0, 11c <free_group+0x11c>
 108:	35000707 	cbnz	w7, 1e8 <free_group+0x1e8>
 10c:	b85f8067 	ldur	w7, [x3, #-8]
 110:	529fffe0 	mov	w0, #0xffff                	// #65535
 114:	6b0000ff 	cmp	w7, w0
 118:	5400068d 	b.le	1e8 <free_group+0x1e8>
 11c:	531c6ce2 	lsl	w2, w7, #4
 120:	928001e0 	mov	x0, #0xfffffffffffffff0    	// #-16
 124:	cb22c000 	sub	x0, x0, w2, sxtw
 128:	8b000064 	add	x4, x3, x0
 12c:	f8606860 	ldr	x0, [x3, x0]
 130:	f9400802 	ldr	x2, [x0, #16]
 134:	eb02009f 	cmp	x4, x2
 138:	54000581 	b.ne	1e8 <free_group+0x1e8>  // b.any
 13c:	f9401004 	ldr	x4, [x0, #32]
 140:	12001082 	and	w2, w4, #0x1f
 144:	6b02003f 	cmp	w1, w2
 148:	5400050c 	b.gt	1e8 <free_group+0x1e8>
 14c:	b9401802 	ldr	w2, [x0, #24]
 150:	1ac12442 	lsr	w2, w2, w1
 154:	370004a2 	tbnz	w2, #0, 1e8 <free_group+0x1e8>
 158:	b9401c02 	ldr	w2, [x0, #28]
 15c:	1ac12442 	lsr	w2, w2, w1
 160:	37000442 	tbnz	w2, #0, 1e8 <free_group+0x1e8>
 164:	9274cc05 	and	x5, x0, #0xfffffffffffff000
 168:	90000002 	adrp	x2, 0 <__malloc_context>
			168: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
 16c:	f9400046 	ldr	x6, [x2]
			16c: R_AARCH64_LDST64_ABS_LO12_NC	__malloc_context
 170:	f94000a2 	ldr	x2, [x5]
 174:	eb06005f 	cmp	x2, x6
 178:	54000381 	b.ne	1e8 <free_group+0x1e8>  // b.any
 17c:	53062c82 	ubfx	w2, w4, #6, #6
 180:	7100bc5f 	cmp	w2, #0x2f
 184:	540002c8 	b.hi	1dc <free_group+0x1dc>  // b.pmore
 188:	90000005 	adrp	x5, 0 <__malloc_size_classes>
			188: R_AARCH64_ADR_PREL_PG_HI21	__malloc_size_classes
 18c:	910000a5 	add	x5, x5, #0x0
			18c: R_AARCH64_ADD_ABS_LO12_NC	__malloc_size_classes
 190:	7862d8a2 	ldrh	w2, [x5, w2, sxtw #1]
 194:	1b027c25 	mul	w5, w1, w2
 198:	6b0500ff 	cmp	w7, w5
 19c:	5400026b 	b.lt	1e8 <free_group+0x1e8>  // b.tstop
 1a0:	0b050042 	add	w2, w2, w5
 1a4:	6b0200ff 	cmp	w7, w2
 1a8:	5400020a 	b.ge	1e8 <free_group+0x1e8>  // b.tcont
 1ac:	f13ffc9f 	cmp	x4, #0xfff
 1b0:	540000c9 	b.ls	1c8 <free_group+0x1c8>  // b.plast
 1b4:	9274cc82 	and	x2, x4, #0xfffffffffffff000
 1b8:	d344fc42 	lsr	x2, x2, #4
 1bc:	d1000442 	sub	x2, x2, #0x1
 1c0:	eb27c05f 	cmp	x2, w7, sxtw
 1c4:	54000123 	b.cc	1e8 <free_group+0x1e8>  // b.lo, b.ul, b.last
 1c8:	f900007f 	str	xzr, [x3]
 1cc:	94000000 	bl	0 <free_group>
			1cc: R_AARCH64_CALL26	.text.nontrivial_free
 1d0:	90000002 	adrp	x2, 0 <__malloc_context>
			1d0: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
 1d4:	91000042 	add	x2, x2, #0x0
			1d4: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 1d8:	17ffffa2 	b	60 <free_group+0x60>
 1dc:	927a1482 	and	x2, x4, #0xfc0
 1e0:	f13f005f 	cmp	x2, #0xfc0
 1e4:	54fffe40 	b.eq	1ac <free_group+0x1ac>  // b.none
 1e8:	d4207d00 	brk	#0x3e8
 1ec:	a9004e73 	stp	x19, x19, [x19]
 1f0:	f9000853 	str	x19, [x2, #16]
 1f4:	17ffffa6 	b	8c <free_group+0x8c>

Disassembly of section .text.__libc_free:

0000000000000000 <__libc_free>:
   0:	b4001460 	cbz	x0, 28c <__libc_free+0x28c>
   4:	f2400c1f 	tst	x0, #0xf
   8:	54001401 	b.ne	288 <__libc_free+0x288>  // b.any
   c:	385fc002 	ldurb	w2, [x0, #-4]
  10:	385fd006 	ldurb	w6, [x0, #-3]
  14:	785fe005 	ldurh	w5, [x0, #-2]
  18:	120010c1 	and	w1, w6, #0x1f
  1c:	340000c2 	cbz	w2, 34 <__libc_free+0x34>
  20:	35001345 	cbnz	w5, 288 <__libc_free+0x288>
  24:	b85f8005 	ldur	w5, [x0, #-8]
  28:	529fffe2 	mov	w2, #0xffff                	// #65535
  2c:	6b0200bf 	cmp	w5, w2
  30:	540012cd 	b.le	288 <__libc_free+0x288>
  34:	531c6ca3 	lsl	w3, w5, #4
  38:	928001e2 	mov	x2, #0xfffffffffffffff0    	// #-16
  3c:	a9bd4ffe 	stp	x30, x19, [sp, #-48]!
  40:	cb23c042 	sub	x2, x2, w3, sxtw
  44:	8b020004 	add	x4, x0, x2
  48:	f8626813 	ldr	x19, [x0, x2]
  4c:	f9400a63 	ldr	x3, [x19, #16]
  50:	eb03009f 	cmp	x4, x3
  54:	54000ca1 	b.ne	1e8 <__libc_free+0x1e8>  // b.any
  58:	f9401262 	ldr	x2, [x19, #32]
  5c:	12001044 	and	w4, w2, #0x1f
  60:	d3401048 	ubfx	x8, x2, #0, #5
  64:	6b04003f 	cmp	w1, w4
  68:	54000c0c 	b.gt	1e8 <__libc_free+0x1e8>
  6c:	b9401a64 	ldr	w4, [x19, #24]
  70:	1ac12484 	lsr	w4, w4, w1
  74:	37000ba4 	tbnz	w4, #0, 1e8 <__libc_free+0x1e8>
  78:	b9401e64 	ldr	w4, [x19, #28]
  7c:	1ac12484 	lsr	w4, w4, w1
  80:	37000b44 	tbnz	w4, #0, 1e8 <__libc_free+0x1e8>
  84:	9274ce64 	and	x4, x19, #0xfffffffffffff000
  88:	90000007 	adrp	x7, 0 <__malloc_context>
			88: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
  8c:	f94000e7 	ldr	x7, [x7]
			8c: R_AARCH64_LDST64_ABS_LO12_NC	__malloc_context
  90:	f9400084 	ldr	x4, [x4]
  94:	eb07009f 	cmp	x4, x7
  98:	54000a81 	b.ne	1e8 <__libc_free+0x1e8>  // b.any
  9c:	53062c47 	ubfx	w7, w2, #6, #6
  a0:	7100bcff 	cmp	w7, #0x2f
  a4:	540009c8 	b.hi	1dc <__libc_free+0x1dc>  // b.pmore
  a8:	90000004 	adrp	x4, 0 <__malloc_size_classes>
			a8: R_AARCH64_ADR_PREL_PG_HI21	__malloc_size_classes
  ac:	91000084 	add	x4, x4, #0x0
			ac: R_AARCH64_ADD_ABS_LO12_NC	__malloc_size_classes
  b0:	7867d884 	ldrh	w4, [x4, w7, sxtw #1]
  b4:	1b047c29 	mul	w9, w1, w4
  b8:	6b0900bf 	cmp	w5, w9
  bc:	5400096b 	b.lt	1e8 <__libc_free+0x1e8>  // b.tstop
  c0:	0b090084 	add	w4, w4, w9
  c4:	6b0400bf 	cmp	w5, w4
  c8:	5400090a 	b.ge	1e8 <__libc_free+0x1e8>  // b.tcont
  cc:	f13ffc5f 	cmp	x2, #0xfff
  d0:	54000129 	b.ls	f4 <__libc_free+0xf4>  // b.plast
  d4:	9274cc44 	and	x4, x2, #0xfffffffffffff000
  d8:	d344fc89 	lsr	x9, x4, #4
  dc:	d1000529 	sub	x9, x9, #0x1
  e0:	eb25c13f 	cmp	x9, w5, sxtw
  e4:	54000823 	b.cc	1e8 <__libc_free+0x1e8>  // b.lo, b.ul, b.last
  e8:	d1004084 	sub	x4, x4, #0x10
  ec:	f240105f 	tst	x2, #0x1f
  f0:	540000a0 	b.eq	104 <__libc_free+0x104>  // b.none
  f4:	90000002 	adrp	x2, 0 <__malloc_size_classes>
			f4: R_AARCH64_ADR_PREL_PG_HI21	__malloc_size_classes
  f8:	91000042 	add	x2, x2, #0x0
			f8: R_AARCH64_ADD_ABS_LO12_NC	__malloc_size_classes
  fc:	7867d844 	ldrh	w4, [x2, w7, sxtw #1]
 100:	d37c3c84 	ubfiz	x4, x4, #4, #16
 104:	d1001087 	sub	x7, x4, #0x4
 108:	2a0103e2 	mov	w2, w1
 10c:	91004063 	add	x3, x3, #0x10
 110:	53057cc5 	lsr	w5, w6, #5
 114:	9b041c42 	madd	x2, x2, x4, x7
 118:	8b020064 	add	x4, x3, x2
 11c:	71027cdf 	cmp	w6, #0x9f
 120:	54000109 	b.ls	140 <__libc_free+0x140>  // b.plast
 124:	710014bf 	cmp	w5, #0x5
 128:	54000601 	b.ne	1e8 <__libc_free+0x1e8>  // b.any
 12c:	b85fc085 	ldur	w5, [x4, #-4]
 130:	f10010bf 	cmp	x5, #0x4
 134:	540005a9 	b.ls	1e8 <__libc_free+0x1e8>  // b.plast
 138:	385fb086 	ldurb	w6, [x4, #-5]
 13c:	35000566 	cbnz	w6, 1e8 <__libc_free+0x1e8>
 140:	cb000086 	sub	x6, x4, x0
 144:	eb0500df 	cmp	x6, x5
 148:	54000503 	b.cc	1e8 <__libc_free+0x1e8>  // b.lo, b.ul, b.last
 14c:	cb050084 	sub	x4, x4, x5
 150:	39400084 	ldrb	w4, [x4]
 154:	350004a4 	cbnz	w4, 1e8 <__libc_free+0x1e8>
 158:	38626862 	ldrb	w2, [x3, x2]
 15c:	35000462 	cbnz	w2, 1e8 <__libc_free+0x1e8>
 160:	52800046 	mov	w6, #0x2                   	// #2
 164:	52800025 	mov	w5, #0x1                   	// #1
 168:	1ac820c6 	lsl	w6, w6, w8
 16c:	90000007 	adrp	x7, 0 <__libc>
			16c: R_AARCH64_ADR_PREL_PG_HI21	__libc
 170:	510004c6 	sub	w6, w6, #0x1
 174:	910000e7 	add	x7, x7, #0x0
			174: R_AARCH64_ADD_ABS_LO12_NC	__libc
 178:	12800002 	mov	w2, #0xffffffff            	// #-1
 17c:	1ac120a5 	lsl	w5, w5, w1
 180:	381fd002 	sturb	w2, [x0, #-3]
 184:	781fe01f 	sturh	wzr, [x0, #-2]
 188:	b9401e64 	ldr	w4, [x19, #28]
 18c:	b9401a60 	ldr	w0, [x19, #24]
 190:	2a000080 	orr	w0, w4, w0
 194:	6a0000bf 	tst	w5, w0
 198:	54000281 	b.ne	1e8 <__libc_free+0x1e8>  // b.any
 19c:	34000324 	cbz	w4, 200 <__libc_free+0x200>
 1a0:	0b0000a0 	add	w0, w5, w0
 1a4:	6b06001f 	cmp	w0, w6
 1a8:	540002c0 	b.eq	200 <__libc_free+0x200>  // b.none
 1ac:	39400ce0 	ldrb	w0, [x7, #3]
 1b0:	0b0400a2 	add	w2, w5, w4
 1b4:	72001c1f 	tst	w0, #0xff
 1b8:	540001c0 	b.eq	1f0 <__libc_free+0x1f0>  // b.none
 1bc:	91007260 	add	x0, x19, #0x1c
 1c0:	885ffc03 	ldaxr	w3, [x0]
 1c4:	6b03009f 	cmp	w4, w3
 1c8:	54000181 	b.ne	1f8 <__libc_free+0x1f8>  // b.any
 1cc:	8803fc02 	stlxr	w3, w2, [x0]
 1d0:	35ffff83 	cbnz	w3, 1c0 <__libc_free+0x1c0>
 1d4:	a8c34ffe 	ldp	x30, x19, [sp], #48
 1d8:	d65f03c0 	ret
 1dc:	927a1444 	and	x4, x2, #0xfc0
 1e0:	f13f009f 	cmp	x4, #0xfc0
 1e4:	54fff740 	b.eq	cc <__libc_free+0xcc>  // b.none
 1e8:	a90157f4 	stp	x20, x21, [sp, #16]
 1ec:	d4207d00 	brk	#0x3e8
 1f0:	b9001e62 	str	w2, [x19, #28]
 1f4:	17fffff8 	b	1d4 <__libc_free+0x1d4>
 1f8:	d5033bbf 	dmb	ish
 1fc:	17ffffe3 	b	188 <__libc_free+0x188>
 200:	90000000 	adrp	x0, 0 <__libc>
			200: R_AARCH64_ADR_PREL_PG_HI21	__libc
 204:	91000000 	add	x0, x0, #0x0
			204: R_AARCH64_ADD_ABS_LO12_NC	__libc
 208:	a90157f4 	stp	x20, x21, [sp, #16]
 20c:	90000014 	adrp	x20, 0 <__malloc_lock>
			20c: R_AARCH64_ADR_PREL_PG_HI21	__malloc_lock
 210:	39400c00 	ldrb	w0, [x0, #3]
 214:	72001c1f 	tst	w0, #0xff
 218:	54000141 	b.ne	240 <__libc_free+0x240>  // b.any
 21c:	aa1303e0 	mov	x0, x19
 220:	94000000 	bl	0 <__libc_free>
			220: R_AARCH64_CALL26	.text.nontrivial_free
 224:	b9400282 	ldr	w2, [x20]
			224: R_AARCH64_LDST32_ABS_LO12_NC	__malloc_lock
 228:	aa0103f3 	mov	x19, x1
 22c:	aa0003f4 	mov	x20, x0
 230:	37f80122 	tbnz	w2, #31, 254 <__libc_free+0x254>
 234:	b5000193 	cbnz	x19, 264 <__libc_free+0x264>
 238:	a94157f4 	ldp	x20, x21, [sp, #16]
 23c:	17ffffe6 	b	1d4 <__libc_free+0x1d4>
 240:	91000280 	add	x0, x20, #0x0
			240: R_AARCH64_ADD_ABS_LO12_NC	__malloc_lock
 244:	b9002fe1 	str	w1, [sp, #44]
 248:	94000000 	bl	0 <__lock>
			248: R_AARCH64_CALL26	__lock
 24c:	b9402fe1 	ldr	w1, [sp, #44]
 250:	17fffff3 	b	21c <__libc_free+0x21c>
 254:	90000000 	adrp	x0, 0 <__malloc_lock>
			254: R_AARCH64_ADR_PREL_PG_HI21	__malloc_lock
 258:	91000000 	add	x0, x0, #0x0
			258: R_AARCH64_ADD_ABS_LO12_NC	__malloc_lock
 25c:	94000000 	bl	0 <__unlock>
			25c: R_AARCH64_CALL26	__unlock
 260:	17fffff5 	b	234 <__libc_free+0x234>
 264:	94000000 	bl	0 <___errno_location>
			264: R_AARCH64_CALL26	___errno_location
 268:	aa0003f5 	mov	x21, x0
 26c:	aa1303e1 	mov	x1, x19
 270:	aa1403e0 	mov	x0, x20
 274:	b94002b3 	ldr	w19, [x21]
 278:	94000000 	bl	0 <munmap>
			278: R_AARCH64_CALL26	munmap
 27c:	b90002b3 	str	w19, [x21]
 280:	a94157f4 	ldp	x20, x21, [sp, #16]
 284:	17ffffd4 	b	1d4 <__libc_free+0x1d4>
 288:	d4207d00 	brk	#0x3e8
 28c:	d65f03c0 	ret

Disassembly of section .text.malloc_trim:

0000000000000000 <malloc_trim>:
   0:	a9bc4ffe 	stp	x30, x19, [sp, #-64]!
   4:	a90157f4 	stp	x20, x21, [sp, #16]
   8:	90000014 	adrp	x20, 0 <__libc>
			8: R_AARCH64_ADR_PREL_PG_HI21	__libc
   c:	91000294 	add	x20, x20, #0x0
			c: R_AARCH64_ADD_ABS_LO12_NC	__libc
  10:	a9025ff6 	stp	x22, x23, [sp, #32]
  14:	a90367f8 	stp	x24, x25, [sp, #48]
  18:	94000000 	bl	0 <___errno_location>
			18: R_AARCH64_CALL26	___errno_location
  1c:	aa0003f6 	mov	x22, x0
  20:	39400e80 	ldrb	w0, [x20, #3]
  24:	b94002d7 	ldr	w23, [x22]
  28:	72001c1f 	tst	w0, #0xff
  2c:	540000e1 	b.ne	48 <malloc_trim+0x48>  // b.any
  30:	90000015 	adrp	x21, 0 <__malloc_context>
			30: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
  34:	910002b5 	add	x21, x21, #0x0
			34: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
  38:	9100a2b9 	add	x25, x21, #0x28
  3c:	aa1503f8 	mov	x24, x21
  40:	52800013 	mov	w19, #0x0                   	// #0
  44:	1400000e 	b	7c <malloc_trim+0x7c>
  48:	90000000 	adrp	x0, 0 <__malloc_lock>
			48: R_AARCH64_ADR_PREL_PG_HI21	__malloc_lock
  4c:	91000000 	add	x0, x0, #0x0
			4c: R_AARCH64_ADD_ABS_LO12_NC	__malloc_lock
  50:	94000000 	bl	0 <__lock>
			50: R_AARCH64_CALL26	__lock
  54:	17fffff7 	b	30 <malloc_trim+0x30>
  58:	a9000842 	stp	x2, x2, [x2]
  5c:	f9000aa2 	str	x2, [x21, #16]
  60:	94000000 	bl	0 <munmap>
			60: R_AARCH64_CALL26	munmap
  64:	7100001f 	cmp	w0, #0x0
  68:	1a9f17e0 	cset	w0, eq	// eq = none
  6c:	2a000273 	orr	w19, w19, w0
  70:	91002318 	add	x24, x24, #0x8
  74:	eb19031f 	cmp	x24, x25
  78:	54000260 	b.eq	c4 <malloc_trim+0xc4>  // b.none
  7c:	f940eb02 	ldr	x2, [x24, #464]
  80:	b4ffff82 	cbz	x2, 70 <malloc_trim+0x70>
  84:	f900eb1f 	str	xzr, [x24, #464]
  88:	a9007c5f 	stp	xzr, xzr, [x2]
  8c:	f9400840 	ldr	x0, [x2, #16]
  90:	a9017c5f 	stp	xzr, xzr, [x2, #16]
  94:	f9400aa3 	ldr	x3, [x21, #16]
  98:	f9401041 	ldr	x1, [x2, #32]
  9c:	f900105f 	str	xzr, [x2, #32]
  a0:	9274cc21 	and	x1, x1, #0xfffffffffffff000
  a4:	b4fffda3 	cbz	x3, 58 <malloc_trim+0x58>
  a8:	f9000443 	str	x3, [x2, #8]
  ac:	f9400063 	ldr	x3, [x3]
  b0:	f9000043 	str	x3, [x2]
  b4:	f9000462 	str	x2, [x3, #8]
  b8:	f9400443 	ldr	x3, [x2, #8]
  bc:	f9000062 	str	x2, [x3]
  c0:	17ffffe8 	b	60 <malloc_trim+0x60>
  c4:	90000019 	adrp	x25, 0 <__malloc_context>
			c4: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context+0x50
  c8:	910742b5 	add	x21, x21, #0x1d0
  cc:	91000339 	add	x25, x25, #0x0
			cc: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context+0x50
  d0:	52800058 	mov	w24, #0x2                   	// #2
  d4:	14000057 	b	230 <malloc_trim+0x230>
  d8:	f9400400 	ldr	x0, [x0, #8]
  dc:	eb00007f 	cmp	x3, x0
  e0:	54000180 	b.eq	110 <malloc_trim+0x110>  // b.none
  e4:	f9401001 	ldr	x1, [x0, #32]
  e8:	362fff81 	tbz	w1, #5, d8 <malloc_trim+0xd8>
  ec:	b9401802 	ldr	w2, [x0, #24]
  f0:	d3401021 	ubfx	x1, x1, #0, #5
  f4:	b9401c04 	ldr	w4, [x0, #28]
  f8:	1ac12301 	lsl	w1, w24, w1
  fc:	51000421 	sub	w1, w1, #0x1
 100:	2a040042 	orr	w2, w2, w4
 104:	6b01005f 	cmp	w2, w1
 108:	54fffe81 	b.ne	d8 <malloc_trim+0xd8>  // b.any
 10c:	14000003 	b	118 <malloc_trim+0x118>
 110:	f9401001 	ldr	x1, [x0, #32]
 114:	362808c1 	tbz	w1, #5, 22c <malloc_trim+0x22c>
 118:	f9401001 	ldr	x1, [x0, #32]
 11c:	b9401802 	ldr	w2, [x0, #24]
 120:	b9401c03 	ldr	w3, [x0, #28]
 124:	d3401021 	ubfx	x1, x1, #0, #5
 128:	2a030042 	orr	w2, w2, w3
 12c:	1ac12301 	lsl	w1, w24, w1
 130:	51000421 	sub	w1, w1, #0x1
 134:	6b01005f 	cmp	w2, w1
 138:	540007a1 	b.ne	22c <malloc_trim+0x22c>  // b.any
 13c:	f9400401 	ldr	x1, [x0, #8]
 140:	eb01001f 	cmp	x0, x1
 144:	540002c0 	b.eq	19c <malloc_trim+0x19c>  // b.none
 148:	f9400002 	ldr	x2, [x0]
 14c:	f9000441 	str	x1, [x2, #8]
 150:	f9400002 	ldr	x2, [x0]
 154:	f9000022 	str	x2, [x1]
 158:	f9400321 	ldr	x1, [x25]
 15c:	eb01001f 	cmp	x0, x1
 160:	54000180 	b.eq	190 <malloc_trim+0x190>  // b.none
 164:	a9007c1f 	stp	xzr, xzr, [x0]
 168:	f9400325 	ldr	x5, [x25]
 16c:	b4000065 	cbz	x5, 178 <malloc_trim+0x178>
 170:	b94018a1 	ldr	w1, [x5, #24]
 174:	34000181 	cbz	w1, 1a4 <malloc_trim+0x1a4>
 178:	94000000 	bl	0 <malloc_trim>
			178: R_AARCH64_CALL26	.text.free_group
 17c:	b50004e1 	cbnz	x1, 218 <malloc_trim+0x218>
 180:	f9400323 	ldr	x3, [x25]
 184:	b4000543 	cbz	x3, 22c <malloc_trim+0x22c>
 188:	aa0303e0 	mov	x0, x3
 18c:	17ffffd6 	b	e4 <malloc_trim+0xe4>
 190:	f9400401 	ldr	x1, [x0, #8]
 194:	f9000321 	str	x1, [x25]
 198:	17fffff3 	b	164 <malloc_trim+0x164>
 19c:	f900033f 	str	xzr, [x25]
 1a0:	17fffff1 	b	164 <malloc_trim+0x164>
 1a4:	b94018a1 	ldr	w1, [x5, #24]
 1a8:	350001e1 	cbnz	w1, 1e4 <malloc_trim+0x1e4>
 1ac:	f94008a2 	ldr	x2, [x5, #16]
 1b0:	910070a3 	add	x3, x5, #0x1c
 1b4:	39400e81 	ldrb	w1, [x20, #3]
 1b8:	f9400446 	ldr	x6, [x2, #8]
 1bc:	d34010c6 	ubfx	x6, x6, #0, #5
 1c0:	1ac62306 	lsl	w6, w24, w6
 1c4:	510004c8 	sub	w8, w6, #0x1
 1c8:	4b0603e6 	neg	w6, w6
 1cc:	72001c3f 	tst	w1, #0xff
 1d0:	540000e1 	b.ne	1ec <malloc_trim+0x1ec>  // b.any
 1d4:	b9401ca7 	ldr	w7, [x5, #28]
 1d8:	0a0600e6 	and	w6, w7, w6
 1dc:	b9001ca6 	str	w6, [x5, #28]
 1e0:	1400000b 	b	20c <malloc_trim+0x20c>
 1e4:	d4207d00 	brk	#0x3e8
 1e8:	d5033bbf 	dmb	ish
 1ec:	b9401ca4 	ldr	w4, [x5, #28]
 1f0:	2a0403e7 	mov	w7, w4
 1f4:	0a060082 	and	w2, w4, w6
 1f8:	885ffc61 	ldaxr	w1, [x3]
 1fc:	6b01009f 	cmp	w4, w1
 200:	54ffff41 	b.ne	1e8 <malloc_trim+0x1e8>  // b.any
 204:	8801fc62 	stlxr	w1, w2, [x3]
 208:	35ffff81 	cbnz	w1, 1f8 <malloc_trim+0x1f8>
 20c:	0a070101 	and	w1, w8, w7
 210:	b90018a1 	str	w1, [x5, #24]
 214:	17ffffd9 	b	178 <malloc_trim+0x178>
 218:	94000000 	bl	0 <munmap>
			218: R_AARCH64_CALL26	munmap
 21c:	7100001f 	cmp	w0, #0x0
 220:	1a9f17e0 	cset	w0, eq	// eq = none
 224:	2a000273 	orr	w19, w19, w0
 228:	17ffffd6 	b	180 <malloc_trim+0x180>
 22c:	91002339 	add	x25, x25, #0x8
 230:	eb15033f 	cmp	x25, x21
 234:	54fffa61 	b.ne	180 <malloc_trim+0x180>  // b.any
 238:	90000001 	adrp	x1, 0 <__malloc_lock>
			238: R_AARCH64_ADR_PREL_PG_HI21	__malloc_lock
 23c:	91000020 	add	x0, x1, #0x0
			23c: R_AARCH64_ADD_ABS_LO12_NC	__malloc_lock
 240:	b9400021 	ldr	w1, [x1]
			240: R_AARCH64_LDST32_ABS_LO12_NC	__malloc_lock
 244:	37f80101 	tbnz	w1, #31, 264 <malloc_trim+0x264>
 248:	b90002d7 	str	w23, [x22]
 24c:	2a1303e0 	mov	w0, w19
 250:	a94157f4 	ldp	x20, x21, [sp, #16]
 254:	a9425ff6 	ldp	x22, x23, [sp, #32]
 258:	a94367f8 	ldp	x24, x25, [sp, #48]
 25c:	a8c44ffe 	ldp	x30, x19, [sp], #64
 260:	d65f03c0 	ret
 264:	94000000 	bl	0 <__unlock>
			264: R_AARCH64_CALL26	__unlock
 268:	17fffff8 	b	248 <malloc_trim+0x248>

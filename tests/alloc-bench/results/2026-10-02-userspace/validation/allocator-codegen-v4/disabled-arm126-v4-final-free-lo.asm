
/Users/alex/code/vinix/third_party/useralloc-libc/build/musl/aarch64/ff88d5a4ea1a8cd33bb50f215311de4767a7deaec49201e25be59abaed06a69c/objects/obj/src/malloc/mallocng/free.lo:     file format elf64-littleaarch64


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
  44:	54000e4c 	b.gt	20c <nontrivial_free+0x20c>
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
  68:	b5000d24 	cbnz	x4, 20c <nontrivial_free+0x20c>
  6c:	f9400004 	ldr	x4, [x0]
  70:	b5000ce4 	cbnz	x4, 20c <nontrivial_free+0x20c>
  74:	b40011a3 	cbz	x3, 2a8 <nontrivial_free+0x2a8>
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
  a0:	540010a1 	b.ne	2b4 <nontrivial_free+0x2b4>  // b.any
  a4:	b9401c02 	ldr	w2, [x0, #28]
  a8:	2a010041 	orr	w1, w2, w1
  ac:	b9001c01 	str	w1, [x0, #28]
  b0:	d2800000 	mov	x0, #0x0                   	// #0
  b4:	d2800001 	mov	x1, #0x0                   	// #0
  b8:	d65f03c0 	ret
  bc:	362ffc03 	tbz	w3, #5, 3c <nontrivial_free+0x3c>
  c0:	f9400407 	ldr	x7, [x0, #8]
  c4:	7100bcbf 	cmp	w5, #0x2f
  c8:	54000a0c 	b.gt	208 <nontrivial_free+0x208>
  cc:	f240107f 	tst	x3, #0x1f
  d0:	54000401 	b.ne	150 <nontrivial_free+0x150>  // b.any
  d4:	f13ffc7f 	cmp	x3, #0xfff
  d8:	54000129 	b.ls	fc <nontrivial_free+0xfc>  // b.plast
  dc:	90000006 	adrp	x6, 0 <__malloc_size_classes>
			dc: R_AARCH64_ADR_PREL_PG_HI21	__malloc_size_classes
  e0:	910000c6 	add	x6, x6, #0x0
			e0: R_AARCH64_ADD_ABS_LO12_NC	__malloc_size_classes
  e4:	9274cc62 	and	x2, x3, #0xfffffffffffff000
  e8:	d1004042 	sub	x2, x2, #0x10
  ec:	7865d8c3 	ldrh	w3, [x6, w5, sxtw #1]
  f0:	d37c3c63 	ubfiz	x3, x3, #4, #16
  f4:	eb03005f 	cmp	x2, x3
  f8:	54000302 	b.cs	158 <nontrivial_free+0x158>  // b.hs, b.nlast
  fc:	b4000287 	cbz	x7, 14c <nontrivial_free+0x14c>
 100:	93407ca5 	sxtw	x5, w5
 104:	90000006 	adrp	x6, 0 <__malloc_context>
			104: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
 108:	910028a2 	add	x2, x5, #0xa
 10c:	910000c1 	add	x1, x6, #0x0
			10c: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 110:	f8627821 	ldr	x1, [x1, x2, lsl #3]
 114:	eb07001f 	cmp	x0, x7
 118:	54000420 	b.eq	19c <nontrivial_free+0x19c>  // b.none
 11c:	f9400004 	ldr	x4, [x0]
 120:	910000c2 	add	x2, x6, #0x0
			120: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 124:	910028a3 	add	x3, x5, #0xa
 128:	f9000487 	str	x7, [x4, #8]
 12c:	f9400004 	ldr	x4, [x0]
 130:	f90000e4 	str	x4, [x7]
 134:	f8637844 	ldr	x4, [x2, x3, lsl #3]
 138:	eb04001f 	cmp	x0, x4
 13c:	540006a0 	b.eq	210 <nontrivial_free+0x210>  // b.none
 140:	a9007c1f 	stp	xzr, xzr, [x0]
 144:	eb01001f 	cmp	x0, x1
 148:	540006a0 	b.eq	21c <nontrivial_free+0x21c>  // b.none
 14c:	14000000 	b	0 <nontrivial_free>
			14c: R_AARCH64_JUMP26	.text.free_group
 150:	f13ffc7f 	cmp	x3, #0xfff
 154:	54fffd49 	b.ls	fc <nontrivial_free+0xfc>  // b.plast
 158:	eb07001f 	cmp	x0, x7
 15c:	54000100 	b.eq	17c <nontrivial_free+0x17c>  // b.none
 160:	b4ffff67 	cbz	x7, 14c <nontrivial_free+0x14c>
 164:	93407ca5 	sxtw	x5, w5
 168:	90000006 	adrp	x6, 0 <__malloc_context>
			168: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
 16c:	910028a2 	add	x2, x5, #0xa
 170:	910000c1 	add	x1, x6, #0x0
			170: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 174:	f8627821 	ldr	x1, [x1, x2, lsl #3]
 178:	17ffffe9 	b	11c <nontrivial_free+0x11c>
 17c:	51001ca2 	sub	w2, w5, #0x7
 180:	71007c5f 	cmp	w2, #0x1f
 184:	54000149 	b.ls	1ac <nontrivial_free+0x1ac>  // b.plast
 188:	93407ca5 	sxtw	x5, w5
 18c:	90000006 	adrp	x6, 0 <__malloc_context>
			18c: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
 190:	910000c1 	add	x1, x6, #0x0
			190: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 194:	910028a2 	add	x2, x5, #0xa
 198:	f8627821 	ldr	x1, [x1, x2, lsl #3]
 19c:	910000c2 	add	x2, x6, #0x0
			19c: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 1a0:	910028a3 	add	x3, x5, #0xa
 1a4:	f823785f 	str	xzr, [x2, x3, lsl #3]
 1a8:	17ffffe6 	b	140 <nontrivial_free+0x140>
 1ac:	90000006 	adrp	x6, 0 <__malloc_context>
			1ac: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
 1b0:	910000c3 	add	x3, x6, #0x0
			1b0: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 1b4:	8b22c062 	add	x2, x3, w2, sxtw
 1b8:	93407ca5 	sxtw	x5, w5
 1bc:	394e6042 	ldrb	w2, [x2, #920]
 1c0:	71018c5f 	cmp	w2, #0x63
 1c4:	54fffe69 	b.ls	190 <nontrivial_free+0x190>  // b.plast
 1c8:	8b050c63 	add	x3, x3, x5, lsl #3
 1cc:	11000509 	add	w9, w8, #0x1
 1d0:	d37d1522 	ubfiz	x2, x9, #3, #6
 1d4:	f940fc63 	ldr	x3, [x3, #504]
 1d8:	8b090042 	add	x2, x2, x9
 1dc:	eb02007f 	cmp	x3, x2
 1e0:	54000063 	b.cc	1ec <nontrivial_free+0x1ec>  // b.lo, b.ul, b.last
 1e4:	71004d3f 	cmp	w9, #0x13
 1e8:	54fffd4d 	b.le	190 <nontrivial_free+0x190>
 1ec:	35fff524 	cbnz	w4, 90 <nontrivial_free+0x90>
 1f0:	910000c6 	add	x6, x6, #0x0
			1f0: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 1f4:	910028a5 	add	x5, x5, #0xa
 1f8:	f86578c2 	ldr	x2, [x6, x5, lsl #3]
 1fc:	eb07005f 	cmp	x2, x7
 200:	54fff480 	b.eq	90 <nontrivial_free+0x90>  // b.none
 204:	14000002 	b	20c <nontrivial_free+0x20c>
 208:	b4fffa27 	cbz	x7, 14c <nontrivial_free+0x14c>
 20c:	d4207d00 	brk	#0x3e8
 210:	f9400404 	ldr	x4, [x0, #8]
 214:	f8237844 	str	x4, [x2, x3, lsl #3]
 218:	17ffffca 	b	140 <nontrivial_free+0x140>
 21c:	910000c1 	add	x1, x6, #0x0
			21c: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 220:	910028a5 	add	x5, x5, #0xa
 224:	f8657825 	ldr	x5, [x1, x5, lsl #3]
 228:	b4fff925 	cbz	x5, 14c <nontrivial_free+0x14c>
 22c:	b94018a1 	ldr	w1, [x5, #24]
 230:	35fffee1 	cbnz	w1, 20c <nontrivial_free+0x20c>
 234:	f94008a1 	ldr	x1, [x5, #16]
 238:	90000002 	adrp	x2, 0 <__libc>
			238: R_AARCH64_ADR_PREL_PG_HI21	__libc
 23c:	91000042 	add	x2, x2, #0x0
			23c: R_AARCH64_ADD_ABS_LO12_NC	__libc
 240:	52800046 	mov	w6, #0x2                   	// #2
 244:	910070a3 	add	x3, x5, #0x1c
 248:	f9400421 	ldr	x1, [x1, #8]
 24c:	39400c42 	ldrb	w2, [x2, #3]
 250:	d3401021 	ubfx	x1, x1, #0, #5
 254:	1ac120c6 	lsl	w6, w6, w1
 258:	510004c8 	sub	w8, w6, #0x1
 25c:	4b0603e6 	neg	w6, w6
 260:	72001c5f 	tst	w2, #0xff
 264:	540000c1 	b.ne	27c <nontrivial_free+0x27c>  // b.any
 268:	b9401ca7 	ldr	w7, [x5, #28]
 26c:	0a0600e6 	and	w6, w7, w6
 270:	b9001ca6 	str	w6, [x5, #28]
 274:	1400000a 	b	29c <nontrivial_free+0x29c>
 278:	d5033bbf 	dmb	ish
 27c:	b9401ca4 	ldr	w4, [x5, #28]
 280:	2a0403e7 	mov	w7, w4
 284:	0a060082 	and	w2, w4, w6
 288:	885ffc61 	ldaxr	w1, [x3]
 28c:	6b01009f 	cmp	w4, w1
 290:	54ffff41 	b.ne	278 <nontrivial_free+0x278>  // b.any
 294:	8801fc62 	stlxr	w1, w2, [x3]
 298:	35ffff81 	cbnz	w1, 288 <nontrivial_free+0x288>
 29c:	0a070101 	and	w1, w8, w7
 2a0:	b90018a1 	str	w1, [x5, #24]
 2a4:	17ffffaa 	b	14c <nontrivial_free+0x14c>
 2a8:	a9000000 	stp	x0, x0, [x0]
 2ac:	f8257840 	str	x0, [x2, x5, lsl #3]
 2b0:	17ffff78 	b	90 <nontrivial_free+0x90>
 2b4:	91007002 	add	x2, x0, #0x1c
 2b8:	885ffc40 	ldaxr	w0, [x2]
 2bc:	2a010000 	orr	w0, w0, w1
 2c0:	8803fc40 	stlxr	w3, w0, [x2]
 2c4:	35ffffa3 	cbnz	w3, 2b8 <nontrivial_free+0x2b8>
 2c8:	17ffff7a 	b	b0 <nontrivial_free+0xb0>

Disassembly of section .text.free_group:

0000000000000000 <free_group>:
   0:	a9be4ffe 	stp	x30, x19, [sp, #-32]!
   4:	aa0003f3 	mov	x19, x0
   8:	f9000bf4 	str	x20, [sp, #16]
   c:	f9401000 	ldr	x0, [x0, #32]
  10:	53062c02 	ubfx	w2, w0, #6, #6
  14:	7100bc5f 	cmp	w2, #0x2f
  18:	5400046d 	b.le	a4 <free_group+0xa4>
  1c:	f13ffc1f 	cmp	x0, #0xfff
  20:	540006c9 	b.ls	f8 <free_group+0xf8>  // b.plast
  24:	90000014 	adrp	x20, 0 <__malloc_context>
			24: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
  28:	91000280 	add	x0, x20, #0x0
			28: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
  2c:	394ee003 	ldrb	w3, [x0, #952]
  30:	11000461 	add	w1, w3, #0x1
  34:	12001c21 	and	w1, w1, #0xff
  38:	7103fc7f 	cmp	w3, #0xff
  3c:	540004c0 	b.eq	d4 <free_group+0xd4>  // b.none
  40:	91000280 	add	x0, x20, #0x0
			40: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
  44:	51001c42 	sub	w2, w2, #0x7
  48:	390ee001 	strb	w1, [x0, #952]
  4c:	71007c5f 	cmp	w2, #0x1f
  50:	54000068 	b.hi	5c <free_group+0x5c>  // b.pmore
  54:	8b22c002 	add	x2, x0, w2, sxtw
  58:	390de041 	strb	w1, [x2, #888]
  5c:	f9401261 	ldr	x1, [x19, #32]
  60:	f9400a60 	ldr	x0, [x19, #16]
  64:	9274cc21 	and	x1, x1, #0xfffffffffffff000
  68:	91000294 	add	x20, x20, #0x0
			68: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
  6c:	a9007e7f 	stp	xzr, xzr, [x19]
  70:	a9017e7f 	stp	xzr, xzr, [x19, #16]
  74:	f9400a82 	ldr	x2, [x20, #16]
  78:	f900127f 	str	xzr, [x19, #32]
  7c:	b4000bc2 	cbz	x2, 1f4 <free_group+0x1f4>
  80:	f9000662 	str	x2, [x19, #8]
  84:	f9400042 	ldr	x2, [x2]
  88:	f9000262 	str	x2, [x19]
  8c:	f9000453 	str	x19, [x2, #8]
  90:	f9400662 	ldr	x2, [x19, #8]
  94:	f9000053 	str	x19, [x2]
  98:	f9400bf4 	ldr	x20, [sp, #16]
  9c:	a8c24ffe 	ldp	x30, x19, [sp], #32
  a0:	d65f03c0 	ret
  a4:	d37d1443 	ubfiz	x3, x2, #3, #6
  a8:	90000001 	adrp	x1, 0 <__malloc_context>
			a8: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
  ac:	9107c063 	add	x3, x3, #0x1f0
  b0:	91000021 	add	x1, x1, #0x0
			b0: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
  b4:	8b030021 	add	x1, x1, x3
  b8:	92401000 	and	x0, x0, #0x1f
  bc:	91000400 	add	x0, x0, #0x1
  c0:	f9400423 	ldr	x3, [x1, #8]
  c4:	cb000060 	sub	x0, x3, x0
  c8:	f9000420 	str	x0, [x1, #8]
  cc:	f9401260 	ldr	x0, [x19, #32]
  d0:	17ffffd3 	b	1c <free_group+0x1c>
  d4:	90000001 	adrp	x1, 0 <__malloc_context>
			d4: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context+0x378
  d8:	910e6000 	add	x0, x0, #0x398
  dc:	91000021 	add	x1, x1, #0x0
			dc: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context+0x378
  e0:	14000002 	b	e8 <free_group+0xe8>
  e4:	3800143f 	strb	wzr, [x1], #1
  e8:	eb00003f 	cmp	x1, x0
  ec:	54ffffc1 	b.ne	e4 <free_group+0xe4>  // b.any
  f0:	52800021 	mov	w1, #0x1                   	// #1
  f4:	17ffffd3 	b	40 <free_group+0x40>
  f8:	f9400a62 	ldr	x2, [x19, #16]
  fc:	f2400c5f 	tst	x2, #0xf
 100:	54000781 	b.ne	1f0 <free_group+0x1f0>  // b.any
 104:	385fc040 	ldurb	w0, [x2, #-4]
 108:	385fd041 	ldurb	w1, [x2, #-3]
 10c:	785fe046 	ldurh	w6, [x2, #-2]
 110:	12001021 	and	w1, w1, #0x1f
 114:	340000c0 	cbz	w0, 12c <free_group+0x12c>
 118:	350006c6 	cbnz	w6, 1f0 <free_group+0x1f0>
 11c:	b85f8046 	ldur	w6, [x2, #-8]
 120:	529fffe0 	mov	w0, #0xffff                	// #65535
 124:	6b0000df 	cmp	w6, w0
 128:	5400064d 	b.le	1f0 <free_group+0x1f0>
 12c:	531c6cc3 	lsl	w3, w6, #4
 130:	928001e0 	mov	x0, #0xfffffffffffffff0    	// #-16
 134:	cb23c000 	sub	x0, x0, w3, sxtw
 138:	8b000044 	add	x4, x2, x0
 13c:	f8606840 	ldr	x0, [x2, x0]
 140:	f9400803 	ldr	x3, [x0, #16]
 144:	eb03009f 	cmp	x4, x3
 148:	54000541 	b.ne	1f0 <free_group+0x1f0>  // b.any
 14c:	f9401003 	ldr	x3, [x0, #32]
 150:	12001064 	and	w4, w3, #0x1f
 154:	6b04003f 	cmp	w1, w4
 158:	540004cc 	b.gt	1f0 <free_group+0x1f0>
 15c:	b9401804 	ldr	w4, [x0, #24]
 160:	1ac12484 	lsr	w4, w4, w1
 164:	37000464 	tbnz	w4, #0, 1f0 <free_group+0x1f0>
 168:	b9401c04 	ldr	w4, [x0, #28]
 16c:	1ac12484 	lsr	w4, w4, w1
 170:	37000404 	tbnz	w4, #0, 1f0 <free_group+0x1f0>
 174:	9274cc04 	and	x4, x0, #0xfffffffffffff000
 178:	90000014 	adrp	x20, 0 <__malloc_context>
			178: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
 17c:	f9400285 	ldr	x5, [x20]
			17c: R_AARCH64_LDST64_ABS_LO12_NC	__malloc_context
 180:	f9400084 	ldr	x4, [x4]
 184:	eb05009f 	cmp	x4, x5
 188:	54000341 	b.ne	1f0 <free_group+0x1f0>  // b.any
 18c:	53062c64 	ubfx	w4, w3, #6, #6
 190:	7100bc9f 	cmp	w4, #0x2f
 194:	54000288 	b.hi	1e4 <free_group+0x1e4>  // b.pmore
 198:	90000005 	adrp	x5, 0 <__malloc_size_classes>
			198: R_AARCH64_ADR_PREL_PG_HI21	__malloc_size_classes
 19c:	910000a5 	add	x5, x5, #0x0
			19c: R_AARCH64_ADD_ABS_LO12_NC	__malloc_size_classes
 1a0:	7864d8a4 	ldrh	w4, [x5, w4, sxtw #1]
 1a4:	1b047c25 	mul	w5, w1, w4
 1a8:	6b0500df 	cmp	w6, w5
 1ac:	5400022b 	b.lt	1f0 <free_group+0x1f0>  // b.tstop
 1b0:	0b050084 	add	w4, w4, w5
 1b4:	6b0400df 	cmp	w6, w4
 1b8:	540001ca 	b.ge	1f0 <free_group+0x1f0>  // b.tcont
 1bc:	f13ffc7f 	cmp	x3, #0xfff
 1c0:	540000c9 	b.ls	1d8 <free_group+0x1d8>  // b.plast
 1c4:	9274cc63 	and	x3, x3, #0xfffffffffffff000
 1c8:	d344fc63 	lsr	x3, x3, #4
 1cc:	d1000463 	sub	x3, x3, #0x1
 1d0:	eb26c07f 	cmp	x3, w6, sxtw
 1d4:	540000e3 	b.cc	1f0 <free_group+0x1f0>  // b.lo, b.ul, b.last
 1d8:	f900005f 	str	xzr, [x2]
 1dc:	94000000 	bl	0 <free_group>
			1dc: R_AARCH64_CALL26	.text.nontrivial_free
 1e0:	17ffffa2 	b	68 <free_group+0x68>
 1e4:	927a1464 	and	x4, x3, #0xfc0
 1e8:	f13f009f 	cmp	x4, #0xfc0
 1ec:	54fffe80 	b.eq	1bc <free_group+0x1bc>  // b.none
 1f0:	d4207d00 	brk	#0x3e8
 1f4:	a9004e73 	stp	x19, x19, [x19]
 1f8:	f9000a93 	str	x19, [x20, #16]
 1fc:	17ffffa7 	b	98 <free_group+0x98>

Disassembly of section .text.__libc_free:

0000000000000000 <__libc_free>:
   0:	b4001440 	cbz	x0, 288 <__libc_free+0x288>
   4:	f2400c1f 	tst	x0, #0xf
   8:	540013e1 	b.ne	284 <__libc_free+0x284>  // b.any
   c:	385fc002 	ldurb	w2, [x0, #-4]
  10:	385fd006 	ldurb	w6, [x0, #-3]
  14:	785fe005 	ldurh	w5, [x0, #-2]
  18:	120010c1 	and	w1, w6, #0x1f
  1c:	340000c2 	cbz	w2, 34 <__libc_free+0x34>
  20:	35001325 	cbnz	w5, 284 <__libc_free+0x284>
  24:	b85f8005 	ldur	w5, [x0, #-8]
  28:	529fffe2 	mov	w2, #0xffff                	// #65535
  2c:	6b0200bf 	cmp	w5, w2
  30:	540012ad 	b.le	284 <__libc_free+0x284>
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
 218:	54000161 	b.ne	244 <__libc_free+0x244>  // b.any
 21c:	aa1303e0 	mov	x0, x19
 220:	94000000 	bl	0 <__libc_free>
			220: R_AARCH64_CALL26	.text.nontrivial_free
 224:	b9400282 	ldr	w2, [x20]
			224: R_AARCH64_LDST32_ABS_LO12_NC	__malloc_lock
 228:	aa0003f5 	mov	x21, x0
 22c:	aa0103f3 	mov	x19, x1
 230:	91000280 	add	x0, x20, #0x0
			230: R_AARCH64_ADD_ABS_LO12_NC	__malloc_lock
 234:	37f80122 	tbnz	w2, #31, 258 <__libc_free+0x258>
 238:	b5000153 	cbnz	x19, 260 <__libc_free+0x260>
 23c:	a94157f4 	ldp	x20, x21, [sp, #16]
 240:	17ffffe5 	b	1d4 <__libc_free+0x1d4>
 244:	91000280 	add	x0, x20, #0x0
			244: R_AARCH64_ADD_ABS_LO12_NC	__malloc_lock
 248:	b9002fe1 	str	w1, [sp, #44]
 24c:	94000000 	bl	0 <__lock>
			24c: R_AARCH64_CALL26	__lock
 250:	b9402fe1 	ldr	w1, [sp, #44]
 254:	17fffff2 	b	21c <__libc_free+0x21c>
 258:	94000000 	bl	0 <__unlock>
			258: R_AARCH64_CALL26	__unlock
 25c:	17fffff7 	b	238 <__libc_free+0x238>
 260:	94000000 	bl	0 <___errno_location>
			260: R_AARCH64_CALL26	___errno_location
 264:	aa0003f4 	mov	x20, x0
 268:	aa1303e1 	mov	x1, x19
 26c:	aa1503e0 	mov	x0, x21
 270:	b9400293 	ldr	w19, [x20]
 274:	94000000 	bl	0 <munmap>
			274: R_AARCH64_CALL26	munmap
 278:	b9000293 	str	w19, [x20]
 27c:	a94157f4 	ldp	x20, x21, [sp, #16]
 280:	17ffffd5 	b	1d4 <__libc_free+0x1d4>
 284:	d4207d00 	brk	#0x3e8
 288:	d65f03c0 	ret

Disassembly of section .text.malloc_trim:

0000000000000000 <malloc_trim>:
   0:	a9bb4ffe 	stp	x30, x19, [sp, #-80]!
   4:	a90157f4 	stp	x20, x21, [sp, #16]
   8:	a9025ff6 	stp	x22, x23, [sp, #32]
   c:	90000016 	adrp	x22, 0 <__libc>
			c: R_AARCH64_ADR_PREL_PG_HI21	__libc
  10:	a90367f8 	stp	x24, x25, [sp, #48]
  14:	f90023fa 	str	x26, [sp, #64]
  18:	94000000 	bl	0 <___errno_location>
			18: R_AARCH64_CALL26	___errno_location
  1c:	910002c1 	add	x1, x22, #0x0
			1c: R_AARCH64_ADD_ABS_LO12_NC	__libc
  20:	aa0003f7 	mov	x23, x0
  24:	39400c20 	ldrb	w0, [x1, #3]
  28:	b94002f8 	ldr	w24, [x23]
  2c:	72001c1f 	tst	w0, #0xff
  30:	54000101 	b.ne	50 <malloc_trim+0x50>  // b.any
  34:	90000015 	adrp	x21, 0 <__malloc_context>
			34: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
  38:	910002b5 	add	x21, x21, #0x0
			38: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
  3c:	90000014 	adrp	x20, 0 <__malloc_context>
			3c: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context+0x1d0
  40:	9107e2b9 	add	x25, x21, #0x1f8
  44:	91000294 	add	x20, x20, #0x0
			44: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context+0x1d0
  48:	52800013 	mov	w19, #0x0                   	// #0
  4c:	1400000c 	b	7c <malloc_trim+0x7c>
  50:	90000000 	adrp	x0, 0 <__malloc_lock>
			50: R_AARCH64_ADR_PREL_PG_HI21	__malloc_lock
  54:	91000000 	add	x0, x0, #0x0
			54: R_AARCH64_ADD_ABS_LO12_NC	__malloc_lock
  58:	94000000 	bl	0 <__lock>
			58: R_AARCH64_CALL26	__lock
  5c:	17fffff6 	b	34 <malloc_trim+0x34>
  60:	a9000842 	stp	x2, x2, [x2]
  64:	f9000aa2 	str	x2, [x21, #16]
  68:	94000000 	bl	0 <munmap>
			68: R_AARCH64_CALL26	munmap
  6c:	7100001f 	cmp	w0, #0x0
  70:	1a9f17e0 	cset	w0, eq	// eq = none
  74:	2a000273 	orr	w19, w19, w0
  78:	91002294 	add	x20, x20, #0x8
  7c:	eb19029f 	cmp	x20, x25
  80:	54000260 	b.eq	cc <malloc_trim+0xcc>  // b.none
  84:	f9400282 	ldr	x2, [x20]
  88:	b4ffff82 	cbz	x2, 78 <malloc_trim+0x78>
  8c:	f900029f 	str	xzr, [x20]
  90:	a9007c5f 	stp	xzr, xzr, [x2]
  94:	f9400840 	ldr	x0, [x2, #16]
  98:	a9017c5f 	stp	xzr, xzr, [x2, #16]
  9c:	f9400aa3 	ldr	x3, [x21, #16]
  a0:	f9401041 	ldr	x1, [x2, #32]
  a4:	f900105f 	str	xzr, [x2, #32]
  a8:	9274cc21 	and	x1, x1, #0xfffffffffffff000
  ac:	b4fffda3 	cbz	x3, 60 <malloc_trim+0x60>
  b0:	f9000443 	str	x3, [x2, #8]
  b4:	f9400063 	ldr	x3, [x3]
  b8:	f9000043 	str	x3, [x2]
  bc:	f9000462 	str	x2, [x3, #8]
  c0:	f9400443 	ldr	x3, [x2, #8]
  c4:	f9000062 	str	x2, [x3]
  c8:	17ffffe8 	b	68 <malloc_trim+0x68>
  cc:	9000001a 	adrp	x26, 0 <__malloc_context>
			cc: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context+0x50
  d0:	910742b5 	add	x21, x21, #0x1d0
  d4:	9100035a 	add	x26, x26, #0x0
			d4: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context+0x50
  d8:	52800059 	mov	w25, #0x2                   	// #2
  dc:	14000057 	b	238 <malloc_trim+0x238>
  e0:	f9400400 	ldr	x0, [x0, #8]
  e4:	eb00007f 	cmp	x3, x0
  e8:	54000180 	b.eq	118 <malloc_trim+0x118>  // b.none
  ec:	f9401001 	ldr	x1, [x0, #32]
  f0:	362fff81 	tbz	w1, #5, e0 <malloc_trim+0xe0>
  f4:	b9401802 	ldr	w2, [x0, #24]
  f8:	d3401021 	ubfx	x1, x1, #0, #5
  fc:	b9401c04 	ldr	w4, [x0, #28]
 100:	1ac12321 	lsl	w1, w25, w1
 104:	51000421 	sub	w1, w1, #0x1
 108:	2a040042 	orr	w2, w2, w4
 10c:	6b01005f 	cmp	w2, w1
 110:	54fffe81 	b.ne	e0 <malloc_trim+0xe0>  // b.any
 114:	14000003 	b	120 <malloc_trim+0x120>
 118:	f9401001 	ldr	x1, [x0, #32]
 11c:	362808c1 	tbz	w1, #5, 234 <malloc_trim+0x234>
 120:	f9401001 	ldr	x1, [x0, #32]
 124:	b9401802 	ldr	w2, [x0, #24]
 128:	b9401c03 	ldr	w3, [x0, #28]
 12c:	d3401021 	ubfx	x1, x1, #0, #5
 130:	2a030042 	orr	w2, w2, w3
 134:	1ac12321 	lsl	w1, w25, w1
 138:	51000421 	sub	w1, w1, #0x1
 13c:	6b01005f 	cmp	w2, w1
 140:	540007a1 	b.ne	234 <malloc_trim+0x234>  // b.any
 144:	f9400401 	ldr	x1, [x0, #8]
 148:	eb01001f 	cmp	x0, x1
 14c:	540002c0 	b.eq	1a4 <malloc_trim+0x1a4>  // b.none
 150:	f9400002 	ldr	x2, [x0]
 154:	f9000441 	str	x1, [x2, #8]
 158:	f9400002 	ldr	x2, [x0]
 15c:	f9000022 	str	x2, [x1]
 160:	f9400341 	ldr	x1, [x26]
 164:	eb01001f 	cmp	x0, x1
 168:	54000180 	b.eq	198 <malloc_trim+0x198>  // b.none
 16c:	a9007c1f 	stp	xzr, xzr, [x0]
 170:	f9400345 	ldr	x5, [x26]
 174:	b4000065 	cbz	x5, 180 <malloc_trim+0x180>
 178:	b94018a1 	ldr	w1, [x5, #24]
 17c:	34000181 	cbz	w1, 1ac <malloc_trim+0x1ac>
 180:	94000000 	bl	0 <malloc_trim>
			180: R_AARCH64_CALL26	.text.free_group
 184:	b50004e1 	cbnz	x1, 220 <malloc_trim+0x220>
 188:	f9400343 	ldr	x3, [x26]
 18c:	b4000543 	cbz	x3, 234 <malloc_trim+0x234>
 190:	aa0303e0 	mov	x0, x3
 194:	17ffffd6 	b	ec <malloc_trim+0xec>
 198:	f9400401 	ldr	x1, [x0, #8]
 19c:	f9000341 	str	x1, [x26]
 1a0:	17fffff3 	b	16c <malloc_trim+0x16c>
 1a4:	f900035f 	str	xzr, [x26]
 1a8:	17fffff1 	b	16c <malloc_trim+0x16c>
 1ac:	b94018a1 	ldr	w1, [x5, #24]
 1b0:	350001e1 	cbnz	w1, 1ec <malloc_trim+0x1ec>
 1b4:	f94008a2 	ldr	x2, [x5, #16]
 1b8:	910070a3 	add	x3, x5, #0x1c
 1bc:	39400e81 	ldrb	w1, [x20, #3]
 1c0:	f9400446 	ldr	x6, [x2, #8]
 1c4:	d34010c6 	ubfx	x6, x6, #0, #5
 1c8:	1ac62326 	lsl	w6, w25, w6
 1cc:	510004c8 	sub	w8, w6, #0x1
 1d0:	4b0603e6 	neg	w6, w6
 1d4:	72001c3f 	tst	w1, #0xff
 1d8:	540000e1 	b.ne	1f4 <malloc_trim+0x1f4>  // b.any
 1dc:	b9401ca7 	ldr	w7, [x5, #28]
 1e0:	0a0600e6 	and	w6, w7, w6
 1e4:	b9001ca6 	str	w6, [x5, #28]
 1e8:	1400000b 	b	214 <malloc_trim+0x214>
 1ec:	d4207d00 	brk	#0x3e8
 1f0:	d5033bbf 	dmb	ish
 1f4:	b9401ca4 	ldr	w4, [x5, #28]
 1f8:	2a0403e7 	mov	w7, w4
 1fc:	0a060082 	and	w2, w4, w6
 200:	885ffc61 	ldaxr	w1, [x3]
 204:	6b01009f 	cmp	w4, w1
 208:	54ffff41 	b.ne	1f0 <malloc_trim+0x1f0>  // b.any
 20c:	8801fc62 	stlxr	w1, w2, [x3]
 210:	35ffff81 	cbnz	w1, 200 <malloc_trim+0x200>
 214:	0a070101 	and	w1, w8, w7
 218:	b90018a1 	str	w1, [x5, #24]
 21c:	17ffffd9 	b	180 <malloc_trim+0x180>
 220:	94000000 	bl	0 <munmap>
			220: R_AARCH64_CALL26	munmap
 224:	7100001f 	cmp	w0, #0x0
 228:	1a9f17e0 	cset	w0, eq	// eq = none
 22c:	2a000273 	orr	w19, w19, w0
 230:	17ffffd6 	b	188 <malloc_trim+0x188>
 234:	9100235a 	add	x26, x26, #0x8
 238:	eb15035f 	cmp	x26, x21
 23c:	54000060 	b.eq	248 <malloc_trim+0x248>  // b.none
 240:	910002d4 	add	x20, x22, #0x0
			240: R_AARCH64_ADD_ABS_LO12_NC	__libc
 244:	17ffffd1 	b	188 <malloc_trim+0x188>
 248:	90000001 	adrp	x1, 0 <__malloc_lock>
			248: R_AARCH64_ADR_PREL_PG_HI21	__malloc_lock
 24c:	91000020 	add	x0, x1, #0x0
			24c: R_AARCH64_ADD_ABS_LO12_NC	__malloc_lock
 250:	b9400021 	ldr	w1, [x1]
			250: R_AARCH64_LDST32_ABS_LO12_NC	__malloc_lock
 254:	37f80121 	tbnz	w1, #31, 278 <malloc_trim+0x278>
 258:	b90002f8 	str	w24, [x23]
 25c:	2a1303e0 	mov	w0, w19
 260:	f94023fa 	ldr	x26, [sp, #64]
 264:	a94157f4 	ldp	x20, x21, [sp, #16]
 268:	a9425ff6 	ldp	x22, x23, [sp, #32]
 26c:	a94367f8 	ldp	x24, x25, [sp, #48]
 270:	a8c54ffe 	ldp	x30, x19, [sp], #80
 274:	d65f03c0 	ret
 278:	94000000 	bl	0 <__unlock>
			278: R_AARCH64_CALL26	__unlock
 27c:	17fffff7 	b	258 <malloc_trim+0x258>


/Users/alex/code/vinix/third_party/useralloc-libc/build/useralloc/v6-prototype/cache/aarch64/960d5f8e8b6ed7696677da75d64eea0cb926a83eca2aa353b15980cbb01883d4/objects/obj/src/malloc/mallocng/free.lo:     file format elf64-littleaarch64


Disassembly of section .text.free_group:

0000000000000000 <free_group>:
   0:	a9be4ffe 	stp	x30, x19, [sp, #-32]!
   4:	aa0003f3 	mov	x19, x0
   8:	f9000bf4 	str	x20, [sp, #16]
   c:	f9401003 	ldr	x3, [x0, #32]
  10:	53062c64 	ubfx	w4, w3, #6, #6
  14:	7100fc9f 	cmp	w4, #0x3f
  18:	54000600 	b.eq	d8 <free_group+0xd8>  // b.none
  1c:	7100bc9f 	cmp	w4, #0x2f
  20:	5400018c 	b.gt	50 <free_group+0x50>
  24:	d37d1481 	ubfiz	x1, x4, #3, #6
  28:	90000000 	adrp	x0, 0 <__malloc_context>
			28: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
  2c:	9107c021 	add	x1, x1, #0x1f0
  30:	91000000 	add	x0, x0, #0x0
			30: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
  34:	8b010000 	add	x0, x0, x1
  38:	92401063 	and	x3, x3, #0x1f
  3c:	91000463 	add	x3, x3, #0x1
  40:	f9400401 	ldr	x1, [x0, #8]
  44:	cb030021 	sub	x1, x1, x3
  48:	f9000401 	str	x1, [x0, #8]
  4c:	f9401263 	ldr	x3, [x19, #32]
  50:	f13ffc7f 	cmp	x3, #0xfff
  54:	54000b09 	b.ls	1b4 <free_group+0x1b4>  // b.plast
  58:	90000014 	adrp	x20, 0 <__malloc_context>
			58: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
  5c:	91000280 	add	x0, x20, #0x0
			5c: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
  60:	394ee002 	ldrb	w2, [x0, #952]
  64:	11000441 	add	w1, w2, #0x1
  68:	12001c21 	and	w1, w1, #0xff
  6c:	7103fc5f 	cmp	w2, #0xff
  70:	54000900 	b.eq	190 <free_group+0x190>  // b.none
  74:	91000280 	add	x0, x20, #0x0
			74: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
  78:	51001c84 	sub	w4, w4, #0x7
  7c:	390ee001 	strb	w1, [x0, #952]
  80:	71007c9f 	cmp	w4, #0x1f
  84:	54000068 	b.hi	90 <free_group+0x90>  // b.pmore
  88:	8b24c004 	add	x4, x0, w4, sxtw
  8c:	390de081 	strb	w1, [x4, #888]
  90:	f9401261 	ldr	x1, [x19, #32]
  94:	f9400a60 	ldr	x0, [x19, #16]
  98:	9274cc21 	and	x1, x1, #0xfffffffffffff000
  9c:	91000294 	add	x20, x20, #0x0
			9c: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
  a0:	a9007e7f 	stp	xzr, xzr, [x19]
  a4:	a9017e7f 	stp	xzr, xzr, [x19, #16]
  a8:	f9400a82 	ldr	x2, [x20, #16]
  ac:	f900127f 	str	xzr, [x19, #32]
  b0:	b4001042 	cbz	x2, 2b8 <free_group+0x2b8>
  b4:	f9000662 	str	x2, [x19, #8]
  b8:	f9400042 	ldr	x2, [x2]
  bc:	f9000262 	str	x2, [x19]
  c0:	f9000453 	str	x19, [x2, #8]
  c4:	f9400662 	ldr	x2, [x19, #8]
  c8:	f9000053 	str	x19, [x2]
  cc:	f9400bf4 	ldr	x20, [sp, #16]
  d0:	a8c24ffe 	ldp	x30, x19, [sp], #32
  d4:	d65f03c0 	ret
  d8:	d34cfc65 	lsr	x5, x3, #12
  dc:	d10080a0 	sub	x0, x5, #0x20
  e0:	f107801f 	cmp	x0, #0x1e0
  e4:	54fffb68 	b.hi	50 <free_group+0x50>  // b.pmore
  e8:	d2800400 	mov	x0, #0x20                  	// #32
  ec:	52800001 	mov	w1, #0x0                   	// #0
  f0:	14000003 	b	fc <free_group+0xfc>
  f4:	11000421 	add	w1, w1, #0x1
  f8:	d37ff800 	lsl	x0, x0, #1
  fc:	eb0000bf 	cmp	x5, x0
 100:	54ffffa8 	b.hi	f4 <free_group+0xf4>  // b.pmore
 104:	93407c22 	sxtw	x2, w1
 108:	90000014 	adrp	x20, 0 <__malloc_context>
			108: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
 10c:	9100e840 	add	x0, x2, #0x3a
 110:	91000286 	add	x6, x20, #0x0
			110: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 114:	f86078c0 	ldr	x0, [x6, x0, lsl #3]
 118:	b40002e0 	cbz	x0, 174 <free_group+0x174>
 11c:	f9401001 	ldr	x1, [x0, #32]
 120:	d34cfc21 	lsr	x1, x1, #12
 124:	eb0100bf 	cmp	x5, x1
 128:	54fff949 	b.ls	50 <free_group+0x50>  // b.plast
 12c:	f9400804 	ldr	x4, [x0, #16]
 130:	a9007c1f 	stp	xzr, xzr, [x0]
 134:	a9017c1f 	stp	xzr, xzr, [x0, #16]
 138:	f94008c3 	ldr	x3, [x6, #16]
 13c:	f900101f 	str	xzr, [x0, #32]
 140:	b4000143 	cbz	x3, 168 <free_group+0x168>
 144:	f9000403 	str	x3, [x0, #8]
 148:	f9400063 	ldr	x3, [x3]
 14c:	f9000003 	str	x3, [x0]
 150:	f9000460 	str	x0, [x3, #8]
 154:	f9400403 	ldr	x3, [x0, #8]
 158:	f9000060 	str	x0, [x3]
 15c:	d3747c21 	ubfiz	x1, x1, #12, #32
 160:	aa0403e0 	mov	x0, x4
 164:	14000005 	b	178 <free_group+0x178>
 168:	a9000000 	stp	x0, x0, [x0]
 16c:	f90008c0 	str	x0, [x6, #16]
 170:	17fffffb 	b	15c <free_group+0x15c>
 174:	d2800001 	mov	x1, #0x0                   	// #0
 178:	91000294 	add	x20, x20, #0x0
			178: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 17c:	9100e842 	add	x2, x2, #0x3a
 180:	52800023 	mov	w3, #0x1                   	// #1
 184:	b9001e63 	str	w3, [x19, #28]
 188:	f8227a93 	str	x19, [x20, x2, lsl #3]
 18c:	17ffffd0 	b	cc <free_group+0xcc>
 190:	90000001 	adrp	x1, 0 <__malloc_context>
			190: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context+0x378
 194:	910e6000 	add	x0, x0, #0x398
 198:	91000021 	add	x1, x1, #0x0
			198: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context+0x378
 19c:	14000002 	b	1a4 <free_group+0x1a4>
 1a0:	3800143f 	strb	wzr, [x1], #1
 1a4:	eb00003f 	cmp	x1, x0
 1a8:	54ffffc1 	b.ne	1a0 <free_group+0x1a0>  // b.any
 1ac:	52800021 	mov	w1, #0x1                   	// #1
 1b0:	17ffffb1 	b	74 <free_group+0x74>
 1b4:	f9400a63 	ldr	x3, [x19, #16]
 1b8:	f2400c7f 	tst	x3, #0xf
 1bc:	540007c1 	b.ne	2b4 <free_group+0x2b4>  // b.any
 1c0:	385fc060 	ldurb	w0, [x3, #-4]
 1c4:	385fd061 	ldurb	w1, [x3, #-3]
 1c8:	785fe066 	ldurh	w6, [x3, #-2]
 1cc:	12001021 	and	w1, w1, #0x1f
 1d0:	340000c0 	cbz	w0, 1e8 <free_group+0x1e8>
 1d4:	35000706 	cbnz	w6, 2b4 <free_group+0x2b4>
 1d8:	b85f8066 	ldur	w6, [x3, #-8]
 1dc:	529fffe0 	mov	w0, #0xffff                	// #65535
 1e0:	6b0000df 	cmp	w6, w0
 1e4:	5400068d 	b.le	2b4 <free_group+0x2b4>
 1e8:	531c6cc2 	lsl	w2, w6, #4
 1ec:	928001e0 	mov	x0, #0xfffffffffffffff0    	// #-16
 1f0:	cb22c000 	sub	x0, x0, w2, sxtw
 1f4:	8b000064 	add	x4, x3, x0
 1f8:	f8606860 	ldr	x0, [x3, x0]
 1fc:	f9400802 	ldr	x2, [x0, #16]
 200:	eb02009f 	cmp	x4, x2
 204:	54000581 	b.ne	2b4 <free_group+0x2b4>  // b.any
 208:	f9401002 	ldr	x2, [x0, #32]
 20c:	12001044 	and	w4, w2, #0x1f
 210:	6b04003f 	cmp	w1, w4
 214:	5400050c 	b.gt	2b4 <free_group+0x2b4>
 218:	b9401804 	ldr	w4, [x0, #24]
 21c:	1ac12484 	lsr	w4, w4, w1
 220:	370004a4 	tbnz	w4, #0, 2b4 <free_group+0x2b4>
 224:	b9401c04 	ldr	w4, [x0, #28]
 228:	1ac12484 	lsr	w4, w4, w1
 22c:	37000444 	tbnz	w4, #0, 2b4 <free_group+0x2b4>
 230:	9274cc04 	and	x4, x0, #0xfffffffffffff000
 234:	90000014 	adrp	x20, 0 <__malloc_context>
			234: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
 238:	f9400285 	ldr	x5, [x20]
			238: R_AARCH64_LDST64_ABS_LO12_NC	__malloc_context
 23c:	f9400084 	ldr	x4, [x4]
 240:	eb05009f 	cmp	x4, x5
 244:	54000381 	b.ne	2b4 <free_group+0x2b4>  // b.any
 248:	53062c44 	ubfx	w4, w2, #6, #6
 24c:	7100bc9f 	cmp	w4, #0x2f
 250:	5400026c 	b.gt	29c <free_group+0x29c>
 254:	90000005 	adrp	x5, 0 <__malloc_size_classes>
			254: R_AARCH64_ADR_PREL_PG_HI21	__malloc_size_classes
 258:	910000a5 	add	x5, x5, #0x0
			258: R_AARCH64_ADD_ABS_LO12_NC	__malloc_size_classes
 25c:	7864d8a4 	ldrh	w4, [x5, w4, sxtw #1]
 260:	1b047c25 	mul	w5, w1, w4
 264:	6b0500df 	cmp	w6, w5
 268:	5400026b 	b.lt	2b4 <free_group+0x2b4>  // b.tstop
 26c:	0b050084 	add	w4, w4, w5
 270:	6b0400df 	cmp	w6, w4
 274:	5400020a 	b.ge	2b4 <free_group+0x2b4>  // b.tcont
 278:	d34cfc42 	lsr	x2, x2, #12
 27c:	b40000a2 	cbz	x2, 290 <free_group+0x290>
 280:	d378dc42 	lsl	x2, x2, #8
 284:	d1000442 	sub	x2, x2, #0x1
 288:	eb26c05f 	cmp	x2, w6, sxtw
 28c:	54000143 	b.cc	2b4 <free_group+0x2b4>  // b.lo, b.ul, b.last
 290:	f900007f 	str	xzr, [x3]
 294:	94000000 	bl	0 <free_group>
			294: R_AARCH64_CALL26	.text.nontrivial_free
 298:	17ffff81 	b	9c <free_group+0x9c>
 29c:	7100fc9f 	cmp	w4, #0x3f
 2a0:	540000a1 	b.ne	2b4 <free_group+0x2b4>  // b.any
 2a4:	f240105f 	tst	x2, #0x1f
 2a8:	54000061 	b.ne	2b4 <free_group+0x2b4>  // b.any
 2ac:	f13ffc5f 	cmp	x2, #0xfff
 2b0:	54fffe48 	b.hi	278 <free_group+0x278>  // b.pmore
 2b4:	d4207d00 	brk	#0x3e8
 2b8:	a9004e73 	stp	x19, x19, [x19]
 2bc:	f9000a93 	str	x19, [x20, #16]
 2c0:	17ffff83 	b	cc <free_group+0xcc>

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
  44:	54000d4c 	b.gt	1ec <nontrivial_free+0x1ec>
  48:	93407ca6 	sxtw	x6, w5
  4c:	90000007 	adrp	x7, 0 <__malloc_context>
			4c: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
  50:	910000e2 	add	x2, x7, #0x0
			50: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
  54:	910028c3 	add	x3, x6, #0xa
  58:	f8637842 	ldr	x2, [x2, x3, lsl #3]
  5c:	eb00005f 	cmp	x2, x0
  60:	54000180 	b.eq	90 <nontrivial_free+0x90>  // b.none
  64:	f9400403 	ldr	x3, [x0, #8]
  68:	b5000c23 	cbnz	x3, 1ec <nontrivial_free+0x1ec>
  6c:	f9400003 	ldr	x3, [x0]
  70:	b5000be3 	cbnz	x3, 1ec <nontrivial_free+0x1ec>
  74:	b4000702 	cbz	x2, 154 <nontrivial_free+0x154>
  78:	f9000402 	str	x2, [x0, #8]
  7c:	f9400042 	ldr	x2, [x2]
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
  a0:	540011c1 	b.ne	2d8 <nontrivial_free+0x2d8>  // b.any
  a4:	b9401c02 	ldr	w2, [x0, #28]
  a8:	2a010041 	orr	w1, w2, w1
  ac:	b9001c01 	str	w1, [x0, #28]
  b0:	d2800000 	mov	x0, #0x0                   	// #0
  b4:	d2800001 	mov	x1, #0x0                   	// #0
  b8:	d65f03c0 	ret
  bc:	362ffc03 	tbz	w3, #5, 3c <nontrivial_free+0x3c>
  c0:	f9400402 	ldr	x2, [x0, #8]
  c4:	7100bcbf 	cmp	w5, #0x2f
  c8:	5400090c 	b.gt	1e8 <nontrivial_free+0x1e8>
  cc:	90000007 	adrp	x7, 0 <__malloc_size_classes>
			cc: R_AARCH64_ADR_PREL_PG_HI21	__malloc_size_classes
  d0:	910000e7 	add	x7, x7, #0x0
			d0: R_AARCH64_ADD_ABS_LO12_NC	__malloc_size_classes
  d4:	92401066 	and	x6, x3, #0x1f
  d8:	f13ffc7f 	cmp	x3, #0xfff
  dc:	fa4088c0 	ccmp	x6, #0x0, #0x0, hi	// hi = pmore
  e0:	93407ca6 	sxtw	x6, w5
  e4:	7865d8e9 	ldrh	w9, [x7, w5, sxtw #1]
  e8:	54000120 	b.eq	10c <nontrivial_free+0x10c>  // b.none
  ec:	eb02001f 	cmp	x0, x2
  f0:	540005c0 	b.eq	1a8 <nontrivial_free+0x1a8>  // b.none
  f4:	b40003a2 	cbz	x2, 168 <nontrivial_free+0x168>
  f8:	910028c1 	add	x1, x6, #0xa
  fc:	90000007 	adrp	x7, 0 <__malloc_context>
			fc: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
 100:	910000e3 	add	x3, x7, #0x0
			100: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 104:	f8617861 	ldr	x1, [x3, x1, lsl #3]
 108:	14000041 	b	20c <nontrivial_free+0x20c>
 10c:	9274cc63 	and	x3, x3, #0xfffffffffffff000
 110:	d37c3d29 	ubfiz	x9, x9, #4, #16
 114:	d1004067 	sub	x7, x3, #0x10
 118:	eb0900ff 	cmp	x7, x9
 11c:	540006a3 	b.cc	1f0 <nontrivial_free+0x1f0>  // b.lo, b.ul, b.last
 120:	eb02001f 	cmp	x0, x2
 124:	54000e60 	b.eq	2f0 <nontrivial_free+0x2f0>  // b.none
 128:	b5fffe82 	cbnz	x2, f8 <nontrivial_free+0xf8>
 12c:	910028c2 	add	x2, x6, #0xa
 130:	90000007 	adrp	x7, 0 <__malloc_context>
			130: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
 134:	910000e5 	add	x5, x7, #0x0
			134: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 138:	f86278a2 	ldr	x2, [x5, x2, lsl #3]
 13c:	b5000802 	cbnz	x2, 23c <nontrivial_free+0x23c>
 140:	f140807f 	cmp	x3, #0x20, lsl #12
 144:	540007c8 	b.hi	23c <nontrivial_free+0x23c>  // b.pmore
 148:	35fffa44 	cbnz	w4, 90 <nontrivial_free+0x90>
 14c:	f9400002 	ldr	x2, [x0]
 150:	b50004e2 	cbnz	x2, 1ec <nontrivial_free+0x1ec>
 154:	910000e7 	add	x7, x7, #0x0
			154: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 158:	910028c6 	add	x6, x6, #0xa
 15c:	a9000000 	stp	x0, x0, [x0]
 160:	f82678e0 	str	x0, [x7, x6, lsl #3]
 164:	17ffffcb 	b	90 <nontrivial_free+0x90>
 168:	910028c2 	add	x2, x6, #0xa
 16c:	90000007 	adrp	x7, 0 <__malloc_context>
			16c: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
 170:	910000e5 	add	x5, x7, #0x0
			170: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 174:	f86278a2 	ldr	x2, [x5, x2, lsl #3]
 178:	b5000622 	cbnz	x2, 23c <nontrivial_free+0x23c>
 17c:	f13ffc7f 	cmp	x3, #0xfff
 180:	540000c8 	b.hi	198 <nontrivial_free+0x198>  // b.pmore
 184:	1b092509 	madd	w9, w8, w9, w9
 188:	11000522 	add	w2, w9, #0x1
 18c:	7140085f 	cmp	w2, #0x2, lsl #12
 190:	5400018d 	b.le	1c0 <nontrivial_free+0x1c0>
 194:	1400002a 	b	23c <nontrivial_free+0x23c>
 198:	9274cc63 	and	x3, x3, #0xfffffffffffff000
 19c:	f140807f 	cmp	x3, #0x20, lsl #12
 1a0:	540004e8 	b.hi	23c <nontrivial_free+0x23c>  // b.pmore
 1a4:	17ffffe9 	b	148 <nontrivial_free+0x148>
 1a8:	f13ffc7f 	cmp	x3, #0xfff
 1ac:	540000e8 	b.hi	1c8 <nontrivial_free+0x1c8>  // b.pmore
 1b0:	1b092509 	madd	w9, w8, w9, w9
 1b4:	11000523 	add	w3, w9, #0x1
 1b8:	7140087f 	cmp	w3, #0x2, lsl #12
 1bc:	5400012c 	b.gt	1e0 <nontrivial_free+0x1e0>
 1c0:	35fff684 	cbnz	w4, 90 <nontrivial_free+0x90>
 1c4:	17ffffa2 	b	4c <nontrivial_free+0x4c>
 1c8:	9274cc63 	and	x3, x3, #0xfffffffffffff000
 1cc:	f140807f 	cmp	x3, #0x20, lsl #12
 1d0:	54ffff89 	b.ls	1c0 <nontrivial_free+0x1c0>  // b.plast
 1d4:	51001ca5 	sub	w5, w5, #0x7
 1d8:	71007cbf 	cmp	w5, #0x1f
 1dc:	54000a49 	b.ls	324 <nontrivial_free+0x324>  // b.plast
 1e0:	90000007 	adrp	x7, 0 <__malloc_context>
			1e0: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
 1e4:	14000005 	b	1f8 <nontrivial_free+0x1f8>
 1e8:	b40002a2 	cbz	x2, 23c <nontrivial_free+0x23c>
 1ec:	d4207d00 	brk	#0x3e8
 1f0:	90000007 	adrp	x7, 0 <__malloc_context>
			1f0: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
 1f4:	b4000242 	cbz	x2, 23c <nontrivial_free+0x23c>
 1f8:	910000e1 	add	x1, x7, #0x0
			1f8: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 1fc:	910028c3 	add	x3, x6, #0xa
 200:	f8637821 	ldr	x1, [x1, x3, lsl #3]
 204:	eb02001f 	cmp	x0, x2
 208:	54000860 	b.eq	314 <nontrivial_free+0x314>  // b.none
 20c:	f9400005 	ldr	x5, [x0]
 210:	910000e3 	add	x3, x7, #0x0
			210: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 214:	910028c4 	add	x4, x6, #0xa
 218:	f90004a2 	str	x2, [x5, #8]
 21c:	f9400005 	ldr	x5, [x0]
 220:	f9000045 	str	x5, [x2]
 224:	f8647862 	ldr	x2, [x3, x4, lsl #3]
 228:	eb02001f 	cmp	x0, x2
 22c:	540000a0 	b.eq	240 <nontrivial_free+0x240>  // b.none
 230:	a9007c1f 	stp	xzr, xzr, [x0]
 234:	eb01001f 	cmp	x0, x1
 238:	540000a0 	b.eq	24c <nontrivial_free+0x24c>  // b.none
 23c:	14000000 	b	0 <nontrivial_free>
			23c: R_AARCH64_JUMP26	.text.free_group
 240:	f9400402 	ldr	x2, [x0, #8]
 244:	f8247862 	str	x2, [x3, x4, lsl #3]
 248:	17fffffa 	b	230 <nontrivial_free+0x230>
 24c:	910000e7 	add	x7, x7, #0x0
			24c: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 250:	910028c6 	add	x6, x6, #0xa
 254:	f86678e5 	ldr	x5, [x7, x6, lsl #3]
 258:	b4ffff25 	cbz	x5, 23c <nontrivial_free+0x23c>
 25c:	b94018a1 	ldr	w1, [x5, #24]
 260:	35fffc61 	cbnz	w1, 1ec <nontrivial_free+0x1ec>
 264:	f94008a1 	ldr	x1, [x5, #16]
 268:	90000002 	adrp	x2, 0 <__libc>
			268: R_AARCH64_ADR_PREL_PG_HI21	__libc
 26c:	91000042 	add	x2, x2, #0x0
			26c: R_AARCH64_ADD_ABS_LO12_NC	__libc
 270:	52800046 	mov	w6, #0x2                   	// #2
 274:	910070a3 	add	x3, x5, #0x1c
 278:	f9400421 	ldr	x1, [x1, #8]
 27c:	39400c42 	ldrb	w2, [x2, #3]
 280:	d3401021 	ubfx	x1, x1, #0, #5
 284:	1ac120c6 	lsl	w6, w6, w1
 288:	510004c8 	sub	w8, w6, #0x1
 28c:	4b0603e6 	neg	w6, w6
 290:	72001c5f 	tst	w2, #0xff
 294:	540000c1 	b.ne	2ac <nontrivial_free+0x2ac>  // b.any
 298:	b9401ca7 	ldr	w7, [x5, #28]
 29c:	0a0700c6 	and	w6, w6, w7
 2a0:	b9001ca6 	str	w6, [x5, #28]
 2a4:	1400000a 	b	2cc <nontrivial_free+0x2cc>
 2a8:	d5033bbf 	dmb	ish
 2ac:	b9401ca4 	ldr	w4, [x5, #28]
 2b0:	2a0403e7 	mov	w7, w4
 2b4:	0a0400c2 	and	w2, w6, w4
 2b8:	885ffc61 	ldaxr	w1, [x3]
 2bc:	6b01009f 	cmp	w4, w1
 2c0:	54ffff41 	b.ne	2a8 <nontrivial_free+0x2a8>  // b.any
 2c4:	8801fc62 	stlxr	w1, w2, [x3]
 2c8:	35ffff81 	cbnz	w1, 2b8 <nontrivial_free+0x2b8>
 2cc:	0a070101 	and	w1, w8, w7
 2d0:	b90018a1 	str	w1, [x5, #24]
 2d4:	17ffffda 	b	23c <nontrivial_free+0x23c>
 2d8:	91007002 	add	x2, x0, #0x1c
 2dc:	885ffc40 	ldaxr	w0, [x2]
 2e0:	2a010000 	orr	w0, w0, w1
 2e4:	8803fc40 	stlxr	w3, w0, [x2]
 2e8:	35ffffa3 	cbnz	w3, 2dc <nontrivial_free+0x2dc>
 2ec:	17ffff71 	b	b0 <nontrivial_free+0xb0>
 2f0:	f140807f 	cmp	x3, #0x20, lsl #12
 2f4:	54fff669 	b.ls	1c0 <nontrivial_free+0x1c0>  // b.plast
 2f8:	51001ca5 	sub	w5, w5, #0x7
 2fc:	71007cbf 	cmp	w5, #0x1f
 300:	54000129 	b.ls	324 <nontrivial_free+0x324>  // b.plast
 304:	910028c1 	add	x1, x6, #0xa
 308:	90000007 	adrp	x7, 0 <__malloc_context>
			308: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
 30c:	910000e2 	add	x2, x7, #0x0
			30c: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 310:	f8617841 	ldr	x1, [x2, x1, lsl #3]
 314:	910000e2 	add	x2, x7, #0x0
			314: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 318:	910028c3 	add	x3, x6, #0xa
 31c:	f823785f 	str	xzr, [x2, x3, lsl #3]
 320:	17ffffc4 	b	230 <nontrivial_free+0x230>
 324:	90000007 	adrp	x7, 0 <__malloc_context>
			324: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
 328:	910000e3 	add	x3, x7, #0x0
			328: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 32c:	8b25c065 	add	x5, x3, w5, sxtw
 330:	394e60a5 	ldrb	w5, [x5, #920]
 334:	71018cbf 	cmp	w5, #0x63
 338:	54fff609 	b.ls	1f8 <nontrivial_free+0x1f8>  // b.plast
 33c:	8b060c63 	add	x3, x3, x6, lsl #3
 340:	1100050a 	add	w10, w8, #0x1
 344:	d37d1545 	ubfiz	x5, x10, #3, #6
 348:	f940fc69 	ldr	x9, [x3, #504]
 34c:	8b0a00a3 	add	x3, x5, x10
 350:	eb03013f 	cmp	x9, x3
 354:	54000063 	b.cc	360 <nontrivial_free+0x360>  // b.lo, b.ul, b.last
 358:	71004d5f 	cmp	w10, #0x13
 35c:	54fff4cd 	b.le	1f4 <nontrivial_free+0x1f4>
 360:	34ffe784 	cbz	w4, 50 <nontrivial_free+0x50>
 364:	17ffff4b 	b	90 <nontrivial_free+0x90>

Disassembly of section .text.__libc_free:

0000000000000000 <__libc_free>:
   0:	b40017c0 	cbz	x0, 2f8 <__libc_free+0x2f8>
   4:	f2400c1f 	tst	x0, #0xf
   8:	54001761 	b.ne	2f4 <__libc_free+0x2f4>  // b.any
   c:	385fc002 	ldurb	w2, [x0, #-4]
  10:	385fd007 	ldurb	w7, [x0, #-3]
  14:	785fe005 	ldurh	w5, [x0, #-2]
  18:	120010e1 	and	w1, w7, #0x1f
  1c:	340000c2 	cbz	w2, 34 <__libc_free+0x34>
  20:	350016a5 	cbnz	w5, 2f4 <__libc_free+0x2f4>
  24:	b85f8005 	ldur	w5, [x0, #-8]
  28:	529fffe2 	mov	w2, #0xffff                	// #65535
  2c:	6b0200bf 	cmp	w5, w2
  30:	5400162d 	b.le	2f4 <__libc_free+0x2f4>
  34:	531c6ca3 	lsl	w3, w5, #4
  38:	928001e2 	mov	x2, #0xfffffffffffffff0    	// #-16
  3c:	a9bd4ffe 	stp	x30, x19, [sp, #-48]!
  40:	cb23c042 	sub	x2, x2, w3, sxtw
  44:	8b020003 	add	x3, x0, x2
  48:	f8626813 	ldr	x19, [x0, x2]
  4c:	f9400a64 	ldr	x4, [x19, #16]
  50:	eb04007f 	cmp	x3, x4
  54:	54000e21 	b.ne	218 <__libc_free+0x218>  // b.any
  58:	f9401263 	ldr	x3, [x19, #32]
  5c:	12001062 	and	w2, w3, #0x1f
  60:	d3401068 	ubfx	x8, x3, #0, #5
  64:	6b02003f 	cmp	w1, w2
  68:	54000d8c 	b.gt	218 <__libc_free+0x218>
  6c:	b9401a62 	ldr	w2, [x19, #24]
  70:	1ac12442 	lsr	w2, w2, w1
  74:	37000d22 	tbnz	w2, #0, 218 <__libc_free+0x218>
  78:	b9401e62 	ldr	w2, [x19, #28]
  7c:	1ac12442 	lsr	w2, w2, w1
  80:	37000cc2 	tbnz	w2, #0, 218 <__libc_free+0x218>
  84:	9274ce62 	and	x2, x19, #0xfffffffffffff000
  88:	90000006 	adrp	x6, 0 <__malloc_context>
			88: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
  8c:	f94000c6 	ldr	x6, [x6]
			8c: R_AARCH64_LDST64_ABS_LO12_NC	__malloc_context
  90:	f9400042 	ldr	x2, [x2]
  94:	eb06005f 	cmp	x2, x6
  98:	54000c01 	b.ne	218 <__libc_free+0x218>  // b.any
  9c:	53062c62 	ubfx	w2, w3, #6, #6
  a0:	7100bc5f 	cmp	w2, #0x2f
  a4:	54000aec 	b.gt	200 <__libc_free+0x200>
  a8:	90000006 	adrp	x6, 0 <__malloc_size_classes>
			a8: R_AARCH64_ADR_PREL_PG_HI21	__malloc_size_classes
  ac:	910000c6 	add	x6, x6, #0x0
			ac: R_AARCH64_ADD_ABS_LO12_NC	__malloc_size_classes
  b0:	7862d8c9 	ldrh	w9, [x6, w2, sxtw #1]
  b4:	1b097c22 	mul	w2, w1, w9
  b8:	6b0200bf 	cmp	w5, w2
  bc:	54000aeb 	b.lt	218 <__libc_free+0x218>  // b.tstop
  c0:	0b020122 	add	w2, w9, w2
  c4:	6b0200bf 	cmp	w5, w2
  c8:	54000a8a 	b.ge	218 <__libc_free+0x218>  // b.tcont
  cc:	d37c3d29 	ubfiz	x9, x9, #4, #16
  d0:	d34cfc62 	lsr	x2, x3, #12
  d4:	b4000a62 	cbz	x2, 220 <__libc_free+0x220>
  d8:	d378dc46 	lsl	x6, x2, #8
  dc:	d374cc42 	lsl	x2, x2, #12
  e0:	d10004c6 	sub	x6, x6, #0x1
  e4:	eb25c0df 	cmp	x6, w5, sxtw
  e8:	54000983 	b.cc	218 <__libc_free+0x218>  // b.lo, b.ul, b.last
  ec:	d1004042 	sub	x2, x2, #0x10
  f0:	f240107f 	tst	x3, #0x1f
  f4:	9a890042 	csel	x2, x2, x9, eq	// eq = none
  f8:	d1001045 	sub	x5, x2, #0x4
  fc:	2a0103e3 	mov	w3, w1
 100:	91004084 	add	x4, x4, #0x10
 104:	53057ce6 	lsr	w6, w7, #5
 108:	9b021463 	madd	x3, x3, x2, x5
 10c:	8b030085 	add	x5, x4, x3
 110:	71027cff 	cmp	w7, #0x9f
 114:	54000109 	b.ls	134 <__libc_free+0x134>  // b.plast
 118:	710014df 	cmp	w6, #0x5
 11c:	540007e1 	b.ne	218 <__libc_free+0x218>  // b.any
 120:	b85fc0a6 	ldur	w6, [x5, #-4]
 124:	f10010df 	cmp	x6, #0x4
 128:	54000789 	b.ls	218 <__libc_free+0x218>  // b.plast
 12c:	385fb0a7 	ldurb	w7, [x5, #-5]
 130:	35000747 	cbnz	w7, 218 <__libc_free+0x218>
 134:	cb0000a7 	sub	x7, x5, x0
 138:	eb0600ff 	cmp	x7, x6
 13c:	540006e3 	b.cc	218 <__libc_free+0x218>  // b.lo, b.ul, b.last
 140:	cb0600a5 	sub	x5, x5, x6
 144:	394000a5 	ldrb	w5, [x5]
 148:	35000685 	cbnz	w5, 218 <__libc_free+0x218>
 14c:	38636883 	ldrb	w3, [x4, x3]
 150:	35000643 	cbnz	w3, 218 <__libc_free+0x218>
 154:	90000007 	adrp	x7, 0 <__libc>
			154: R_AARCH64_ADR_PREL_PG_HI21	__libc
 158:	910000e3 	add	x3, x7, #0x0
			158: R_AARCH64_ADD_ABS_LO12_NC	__libc
 15c:	12800004 	mov	w4, #0xffffffff            	// #-1
 160:	381fd004 	sturb	w4, [x0, #-3]
 164:	781fe01f 	sturh	wzr, [x0, #-2]
 168:	52800046 	mov	w6, #0x2                   	// #2
 16c:	52800025 	mov	w5, #0x1                   	// #1
 170:	1ac820c6 	lsl	w6, w6, w8
 174:	39400c60 	ldrb	w0, [x3, #3]
 178:	510004c6 	sub	w6, w6, #0x1
 17c:	1ac120a5 	lsl	w5, w5, w1
 180:	72001c1f 	tst	w0, #0xff
 184:	54000121 	b.ne	1a8 <__libc_free+0x1a8>  // b.any
 188:	f9401260 	ldr	x0, [x19, #32]
 18c:	53062c03 	ubfx	w3, w0, #6, #6
 190:	7100bc7f 	cmp	w3, #0x2f
 194:	540000a8 	b.hi	1a8 <__libc_free+0x1a8>  // b.pmore
 198:	f9400663 	ldr	x3, [x19, #8]
 19c:	eb13007f 	cmp	x3, x19
 1a0:	fa420122 	ccmp	x9, x2, #0x2, eq	// eq = none
 1a4:	54000429 	b.ls	228 <__libc_free+0x228>  // b.plast
 1a8:	910000e8 	add	x8, x7, #0x0
			1a8: R_AARCH64_ADD_ABS_LO12_NC	__libc
 1ac:	b9401e64 	ldr	w4, [x19, #28]
 1b0:	b9401a60 	ldr	w0, [x19, #24]
 1b4:	2a000080 	orr	w0, w4, w0
 1b8:	6a0000bf 	tst	w5, w0
 1bc:	540002e1 	b.ne	218 <__libc_free+0x218>  // b.any
 1c0:	340005a4 	cbz	w4, 274 <__libc_free+0x274>
 1c4:	0b0000a0 	add	w0, w5, w0
 1c8:	6b06001f 	cmp	w0, w6
 1cc:	54000540 	b.eq	274 <__libc_free+0x274>  // b.none
 1d0:	39400d00 	ldrb	w0, [x8, #3]
 1d4:	0b0400a2 	add	w2, w5, w4
 1d8:	72001c1f 	tst	w0, #0xff
 1dc:	54000440 	b.eq	264 <__libc_free+0x264>  // b.none
 1e0:	91007260 	add	x0, x19, #0x1c
 1e4:	885ffc03 	ldaxr	w3, [x0]
 1e8:	6b03009f 	cmp	w4, w3
 1ec:	54000401 	b.ne	26c <__libc_free+0x26c>  // b.any
 1f0:	8803fc02 	stlxr	w3, w2, [x0]
 1f4:	35ffff83 	cbnz	w3, 1e4 <__libc_free+0x1e4>
 1f8:	a8c34ffe 	ldp	x30, x19, [sp], #48
 1fc:	d65f03c0 	ret
 200:	7100fc5f 	cmp	w2, #0x3f
 204:	540000a1 	b.ne	218 <__libc_free+0x218>  // b.any
 208:	f2401069 	ands	x9, x3, #0x1f
 20c:	54000061 	b.ne	218 <__libc_free+0x218>  // b.any
 210:	f13ffc7f 	cmp	x3, #0xfff
 214:	54fff5e8 	b.hi	d0 <__libc_free+0xd0>  // b.pmore
 218:	a90157f4 	stp	x20, x21, [sp, #16]
 21c:	d4207d00 	brk	#0x3e8
 220:	aa0903e2 	mov	x2, x9
 224:	17ffffb5 	b	f8 <__libc_free+0xf8>
 228:	f13ffc1f 	cmp	x0, #0xfff
 22c:	540000a9 	b.ls	240 <__libc_free+0x240>  // b.plast
 230:	9274cc00 	and	x0, x0, #0xfffffffffffff000
 234:	f140801f 	cmp	x0, #0x20, lsl #12
 238:	54fffb88 	b.hi	1a8 <__libc_free+0x1a8>  // b.pmore
 23c:	14000006 	b	254 <__libc_free+0x254>
 240:	92401000 	and	x0, x0, #0x1f
 244:	9b020802 	madd	x2, x0, x2, x2
 248:	91004040 	add	x0, x2, #0x10
 24c:	f140801f 	cmp	x0, #0x20, lsl #12
 250:	54fffac8 	b.hi	1a8 <__libc_free+0x1a8>  // b.pmore
 254:	b9401e60 	ldr	w0, [x19, #28]
 258:	2a0000a5 	orr	w5, w5, w0
 25c:	b9001e65 	str	w5, [x19, #28]
 260:	17ffffe6 	b	1f8 <__libc_free+0x1f8>
 264:	b9001e62 	str	w2, [x19, #28]
 268:	17ffffe4 	b	1f8 <__libc_free+0x1f8>
 26c:	d5033bbf 	dmb	ish
 270:	17ffffcf 	b	1ac <__libc_free+0x1ac>
 274:	910000e7 	add	x7, x7, #0x0
			274: R_AARCH64_ADD_ABS_LO12_NC	__libc
 278:	a90157f4 	stp	x20, x21, [sp, #16]
 27c:	90000014 	adrp	x20, 0 <__malloc_lock>
			27c: R_AARCH64_ADR_PREL_PG_HI21	__malloc_lock
 280:	39400ce0 	ldrb	w0, [x7, #3]
 284:	72001c1f 	tst	w0, #0xff
 288:	54000161 	b.ne	2b4 <__libc_free+0x2b4>  // b.any
 28c:	aa1303e0 	mov	x0, x19
 290:	94000000 	bl	0 <__libc_free>
			290: R_AARCH64_CALL26	.text.nontrivial_free
 294:	b9400282 	ldr	w2, [x20]
			294: R_AARCH64_LDST32_ABS_LO12_NC	__malloc_lock
 298:	aa0003f5 	mov	x21, x0
 29c:	aa0103f3 	mov	x19, x1
 2a0:	91000280 	add	x0, x20, #0x0
			2a0: R_AARCH64_ADD_ABS_LO12_NC	__malloc_lock
 2a4:	37f80122 	tbnz	w2, #31, 2c8 <__libc_free+0x2c8>
 2a8:	b5000153 	cbnz	x19, 2d0 <__libc_free+0x2d0>
 2ac:	a94157f4 	ldp	x20, x21, [sp, #16]
 2b0:	17ffffd2 	b	1f8 <__libc_free+0x1f8>
 2b4:	91000280 	add	x0, x20, #0x0
			2b4: R_AARCH64_ADD_ABS_LO12_NC	__malloc_lock
 2b8:	b9002fe1 	str	w1, [sp, #44]
 2bc:	94000000 	bl	0 <__lock>
			2bc: R_AARCH64_CALL26	__lock
 2c0:	b9402fe1 	ldr	w1, [sp, #44]
 2c4:	17fffff2 	b	28c <__libc_free+0x28c>
 2c8:	94000000 	bl	0 <__unlock>
			2c8: R_AARCH64_CALL26	__unlock
 2cc:	17fffff7 	b	2a8 <__libc_free+0x2a8>
 2d0:	94000000 	bl	0 <___errno_location>
			2d0: R_AARCH64_CALL26	___errno_location
 2d4:	aa0003f4 	mov	x20, x0
 2d8:	aa1303e1 	mov	x1, x19
 2dc:	aa1503e0 	mov	x0, x21
 2e0:	b9400293 	ldr	w19, [x20]
 2e4:	94000000 	bl	0 <munmap>
			2e4: R_AARCH64_CALL26	munmap
 2e8:	b9000293 	str	w19, [x20]
 2ec:	a94157f4 	ldp	x20, x21, [sp, #16]
 2f0:	17ffffc2 	b	1f8 <__libc_free+0x1f8>
 2f4:	d4207d00 	brk	#0x3e8
 2f8:	d65f03c0 	ret

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

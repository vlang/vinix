
/Users/alex/code/vinix/third_party/useralloc-libc/build/musl/aarch64/8adbe7fc2d9d74c610f67eb2cab1fe514a0da223a0d1c9f5158aa5374a4282ad/objects/obj/src/malloc/mallocng/free.lo:     file format elf64-littleaarch64


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
  b0:	b4001002 	cbz	x2, 2b0 <free_group+0x2b0>
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
 1b4:	f9400a62 	ldr	x2, [x19, #16]
 1b8:	f2400c5f 	tst	x2, #0xf
 1bc:	54000781 	b.ne	2ac <free_group+0x2ac>  // b.any
 1c0:	385fc040 	ldurb	w0, [x2, #-4]
 1c4:	385fd041 	ldurb	w1, [x2, #-3]
 1c8:	785fe046 	ldurh	w6, [x2, #-2]
 1cc:	12001021 	and	w1, w1, #0x1f
 1d0:	340000c0 	cbz	w0, 1e8 <free_group+0x1e8>
 1d4:	350006c6 	cbnz	w6, 2ac <free_group+0x2ac>
 1d8:	b85f8046 	ldur	w6, [x2, #-8]
 1dc:	529fffe0 	mov	w0, #0xffff                	// #65535
 1e0:	6b0000df 	cmp	w6, w0
 1e4:	5400064d 	b.le	2ac <free_group+0x2ac>
 1e8:	531c6cc3 	lsl	w3, w6, #4
 1ec:	928001e0 	mov	x0, #0xfffffffffffffff0    	// #-16
 1f0:	cb23c000 	sub	x0, x0, w3, sxtw
 1f4:	8b000044 	add	x4, x2, x0
 1f8:	f8606840 	ldr	x0, [x2, x0]
 1fc:	f9400803 	ldr	x3, [x0, #16]
 200:	eb03009f 	cmp	x4, x3
 204:	54000541 	b.ne	2ac <free_group+0x2ac>  // b.any
 208:	f9401003 	ldr	x3, [x0, #32]
 20c:	12001064 	and	w4, w3, #0x1f
 210:	6b04003f 	cmp	w1, w4
 214:	540004cc 	b.gt	2ac <free_group+0x2ac>
 218:	b9401804 	ldr	w4, [x0, #24]
 21c:	1ac12484 	lsr	w4, w4, w1
 220:	37000464 	tbnz	w4, #0, 2ac <free_group+0x2ac>
 224:	b9401c04 	ldr	w4, [x0, #28]
 228:	1ac12484 	lsr	w4, w4, w1
 22c:	37000404 	tbnz	w4, #0, 2ac <free_group+0x2ac>
 230:	9274cc04 	and	x4, x0, #0xfffffffffffff000
 234:	90000014 	adrp	x20, 0 <__malloc_context>
			234: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
 238:	f9400285 	ldr	x5, [x20]
			238: R_AARCH64_LDST64_ABS_LO12_NC	__malloc_context
 23c:	f9400084 	ldr	x4, [x4]
 240:	eb05009f 	cmp	x4, x5
 244:	54000341 	b.ne	2ac <free_group+0x2ac>  // b.any
 248:	53062c64 	ubfx	w4, w3, #6, #6
 24c:	7100bc9f 	cmp	w4, #0x2f
 250:	54000288 	b.hi	2a0 <free_group+0x2a0>  // b.pmore
 254:	90000005 	adrp	x5, 0 <__malloc_size_classes>
			254: R_AARCH64_ADR_PREL_PG_HI21	__malloc_size_classes
 258:	910000a5 	add	x5, x5, #0x0
			258: R_AARCH64_ADD_ABS_LO12_NC	__malloc_size_classes
 25c:	7864d8a4 	ldrh	w4, [x5, w4, sxtw #1]
 260:	1b047c25 	mul	w5, w1, w4
 264:	6b0500df 	cmp	w6, w5
 268:	5400022b 	b.lt	2ac <free_group+0x2ac>  // b.tstop
 26c:	0b050084 	add	w4, w4, w5
 270:	6b0400df 	cmp	w6, w4
 274:	540001ca 	b.ge	2ac <free_group+0x2ac>  // b.tcont
 278:	f13ffc7f 	cmp	x3, #0xfff
 27c:	540000c9 	b.ls	294 <free_group+0x294>  // b.plast
 280:	9274cc63 	and	x3, x3, #0xfffffffffffff000
 284:	d344fc63 	lsr	x3, x3, #4
 288:	d1000463 	sub	x3, x3, #0x1
 28c:	eb26c07f 	cmp	x3, w6, sxtw
 290:	540000e3 	b.cc	2ac <free_group+0x2ac>  // b.lo, b.ul, b.last
 294:	f900005f 	str	xzr, [x2]
 298:	94000000 	bl	0 <free_group>
			298: R_AARCH64_CALL26	.text.nontrivial_free
 29c:	17ffff80 	b	9c <free_group+0x9c>
 2a0:	927a1464 	and	x4, x3, #0xfc0
 2a4:	f13f009f 	cmp	x4, #0xfc0
 2a8:	54fffe80 	b.eq	278 <free_group+0x278>  // b.none
 2ac:	d4207d00 	brk	#0x3e8
 2b0:	a9004e73 	stp	x19, x19, [x19]
 2b4:	f9000a93 	str	x19, [x20, #16]
 2b8:	17ffff85 	b	cc <free_group+0xcc>

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
   0:	b4001820 	cbz	x0, 304 <__libc_free+0x304>
   4:	f2400c1f 	tst	x0, #0xf
   8:	540017c1 	b.ne	300 <__libc_free+0x300>  // b.any
   c:	385fc002 	ldurb	w2, [x0, #-4]
  10:	385fd006 	ldurb	w6, [x0, #-3]
  14:	785fe005 	ldurh	w5, [x0, #-2]
  18:	120010c1 	and	w1, w6, #0x1f
  1c:	340000c2 	cbz	w2, 34 <__libc_free+0x34>
  20:	35001705 	cbnz	w5, 300 <__libc_free+0x300>
  24:	b85f8005 	ldur	w5, [x0, #-8]
  28:	529fffe2 	mov	w2, #0xffff                	// #65535
  2c:	6b0200bf 	cmp	w5, w2
  30:	5400168d 	b.le	300 <__libc_free+0x300>
  34:	531c6ca3 	lsl	w3, w5, #4
  38:	928001e2 	mov	x2, #0xfffffffffffffff0    	// #-16
  3c:	a9bd4ffe 	stp	x30, x19, [sp, #-48]!
  40:	cb23c042 	sub	x2, x2, w3, sxtw
  44:	8b020004 	add	x4, x0, x2
  48:	f8626813 	ldr	x19, [x0, x2]
  4c:	f9400a63 	ldr	x3, [x19, #16]
  50:	eb03009f 	cmp	x4, x3
  54:	54000e01 	b.ne	214 <__libc_free+0x214>  // b.any
  58:	f9401262 	ldr	x2, [x19, #32]
  5c:	12001044 	and	w4, w2, #0x1f
  60:	d3401049 	ubfx	x9, x2, #0, #5
  64:	6b04003f 	cmp	w1, w4
  68:	54000d6c 	b.gt	214 <__libc_free+0x214>
  6c:	b9401a64 	ldr	w4, [x19, #24]
  70:	1ac12484 	lsr	w4, w4, w1
  74:	37000d04 	tbnz	w4, #0, 214 <__libc_free+0x214>
  78:	b9401e64 	ldr	w4, [x19, #28]
  7c:	1ac12484 	lsr	w4, w4, w1
  80:	37000ca4 	tbnz	w4, #0, 214 <__libc_free+0x214>
  84:	9274ce64 	and	x4, x19, #0xfffffffffffff000
  88:	90000007 	adrp	x7, 0 <__malloc_context>
			88: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
  8c:	f94000e7 	ldr	x7, [x7]
			8c: R_AARCH64_LDST64_ABS_LO12_NC	__malloc_context
  90:	f9400084 	ldr	x4, [x4]
  94:	eb07009f 	cmp	x4, x7
  98:	54000be1 	b.ne	214 <__libc_free+0x214>  // b.any
  9c:	53062c44 	ubfx	w4, w2, #6, #6
  a0:	7100bc9f 	cmp	w4, #0x2f
  a4:	54000b28 	b.hi	208 <__libc_free+0x208>  // b.pmore
  a8:	90000007 	adrp	x7, 0 <__malloc_size_classes>
			a8: R_AARCH64_ADR_PREL_PG_HI21	__malloc_size_classes
  ac:	910000e7 	add	x7, x7, #0x0
			ac: R_AARCH64_ADD_ABS_LO12_NC	__malloc_size_classes
  b0:	7864d8e7 	ldrh	w7, [x7, w4, sxtw #1]
  b4:	1b077c28 	mul	w8, w1, w7
  b8:	6b0800bf 	cmp	w5, w8
  bc:	54000acb 	b.lt	214 <__libc_free+0x214>  // b.tstop
  c0:	0b0800e7 	add	w7, w7, w8
  c4:	6b0700bf 	cmp	w5, w7
  c8:	54000a6a 	b.ge	214 <__libc_free+0x214>  // b.tcont
  cc:	f13ffc5f 	cmp	x2, #0xfff
  d0:	54000129 	b.ls	f4 <__libc_free+0xf4>  // b.plast
  d4:	9274cc47 	and	x7, x2, #0xfffffffffffff000
  d8:	d344fce8 	lsr	x8, x7, #4
  dc:	d1000508 	sub	x8, x8, #0x1
  e0:	eb25c11f 	cmp	x8, w5, sxtw
  e4:	54000983 	b.cc	214 <__libc_free+0x214>  // b.lo, b.ul, b.last
  e8:	d10040e7 	sub	x7, x7, #0x10
  ec:	f240105f 	tst	x2, #0x1f
  f0:	540000a0 	b.eq	104 <__libc_free+0x104>  // b.none
  f4:	90000002 	adrp	x2, 0 <__malloc_size_classes>
			f4: R_AARCH64_ADR_PREL_PG_HI21	__malloc_size_classes
  f8:	91000042 	add	x2, x2, #0x0
			f8: R_AARCH64_ADD_ABS_LO12_NC	__malloc_size_classes
  fc:	7864d847 	ldrh	w7, [x2, w4, sxtw #1]
 100:	d37c3ce7 	ubfiz	x7, x7, #4, #16
 104:	d10010e4 	sub	x4, x7, #0x4
 108:	2a0103e2 	mov	w2, w1
 10c:	91004063 	add	x3, x3, #0x10
 110:	53057cc5 	lsr	w5, w6, #5
 114:	9b071042 	madd	x2, x2, x7, x4
 118:	8b020064 	add	x4, x3, x2
 11c:	71027cdf 	cmp	w6, #0x9f
 120:	54000109 	b.ls	140 <__libc_free+0x140>  // b.plast
 124:	710014bf 	cmp	w5, #0x5
 128:	54000761 	b.ne	214 <__libc_free+0x214>  // b.any
 12c:	b85fc085 	ldur	w5, [x4, #-4]
 130:	f10010bf 	cmp	x5, #0x4
 134:	54000709 	b.ls	214 <__libc_free+0x214>  // b.plast
 138:	385fb086 	ldurb	w6, [x4, #-5]
 13c:	350006c6 	cbnz	w6, 214 <__libc_free+0x214>
 140:	cb000086 	sub	x6, x4, x0
 144:	eb0500df 	cmp	x6, x5
 148:	54000663 	b.cc	214 <__libc_free+0x214>  // b.lo, b.ul, b.last
 14c:	cb050084 	sub	x4, x4, x5
 150:	39400084 	ldrb	w4, [x4]
 154:	35000604 	cbnz	w4, 214 <__libc_free+0x214>
 158:	38626862 	ldrb	w2, [x3, x2]
 15c:	350005c2 	cbnz	w2, 214 <__libc_free+0x214>
 160:	90000008 	adrp	x8, 0 <__libc>
			160: R_AARCH64_ADR_PREL_PG_HI21	__libc
 164:	91000102 	add	x2, x8, #0x0
			164: R_AARCH64_ADD_ABS_LO12_NC	__libc
 168:	12800003 	mov	w3, #0xffffffff            	// #-1
 16c:	381fd003 	sturb	w3, [x0, #-3]
 170:	781fe01f 	sturh	wzr, [x0, #-2]
 174:	52800046 	mov	w6, #0x2                   	// #2
 178:	52800025 	mov	w5, #0x1                   	// #1
 17c:	1ac920c6 	lsl	w6, w6, w9
 180:	39400c40 	ldrb	w0, [x2, #3]
 184:	510004c6 	sub	w6, w6, #0x1
 188:	1ac120a5 	lsl	w5, w5, w1
 18c:	72001c1f 	tst	w0, #0xff
 190:	54000101 	b.ne	1b0 <__libc_free+0x1b0>  // b.any
 194:	f9401260 	ldr	x0, [x19, #32]
 198:	53062c02 	ubfx	w2, w0, #6, #6
 19c:	7100bc5f 	cmp	w2, #0x2f
 1a0:	54000088 	b.hi	1b0 <__libc_free+0x1b0>  // b.pmore
 1a4:	f9400663 	ldr	x3, [x19, #8]
 1a8:	eb13007f 	cmp	x3, x19
 1ac:	54000380 	b.eq	21c <__libc_free+0x21c>  // b.none
 1b0:	91000107 	add	x7, x8, #0x0
			1b0: R_AARCH64_ADD_ABS_LO12_NC	__libc
 1b4:	b9401e64 	ldr	w4, [x19, #28]
 1b8:	b9401a60 	ldr	w0, [x19, #24]
 1bc:	2a000080 	orr	w0, w4, w0
 1c0:	6a0000bf 	tst	w5, w0
 1c4:	54000281 	b.ne	214 <__libc_free+0x214>  // b.any
 1c8:	340005c4 	cbz	w4, 280 <__libc_free+0x280>
 1cc:	0b0000a0 	add	w0, w5, w0
 1d0:	6b06001f 	cmp	w0, w6
 1d4:	54000560 	b.eq	280 <__libc_free+0x280>  // b.none
 1d8:	39400ce0 	ldrb	w0, [x7, #3]
 1dc:	0b0400a2 	add	w2, w5, w4
 1e0:	72001c1f 	tst	w0, #0xff
 1e4:	54000460 	b.eq	270 <__libc_free+0x270>  // b.none
 1e8:	91007260 	add	x0, x19, #0x1c
 1ec:	885ffc03 	ldaxr	w3, [x0]
 1f0:	6b03009f 	cmp	w4, w3
 1f4:	54000421 	b.ne	278 <__libc_free+0x278>  // b.any
 1f8:	8803fc02 	stlxr	w3, w2, [x0]
 1fc:	35ffff83 	cbnz	w3, 1ec <__libc_free+0x1ec>
 200:	a8c34ffe 	ldp	x30, x19, [sp], #48
 204:	d65f03c0 	ret
 208:	927a1447 	and	x7, x2, #0xfc0
 20c:	f13f00ff 	cmp	x7, #0xfc0
 210:	54fff5e0 	b.eq	cc <__libc_free+0xcc>  // b.none
 214:	a90157f4 	stp	x20, x21, [sp, #16]
 218:	d4207d00 	brk	#0x3e8
 21c:	90000003 	adrp	x3, 0 <__malloc_size_classes>
			21c: R_AARCH64_ADR_PREL_PG_HI21	__malloc_size_classes
 220:	91000063 	add	x3, x3, #0x0
			220: R_AARCH64_ADD_ABS_LO12_NC	__malloc_size_classes
 224:	7862d862 	ldrh	w2, [x3, w2, sxtw #1]
 228:	d37c3c42 	ubfiz	x2, x2, #4, #16
 22c:	eb07005f 	cmp	x2, x7
 230:	54fffc08 	b.hi	1b0 <__libc_free+0x1b0>  // b.pmore
 234:	f13ffc1f 	cmp	x0, #0xfff
 238:	540000a9 	b.ls	24c <__libc_free+0x24c>  // b.plast
 23c:	9274cc00 	and	x0, x0, #0xfffffffffffff000
 240:	f140801f 	cmp	x0, #0x20, lsl #12
 244:	54fffb68 	b.hi	1b0 <__libc_free+0x1b0>  // b.pmore
 248:	14000006 	b	260 <__libc_free+0x260>
 24c:	92401000 	and	x0, x0, #0x1f
 250:	9b071c07 	madd	x7, x0, x7, x7
 254:	910040e0 	add	x0, x7, #0x10
 258:	f140801f 	cmp	x0, #0x20, lsl #12
 25c:	54fffaa8 	b.hi	1b0 <__libc_free+0x1b0>  // b.pmore
 260:	b9401e60 	ldr	w0, [x19, #28]
 264:	2a0000a5 	orr	w5, w5, w0
 268:	b9001e65 	str	w5, [x19, #28]
 26c:	17ffffe5 	b	200 <__libc_free+0x200>
 270:	b9001e62 	str	w2, [x19, #28]
 274:	17ffffe3 	b	200 <__libc_free+0x200>
 278:	d5033bbf 	dmb	ish
 27c:	17ffffce 	b	1b4 <__libc_free+0x1b4>
 280:	91000108 	add	x8, x8, #0x0
			280: R_AARCH64_ADD_ABS_LO12_NC	__libc
 284:	a90157f4 	stp	x20, x21, [sp, #16]
 288:	90000014 	adrp	x20, 0 <__malloc_lock>
			288: R_AARCH64_ADR_PREL_PG_HI21	__malloc_lock
 28c:	39400d00 	ldrb	w0, [x8, #3]
 290:	72001c1f 	tst	w0, #0xff
 294:	54000161 	b.ne	2c0 <__libc_free+0x2c0>  // b.any
 298:	aa1303e0 	mov	x0, x19
 29c:	94000000 	bl	0 <__libc_free>
			29c: R_AARCH64_CALL26	.text.nontrivial_free
 2a0:	b9400282 	ldr	w2, [x20]
			2a0: R_AARCH64_LDST32_ABS_LO12_NC	__malloc_lock
 2a4:	aa0003f5 	mov	x21, x0
 2a8:	aa0103f3 	mov	x19, x1
 2ac:	91000280 	add	x0, x20, #0x0
			2ac: R_AARCH64_ADD_ABS_LO12_NC	__malloc_lock
 2b0:	37f80122 	tbnz	w2, #31, 2d4 <__libc_free+0x2d4>
 2b4:	b5000153 	cbnz	x19, 2dc <__libc_free+0x2dc>
 2b8:	a94157f4 	ldp	x20, x21, [sp, #16]
 2bc:	17ffffd1 	b	200 <__libc_free+0x200>
 2c0:	91000280 	add	x0, x20, #0x0
			2c0: R_AARCH64_ADD_ABS_LO12_NC	__malloc_lock
 2c4:	b9002fe1 	str	w1, [sp, #44]
 2c8:	94000000 	bl	0 <__lock>
			2c8: R_AARCH64_CALL26	__lock
 2cc:	b9402fe1 	ldr	w1, [sp, #44]
 2d0:	17fffff2 	b	298 <__libc_free+0x298>
 2d4:	94000000 	bl	0 <__unlock>
			2d4: R_AARCH64_CALL26	__unlock
 2d8:	17fffff7 	b	2b4 <__libc_free+0x2b4>
 2dc:	94000000 	bl	0 <___errno_location>
			2dc: R_AARCH64_CALL26	___errno_location
 2e0:	aa0003f4 	mov	x20, x0
 2e4:	aa1303e1 	mov	x1, x19
 2e8:	aa1503e0 	mov	x0, x21
 2ec:	b9400293 	ldr	w19, [x20]
 2f0:	94000000 	bl	0 <munmap>
			2f0: R_AARCH64_CALL26	munmap
 2f4:	b9000293 	str	w19, [x20]
 2f8:	a94157f4 	ldp	x20, x21, [sp, #16]
 2fc:	17ffffc1 	b	200 <__libc_free+0x200>
 300:	d4207d00 	brk	#0x3e8
 304:	d65f03c0 	ret

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

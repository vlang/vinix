
/Users/alex/code/vinix/third_party/useralloc-libc/build/musl/aarch64/8adbe7fc2d9d74c610f67eb2cab1fe514a0da223a0d1c9f5158aa5374a4282ad/objects/obj/src/malloc/mallocng/free.o:     file format elf64-littleaarch64


Disassembly of section .text.free_group:

0000000000000000 <free_group>:
   0:	a9bf4ffe 	stp	x30, x19, [sp, #-16]!
   4:	aa0003f3 	mov	x19, x0
   8:	f9401004 	ldr	x4, [x0, #32]
   c:	53062c85 	ubfx	w5, w4, #6, #6
  10:	7100fcbf 	cmp	w5, #0x3f
  14:	540005a0 	b.eq	c8 <free_group+0xc8>  // b.none
  18:	7100bcbf 	cmp	w5, #0x2f
  1c:	5400018c 	b.gt	4c <free_group+0x4c>
  20:	d37d14a0 	ubfiz	x0, x5, #3, #6
  24:	90000002 	adrp	x2, 0 <__malloc_context>
			24: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
  28:	9107c000 	add	x0, x0, #0x1f0
  2c:	91000042 	add	x2, x2, #0x0
			2c: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
  30:	8b000042 	add	x2, x2, x0
  34:	92401084 	and	x4, x4, #0x1f
  38:	91000484 	add	x4, x4, #0x1
  3c:	f9400440 	ldr	x0, [x2, #8]
  40:	cb040000 	sub	x0, x0, x4
  44:	f9000440 	str	x0, [x2, #8]
  48:	f9401264 	ldr	x4, [x19, #32]
  4c:	f13ffc9f 	cmp	x4, #0xfff
  50:	54000a89 	b.ls	1a0 <free_group+0x1a0>  // b.plast
  54:	90000002 	adrp	x2, 0 <__malloc_context>
			54: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
  58:	91000042 	add	x2, x2, #0x0
			58: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
  5c:	394ee041 	ldrb	w1, [x2, #952]
  60:	11000420 	add	w0, w1, #0x1
  64:	12001c00 	and	w0, w0, #0xff
  68:	7103fc3f 	cmp	w1, #0xff
  6c:	54000880 	b.eq	17c <free_group+0x17c>  // b.none
  70:	51001ca5 	sub	w5, w5, #0x7
  74:	390ee040 	strb	w0, [x2, #952]
  78:	71007cbf 	cmp	w5, #0x1f
  7c:	54000068 	b.hi	88 <free_group+0x88>  // b.pmore
  80:	8b25c045 	add	x5, x2, w5, sxtw
  84:	390de0a0 	strb	w0, [x5, #888]
  88:	f9401261 	ldr	x1, [x19, #32]
  8c:	f9400a60 	ldr	x0, [x19, #16]
  90:	9274cc21 	and	x1, x1, #0xfffffffffffff000
  94:	a9007e7f 	stp	xzr, xzr, [x19]
  98:	a9017e7f 	stp	xzr, xzr, [x19, #16]
  9c:	f9400843 	ldr	x3, [x2, #16]
  a0:	f900127f 	str	xzr, [x19, #32]
  a4:	b4001003 	cbz	x3, 2a4 <free_group+0x2a4>
  a8:	f9000663 	str	x3, [x19, #8]
  ac:	f9400062 	ldr	x2, [x3]
  b0:	f9000262 	str	x2, [x19]
  b4:	f9000453 	str	x19, [x2, #8]
  b8:	f9400662 	ldr	x2, [x19, #8]
  bc:	f9000053 	str	x19, [x2]
  c0:	a8c14ffe 	ldp	x30, x19, [sp], #16
  c4:	d65f03c0 	ret
  c8:	d34cfc86 	lsr	x6, x4, #12
  cc:	d10080c0 	sub	x0, x6, #0x20
  d0:	f107801f 	cmp	x0, #0x1e0
  d4:	54fffbc8 	b.hi	4c <free_group+0x4c>  // b.pmore
  d8:	d2800400 	mov	x0, #0x20                  	// #32
  dc:	52800001 	mov	w1, #0x0                   	// #0
  e0:	14000003 	b	ec <free_group+0xec>
  e4:	11000421 	add	w1, w1, #0x1
  e8:	d37ff800 	lsl	x0, x0, #1
  ec:	eb0000df 	cmp	x6, x0
  f0:	54ffffa8 	b.hi	e4 <free_group+0xe4>  // b.pmore
  f4:	93407c23 	sxtw	x3, w1
  f8:	90000002 	adrp	x2, 0 <__malloc_context>
			f8: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
  fc:	9100e860 	add	x0, x3, #0x3a
 100:	91000042 	add	x2, x2, #0x0
			100: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 104:	f8607840 	ldr	x0, [x2, x0, lsl #3]
 108:	b40002e0 	cbz	x0, 164 <free_group+0x164>
 10c:	f9401001 	ldr	x1, [x0, #32]
 110:	d34cfc21 	lsr	x1, x1, #12
 114:	eb0100df 	cmp	x6, x1
 118:	54fff9a9 	b.ls	4c <free_group+0x4c>  // b.plast
 11c:	f9400805 	ldr	x5, [x0, #16]
 120:	a9007c1f 	stp	xzr, xzr, [x0]
 124:	a9017c1f 	stp	xzr, xzr, [x0, #16]
 128:	f9400844 	ldr	x4, [x2, #16]
 12c:	f900101f 	str	xzr, [x0, #32]
 130:	b4000144 	cbz	x4, 158 <free_group+0x158>
 134:	f9000404 	str	x4, [x0, #8]
 138:	f9400084 	ldr	x4, [x4]
 13c:	f9000004 	str	x4, [x0]
 140:	f9000480 	str	x0, [x4, #8]
 144:	f9400404 	ldr	x4, [x0, #8]
 148:	f9000080 	str	x0, [x4]
 14c:	d3747c21 	ubfiz	x1, x1, #12, #32
 150:	aa0503e0 	mov	x0, x5
 154:	14000005 	b	168 <free_group+0x168>
 158:	a9000000 	stp	x0, x0, [x0]
 15c:	f9000840 	str	x0, [x2, #16]
 160:	17fffffb 	b	14c <free_group+0x14c>
 164:	d2800001 	mov	x1, #0x0                   	// #0
 168:	9100e863 	add	x3, x3, #0x3a
 16c:	52800024 	mov	w4, #0x1                   	// #1
 170:	b9001e64 	str	w4, [x19, #28]
 174:	f8237853 	str	x19, [x2, x3, lsl #3]
 178:	17ffffd2 	b	c0 <free_group+0xc0>
 17c:	90000001 	adrp	x1, 0 <__malloc_context>
			17c: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context+0x378
 180:	910e6040 	add	x0, x2, #0x398
 184:	91000021 	add	x1, x1, #0x0
			184: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context+0x378
 188:	14000002 	b	190 <free_group+0x190>
 18c:	3800143f 	strb	wzr, [x1], #1
 190:	eb00003f 	cmp	x1, x0
 194:	54ffffc1 	b.ne	18c <free_group+0x18c>  // b.any
 198:	52800020 	mov	w0, #0x1                   	// #1
 19c:	17ffffb5 	b	70 <free_group+0x70>
 1a0:	f9400a63 	ldr	x3, [x19, #16]
 1a4:	f2400c7f 	tst	x3, #0xf
 1a8:	540007c1 	b.ne	2a0 <free_group+0x2a0>  // b.any
 1ac:	385fc060 	ldurb	w0, [x3, #-4]
 1b0:	385fd061 	ldurb	w1, [x3, #-3]
 1b4:	785fe067 	ldurh	w7, [x3, #-2]
 1b8:	12001021 	and	w1, w1, #0x1f
 1bc:	340000c0 	cbz	w0, 1d4 <free_group+0x1d4>
 1c0:	35000707 	cbnz	w7, 2a0 <free_group+0x2a0>
 1c4:	b85f8067 	ldur	w7, [x3, #-8]
 1c8:	529fffe0 	mov	w0, #0xffff                	// #65535
 1cc:	6b0000ff 	cmp	w7, w0
 1d0:	5400068d 	b.le	2a0 <free_group+0x2a0>
 1d4:	531c6ce2 	lsl	w2, w7, #4
 1d8:	928001e0 	mov	x0, #0xfffffffffffffff0    	// #-16
 1dc:	cb22c000 	sub	x0, x0, w2, sxtw
 1e0:	8b000064 	add	x4, x3, x0
 1e4:	f8606860 	ldr	x0, [x3, x0]
 1e8:	f9400802 	ldr	x2, [x0, #16]
 1ec:	eb02009f 	cmp	x4, x2
 1f0:	54000581 	b.ne	2a0 <free_group+0x2a0>  // b.any
 1f4:	f9401004 	ldr	x4, [x0, #32]
 1f8:	12001082 	and	w2, w4, #0x1f
 1fc:	6b02003f 	cmp	w1, w2
 200:	5400050c 	b.gt	2a0 <free_group+0x2a0>
 204:	b9401802 	ldr	w2, [x0, #24]
 208:	1ac12442 	lsr	w2, w2, w1
 20c:	370004a2 	tbnz	w2, #0, 2a0 <free_group+0x2a0>
 210:	b9401c02 	ldr	w2, [x0, #28]
 214:	1ac12442 	lsr	w2, w2, w1
 218:	37000442 	tbnz	w2, #0, 2a0 <free_group+0x2a0>
 21c:	9274cc05 	and	x5, x0, #0xfffffffffffff000
 220:	90000002 	adrp	x2, 0 <__malloc_context>
			220: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
 224:	f9400046 	ldr	x6, [x2]
			224: R_AARCH64_LDST64_ABS_LO12_NC	__malloc_context
 228:	f94000a2 	ldr	x2, [x5]
 22c:	eb06005f 	cmp	x2, x6
 230:	54000381 	b.ne	2a0 <free_group+0x2a0>  // b.any
 234:	53062c82 	ubfx	w2, w4, #6, #6
 238:	7100bc5f 	cmp	w2, #0x2f
 23c:	540002c8 	b.hi	294 <free_group+0x294>  // b.pmore
 240:	90000005 	adrp	x5, 0 <__malloc_size_classes>
			240: R_AARCH64_ADR_PREL_PG_HI21	__malloc_size_classes
 244:	910000a5 	add	x5, x5, #0x0
			244: R_AARCH64_ADD_ABS_LO12_NC	__malloc_size_classes
 248:	7862d8a2 	ldrh	w2, [x5, w2, sxtw #1]
 24c:	1b027c25 	mul	w5, w1, w2
 250:	6b0500ff 	cmp	w7, w5
 254:	5400026b 	b.lt	2a0 <free_group+0x2a0>  // b.tstop
 258:	0b050042 	add	w2, w2, w5
 25c:	6b0200ff 	cmp	w7, w2
 260:	5400020a 	b.ge	2a0 <free_group+0x2a0>  // b.tcont
 264:	f13ffc9f 	cmp	x4, #0xfff
 268:	540000c9 	b.ls	280 <free_group+0x280>  // b.plast
 26c:	9274cc82 	and	x2, x4, #0xfffffffffffff000
 270:	d344fc42 	lsr	x2, x2, #4
 274:	d1000442 	sub	x2, x2, #0x1
 278:	eb27c05f 	cmp	x2, w7, sxtw
 27c:	54000123 	b.cc	2a0 <free_group+0x2a0>  // b.lo, b.ul, b.last
 280:	f900007f 	str	xzr, [x3]
 284:	94000000 	bl	0 <free_group>
			284: R_AARCH64_CALL26	.text.nontrivial_free
 288:	90000002 	adrp	x2, 0 <__malloc_context>
			288: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
 28c:	91000042 	add	x2, x2, #0x0
			28c: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 290:	17ffff81 	b	94 <free_group+0x94>
 294:	927a1482 	and	x2, x4, #0xfc0
 298:	f13f005f 	cmp	x2, #0xfc0
 29c:	54fffe40 	b.eq	264 <free_group+0x264>  // b.none
 2a0:	d4207d00 	brk	#0x3e8
 2a4:	a9004e73 	stp	x19, x19, [x19]
 2a8:	f9000853 	str	x19, [x2, #16]
 2ac:	17ffff85 	b	c0 <free_group+0xc0>

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
  48:	93407ca7 	sxtw	x7, w5
  4c:	90000002 	adrp	x2, 0 <__malloc_context>
			4c: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
  50:	91000042 	add	x2, x2, #0x0
			50: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
  54:	910028e3 	add	x3, x7, #0xa
  58:	f8637843 	ldr	x3, [x2, x3, lsl #3]
  5c:	eb00007f 	cmp	x3, x0
  60:	54000180 	b.eq	90 <nontrivial_free+0x90>  // b.none
  64:	f9400404 	ldr	x4, [x0, #8]
  68:	b5000c24 	cbnz	x4, 1ec <nontrivial_free+0x1ec>
  6c:	f9400004 	ldr	x4, [x0]
  70:	b5000be4 	cbnz	x4, 1ec <nontrivial_free+0x1ec>
  74:	b4000703 	cbz	x3, 154 <nontrivial_free+0x154>
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
  a0:	54001181 	b.ne	2d0 <nontrivial_free+0x2d0>  // b.any
  a4:	b9401c02 	ldr	w2, [x0, #28]
  a8:	2a010041 	orr	w1, w2, w1
  ac:	b9001c01 	str	w1, [x0, #28]
  b0:	d2800000 	mov	x0, #0x0                   	// #0
  b4:	d2800001 	mov	x1, #0x0                   	// #0
  b8:	d65f03c0 	ret
  bc:	362ffc03 	tbz	w3, #5, 3c <nontrivial_free+0x3c>
  c0:	f9400406 	ldr	x6, [x0, #8]
  c4:	7100bcbf 	cmp	w5, #0x2f
  c8:	5400090c 	b.gt	1e8 <nontrivial_free+0x1e8>
  cc:	90000002 	adrp	x2, 0 <__malloc_size_classes>
			cc: R_AARCH64_ADR_PREL_PG_HI21	__malloc_size_classes
  d0:	91000042 	add	x2, x2, #0x0
			d0: R_AARCH64_ADD_ABS_LO12_NC	__malloc_size_classes
  d4:	92401067 	and	x7, x3, #0x1f
  d8:	f13ffc7f 	cmp	x3, #0xfff
  dc:	fa4088e0 	ccmp	x7, #0x0, #0x0, hi	// hi = pmore
  e0:	93407ca7 	sxtw	x7, w5
  e4:	7865d849 	ldrh	w9, [x2, w5, sxtw #1]
  e8:	54000120 	b.eq	10c <nontrivial_free+0x10c>  // b.none
  ec:	eb06001f 	cmp	x0, x6
  f0:	540005a0 	b.eq	1a4 <nontrivial_free+0x1a4>  // b.none
  f4:	b4000386 	cbz	x6, 164 <nontrivial_free+0x164>
  f8:	910028e1 	add	x1, x7, #0xa
  fc:	90000002 	adrp	x2, 0 <__malloc_context>
			fc: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
 100:	91000042 	add	x2, x2, #0x0
			100: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 104:	f8617841 	ldr	x1, [x2, x1, lsl #3]
 108:	14000041 	b	20c <nontrivial_free+0x20c>
 10c:	9274cc63 	and	x3, x3, #0xfffffffffffff000
 110:	d37c3d29 	ubfiz	x9, x9, #4, #16
 114:	d1004062 	sub	x2, x3, #0x10
 118:	eb09005f 	cmp	x2, x9
 11c:	540006a3 	b.cc	1f0 <nontrivial_free+0x1f0>  // b.lo, b.ul, b.last
 120:	eb06001f 	cmp	x0, x6
 124:	54000e20 	b.eq	2e8 <nontrivial_free+0x2e8>  // b.none
 128:	b5fffe86 	cbnz	x6, f8 <nontrivial_free+0xf8>
 12c:	910028e5 	add	x5, x7, #0xa
 130:	90000002 	adrp	x2, 0 <__malloc_context>
			130: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
 134:	91000042 	add	x2, x2, #0x0
			134: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 138:	f8657845 	ldr	x5, [x2, x5, lsl #3]
 13c:	b50007e5 	cbnz	x5, 238 <nontrivial_free+0x238>
 140:	f140807f 	cmp	x3, #0x20, lsl #12
 144:	540007a8 	b.hi	238 <nontrivial_free+0x238>  // b.pmore
 148:	35fffa44 	cbnz	w4, 90 <nontrivial_free+0x90>
 14c:	f9400003 	ldr	x3, [x0]
 150:	b50004e3 	cbnz	x3, 1ec <nontrivial_free+0x1ec>
 154:	910028e7 	add	x7, x7, #0xa
 158:	a9000000 	stp	x0, x0, [x0]
 15c:	f8277840 	str	x0, [x2, x7, lsl #3]
 160:	17ffffcc 	b	90 <nontrivial_free+0x90>
 164:	910028e5 	add	x5, x7, #0xa
 168:	90000002 	adrp	x2, 0 <__malloc_context>
			168: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
 16c:	91000042 	add	x2, x2, #0x0
			16c: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 170:	f8657845 	ldr	x5, [x2, x5, lsl #3]
 174:	b5000625 	cbnz	x5, 238 <nontrivial_free+0x238>
 178:	f13ffc7f 	cmp	x3, #0xfff
 17c:	540000c8 	b.hi	194 <nontrivial_free+0x194>  // b.pmore
 180:	1b092509 	madd	w9, w8, w9, w9
 184:	11000522 	add	w2, w9, #0x1
 188:	7140085f 	cmp	w2, #0x2, lsl #12
 18c:	5400018d 	b.le	1bc <nontrivial_free+0x1bc>
 190:	1400002a 	b	238 <nontrivial_free+0x238>
 194:	9274cc63 	and	x3, x3, #0xfffffffffffff000
 198:	f140807f 	cmp	x3, #0x20, lsl #12
 19c:	540004e8 	b.hi	238 <nontrivial_free+0x238>  // b.pmore
 1a0:	17ffffea 	b	148 <nontrivial_free+0x148>
 1a4:	f13ffc7f 	cmp	x3, #0xfff
 1a8:	540000e8 	b.hi	1c4 <nontrivial_free+0x1c4>  // b.pmore
 1ac:	1b092509 	madd	w9, w8, w9, w9
 1b0:	11000522 	add	w2, w9, #0x1
 1b4:	7140085f 	cmp	w2, #0x2, lsl #12
 1b8:	5400012c 	b.gt	1dc <nontrivial_free+0x1dc>
 1bc:	35fff6a4 	cbnz	w4, 90 <nontrivial_free+0x90>
 1c0:	17ffffa3 	b	4c <nontrivial_free+0x4c>
 1c4:	9274cc63 	and	x3, x3, #0xfffffffffffff000
 1c8:	f140807f 	cmp	x3, #0x20, lsl #12
 1cc:	54ffff89 	b.ls	1bc <nontrivial_free+0x1bc>  // b.plast
 1d0:	51001ca5 	sub	w5, w5, #0x7
 1d4:	71007cbf 	cmp	w5, #0x1f
 1d8:	54000a09 	b.ls	318 <nontrivial_free+0x318>  // b.plast
 1dc:	90000002 	adrp	x2, 0 <__malloc_context>
			1dc: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
 1e0:	91000042 	add	x2, x2, #0x0
			1e0: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 1e4:	14000006 	b	1fc <nontrivial_free+0x1fc>
 1e8:	b4000286 	cbz	x6, 238 <nontrivial_free+0x238>
 1ec:	d4207d00 	brk	#0x3e8
 1f0:	90000002 	adrp	x2, 0 <__malloc_context>
			1f0: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
 1f4:	91000042 	add	x2, x2, #0x0
			1f4: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 1f8:	b4000206 	cbz	x6, 238 <nontrivial_free+0x238>
 1fc:	910028e1 	add	x1, x7, #0xa
 200:	f8617841 	ldr	x1, [x2, x1, lsl #3]
 204:	eb06001f 	cmp	x0, x6
 208:	54000820 	b.eq	30c <nontrivial_free+0x30c>  // b.none
 20c:	f9400004 	ldr	x4, [x0]
 210:	910028e3 	add	x3, x7, #0xa
 214:	f9000486 	str	x6, [x4, #8]
 218:	f9400004 	ldr	x4, [x0]
 21c:	f90000c4 	str	x4, [x6]
 220:	f8637844 	ldr	x4, [x2, x3, lsl #3]
 224:	eb04001f 	cmp	x0, x4
 228:	540000a0 	b.eq	23c <nontrivial_free+0x23c>  // b.none
 22c:	a9007c1f 	stp	xzr, xzr, [x0]
 230:	eb01001f 	cmp	x0, x1
 234:	540000a0 	b.eq	248 <nontrivial_free+0x248>  // b.none
 238:	14000000 	b	0 <nontrivial_free>
			238: R_AARCH64_JUMP26	.text.free_group
 23c:	f9400404 	ldr	x4, [x0, #8]
 240:	f8237844 	str	x4, [x2, x3, lsl #3]
 244:	17fffffa 	b	22c <nontrivial_free+0x22c>
 248:	910028e7 	add	x7, x7, #0xa
 24c:	f8677845 	ldr	x5, [x2, x7, lsl #3]
 250:	b4ffff45 	cbz	x5, 238 <nontrivial_free+0x238>
 254:	b94018a1 	ldr	w1, [x5, #24]
 258:	35fffca1 	cbnz	w1, 1ec <nontrivial_free+0x1ec>
 25c:	f94008a1 	ldr	x1, [x5, #16]
 260:	90000002 	adrp	x2, 0 <__libc>
			260: R_AARCH64_ADR_PREL_PG_HI21	__libc
 264:	91000042 	add	x2, x2, #0x0
			264: R_AARCH64_ADD_ABS_LO12_NC	__libc
 268:	52800046 	mov	w6, #0x2                   	// #2
 26c:	910070a3 	add	x3, x5, #0x1c
 270:	f9400421 	ldr	x1, [x1, #8]
 274:	39400c42 	ldrb	w2, [x2, #3]
 278:	d3401021 	ubfx	x1, x1, #0, #5
 27c:	1ac120c6 	lsl	w6, w6, w1
 280:	510004c8 	sub	w8, w6, #0x1
 284:	4b0603e6 	neg	w6, w6
 288:	72001c5f 	tst	w2, #0xff
 28c:	540000c1 	b.ne	2a4 <nontrivial_free+0x2a4>  // b.any
 290:	b9401ca7 	ldr	w7, [x5, #28]
 294:	0a0700c6 	and	w6, w6, w7
 298:	b9001ca6 	str	w6, [x5, #28]
 29c:	1400000a 	b	2c4 <nontrivial_free+0x2c4>
 2a0:	d5033bbf 	dmb	ish
 2a4:	b9401ca4 	ldr	w4, [x5, #28]
 2a8:	2a0403e7 	mov	w7, w4
 2ac:	0a0400c2 	and	w2, w6, w4
 2b0:	885ffc61 	ldaxr	w1, [x3]
 2b4:	6b01009f 	cmp	w4, w1
 2b8:	54ffff41 	b.ne	2a0 <nontrivial_free+0x2a0>  // b.any
 2bc:	8801fc62 	stlxr	w1, w2, [x3]
 2c0:	35ffff81 	cbnz	w1, 2b0 <nontrivial_free+0x2b0>
 2c4:	0a070101 	and	w1, w8, w7
 2c8:	b90018a1 	str	w1, [x5, #24]
 2cc:	17ffffdb 	b	238 <nontrivial_free+0x238>
 2d0:	91007002 	add	x2, x0, #0x1c
 2d4:	885ffc40 	ldaxr	w0, [x2]
 2d8:	2a010000 	orr	w0, w0, w1
 2dc:	8803fc40 	stlxr	w3, w0, [x2]
 2e0:	35ffffa3 	cbnz	w3, 2d4 <nontrivial_free+0x2d4>
 2e4:	17ffff73 	b	b0 <nontrivial_free+0xb0>
 2e8:	f140807f 	cmp	x3, #0x20, lsl #12
 2ec:	54fff689 	b.ls	1bc <nontrivial_free+0x1bc>  // b.plast
 2f0:	51001ca5 	sub	w5, w5, #0x7
 2f4:	71007cbf 	cmp	w5, #0x1f
 2f8:	54000109 	b.ls	318 <nontrivial_free+0x318>  // b.plast
 2fc:	910028e1 	add	x1, x7, #0xa
 300:	90000002 	adrp	x2, 0 <__malloc_context>
			300: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
 304:	91000042 	add	x2, x2, #0x0
			304: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 308:	f8617841 	ldr	x1, [x2, x1, lsl #3]
 30c:	910028e3 	add	x3, x7, #0xa
 310:	f823785f 	str	xzr, [x2, x3, lsl #3]
 314:	17ffffc6 	b	22c <nontrivial_free+0x22c>
 318:	90000002 	adrp	x2, 0 <__malloc_context>
			318: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
 31c:	91000042 	add	x2, x2, #0x0
			31c: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 320:	8b25c045 	add	x5, x2, w5, sxtw
 324:	394e60a3 	ldrb	w3, [x5, #920]
 328:	71018c7f 	cmp	w3, #0x63
 32c:	54fff689 	b.ls	1fc <nontrivial_free+0x1fc>  // b.plast
 330:	8b070c45 	add	x5, x2, x7, lsl #3
 334:	11000509 	add	w9, w8, #0x1
 338:	d37d1523 	ubfiz	x3, x9, #3, #6
 33c:	f940fca5 	ldr	x5, [x5, #504]
 340:	8b090063 	add	x3, x3, x9
 344:	eb0300bf 	cmp	x5, x3
 348:	54000063 	b.cc	354 <nontrivial_free+0x354>  // b.lo, b.ul, b.last
 34c:	71004d3f 	cmp	w9, #0x13
 350:	54fff54d 	b.le	1f8 <nontrivial_free+0x1f8>
 354:	34ffe804 	cbz	w4, 54 <nontrivial_free+0x54>
 358:	17ffff4e 	b	90 <nontrivial_free+0x90>

Disassembly of section .text.__libc_free:

0000000000000000 <__libc_free>:
   0:	b40017e0 	cbz	x0, 2fc <__libc_free+0x2fc>
   4:	f2400c1f 	tst	x0, #0xf
   8:	54001781 	b.ne	2f8 <__libc_free+0x2f8>  // b.any
   c:	385fc002 	ldurb	w2, [x0, #-4]
  10:	385fd006 	ldurb	w6, [x0, #-3]
  14:	785fe008 	ldurh	w8, [x0, #-2]
  18:	120010c1 	and	w1, w6, #0x1f
  1c:	340000c2 	cbz	w2, 34 <__libc_free+0x34>
  20:	350016c8 	cbnz	w8, 2f8 <__libc_free+0x2f8>
  24:	b85f8008 	ldur	w8, [x0, #-8]
  28:	529fffe2 	mov	w2, #0xffff                	// #65535
  2c:	6b02011f 	cmp	w8, w2
  30:	5400164d 	b.le	2f8 <__libc_free+0x2f8>
  34:	531c6d03 	lsl	w3, w8, #4
  38:	928001e2 	mov	x2, #0xfffffffffffffff0    	// #-16
  3c:	a9bd4ffe 	stp	x30, x19, [sp, #-48]!
  40:	cb23c042 	sub	x2, x2, w3, sxtw
  44:	8b020004 	add	x4, x0, x2
  48:	f8626813 	ldr	x19, [x0, x2]
  4c:	f9400a63 	ldr	x3, [x19, #16]
  50:	eb03009f 	cmp	x4, x3
  54:	54000cc1 	b.ne	1ec <__libc_free+0x1ec>  // b.any
  58:	f9401262 	ldr	x2, [x19, #32]
  5c:	12001044 	and	w4, w2, #0x1f
  60:	d3401049 	ubfx	x9, x2, #0, #5
  64:	6b04003f 	cmp	w1, w4
  68:	54000c2c 	b.gt	1ec <__libc_free+0x1ec>
  6c:	b9401a64 	ldr	w4, [x19, #24]
  70:	1ac12484 	lsr	w4, w4, w1
  74:	37000bc4 	tbnz	w4, #0, 1ec <__libc_free+0x1ec>
  78:	b9401e64 	ldr	w4, [x19, #28]
  7c:	1ac12484 	lsr	w4, w4, w1
  80:	37000b64 	tbnz	w4, #0, 1ec <__libc_free+0x1ec>
  84:	9274ce64 	and	x4, x19, #0xfffffffffffff000
  88:	90000005 	adrp	x5, 0 <__malloc_context>
			88: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
  8c:	f94000a5 	ldr	x5, [x5]
			8c: R_AARCH64_LDST64_ABS_LO12_NC	__malloc_context
  90:	f9400084 	ldr	x4, [x4]
  94:	eb05009f 	cmp	x4, x5
  98:	54000aa1 	b.ne	1ec <__libc_free+0x1ec>  // b.any
  9c:	53062c44 	ubfx	w4, w2, #6, #6
  a0:	7100bc9f 	cmp	w4, #0x2f
  a4:	540009e8 	b.hi	1e0 <__libc_free+0x1e0>  // b.pmore
  a8:	90000005 	adrp	x5, 0 <__malloc_size_classes>
			a8: R_AARCH64_ADR_PREL_PG_HI21	__malloc_size_classes
  ac:	910000a5 	add	x5, x5, #0x0
			ac: R_AARCH64_ADD_ABS_LO12_NC	__malloc_size_classes
  b0:	7864d8a5 	ldrh	w5, [x5, w4, sxtw #1]
  b4:	1b057c27 	mul	w7, w1, w5
  b8:	6b07011f 	cmp	w8, w7
  bc:	5400098b 	b.lt	1ec <__libc_free+0x1ec>  // b.tstop
  c0:	0b0700a5 	add	w5, w5, w7
  c4:	6b05011f 	cmp	w8, w5
  c8:	5400092a 	b.ge	1ec <__libc_free+0x1ec>  // b.tcont
  cc:	f13ffc5f 	cmp	x2, #0xfff
  d0:	54000129 	b.ls	f4 <__libc_free+0xf4>  // b.plast
  d4:	9274cc47 	and	x7, x2, #0xfffffffffffff000
  d8:	d344fce5 	lsr	x5, x7, #4
  dc:	d10004a5 	sub	x5, x5, #0x1
  e0:	eb28c0bf 	cmp	x5, w8, sxtw
  e4:	54000843 	b.cc	1ec <__libc_free+0x1ec>  // b.lo, b.ul, b.last
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
 128:	54000621 	b.ne	1ec <__libc_free+0x1ec>  // b.any
 12c:	b85fc085 	ldur	w5, [x4, #-4]
 130:	f10010bf 	cmp	x5, #0x4
 134:	540005c9 	b.ls	1ec <__libc_free+0x1ec>  // b.plast
 138:	385fb086 	ldurb	w6, [x4, #-5]
 13c:	35000586 	cbnz	w6, 1ec <__libc_free+0x1ec>
 140:	cb000086 	sub	x6, x4, x0
 144:	eb0500df 	cmp	x6, x5
 148:	54000523 	b.cc	1ec <__libc_free+0x1ec>  // b.lo, b.ul, b.last
 14c:	cb050084 	sub	x4, x4, x5
 150:	39400084 	ldrb	w4, [x4]
 154:	350004c4 	cbnz	w4, 1ec <__libc_free+0x1ec>
 158:	38626862 	ldrb	w2, [x3, x2]
 15c:	35000482 	cbnz	w2, 1ec <__libc_free+0x1ec>
 160:	90000008 	adrp	x8, 0 <__libc>
			160: R_AARCH64_ADR_PREL_PG_HI21	__libc
 164:	91000108 	add	x8, x8, #0x0
			164: R_AARCH64_ADD_ABS_LO12_NC	__libc
 168:	12800002 	mov	w2, #0xffffffff            	// #-1
 16c:	381fd002 	sturb	w2, [x0, #-3]
 170:	781fe01f 	sturh	wzr, [x0, #-2]
 174:	52800046 	mov	w6, #0x2                   	// #2
 178:	52800025 	mov	w5, #0x1                   	// #1
 17c:	1ac920c6 	lsl	w6, w6, w9
 180:	39400d00 	ldrb	w0, [x8, #3]
 184:	510004c6 	sub	w6, w6, #0x1
 188:	1ac120a5 	lsl	w5, w5, w1
 18c:	72001c1f 	tst	w0, #0xff
 190:	540004a1 	b.ne	224 <__libc_free+0x224>  // b.any
 194:	f9401260 	ldr	x0, [x19, #32]
 198:	53062c02 	ubfx	w2, w0, #6, #6
 19c:	7100bc5f 	cmp	w2, #0x2f
 1a0:	54000428 	b.hi	224 <__libc_free+0x224>  // b.pmore
 1a4:	f9400663 	ldr	x3, [x19, #8]
 1a8:	eb13007f 	cmp	x3, x19
 1ac:	540003c1 	b.ne	224 <__libc_free+0x224>  // b.any
 1b0:	90000003 	adrp	x3, 0 <__malloc_size_classes>
			1b0: R_AARCH64_ADR_PREL_PG_HI21	__malloc_size_classes
 1b4:	91000063 	add	x3, x3, #0x0
			1b4: R_AARCH64_ADD_ABS_LO12_NC	__malloc_size_classes
 1b8:	7862d862 	ldrh	w2, [x3, w2, sxtw #1]
 1bc:	d37c3c42 	ubfiz	x2, x2, #4, #16
 1c0:	eb07005f 	cmp	x2, x7
 1c4:	54000308 	b.hi	224 <__libc_free+0x224>  // b.pmore
 1c8:	f13ffc1f 	cmp	x0, #0xfff
 1cc:	54000149 	b.ls	1f4 <__libc_free+0x1f4>  // b.plast
 1d0:	9274cc00 	and	x0, x0, #0xfffffffffffff000
 1d4:	f140801f 	cmp	x0, #0x20, lsl #12
 1d8:	54000268 	b.hi	224 <__libc_free+0x224>  // b.pmore
 1dc:	1400000b 	b	208 <__libc_free+0x208>
 1e0:	927a1445 	and	x5, x2, #0xfc0
 1e4:	f13f00bf 	cmp	x5, #0xfc0
 1e8:	54fff720 	b.eq	cc <__libc_free+0xcc>  // b.none
 1ec:	a90157f4 	stp	x20, x21, [sp, #16]
 1f0:	d4207d00 	brk	#0x3e8
 1f4:	92401000 	and	x0, x0, #0x1f
 1f8:	9b071c07 	madd	x7, x0, x7, x7
 1fc:	910040e0 	add	x0, x7, #0x10
 200:	f140801f 	cmp	x0, #0x20, lsl #12
 204:	54000108 	b.hi	224 <__libc_free+0x224>  // b.pmore
 208:	b9401e60 	ldr	w0, [x19, #28]
 20c:	2a0000a5 	orr	w5, w5, w0
 210:	b9001e65 	str	w5, [x19, #28]
 214:	14000017 	b	270 <__libc_free+0x270>
 218:	b9001e62 	str	w2, [x19, #28]
 21c:	14000015 	b	270 <__libc_free+0x270>
 220:	d5033bbf 	dmb	ish
 224:	b9401e64 	ldr	w4, [x19, #28]
 228:	b9401a60 	ldr	w0, [x19, #24]
 22c:	2a000080 	orr	w0, w4, w0
 230:	6a0000bf 	tst	w5, w0
 234:	54fffdc1 	b.ne	1ec <__libc_free+0x1ec>  // b.any
 238:	34000204 	cbz	w4, 278 <__libc_free+0x278>
 23c:	0b0000a0 	add	w0, w5, w0
 240:	6b06001f 	cmp	w0, w6
 244:	540001a0 	b.eq	278 <__libc_free+0x278>  // b.none
 248:	39400d00 	ldrb	w0, [x8, #3]
 24c:	0b0400a2 	add	w2, w5, w4
 250:	72001c1f 	tst	w0, #0xff
 254:	54fffe20 	b.eq	218 <__libc_free+0x218>  // b.none
 258:	91007260 	add	x0, x19, #0x1c
 25c:	885ffc03 	ldaxr	w3, [x0]
 260:	6b03009f 	cmp	w4, w3
 264:	54fffde1 	b.ne	220 <__libc_free+0x220>  // b.any
 268:	8803fc02 	stlxr	w3, w2, [x0]
 26c:	35ffff83 	cbnz	w3, 25c <__libc_free+0x25c>
 270:	a8c34ffe 	ldp	x30, x19, [sp], #48
 274:	d65f03c0 	ret
 278:	a90157f4 	stp	x20, x21, [sp, #16]
 27c:	90000014 	adrp	x20, 0 <__malloc_lock>
			27c: R_AARCH64_ADR_PREL_PG_HI21	__malloc_lock
 280:	39400d00 	ldrb	w0, [x8, #3]
 284:	72001c1f 	tst	w0, #0xff
 288:	54000141 	b.ne	2b0 <__libc_free+0x2b0>  // b.any
 28c:	aa1303e0 	mov	x0, x19
 290:	94000000 	bl	0 <__libc_free>
			290: R_AARCH64_CALL26	.text.nontrivial_free
 294:	b9400282 	ldr	w2, [x20]
			294: R_AARCH64_LDST32_ABS_LO12_NC	__malloc_lock
 298:	aa0103f3 	mov	x19, x1
 29c:	aa0003f4 	mov	x20, x0
 2a0:	37f80122 	tbnz	w2, #31, 2c4 <__libc_free+0x2c4>
 2a4:	b5000193 	cbnz	x19, 2d4 <__libc_free+0x2d4>
 2a8:	a94157f4 	ldp	x20, x21, [sp, #16]
 2ac:	17fffff1 	b	270 <__libc_free+0x270>
 2b0:	91000280 	add	x0, x20, #0x0
			2b0: R_AARCH64_ADD_ABS_LO12_NC	__malloc_lock
 2b4:	b9002fe1 	str	w1, [sp, #44]
 2b8:	94000000 	bl	0 <__lock>
			2b8: R_AARCH64_CALL26	__lock
 2bc:	b9402fe1 	ldr	w1, [sp, #44]
 2c0:	17fffff3 	b	28c <__libc_free+0x28c>
 2c4:	90000000 	adrp	x0, 0 <__malloc_lock>
			2c4: R_AARCH64_ADR_PREL_PG_HI21	__malloc_lock
 2c8:	91000000 	add	x0, x0, #0x0
			2c8: R_AARCH64_ADD_ABS_LO12_NC	__malloc_lock
 2cc:	94000000 	bl	0 <__unlock>
			2cc: R_AARCH64_CALL26	__unlock
 2d0:	17fffff5 	b	2a4 <__libc_free+0x2a4>
 2d4:	94000000 	bl	0 <___errno_location>
			2d4: R_AARCH64_CALL26	___errno_location
 2d8:	aa0003f5 	mov	x21, x0
 2dc:	aa1303e1 	mov	x1, x19
 2e0:	aa1403e0 	mov	x0, x20
 2e4:	b94002b3 	ldr	w19, [x21]
 2e8:	94000000 	bl	0 <munmap>
			2e8: R_AARCH64_CALL26	munmap
 2ec:	b90002b3 	str	w19, [x21]
 2f0:	a94157f4 	ldp	x20, x21, [sp, #16]
 2f4:	17ffffdf 	b	270 <__libc_free+0x270>
 2f8:	d4207d00 	brk	#0x3e8
 2fc:	d65f03c0 	ret

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

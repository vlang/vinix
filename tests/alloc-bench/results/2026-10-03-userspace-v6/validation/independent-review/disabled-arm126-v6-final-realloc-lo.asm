
/Users/alex/code/vinix/third_party/useralloc-libc/build/useralloc/v6-prototype/cache/aarch64/8aad8f723adaef17f8d174ed7f056b626093fa67fc8ddb0c76ab0f8be6f11817/objects/obj/src/malloc/mallocng/realloc.lo:     file format elf64-littleaarch64


Disassembly of section .text.__libc_realloc:

0000000000000000 <__libc_realloc>:
   0:	a9bc4ffe 	stp	x30, x19, [sp, #-64]!
   4:	a90157f4 	stp	x20, x21, [sp, #16]
   8:	aa0103f4 	mov	x20, x1
   c:	b4001180 	cbz	x0, 23c <__libc_realloc+0x23c>
  10:	aa0003f3 	mov	x19, x0
  14:	92820020 	mov	x0, #0xffffffffffffeffe    	// #-4098
  18:	a9025ff6 	stp	x22, x23, [sp, #32]
  1c:	f2efffe0 	movk	x0, #0x7fff, lsl #48
  20:	eb00003f 	cmp	x1, x0
  24:	54001368 	b.hi	290 <__libc_realloc+0x290>  // b.pmore
  28:	a90367f8 	stp	x24, x25, [sp, #48]
  2c:	f2400e7f 	tst	x19, #0xf
  30:	540010e1 	b.ne	24c <__libc_realloc+0x24c>  // b.any
  34:	385fc260 	ldurb	w0, [x19, #-4]
  38:	385fd269 	ldurb	w9, [x19, #-3]
  3c:	785fe262 	ldurh	w2, [x19, #-2]
  40:	12001126 	and	w6, w9, #0x1f
  44:	340000c0 	cbz	w0, 5c <__libc_realloc+0x5c>
  48:	35001022 	cbnz	w2, 24c <__libc_realloc+0x24c>
  4c:	b85f8262 	ldur	w2, [x19, #-8]
  50:	529fffe0 	mov	w0, #0xffff                	// #65535
  54:	6b00005f 	cmp	w2, w0
  58:	54000fad 	b.le	24c <__libc_realloc+0x24c>
  5c:	531c6c41 	lsl	w1, w2, #4
  60:	928001e0 	mov	x0, #0xfffffffffffffff0    	// #-16
  64:	cb21c000 	sub	x0, x0, w1, sxtw
  68:	8b000261 	add	x1, x19, x0
  6c:	f8606a78 	ldr	x24, [x19, x0]
  70:	f9400b00 	ldr	x0, [x24, #16]
  74:	eb00003f 	cmp	x1, x0
  78:	54000ea1 	b.ne	24c <__libc_realloc+0x24c>  // b.any
  7c:	f9401305 	ldr	x5, [x24, #32]
  80:	120010a1 	and	w1, w5, #0x1f
  84:	6b0100df 	cmp	w6, w1
  88:	54000e2c 	b.gt	24c <__libc_realloc+0x24c>
  8c:	b9401b01 	ldr	w1, [x24, #24]
  90:	1ac62421 	lsr	w1, w1, w6
  94:	37000dc1 	tbnz	w1, #0, 24c <__libc_realloc+0x24c>
  98:	b9401f01 	ldr	w1, [x24, #28]
  9c:	1ac62421 	lsr	w1, w1, w6
  a0:	37000d61 	tbnz	w1, #0, 24c <__libc_realloc+0x24c>
  a4:	9274cf01 	and	x1, x24, #0xfffffffffffff000
  a8:	90000003 	adrp	x3, 0 <__malloc_context>
			a8: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
  ac:	f9400063 	ldr	x3, [x3]
			ac: R_AARCH64_LDST64_ABS_LO12_NC	__malloc_context
  b0:	f9400021 	ldr	x1, [x1]
  b4:	eb03003f 	cmp	x1, x3
  b8:	54000ca1 	b.ne	24c <__libc_realloc+0x24c>  // b.any
  bc:	53062ca7 	ubfx	w7, w5, #6, #6
  c0:	7100bcff 	cmp	w7, #0x2f
  c4:	54000c6c 	b.gt	250 <__libc_realloc+0x250>
  c8:	90000003 	adrp	x3, 0 <__malloc_size_classes>
			c8: R_AARCH64_ADR_PREL_PG_HI21	__malloc_size_classes
  cc:	91000061 	add	x1, x3, #0x0
			cc: R_AARCH64_ADD_ABS_LO12_NC	__malloc_size_classes
  d0:	7867d821 	ldrh	w1, [x1, w7, sxtw #1]
  d4:	1b017cc4 	mul	w4, w6, w1
  d8:	6b04005f 	cmp	w2, w4
  dc:	54000b8b 	b.lt	24c <__libc_realloc+0x24c>  // b.tstop
  e0:	0b040021 	add	w1, w1, w4
  e4:	6b01005f 	cmp	w2, w1
  e8:	54000b2a 	b.ge	24c <__libc_realloc+0x24c>  // b.tcont
  ec:	d34cfca1 	lsr	x1, x5, #12
  f0:	b40000a1 	cbz	x1, 104 <__libc_realloc+0x104>
  f4:	d378dc24 	lsl	x4, x1, #8
  f8:	d1000484 	sub	x4, x4, #0x1
  fc:	eb22c09f 	cmp	x4, w2, sxtw
 100:	54000a63 	b.cc	24c <__libc_realloc+0x24c>  // b.lo, b.ul, b.last
 104:	f13ffcbf 	cmp	x5, #0xfff
 108:	924010a2 	and	x2, x5, #0x1f
 10c:	fa408840 	ccmp	x2, #0x0, #0x0, hi	// hi = pmore
 110:	d374cc24 	lsl	x4, x1, #12
 114:	54000ba0 	b.eq	288 <__libc_realloc+0x288>  // b.none
 118:	91000063 	add	x3, x3, #0x0
			118: R_AARCH64_ADD_ABS_LO12_NC	__malloc_size_classes
 11c:	7867d864 	ldrh	w4, [x3, w7, sxtw #1]
 120:	d37c3c84 	ubfiz	x4, x4, #4, #16
 124:	9100400b 	add	x11, x0, #0x10
 128:	2a0603e2 	mov	w2, w6
 12c:	d100108a 	sub	x10, x4, #0x4
 130:	53057d23 	lsr	w3, w9, #5
 134:	9b042c42 	madd	x2, x2, x4, x11
 138:	8b0a0048 	add	x8, x2, x10
 13c:	71027d3f 	cmp	w9, #0x9f
 140:	54000109 	b.ls	160 <__libc_realloc+0x160>  // b.plast
 144:	7100147f 	cmp	w3, #0x5
 148:	54000821 	b.ne	24c <__libc_realloc+0x24c>  // b.any
 14c:	b85fc103 	ldur	w3, [x8, #-4]
 150:	f100107f 	cmp	x3, #0x4
 154:	540007c9 	b.ls	24c <__libc_realloc+0x24c>  // b.plast
 158:	385fb104 	ldurb	w4, [x8, #-5]
 15c:	35000784 	cbnz	w4, 24c <__libc_realloc+0x24c>
 160:	cb130104 	sub	x4, x8, x19
 164:	eb03009f 	cmp	x4, x3
 168:	54000723 	b.cc	24c <__libc_realloc+0x24c>  // b.lo, b.ul, b.last
 16c:	cb030116 	sub	x22, x8, x3
 170:	394002c3 	ldrb	w3, [x22]
 174:	350006c3 	cbnz	w3, 24c <__libc_realloc+0x24c>
 178:	386a6843 	ldrb	w3, [x2, x10]
 17c:	35000683 	cbnz	w3, 24c <__libc_realloc+0x24c>
 180:	d29ffd63 	mov	x3, #0xffeb                	// #65515
 184:	f2a00023 	movk	x3, #0x1, lsl #16
 188:	eb03009f 	cmp	x4, x3
 18c:	9a839089 	csel	x9, x4, x3, ls	// ls = plast
 190:	eb09029f 	cmp	x20, x9
 194:	54000aa8 	b.hi	2e8 <__libc_realloc+0x2e8>  // b.pmore
 198:	91000e80 	add	x0, x20, #0x3
 19c:	d344fc01 	lsr	x1, x0, #4
 1a0:	11000422 	add	w2, w1, #0x1
 1a4:	f1027c1f 	cmp	x0, #0x9f
 1a8:	54000249 	b.ls	1f0 <__libc_realloc+0x1f0>  // b.plast
 1ac:	91000421 	add	x1, x1, #0x1
 1b0:	528003c0 	mov	w0, #0x1e                  	// #30
 1b4:	5ac01022 	clz	w2, w1
 1b8:	90000003 	adrp	x3, 0 <__malloc_size_classes>
			1b8: R_AARCH64_ADR_PREL_PG_HI21	__malloc_size_classes
 1bc:	4b020000 	sub	w0, w0, w2
 1c0:	91000065 	add	x5, x3, #0x0
			1c0: R_AARCH64_ADD_ABS_LO12_NC	__malloc_size_classes
 1c4:	531e7400 	lsl	w0, w0, #2
 1c8:	11000402 	add	w2, w0, #0x1
 1cc:	7862d8a5 	ldrh	w5, [x5, w2, sxtw #1]
 1d0:	eb05003f 	cmp	x1, x5
 1d4:	54000069 	b.ls	1e0 <__libc_realloc+0x1e0>  // b.plast
 1d8:	11000c02 	add	w2, w0, #0x3
 1dc:	11000800 	add	w0, w0, #0x2
 1e0:	91000063 	add	x3, x3, #0x0
			1e0: R_AARCH64_ADD_ABS_LO12_NC	__malloc_size_classes
 1e4:	7860d860 	ldrh	w0, [x3, w0, sxtw #1]
 1e8:	eb00003f 	cmp	x1, x0
 1ec:	1a829442 	cinc	w2, w2, hi	// hi = pmore
 1f0:	6b0200ff 	cmp	w7, w2
 1f4:	5400058d 	b.le	2a4 <__libc_realloc+0x2a4>
 1f8:	aa1403e0 	mov	x0, x20
 1fc:	94000000 	bl	0 <__libc_malloc_impl>
			1fc: R_AARCH64_CALL26	__libc_malloc_impl
 200:	aa0003f7 	mov	x23, x0
 204:	b4000d40 	cbz	x0, 3ac <__libc_realloc+0x3ac>
 208:	cb1302c2 	sub	x2, x22, x19
 20c:	aa1303e1 	mov	x1, x19
 210:	eb14005f 	cmp	x2, x20
 214:	9a949042 	csel	x2, x2, x20, ls	// ls = plast
 218:	94000000 	bl	0 <memcpy>
			218: R_AARCH64_CALL26	memcpy
 21c:	aa1303e0 	mov	x0, x19
 220:	94000000 	bl	0 <__libc_free>
			220: R_AARCH64_CALL26	__libc_free
 224:	a94367f8 	ldp	x24, x25, [sp, #48]
 228:	aa1703e0 	mov	x0, x23
 22c:	a9425ff6 	ldp	x22, x23, [sp, #32]
 230:	a94157f4 	ldp	x20, x21, [sp, #16]
 234:	a8c44ffe 	ldp	x30, x19, [sp], #64
 238:	d65f03c0 	ret
 23c:	a94157f4 	ldp	x20, x21, [sp, #16]
 240:	aa0103e0 	mov	x0, x1
 244:	a8c44ffe 	ldp	x30, x19, [sp], #64
 248:	14000000 	b	0 <__libc_malloc_impl>
			248: R_AARCH64_JUMP26	__libc_malloc_impl
 24c:	d4207d00 	brk	#0x3e8
 250:	7100fcff 	cmp	w7, #0x3f
 254:	54ffffc1 	b.ne	24c <__libc_realloc+0x24c>  // b.any
 258:	f24010bf 	tst	x5, #0x1f
 25c:	54ffff81 	b.ne	24c <__libc_realloc+0x24c>  // b.any
 260:	f13ffcbf 	cmp	x5, #0xfff
 264:	54ffff49 	b.ls	24c <__libc_realloc+0x24c>  // b.plast
 268:	d34cfca1 	lsr	x1, x5, #12
 26c:	d2800004 	mov	x4, #0x0                   	// #0
 270:	b40000c1 	cbz	x1, 288 <__libc_realloc+0x288>
 274:	d378dc23 	lsl	x3, x1, #8
 278:	d374cc24 	lsl	x4, x1, #12
 27c:	d1000463 	sub	x3, x3, #0x1
 280:	eb22c07f 	cmp	x3, w2, sxtw
 284:	54fffe43 	b.cc	24c <__libc_realloc+0x24c>  // b.lo, b.ul, b.last
 288:	d1004084 	sub	x4, x4, #0x10
 28c:	17ffffa6 	b	124 <__libc_realloc+0x124>
 290:	94000000 	bl	0 <___errno_location>
			290: R_AARCH64_CALL26	___errno_location
 294:	d2800017 	mov	x23, #0x0                   	// #0
 298:	52800181 	mov	w1, #0xc                   	// #12
 29c:	b9000001 	str	w1, [x0]
 2a0:	17ffffe2 	b	228 <__libc_realloc+0x228>
 2a4:	6b140084 	subs	w4, w4, w20
 2a8:	540000e0 	b.eq	2c4 <__libc_realloc+0x2c4>  // b.none
 2ac:	4b0403e0 	neg	w0, w4
 2b0:	3820c91f 	strb	wzr, [x8, w0, sxtw]
 2b4:	7100109f 	cmp	w4, #0x4
 2b8:	540000ec 	b.gt	2d4 <__libc_realloc+0x2d4>
 2bc:	0b0414c4 	add	w4, w6, w4, lsl #5
 2c0:	12001c86 	and	w6, w4, #0xff
 2c4:	381fd266 	sturb	w6, [x19, #-3]
 2c8:	aa1303f7 	mov	x23, x19
 2cc:	a94367f8 	ldp	x24, x25, [sp, #48]
 2d0:	17ffffd6 	b	228 <__libc_realloc+0x228>
 2d4:	510180c6 	sub	w6, w6, #0x60
 2d8:	381fb11f 	sturb	wzr, [x8, #-5]
 2dc:	12001cc6 	and	w6, w6, #0xff
 2e0:	b81fc104 	stur	w4, [x8, #-4]
 2e4:	17fffff8 	b	2c4 <__libc_realloc+0x2c4>
 2e8:	7100bcff 	cmp	w7, #0x2f
 2ec:	fa438280 	ccmp	x20, x3, #0x0, hi	// hi = pmore
 2f0:	54fff849 	b.ls	1f8 <__libc_realloc+0x1f8>  // b.plast
 2f4:	927a14a5 	and	x5, x5, #0xfc0
 2f8:	f13f00bf 	cmp	x5, #0xfc0
 2fc:	54fffa81 	b.ne	24c <__libc_realloc+0x24c>  // b.any
 300:	cb020275 	sub	x21, x19, x2
 304:	d2820262 	mov	x2, #0x1013                	// #4115
 308:	8b020297 	add	x23, x20, x2
 30c:	d374cc21 	lsl	x1, x1, #12
 310:	8b1502f7 	add	x23, x23, x21
 314:	9274cef9 	and	x25, x23, #0xfffffffffffff000
 318:	eb19003f 	cmp	x1, x25
 31c:	54000301 	b.ne	37c <__libc_realloc+0x37c>  // b.any
 320:	f9401303 	ldr	x3, [x24, #32]
 324:	d1005339 	sub	x25, x25, #0x14
 328:	d34cfee1 	lsr	x1, x23, #12
 32c:	8b150177 	add	x23, x11, x21
 330:	f9000b00 	str	x0, [x24, #16]
 334:	cb150322 	sub	x2, x25, x21
 338:	b374cc23 	bfi	x3, x1, #12, #52
 33c:	f9001303 	str	x3, [x24, #32]
 340:	3839697f 	strb	wzr, [x11, x25]
 344:	6b140042 	subs	w2, w2, w20
 348:	8b19016b 	add	x11, x11, x25
 34c:	385fd2e0 	ldurb	w0, [x23, #-3]
 350:	12001000 	and	w0, w0, #0x1f
 354:	540000e0 	b.eq	370 <__libc_realloc+0x370>  // b.none
 358:	4b0203e1 	neg	w1, w2
 35c:	3821c97f 	strb	wzr, [x11, w1, sxtw]
 360:	7100105f 	cmp	w2, #0x4
 364:	540001ac 	b.gt	398 <__libc_realloc+0x398>
 368:	0b021400 	add	w0, w0, w2, lsl #5
 36c:	12001c00 	and	w0, w0, #0xff
 370:	381fd2e0 	sturb	w0, [x23, #-3]
 374:	a94367f8 	ldp	x24, x25, [sp, #48]
 378:	17ffffac 	b	228 <__libc_realloc+0x228>
 37c:	aa1903e2 	mov	x2, x25
 380:	52800023 	mov	w3, #0x1                   	// #1
 384:	94000000 	bl	0 <__mremap>
			384: R_AARCH64_CALL26	__mremap
 388:	b100041f 	cmn	x0, #0x1
 38c:	54fff360 	b.eq	1f8 <__libc_realloc+0x1f8>  // b.none
 390:	9100400b 	add	x11, x0, #0x10
 394:	17ffffe3 	b	320 <__libc_realloc+0x320>
 398:	51018000 	sub	w0, w0, #0x60
 39c:	381fb17f 	sturb	wzr, [x11, #-5]
 3a0:	12001c00 	and	w0, w0, #0xff
 3a4:	b81fc162 	stur	w2, [x11, #-4]
 3a8:	17fffff2 	b	370 <__libc_realloc+0x370>
 3ac:	a94367f8 	ldp	x24, x25, [sp, #48]
 3b0:	17ffff9e 	b	228 <__libc_realloc+0x228>

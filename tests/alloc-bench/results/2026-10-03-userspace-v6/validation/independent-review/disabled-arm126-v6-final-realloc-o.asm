
/Users/alex/code/vinix/third_party/useralloc-libc/build/useralloc/v6-prototype/cache/aarch64/8aad8f723adaef17f8d174ed7f056b626093fa67fc8ddb0c76ab0f8be6f11817/objects/obj/src/malloc/mallocng/realloc.o:     file format elf64-littleaarch64


Disassembly of section .text.__libc_realloc:

0000000000000000 <__libc_realloc>:
   0:	a9bc4ffe 	stp	x30, x19, [sp, #-64]!
   4:	a90157f4 	stp	x20, x21, [sp, #16]
   8:	aa0103f4 	mov	x20, x1
   c:	b4001140 	cbz	x0, 234 <__libc_realloc+0x234>
  10:	aa0003f3 	mov	x19, x0
  14:	92820020 	mov	x0, #0xffffffffffffeffe    	// #-4098
  18:	a9025ff6 	stp	x22, x23, [sp, #32]
  1c:	f2efffe0 	movk	x0, #0x7fff, lsl #48
  20:	eb00003f 	cmp	x1, x0
  24:	54001328 	b.hi	288 <__libc_realloc+0x288>  // b.pmore
  28:	a90367f8 	stp	x24, x25, [sp, #48]
  2c:	f2400e7f 	tst	x19, #0xf
  30:	540010a1 	b.ne	244 <__libc_realloc+0x244>  // b.any
  34:	385fc260 	ldurb	w0, [x19, #-4]
  38:	385fd269 	ldurb	w9, [x19, #-3]
  3c:	785fe262 	ldurh	w2, [x19, #-2]
  40:	12001126 	and	w6, w9, #0x1f
  44:	340000c0 	cbz	w0, 5c <__libc_realloc+0x5c>
  48:	35000fe2 	cbnz	w2, 244 <__libc_realloc+0x244>
  4c:	b85f8262 	ldur	w2, [x19, #-8]
  50:	529fffe0 	mov	w0, #0xffff                	// #65535
  54:	6b00005f 	cmp	w2, w0
  58:	54000f6d 	b.le	244 <__libc_realloc+0x244>
  5c:	531c6c41 	lsl	w1, w2, #4
  60:	928001e0 	mov	x0, #0xfffffffffffffff0    	// #-16
  64:	cb21c000 	sub	x0, x0, w1, sxtw
  68:	8b000261 	add	x1, x19, x0
  6c:	f8606a78 	ldr	x24, [x19, x0]
  70:	f9400b00 	ldr	x0, [x24, #16]
  74:	eb00003f 	cmp	x1, x0
  78:	54000e61 	b.ne	244 <__libc_realloc+0x244>  // b.any
  7c:	f9401305 	ldr	x5, [x24, #32]
  80:	120010a1 	and	w1, w5, #0x1f
  84:	6b0100df 	cmp	w6, w1
  88:	54000dec 	b.gt	244 <__libc_realloc+0x244>
  8c:	b9401b01 	ldr	w1, [x24, #24]
  90:	1ac62421 	lsr	w1, w1, w6
  94:	37000d81 	tbnz	w1, #0, 244 <__libc_realloc+0x244>
  98:	b9401f01 	ldr	w1, [x24, #28]
  9c:	1ac62421 	lsr	w1, w1, w6
  a0:	37000d21 	tbnz	w1, #0, 244 <__libc_realloc+0x244>
  a4:	9274cf01 	and	x1, x24, #0xfffffffffffff000
  a8:	90000003 	adrp	x3, 0 <__malloc_context>
			a8: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
  ac:	f9400063 	ldr	x3, [x3]
			ac: R_AARCH64_LDST64_ABS_LO12_NC	__malloc_context
  b0:	f9400021 	ldr	x1, [x1]
  b4:	eb03003f 	cmp	x1, x3
  b8:	54000c61 	b.ne	244 <__libc_realloc+0x244>  // b.any
  bc:	53062ca7 	ubfx	w7, w5, #6, #6
  c0:	7100bcff 	cmp	w7, #0x2f
  c4:	54000c2c 	b.gt	248 <__libc_realloc+0x248>
  c8:	90000003 	adrp	x3, 0 <__malloc_size_classes>
			c8: R_AARCH64_ADR_PREL_PG_HI21	__malloc_size_classes
  cc:	91000063 	add	x3, x3, #0x0
			cc: R_AARCH64_ADD_ABS_LO12_NC	__malloc_size_classes
  d0:	7867d861 	ldrh	w1, [x3, w7, sxtw #1]
  d4:	1b017cc4 	mul	w4, w6, w1
  d8:	6b04005f 	cmp	w2, w4
  dc:	54000b4b 	b.lt	244 <__libc_realloc+0x244>  // b.tstop
  e0:	0b040021 	add	w1, w1, w4
  e4:	6b01005f 	cmp	w2, w1
  e8:	54000aea 	b.ge	244 <__libc_realloc+0x244>  // b.tcont
  ec:	d34cfca1 	lsr	x1, x5, #12
  f0:	b40000a1 	cbz	x1, 104 <__libc_realloc+0x104>
  f4:	d378dc24 	lsl	x4, x1, #8
  f8:	d1000484 	sub	x4, x4, #0x1
  fc:	eb22c09f 	cmp	x4, w2, sxtw
 100:	54000a23 	b.cc	244 <__libc_realloc+0x244>  // b.lo, b.ul, b.last
 104:	f13ffcbf 	cmp	x5, #0xfff
 108:	924010a2 	and	x2, x5, #0x1f
 10c:	fa408840 	ccmp	x2, #0x0, #0x0, hi	// hi = pmore
 110:	d374cc24 	lsl	x4, x1, #12
 114:	54000b60 	b.eq	280 <__libc_realloc+0x280>  // b.none
 118:	7867d864 	ldrh	w4, [x3, w7, sxtw #1]
 11c:	d37c3c84 	ubfiz	x4, x4, #4, #16
 120:	9100400b 	add	x11, x0, #0x10
 124:	2a0603e2 	mov	w2, w6
 128:	d100108a 	sub	x10, x4, #0x4
 12c:	53057d23 	lsr	w3, w9, #5
 130:	9b042c42 	madd	x2, x2, x4, x11
 134:	8b0a0048 	add	x8, x2, x10
 138:	71027d3f 	cmp	w9, #0x9f
 13c:	54000109 	b.ls	15c <__libc_realloc+0x15c>  // b.plast
 140:	7100147f 	cmp	w3, #0x5
 144:	54000801 	b.ne	244 <__libc_realloc+0x244>  // b.any
 148:	b85fc103 	ldur	w3, [x8, #-4]
 14c:	f100107f 	cmp	x3, #0x4
 150:	540007a9 	b.ls	244 <__libc_realloc+0x244>  // b.plast
 154:	385fb104 	ldurb	w4, [x8, #-5]
 158:	35000764 	cbnz	w4, 244 <__libc_realloc+0x244>
 15c:	cb130104 	sub	x4, x8, x19
 160:	eb03009f 	cmp	x4, x3
 164:	54000703 	b.cc	244 <__libc_realloc+0x244>  // b.lo, b.ul, b.last
 168:	cb030116 	sub	x22, x8, x3
 16c:	394002c3 	ldrb	w3, [x22]
 170:	350006a3 	cbnz	w3, 244 <__libc_realloc+0x244>
 174:	386a6843 	ldrb	w3, [x2, x10]
 178:	35000663 	cbnz	w3, 244 <__libc_realloc+0x244>
 17c:	d29ffd63 	mov	x3, #0xffeb                	// #65515
 180:	f2a00023 	movk	x3, #0x1, lsl #16
 184:	eb03009f 	cmp	x4, x3
 188:	9a839089 	csel	x9, x4, x3, ls	// ls = plast
 18c:	eb09029f 	cmp	x20, x9
 190:	54000a88 	b.hi	2e0 <__libc_realloc+0x2e0>  // b.pmore
 194:	91000e80 	add	x0, x20, #0x3
 198:	d344fc01 	lsr	x1, x0, #4
 19c:	11000422 	add	w2, w1, #0x1
 1a0:	f1027c1f 	cmp	x0, #0x9f
 1a4:	54000229 	b.ls	1e8 <__libc_realloc+0x1e8>  // b.plast
 1a8:	91000421 	add	x1, x1, #0x1
 1ac:	528003c0 	mov	w0, #0x1e                  	// #30
 1b0:	5ac01022 	clz	w2, w1
 1b4:	90000003 	adrp	x3, 0 <__malloc_size_classes>
			1b4: R_AARCH64_ADR_PREL_PG_HI21	__malloc_size_classes
 1b8:	4b020000 	sub	w0, w0, w2
 1bc:	91000063 	add	x3, x3, #0x0
			1bc: R_AARCH64_ADD_ABS_LO12_NC	__malloc_size_classes
 1c0:	531e7400 	lsl	w0, w0, #2
 1c4:	11000402 	add	w2, w0, #0x1
 1c8:	7862d865 	ldrh	w5, [x3, w2, sxtw #1]
 1cc:	eb05003f 	cmp	x1, x5
 1d0:	54000069 	b.ls	1dc <__libc_realloc+0x1dc>  // b.plast
 1d4:	11000c02 	add	w2, w0, #0x3
 1d8:	11000800 	add	w0, w0, #0x2
 1dc:	7860d860 	ldrh	w0, [x3, w0, sxtw #1]
 1e0:	eb00003f 	cmp	x1, x0
 1e4:	1a829442 	cinc	w2, w2, hi	// hi = pmore
 1e8:	6b0200ff 	cmp	w7, w2
 1ec:	5400058d 	b.le	29c <__libc_realloc+0x29c>
 1f0:	aa1403e0 	mov	x0, x20
 1f4:	94000000 	bl	0 <__libc_malloc_impl>
			1f4: R_AARCH64_CALL26	__libc_malloc_impl
 1f8:	aa0003f7 	mov	x23, x0
 1fc:	b4000d40 	cbz	x0, 3a4 <__libc_realloc+0x3a4>
 200:	cb1302c2 	sub	x2, x22, x19
 204:	aa1303e1 	mov	x1, x19
 208:	eb14005f 	cmp	x2, x20
 20c:	9a949042 	csel	x2, x2, x20, ls	// ls = plast
 210:	94000000 	bl	0 <memcpy>
			210: R_AARCH64_CALL26	memcpy
 214:	aa1303e0 	mov	x0, x19
 218:	94000000 	bl	0 <__libc_free>
			218: R_AARCH64_CALL26	__libc_free
 21c:	a94367f8 	ldp	x24, x25, [sp, #48]
 220:	aa1703e0 	mov	x0, x23
 224:	a9425ff6 	ldp	x22, x23, [sp, #32]
 228:	a94157f4 	ldp	x20, x21, [sp, #16]
 22c:	a8c44ffe 	ldp	x30, x19, [sp], #64
 230:	d65f03c0 	ret
 234:	a94157f4 	ldp	x20, x21, [sp, #16]
 238:	aa0103e0 	mov	x0, x1
 23c:	a8c44ffe 	ldp	x30, x19, [sp], #64
 240:	14000000 	b	0 <__libc_malloc_impl>
			240: R_AARCH64_JUMP26	__libc_malloc_impl
 244:	d4207d00 	brk	#0x3e8
 248:	7100fcff 	cmp	w7, #0x3f
 24c:	54ffffc1 	b.ne	244 <__libc_realloc+0x244>  // b.any
 250:	f24010bf 	tst	x5, #0x1f
 254:	54ffff81 	b.ne	244 <__libc_realloc+0x244>  // b.any
 258:	f13ffcbf 	cmp	x5, #0xfff
 25c:	54ffff49 	b.ls	244 <__libc_realloc+0x244>  // b.plast
 260:	d34cfca1 	lsr	x1, x5, #12
 264:	d2800004 	mov	x4, #0x0                   	// #0
 268:	b40000c1 	cbz	x1, 280 <__libc_realloc+0x280>
 26c:	d378dc23 	lsl	x3, x1, #8
 270:	d374cc24 	lsl	x4, x1, #12
 274:	d1000463 	sub	x3, x3, #0x1
 278:	eb22c07f 	cmp	x3, w2, sxtw
 27c:	54fffe43 	b.cc	244 <__libc_realloc+0x244>  // b.lo, b.ul, b.last
 280:	d1004084 	sub	x4, x4, #0x10
 284:	17ffffa7 	b	120 <__libc_realloc+0x120>
 288:	94000000 	bl	0 <___errno_location>
			288: R_AARCH64_CALL26	___errno_location
 28c:	d2800017 	mov	x23, #0x0                   	// #0
 290:	52800181 	mov	w1, #0xc                   	// #12
 294:	b9000001 	str	w1, [x0]
 298:	17ffffe2 	b	220 <__libc_realloc+0x220>
 29c:	6b140084 	subs	w4, w4, w20
 2a0:	540000e0 	b.eq	2bc <__libc_realloc+0x2bc>  // b.none
 2a4:	4b0403e0 	neg	w0, w4
 2a8:	3820c91f 	strb	wzr, [x8, w0, sxtw]
 2ac:	7100109f 	cmp	w4, #0x4
 2b0:	540000ec 	b.gt	2cc <__libc_realloc+0x2cc>
 2b4:	0b0414c4 	add	w4, w6, w4, lsl #5
 2b8:	12001c86 	and	w6, w4, #0xff
 2bc:	381fd266 	sturb	w6, [x19, #-3]
 2c0:	aa1303f7 	mov	x23, x19
 2c4:	a94367f8 	ldp	x24, x25, [sp, #48]
 2c8:	17ffffd6 	b	220 <__libc_realloc+0x220>
 2cc:	510180c6 	sub	w6, w6, #0x60
 2d0:	381fb11f 	sturb	wzr, [x8, #-5]
 2d4:	12001cc6 	and	w6, w6, #0xff
 2d8:	b81fc104 	stur	w4, [x8, #-4]
 2dc:	17fffff8 	b	2bc <__libc_realloc+0x2bc>
 2e0:	7100bcff 	cmp	w7, #0x2f
 2e4:	fa438280 	ccmp	x20, x3, #0x0, hi	// hi = pmore
 2e8:	54fff849 	b.ls	1f0 <__libc_realloc+0x1f0>  // b.plast
 2ec:	927a14a5 	and	x5, x5, #0xfc0
 2f0:	f13f00bf 	cmp	x5, #0xfc0
 2f4:	54fffa81 	b.ne	244 <__libc_realloc+0x244>  // b.any
 2f8:	cb020275 	sub	x21, x19, x2
 2fc:	d2820262 	mov	x2, #0x1013                	// #4115
 300:	8b020297 	add	x23, x20, x2
 304:	d374cc21 	lsl	x1, x1, #12
 308:	8b1502f7 	add	x23, x23, x21
 30c:	9274cef9 	and	x25, x23, #0xfffffffffffff000
 310:	eb19003f 	cmp	x1, x25
 314:	54000301 	b.ne	374 <__libc_realloc+0x374>  // b.any
 318:	f9401303 	ldr	x3, [x24, #32]
 31c:	d1005339 	sub	x25, x25, #0x14
 320:	d34cfee1 	lsr	x1, x23, #12
 324:	8b150177 	add	x23, x11, x21
 328:	f9000b00 	str	x0, [x24, #16]
 32c:	cb150322 	sub	x2, x25, x21
 330:	b374cc23 	bfi	x3, x1, #12, #52
 334:	f9001303 	str	x3, [x24, #32]
 338:	3839697f 	strb	wzr, [x11, x25]
 33c:	6b140042 	subs	w2, w2, w20
 340:	8b19016b 	add	x11, x11, x25
 344:	385fd2e0 	ldurb	w0, [x23, #-3]
 348:	12001000 	and	w0, w0, #0x1f
 34c:	540000e0 	b.eq	368 <__libc_realloc+0x368>  // b.none
 350:	4b0203e1 	neg	w1, w2
 354:	3821c97f 	strb	wzr, [x11, w1, sxtw]
 358:	7100105f 	cmp	w2, #0x4
 35c:	540001ac 	b.gt	390 <__libc_realloc+0x390>
 360:	0b021400 	add	w0, w0, w2, lsl #5
 364:	12001c00 	and	w0, w0, #0xff
 368:	381fd2e0 	sturb	w0, [x23, #-3]
 36c:	a94367f8 	ldp	x24, x25, [sp, #48]
 370:	17ffffac 	b	220 <__libc_realloc+0x220>
 374:	aa1903e2 	mov	x2, x25
 378:	52800023 	mov	w3, #0x1                   	// #1
 37c:	94000000 	bl	0 <__mremap>
			37c: R_AARCH64_CALL26	__mremap
 380:	b100041f 	cmn	x0, #0x1
 384:	54fff360 	b.eq	1f0 <__libc_realloc+0x1f0>  // b.none
 388:	9100400b 	add	x11, x0, #0x10
 38c:	17ffffe3 	b	318 <__libc_realloc+0x318>
 390:	51018000 	sub	w0, w0, #0x60
 394:	381fb17f 	sturb	wzr, [x11, #-5]
 398:	12001c00 	and	w0, w0, #0xff
 39c:	b81fc162 	stur	w2, [x11, #-4]
 3a0:	17fffff2 	b	368 <__libc_realloc+0x368>
 3a4:	a94367f8 	ldp	x24, x25, [sp, #48]
 3a8:	17ffff9e 	b	220 <__libc_realloc+0x220>

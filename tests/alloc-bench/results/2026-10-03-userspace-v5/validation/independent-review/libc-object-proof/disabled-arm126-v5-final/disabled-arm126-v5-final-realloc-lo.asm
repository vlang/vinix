
/Users/alex/code/vinix/third_party/useralloc-libc/build/musl/aarch64/45e591e09bed5a7f37f2a259e8135213cdbcff073604a7239878a1169ec7dae3/objects/obj/src/malloc/mallocng/realloc.lo:     file format elf64-littleaarch64


Disassembly of section .text.__libc_realloc:

0000000000000000 <__libc_realloc>:
   0:	a9bc4ffe 	stp	x30, x19, [sp, #-64]!
   4:	a90157f4 	stp	x20, x21, [sp, #16]
   8:	aa0103f4 	mov	x20, x1
   c:	b40011a0 	cbz	x0, 240 <__libc_realloc+0x240>
  10:	aa0003f3 	mov	x19, x0
  14:	92820020 	mov	x0, #0xffffffffffffeffe    	// #-4098
  18:	a9025ff6 	stp	x22, x23, [sp, #32]
  1c:	f2efffe0 	movk	x0, #0x7fff, lsl #48
  20:	eb00003f 	cmp	x1, x0
  24:	540011e8 	b.hi	260 <__libc_realloc+0x260>  // b.pmore
  28:	a90367f8 	stp	x24, x25, [sp, #48]
  2c:	f2400e7f 	tst	x19, #0xf
  30:	54001161 	b.ne	25c <__libc_realloc+0x25c>  // b.any
  34:	385fc260 	ldurb	w0, [x19, #-4]
  38:	385fd268 	ldurb	w8, [x19, #-3]
  3c:	785fe262 	ldurh	w2, [x19, #-2]
  40:	12001105 	and	w5, w8, #0x1f
  44:	340000c0 	cbz	w0, 5c <__libc_realloc+0x5c>
  48:	350010a2 	cbnz	w2, 25c <__libc_realloc+0x25c>
  4c:	b85f8262 	ldur	w2, [x19, #-8]
  50:	529fffe0 	mov	w0, #0xffff                	// #65535
  54:	6b00005f 	cmp	w2, w0
  58:	5400102d 	b.le	25c <__libc_realloc+0x25c>
  5c:	531c6c41 	lsl	w1, w2, #4
  60:	928001e0 	mov	x0, #0xfffffffffffffff0    	// #-16
  64:	cb21c000 	sub	x0, x0, w1, sxtw
  68:	8b000261 	add	x1, x19, x0
  6c:	f8606a78 	ldr	x24, [x19, x0]
  70:	f9400b00 	ldr	x0, [x24, #16]
  74:	eb00003f 	cmp	x1, x0
  78:	54000f21 	b.ne	25c <__libc_realloc+0x25c>  // b.any
  7c:	f9401301 	ldr	x1, [x24, #32]
  80:	12001023 	and	w3, w1, #0x1f
  84:	6b0300bf 	cmp	w5, w3
  88:	54000eac 	b.gt	25c <__libc_realloc+0x25c>
  8c:	b9401b03 	ldr	w3, [x24, #24]
  90:	1ac52463 	lsr	w3, w3, w5
  94:	37000e43 	tbnz	w3, #0, 25c <__libc_realloc+0x25c>
  98:	b9401f03 	ldr	w3, [x24, #28]
  9c:	1ac52463 	lsr	w3, w3, w5
  a0:	37000de3 	tbnz	w3, #0, 25c <__libc_realloc+0x25c>
  a4:	9274cf03 	and	x3, x24, #0xfffffffffffff000
  a8:	90000004 	adrp	x4, 0 <__malloc_context>
			a8: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
  ac:	f9400084 	ldr	x4, [x4]
			ac: R_AARCH64_LDST64_ABS_LO12_NC	__malloc_context
  b0:	f9400063 	ldr	x3, [x3]
  b4:	eb04007f 	cmp	x3, x4
  b8:	54000d21 	b.ne	25c <__libc_realloc+0x25c>  // b.any
  bc:	53062c26 	ubfx	w6, w1, #6, #6
  c0:	7100bcdf 	cmp	w6, #0x2f
  c4:	54000c68 	b.hi	250 <__libc_realloc+0x250>  // b.pmore
  c8:	90000003 	adrp	x3, 0 <__malloc_size_classes>
			c8: R_AARCH64_ADR_PREL_PG_HI21	__malloc_size_classes
  cc:	91000063 	add	x3, x3, #0x0
			cc: R_AARCH64_ADD_ABS_LO12_NC	__malloc_size_classes
  d0:	7866d863 	ldrh	w3, [x3, w6, sxtw #1]
  d4:	1b037ca4 	mul	w4, w5, w3
  d8:	6b04005f 	cmp	w2, w4
  dc:	54000c0b 	b.lt	25c <__libc_realloc+0x25c>  // b.tstop
  e0:	0b040063 	add	w3, w3, w4
  e4:	6b03005f 	cmp	w2, w3
  e8:	54000baa 	b.ge	25c <__libc_realloc+0x25c>  // b.tcont
  ec:	f13ffc3f 	cmp	x1, #0xfff
  f0:	54000129 	b.ls	114 <__libc_realloc+0x114>  // b.plast
  f4:	9274cc23 	and	x3, x1, #0xfffffffffffff000
  f8:	d344fc64 	lsr	x4, x3, #4
  fc:	d1000484 	sub	x4, x4, #0x1
 100:	eb22c09f 	cmp	x4, w2, sxtw
 104:	54000ac3 	b.cc	25c <__libc_realloc+0x25c>  // b.lo, b.ul, b.last
 108:	d1004063 	sub	x3, x3, #0x10
 10c:	f240103f 	tst	x1, #0x1f
 110:	540000a0 	b.eq	124 <__libc_realloc+0x124>  // b.none
 114:	90000002 	adrp	x2, 0 <__malloc_size_classes>
			114: R_AARCH64_ADR_PREL_PG_HI21	__malloc_size_classes
 118:	91000042 	add	x2, x2, #0x0
			118: R_AARCH64_ADD_ABS_LO12_NC	__malloc_size_classes
 11c:	7866d843 	ldrh	w3, [x2, w6, sxtw #1]
 120:	d37c3c63 	ubfiz	x3, x3, #4, #16
 124:	9100400a 	add	x10, x0, #0x10
 128:	2a0503e2 	mov	w2, w5
 12c:	d1001069 	sub	x9, x3, #0x4
 130:	53057d04 	lsr	w4, w8, #5
 134:	9b032842 	madd	x2, x2, x3, x10
 138:	2a0403e3 	mov	w3, w4
 13c:	8b090047 	add	x7, x2, x9
 140:	71027d1f 	cmp	w8, #0x9f
 144:	54000109 	b.ls	164 <__libc_realloc+0x164>  // b.plast
 148:	7100149f 	cmp	w4, #0x5
 14c:	54000881 	b.ne	25c <__libc_realloc+0x25c>  // b.any
 150:	b85fc0e3 	ldur	w3, [x7, #-4]
 154:	f100107f 	cmp	x3, #0x4
 158:	54000829 	b.ls	25c <__libc_realloc+0x25c>  // b.plast
 15c:	385fb0e4 	ldurb	w4, [x7, #-5]
 160:	350007e4 	cbnz	w4, 25c <__libc_realloc+0x25c>
 164:	cb1300e4 	sub	x4, x7, x19
 168:	eb03009f 	cmp	x4, x3
 16c:	54000783 	b.cc	25c <__libc_realloc+0x25c>  // b.lo, b.ul, b.last
 170:	cb0300f6 	sub	x22, x7, x3
 174:	394002c3 	ldrb	w3, [x22]
 178:	35000723 	cbnz	w3, 25c <__libc_realloc+0x25c>
 17c:	38696843 	ldrb	w3, [x2, x9]
 180:	350006e3 	cbnz	w3, 25c <__libc_realloc+0x25c>
 184:	d29ffd63 	mov	x3, #0xffeb                	// #65515
 188:	f2a00023 	movk	x3, #0x1, lsl #16
 18c:	eb03009f 	cmp	x4, x3
 190:	9a839088 	csel	x8, x4, x3, ls	// ls = plast
 194:	eb08029f 	cmp	x20, x8
 198:	54000908 	b.hi	2b8 <__libc_realloc+0x2b8>  // b.pmore
 19c:	91000e80 	add	x0, x20, #0x3
 1a0:	d344fc01 	lsr	x1, x0, #4
 1a4:	11000422 	add	w2, w1, #0x1
 1a8:	f1027c1f 	cmp	x0, #0x9f
 1ac:	54000249 	b.ls	1f4 <__libc_realloc+0x1f4>  // b.plast
 1b0:	91000421 	add	x1, x1, #0x1
 1b4:	528003c0 	mov	w0, #0x1e                  	// #30
 1b8:	5ac01022 	clz	w2, w1
 1bc:	90000003 	adrp	x3, 0 <__malloc_size_classes>
			1bc: R_AARCH64_ADR_PREL_PG_HI21	__malloc_size_classes
 1c0:	4b020000 	sub	w0, w0, w2
 1c4:	91000068 	add	x8, x3, #0x0
			1c4: R_AARCH64_ADD_ABS_LO12_NC	__malloc_size_classes
 1c8:	531e7400 	lsl	w0, w0, #2
 1cc:	11000402 	add	w2, w0, #0x1
 1d0:	7862d908 	ldrh	w8, [x8, w2, sxtw #1]
 1d4:	eb08003f 	cmp	x1, x8
 1d8:	54000069 	b.ls	1e4 <__libc_realloc+0x1e4>  // b.plast
 1dc:	11000c02 	add	w2, w0, #0x3
 1e0:	11000800 	add	w0, w0, #0x2
 1e4:	91000063 	add	x3, x3, #0x0
			1e4: R_AARCH64_ADD_ABS_LO12_NC	__malloc_size_classes
 1e8:	7860d860 	ldrh	w0, [x3, w0, sxtw #1]
 1ec:	eb00003f 	cmp	x1, x0
 1f0:	1a829442 	cinc	w2, w2, hi	// hi = pmore
 1f4:	6b0200df 	cmp	w6, w2
 1f8:	540003ed 	b.le	274 <__libc_realloc+0x274>
 1fc:	aa1403e0 	mov	x0, x20
 200:	94000000 	bl	0 <__libc_malloc_impl>
			200: R_AARCH64_CALL26	__libc_malloc_impl
 204:	aa0003f7 	mov	x23, x0
 208:	b4000ba0 	cbz	x0, 37c <__libc_realloc+0x37c>
 20c:	cb1302c2 	sub	x2, x22, x19
 210:	aa1303e1 	mov	x1, x19
 214:	eb14005f 	cmp	x2, x20
 218:	9a949042 	csel	x2, x2, x20, ls	// ls = plast
 21c:	94000000 	bl	0 <memcpy>
			21c: R_AARCH64_CALL26	memcpy
 220:	aa1303e0 	mov	x0, x19
 224:	94000000 	bl	0 <__libc_free>
			224: R_AARCH64_CALL26	__libc_free
 228:	a94367f8 	ldp	x24, x25, [sp, #48]
 22c:	aa1703e0 	mov	x0, x23
 230:	a9425ff6 	ldp	x22, x23, [sp, #32]
 234:	a94157f4 	ldp	x20, x21, [sp, #16]
 238:	a8c44ffe 	ldp	x30, x19, [sp], #64
 23c:	d65f03c0 	ret
 240:	a94157f4 	ldp	x20, x21, [sp, #16]
 244:	aa0103e0 	mov	x0, x1
 248:	a8c44ffe 	ldp	x30, x19, [sp], #64
 24c:	14000000 	b	0 <__libc_malloc_impl>
			24c: R_AARCH64_JUMP26	__libc_malloc_impl
 250:	927a1423 	and	x3, x1, #0xfc0
 254:	f13f007f 	cmp	x3, #0xfc0
 258:	54fff4a0 	b.eq	ec <__libc_realloc+0xec>  // b.none
 25c:	d4207d00 	brk	#0x3e8
 260:	94000000 	bl	0 <___errno_location>
			260: R_AARCH64_CALL26	___errno_location
 264:	d2800017 	mov	x23, #0x0                   	// #0
 268:	52800181 	mov	w1, #0xc                   	// #12
 26c:	b9000001 	str	w1, [x0]
 270:	17ffffef 	b	22c <__libc_realloc+0x22c>
 274:	6b140084 	subs	w4, w4, w20
 278:	540000e0 	b.eq	294 <__libc_realloc+0x294>  // b.none
 27c:	4b0403e0 	neg	w0, w4
 280:	3820c8ff 	strb	wzr, [x7, w0, sxtw]
 284:	7100109f 	cmp	w4, #0x4
 288:	540000ec 	b.gt	2a4 <__libc_realloc+0x2a4>
 28c:	0b0414a4 	add	w4, w5, w4, lsl #5
 290:	12001c85 	and	w5, w4, #0xff
 294:	381fd265 	sturb	w5, [x19, #-3]
 298:	aa1303f7 	mov	x23, x19
 29c:	a94367f8 	ldp	x24, x25, [sp, #48]
 2a0:	17ffffe3 	b	22c <__libc_realloc+0x22c>
 2a4:	510180a5 	sub	w5, w5, #0x60
 2a8:	381fb0ff 	sturb	wzr, [x7, #-5]
 2ac:	12001ca5 	and	w5, w5, #0xff
 2b0:	b81fc0e4 	stur	w4, [x7, #-4]
 2b4:	17fffff8 	b	294 <__libc_realloc+0x294>
 2b8:	7100bcdf 	cmp	w6, #0x2f
 2bc:	fa438280 	ccmp	x20, x3, #0x0, hi	// hi = pmore
 2c0:	54fff9e9 	b.ls	1fc <__libc_realloc+0x1fc>  // b.plast
 2c4:	927a1423 	and	x3, x1, #0xfc0
 2c8:	f13f007f 	cmp	x3, #0xfc0
 2cc:	54fffc81 	b.ne	25c <__libc_realloc+0x25c>  // b.any
 2d0:	cb020275 	sub	x21, x19, x2
 2d4:	d2820262 	mov	x2, #0x1013                	// #4115
 2d8:	8b020297 	add	x23, x20, x2
 2dc:	9274cc21 	and	x1, x1, #0xfffffffffffff000
 2e0:	8b1502f7 	add	x23, x23, x21
 2e4:	9274cef9 	and	x25, x23, #0xfffffffffffff000
 2e8:	eb19003f 	cmp	x1, x25
 2ec:	54000301 	b.ne	34c <__libc_realloc+0x34c>  // b.any
 2f0:	f9401303 	ldr	x3, [x24, #32]
 2f4:	d1005339 	sub	x25, x25, #0x14
 2f8:	d34cfee1 	lsr	x1, x23, #12
 2fc:	8b150157 	add	x23, x10, x21
 300:	f9000b00 	str	x0, [x24, #16]
 304:	cb150322 	sub	x2, x25, x21
 308:	b374cc23 	bfi	x3, x1, #12, #52
 30c:	f9001303 	str	x3, [x24, #32]
 310:	3839695f 	strb	wzr, [x10, x25]
 314:	6b140042 	subs	w2, w2, w20
 318:	8b19014a 	add	x10, x10, x25
 31c:	385fd2e0 	ldurb	w0, [x23, #-3]
 320:	12001000 	and	w0, w0, #0x1f
 324:	540000e0 	b.eq	340 <__libc_realloc+0x340>  // b.none
 328:	4b0203e1 	neg	w1, w2
 32c:	3821c95f 	strb	wzr, [x10, w1, sxtw]
 330:	7100105f 	cmp	w2, #0x4
 334:	540001ac 	b.gt	368 <__libc_realloc+0x368>
 338:	0b021400 	add	w0, w0, w2, lsl #5
 33c:	12001c00 	and	w0, w0, #0xff
 340:	381fd2e0 	sturb	w0, [x23, #-3]
 344:	a94367f8 	ldp	x24, x25, [sp, #48]
 348:	17ffffb9 	b	22c <__libc_realloc+0x22c>
 34c:	aa1903e2 	mov	x2, x25
 350:	52800023 	mov	w3, #0x1                   	// #1
 354:	94000000 	bl	0 <__mremap>
			354: R_AARCH64_CALL26	__mremap
 358:	b100041f 	cmn	x0, #0x1
 35c:	54fff500 	b.eq	1fc <__libc_realloc+0x1fc>  // b.none
 360:	9100400a 	add	x10, x0, #0x10
 364:	17ffffe3 	b	2f0 <__libc_realloc+0x2f0>
 368:	51018000 	sub	w0, w0, #0x60
 36c:	381fb15f 	sturb	wzr, [x10, #-5]
 370:	12001c00 	and	w0, w0, #0xff
 374:	b81fc142 	stur	w2, [x10, #-4]
 378:	17fffff2 	b	340 <__libc_realloc+0x340>
 37c:	a94367f8 	ldp	x24, x25, [sp, #48]
 380:	17ffffab 	b	22c <__libc_realloc+0x22c>

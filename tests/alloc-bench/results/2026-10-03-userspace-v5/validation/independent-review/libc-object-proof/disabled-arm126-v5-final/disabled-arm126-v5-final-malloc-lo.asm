
/Users/alex/code/vinix/third_party/useralloc-libc/build/musl/aarch64/45e591e09bed5a7f37f2a259e8135213cdbcff073604a7239878a1169ec7dae3/objects/obj/src/malloc/mallocng/malloc.lo:     file format elf64-littleaarch64


Disassembly of section .text.__malloc_atfork:

0000000000000000 <__malloc_atfork>:
   0:	7100001f 	cmp	w0, #0x0
   4:	540000ab 	b.lt	18 <__malloc_atfork+0x18>  // b.tstop
   8:	54000180 	b.eq	38 <__malloc_atfork+0x38>  // b.none
   c:	90000000 	adrp	x0, 0 <__malloc_atfork>
			c: R_AARCH64_ADR_PREL_PG_HI21	__malloc_lock
  10:	b900001f 	str	wzr, [x0]
			10: R_AARCH64_LDST32_ABS_LO12_NC	__malloc_lock
  14:	d65f03c0 	ret
  18:	90000000 	adrp	x0, 0 <__libc>
			18: R_AARCH64_ADR_PREL_PG_HI21	__libc
  1c:	91000000 	add	x0, x0, #0x0
			1c: R_AARCH64_ADD_ABS_LO12_NC	__libc
  20:	39400c00 	ldrb	w0, [x0, #3]
  24:	72001c1f 	tst	w0, #0xff
  28:	54ffff60 	b.eq	14 <__malloc_atfork+0x14>  // b.none
  2c:	90000000 	adrp	x0, 0 <__malloc_atfork>
			2c: R_AARCH64_ADR_PREL_PG_HI21	__malloc_lock
  30:	91000000 	add	x0, x0, #0x0
			30: R_AARCH64_ADD_ABS_LO12_NC	__malloc_lock
  34:	14000000 	b	0 <__lock>
			34: R_AARCH64_JUMP26	__lock
  38:	90000001 	adrp	x1, 0 <__malloc_atfork>
			38: R_AARCH64_ADR_PREL_PG_HI21	__malloc_lock
  3c:	91000020 	add	x0, x1, #0x0
			3c: R_AARCH64_ADD_ABS_LO12_NC	__malloc_lock
  40:	b9400021 	ldr	w1, [x1]
			40: R_AARCH64_LDST32_ABS_LO12_NC	__malloc_lock
  44:	36fffe81 	tbz	w1, #31, 14 <__malloc_atfork+0x14>
  48:	14000000 	b	0 <__unlock>
			48: R_AARCH64_JUMP26	__unlock

Disassembly of section .text.__malloc_alloc_meta:

0000000000000000 <__malloc_alloc_meta>:
   0:	d10143ff 	sub	sp, sp, #0x50
   4:	90000000 	adrp	x0, 0 <__stack_chk_guard>
			4: R_AARCH64_ADR_GOT_PAGE	__stack_chk_guard
   8:	f9400000 	ldr	x0, [x0]
			8: R_AARCH64_LD64_GOT_LO12_NC	__stack_chk_guard
   c:	a90257f4 	stp	x20, x21, [sp, #32]
  10:	90000014 	adrp	x20, 0 <__malloc_alloc_meta>
			10: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
  14:	91000281 	add	x1, x20, #0x0
			14: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
  18:	a9014ffe 	stp	x30, x19, [sp, #16]
  1c:	b9400821 	ldr	w1, [x1, #8]
  20:	f9400002 	ldr	x2, [x0]
  24:	f90007e2 	str	x2, [sp, #8]
  28:	d2800002 	mov	x2, #0x0                   	// #0
  2c:	34000361 	cbz	w1, 98 <__malloc_alloc_meta+0x98>
  30:	91000281 	add	x1, x20, #0x0
			30: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
  34:	f9400833 	ldr	x19, [x1, #16]
  38:	b40006d3 	cbz	x19, 110 <__malloc_alloc_meta+0x110>
  3c:	f9400660 	ldr	x0, [x19, #8]
  40:	eb00027f 	cmp	x19, x0
  44:	540007c0 	b.eq	13c <__malloc_alloc_meta+0x13c>  // b.none
  48:	f9400262 	ldr	x2, [x19]
  4c:	f9000440 	str	x0, [x2, #8]
  50:	f9400262 	ldr	x2, [x19]
  54:	f9000002 	str	x2, [x0]
  58:	f9400820 	ldr	x0, [x1, #16]
  5c:	eb00027f 	cmp	x19, x0
  60:	54000680 	b.eq	130 <__malloc_alloc_meta+0x130>  // b.none
  64:	a9007e7f 	stp	xzr, xzr, [x19]
  68:	90000000 	adrp	x0, 0 <__stack_chk_guard>
			68: R_AARCH64_ADR_GOT_PAGE	__stack_chk_guard
  6c:	f9400000 	ldr	x0, [x0]
			6c: R_AARCH64_LD64_GOT_LO12_NC	__stack_chk_guard
  70:	f94007e2 	ldr	x2, [sp, #8]
  74:	f9400001 	ldr	x1, [x0]
  78:	eb010042 	subs	x2, x2, x1
  7c:	d2800001 	mov	x1, #0x0                   	// #0
  80:	54001561 	b.ne	32c <__malloc_alloc_meta+0x32c>  // b.any
  84:	a94257f4 	ldp	x20, x21, [sp, #32]
  88:	aa1303e0 	mov	x0, x19
  8c:	a9414ffe 	ldp	x30, x19, [sp, #16]
  90:	910143ff 	add	sp, sp, #0x50
  94:	d65f03c0 	ret
  98:	d289cda0 	mov	x0, #0x4e6d                	// #20077
  9c:	a9035ff6 	stp	x22, x23, [sp, #48]
  a0:	910003f6 	mov	x22, sp
  a4:	f2a838c0 	movk	x0, #0x41c6, lsl #16
  a8:	90000015 	adrp	x21, 0 <__libc>
			a8: R_AARCH64_ADR_PREL_PG_HI21	__libc
  ac:	d2800013 	mov	x19, #0x0                   	// #0
  b0:	910002b5 	add	x21, x21, #0x0
			b0: R_AARCH64_ADD_ABS_LO12_NC	__libc
  b4:	9b007ec0 	mul	x0, x22, x0
  b8:	f90003e0 	str	x0, [sp]
  bc:	14000002 	b	c4 <__malloc_alloc_meta+0xc4>
  c0:	91004273 	add	x19, x19, #0x10
  c4:	f94006a1 	ldr	x1, [x21, #8]
  c8:	f8736820 	ldr	x0, [x1, x19]
  cc:	b4000140 	cbz	x0, f4 <__malloc_alloc_meta+0xf4>
  d0:	f100641f 	cmp	x0, #0x19
  d4:	54ffff61 	b.ne	c0 <__malloc_alloc_meta+0xc0>  // b.any
  d8:	8b130021 	add	x1, x1, x19
  dc:	d2800102 	mov	x2, #0x8                   	// #8
  e0:	aa1603e0 	mov	x0, x22
  e4:	f9400421 	ldr	x1, [x1, #8]
  e8:	8b020021 	add	x1, x1, x2
  ec:	94000000 	bl	0 <memcpy>
			ec: R_AARCH64_CALL26	memcpy
  f0:	17fffff4 	b	c0 <__malloc_alloc_meta+0xc0>
  f4:	91000280 	add	x0, x20, #0x0
			f4: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
  f8:	52800021 	mov	w1, #0x1                   	// #1
  fc:	f94003e2 	ldr	x2, [sp]
 100:	f9000282 	str	x2, [x20]
			100: R_AARCH64_LDST64_ABS_LO12_NC	__malloc_context
 104:	b9000801 	str	w1, [x0, #8]
 108:	a9435ff6 	ldp	x22, x23, [sp, #48]
 10c:	17ffffc9 	b	30 <__malloc_alloc_meta+0x30>
 110:	f9401020 	ldr	x0, [x1, #32]
 114:	b4000180 	cbz	x0, 144 <__malloc_alloc_meta+0x144>
 118:	f9400c33 	ldr	x19, [x1, #24]
 11c:	d1000400 	sub	x0, x0, #0x1
 120:	91000294 	add	x20, x20, #0x0
			120: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 124:	9100a261 	add	x1, x19, #0x28
 128:	a9018281 	stp	x1, x0, [x20, #24]
 12c:	17ffffce 	b	64 <__malloc_alloc_meta+0x64>
 130:	f9400660 	ldr	x0, [x19, #8]
 134:	f9000820 	str	x0, [x1, #16]
 138:	17ffffcb 	b	64 <__malloc_alloc_meta+0x64>
 13c:	f900083f 	str	xzr, [x1, #16]
 140:	17ffffc9 	b	64 <__malloc_alloc_meta+0x64>
 144:	90000000 	adrp	x0, 0 <__libc>
			144: R_AARCH64_ADR_PREL_PG_HI21	__libc+0x30
 148:	a9035ff6 	stp	x22, x23, [sp, #48]
 14c:	d2820003 	mov	x3, #0x1000                	// #4096
 150:	f9401422 	ldr	x2, [x1, #40]
 154:	f9400000 	ldr	x0, [x0]
			154: R_AARCH64_LDST64_ABS_LO12_NC	__libc+0x30
 158:	eb03001f 	cmp	x0, x3
 15c:	9a832017 	csel	x23, x0, x3, cs	// cs = hs, nlast
 160:	b5000ac2 	cbnz	x2, 2b8 <__malloc_alloc_meta+0x2b8>
 164:	f941e035 	ldr	x21, [x1, #960]
 168:	b10006bf 	cmn	x21, #0x1
 16c:	540001a0 	b.eq	1a0 <__malloc_alloc_meta+0x1a0>  // b.none
 170:	b4000635 	cbz	x21, 234 <__malloc_alloc_meta+0x234>
 174:	8b1702b6 	add	x22, x21, x23
 178:	d2801ac8 	mov	x8, #0xd6                  	// #214
 17c:	aa1603e0 	mov	x0, x22
 180:	d4000001 	svc	#0x0
 184:	eb0002df 	cmp	x22, x0
 188:	54000800 	b.eq	288 <__malloc_alloc_meta+0x288>  // b.none
 18c:	91000280 	add	x0, x20, #0x0
			18c: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 190:	92800002 	mov	x2, #0xffffffffffffffff    	// #-1
 194:	f9401401 	ldr	x1, [x0, #40]
 198:	f901e002 	str	x2, [x0, #960]
 19c:	b5000801 	cbnz	x1, 29c <__malloc_alloc_meta+0x29c>
 1a0:	f90023f8 	str	x24, [sp, #64]
 1a4:	91000298 	add	x24, x20, #0x0
			1a4: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 1a8:	d2800056 	mov	x22, #0x2                   	// #2
 1ac:	d2800005 	mov	x5, #0x0                   	// #0
 1b0:	12800004 	mov	w4, #0xffffffff            	// #-1
 1b4:	52800443 	mov	w3, #0x22                  	// #34
 1b8:	f9401b01 	ldr	x1, [x24, #48]
 1bc:	52800002 	mov	w2, #0x0                   	// #0
 1c0:	d2800000 	mov	x0, #0x0                   	// #0
 1c4:	9ac122d6 	lsl	x22, x22, x1
 1c8:	9b177ec1 	mul	x1, x22, x23
 1cc:	94000000 	bl	0 <__mmap>
			1cc: R_AARCH64_CALL26	__mmap
 1d0:	b100041f 	cmn	x0, #0x1
 1d4:	54000a60 	b.eq	320 <__malloc_alloc_meta+0x320>  // b.none
 1d8:	d34cfee1 	lsr	x1, x23, #12
 1dc:	d10006d6 	sub	x22, x22, #0x1
 1e0:	f9401b02 	ldr	x2, [x24, #48]
 1e4:	8b170015 	add	x21, x0, x23
 1e8:	9b017ec0 	mul	x0, x22, x1
 1ec:	f9002715 	str	x21, [x24, #72]
 1f0:	91000442 	add	x2, x2, #0x1
 1f4:	a9028b00 	stp	x0, x2, [x24, #40]
 1f8:	d10006e1 	sub	x1, x23, #0x1
 1fc:	f94023f8 	ldr	x24, [sp, #64]
 200:	ea0102bf 	tst	x21, x1
 204:	54000641 	b.ne	2cc <__malloc_alloc_meta+0x2cc>  // b.any
 208:	aa1703e1 	mov	x1, x23
 20c:	aa1503e0 	mov	x0, x21
 210:	52800062 	mov	w2, #0x3                   	// #3
 214:	94000000 	bl	0 <mprotect>
			214: R_AARCH64_CALL26	mprotect
 218:	340005a0 	cbz	w0, 2cc <__malloc_alloc_meta+0x2cc>
 21c:	94000000 	bl	0 <___errno_location>
			21c: R_AARCH64_CALL26	___errno_location
 220:	b9400000 	ldr	w0, [x0]
 224:	7100981f 	cmp	w0, #0x26
 228:	54000520 	b.eq	2cc <__malloc_alloc_meta+0x2cc>  // b.none
 22c:	a9435ff6 	ldp	x22, x23, [sp, #48]
 230:	17ffff8e 	b	68 <__malloc_alloc_meta+0x68>
 234:	d2801ac8 	mov	x8, #0xd6                  	// #214
 238:	d2800000 	mov	x0, #0x0                   	// #0
 23c:	d4000001 	svc	#0x0
 240:	d10006e2 	sub	x2, x23, #0x1
 244:	cb0003f6 	neg	x22, x0
 248:	8a0202d6 	and	x22, x22, x2
 24c:	8b0002d6 	add	x22, x22, x0
 250:	f901e036 	str	x22, [x1, #960]
 254:	8b1706d6 	add	x22, x22, x23, lsl #1
 258:	aa1603e0 	mov	x0, x22
 25c:	d4000001 	svc	#0x0
 260:	eb0002df 	cmp	x22, x0
 264:	54fff941 	b.ne	18c <__malloc_alloc_meta+0x18c>  // b.any
 268:	f941e020 	ldr	x0, [x1, #960]
 26c:	cb1702d5 	sub	x21, x22, x23
 270:	aa1703e1 	mov	x1, x23
 274:	d2800005 	mov	x5, #0x0                   	// #0
 278:	12800004 	mov	w4, #0xffffffff            	// #-1
 27c:	52800643 	mov	w3, #0x32                  	// #50
 280:	52800002 	mov	w2, #0x0                   	// #0
 284:	94000000 	bl	0 <__mmap>
			284: R_AARCH64_CALL26	__mmap
 288:	91000281 	add	x1, x20, #0x0
			288: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 28c:	d34cfee0 	lsr	x0, x23, #12
 290:	f9001420 	str	x0, [x1, #40]
 294:	f901e036 	str	x22, [x1, #960]
 298:	1400000d 	b	2cc <__malloc_alloc_meta+0x2cc>
 29c:	f9402415 	ldr	x21, [x0, #72]
 2a0:	d10006e0 	sub	x0, x23, #0x1
 2a4:	ea0002bf 	tst	x21, x0
 2a8:	1a9f17e0 	cset	w0, eq	// eq = none
 2ac:	14000007 	b	2c8 <__malloc_alloc_meta+0x2c8>
 2b0:	f9001c15 	str	x21, [x0, #56]
 2b4:	1400000f 	b	2f0 <__malloc_alloc_meta+0x2f0>
 2b8:	f9402435 	ldr	x21, [x1, #72]
 2bc:	d10006e0 	sub	x0, x23, #0x1
 2c0:	ea0002bf 	tst	x21, x0
 2c4:	1a9f17e0 	cset	w0, eq	// eq = none
 2c8:	35fffa00 	cbnz	w0, 208 <__malloc_alloc_meta+0x208>
 2cc:	91000280 	add	x0, x20, #0x0
			2cc: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 2d0:	914006a2 	add	x2, x21, #0x1, lsl #12
 2d4:	f9401401 	ldr	x1, [x0, #40]
 2d8:	f9002402 	str	x2, [x0, #72]
 2dc:	f9402002 	ldr	x2, [x0, #64]
 2e0:	d1000421 	sub	x1, x1, #0x1
 2e4:	f9001401 	str	x1, [x0, #40]
 2e8:	b4fffe42 	cbz	x2, 2b0 <__malloc_alloc_meta+0x2b0>
 2ec:	f9000455 	str	x21, [x2, #8]
 2f0:	91000281 	add	x1, x20, #0x0
			2f0: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 2f4:	52800ca3 	mov	w3, #0x65                  	// #101
 2f8:	f9400282 	ldr	x2, [x20]
			2f8: R_AARCH64_LDST64_ABS_LO12_NC	__malloc_context
 2fc:	d2800c80 	mov	x0, #0x64                  	// #100
 300:	f9002035 	str	x21, [x1, #64]
 304:	f90002a2 	str	x2, [x21]
 308:	f9402022 	ldr	x2, [x1, #64]
 30c:	b9001043 	str	w3, [x2, #16]
 310:	f9402033 	ldr	x19, [x1, #64]
 314:	a9435ff6 	ldp	x22, x23, [sp, #48]
 318:	91006273 	add	x19, x19, #0x18
 31c:	17ffff81 	b	120 <__malloc_alloc_meta+0x120>
 320:	f94023f8 	ldr	x24, [sp, #64]
 324:	a9435ff6 	ldp	x22, x23, [sp, #48]
 328:	17ffff50 	b	68 <__malloc_alloc_meta+0x68>
 32c:	a9035ff6 	stp	x22, x23, [sp, #48]
 330:	f90023f8 	str	x24, [sp, #64]
 334:	94000000 	bl	0 <__stack_chk_fail>
			334: R_AARCH64_CALL26	__stack_chk_fail

Disassembly of section .text.alloc_slot:

0000000000000000 <alloc_slot>:
   0:	a9ba4ffe 	stp	x30, x19, [sp, #-96]!
   4:	a90367f8 	stp	x24, x25, [sp, #48]
   8:	93407c18 	sxtw	x24, w0
   c:	aa0103f9 	mov	x25, x1
  10:	91002b01 	add	x1, x24, #0xa
  14:	a9025ff6 	stp	x22, x23, [sp, #32]
  18:	90000016 	adrp	x22, 0 <alloc_slot>
			18: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
  1c:	910002c2 	add	x2, x22, #0x0
			1c: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
  20:	a90157f4 	stp	x20, x21, [sp, #16]
  24:	aa1803f5 	mov	x21, x24
  28:	f8617846 	ldr	x6, [x2, x1, lsl #3]
  2c:	b4000286 	cbz	x6, 7c <alloc_slot+0x7c>
  30:	b94018c0 	ldr	w0, [x6, #24]
  34:	350013c0 	cbnz	w0, 2ac <alloc_slot+0x2ac>
  38:	b9401cc3 	ldr	w3, [x6, #28]
  3c:	f94004c0 	ldr	x0, [x6, #8]
  40:	35000663 	cbnz	w3, 10c <alloc_slot+0x10c>
  44:	eb0000df 	cmp	x6, x0
  48:	540005e0 	b.eq	104 <alloc_slot+0x104>  // b.none
  4c:	f94000c3 	ldr	x3, [x6]
  50:	f9000460 	str	x0, [x3, #8]
  54:	f94000c3 	ldr	x3, [x6]
  58:	f9000003 	str	x3, [x0]
  5c:	f8617840 	ldr	x0, [x2, x1, lsl #3]
  60:	eb0000df 	cmp	x6, x0
  64:	540004a0 	b.eq	f8 <alloc_slot+0xf8>  // b.none
  68:	910002c0 	add	x0, x22, #0x0
			68: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
  6c:	91002b01 	add	x1, x24, #0xa
  70:	a9007cdf 	stp	xzr, xzr, [x6]
  74:	f8617806 	ldr	x6, [x0, x1, lsl #3]
  78:	b50004e6 	cbnz	x6, 114 <alloc_slot+0x114>
  7c:	a9046ffa 	stp	x26, x27, [sp, #64]
  80:	9000001b 	adrp	x27, 0 <alloc_slot>
			80: R_AARCH64_ADR_PREL_PG_HI21	__malloc_size_classes
  84:	91000360 	add	x0, x27, #0x0
			84: R_AARCH64_ADD_ABS_LO12_NC	__malloc_size_classes
  88:	f9002bfc 	str	x28, [sp, #80]
  8c:	7875d817 	ldrh	w23, [x0, w21, sxtw #1]
  90:	94000000 	bl	0 <alloc_slot>
			90: R_AARCH64_CALL26	__malloc_alloc_meta
  94:	aa0003f4 	mov	x20, x0
  98:	531c6efc 	lsl	w28, w23, #4
  9c:	d37c3ef7 	ubfiz	x23, x23, #4, #16
  a0:	b4003d20 	cbz	x0, 844 <alloc_slot+0x844>
  a4:	910002c0 	add	x0, x22, #0x0
			a4: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
  a8:	90000001 	adrp	x1, 0 <__libc>
			a8: R_AARCH64_ADR_PREL_PG_HI21	__libc+0x30
  ac:	8b180c00 	add	x0, x0, x24, lsl #3
  b0:	f9400024 	ldr	x4, [x1]
			b0: R_AARCH64_LDST64_ABS_LO12_NC	__libc+0x30
  b4:	f940fc03 	ldr	x3, [x0, #504]
  b8:	710022bf 	cmp	w21, #0x8
  bc:	5400110c 	b.gt	2dc <alloc_slot+0x2dc>
  c0:	8b180700 	add	x0, x24, x24, lsl #1
  c4:	90000001 	adrp	x1, 0 <alloc_slot>
			c4: R_AARCH64_ADR_PREL_PG_HI21	.rodata.small_cnt_tab
  c8:	91000021 	add	x1, x1, #0x0
			c8: R_AARCH64_ADD_ABS_LO12_NC	.rodata.small_cnt_tab
  cc:	8b000022 	add	x2, x1, x0
  d0:	38606833 	ldrb	w19, [x1, x0]
  d4:	d37e1e60 	ubfiz	x0, x19, #2, #8
  d8:	eb00007f 	cmp	x3, x0
  dc:	54001202 	b.cs	31c <alloc_slot+0x31c>  // b.hs, b.nlast
  e0:	39400453 	ldrb	w19, [x2, #1]
  e4:	d37e1e60 	ubfiz	x0, x19, #2, #8
  e8:	eb03001f 	cmp	x0, x3
  ec:	54001189 	b.ls	31c <alloc_slot+0x31c>  // b.plast
  f0:	39400853 	ldrb	w19, [x2, #2]
  f4:	1400008a 	b	31c <alloc_slot+0x31c>
  f8:	f94004c0 	ldr	x0, [x6, #8]
  fc:	f8217840 	str	x0, [x2, x1, lsl #3]
 100:	17ffffda 	b	68 <alloc_slot+0x68>
 104:	f821785f 	str	xzr, [x2, x1, lsl #3]
 108:	17ffffd8 	b	68 <alloc_slot+0x68>
 10c:	aa0003e6 	mov	x6, x0
 110:	f8217840 	str	x0, [x2, x1, lsl #3]
 114:	f94010c1 	ldr	x1, [x6, #32]
 118:	52800040 	mov	w0, #0x2                   	// #2
 11c:	b9401cc2 	ldr	w2, [x6, #28]
 120:	d3401023 	ubfx	x3, x1, #0, #5
 124:	1ac32000 	lsl	w0, w0, w3
 128:	51000400 	sub	w0, w0, #0x1
 12c:	6b00005f 	cmp	w2, w0
 130:	54000480 	b.eq	1c0 <alloc_slot+0x1c0>  // b.none
 134:	f94008c4 	ldr	x4, [x6, #16]
 138:	52800040 	mov	w0, #0x2                   	// #2
 13c:	f9400481 	ldr	x1, [x4, #8]
 140:	12001023 	and	w3, w1, #0x1f
 144:	d3401021 	ubfx	x1, x1, #0, #5
 148:	1ac12000 	lsl	w0, w0, w1
 14c:	51000400 	sub	w0, w0, #0x1
 150:	6a02001f 	tst	w0, w2
 154:	54000101 	b.ne	174 <alloc_slot+0x174>  // b.any
 158:	f94004c7 	ldr	x7, [x6, #8]
 15c:	eb0700df 	cmp	x6, x7
 160:	540003e0 	b.eq	1dc <alloc_slot+0x1dc>  // b.none
 164:	910002c0 	add	x0, x22, #0x0
			164: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 168:	91002b01 	add	x1, x24, #0xa
 16c:	f8217807 	str	x7, [x0, x1, lsl #3]
 170:	aa0703e6 	mov	x6, x7
 174:	b94018c0 	ldr	w0, [x6, #24]
 178:	35000660 	cbnz	w0, 244 <alloc_slot+0x244>
 17c:	f94008c0 	ldr	x0, [x6, #16]
 180:	90000001 	adrp	x1, 0 <__libc>
			180: R_AARCH64_ADR_PREL_PG_HI21	__libc
 184:	91000021 	add	x1, x1, #0x0
			184: R_AARCH64_ADD_ABS_LO12_NC	__libc
 188:	52800047 	mov	w7, #0x2                   	// #2
 18c:	910070c4 	add	x4, x6, #0x1c
 190:	f9400400 	ldr	x0, [x0, #8]
 194:	39400c21 	ldrb	w1, [x1, #3]
 198:	d3401000 	ubfx	x0, x0, #0, #5
 19c:	1ac020e7 	lsl	w7, w7, w0
 1a0:	510004e0 	sub	w0, w7, #0x1
 1a4:	4b0703e7 	neg	w7, w7
 1a8:	72001c3f 	tst	w1, #0xff
 1ac:	54000541 	b.ne	254 <alloc_slot+0x254>  // b.any
 1b0:	b9401cc1 	ldr	w1, [x6, #28]
 1b4:	0a070027 	and	w7, w1, w7
 1b8:	b9001cc7 	str	w7, [x6, #28]
 1bc:	1400002e 	b	274 <alloc_slot+0x274>
 1c0:	362ffda1 	tbz	w1, #5, 174 <alloc_slot+0x174>
 1c4:	910002c0 	add	x0, x22, #0x0
			1c4: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 1c8:	91002b01 	add	x1, x24, #0xa
 1cc:	f94004c6 	ldr	x6, [x6, #8]
 1d0:	f8217806 	str	x6, [x0, x1, lsl #3]
 1d4:	b9401cc2 	ldr	w2, [x6, #28]
 1d8:	17ffffd7 	b	134 <alloc_slot+0x134>
 1dc:	f94010e6 	ldr	x6, [x7, #32]
 1e0:	90000000 	adrp	x0, 0 <alloc_slot>
			1e0: R_AARCH64_ADR_PREL_PG_HI21	__malloc_size_classes
 1e4:	91000000 	add	x0, x0, #0x0
			1e4: R_AARCH64_ADD_ABS_LO12_NC	__malloc_size_classes
 1e8:	11000863 	add	w3, w3, #0x2
 1ec:	53062cc1 	ubfx	w1, w6, #6, #6
 1f0:	7861d805 	ldrh	w5, [x0, w1, sxtw #1]
 1f4:	531c6ca5 	lsl	w5, w5, #4
 1f8:	1b057c61 	mul	w1, w3, w5
 1fc:	11004021 	add	w1, w1, #0x10
 200:	14000003 	b	20c <alloc_slot+0x20c>
 204:	11000463 	add	w3, w3, #0x1
 208:	2a0203e1 	mov	w1, w2
 20c:	0b0100a2 	add	w2, w5, w1
 210:	51000440 	sub	w0, w2, #0x1
 214:	4a010000 	eor	w0, w0, w1
 218:	713ffc1f 	cmp	w0, #0xfff
 21c:	54ffff4d 	b.le	204 <alloc_slot+0x204>
 220:	120010c0 	and	w0, w6, #0x1f
 224:	39402081 	ldrb	w1, [x4, #8]
 228:	11000400 	add	w0, w0, #0x1
 22c:	6b03001f 	cmp	w0, w3
 230:	1a83d000 	csel	w0, w0, w3, le
 234:	51000400 	sub	w0, w0, #0x1
 238:	33001001 	bfxil	w1, w0, #0, #5
 23c:	39002081 	strb	w1, [x4, #8]
 240:	17ffffcc 	b	170 <alloc_slot+0x170>
 244:	a9046ffa 	stp	x26, x27, [sp, #64]
 248:	f9002bfc 	str	x28, [sp, #80]
 24c:	d4207d00 	brk	#0x3e8
 250:	d5033bbf 	dmb	ish
 254:	b9401cc5 	ldr	w5, [x6, #28]
 258:	2a0503e1 	mov	w1, w5
 25c:	0a0700a3 	and	w3, w5, w7
 260:	885ffc82 	ldaxr	w2, [x4]
 264:	6b0200bf 	cmp	w5, w2
 268:	54ffff41 	b.ne	250 <alloc_slot+0x250>  // b.any
 26c:	8802fc83 	stlxr	w2, w3, [x4]
 270:	35ffff82 	cbnz	w2, 260 <alloc_slot+0x260>
 274:	0a010000 	and	w0, w0, w1
 278:	b90018c0 	str	w0, [x6, #24]
 27c:	34fffe40 	cbz	w0, 244 <alloc_slot+0x244>
 280:	f94010c1 	ldr	x1, [x6, #32]
 284:	53062c21 	ubfx	w1, w1, #6, #6
 288:	51001c21 	sub	w1, w1, #0x7
 28c:	71007c3f 	cmp	w1, #0x1f
 290:	540000e8 	b.hi	2ac <alloc_slot+0x2ac>  // b.pmore
 294:	910002c2 	add	x2, x22, #0x0
			294: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 298:	8b21c041 	add	x1, x2, w1, sxtw
 29c:	394e6022 	ldrb	w2, [x1, #920]
 2a0:	34000062 	cbz	w2, 2ac <alloc_slot+0x2ac>
 2a4:	51000442 	sub	w2, w2, #0x1
 2a8:	390e6022 	strb	w2, [x1, #920]
 2ac:	4b0003e2 	neg	w2, w0
 2b0:	0a220001 	bic	w1, w0, w2
 2b4:	b90018c1 	str	w1, [x6, #24]
 2b8:	6a000042 	ands	w2, w2, w0
 2bc:	54ffee00 	b.eq	7c <alloc_slot+0x7c>  // b.none
 2c0:	5ac00040 	rbit	w0, w2
 2c4:	5ac01000 	clz	w0, w0
 2c8:	a94157f4 	ldp	x20, x21, [sp, #16]
 2cc:	a9425ff6 	ldp	x22, x23, [sp, #32]
 2d0:	a94367f8 	ldp	x24, x25, [sp, #48]
 2d4:	a8c64ffe 	ldp	x30, x19, [sp], #96
 2d8:	d65f03c0 	ret
 2dc:	120006a1 	and	w1, w21, #0x3
 2e0:	90000000 	adrp	x0, 0 <alloc_slot>
			2e0: R_AARCH64_ADR_PREL_PG_HI21	.rodata.med_cnt_tab
 2e4:	91000000 	add	x0, x0, #0x0
			2e4: R_AARCH64_ADD_ABS_LO12_NC	.rodata.med_cnt_tab
 2e8:	3861c813 	ldrb	w19, [x0, w1, sxtw]
 2ec:	14000002 	b	2f4 <alloc_slot+0x2f4>
 2f0:	13017e73 	asr	w19, w19, #1
 2f4:	37000093 	tbnz	w19, #0, 304 <alloc_slot+0x304>
 2f8:	531e7660 	lsl	w0, w19, #2
 2fc:	eb20c07f 	cmp	x3, w0, sxtw
 300:	54ffff83 	b.cc	2f0 <alloc_slot+0x2f0>  // b.lo, b.ul, b.last
 304:	b2404fe1 	mov	x1, #0xfffff               	// #1048575
 308:	14000002 	b	310 <alloc_slot+0x310>
 30c:	13017e73 	asr	w19, w19, #1
 310:	9bb37ee0 	umull	x0, w23, w19
 314:	eb01001f 	cmp	x0, x1
 318:	54ffffa8 	b.hi	30c <alloc_slot+0x30c>  // b.pmore
 31c:	d341fc80 	lsr	x0, x4, #1
 320:	93407e7a 	sxtw	x26, w19
 324:	7100067f 	cmp	w19, #0x1
 328:	54000280 	b.eq	378 <alloc_slot+0x378>  // b.none
 32c:	9bba7f85 	umull	x5, w28, w26
 330:	910040a1 	add	x1, x5, #0x10
 334:	eb00003f 	cmp	x1, x0
 338:	540019e9 	b.ls	674 <alloc_slot+0x674>  // b.plast
 33c:	531e7666 	lsl	w6, w19, #2
 340:	93407cc6 	sxtw	x6, w6
 344:	910002c1 	add	x1, x22, #0x0
			344: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 348:	51001ea0 	sub	w0, w21, #0x7
 34c:	394ee022 	ldrb	w2, [x1, #952]
 350:	71007c1f 	cmp	w0, #0x1f
 354:	54000368 	b.hi	3c0 <alloc_slot+0x3c0>  // b.pmore
 358:	8b20c020 	add	x0, x1, w0, sxtw
 35c:	394de001 	ldrb	w1, [x0, #888]
 360:	394e6007 	ldrb	w7, [x0, #920]
 364:	350001c1 	cbnz	w1, 39c <alloc_slot+0x39c>
 368:	71018cff 	cmp	w7, #0x63
 36c:	1a9f97e1 	cset	w1, hi	// hi = pmore
 370:	1a9f87e8 	cset	w8, ls	// ls = plast
 374:	14000015 	b	3c8 <alloc_slot+0x3c8>
 378:	910042e1 	add	x1, x23, #0x10
 37c:	eb00003f 	cmp	x1, x0
 380:	54000088 	b.hi	390 <alloc_slot+0x390>  // b.pmore
 384:	d280005a 	mov	x26, #0x2                   	// #2
 388:	2a1a03f3 	mov	w19, w26
 38c:	17ffffe8 	b	32c <alloc_slot+0x32c>
 390:	aa1703e5 	mov	x5, x23
 394:	d2800086 	mov	x6, #0x4                   	// #4
 398:	17ffffeb 	b	344 <alloc_slot+0x344>
 39c:	4b010041 	sub	w1, w2, w1
 3a0:	7100243f 	cmp	w1, #0x9
 3a4:	54fffe2c 	b.gt	368 <alloc_slot+0x368>
 3a8:	71018cff 	cmp	w7, #0x63
 3ac:	110004e8 	add	w8, w7, #0x1
 3b0:	12800d21 	mov	w1, #0xffffff96            	// #-106
 3b4:	1a882021 	csel	w1, w1, w8, cs	// cs = hs, nlast
 3b8:	390e6001 	strb	w1, [x0, #920]
 3bc:	17ffffeb 	b	368 <alloc_slot+0x368>
 3c0:	52800001 	mov	w1, #0x0                   	// #0
 3c4:	52800028 	mov	w8, #0x1                   	// #1
 3c8:	11000440 	add	w0, w2, #0x1
 3cc:	12001c00 	and	w0, w0, #0xff
 3d0:	7103fc5f 	cmp	w2, #0xff
 3d4:	54000320 	b.eq	438 <alloc_slot+0x438>  // b.none
 3d8:	910002c2 	add	x2, x22, #0x0
			3d8: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 3dc:	d1000487 	sub	x7, x4, #0x1
 3e0:	390ee040 	strb	w0, [x2, #952]
 3e4:	37000475 	tbnz	w21, #0, 470 <alloc_slot+0x470>
 3e8:	71007ebf 	cmp	w21, #0x1f
 3ec:	540003ac 	b.gt	460 <alloc_slot+0x460>
 3f0:	110006a0 	add	w0, w21, #0x1
 3f4:	7100011f 	cmp	w8, #0x0
 3f8:	8b20cc40 	add	x0, x2, w0, sxtw #3
 3fc:	f940fc00 	ldr	x0, [x0, #504]
 400:	8b000063 	add	x3, x3, x0
 404:	fa461062 	ccmp	x3, x6, #0x2, ne	// ne = any
 408:	540003a2 	b.cs	47c <alloc_slot+0x47c>  // b.hs, b.nlast
 40c:	120006a0 	and	w0, w21, #0x3
 410:	7100081f 	cmp	w0, #0x2
 414:	54001180 	b.eq	644 <alloc_slot+0x644>  // b.none
 418:	eb040cbf 	cmp	x5, x4, lsl #3
 41c:	54001188 	b.hi	64c <alloc_slot+0x64c>  // b.pmore
 420:	eb0404bf 	cmp	x5, x4, lsl #1
 424:	540002c9 	b.ls	47c <alloc_slot+0x47c>  // b.plast
 428:	d28000a0 	mov	x0, #0x5                   	// #5
 42c:	52800022 	mov	w2, #0x1                   	// #1
 430:	2a0003f3 	mov	w19, w0
 434:	14000015 	b	488 <alloc_slot+0x488>
 438:	910002c0 	add	x0, x22, #0x0
			438: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 43c:	90000002 	adrp	x2, 0 <alloc_slot>
			43c: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context+0x378
 440:	910e6000 	add	x0, x0, #0x398
 444:	91000042 	add	x2, x2, #0x0
			444: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context+0x378
 448:	14000002 	b	450 <alloc_slot+0x450>
 44c:	3800145f 	strb	wzr, [x2], #1
 450:	eb00005f 	cmp	x2, x0
 454:	54ffffc1 	b.ne	44c <alloc_slot+0x44c>  // b.any
 458:	52800020 	mov	w0, #0x1                   	// #1
 45c:	17ffffdf 	b	3d8 <alloc_slot+0x3d8>
 460:	7100011f 	cmp	w8, #0x0
 464:	fa461062 	ccmp	x3, x6, #0x2, ne	// ne = any
 468:	540000a2 	b.cs	47c <alloc_slot+0x47c>  // b.hs, b.nlast
 46c:	17ffffe8 	b	40c <alloc_slot+0x40c>
 470:	7100011f 	cmp	w8, #0x0
 474:	fa461062 	ccmp	x3, x6, #0x2, ne	// ne = any
 478:	54000ac3 	b.cc	5d0 <alloc_slot+0x5d0>  // b.lo, b.ul, b.last
 47c:	71001e7f 	cmp	w19, #0x7
 480:	93407e60 	sxtw	x0, w19
 484:	1a9fc7e2 	cset	w2, le
 488:	9ba07f80 	umull	x0, w28, w0
 48c:	928001fa 	mov	x26, #0xfffffffffffffff0    	// #-16
 490:	52000021 	eor	w1, w1, #0x1
 494:	cb00035a 	sub	x26, x26, x0
 498:	91004000 	add	x0, x0, #0x10
 49c:	8a07035a 	and	x26, x26, x7
 4a0:	8b00035a 	add	x26, x26, x0
 4a4:	6a01005f 	tst	w2, w1
 4a8:	54000ae1 	b.ne	604 <alloc_slot+0x604>  // b.any
 4ac:	aa1a03e1 	mov	x1, x26
 4b0:	d2800005 	mov	x5, #0x0                   	// #0
 4b4:	12800004 	mov	w4, #0xffffffff            	// #-1
 4b8:	52800443 	mov	w3, #0x22                  	// #34
 4bc:	52800062 	mov	w2, #0x3                   	// #3
 4c0:	d2800000 	mov	x0, #0x0                   	// #0
 4c4:	94000000 	bl	0 <__mmap>
			4c4: R_AARCH64_CALL26	__mmap
 4c8:	b100041f 	cmn	x0, #0x1
 4cc:	54001a40 	b.eq	814 <alloc_slot+0x814>  // b.none
 4d0:	d281fe02 	mov	x2, #0xff0                 	// #4080
 4d4:	d34cff46 	lsr	x6, x26, #12
 4d8:	f9401285 	ldr	x5, [x20, #32]
 4dc:	910002c4 	add	x4, x22, #0x0
			4dc: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 4e0:	9ad70841 	udiv	x1, x2, x23
 4e4:	51000663 	sub	w3, w19, #0x1
 4e8:	93407e7a 	sxtw	x26, w19
 4ec:	b374ccc5 	bfi	x5, x6, #12, #52
 4f0:	f9001285 	str	x5, [x20, #32]
 4f4:	51000421 	sub	w1, w1, #0x1
 4f8:	b9400c82 	ldr	w2, [x4, #12]
 4fc:	6b13003f 	cmp	w1, w19
 500:	1a83b021 	csel	w1, w1, w3, lt	// lt = tstop
 504:	11000442 	add	w2, w2, #0x1
 508:	b9000c82 	str	w2, [x4, #12]
 50c:	0aa17c22 	bic	w2, w1, w1, asr #31
 510:	910002d6 	add	x22, x22, #0x0
			510: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 514:	52800041 	mov	w1, #0x2                   	// #2
 518:	8b180ec4 	add	x4, x22, x24, lsl #3
 51c:	1ac22025 	lsl	w5, w1, w2
 520:	510004a5 	sub	w5, w5, #0x1
 524:	1ac32021 	lsl	w1, w1, w3
 528:	120016b5 	and	w21, w21, #0x3f
 52c:	12001063 	and	w3, w3, #0x1f
 530:	f940fc86 	ldr	x6, [x4, #504]
 534:	321b0063 	orr	w3, w3, #0x20
 538:	2a151863 	orr	w3, w3, w21, lsl #6
 53c:	8b1a00c6 	add	x6, x6, x26
 540:	f900fc86 	str	x6, [x4, #504]
 544:	b9001a85 	str	w5, [x20, #24]
 548:	f9000a80 	str	x0, [x20, #16]
 54c:	b9401a84 	ldr	w4, [x20, #24]
 550:	4b040021 	sub	w1, w1, w4
 554:	51000421 	sub	w1, w1, #0x1
 558:	b9001e81 	str	w1, [x20, #28]
 55c:	f9000014 	str	x20, [x0]
 560:	f9400a80 	ldr	x0, [x20, #16]
 564:	39402001 	ldrb	w1, [x0, #8]
 568:	33001041 	bfxil	w1, w2, #0, #5
 56c:	39002001 	strb	w1, [x0, #8]
 570:	79404280 	ldrh	w0, [x20, #32]
 574:	f9400682 	ldr	x2, [x20, #8]
 578:	12144c00 	and	w0, w0, #0xfffff000
 57c:	b9401a81 	ldr	w1, [x20, #24]
 580:	2a000060 	orr	w0, w3, w0
 584:	79004280 	strh	w0, [x20, #32]
 588:	51000420 	sub	w0, w1, #0x1
 58c:	b9001a80 	str	w0, [x20, #24]
 590:	b5ffe5e2 	cbnz	x2, 24c <alloc_slot+0x24c>
 594:	f9400280 	ldr	x0, [x20]
 598:	b5ffe5a0 	cbnz	x0, 24c <alloc_slot+0x24c>
 59c:	91002b18 	add	x24, x24, #0xa
 5a0:	f8787ac0 	ldr	x0, [x22, x24, lsl #3]
 5a4:	b4001740 	cbz	x0, 88c <alloc_slot+0x88c>
 5a8:	f9000680 	str	x0, [x20, #8]
 5ac:	f9400000 	ldr	x0, [x0]
 5b0:	f9000280 	str	x0, [x20]
 5b4:	f9000414 	str	x20, [x0, #8]
 5b8:	f9400680 	ldr	x0, [x20, #8]
 5bc:	f9000014 	str	x20, [x0]
 5c0:	f9402bfc 	ldr	x28, [sp, #80]
 5c4:	52800000 	mov	w0, #0x0                   	// #0
 5c8:	a9446ffa 	ldp	x26, x27, [sp, #64]
 5cc:	17ffff3f 	b	2c8 <alloc_slot+0x2c8>
 5d0:	120006a0 	and	w0, w21, #0x3
 5d4:	7100041f 	cmp	w0, #0x1
 5d8:	54fff521 	b.ne	47c <alloc_slot+0x47c>  // b.any
 5dc:	eb040cbf 	cmp	x5, x4, lsl #3
 5e0:	54fff4e9 	b.ls	47c <alloc_slot+0x47c>  // b.plast
 5e4:	2a1c03e0 	mov	w0, w28
 5e8:	928001fa 	mov	x26, #0xfffffffffffffff0    	// #-16
 5ec:	52800053 	mov	w19, #0x2                   	// #2
 5f0:	d37ff800 	lsl	x0, x0, #1
 5f4:	cb00035a 	sub	x26, x26, x0
 5f8:	91004000 	add	x0, x0, #0x10
 5fc:	8a07035a 	and	x26, x26, x7
 600:	8b00035a 	add	x26, x26, x0
 604:	92800260 	mov	x0, #0xffffffffffffffec    	// #-20
 608:	cb190000 	sub	x0, x0, x25
 60c:	8a070000 	and	x0, x0, x7
 610:	91005339 	add	x25, x25, #0x14
 614:	8b190000 	add	x0, x0, x25
 618:	910042e1 	add	x1, x23, #0x10
 61c:	eb01001f 	cmp	x0, x1
 620:	540001e3 	b.cc	65c <alloc_slot+0x65c>  // b.lo, b.ul, b.last
 624:	eb04081f 	cmp	x0, x4, lsl #2
 628:	54fff423 	b.cc	4ac <alloc_slot+0x4ac>  // b.lo, b.ul, b.last
 62c:	531f7a61 	lsl	w1, w19, #1
 630:	93407c21 	sxtw	x1, w1
 634:	eb03003f 	cmp	x1, x3
 638:	9a80935a 	csel	x26, x26, x0, ls	// ls = plast
 63c:	1a9f9673 	csinc	w19, w19, wzr, ls	// ls = plast
 640:	17ffff9b 	b	4ac <alloc_slot+0x4ac>
 644:	eb0408bf 	cmp	x5, x4, lsl #2
 648:	54fff1a9 	b.ls	47c <alloc_slot+0x47c>  // b.plast
 64c:	d2800060 	mov	x0, #0x3                   	// #3
 650:	52800022 	mov	w2, #0x1                   	// #1
 654:	2a0003f3 	mov	w19, w0
 658:	17ffff8c 	b	488 <alloc_slot+0x488>
 65c:	aa0003fa 	mov	x26, x0
 660:	52800033 	mov	w19, #0x1                   	// #1
 664:	17ffff92 	b	4ac <alloc_slot+0x4ac>
 668:	a9005294 	stp	x20, x20, [x20]
 66c:	f9000ad4 	str	x20, [x22, #16]
 670:	14000075 	b	844 <alloc_slot+0x844>
 674:	910030a1 	add	x1, x5, #0xc
 678:	d344fcb9 	lsr	x25, x5, #4
 67c:	f10240bf 	cmp	x5, #0x90
 680:	540001e9 	b.ls	6bc <alloc_slot+0x6bc>  // b.plast
 684:	91000722 	add	x2, x25, #0x1
 688:	528003d9 	mov	w25, #0x1e                  	// #30
 68c:	5ac01043 	clz	w3, w2
 690:	91000360 	add	x0, x27, #0x0
			690: R_AARCH64_ADD_ABS_LO12_NC	__malloc_size_classes
 694:	4b030339 	sub	w25, w25, w3
 698:	531e7739 	lsl	w25, w25, #2
 69c:	11000724 	add	w4, w25, #0x1
 6a0:	11000b23 	add	w3, w25, #0x2
 6a4:	7864d804 	ldrh	w4, [x0, w4, sxtw #1]
 6a8:	eb04005f 	cmp	x2, x4
 6ac:	1a998079 	csel	w25, w3, w25, hi	// hi = pmore
 6b0:	7879d800 	ldrh	w0, [x0, w25, sxtw #1]
 6b4:	eb00005f 	cmp	x2, x0
 6b8:	1a999739 	cinc	w25, w25, hi	// hi = pmore
 6bc:	2a1903e0 	mov	w0, w25
 6c0:	97fffe50 	bl	0 <alloc_slot>
 6c4:	2a0003e4 	mov	w4, w0
 6c8:	3100041f 	cmn	w0, #0x1
 6cc:	54000a40 	b.eq	814 <alloc_slot+0x814>  // b.none
 6d0:	910002c0 	add	x0, x22, #0x0
			6d0: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 6d4:	9100037b 	add	x27, x27, #0x0
			6d4: R_AARCH64_ADD_ABS_LO12_NC	__malloc_size_classes
 6d8:	8b39cc00 	add	x0, x0, w25, sxtw #3
 6dc:	7879db67 	ldrh	w7, [x27, w25, sxtw #1]
 6e0:	f9402809 	ldr	x9, [x0, #80]
 6e4:	531c6ce7 	lsl	w7, w7, #4
 6e8:	510010e7 	sub	w7, w7, #0x4
 6ec:	f9401121 	ldr	x1, [x9, #32]
 6f0:	93407ce3 	sxtw	x3, w7
 6f4:	f13ffc3f 	cmp	x1, #0xfff
 6f8:	92401020 	and	x0, x1, #0x1f
 6fc:	fa408800 	ccmp	x0, #0x0, #0x0, hi	// hi = pmore
 700:	54000aa0 	b.eq	854 <alloc_slot+0x854>  // b.none
 704:	53062c21 	ubfx	w1, w1, #6, #6
 708:	7861db61 	ldrh	w1, [x27, w1, sxtw #1]
 70c:	d37c3c21 	ubfiz	x1, x1, #4, #16
 710:	f9400922 	ldr	x2, [x9, #16]
 714:	93407c80 	sxtw	x0, w4
 718:	cb030023 	sub	x3, x1, x3
 71c:	d1001026 	sub	x6, x1, #0x4
 720:	91004042 	add	x2, x2, #0x10
 724:	d1001063 	sub	x3, x3, #0x4
 728:	9b010800 	madd	x0, x0, x1, x2
 72c:	8b060006 	add	x6, x0, x6
 730:	385fc005 	ldurb	w5, [x0, #-4]
 734:	35ffd8c5 	cbnz	w5, 24c <alloc_slot+0x24c>
 738:	f1003c7f 	cmp	x3, #0xf
 73c:	54000389 	b.ls	7ac <alloc_slot+0x7ac>  // b.plast
 740:	385fd001 	ldurb	w1, [x0, #-3]
 744:	340008e1 	cbz	w1, 860 <alloc_slot+0x860>
 748:	785fe008 	ldurh	w8, [x0, #-2]
 74c:	11000508 	add	w8, w8, #0x1
 750:	12001d08 	and	w8, w8, #0xff
 754:	d344fc6a 	lsr	x10, x3, #4
 758:	eb28c15f 	cmp	x10, w8, sxtw
 75c:	54000162 	b.cs	788 <alloc_slot+0x788>  // b.hs, b.nlast
 760:	aa431541 	orr	x1, x10, x3, lsr #5
 764:	aa410821 	orr	x1, x1, x1, lsr #2
 768:	aa411021 	orr	x1, x1, x1, lsr #4
 76c:	0a010108 	and	w8, w8, w1
 770:	eb28c15f 	cmp	x10, w8, sxtw
 774:	540000a2 	b.cs	788 <alloc_slot+0x788>  // b.hs, b.nlast
 778:	4b0a0108 	sub	w8, w8, w10
 77c:	51000508 	sub	w8, w8, #0x1
 780:	eb28c15f 	cmp	x10, w8, sxtw
 784:	54ffd643 	b.cc	24c <alloc_slot+0x24c>  // b.lo, b.ul, b.last
 788:	34000128 	cbz	w8, 7ac <alloc_slot+0x7ac>
 78c:	531c6d01 	lsl	w1, w8, #4
 790:	128003e2 	mov	w2, #0xffffffe0            	// #-32
 794:	381fd002 	sturb	w2, [x0, #-3]
 798:	781fe008 	sturh	w8, [x0, #-2]
 79c:	8b21c000 	add	x0, x0, w1, sxtw
 7a0:	381fc01f 	sturb	wzr, [x0, #-4]
 7a4:	f9400922 	ldr	x2, [x9, #16]
 7a8:	91004042 	add	x2, x2, #0x10
 7ac:	cb020001 	sub	x1, x0, x2
 7b0:	cb0000c2 	sub	x2, x6, x0
 7b4:	6b070042 	subs	w2, w2, w7
 7b8:	d344fc21 	lsr	x1, x1, #4
 7bc:	781fe001 	sturh	w1, [x0, #-2]
 7c0:	54000120 	b.eq	7e4 <alloc_slot+0x7e4>  // b.none
 7c4:	4b0203e1 	neg	w1, w2
 7c8:	531b0845 	ubfiz	w5, w2, #5, #3
 7cc:	3821c8df 	strb	wzr, [x6, w1, sxtw]
 7d0:	7100105f 	cmp	w2, #0x4
 7d4:	5400008d 	b.le	7e4 <alloc_slot+0x7e4>
 7d8:	52801405 	mov	w5, #0xa0                  	// #160
 7dc:	381fb0df 	sturb	wzr, [x6, #-5]
 7e0:	b81fc0c2 	stur	w2, [x6, #-4]
 7e4:	0b0400a5 	add	w5, w5, w4
 7e8:	381fd005 	sturb	w5, [x0, #-3]
 7ec:	91003002 	add	x2, x0, #0xc
 7f0:	52800001 	mov	w1, #0x0                   	// #0
 7f4:	f9401283 	ldr	x3, [x20, #32]
 7f8:	92402c63 	and	x3, x3, #0xfff
 7fc:	f9001283 	str	x3, [x20, #32]
 800:	385fd003 	ldurb	w3, [x0, #-3]
 804:	12001063 	and	w3, w3, #0x1f
 808:	321a6463 	orr	w3, w3, #0xffffffc0
 80c:	381fd003 	sturb	w3, [x0, #-3]
 810:	1400001a 	b	878 <alloc_slot+0x878>
 814:	910002d6 	add	x22, x22, #0x0
			814: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 818:	a9007e9f 	stp	xzr, xzr, [x20]
 81c:	a9017e9f 	stp	xzr, xzr, [x20, #16]
 820:	f9400ac0 	ldr	x0, [x22, #16]
 824:	f900129f 	str	xzr, [x20, #32]
 828:	b4fff200 	cbz	x0, 668 <alloc_slot+0x668>
 82c:	f9000680 	str	x0, [x20, #8]
 830:	f9400000 	ldr	x0, [x0]
 834:	f9000280 	str	x0, [x20]
 838:	f9000414 	str	x20, [x0, #8]
 83c:	f9400680 	ldr	x0, [x20, #8]
 840:	f9000014 	str	x20, [x0]
 844:	f9402bfc 	ldr	x28, [sp, #80]
 848:	12800000 	mov	w0, #0xffffffff            	// #-1
 84c:	a9446ffa 	ldp	x26, x27, [sp, #64]
 850:	17fffe9e 	b	2c8 <alloc_slot+0x2c8>
 854:	9274cc21 	and	x1, x1, #0xfffffffffffff000
 858:	d1004021 	sub	x1, x1, #0x10
 85c:	17ffffad 	b	710 <alloc_slot+0x710>
 860:	910002c1 	add	x1, x22, #0x0
			860: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 864:	39403028 	ldrb	w8, [x1, #12]
 868:	17ffffbb 	b	754 <alloc_slot+0x754>
 86c:	11000421 	add	w1, w1, #0x1
 870:	3900005f 	strb	wzr, [x2]
 874:	8b170042 	add	x2, x2, x23
 878:	6b01027f 	cmp	w19, w1
 87c:	54ffff8a 	b.ge	86c <alloc_slot+0x86c>  // b.tcont
 880:	51000663 	sub	w3, w19, #0x1
 884:	2a0303e2 	mov	w2, w3
 888:	17ffff22 	b	510 <alloc_slot+0x510>
 88c:	a9005294 	stp	x20, x20, [x20]
 890:	f8387ad4 	str	x20, [x22, x24, lsl #3]
 894:	17ffff4b 	b	5c0 <alloc_slot+0x5c0>

Disassembly of section .text.__libc_malloc_impl:

0000000000000000 <__libc_malloc_impl>:
   0:	92820021 	mov	x1, #0xffffffffffffeffe    	// #-4098
   4:	a9bb4ffe 	stp	x30, x19, [sp, #-80]!
   8:	f2efffe1 	movk	x1, #0x7fff, lsl #48
   c:	eb01001f 	cmp	x0, x1
  10:	54000948 	b.hi	138 <__libc_malloc_impl+0x138>  // b.pmore
  14:	aa0003f3 	mov	x19, x0
  18:	d29ffd60 	mov	x0, #0xffeb                	// #65515
  1c:	a90157f4 	stp	x20, x21, [sp, #16]
  20:	f2a00020 	movk	x0, #0x1, lsl #16
  24:	a9025ff6 	stp	x22, x23, [sp, #32]
  28:	a90367f8 	stp	x24, x25, [sp, #48]
  2c:	f90023fa 	str	x26, [sp, #64]
  30:	eb00027f 	cmp	x19, x0
  34:	540008c8 	b.hi	14c <__libc_malloc_impl+0x14c>  // b.pmore
  38:	91000e61 	add	x1, x19, #0x3
  3c:	d344fc20 	lsr	x0, x1, #4
  40:	2a0003f4 	mov	w20, w0
  44:	f1027c3f 	cmp	x1, #0x9f
  48:	54000209 	b.ls	88 <__libc_malloc_impl+0x88>  // b.plast
  4c:	91000400 	add	x0, x0, #0x1
  50:	528003d4 	mov	w20, #0x1e                  	// #30
  54:	5ac01002 	clz	w2, w0
  58:	90000001 	adrp	x1, 0 <__libc_malloc_impl>
			58: R_AARCH64_ADR_PREL_PG_HI21	__malloc_size_classes
  5c:	4b020294 	sub	w20, w20, w2
  60:	91000021 	add	x1, x1, #0x0
			60: R_AARCH64_ADD_ABS_LO12_NC	__malloc_size_classes
  64:	531e7694 	lsl	w20, w20, #2
  68:	11000683 	add	w3, w20, #0x1
  6c:	11000a82 	add	w2, w20, #0x2
  70:	7863d823 	ldrh	w3, [x1, w3, sxtw #1]
  74:	eb03001f 	cmp	x0, x3
  78:	1a948054 	csel	w20, w2, w20, hi	// hi = pmore
  7c:	7874d821 	ldrh	w1, [x1, w20, sxtw #1]
  80:	eb01001f 	cmp	x0, x1
  84:	1a949694 	cinc	w20, w20, hi	// hi = pmore
  88:	90000000 	adrp	x0, 0 <__libc>
			88: R_AARCH64_ADR_PREL_PG_HI21	__libc
  8c:	91000000 	add	x0, x0, #0x0
			8c: R_AARCH64_ADD_ABS_LO12_NC	__libc
  90:	90000019 	adrp	x25, 0 <__libc_malloc_impl>
			90: R_AARCH64_ADR_PREL_PG_HI21	__malloc_lock
  94:	39400c00 	ldrb	w0, [x0, #3]
  98:	72001c1f 	tst	w0, #0xff
  9c:	54000e21 	b.ne	260 <__libc_malloc_impl+0x260>  // b.any
  a0:	93407e80 	sxtw	x0, w20
  a4:	90000017 	adrp	x23, 0 <__libc_malloc_impl>
			a4: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
  a8:	91002802 	add	x2, x0, #0xa
  ac:	910002e1 	add	x1, x23, #0x0
			ac: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
  b0:	f8627835 	ldr	x21, [x1, x2, lsl #3]
  b4:	f10002bf 	cmp	x21, #0x0
  b8:	7a430a84 	ccmp	w20, #0x3, #0x4, eq	// eq = none
  bc:	54000e8d 	b.le	28c <__libc_malloc_impl+0x28c>
  c0:	71007e9f 	cmp	w20, #0x1f
  c4:	7a46da84 	ccmp	w20, #0x6, #0x4, le
  c8:	54000200 	b.eq	108 <__libc_malloc_impl+0x108>  // b.none
  cc:	370001f4 	tbnz	w20, #0, 108 <__libc_malloc_impl+0x108>
  d0:	8b000c20 	add	x0, x1, x0, lsl #3
  d4:	f940fc00 	ldr	x0, [x0, #504]
  d8:	b5000180 	cbnz	x0, 108 <__libc_malloc_impl+0x108>
  dc:	32000282 	orr	w2, w20, #0x1
  e0:	93407c40 	sxtw	x0, w2
  e4:	91002803 	add	x3, x0, #0xa
  e8:	8b000c20 	add	x0, x1, x0, lsl #3
  ec:	f8637835 	ldr	x21, [x1, x3, lsl #3]
  f0:	f940fc00 	ldr	x0, [x0, #504]
  f4:	b4000c55 	cbz	x21, 27c <__libc_malloc_impl+0x27c>
  f8:	b9401aa1 	ldr	w1, [x21, #24]
  fc:	34000b81 	cbz	w1, 26c <__libc_malloc_impl+0x26c>
 100:	f100301f 	cmp	x0, #0xc
 104:	54001709 	b.ls	3e4 <__libc_malloc_impl+0x3e4>  // b.plast
 108:	aa1303e1 	mov	x1, x19
 10c:	2a1403e0 	mov	w0, w20
 110:	94000000 	bl	0 <__libc_malloc_impl>
			110: R_AARCH64_CALL26	.text.alloc_slot
 114:	2a0003f6 	mov	w22, w0
 118:	3100041f 	cmn	w0, #0x1
 11c:	54001680 	b.eq	3ec <__libc_malloc_impl+0x3ec>  // b.none
 120:	910002f7 	add	x23, x23, #0x0
			120: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 124:	93407c1a 	sxtw	x26, w0
 128:	8b34cef4 	add	x20, x23, w20, sxtw #3
 12c:	b9400ef8 	ldr	w24, [x23, #12]
 130:	f9402a95 	ldr	x21, [x20, #80]
 134:	14000062 	b	2bc <__libc_malloc_impl+0x2bc>
 138:	94000000 	bl	0 <___errno_location>
			138: R_AARCH64_CALL26	___errno_location
 13c:	52800181 	mov	w1, #0xc                   	// #12
 140:	b9000001 	str	w1, [x0]
 144:	d2800000 	mov	x0, #0x0                   	// #0
 148:	140000a5 	b	3dc <__libc_malloc_impl+0x3dc>
 14c:	d2820260 	mov	x0, #0x1013                	// #4115
 150:	91005278 	add	x24, x19, #0x14
 154:	8b000276 	add	x22, x19, x0
 158:	aa1803e1 	mov	x1, x24
 15c:	d2800005 	mov	x5, #0x0                   	// #0
 160:	12800004 	mov	w4, #0xffffffff            	// #-1
 164:	52800443 	mov	w3, #0x22                  	// #34
 168:	52800062 	mov	w2, #0x3                   	// #3
 16c:	d2800000 	mov	x0, #0x0                   	// #0
 170:	94000000 	bl	0 <__mmap>
			170: R_AARCH64_CALL26	__mmap
 174:	aa0003f4 	mov	x20, x0
 178:	b100041f 	cmn	x0, #0x1
 17c:	540013e0 	b.eq	3f8 <__libc_malloc_impl+0x3f8>  // b.none
 180:	90000000 	adrp	x0, 0 <__libc>
			180: R_AARCH64_ADR_PREL_PG_HI21	__libc
 184:	91000000 	add	x0, x0, #0x0
			184: R_AARCH64_ADD_ABS_LO12_NC	__libc
 188:	90000019 	adrp	x25, 0 <__libc_malloc_impl>
			188: R_AARCH64_ADR_PREL_PG_HI21	__malloc_lock
 18c:	39400c00 	ldrb	w0, [x0, #3]
 190:	72001c1f 	tst	w0, #0xff
 194:	54000341 	b.ne	1fc <__libc_malloc_impl+0x1fc>  // b.any
 198:	90000017 	adrp	x23, 0 <__libc_malloc_impl>
			198: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
 19c:	910002e2 	add	x2, x23, #0x0
			19c: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 1a0:	394ee041 	ldrb	w1, [x2, #952]
 1a4:	11000420 	add	w0, w1, #0x1
 1a8:	12001c00 	and	w0, w0, #0xff
 1ac:	7103fc3f 	cmp	w1, #0xff
 1b0:	540002c0 	b.eq	208 <__libc_malloc_impl+0x208>  // b.none
 1b4:	910002f7 	add	x23, x23, #0x0
			1b4: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 1b8:	390ee2e0 	strb	w0, [x23, #952]
 1bc:	94000000 	bl	0 <__libc_malloc_impl>
			1bc: R_AARCH64_CALL26	__malloc_alloc_meta
 1c0:	aa0003f5 	mov	x21, x0
 1c4:	b4000340 	cbz	x0, 22c <__libc_malloc_impl+0x22c>
 1c8:	f9000ab4 	str	x20, [x21, #16]
 1cc:	9274ced6 	and	x22, x22, #0xfffffffffffff000
 1d0:	f9000295 	str	x21, [x20]
 1d4:	b27b1ac0 	orr	x0, x22, #0xfe0
 1d8:	b9001ebf 	str	wzr, [x21, #28]
 1dc:	d280001a 	mov	x26, #0x0                   	// #0
 1e0:	b9400ee2 	ldr	w2, [x23, #12]
 1e4:	52800016 	mov	w22, #0x0                   	// #0
 1e8:	b9001abf 	str	wzr, [x21, #24]
 1ec:	11000458 	add	w24, w2, #0x1
 1f0:	b9000ef8 	str	w24, [x23, #12]
 1f4:	f90012a0 	str	x0, [x21, #32]
 1f8:	14000031 	b	2bc <__libc_malloc_impl+0x2bc>
 1fc:	91000320 	add	x0, x25, #0x0
			1fc: R_AARCH64_ADD_ABS_LO12_NC	__malloc_lock
 200:	94000000 	bl	0 <__lock>
			200: R_AARCH64_CALL26	__lock
 204:	17ffffe5 	b	198 <__libc_malloc_impl+0x198>
 208:	90000001 	adrp	x1, 0 <__libc_malloc_impl>
			208: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context+0x378
 20c:	910e6042 	add	x2, x2, #0x398
 210:	91000021 	add	x1, x1, #0x0
			210: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context+0x378
 214:	14000002 	b	21c <__libc_malloc_impl+0x21c>
 218:	3800143f 	strb	wzr, [x1], #1
 21c:	eb01005f 	cmp	x2, x1
 220:	54ffffc1 	b.ne	218 <__libc_malloc_impl+0x218>  // b.any
 224:	52800020 	mov	w0, #0x1                   	// #1
 228:	17ffffe3 	b	1b4 <__libc_malloc_impl+0x1b4>
 22c:	b9400321 	ldr	w1, [x25]
			22c: R_AARCH64_LDST32_ABS_LO12_NC	__malloc_lock
 230:	91000320 	add	x0, x25, #0x0
			230: R_AARCH64_ADD_ABS_LO12_NC	__malloc_lock
 234:	37f80121 	tbnz	w1, #31, 258 <__libc_malloc_impl+0x258>
 238:	aa1803e1 	mov	x1, x24
 23c:	aa1403e0 	mov	x0, x20
 240:	94000000 	bl	0 <munmap>
			240: R_AARCH64_CALL26	munmap
 244:	f94023fa 	ldr	x26, [sp, #64]
 248:	a94157f4 	ldp	x20, x21, [sp, #16]
 24c:	a9425ff6 	ldp	x22, x23, [sp, #32]
 250:	a94367f8 	ldp	x24, x25, [sp, #48]
 254:	17ffffbc 	b	144 <__libc_malloc_impl+0x144>
 258:	94000000 	bl	0 <__unlock>
			258: R_AARCH64_CALL26	__unlock
 25c:	17fffff7 	b	238 <__libc_malloc_impl+0x238>
 260:	91000320 	add	x0, x25, #0x0
			260: R_AARCH64_ADD_ABS_LO12_NC	__malloc_lock
 264:	94000000 	bl	0 <__lock>
			264: R_AARCH64_CALL26	__lock
 268:	17ffff8e 	b	a0 <__libc_malloc_impl+0xa0>
 26c:	b9401ea1 	ldr	w1, [x21, #28]
 270:	35fff481 	cbnz	w1, 100 <__libc_malloc_impl+0x100>
 274:	91000c00 	add	x0, x0, #0x3
 278:	17ffffa2 	b	100 <__libc_malloc_impl+0x100>
 27c:	91000c00 	add	x0, x0, #0x3
 280:	f100301f 	cmp	x0, #0xc
 284:	1a828294 	csel	w20, w20, w2, hi	// hi = pmore
 288:	17ffffa0 	b	108 <__libc_malloc_impl+0x108>
 28c:	b4fff3f5 	cbz	x21, 108 <__libc_malloc_impl+0x108>
 290:	b9401aa0 	ldr	w0, [x21, #24]
 294:	4b0003f6 	neg	w22, w0
 298:	6a0002d6 	ands	w22, w22, w0
 29c:	54fff360 	b.eq	108 <__libc_malloc_impl+0x108>  // b.none
 2a0:	910002f7 	add	x23, x23, #0x0
			2a0: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 2a4:	4b160000 	sub	w0, w0, w22
 2a8:	5ac002d6 	rbit	w22, w22
 2ac:	b9001aa0 	str	w0, [x21, #24]
 2b0:	5ac012d6 	clz	w22, w22
 2b4:	b9400ef8 	ldr	w24, [x23, #12]
 2b8:	93407eda 	sxtw	x26, w22
 2bc:	b9400321 	ldr	w1, [x25]
			2bc: R_AARCH64_LDST32_ABS_LO12_NC	__malloc_lock
 2c0:	91000320 	add	x0, x25, #0x0
			2c0: R_AARCH64_ADD_ABS_LO12_NC	__malloc_lock
 2c4:	37f80b01 	tbnz	w1, #31, 424 <__libc_malloc_impl+0x424>
 2c8:	f94012a2 	ldr	x2, [x21, #32]
 2cc:	f13ffc5f 	cmp	x2, #0xfff
 2d0:	92401040 	and	x0, x2, #0x1f
 2d4:	fa408800 	ccmp	x0, #0x0, #0x0, hi	// hi = pmore
 2d8:	54000aa0 	b.eq	42c <__libc_malloc_impl+0x42c>  // b.none
 2dc:	53062c42 	ubfx	w2, w2, #6, #6
 2e0:	90000000 	adrp	x0, 0 <__libc_malloc_impl>
			2e0: R_AARCH64_ADR_PREL_PG_HI21	__malloc_size_classes
 2e4:	91000000 	add	x0, x0, #0x0
			2e4: R_AARCH64_ADD_ABS_LO12_NC	__malloc_size_classes
 2e8:	7862d802 	ldrh	w2, [x0, w2, sxtw #1]
 2ec:	d37c3c42 	ubfiz	x2, x2, #4, #16
 2f0:	f9400aa1 	ldr	x1, [x21, #16]
 2f4:	d1001045 	sub	x5, x2, #0x4
 2f8:	cb130043 	sub	x3, x2, x19
 2fc:	91004021 	add	x1, x1, #0x10
 300:	d1001063 	sub	x3, x3, #0x4
 304:	9b1a0440 	madd	x0, x2, x26, x1
 308:	8b050005 	add	x5, x0, x5
 30c:	385fc004 	ldurb	w4, [x0, #-4]
 310:	35000944 	cbnz	w4, 438 <__libc_malloc_impl+0x438>
 314:	f1003c7f 	cmp	x3, #0xf
 318:	540003a9 	b.ls	38c <__libc_malloc_impl+0x38c>  // b.plast
 31c:	385fd006 	ldurb	w6, [x0, #-3]
 320:	12001f02 	and	w2, w24, #0xff
 324:	34000086 	cbz	w6, 334 <__libc_malloc_impl+0x334>
 328:	785fe002 	ldurh	w2, [x0, #-2]
 32c:	11000442 	add	w2, w2, #0x1
 330:	12001c42 	and	w2, w2, #0xff
 334:	d344fc66 	lsr	x6, x3, #4
 338:	eb22c0df 	cmp	x6, w2, sxtw
 33c:	54000162 	b.cs	368 <__libc_malloc_impl+0x368>  // b.hs, b.nlast
 340:	aa4314c3 	orr	x3, x6, x3, lsr #5
 344:	aa430863 	orr	x3, x3, x3, lsr #2
 348:	aa431063 	orr	x3, x3, x3, lsr #4
 34c:	0a030042 	and	w2, w2, w3
 350:	eb22c0df 	cmp	x6, w2, sxtw
 354:	540000a2 	b.cs	368 <__libc_malloc_impl+0x368>  // b.hs, b.nlast
 358:	4b060042 	sub	w2, w2, w6
 35c:	51000442 	sub	w2, w2, #0x1
 360:	eb22c0df 	cmp	x6, w2, sxtw
 364:	540006a3 	b.cc	438 <__libc_malloc_impl+0x438>  // b.lo, b.ul, b.last
 368:	34000122 	cbz	w2, 38c <__libc_malloc_impl+0x38c>
 36c:	531c6c41 	lsl	w1, w2, #4
 370:	128003e3 	mov	w3, #0xffffffe0            	// #-32
 374:	381fd003 	sturb	w3, [x0, #-3]
 378:	781fe002 	sturh	w2, [x0, #-2]
 37c:	8b21c000 	add	x0, x0, w1, sxtw
 380:	381fc01f 	sturb	wzr, [x0, #-4]
 384:	f9400aa1 	ldr	x1, [x21, #16]
 388:	91004021 	add	x1, x1, #0x10
 38c:	cb010001 	sub	x1, x0, x1
 390:	cb0000a2 	sub	x2, x5, x0
 394:	6b130042 	subs	w2, w2, w19
 398:	d344fc21 	lsr	x1, x1, #4
 39c:	781fe001 	sturh	w1, [x0, #-2]
 3a0:	54000120 	b.eq	3c4 <__libc_malloc_impl+0x3c4>  // b.none
 3a4:	4b0203e1 	neg	w1, w2
 3a8:	531b0844 	ubfiz	w4, w2, #5, #3
 3ac:	3821c8bf 	strb	wzr, [x5, w1, sxtw]
 3b0:	7100105f 	cmp	w2, #0x4
 3b4:	5400008d 	b.le	3c4 <__libc_malloc_impl+0x3c4>
 3b8:	52801404 	mov	w4, #0xa0                  	// #160
 3bc:	381fb0bf 	sturb	wzr, [x5, #-5]
 3c0:	b81fc0a2 	stur	w2, [x5, #-4]
 3c4:	0b160084 	add	w4, w4, w22
 3c8:	381fd004 	sturb	w4, [x0, #-3]
 3cc:	a94157f4 	ldp	x20, x21, [sp, #16]
 3d0:	a9425ff6 	ldp	x22, x23, [sp, #32]
 3d4:	a94367f8 	ldp	x24, x25, [sp, #48]
 3d8:	f94023fa 	ldr	x26, [sp, #64]
 3dc:	a8c54ffe 	ldp	x30, x19, [sp], #80
 3e0:	d65f03c0 	ret
 3e4:	2a0203f4 	mov	w20, w2
 3e8:	17ffffaa 	b	290 <__libc_malloc_impl+0x290>
 3ec:	b9400321 	ldr	w1, [x25]
			3ec: R_AARCH64_LDST32_ABS_LO12_NC	__malloc_lock
 3f0:	91000320 	add	x0, x25, #0x0
			3f0: R_AARCH64_ADD_ABS_LO12_NC	__malloc_lock
 3f4:	37f800c1 	tbnz	w1, #31, 40c <__libc_malloc_impl+0x40c>
 3f8:	f94023fa 	ldr	x26, [sp, #64]
 3fc:	a94157f4 	ldp	x20, x21, [sp, #16]
 400:	a9425ff6 	ldp	x22, x23, [sp, #32]
 404:	a94367f8 	ldp	x24, x25, [sp, #48]
 408:	17ffff4f 	b	144 <__libc_malloc_impl+0x144>
 40c:	94000000 	bl	0 <__unlock>
			40c: R_AARCH64_CALL26	__unlock
 410:	f94023fa 	ldr	x26, [sp, #64]
 414:	a94157f4 	ldp	x20, x21, [sp, #16]
 418:	a9425ff6 	ldp	x22, x23, [sp, #32]
 41c:	a94367f8 	ldp	x24, x25, [sp, #48]
 420:	17ffff49 	b	144 <__libc_malloc_impl+0x144>
 424:	94000000 	bl	0 <__unlock>
			424: R_AARCH64_CALL26	__unlock
 428:	17ffffa8 	b	2c8 <__libc_malloc_impl+0x2c8>
 42c:	9274cc42 	and	x2, x2, #0xfffffffffffff000
 430:	d1004042 	sub	x2, x2, #0x10
 434:	17ffffaf 	b	2f0 <__libc_malloc_impl+0x2f0>
 438:	d4207d00 	brk	#0x3e8

Disassembly of section .text.__malloc_allzerop:

0000000000000000 <__malloc_allzerop>:
   0:	f2400c1f 	tst	x0, #0xf
   4:	540007e1 	b.ne	100 <__malloc_allzerop+0x100>  // b.any
   8:	385fc002 	ldurb	w2, [x0, #-4]
   c:	385fd001 	ldurb	w1, [x0, #-3]
  10:	785fe003 	ldurh	w3, [x0, #-2]
  14:	12001021 	and	w1, w1, #0x1f
  18:	340000c2 	cbz	w2, 30 <__malloc_allzerop+0x30>
  1c:	35000723 	cbnz	w3, 100 <__malloc_allzerop+0x100>
  20:	b85f8003 	ldur	w3, [x0, #-8]
  24:	529fffe2 	mov	w2, #0xffff                	// #65535
  28:	6b02007f 	cmp	w3, w2
  2c:	540006ad 	b.le	100 <__malloc_allzerop+0x100>
  30:	531c6c64 	lsl	w4, w3, #4
  34:	928001e2 	mov	x2, #0xfffffffffffffff0    	// #-16
  38:	cb24c042 	sub	x2, x2, w4, sxtw
  3c:	8b020004 	add	x4, x0, x2
  40:	f8626800 	ldr	x0, [x0, x2]
  44:	f9400802 	ldr	x2, [x0, #16]
  48:	eb02009f 	cmp	x4, x2
  4c:	540005a1 	b.ne	100 <__malloc_allzerop+0x100>  // b.any
  50:	f9401002 	ldr	x2, [x0, #32]
  54:	12001044 	and	w4, w2, #0x1f
  58:	6b04003f 	cmp	w1, w4
  5c:	5400052c 	b.gt	100 <__malloc_allzerop+0x100>
  60:	b9401804 	ldr	w4, [x0, #24]
  64:	1ac12484 	lsr	w4, w4, w1
  68:	370004c4 	tbnz	w4, #0, 100 <__malloc_allzerop+0x100>
  6c:	b9401c04 	ldr	w4, [x0, #28]
  70:	1ac12484 	lsr	w4, w4, w1
  74:	37000464 	tbnz	w4, #0, 100 <__malloc_allzerop+0x100>
  78:	9274cc00 	and	x0, x0, #0xfffffffffffff000
  7c:	90000004 	adrp	x4, 0 <__malloc_allzerop>
			7c: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
  80:	f9400084 	ldr	x4, [x4]
			80: R_AARCH64_LDST64_ABS_LO12_NC	__malloc_context
  84:	f9400000 	ldr	x0, [x0]
  88:	eb04001f 	cmp	x0, x4
  8c:	540003a1 	b.ne	100 <__malloc_allzerop+0x100>  // b.any
  90:	53062c40 	ubfx	w0, w2, #6, #6
  94:	7100bc1f 	cmp	w0, #0x2f
  98:	540001c8 	b.hi	d0 <__malloc_allzerop+0xd0>  // b.pmore
  9c:	90000004 	adrp	x4, 0 <__malloc_allzerop>
			9c: R_AARCH64_ADR_PREL_PG_HI21	__malloc_size_classes
  a0:	91000084 	add	x4, x4, #0x0
			a0: R_AARCH64_ADD_ABS_LO12_NC	__malloc_size_classes
  a4:	7860d880 	ldrh	w0, [x4, w0, sxtw #1]
  a8:	1b007c21 	mul	w1, w1, w0
  ac:	6b01007f 	cmp	w3, w1
  b0:	5400028b 	b.lt	100 <__malloc_allzerop+0x100>  // b.tstop
  b4:	0b010001 	add	w1, w0, w1
  b8:	6b01007f 	cmp	w3, w1
  bc:	5400022a 	b.ge	100 <__malloc_allzerop+0x100>  // b.tcont
  c0:	f13ffc5f 	cmp	x2, #0xfff
  c4:	54000208 	b.hi	104 <__malloc_allzerop+0x104>  // b.pmore
  c8:	52800000 	mov	w0, #0x0                   	// #0
  cc:	14000007 	b	e8 <__malloc_allzerop+0xe8>
  d0:	927a1440 	and	x0, x2, #0xfc0
  d4:	f13f001f 	cmp	x0, #0xfc0
  d8:	54000141 	b.ne	100 <__malloc_allzerop+0x100>  // b.any
  dc:	f13ffc5f 	cmp	x2, #0xfff
  e0:	54000068 	b.hi	ec <__malloc_allzerop+0xec>  // b.pmore
  e4:	52800020 	mov	w0, #0x1                   	// #1
  e8:	d65f03c0 	ret
  ec:	9274cc42 	and	x2, x2, #0xfffffffffffff000
  f0:	d344fc42 	lsr	x2, x2, #4
  f4:	d1000442 	sub	x2, x2, #0x1
  f8:	eb23c05f 	cmp	x2, w3, sxtw
  fc:	54ffff42 	b.cs	e4 <__malloc_allzerop+0xe4>  // b.hs, b.nlast
 100:	d4207d00 	brk	#0x3e8
 104:	9274cc44 	and	x4, x2, #0xfffffffffffff000
 108:	d344fc81 	lsr	x1, x4, #4
 10c:	d1000421 	sub	x1, x1, #0x1
 110:	eb23c03f 	cmp	x1, w3, sxtw
 114:	54ffff63 	b.cc	100 <__malloc_allzerop+0x100>  // b.lo, b.ul, b.last
 118:	d37c3c01 	ubfiz	x1, x0, #4, #16
 11c:	52800000 	mov	w0, #0x0                   	// #0
 120:	f240105f 	tst	x2, #0x1f
 124:	54fffe21 	b.ne	e8 <__malloc_allzerop+0xe8>  // b.any
 128:	d1004084 	sub	x4, x4, #0x10
 12c:	eb01009f 	cmp	x4, x1
 130:	1a9f27e0 	cset	w0, cc	// cc = lo, ul, last
 134:	17ffffed 	b	e8 <__malloc_allzerop+0xe8>


/Users/alex/code/vinix/third_party/useralloc-libc/build/musl/aarch64/8adbe7fc2d9d74c610f67eb2cab1fe514a0da223a0d1c9f5158aa5374a4282ad/objects/obj/src/malloc/mallocng/malloc.lo:     file format elf64-littleaarch64


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
  7c:	f9002bfc 	str	x28, [sp, #80]
  80:	9000001c 	adrp	x28, 0 <alloc_slot>
			80: R_AARCH64_ADR_PREL_PG_HI21	__malloc_size_classes
  84:	91000380 	add	x0, x28, #0x0
			84: R_AARCH64_ADD_ABS_LO12_NC	__malloc_size_classes
  88:	a9046ffa 	stp	x26, x27, [sp, #64]
  8c:	7875d817 	ldrh	w23, [x0, w21, sxtw #1]
  90:	94000000 	bl	0 <alloc_slot>
			90: R_AARCH64_CALL26	__malloc_alloc_meta
  94:	aa0003f4 	mov	x20, x0
  98:	531c6efb 	lsl	w27, w23, #4
  9c:	d37c3ef7 	ubfiz	x23, x23, #4, #16
  a0:	b4004240 	cbz	x0, 8e8 <alloc_slot+0x8e8>
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
  cc:	8b000025 	add	x5, x1, x0
  d0:	38606822 	ldrb	w2, [x1, x0]
  d4:	d37e1c40 	ubfiz	x0, x2, #2, #8
  d8:	eb00007f 	cmp	x3, x0
  dc:	54001202 	b.cs	31c <alloc_slot+0x31c>  // b.hs, b.nlast
  e0:	394004a2 	ldrb	w2, [x5, #1]
  e4:	d37e1c40 	ubfiz	x0, x2, #2, #8
  e8:	eb03001f 	cmp	x0, x3
  ec:	54001189 	b.ls	31c <alloc_slot+0x31c>  // b.plast
  f0:	394008a2 	ldrb	w2, [x5, #2]
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
 2e8:	3861c802 	ldrb	w2, [x0, w1, sxtw]
 2ec:	14000002 	b	2f4 <alloc_slot+0x2f4>
 2f0:	13017c42 	asr	w2, w2, #1
 2f4:	37000082 	tbnz	w2, #0, 304 <alloc_slot+0x304>
 2f8:	531e7440 	lsl	w0, w2, #2
 2fc:	eb20c07f 	cmp	x3, w0, sxtw
 300:	54ffff83 	b.cc	2f0 <alloc_slot+0x2f0>  // b.lo, b.ul, b.last
 304:	b2404fe1 	mov	x1, #0xfffff               	// #1048575
 308:	14000002 	b	310 <alloc_slot+0x310>
 30c:	13017c42 	asr	w2, w2, #1
 310:	9ba27ee0 	umull	x0, w23, w2
 314:	eb01001f 	cmp	x0, x1
 318:	54ffffa8 	b.hi	30c <alloc_slot+0x30c>  // b.pmore
 31c:	b27c33e0 	mov	x0, #0x1fff0               	// #131056
 320:	d341fc81 	lsr	x1, x4, #1
 324:	9ad70800 	udiv	x0, x0, x23
 328:	f100201f 	cmp	x0, #0x8
 32c:	54000269 	b.ls	378 <alloc_slot+0x378>  // b.plast
 330:	7100205f 	cmp	w2, #0x8
 334:	52800100 	mov	w0, #0x8                   	// #8
 338:	1a80a053 	csel	w19, w2, w0, ge	// ge = tcont
 33c:	51001ea0 	sub	w0, w21, #0x7
 340:	93407e7a 	sxtw	x26, w19
 344:	9bbb7e65 	umull	x5, w19, w27
 348:	910040a2 	add	x2, x5, #0x10
 34c:	eb01005f 	cmp	x2, x1
 350:	54001d49 	b.ls	6f8 <alloc_slot+0x6f8>  // b.plast
 354:	531e7666 	lsl	w6, w19, #2
 358:	93407cc6 	sxtw	x6, w6
 35c:	71007c1f 	cmp	w0, #0x1f
 360:	54000a89 	b.ls	4b0 <alloc_slot+0x4b0>  // b.plast
 364:	910002c0 	add	x0, x22, #0x0
			364: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 368:	52800008 	mov	w8, #0x0                   	// #0
 36c:	52800021 	mov	w1, #0x1                   	// #1
 370:	394ee002 	ldrb	w2, [x0, #952]
 374:	1400001e 	b	3ec <alloc_slot+0x3ec>
 378:	6b00005f 	cmp	w2, w0
 37c:	1a80c053 	csel	w19, w2, w0, gt
 380:	93407e7a 	sxtw	x26, w19
 384:	7100067f 	cmp	w19, #0x1
 388:	540000c1 	b.ne	3a0 <alloc_slot+0x3a0>  // b.any
 38c:	910042e0 	add	x0, x23, #0x10
 390:	eb01001f 	cmp	x0, x1
 394:	54000148 	b.hi	3bc <alloc_slot+0x3bc>  // b.pmore
 398:	d280005a 	mov	x26, #0x2                   	// #2
 39c:	2a1a03f3 	mov	w19, w26
 3a0:	9bba7f65 	umull	x5, w27, w26
 3a4:	910040a0 	add	x0, x5, #0x10
 3a8:	eb01001f 	cmp	x0, x1
 3ac:	54001a69 	b.ls	6f8 <alloc_slot+0x6f8>  // b.plast
 3b0:	531e7666 	lsl	w6, w19, #2
 3b4:	93407cc6 	sxtw	x6, w6
 3b8:	14000003 	b	3c4 <alloc_slot+0x3c4>
 3bc:	aa1703e5 	mov	x5, x23
 3c0:	d2800086 	mov	x6, #0x4                   	// #4
 3c4:	51001ea0 	sub	w0, w21, #0x7
 3c8:	b27c33e1 	mov	x1, #0x1fff0               	// #131056
 3cc:	eb0102ff 	cmp	x23, x1
 3d0:	54fffc29 	b.ls	354 <alloc_slot+0x354>  // b.plast
 3d4:	71007c1f 	cmp	w0, #0x1f
 3d8:	54000429 	b.ls	45c <alloc_slot+0x45c>  // b.plast
 3dc:	910002c0 	add	x0, x22, #0x0
			3dc: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 3e0:	52800028 	mov	w8, #0x1                   	// #1
 3e4:	52800001 	mov	w1, #0x0                   	// #0
 3e8:	394ee002 	ldrb	w2, [x0, #952]
 3ec:	11000440 	add	w0, w2, #0x1
 3f0:	12001c00 	and	w0, w0, #0xff
 3f4:	7103fc5f 	cmp	w2, #0xff
 3f8:	54000620 	b.eq	4bc <alloc_slot+0x4bc>  // b.none
 3fc:	910002c2 	add	x2, x22, #0x0
			3fc: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 400:	d1000487 	sub	x7, x4, #0x1
 404:	390ee040 	strb	w0, [x2, #952]
 408:	37000775 	tbnz	w21, #0, 4f4 <alloc_slot+0x4f4>
 40c:	71007ebf 	cmp	w21, #0x1f
 410:	540006ac 	b.gt	4e4 <alloc_slot+0x4e4>
 414:	110006a0 	add	w0, w21, #0x1
 418:	7100011f 	cmp	w8, #0x0
 41c:	8b20cc40 	add	x0, x2, w0, sxtw #3
 420:	f940fc00 	ldr	x0, [x0, #504]
 424:	8b000063 	add	x3, x3, x0
 428:	fa461062 	ccmp	x3, x6, #0x2, ne	// ne = any
 42c:	540006a2 	b.cs	500 <alloc_slot+0x500>  // b.hs, b.nlast
 430:	120006a0 	and	w0, w21, #0x3
 434:	7100081f 	cmp	w0, #0x2
 438:	54001480 	b.eq	6c8 <alloc_slot+0x6c8>  // b.none
 43c:	eb040cbf 	cmp	x5, x4, lsl #3
 440:	54001488 	b.hi	6d0 <alloc_slot+0x6d0>  // b.pmore
 444:	eb0404bf 	cmp	x5, x4, lsl #1
 448:	540005c9 	b.ls	500 <alloc_slot+0x500>  // b.plast
 44c:	d28000a0 	mov	x0, #0x5                   	// #5
 450:	52800022 	mov	w2, #0x1                   	// #1
 454:	2a0003f3 	mov	w19, w0
 458:	1400002d 	b	50c <alloc_slot+0x50c>
 45c:	910002c1 	add	x1, x22, #0x0
			45c: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 460:	8b20c021 	add	x1, x1, w0, sxtw
 464:	394e6021 	ldrb	w1, [x1, #920]
 468:	71018c3f 	cmp	w1, #0x63
 46c:	1a9f97e1 	cset	w1, hi	// hi = pmore
 470:	1a9f87e8 	cset	w8, ls	// ls = plast
 474:	910002c2 	add	x2, x22, #0x0
			474: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 478:	8b20c040 	add	x0, x2, w0, sxtw
 47c:	394ee042 	ldrb	w2, [x2, #952]
 480:	394de007 	ldrb	w7, [x0, #888]
 484:	34fffb47 	cbz	w7, 3ec <alloc_slot+0x3ec>
 488:	4b070047 	sub	w7, w2, w7
 48c:	710024ff 	cmp	w7, #0x9
 490:	54fffaec 	b.gt	3ec <alloc_slot+0x3ec>
 494:	394e6007 	ldrb	w7, [x0, #920]
 498:	12800d29 	mov	w9, #0xffffff96            	// #-106
 49c:	71018cff 	cmp	w7, #0x63
 4a0:	110004e7 	add	w7, w7, #0x1
 4a4:	1a872127 	csel	w7, w9, w7, cs	// cs = hs, nlast
 4a8:	390e6007 	strb	w7, [x0, #920]
 4ac:	17ffffd0 	b	3ec <alloc_slot+0x3ec>
 4b0:	52800008 	mov	w8, #0x0                   	// #0
 4b4:	52800021 	mov	w1, #0x1                   	// #1
 4b8:	17ffffef 	b	474 <alloc_slot+0x474>
 4bc:	910002c0 	add	x0, x22, #0x0
			4bc: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 4c0:	90000002 	adrp	x2, 0 <alloc_slot>
			4c0: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context+0x378
 4c4:	910e6000 	add	x0, x0, #0x398
 4c8:	91000042 	add	x2, x2, #0x0
			4c8: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context+0x378
 4cc:	14000002 	b	4d4 <alloc_slot+0x4d4>
 4d0:	3800145f 	strb	wzr, [x2], #1
 4d4:	eb00005f 	cmp	x2, x0
 4d8:	54ffffc1 	b.ne	4d0 <alloc_slot+0x4d0>  // b.any
 4dc:	52800020 	mov	w0, #0x1                   	// #1
 4e0:	17ffffc7 	b	3fc <alloc_slot+0x3fc>
 4e4:	7100011f 	cmp	w8, #0x0
 4e8:	fa461062 	ccmp	x3, x6, #0x2, ne	// ne = any
 4ec:	540000a2 	b.cs	500 <alloc_slot+0x500>  // b.hs, b.nlast
 4f0:	17ffffd0 	b	430 <alloc_slot+0x430>
 4f4:	7100011f 	cmp	w8, #0x0
 4f8:	fa461062 	ccmp	x3, x6, #0x2, ne	// ne = any
 4fc:	54000ac3 	b.cc	654 <alloc_slot+0x654>  // b.lo, b.ul, b.last
 500:	71001e7f 	cmp	w19, #0x7
 504:	93407e60 	sxtw	x0, w19
 508:	1a9fc7e2 	cset	w2, le
 50c:	9ba07f60 	umull	x0, w27, w0
 510:	928001fa 	mov	x26, #0xfffffffffffffff0    	// #-16
 514:	52000021 	eor	w1, w1, #0x1
 518:	cb00035a 	sub	x26, x26, x0
 51c:	91004000 	add	x0, x0, #0x10
 520:	8a07035a 	and	x26, x26, x7
 524:	8b00035a 	add	x26, x26, x0
 528:	6a01005f 	tst	w2, w1
 52c:	54000ae1 	b.ne	688 <alloc_slot+0x688>  // b.any
 530:	aa1a03e1 	mov	x1, x26
 534:	d2800005 	mov	x5, #0x0                   	// #0
 538:	12800004 	mov	w4, #0xffffffff            	// #-1
 53c:	52800443 	mov	w3, #0x22                  	// #34
 540:	52800062 	mov	w2, #0x3                   	// #3
 544:	d2800000 	mov	x0, #0x0                   	// #0
 548:	94000000 	bl	0 <__mmap>
			548: R_AARCH64_CALL26	__mmap
 54c:	b100041f 	cmn	x0, #0x1
 550:	54001b40 	b.eq	8b8 <alloc_slot+0x8b8>  // b.none
 554:	d281fe02 	mov	x2, #0xff0                 	// #4080
 558:	d34cff46 	lsr	x6, x26, #12
 55c:	f9401285 	ldr	x5, [x20, #32]
 560:	910002c4 	add	x4, x22, #0x0
			560: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 564:	9ad70841 	udiv	x1, x2, x23
 568:	51000663 	sub	w3, w19, #0x1
 56c:	93407e7a 	sxtw	x26, w19
 570:	b374ccc5 	bfi	x5, x6, #12, #52
 574:	f9001285 	str	x5, [x20, #32]
 578:	51000421 	sub	w1, w1, #0x1
 57c:	b9400c82 	ldr	w2, [x4, #12]
 580:	6b13003f 	cmp	w1, w19
 584:	1a83b021 	csel	w1, w1, w3, lt	// lt = tstop
 588:	11000442 	add	w2, w2, #0x1
 58c:	b9000c82 	str	w2, [x4, #12]
 590:	0aa17c22 	bic	w2, w1, w1, asr #31
 594:	910002d6 	add	x22, x22, #0x0
			594: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 598:	52800041 	mov	w1, #0x2                   	// #2
 59c:	8b180ec4 	add	x4, x22, x24, lsl #3
 5a0:	1ac22025 	lsl	w5, w1, w2
 5a4:	510004a5 	sub	w5, w5, #0x1
 5a8:	1ac32021 	lsl	w1, w1, w3
 5ac:	120016b5 	and	w21, w21, #0x3f
 5b0:	12001063 	and	w3, w3, #0x1f
 5b4:	f940fc86 	ldr	x6, [x4, #504]
 5b8:	321b0063 	orr	w3, w3, #0x20
 5bc:	2a151863 	orr	w3, w3, w21, lsl #6
 5c0:	8b1a00c6 	add	x6, x6, x26
 5c4:	f900fc86 	str	x6, [x4, #504]
 5c8:	b9001a85 	str	w5, [x20, #24]
 5cc:	f9000a80 	str	x0, [x20, #16]
 5d0:	b9401a84 	ldr	w4, [x20, #24]
 5d4:	4b040021 	sub	w1, w1, w4
 5d8:	51000421 	sub	w1, w1, #0x1
 5dc:	b9001e81 	str	w1, [x20, #28]
 5e0:	f9000014 	str	x20, [x0]
 5e4:	f9400a80 	ldr	x0, [x20, #16]
 5e8:	39402001 	ldrb	w1, [x0, #8]
 5ec:	33001041 	bfxil	w1, w2, #0, #5
 5f0:	39002001 	strb	w1, [x0, #8]
 5f4:	79404280 	ldrh	w0, [x20, #32]
 5f8:	f9400682 	ldr	x2, [x20, #8]
 5fc:	12144c00 	and	w0, w0, #0xfffff000
 600:	b9401a81 	ldr	w1, [x20, #24]
 604:	2a000060 	orr	w0, w3, w0
 608:	79004280 	strh	w0, [x20, #32]
 60c:	51000420 	sub	w0, w1, #0x1
 610:	b9001a80 	str	w0, [x20, #24]
 614:	b5ffe1c2 	cbnz	x2, 24c <alloc_slot+0x24c>
 618:	f9400280 	ldr	x0, [x20]
 61c:	b5ffe180 	cbnz	x0, 24c <alloc_slot+0x24c>
 620:	91002b18 	add	x24, x24, #0xa
 624:	f8787ac0 	ldr	x0, [x22, x24, lsl #3]
 628:	b4001740 	cbz	x0, 910 <alloc_slot+0x910>
 62c:	f9000680 	str	x0, [x20, #8]
 630:	f9400000 	ldr	x0, [x0]
 634:	f9000280 	str	x0, [x20]
 638:	f9000414 	str	x20, [x0, #8]
 63c:	f9400680 	ldr	x0, [x20, #8]
 640:	f9000014 	str	x20, [x0]
 644:	f9402bfc 	ldr	x28, [sp, #80]
 648:	52800000 	mov	w0, #0x0                   	// #0
 64c:	a9446ffa 	ldp	x26, x27, [sp, #64]
 650:	17ffff1e 	b	2c8 <alloc_slot+0x2c8>
 654:	120006a0 	and	w0, w21, #0x3
 658:	7100041f 	cmp	w0, #0x1
 65c:	54fff521 	b.ne	500 <alloc_slot+0x500>  // b.any
 660:	eb040cbf 	cmp	x5, x4, lsl #3
 664:	54fff4e9 	b.ls	500 <alloc_slot+0x500>  // b.plast
 668:	2a1b03e0 	mov	w0, w27
 66c:	928001fa 	mov	x26, #0xfffffffffffffff0    	// #-16
 670:	52800053 	mov	w19, #0x2                   	// #2
 674:	d37ff800 	lsl	x0, x0, #1
 678:	cb00035a 	sub	x26, x26, x0
 67c:	91004000 	add	x0, x0, #0x10
 680:	8a07035a 	and	x26, x26, x7
 684:	8b00035a 	add	x26, x26, x0
 688:	92800260 	mov	x0, #0xffffffffffffffec    	// #-20
 68c:	cb190000 	sub	x0, x0, x25
 690:	8a070000 	and	x0, x0, x7
 694:	91005339 	add	x25, x25, #0x14
 698:	8b190000 	add	x0, x0, x25
 69c:	910042e1 	add	x1, x23, #0x10
 6a0:	eb01001f 	cmp	x0, x1
 6a4:	540001e3 	b.cc	6e0 <alloc_slot+0x6e0>  // b.lo, b.ul, b.last
 6a8:	eb04081f 	cmp	x0, x4, lsl #2
 6ac:	54fff423 	b.cc	530 <alloc_slot+0x530>  // b.lo, b.ul, b.last
 6b0:	531f7a61 	lsl	w1, w19, #1
 6b4:	93407c21 	sxtw	x1, w1
 6b8:	eb03003f 	cmp	x1, x3
 6bc:	9a80935a 	csel	x26, x26, x0, ls	// ls = plast
 6c0:	1a9f9673 	csinc	w19, w19, wzr, ls	// ls = plast
 6c4:	17ffff9b 	b	530 <alloc_slot+0x530>
 6c8:	eb0408bf 	cmp	x5, x4, lsl #2
 6cc:	54fff1a9 	b.ls	500 <alloc_slot+0x500>  // b.plast
 6d0:	d2800060 	mov	x0, #0x3                   	// #3
 6d4:	52800022 	mov	w2, #0x1                   	// #1
 6d8:	2a0003f3 	mov	w19, w0
 6dc:	17ffff8c 	b	50c <alloc_slot+0x50c>
 6e0:	aa0003fa 	mov	x26, x0
 6e4:	52800033 	mov	w19, #0x1                   	// #1
 6e8:	17ffff92 	b	530 <alloc_slot+0x530>
 6ec:	a9005294 	stp	x20, x20, [x20]
 6f0:	f9000ad4 	str	x20, [x22, #16]
 6f4:	1400007d 	b	8e8 <alloc_slot+0x8e8>
 6f8:	910030a1 	add	x1, x5, #0xc
 6fc:	d344fcb9 	lsr	x25, x5, #4
 700:	f10240bf 	cmp	x5, #0x90
 704:	540001e9 	b.ls	740 <alloc_slot+0x740>  // b.plast
 708:	91000722 	add	x2, x25, #0x1
 70c:	528003d9 	mov	w25, #0x1e                  	// #30
 710:	5ac01043 	clz	w3, w2
 714:	91000380 	add	x0, x28, #0x0
			714: R_AARCH64_ADD_ABS_LO12_NC	__malloc_size_classes
 718:	4b030339 	sub	w25, w25, w3
 71c:	531e7739 	lsl	w25, w25, #2
 720:	11000724 	add	w4, w25, #0x1
 724:	11000b23 	add	w3, w25, #0x2
 728:	7864d804 	ldrh	w4, [x0, w4, sxtw #1]
 72c:	eb04005f 	cmp	x2, x4
 730:	1a998079 	csel	w25, w3, w25, hi	// hi = pmore
 734:	7879d800 	ldrh	w0, [x0, w25, sxtw #1]
 738:	eb00005f 	cmp	x2, x0
 73c:	1a999739 	cinc	w25, w25, hi	// hi = pmore
 740:	2a1903e0 	mov	w0, w25
 744:	97fffe2f 	bl	0 <alloc_slot>
 748:	2a0003e4 	mov	w4, w0
 74c:	3100041f 	cmn	w0, #0x1
 750:	54000b40 	b.eq	8b8 <alloc_slot+0x8b8>  // b.none
 754:	910002c0 	add	x0, x22, #0x0
			754: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 758:	9100039c 	add	x28, x28, #0x0
			758: R_AARCH64_ADD_ABS_LO12_NC	__malloc_size_classes
 75c:	8b39cc00 	add	x0, x0, w25, sxtw #3
 760:	7879db87 	ldrh	w7, [x28, w25, sxtw #1]
 764:	f9402809 	ldr	x9, [x0, #80]
 768:	531c6ce7 	lsl	w7, w7, #4
 76c:	510010e7 	sub	w7, w7, #0x4
 770:	f9401121 	ldr	x1, [x9, #32]
 774:	93407ce3 	sxtw	x3, w7
 778:	f13ffc3f 	cmp	x1, #0xfff
 77c:	92401020 	and	x0, x1, #0x1f
 780:	fa408800 	ccmp	x0, #0x0, #0x0, hi	// hi = pmore
 784:	54000ba0 	b.eq	8f8 <alloc_slot+0x8f8>  // b.none
 788:	53062c21 	ubfx	w1, w1, #6, #6
 78c:	7861db81 	ldrh	w1, [x28, w1, sxtw #1]
 790:	d37c3c21 	ubfiz	x1, x1, #4, #16
 794:	f9400922 	ldr	x2, [x9, #16]
 798:	93407c80 	sxtw	x0, w4
 79c:	cb030023 	sub	x3, x1, x3
 7a0:	d1001026 	sub	x6, x1, #0x4
 7a4:	91004042 	add	x2, x2, #0x10
 7a8:	d1001063 	sub	x3, x3, #0x4
 7ac:	9b010800 	madd	x0, x0, x1, x2
 7b0:	8b060006 	add	x6, x0, x6
 7b4:	385fc005 	ldurb	w5, [x0, #-4]
 7b8:	35ffd4a5 	cbnz	w5, 24c <alloc_slot+0x24c>
 7bc:	f1003c7f 	cmp	x3, #0xf
 7c0:	54000389 	b.ls	830 <alloc_slot+0x830>  // b.plast
 7c4:	385fd001 	ldurb	w1, [x0, #-3]
 7c8:	340009e1 	cbz	w1, 904 <alloc_slot+0x904>
 7cc:	785fe008 	ldurh	w8, [x0, #-2]
 7d0:	11000508 	add	w8, w8, #0x1
 7d4:	12001d08 	and	w8, w8, #0xff
 7d8:	d344fc6a 	lsr	x10, x3, #4
 7dc:	eb28c15f 	cmp	x10, w8, sxtw
 7e0:	54000162 	b.cs	80c <alloc_slot+0x80c>  // b.hs, b.nlast
 7e4:	aa431541 	orr	x1, x10, x3, lsr #5
 7e8:	aa410821 	orr	x1, x1, x1, lsr #2
 7ec:	aa411021 	orr	x1, x1, x1, lsr #4
 7f0:	0a010108 	and	w8, w8, w1
 7f4:	eb28c15f 	cmp	x10, w8, sxtw
 7f8:	540000a2 	b.cs	80c <alloc_slot+0x80c>  // b.hs, b.nlast
 7fc:	4b0a0108 	sub	w8, w8, w10
 800:	51000508 	sub	w8, w8, #0x1
 804:	eb28c15f 	cmp	x10, w8, sxtw
 808:	54ffd223 	b.cc	24c <alloc_slot+0x24c>  // b.lo, b.ul, b.last
 80c:	34000128 	cbz	w8, 830 <alloc_slot+0x830>
 810:	531c6d01 	lsl	w1, w8, #4
 814:	128003e2 	mov	w2, #0xffffffe0            	// #-32
 818:	381fd002 	sturb	w2, [x0, #-3]
 81c:	781fe008 	sturh	w8, [x0, #-2]
 820:	8b21c000 	add	x0, x0, w1, sxtw
 824:	381fc01f 	sturb	wzr, [x0, #-4]
 828:	f9400922 	ldr	x2, [x9, #16]
 82c:	91004042 	add	x2, x2, #0x10
 830:	cb020001 	sub	x1, x0, x2
 834:	cb0000c2 	sub	x2, x6, x0
 838:	6b070042 	subs	w2, w2, w7
 83c:	d344fc21 	lsr	x1, x1, #4
 840:	781fe001 	sturh	w1, [x0, #-2]
 844:	54000120 	b.eq	868 <alloc_slot+0x868>  // b.none
 848:	4b0203e1 	neg	w1, w2
 84c:	531b0845 	ubfiz	w5, w2, #5, #3
 850:	3821c8df 	strb	wzr, [x6, w1, sxtw]
 854:	7100105f 	cmp	w2, #0x4
 858:	5400008d 	b.le	868 <alloc_slot+0x868>
 85c:	52801405 	mov	w5, #0xa0                  	// #160
 860:	381fb0df 	sturb	wzr, [x6, #-5]
 864:	b81fc0c2 	stur	w2, [x6, #-4]
 868:	0b0400a5 	add	w5, w5, w4
 86c:	381fd005 	sturb	w5, [x0, #-3]
 870:	91003002 	add	x2, x0, #0xc
 874:	11000663 	add	w3, w19, #0x1
 878:	f9401284 	ldr	x4, [x20, #32]
 87c:	52800001 	mov	w1, #0x0                   	// #0
 880:	92402c84 	and	x4, x4, #0xfff
 884:	f9001284 	str	x4, [x20, #32]
 888:	385fd004 	ldurb	w4, [x0, #-3]
 88c:	12001084 	and	w4, w4, #0x1f
 890:	321a6484 	orr	w4, w4, #0xffffffc0
 894:	381fd004 	sturb	w4, [x0, #-3]
 898:	11000421 	add	w1, w1, #0x1
 89c:	3900005f 	strb	wzr, [x2]
 8a0:	8b170042 	add	x2, x2, x23
 8a4:	6b03003f 	cmp	w1, w3
 8a8:	54ffff81 	b.ne	898 <alloc_slot+0x898>  // b.any
 8ac:	51000663 	sub	w3, w19, #0x1
 8b0:	2a0303e2 	mov	w2, w3
 8b4:	17ffff38 	b	594 <alloc_slot+0x594>
 8b8:	910002d6 	add	x22, x22, #0x0
			8b8: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 8bc:	a9007e9f 	stp	xzr, xzr, [x20]
 8c0:	a9017e9f 	stp	xzr, xzr, [x20, #16]
 8c4:	f9400ac0 	ldr	x0, [x22, #16]
 8c8:	f900129f 	str	xzr, [x20, #32]
 8cc:	b4fff100 	cbz	x0, 6ec <alloc_slot+0x6ec>
 8d0:	f9000680 	str	x0, [x20, #8]
 8d4:	f9400000 	ldr	x0, [x0]
 8d8:	f9000280 	str	x0, [x20]
 8dc:	f9000414 	str	x20, [x0, #8]
 8e0:	f9400680 	ldr	x0, [x20, #8]
 8e4:	f9000014 	str	x20, [x0]
 8e8:	f9402bfc 	ldr	x28, [sp, #80]
 8ec:	12800000 	mov	w0, #0xffffffff            	// #-1
 8f0:	a9446ffa 	ldp	x26, x27, [sp, #64]
 8f4:	17fffe75 	b	2c8 <alloc_slot+0x2c8>
 8f8:	9274cc21 	and	x1, x1, #0xfffffffffffff000
 8fc:	d1004021 	sub	x1, x1, #0x10
 900:	17ffffa5 	b	794 <alloc_slot+0x794>
 904:	910002c1 	add	x1, x22, #0x0
			904: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 908:	39403028 	ldrb	w8, [x1, #12]
 90c:	17ffffb3 	b	7d8 <alloc_slot+0x7d8>
 910:	a9005294 	stp	x20, x20, [x20]
 914:	f8387ad4 	str	x20, [x22, x24, lsl #3]
 918:	17ffff4b 	b	644 <alloc_slot+0x644>

Disassembly of section .text.__libc_malloc_impl:

0000000000000000 <__libc_malloc_impl>:
   0:	92820021 	mov	x1, #0xffffffffffffeffe    	// #-4098
   4:	a9bb4ffe 	stp	x30, x19, [sp, #-80]!
   8:	f2efffe1 	movk	x1, #0x7fff, lsl #48
   c:	eb01001f 	cmp	x0, x1
  10:	54000688 	b.hi	e0 <__libc_malloc_impl+0xe0>  // b.pmore
  14:	aa0003f3 	mov	x19, x0
  18:	d29ffd60 	mov	x0, #0xffeb                	// #65515
  1c:	a90157f4 	stp	x20, x21, [sp, #16]
  20:	f2a00020 	movk	x0, #0x1, lsl #16
  24:	a9025ff6 	stp	x22, x23, [sp, #32]
  28:	a90367f8 	stp	x24, x25, [sp, #48]
  2c:	f90023fa 	str	x26, [sp, #64]
  30:	eb00027f 	cmp	x19, x0
  34:	54000608 	b.hi	f4 <__libc_malloc_impl+0xf4>  // b.pmore
  38:	91000e60 	add	x0, x19, #0x3
  3c:	d344fc14 	lsr	x20, x0, #4
  40:	f1027c1f 	cmp	x0, #0x9f
  44:	54000209 	b.ls	84 <__libc_malloc_impl+0x84>  // b.plast
  48:	91000681 	add	x1, x20, #0x1
  4c:	528003d4 	mov	w20, #0x1e                  	// #30
  50:	5ac01022 	clz	w2, w1
  54:	90000000 	adrp	x0, 0 <__libc_malloc_impl>
			54: R_AARCH64_ADR_PREL_PG_HI21	__malloc_size_classes
  58:	4b020294 	sub	w20, w20, w2
  5c:	91000000 	add	x0, x0, #0x0
			5c: R_AARCH64_ADD_ABS_LO12_NC	__malloc_size_classes
  60:	531e7694 	lsl	w20, w20, #2
  64:	11000683 	add	w3, w20, #0x1
  68:	11000a82 	add	w2, w20, #0x2
  6c:	7863d803 	ldrh	w3, [x0, w3, sxtw #1]
  70:	eb03003f 	cmp	x1, x3
  74:	1a948054 	csel	w20, w2, w20, hi	// hi = pmore
  78:	7874d800 	ldrh	w0, [x0, w20, sxtw #1]
  7c:	eb00003f 	cmp	x1, x0
  80:	1a949694 	cinc	w20, w20, hi	// hi = pmore
  84:	90000000 	adrp	x0, 0 <__libc>
			84: R_AARCH64_ADR_PREL_PG_HI21	__libc
  88:	91000000 	add	x0, x0, #0x0
			88: R_AARCH64_ADD_ABS_LO12_NC	__libc
  8c:	90000018 	adrp	x24, 0 <__libc_malloc_impl>
			8c: R_AARCH64_ADR_PREL_PG_HI21	__malloc_lock
  90:	39400c00 	ldrb	w0, [x0, #3]
  94:	72001c1f 	tst	w0, #0xff
  98:	54001c01 	b.ne	418 <__libc_malloc_impl+0x418>  // b.any
  9c:	93407e95 	sxtw	x21, w20
  a0:	90000019 	adrp	x25, 0 <__libc_malloc_impl>
			a0: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
  a4:	91002aa0 	add	x0, x21, #0xa
  a8:	91000322 	add	x2, x25, #0x0
			a8: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
  ac:	f8607856 	ldr	x22, [x2, x0, lsl #3]
  b0:	b4001bb6 	cbz	x22, 424 <__libc_malloc_impl+0x424>
  b4:	b9401ac0 	ldr	w0, [x22, #24]
  b8:	4b0003e1 	neg	w1, w0
  bc:	6a000021 	ands	w1, w1, w0
  c0:	54001b20 	b.eq	424 <__libc_malloc_impl+0x424>  // b.none
  c4:	5ac00034 	rbit	w20, w1
  c8:	4b010000 	sub	w0, w0, w1
  cc:	5ac01294 	clz	w20, w20
  d0:	b9400c57 	ldr	w23, [x2, #12]
  d4:	b9001ac0 	str	w0, [x22, #24]
  d8:	93407e9a 	sxtw	x26, w20
  dc:	1400004f 	b	218 <__libc_malloc_impl+0x218>
  e0:	94000000 	bl	0 <___errno_location>
			e0: R_AARCH64_CALL26	___errno_location
  e4:	52800181 	mov	w1, #0xc                   	// #12
  e8:	b9000001 	str	w1, [x0]
  ec:	d2800000 	mov	x0, #0x0                   	// #0
  f0:	14000092 	b	338 <__libc_malloc_impl+0x338>
  f4:	d2820260 	mov	x0, #0x1013                	// #4115
  f8:	8b000275 	add	x21, x19, x0
  fc:	91005277 	add	x23, x19, #0x14
 100:	d34cfeb5 	lsr	x21, x21, #12
 104:	d10082a0 	sub	x0, x21, #0x20
 108:	f107801f 	cmp	x0, #0x1e0
 10c:	54000368 	b.hi	178 <__libc_malloc_impl+0x178>  // b.pmore
 110:	52800014 	mov	w20, #0x0                   	// #0
 114:	d2800401 	mov	x1, #0x20                  	// #32
 118:	eb0102bf 	cmp	x21, x1
 11c:	54000089 	b.ls	12c <__libc_malloc_impl+0x12c>  // b.plast
 120:	11000694 	add	w20, w20, #0x1
 124:	d37ff821 	lsl	x1, x1, #1
 128:	17fffffc 	b	118 <__libc_malloc_impl+0x118>
 12c:	90000000 	adrp	x0, 0 <__libc>
			12c: R_AARCH64_ADR_PREL_PG_HI21	__libc
 130:	91000000 	add	x0, x0, #0x0
			130: R_AARCH64_ADD_ABS_LO12_NC	__libc
 134:	90000018 	adrp	x24, 0 <__libc_malloc_impl>
			134: R_AARCH64_ADR_PREL_PG_HI21	__malloc_lock
 138:	39400c00 	ldrb	w0, [x0, #3]
 13c:	72001c1f 	tst	w0, #0xff
 140:	54001001 	b.ne	340 <__libc_malloc_impl+0x340>  // b.any
 144:	93407e94 	sxtw	x20, w20
 148:	90000019 	adrp	x25, 0 <__libc_malloc_impl>
			148: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
 14c:	9100ea94 	add	x20, x20, #0x3a
 150:	91000321 	add	x1, x25, #0x0
			150: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 154:	f8747836 	ldr	x22, [x1, x20, lsl #3]
 158:	b40000b6 	cbz	x22, 16c <__libc_malloc_impl+0x16c>
 15c:	f94012c0 	ldr	x0, [x22, #32]
 160:	9274cc00 	and	x0, x0, #0xfffffffffffff000
 164:	eb17001f 	cmp	x0, x23
 168:	54000f22 	b.cs	34c <__libc_malloc_impl+0x34c>  // b.hs, b.nlast
 16c:	b9400301 	ldr	w1, [x24]
			16c: R_AARCH64_LDST32_ABS_LO12_NC	__malloc_lock
 170:	91000300 	add	x0, x24, #0x0
			170: R_AARCH64_ADD_ABS_LO12_NC	__malloc_lock
 174:	37f811c1 	tbnz	w1, #31, 3ac <__libc_malloc_impl+0x3ac>
 178:	aa1703e1 	mov	x1, x23
 17c:	d2800005 	mov	x5, #0x0                   	// #0
 180:	12800004 	mov	w4, #0xffffffff            	// #-1
 184:	52800443 	mov	w3, #0x22                  	// #34
 188:	52800062 	mov	w2, #0x3                   	// #3
 18c:	d2800000 	mov	x0, #0x0                   	// #0
 190:	94000000 	bl	0 <__mmap>
			190: R_AARCH64_CALL26	__mmap
 194:	aa0003f4 	mov	x20, x0
 198:	b100041f 	cmn	x0, #0x1
 19c:	54001620 	b.eq	460 <__libc_malloc_impl+0x460>  // b.none
 1a0:	90000000 	adrp	x0, 0 <__libc>
			1a0: R_AARCH64_ADR_PREL_PG_HI21	__libc
 1a4:	91000000 	add	x0, x0, #0x0
			1a4: R_AARCH64_ADD_ABS_LO12_NC	__libc
 1a8:	90000018 	adrp	x24, 0 <__libc_malloc_impl>
			1a8: R_AARCH64_ADR_PREL_PG_HI21	__malloc_lock
 1ac:	39400c00 	ldrb	w0, [x0, #3]
 1b0:	72001c1f 	tst	w0, #0xff
 1b4:	54001001 	b.ne	3b4 <__libc_malloc_impl+0x3b4>  // b.any
 1b8:	90000019 	adrp	x25, 0 <__libc_malloc_impl>
			1b8: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
 1bc:	91000322 	add	x2, x25, #0x0
			1bc: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 1c0:	394ee041 	ldrb	w1, [x2, #952]
 1c4:	11000420 	add	w0, w1, #0x1
 1c8:	12001c00 	and	w0, w0, #0xff
 1cc:	7103fc3f 	cmp	w1, #0xff
 1d0:	54000f80 	b.eq	3c0 <__libc_malloc_impl+0x3c0>  // b.none
 1d4:	91000339 	add	x25, x25, #0x0
			1d4: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 1d8:	390ee320 	strb	w0, [x25, #952]
 1dc:	94000000 	bl	0 <__libc_malloc_impl>
			1dc: R_AARCH64_CALL26	__malloc_alloc_meta
 1e0:	aa0003f6 	mov	x22, x0
 1e4:	b4001000 	cbz	x0, 3e4 <__libc_malloc_impl+0x3e4>
 1e8:	f9000814 	str	x20, [x0, #16]
 1ec:	d374ceb5 	lsl	x21, x21, #12
 1f0:	f9000280 	str	x0, [x20]
 1f4:	b27b1ab5 	orr	x21, x21, #0xfe0
 1f8:	b9001c1f 	str	wzr, [x0, #28]
 1fc:	d280001a 	mov	x26, #0x0                   	// #0
 200:	b9400f21 	ldr	w1, [x25, #12]
 204:	52800014 	mov	w20, #0x0                   	// #0
 208:	b900181f 	str	wzr, [x0, #24]
 20c:	11000437 	add	w23, w1, #0x1
 210:	b9000f37 	str	w23, [x25, #12]
 214:	f9001015 	str	x21, [x0, #32]
 218:	b9400301 	ldr	w1, [x24]
			218: R_AARCH64_LDST32_ABS_LO12_NC	__malloc_lock
 21c:	91000300 	add	x0, x24, #0x0
			21c: R_AARCH64_ADD_ABS_LO12_NC	__malloc_lock
 220:	37f81361 	tbnz	w1, #31, 48c <__libc_malloc_impl+0x48c>
 224:	f94012c1 	ldr	x1, [x22, #32]
 228:	f13ffc3f 	cmp	x1, #0xfff
 22c:	92401020 	and	x0, x1, #0x1f
 230:	fa408800 	ccmp	x0, #0x0, #0x0, hi	// hi = pmore
 234:	54001300 	b.eq	494 <__libc_malloc_impl+0x494>  // b.none
 238:	53062c21 	ubfx	w1, w1, #6, #6
 23c:	90000000 	adrp	x0, 0 <__libc_malloc_impl>
			23c: R_AARCH64_ADR_PREL_PG_HI21	__malloc_size_classes
 240:	91000000 	add	x0, x0, #0x0
			240: R_AARCH64_ADD_ABS_LO12_NC	__malloc_size_classes
 244:	7861d801 	ldrh	w1, [x0, w1, sxtw #1]
 248:	d37c3c21 	ubfiz	x1, x1, #4, #16
 24c:	f9400ac2 	ldr	x2, [x22, #16]
 250:	d1001025 	sub	x5, x1, #0x4
 254:	cb130023 	sub	x3, x1, x19
 258:	91004042 	add	x2, x2, #0x10
 25c:	d1001063 	sub	x3, x3, #0x4
 260:	9b1a0820 	madd	x0, x1, x26, x2
 264:	8b050005 	add	x5, x0, x5
 268:	385fc004 	ldurb	w4, [x0, #-4]
 26c:	350011a4 	cbnz	w4, 4a0 <__libc_malloc_impl+0x4a0>
 270:	f1003c7f 	cmp	x3, #0xf
 274:	540003a9 	b.ls	2e8 <__libc_malloc_impl+0x2e8>  // b.plast
 278:	385fd006 	ldurb	w6, [x0, #-3]
 27c:	12001ee1 	and	w1, w23, #0xff
 280:	34000086 	cbz	w6, 290 <__libc_malloc_impl+0x290>
 284:	785fe001 	ldurh	w1, [x0, #-2]
 288:	11000421 	add	w1, w1, #0x1
 28c:	12001c21 	and	w1, w1, #0xff
 290:	d344fc66 	lsr	x6, x3, #4
 294:	eb21c0df 	cmp	x6, w1, sxtw
 298:	54000162 	b.cs	2c4 <__libc_malloc_impl+0x2c4>  // b.hs, b.nlast
 29c:	aa4314c3 	orr	x3, x6, x3, lsr #5
 2a0:	aa430863 	orr	x3, x3, x3, lsr #2
 2a4:	aa431063 	orr	x3, x3, x3, lsr #4
 2a8:	0a030021 	and	w1, w1, w3
 2ac:	eb21c0df 	cmp	x6, w1, sxtw
 2b0:	540000a2 	b.cs	2c4 <__libc_malloc_impl+0x2c4>  // b.hs, b.nlast
 2b4:	4b060021 	sub	w1, w1, w6
 2b8:	51000421 	sub	w1, w1, #0x1
 2bc:	eb21c0df 	cmp	x6, w1, sxtw
 2c0:	54000f03 	b.cc	4a0 <__libc_malloc_impl+0x4a0>  // b.lo, b.ul, b.last
 2c4:	34000121 	cbz	w1, 2e8 <__libc_malloc_impl+0x2e8>
 2c8:	531c6c22 	lsl	w2, w1, #4
 2cc:	128003e3 	mov	w3, #0xffffffe0            	// #-32
 2d0:	381fd003 	sturb	w3, [x0, #-3]
 2d4:	781fe001 	sturh	w1, [x0, #-2]
 2d8:	8b22c000 	add	x0, x0, w2, sxtw
 2dc:	381fc01f 	sturb	wzr, [x0, #-4]
 2e0:	f9400ac2 	ldr	x2, [x22, #16]
 2e4:	91004042 	add	x2, x2, #0x10
 2e8:	cb020002 	sub	x2, x0, x2
 2ec:	cb0000a1 	sub	x1, x5, x0
 2f0:	6b130021 	subs	w1, w1, w19
 2f4:	d344fc42 	lsr	x2, x2, #4
 2f8:	781fe002 	sturh	w2, [x0, #-2]
 2fc:	54000120 	b.eq	320 <__libc_malloc_impl+0x320>  // b.none
 300:	4b0103e2 	neg	w2, w1
 304:	531b0824 	ubfiz	w4, w1, #5, #3
 308:	3822c8bf 	strb	wzr, [x5, w2, sxtw]
 30c:	7100103f 	cmp	w1, #0x4
 310:	5400008d 	b.le	320 <__libc_malloc_impl+0x320>
 314:	52801404 	mov	w4, #0xa0                  	// #160
 318:	381fb0bf 	sturb	wzr, [x5, #-5]
 31c:	b81fc0a1 	stur	w1, [x5, #-4]
 320:	0b140084 	add	w4, w4, w20
 324:	381fd004 	sturb	w4, [x0, #-3]
 328:	a94157f4 	ldp	x20, x21, [sp, #16]
 32c:	a9425ff6 	ldp	x22, x23, [sp, #32]
 330:	a94367f8 	ldp	x24, x25, [sp, #48]
 334:	f94023fa 	ldr	x26, [sp, #64]
 338:	a8c54ffe 	ldp	x30, x19, [sp], #80
 33c:	d65f03c0 	ret
 340:	91000300 	add	x0, x24, #0x0
			340: R_AARCH64_ADD_ABS_LO12_NC	__malloc_lock
 344:	94000000 	bl	0 <__lock>
			344: R_AARCH64_CALL26	__lock
 348:	17ffff7f 	b	144 <__libc_malloc_impl+0x144>
 34c:	f834783f 	str	xzr, [x1, x20, lsl #3]
 350:	b9001edf 	str	wzr, [x22, #28]
 354:	394ee022 	ldrb	w2, [x1, #952]
 358:	11000440 	add	w0, w2, #0x1
 35c:	12001c00 	and	w0, w0, #0xff
 360:	7103fc5f 	cmp	w2, #0xff
 364:	54000120 	b.eq	388 <__libc_malloc_impl+0x388>  // b.none
 368:	91000339 	add	x25, x25, #0x0
			368: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 36c:	d280001a 	mov	x26, #0x0                   	// #0
 370:	52800014 	mov	w20, #0x0                   	// #0
 374:	b9400f21 	ldr	w1, [x25, #12]
 378:	390ee320 	strb	w0, [x25, #952]
 37c:	11000437 	add	w23, w1, #0x1
 380:	b9000f37 	str	w23, [x25, #12]
 384:	17ffffa5 	b	218 <__libc_malloc_impl+0x218>
 388:	90000000 	adrp	x0, 0 <__libc_malloc_impl>
			388: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context+0x378
 38c:	910e6021 	add	x1, x1, #0x398
 390:	91000000 	add	x0, x0, #0x0
			390: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context+0x378
 394:	14000002 	b	39c <__libc_malloc_impl+0x39c>
 398:	3800141f 	strb	wzr, [x0], #1
 39c:	eb00003f 	cmp	x1, x0
 3a0:	54ffffc1 	b.ne	398 <__libc_malloc_impl+0x398>  // b.any
 3a4:	52800020 	mov	w0, #0x1                   	// #1
 3a8:	17fffff0 	b	368 <__libc_malloc_impl+0x368>
 3ac:	94000000 	bl	0 <__unlock>
			3ac: R_AARCH64_CALL26	__unlock
 3b0:	17ffff72 	b	178 <__libc_malloc_impl+0x178>
 3b4:	91000300 	add	x0, x24, #0x0
			3b4: R_AARCH64_ADD_ABS_LO12_NC	__malloc_lock
 3b8:	94000000 	bl	0 <__lock>
			3b8: R_AARCH64_CALL26	__lock
 3bc:	17ffff7f 	b	1b8 <__libc_malloc_impl+0x1b8>
 3c0:	90000001 	adrp	x1, 0 <__libc_malloc_impl>
			3c0: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context+0x378
 3c4:	910e6042 	add	x2, x2, #0x398
 3c8:	91000021 	add	x1, x1, #0x0
			3c8: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context+0x378
 3cc:	14000002 	b	3d4 <__libc_malloc_impl+0x3d4>
 3d0:	3800143f 	strb	wzr, [x1], #1
 3d4:	eb01005f 	cmp	x2, x1
 3d8:	54ffffc1 	b.ne	3d0 <__libc_malloc_impl+0x3d0>  // b.any
 3dc:	52800020 	mov	w0, #0x1                   	// #1
 3e0:	17ffff7d 	b	1d4 <__libc_malloc_impl+0x1d4>
 3e4:	b9400301 	ldr	w1, [x24]
			3e4: R_AARCH64_LDST32_ABS_LO12_NC	__malloc_lock
 3e8:	91000300 	add	x0, x24, #0x0
			3e8: R_AARCH64_ADD_ABS_LO12_NC	__malloc_lock
 3ec:	37f80121 	tbnz	w1, #31, 410 <__libc_malloc_impl+0x410>
 3f0:	aa1703e1 	mov	x1, x23
 3f4:	aa1403e0 	mov	x0, x20
 3f8:	94000000 	bl	0 <munmap>
			3f8: R_AARCH64_CALL26	munmap
 3fc:	f94023fa 	ldr	x26, [sp, #64]
 400:	a94157f4 	ldp	x20, x21, [sp, #16]
 404:	a9425ff6 	ldp	x22, x23, [sp, #32]
 408:	a94367f8 	ldp	x24, x25, [sp, #48]
 40c:	17ffff38 	b	ec <__libc_malloc_impl+0xec>
 410:	94000000 	bl	0 <__unlock>
			410: R_AARCH64_CALL26	__unlock
 414:	17fffff7 	b	3f0 <__libc_malloc_impl+0x3f0>
 418:	91000300 	add	x0, x24, #0x0
			418: R_AARCH64_ADD_ABS_LO12_NC	__malloc_lock
 41c:	94000000 	bl	0 <__lock>
			41c: R_AARCH64_CALL26	__lock
 420:	17ffff1f 	b	9c <__libc_malloc_impl+0x9c>
 424:	2a1403e0 	mov	w0, w20
 428:	aa1303e1 	mov	x1, x19
 42c:	94000000 	bl	0 <__libc_malloc_impl>
			42c: R_AARCH64_CALL26	.text.alloc_slot
 430:	2a0003f4 	mov	w20, w0
 434:	3100041f 	cmn	w0, #0x1
 438:	540000e0 	b.eq	454 <__libc_malloc_impl+0x454>  // b.none
 43c:	91000339 	add	x25, x25, #0x0
			43c: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 440:	91002ab5 	add	x21, x21, #0xa
 444:	93407c1a 	sxtw	x26, w0
 448:	f8757b36 	ldr	x22, [x25, x21, lsl #3]
 44c:	b9400f37 	ldr	w23, [x25, #12]
 450:	17ffff72 	b	218 <__libc_malloc_impl+0x218>
 454:	b9400301 	ldr	w1, [x24]
			454: R_AARCH64_LDST32_ABS_LO12_NC	__malloc_lock
 458:	91000300 	add	x0, x24, #0x0
			458: R_AARCH64_ADD_ABS_LO12_NC	__malloc_lock
 45c:	37f800c1 	tbnz	w1, #31, 474 <__libc_malloc_impl+0x474>
 460:	f94023fa 	ldr	x26, [sp, #64]
 464:	a94157f4 	ldp	x20, x21, [sp, #16]
 468:	a9425ff6 	ldp	x22, x23, [sp, #32]
 46c:	a94367f8 	ldp	x24, x25, [sp, #48]
 470:	17ffff1f 	b	ec <__libc_malloc_impl+0xec>
 474:	94000000 	bl	0 <__unlock>
			474: R_AARCH64_CALL26	__unlock
 478:	f94023fa 	ldr	x26, [sp, #64]
 47c:	a94157f4 	ldp	x20, x21, [sp, #16]
 480:	a9425ff6 	ldp	x22, x23, [sp, #32]
 484:	a94367f8 	ldp	x24, x25, [sp, #48]
 488:	17ffff19 	b	ec <__libc_malloc_impl+0xec>
 48c:	94000000 	bl	0 <__unlock>
			48c: R_AARCH64_CALL26	__unlock
 490:	17ffff65 	b	224 <__libc_malloc_impl+0x224>
 494:	9274cc21 	and	x1, x1, #0xfffffffffffff000
 498:	d1004021 	sub	x1, x1, #0x10
 49c:	17ffff6c 	b	24c <__libc_malloc_impl+0x24c>
 4a0:	d4207d00 	brk	#0x3e8

Disassembly of section .text.__malloc_allzerop:

0000000000000000 <__malloc_allzerop>:
   0:	f2400c1f 	tst	x0, #0xf
   4:	540007a1 	b.ne	f8 <__malloc_allzerop+0xf8>  // b.any
   8:	385fc002 	ldurb	w2, [x0, #-4]
   c:	385fd001 	ldurb	w1, [x0, #-3]
  10:	785fe003 	ldurh	w3, [x0, #-2]
  14:	12001021 	and	w1, w1, #0x1f
  18:	340000c2 	cbz	w2, 30 <__malloc_allzerop+0x30>
  1c:	350006e3 	cbnz	w3, f8 <__malloc_allzerop+0xf8>
  20:	b85f8003 	ldur	w3, [x0, #-8]
  24:	529fffe2 	mov	w2, #0xffff                	// #65535
  28:	6b02007f 	cmp	w3, w2
  2c:	5400066d 	b.le	f8 <__malloc_allzerop+0xf8>
  30:	531c6c64 	lsl	w4, w3, #4
  34:	928001e2 	mov	x2, #0xfffffffffffffff0    	// #-16
  38:	cb24c042 	sub	x2, x2, w4, sxtw
  3c:	8b020004 	add	x4, x0, x2
  40:	f8626800 	ldr	x0, [x0, x2]
  44:	f9400802 	ldr	x2, [x0, #16]
  48:	eb02009f 	cmp	x4, x2
  4c:	54000561 	b.ne	f8 <__malloc_allzerop+0xf8>  // b.any
  50:	f9401002 	ldr	x2, [x0, #32]
  54:	12001044 	and	w4, w2, #0x1f
  58:	6b04003f 	cmp	w1, w4
  5c:	540004ec 	b.gt	f8 <__malloc_allzerop+0xf8>
  60:	b9401804 	ldr	w4, [x0, #24]
  64:	1ac12484 	lsr	w4, w4, w1
  68:	37000484 	tbnz	w4, #0, f8 <__malloc_allzerop+0xf8>
  6c:	b9401c04 	ldr	w4, [x0, #28]
  70:	1ac12484 	lsr	w4, w4, w1
  74:	37000424 	tbnz	w4, #0, f8 <__malloc_allzerop+0xf8>
  78:	9274cc00 	and	x0, x0, #0xfffffffffffff000
  7c:	90000004 	adrp	x4, 0 <__malloc_allzerop>
			7c: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
  80:	f9400084 	ldr	x4, [x4]
			80: R_AARCH64_LDST64_ABS_LO12_NC	__malloc_context
  84:	f9400000 	ldr	x0, [x0]
  88:	eb04001f 	cmp	x0, x4
  8c:	54000361 	b.ne	f8 <__malloc_allzerop+0xf8>  // b.any
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
  b0:	5400024b 	b.lt	f8 <__malloc_allzerop+0xf8>  // b.tstop
  b4:	0b010001 	add	w1, w0, w1
  b8:	6b01007f 	cmp	w3, w1
  bc:	540001ea 	b.ge	f8 <__malloc_allzerop+0xf8>  // b.tcont
  c0:	f13ffc5f 	cmp	x2, #0xfff
  c4:	540001c8 	b.hi	fc <__malloc_allzerop+0xfc>  // b.pmore
  c8:	52800000 	mov	w0, #0x0                   	// #0
  cc:	d65f03c0 	ret
  d0:	927a1440 	and	x0, x2, #0xfc0
  d4:	f13f001f 	cmp	x0, #0xfc0
  d8:	54000101 	b.ne	f8 <__malloc_allzerop+0xf8>  // b.any
  dc:	f13ffc5f 	cmp	x2, #0xfff
  e0:	54ffff49 	b.ls	c8 <__malloc_allzerop+0xc8>  // b.plast
  e4:	9274cc42 	and	x2, x2, #0xfffffffffffff000
  e8:	d344fc42 	lsr	x2, x2, #4
  ec:	d1000442 	sub	x2, x2, #0x1
  f0:	eb23c05f 	cmp	x2, w3, sxtw
  f4:	54fffea2 	b.cs	c8 <__malloc_allzerop+0xc8>  // b.hs, b.nlast
  f8:	d4207d00 	brk	#0x3e8
  fc:	9274cc44 	and	x4, x2, #0xfffffffffffff000
 100:	d344fc81 	lsr	x1, x4, #4
 104:	d1000421 	sub	x1, x1, #0x1
 108:	eb23c03f 	cmp	x1, w3, sxtw
 10c:	54ffff63 	b.cc	f8 <__malloc_allzerop+0xf8>  // b.lo, b.ul, b.last
 110:	d37c3c01 	ubfiz	x1, x0, #4, #16
 114:	52800000 	mov	w0, #0x0                   	// #0
 118:	f240105f 	tst	x2, #0x1f
 11c:	54fffd81 	b.ne	cc <__malloc_allzerop+0xcc>  // b.any
 120:	d1004084 	sub	x4, x4, #0x10
 124:	eb01009f 	cmp	x4, x1
 128:	1a9f27e0 	cset	w0, cc	// cc = lo, ul, last
 12c:	17ffffe8 	b	cc <__malloc_allzerop+0xcc>

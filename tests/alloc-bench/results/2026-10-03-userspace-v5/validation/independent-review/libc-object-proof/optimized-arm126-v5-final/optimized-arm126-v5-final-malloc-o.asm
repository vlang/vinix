
/Users/alex/code/vinix/third_party/useralloc-libc/build/musl/aarch64/8adbe7fc2d9d74c610f67eb2cab1fe514a0da223a0d1c9f5158aa5374a4282ad/objects/obj/src/malloc/mallocng/malloc.o:     file format elf64-littleaarch64


Disassembly of section .text.__malloc_atfork:

0000000000000000 <__malloc_atfork>:
   0:	7100001f 	cmp	w0, #0x0
   4:	540000ab 	b.lt	18 <__malloc_atfork+0x18>  // b.tstop
   8:	90000000 	adrp	x0, 0 <__malloc_atfork>
			8: R_AARCH64_ADR_PREL_PG_HI21	__malloc_lock
   c:	54000160 	b.eq	38 <__malloc_atfork+0x38>  // b.none
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
  38:	b9400000 	ldr	w0, [x0]
			38: R_AARCH64_LDST32_ABS_LO12_NC	__malloc_lock
  3c:	36fffec0 	tbz	w0, #31, 14 <__malloc_atfork+0x14>
  40:	90000000 	adrp	x0, 0 <__malloc_atfork>
			40: R_AARCH64_ADR_PREL_PG_HI21	__malloc_lock
  44:	91000000 	add	x0, x0, #0x0
			44: R_AARCH64_ADD_ABS_LO12_NC	__malloc_lock
  48:	14000000 	b	0 <__unlock>
			48: R_AARCH64_JUMP26	__unlock

Disassembly of section .text.__malloc_alloc_meta:

0000000000000000 <__malloc_alloc_meta>:
   0:	d10143ff 	sub	sp, sp, #0x50
   4:	90000000 	adrp	x0, 0 <__stack_chk_guard>
			4: R_AARCH64_ADR_PREL_PG_HI21	__stack_chk_guard
   8:	91000000 	add	x0, x0, #0x0
			8: R_AARCH64_ADD_ABS_LO12_NC	__stack_chk_guard
   c:	a90257f4 	stp	x20, x21, [sp, #32]
  10:	a9035ff6 	stp	x22, x23, [sp, #48]
  14:	90000016 	adrp	x22, 0 <__malloc_alloc_meta>
			14: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
  18:	910002d4 	add	x20, x22, #0x0
			18: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
  1c:	a9014ffe 	stp	x30, x19, [sp, #16]
  20:	f9400001 	ldr	x1, [x0]
  24:	f90007e1 	str	x1, [sp, #8]
  28:	d2800001 	mov	x1, #0x0                   	// #0
  2c:	b9400a80 	ldr	w0, [x20, #8]
  30:	34000340 	cbz	w0, 98 <__malloc_alloc_meta+0x98>
  34:	f9400a93 	ldr	x19, [x20, #16]
  38:	b4000673 	cbz	x19, 104 <__malloc_alloc_meta+0x104>
  3c:	f9400660 	ldr	x0, [x19, #8]
  40:	eb00027f 	cmp	x19, x0
  44:	54000740 	b.eq	12c <__malloc_alloc_meta+0x12c>  // b.none
  48:	f9400261 	ldr	x1, [x19]
  4c:	f9000420 	str	x0, [x1, #8]
  50:	f9400261 	ldr	x1, [x19]
  54:	f9000001 	str	x1, [x0]
  58:	f9400a80 	ldr	x0, [x20, #16]
  5c:	eb00027f 	cmp	x19, x0
  60:	54000600 	b.eq	120 <__malloc_alloc_meta+0x120>  // b.none
  64:	a9007e7f 	stp	xzr, xzr, [x19]
  68:	90000000 	adrp	x0, 0 <__stack_chk_guard>
			68: R_AARCH64_ADR_PREL_PG_HI21	__stack_chk_guard
  6c:	f94007e2 	ldr	x2, [sp, #8]
  70:	f9400001 	ldr	x1, [x0]
			70: R_AARCH64_LDST64_ABS_LO12_NC	__stack_chk_guard
  74:	eb010042 	subs	x2, x2, x1
  78:	d2800001 	mov	x1, #0x0                   	// #0
  7c:	54001321 	b.ne	2e0 <__malloc_alloc_meta+0x2e0>  // b.any
  80:	a94257f4 	ldp	x20, x21, [sp, #32]
  84:	aa1303e0 	mov	x0, x19
  88:	a9414ffe 	ldp	x30, x19, [sp, #16]
  8c:	a9435ff6 	ldp	x22, x23, [sp, #48]
  90:	910143ff 	add	sp, sp, #0x50
  94:	d65f03c0 	ret
  98:	910003e1 	mov	x1, sp
  9c:	d289cda0 	mov	x0, #0x4e6d                	// #20077
  a0:	f2a838c0 	movk	x0, #0x41c6, lsl #16
  a4:	90000015 	adrp	x21, 0 <__libc>
			a4: R_AARCH64_ADR_PREL_PG_HI21	__libc
  a8:	d2800013 	mov	x19, #0x0                   	// #0
  ac:	910002b5 	add	x21, x21, #0x0
			ac: R_AARCH64_ADD_ABS_LO12_NC	__libc
  b0:	9b007c20 	mul	x0, x1, x0
  b4:	f90003e0 	str	x0, [sp]
  b8:	14000002 	b	c0 <__malloc_alloc_meta+0xc0>
  bc:	91004273 	add	x19, x19, #0x10
  c0:	f94006a1 	ldr	x1, [x21, #8]
  c4:	f8736820 	ldr	x0, [x1, x19]
  c8:	b4000140 	cbz	x0, f0 <__malloc_alloc_meta+0xf0>
  cc:	f100641f 	cmp	x0, #0x19
  d0:	54ffff61 	b.ne	bc <__malloc_alloc_meta+0xbc>  // b.any
  d4:	8b130021 	add	x1, x1, x19
  d8:	d2800102 	mov	x2, #0x8                   	// #8
  dc:	910003e0 	mov	x0, sp
  e0:	f9400421 	ldr	x1, [x1, #8]
  e4:	8b020021 	add	x1, x1, x2
  e8:	94000000 	bl	0 <memcpy>
			e8: R_AARCH64_CALL26	memcpy
  ec:	17fffff4 	b	bc <__malloc_alloc_meta+0xbc>
  f0:	f94003e0 	ldr	x0, [sp]
  f4:	f90002c0 	str	x0, [x22]
			f4: R_AARCH64_LDST64_ABS_LO12_NC	__malloc_context
  f8:	52800020 	mov	w0, #0x1                   	// #1
  fc:	b9000a80 	str	w0, [x20, #8]
 100:	17ffffcd 	b	34 <__malloc_alloc_meta+0x34>
 104:	f9401280 	ldr	x0, [x20, #32]
 108:	b4000160 	cbz	x0, 134 <__malloc_alloc_meta+0x134>
 10c:	f9400e93 	ldr	x19, [x20, #24]
 110:	d1000400 	sub	x0, x0, #0x1
 114:	9100a261 	add	x1, x19, #0x28
 118:	a9018281 	stp	x1, x0, [x20, #24]
 11c:	17ffffd2 	b	64 <__malloc_alloc_meta+0x64>
 120:	f9400660 	ldr	x0, [x19, #8]
 124:	f9000a80 	str	x0, [x20, #16]
 128:	17ffffcf 	b	64 <__malloc_alloc_meta+0x64>
 12c:	f9000a9f 	str	xzr, [x20, #16]
 130:	17ffffcd 	b	64 <__malloc_alloc_meta+0x64>
 134:	90000000 	adrp	x0, 0 <__libc>
			134: R_AARCH64_ADR_PREL_PG_HI21	__libc+0x30
 138:	f90023f8 	str	x24, [sp, #64]
 13c:	d2820002 	mov	x2, #0x1000                	// #4096
 140:	f9401681 	ldr	x1, [x20, #40]
 144:	f9400000 	ldr	x0, [x0]
			144: R_AARCH64_LDST64_ABS_LO12_NC	__libc+0x30
 148:	eb02001f 	cmp	x0, x2
 14c:	9a822018 	csel	x24, x0, x2, cs	// cs = hs, nlast
 150:	b5000981 	cbnz	x1, 280 <__malloc_alloc_meta+0x280>
 154:	f941e295 	ldr	x21, [x20, #960]
 158:	b10006bf 	cmn	x21, #0x1
 15c:	54000180 	b.eq	18c <__malloc_alloc_meta+0x18c>  // b.none
 160:	b40005b5 	cbz	x21, 214 <__malloc_alloc_meta+0x214>
 164:	8b1802b7 	add	x23, x21, x24
 168:	d2801ac8 	mov	x8, #0xd6                  	// #214
 16c:	aa1703e0 	mov	x0, x23
 170:	d4000001 	svc	#0x0
 174:	eb0002ff 	cmp	x23, x0
 178:	54000780 	b.eq	268 <__malloc_alloc_meta+0x268>  // b.none
 17c:	f9401680 	ldr	x0, [x20, #40]
 180:	92800001 	mov	x1, #0xffffffffffffffff    	// #-1
 184:	f901e281 	str	x1, [x20, #960]
 188:	b50007c0 	cbnz	x0, 280 <__malloc_alloc_meta+0x280>
 18c:	f9401a80 	ldr	x0, [x20, #48]
 190:	d2800055 	mov	x21, #0x2                   	// #2
 194:	d2800005 	mov	x5, #0x0                   	// #0
 198:	12800004 	mov	w4, #0xffffffff            	// #-1
 19c:	52800443 	mov	w3, #0x22                  	// #34
 1a0:	52800002 	mov	w2, #0x0                   	// #0
 1a4:	9ac022b5 	lsl	x21, x21, x0
 1a8:	d2800000 	mov	x0, #0x0                   	// #0
 1ac:	9b187ea1 	mul	x1, x21, x24
 1b0:	94000000 	bl	0 <__mmap>
			1b0: R_AARCH64_CALL26	__mmap
 1b4:	b100041f 	cmn	x0, #0x1
 1b8:	540002a0 	b.eq	20c <__malloc_alloc_meta+0x20c>  // b.none
 1bc:	d10006a1 	sub	x1, x21, #0x1
 1c0:	d34cff03 	lsr	x3, x24, #12
 1c4:	f9401a82 	ldr	x2, [x20, #48]
 1c8:	8b180015 	add	x21, x0, x24
 1cc:	9b037c20 	mul	x0, x1, x3
 1d0:	d1000701 	sub	x1, x24, #0x1
 1d4:	91000442 	add	x2, x2, #0x1
 1d8:	a9028a80 	stp	x0, x2, [x20, #40]
 1dc:	f9002695 	str	x21, [x20, #72]
 1e0:	ea0102bf 	tst	x21, x1
 1e4:	54000581 	b.ne	294 <__malloc_alloc_meta+0x294>  // b.any
 1e8:	aa1803e1 	mov	x1, x24
 1ec:	aa1503e0 	mov	x0, x21
 1f0:	52800062 	mov	w2, #0x3                   	// #3
 1f4:	94000000 	bl	0 <mprotect>
			1f4: R_AARCH64_CALL26	mprotect
 1f8:	340004e0 	cbz	w0, 294 <__malloc_alloc_meta+0x294>
 1fc:	94000000 	bl	0 <___errno_location>
			1fc: R_AARCH64_CALL26	___errno_location
 200:	b9400000 	ldr	w0, [x0]
 204:	7100981f 	cmp	w0, #0x26
 208:	54000460 	b.eq	294 <__malloc_alloc_meta+0x294>  // b.none
 20c:	f94023f8 	ldr	x24, [sp, #64]
 210:	17ffff96 	b	68 <__malloc_alloc_meta+0x68>
 214:	d2801ac8 	mov	x8, #0xd6                  	// #214
 218:	d2800000 	mov	x0, #0x0                   	// #0
 21c:	d4000001 	svc	#0x0
 220:	d1000701 	sub	x1, x24, #0x1
 224:	cb0003f7 	neg	x23, x0
 228:	8a0102f7 	and	x23, x23, x1
 22c:	8b0002f7 	add	x23, x23, x0
 230:	f901e297 	str	x23, [x20, #960]
 234:	8b1806f7 	add	x23, x23, x24, lsl #1
 238:	aa1703e0 	mov	x0, x23
 23c:	d4000001 	svc	#0x0
 240:	eb0002ff 	cmp	x23, x0
 244:	54fff9c1 	b.ne	17c <__malloc_alloc_meta+0x17c>  // b.any
 248:	f941e280 	ldr	x0, [x20, #960]
 24c:	aa1803e1 	mov	x1, x24
 250:	cb1802f5 	sub	x21, x23, x24
 254:	d2800005 	mov	x5, #0x0                   	// #0
 258:	12800004 	mov	w4, #0xffffffff            	// #-1
 25c:	52800643 	mov	w3, #0x32                  	// #50
 260:	52800002 	mov	w2, #0x0                   	// #0
 264:	94000000 	bl	0 <__mmap>
			264: R_AARCH64_CALL26	__mmap
 268:	d34cff00 	lsr	x0, x24, #12
 26c:	f9001680 	str	x0, [x20, #40]
 270:	f901e297 	str	x23, [x20, #960]
 274:	14000008 	b	294 <__malloc_alloc_meta+0x294>
 278:	f9001e95 	str	x21, [x20, #56]
 27c:	1400000e 	b	2b4 <__malloc_alloc_meta+0x2b4>
 280:	f9402695 	ldr	x21, [x20, #72]
 284:	d1000700 	sub	x0, x24, #0x1
 288:	ea0002bf 	tst	x21, x0
 28c:	1a9f17e0 	cset	w0, eq	// eq = none
 290:	35fffac0 	cbnz	w0, 1e8 <__malloc_alloc_meta+0x1e8>
 294:	f9401681 	ldr	x1, [x20, #40]
 298:	914006a0 	add	x0, x21, #0x1, lsl #12
 29c:	f9402282 	ldr	x2, [x20, #64]
 2a0:	d1000421 	sub	x1, x1, #0x1
 2a4:	f9001681 	str	x1, [x20, #40]
 2a8:	f9002680 	str	x0, [x20, #72]
 2ac:	b4fffe62 	cbz	x2, 278 <__malloc_alloc_meta+0x278>
 2b0:	f9000455 	str	x21, [x2, #8]
 2b4:	f94002c0 	ldr	x0, [x22]
			2b4: R_AARCH64_LDST64_ABS_LO12_NC	__malloc_context
 2b8:	f9002295 	str	x21, [x20, #64]
 2bc:	f90002a0 	str	x0, [x21]
 2c0:	52800ca2 	mov	w2, #0x65                  	// #101
 2c4:	d2800c80 	mov	x0, #0x64                  	// #100
 2c8:	f9402281 	ldr	x1, [x20, #64]
 2cc:	b9001022 	str	w2, [x1, #16]
 2d0:	f9402293 	ldr	x19, [x20, #64]
 2d4:	f94023f8 	ldr	x24, [sp, #64]
 2d8:	91006273 	add	x19, x19, #0x18
 2dc:	17ffff8e 	b	114 <__malloc_alloc_meta+0x114>
 2e0:	f90023f8 	str	x24, [sp, #64]
 2e4:	94000000 	bl	0 <__stack_chk_fail>
			2e4: R_AARCH64_CALL26	__stack_chk_fail

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
  1c:	910002d6 	add	x22, x22, #0x0
			1c: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
  20:	a90157f4 	stp	x20, x21, [sp, #16]
  24:	aa1803f5 	mov	x21, x24
  28:	f8617ac6 	ldr	x6, [x22, x1, lsl #3]
  2c:	b4000266 	cbz	x6, 78 <alloc_slot+0x78>
  30:	b94018c0 	ldr	w0, [x6, #24]
  34:	35001320 	cbnz	w0, 298 <alloc_slot+0x298>
  38:	b9401cc2 	ldr	w2, [x6, #28]
  3c:	f94004c0 	ldr	x0, [x6, #8]
  40:	35000622 	cbnz	w2, 104 <alloc_slot+0x104>
  44:	eb0000df 	cmp	x6, x0
  48:	540005a0 	b.eq	fc <alloc_slot+0xfc>  // b.none
  4c:	f94000c2 	ldr	x2, [x6]
  50:	f9000440 	str	x0, [x2, #8]
  54:	f94000c2 	ldr	x2, [x6]
  58:	f9000002 	str	x2, [x0]
  5c:	f8617ac0 	ldr	x0, [x22, x1, lsl #3]
  60:	eb0000df 	cmp	x6, x0
  64:	54000460 	b.eq	f0 <alloc_slot+0xf0>  // b.none
  68:	91002b00 	add	x0, x24, #0xa
  6c:	a9007cdf 	stp	xzr, xzr, [x6]
  70:	f8607ac6 	ldr	x6, [x22, x0, lsl #3]
  74:	b50004c6 	cbnz	x6, 10c <alloc_slot+0x10c>
  78:	a9046ffa 	stp	x26, x27, [sp, #64]
  7c:	9000001b 	adrp	x27, 0 <alloc_slot>
			7c: R_AARCH64_ADR_PREL_PG_HI21	__malloc_size_classes
  80:	9100037b 	add	x27, x27, #0x0
			80: R_AARCH64_ADD_ABS_LO12_NC	__malloc_size_classes
  84:	f9002bfc 	str	x28, [sp, #80]
  88:	7875db77 	ldrh	w23, [x27, w21, sxtw #1]
  8c:	94000000 	bl	0 <alloc_slot>
			8c: R_AARCH64_CALL26	__malloc_alloc_meta
  90:	aa0003f4 	mov	x20, x0
  94:	531c6efc 	lsl	w28, w23, #4
  98:	d37c3ef7 	ubfiz	x23, x23, #4, #16
  9c:	b4004040 	cbz	x0, 8a4 <alloc_slot+0x8a4>
  a0:	8b180ec0 	add	x0, x22, x24, lsl #3
  a4:	90000001 	adrp	x1, 0 <__libc>
			a4: R_AARCH64_ADR_PREL_PG_HI21	__libc+0x30
  a8:	f9400024 	ldr	x4, [x1]
			a8: R_AARCH64_LDST64_ABS_LO12_NC	__libc+0x30
  ac:	f940fc03 	ldr	x3, [x0, #504]
  b0:	710022bf 	cmp	w21, #0x8
  b4:	540010ac 	b.gt	2c8 <alloc_slot+0x2c8>
  b8:	8b180700 	add	x0, x24, x24, lsl #1
  bc:	90000001 	adrp	x1, 0 <alloc_slot>
			bc: R_AARCH64_ADR_PREL_PG_HI21	.rodata.small_cnt_tab
  c0:	91000021 	add	x1, x1, #0x0
			c0: R_AARCH64_ADD_ABS_LO12_NC	.rodata.small_cnt_tab
  c4:	8b000025 	add	x5, x1, x0
  c8:	38606822 	ldrb	w2, [x1, x0]
  cc:	d37e1c40 	ubfiz	x0, x2, #2, #8
  d0:	eb00007f 	cmp	x3, x0
  d4:	540011a2 	b.cs	308 <alloc_slot+0x308>  // b.hs, b.nlast
  d8:	394004a2 	ldrb	w2, [x5, #1]
  dc:	d37e1c40 	ubfiz	x0, x2, #2, #8
  e0:	eb03001f 	cmp	x0, x3
  e4:	54001129 	b.ls	308 <alloc_slot+0x308>  // b.plast
  e8:	394008a2 	ldrb	w2, [x5, #2]
  ec:	14000087 	b	308 <alloc_slot+0x308>
  f0:	f94004c0 	ldr	x0, [x6, #8]
  f4:	f8217ac0 	str	x0, [x22, x1, lsl #3]
  f8:	17ffffdc 	b	68 <alloc_slot+0x68>
  fc:	f8217adf 	str	xzr, [x22, x1, lsl #3]
 100:	17ffffda 	b	68 <alloc_slot+0x68>
 104:	aa0003e6 	mov	x6, x0
 108:	f8217ac0 	str	x0, [x22, x1, lsl #3]
 10c:	f94010c1 	ldr	x1, [x6, #32]
 110:	52800040 	mov	w0, #0x2                   	// #2
 114:	b9401cc2 	ldr	w2, [x6, #28]
 118:	d3401023 	ubfx	x3, x1, #0, #5
 11c:	1ac32000 	lsl	w0, w0, w3
 120:	51000400 	sub	w0, w0, #0x1
 124:	6b00005f 	cmp	w2, w0
 128:	54000460 	b.eq	1b4 <alloc_slot+0x1b4>  // b.none
 12c:	f94008c4 	ldr	x4, [x6, #16]
 130:	52800040 	mov	w0, #0x2                   	// #2
 134:	f9400481 	ldr	x1, [x4, #8]
 138:	12001023 	and	w3, w1, #0x1f
 13c:	d3401021 	ubfx	x1, x1, #0, #5
 140:	1ac12000 	lsl	w0, w0, w1
 144:	51000400 	sub	w0, w0, #0x1
 148:	6a02001f 	tst	w0, w2
 14c:	540000e1 	b.ne	168 <alloc_slot+0x168>  // b.any
 150:	f94004c7 	ldr	x7, [x6, #8]
 154:	eb0700df 	cmp	x6, x7
 158:	540003a0 	b.eq	1cc <alloc_slot+0x1cc>  // b.none
 15c:	91002b00 	add	x0, x24, #0xa
 160:	f8207ac7 	str	x7, [x22, x0, lsl #3]
 164:	aa0703e6 	mov	x6, x7
 168:	b94018c0 	ldr	w0, [x6, #24]
 16c:	35000640 	cbnz	w0, 234 <alloc_slot+0x234>
 170:	f94008c0 	ldr	x0, [x6, #16]
 174:	90000001 	adrp	x1, 0 <__libc>
			174: R_AARCH64_ADR_PREL_PG_HI21	__libc
 178:	91000021 	add	x1, x1, #0x0
			178: R_AARCH64_ADD_ABS_LO12_NC	__libc
 17c:	52800047 	mov	w7, #0x2                   	// #2
 180:	910070c4 	add	x4, x6, #0x1c
 184:	f9400400 	ldr	x0, [x0, #8]
 188:	39400c21 	ldrb	w1, [x1, #3]
 18c:	d3401000 	ubfx	x0, x0, #0, #5
 190:	1ac020e7 	lsl	w7, w7, w0
 194:	510004e0 	sub	w0, w7, #0x1
 198:	4b0703e7 	neg	w7, w7
 19c:	72001c3f 	tst	w1, #0xff
 1a0:	54000521 	b.ne	244 <alloc_slot+0x244>  // b.any
 1a4:	b9401cc1 	ldr	w1, [x6, #28]
 1a8:	0a070027 	and	w7, w1, w7
 1ac:	b9001cc7 	str	w7, [x6, #28]
 1b0:	1400002d 	b	264 <alloc_slot+0x264>
 1b4:	362ffda1 	tbz	w1, #5, 168 <alloc_slot+0x168>
 1b8:	91002b00 	add	x0, x24, #0xa
 1bc:	f94004c6 	ldr	x6, [x6, #8]
 1c0:	f8207ac6 	str	x6, [x22, x0, lsl #3]
 1c4:	b9401cc2 	ldr	w2, [x6, #28]
 1c8:	17ffffd9 	b	12c <alloc_slot+0x12c>
 1cc:	f94010e6 	ldr	x6, [x7, #32]
 1d0:	90000000 	adrp	x0, 0 <alloc_slot>
			1d0: R_AARCH64_ADR_PREL_PG_HI21	__malloc_size_classes
 1d4:	91000000 	add	x0, x0, #0x0
			1d4: R_AARCH64_ADD_ABS_LO12_NC	__malloc_size_classes
 1d8:	11000863 	add	w3, w3, #0x2
 1dc:	53062cc1 	ubfx	w1, w6, #6, #6
 1e0:	7861d805 	ldrh	w5, [x0, w1, sxtw #1]
 1e4:	531c6ca5 	lsl	w5, w5, #4
 1e8:	1b057c61 	mul	w1, w3, w5
 1ec:	11004021 	add	w1, w1, #0x10
 1f0:	14000003 	b	1fc <alloc_slot+0x1fc>
 1f4:	11000463 	add	w3, w3, #0x1
 1f8:	2a0203e1 	mov	w1, w2
 1fc:	0b0100a2 	add	w2, w5, w1
 200:	51000440 	sub	w0, w2, #0x1
 204:	4a010000 	eor	w0, w0, w1
 208:	713ffc1f 	cmp	w0, #0xfff
 20c:	54ffff4d 	b.le	1f4 <alloc_slot+0x1f4>
 210:	120010c0 	and	w0, w6, #0x1f
 214:	39402081 	ldrb	w1, [x4, #8]
 218:	11000400 	add	w0, w0, #0x1
 21c:	6b03001f 	cmp	w0, w3
 220:	1a83d000 	csel	w0, w0, w3, le
 224:	51000400 	sub	w0, w0, #0x1
 228:	33001001 	bfxil	w1, w0, #0, #5
 22c:	39002081 	strb	w1, [x4, #8]
 230:	17ffffcd 	b	164 <alloc_slot+0x164>
 234:	a9046ffa 	stp	x26, x27, [sp, #64]
 238:	f9002bfc 	str	x28, [sp, #80]
 23c:	d4207d00 	brk	#0x3e8
 240:	d5033bbf 	dmb	ish
 244:	b9401cc5 	ldr	w5, [x6, #28]
 248:	2a0503e1 	mov	w1, w5
 24c:	0a0700a3 	and	w3, w5, w7
 250:	885ffc82 	ldaxr	w2, [x4]
 254:	6b0200bf 	cmp	w5, w2
 258:	54ffff41 	b.ne	240 <alloc_slot+0x240>  // b.any
 25c:	8802fc83 	stlxr	w2, w3, [x4]
 260:	35ffff82 	cbnz	w2, 250 <alloc_slot+0x250>
 264:	0a010000 	and	w0, w0, w1
 268:	b90018c0 	str	w0, [x6, #24]
 26c:	34fffe40 	cbz	w0, 234 <alloc_slot+0x234>
 270:	f94010c1 	ldr	x1, [x6, #32]
 274:	53062c21 	ubfx	w1, w1, #6, #6
 278:	51001c21 	sub	w1, w1, #0x7
 27c:	71007c3f 	cmp	w1, #0x1f
 280:	540000c8 	b.hi	298 <alloc_slot+0x298>  // b.pmore
 284:	8b21c2c1 	add	x1, x22, w1, sxtw
 288:	394e6022 	ldrb	w2, [x1, #920]
 28c:	34000062 	cbz	w2, 298 <alloc_slot+0x298>
 290:	51000442 	sub	w2, w2, #0x1
 294:	390e6022 	strb	w2, [x1, #920]
 298:	4b0003e2 	neg	w2, w0
 29c:	0a220001 	bic	w1, w0, w2
 2a0:	b90018c1 	str	w1, [x6, #24]
 2a4:	6a000042 	ands	w2, w2, w0
 2a8:	54ffee80 	b.eq	78 <alloc_slot+0x78>  // b.none
 2ac:	5ac00040 	rbit	w0, w2
 2b0:	5ac01000 	clz	w0, w0
 2b4:	a94157f4 	ldp	x20, x21, [sp, #16]
 2b8:	a9425ff6 	ldp	x22, x23, [sp, #32]
 2bc:	a94367f8 	ldp	x24, x25, [sp, #48]
 2c0:	a8c64ffe 	ldp	x30, x19, [sp], #96
 2c4:	d65f03c0 	ret
 2c8:	120006a1 	and	w1, w21, #0x3
 2cc:	90000000 	adrp	x0, 0 <alloc_slot>
			2cc: R_AARCH64_ADR_PREL_PG_HI21	.rodata.med_cnt_tab
 2d0:	91000000 	add	x0, x0, #0x0
			2d0: R_AARCH64_ADD_ABS_LO12_NC	.rodata.med_cnt_tab
 2d4:	3861c802 	ldrb	w2, [x0, w1, sxtw]
 2d8:	14000002 	b	2e0 <alloc_slot+0x2e0>
 2dc:	13017c42 	asr	w2, w2, #1
 2e0:	37000082 	tbnz	w2, #0, 2f0 <alloc_slot+0x2f0>
 2e4:	531e7440 	lsl	w0, w2, #2
 2e8:	eb20c07f 	cmp	x3, w0, sxtw
 2ec:	54ffff83 	b.cc	2dc <alloc_slot+0x2dc>  // b.lo, b.ul, b.last
 2f0:	b2404fe1 	mov	x1, #0xfffff               	// #1048575
 2f4:	14000002 	b	2fc <alloc_slot+0x2fc>
 2f8:	13017c42 	asr	w2, w2, #1
 2fc:	9ba27ee0 	umull	x0, w23, w2
 300:	eb01001f 	cmp	x0, x1
 304:	54ffffa8 	b.hi	2f8 <alloc_slot+0x2f8>  // b.pmore
 308:	b27c33e0 	mov	x0, #0x1fff0               	// #131056
 30c:	d341fc81 	lsr	x1, x4, #1
 310:	9ad70800 	udiv	x0, x0, x23
 314:	f100201f 	cmp	x0, #0x8
 318:	54000249 	b.ls	360 <alloc_slot+0x360>  // b.plast
 31c:	7100205f 	cmp	w2, #0x8
 320:	52800100 	mov	w0, #0x8                   	// #8
 324:	1a80a053 	csel	w19, w2, w0, ge	// ge = tcont
 328:	51001ea0 	sub	w0, w21, #0x7
 32c:	93407e7a 	sxtw	x26, w19
 330:	9bbc7e65 	umull	x5, w19, w28
 334:	910040a2 	add	x2, x5, #0x10
 338:	eb01005f 	cmp	x2, x1
 33c:	54001c49 	b.ls	6c4 <alloc_slot+0x6c4>  // b.plast
 340:	531e7666 	lsl	w6, w19, #2
 344:	93407cc6 	sxtw	x6, w6
 348:	71007c1f 	cmp	w0, #0x1f
 34c:	540009e9 	b.ls	488 <alloc_slot+0x488>  // b.plast
 350:	394ee2c2 	ldrb	w2, [x22, #952]
 354:	52800008 	mov	w8, #0x0                   	// #0
 358:	52800021 	mov	w1, #0x1                   	// #1
 35c:	1400001d 	b	3d0 <alloc_slot+0x3d0>
 360:	6b00005f 	cmp	w2, w0
 364:	1a80c053 	csel	w19, w2, w0, gt
 368:	93407e7a 	sxtw	x26, w19
 36c:	7100067f 	cmp	w19, #0x1
 370:	540000c1 	b.ne	388 <alloc_slot+0x388>  // b.any
 374:	910042e0 	add	x0, x23, #0x10
 378:	eb01001f 	cmp	x0, x1
 37c:	54000148 	b.hi	3a4 <alloc_slot+0x3a4>  // b.pmore
 380:	d280005a 	mov	x26, #0x2                   	// #2
 384:	2a1a03f3 	mov	w19, w26
 388:	9bba7f85 	umull	x5, w28, w26
 38c:	910040a0 	add	x0, x5, #0x10
 390:	eb01001f 	cmp	x0, x1
 394:	54001989 	b.ls	6c4 <alloc_slot+0x6c4>  // b.plast
 398:	531e7666 	lsl	w6, w19, #2
 39c:	93407cc6 	sxtw	x6, w6
 3a0:	14000003 	b	3ac <alloc_slot+0x3ac>
 3a4:	aa1703e5 	mov	x5, x23
 3a8:	d2800086 	mov	x6, #0x4                   	// #4
 3ac:	51001ea0 	sub	w0, w21, #0x7
 3b0:	b27c33e1 	mov	x1, #0x1fff0               	// #131056
 3b4:	eb0102ff 	cmp	x23, x1
 3b8:	54fffc49 	b.ls	340 <alloc_slot+0x340>  // b.plast
 3bc:	71007c1f 	cmp	w0, #0x1f
 3c0:	540003e9 	b.ls	43c <alloc_slot+0x43c>  // b.plast
 3c4:	394ee2c2 	ldrb	w2, [x22, #952]
 3c8:	52800028 	mov	w8, #0x1                   	// #1
 3cc:	52800001 	mov	w1, #0x0                   	// #0
 3d0:	11000440 	add	w0, w2, #0x1
 3d4:	12001c00 	and	w0, w0, #0xff
 3d8:	7103fc5f 	cmp	w2, #0xff
 3dc:	540005c0 	b.eq	494 <alloc_slot+0x494>  // b.none
 3e0:	390ee2c0 	strb	w0, [x22, #952]
 3e4:	d1000487 	sub	x7, x4, #0x1
 3e8:	37000715 	tbnz	w21, #0, 4c8 <alloc_slot+0x4c8>
 3ec:	71007ebf 	cmp	w21, #0x1f
 3f0:	5400064c 	b.gt	4b8 <alloc_slot+0x4b8>
 3f4:	110006a0 	add	w0, w21, #0x1
 3f8:	7100011f 	cmp	w8, #0x0
 3fc:	8b20cec0 	add	x0, x22, w0, sxtw #3
 400:	f940fc00 	ldr	x0, [x0, #504]
 404:	8b000063 	add	x3, x3, x0
 408:	fa461062 	ccmp	x3, x6, #0x2, ne	// ne = any
 40c:	54000642 	b.cs	4d4 <alloc_slot+0x4d4>  // b.hs, b.nlast
 410:	120006a0 	and	w0, w21, #0x3
 414:	7100081f 	cmp	w0, #0x2
 418:	540013e0 	b.eq	694 <alloc_slot+0x694>  // b.none
 41c:	eb040cbf 	cmp	x5, x4, lsl #3
 420:	540013e8 	b.hi	69c <alloc_slot+0x69c>  // b.pmore
 424:	eb0404bf 	cmp	x5, x4, lsl #1
 428:	54000569 	b.ls	4d4 <alloc_slot+0x4d4>  // b.plast
 42c:	d28000a0 	mov	x0, #0x5                   	// #5
 430:	52800022 	mov	w2, #0x1                   	// #1
 434:	2a0003f3 	mov	w19, w0
 438:	1400002a 	b	4e0 <alloc_slot+0x4e0>
 43c:	8b20c2c1 	add	x1, x22, w0, sxtw
 440:	394e6021 	ldrb	w1, [x1, #920]
 444:	71018c3f 	cmp	w1, #0x63
 448:	1a9f97e1 	cset	w1, hi	// hi = pmore
 44c:	1a9f87e8 	cset	w8, ls	// ls = plast
 450:	8b20c2c0 	add	x0, x22, w0, sxtw
 454:	394ee2c2 	ldrb	w2, [x22, #952]
 458:	394de007 	ldrb	w7, [x0, #888]
 45c:	34fffba7 	cbz	w7, 3d0 <alloc_slot+0x3d0>
 460:	4b070047 	sub	w7, w2, w7
 464:	710024ff 	cmp	w7, #0x9
 468:	54fffb4c 	b.gt	3d0 <alloc_slot+0x3d0>
 46c:	394e6007 	ldrb	w7, [x0, #920]
 470:	12800d29 	mov	w9, #0xffffff96            	// #-106
 474:	71018cff 	cmp	w7, #0x63
 478:	110004e7 	add	w7, w7, #0x1
 47c:	1a872127 	csel	w7, w9, w7, cs	// cs = hs, nlast
 480:	390e6007 	strb	w7, [x0, #920]
 484:	17ffffd3 	b	3d0 <alloc_slot+0x3d0>
 488:	52800008 	mov	w8, #0x0                   	// #0
 48c:	52800021 	mov	w1, #0x1                   	// #1
 490:	17fffff0 	b	450 <alloc_slot+0x450>
 494:	90000002 	adrp	x2, 0 <alloc_slot>
			494: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context+0x378
 498:	910e62c0 	add	x0, x22, #0x398
 49c:	91000042 	add	x2, x2, #0x0
			49c: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context+0x378
 4a0:	14000002 	b	4a8 <alloc_slot+0x4a8>
 4a4:	3800145f 	strb	wzr, [x2], #1
 4a8:	eb00005f 	cmp	x2, x0
 4ac:	54ffffc1 	b.ne	4a4 <alloc_slot+0x4a4>  // b.any
 4b0:	52800020 	mov	w0, #0x1                   	// #1
 4b4:	17ffffcb 	b	3e0 <alloc_slot+0x3e0>
 4b8:	7100011f 	cmp	w8, #0x0
 4bc:	fa461062 	ccmp	x3, x6, #0x2, ne	// ne = any
 4c0:	540000a2 	b.cs	4d4 <alloc_slot+0x4d4>  // b.hs, b.nlast
 4c4:	17ffffd3 	b	410 <alloc_slot+0x410>
 4c8:	7100011f 	cmp	w8, #0x0
 4cc:	fa461062 	ccmp	x3, x6, #0x2, ne	// ne = any
 4d0:	54000a83 	b.cc	620 <alloc_slot+0x620>  // b.lo, b.ul, b.last
 4d4:	71001e7f 	cmp	w19, #0x7
 4d8:	93407e60 	sxtw	x0, w19
 4dc:	1a9fc7e2 	cset	w2, le
 4e0:	9ba07f80 	umull	x0, w28, w0
 4e4:	928001fa 	mov	x26, #0xfffffffffffffff0    	// #-16
 4e8:	52000021 	eor	w1, w1, #0x1
 4ec:	cb00035a 	sub	x26, x26, x0
 4f0:	91004000 	add	x0, x0, #0x10
 4f4:	8a07035a 	and	x26, x26, x7
 4f8:	8b00035a 	add	x26, x26, x0
 4fc:	6a01005f 	tst	w2, w1
 500:	54000aa1 	b.ne	654 <alloc_slot+0x654>  // b.any
 504:	aa1a03e1 	mov	x1, x26
 508:	d2800005 	mov	x5, #0x0                   	// #0
 50c:	12800004 	mov	w4, #0xffffffff            	// #-1
 510:	52800443 	mov	w3, #0x22                  	// #34
 514:	52800062 	mov	w2, #0x3                   	// #3
 518:	d2800000 	mov	x0, #0x0                   	// #0
 51c:	94000000 	bl	0 <__mmap>
			51c: R_AARCH64_CALL26	__mmap
 520:	b100041f 	cmn	x0, #0x1
 524:	54001aa0 	b.eq	878 <alloc_slot+0x878>  // b.none
 528:	d281fe02 	mov	x2, #0xff0                 	// #4080
 52c:	d34cff45 	lsr	x5, x26, #12
 530:	f9401284 	ldr	x4, [x20, #32]
 534:	51000663 	sub	w3, w19, #0x1
 538:	9ad70841 	udiv	x1, x2, x23
 53c:	93407e7a 	sxtw	x26, w19
 540:	b374cca4 	bfi	x4, x5, #12, #52
 544:	f9001284 	str	x4, [x20, #32]
 548:	51000421 	sub	w1, w1, #0x1
 54c:	b9400ec2 	ldr	w2, [x22, #12]
 550:	6b13003f 	cmp	w1, w19
 554:	1a83b021 	csel	w1, w1, w3, lt	// lt = tstop
 558:	11000442 	add	w2, w2, #0x1
 55c:	b9000ec2 	str	w2, [x22, #12]
 560:	0aa17c22 	bic	w2, w1, w1, asr #31
 564:	8b180ec4 	add	x4, x22, x24, lsl #3
 568:	52800041 	mov	w1, #0x2                   	// #2
 56c:	1ac22025 	lsl	w5, w1, w2
 570:	510004a5 	sub	w5, w5, #0x1
 574:	1ac32021 	lsl	w1, w1, w3
 578:	120016b5 	and	w21, w21, #0x3f
 57c:	f940fc86 	ldr	x6, [x4, #504]
 580:	12001063 	and	w3, w3, #0x1f
 584:	321b0063 	orr	w3, w3, #0x20
 588:	8b1a00c6 	add	x6, x6, x26
 58c:	f900fc86 	str	x6, [x4, #504]
 590:	b9001a85 	str	w5, [x20, #24]
 594:	2a151863 	orr	w3, w3, w21, lsl #6
 598:	f9000a80 	str	x0, [x20, #16]
 59c:	b9401a84 	ldr	w4, [x20, #24]
 5a0:	4b040021 	sub	w1, w1, w4
 5a4:	51000421 	sub	w1, w1, #0x1
 5a8:	b9001e81 	str	w1, [x20, #28]
 5ac:	f9000014 	str	x20, [x0]
 5b0:	f9400a80 	ldr	x0, [x20, #16]
 5b4:	39402001 	ldrb	w1, [x0, #8]
 5b8:	33001041 	bfxil	w1, w2, #0, #5
 5bc:	39002001 	strb	w1, [x0, #8]
 5c0:	79404280 	ldrh	w0, [x20, #32]
 5c4:	f9400682 	ldr	x2, [x20, #8]
 5c8:	12144c00 	and	w0, w0, #0xfffff000
 5cc:	b9401a81 	ldr	w1, [x20, #24]
 5d0:	2a000060 	orr	w0, w3, w0
 5d4:	79004280 	strh	w0, [x20, #32]
 5d8:	51000420 	sub	w0, w1, #0x1
 5dc:	b9001a80 	str	w0, [x20, #24]
 5e0:	b5ffe2e2 	cbnz	x2, 23c <alloc_slot+0x23c>
 5e4:	f9400280 	ldr	x0, [x20]
 5e8:	b5ffe2a0 	cbnz	x0, 23c <alloc_slot+0x23c>
 5ec:	91002b18 	add	x24, x24, #0xa
 5f0:	f8787ac0 	ldr	x0, [x22, x24, lsl #3]
 5f4:	b40016a0 	cbz	x0, 8c8 <alloc_slot+0x8c8>
 5f8:	f9000680 	str	x0, [x20, #8]
 5fc:	f9400000 	ldr	x0, [x0]
 600:	f9000280 	str	x0, [x20]
 604:	f9000414 	str	x20, [x0, #8]
 608:	f9400680 	ldr	x0, [x20, #8]
 60c:	f9000014 	str	x20, [x0]
 610:	f9402bfc 	ldr	x28, [sp, #80]
 614:	52800000 	mov	w0, #0x0                   	// #0
 618:	a9446ffa 	ldp	x26, x27, [sp, #64]
 61c:	17ffff26 	b	2b4 <alloc_slot+0x2b4>
 620:	120006a0 	and	w0, w21, #0x3
 624:	7100041f 	cmp	w0, #0x1
 628:	54fff561 	b.ne	4d4 <alloc_slot+0x4d4>  // b.any
 62c:	eb040cbf 	cmp	x5, x4, lsl #3
 630:	54fff529 	b.ls	4d4 <alloc_slot+0x4d4>  // b.plast
 634:	2a1c03e0 	mov	w0, w28
 638:	928001fa 	mov	x26, #0xfffffffffffffff0    	// #-16
 63c:	52800053 	mov	w19, #0x2                   	// #2
 640:	d37ff800 	lsl	x0, x0, #1
 644:	cb00035a 	sub	x26, x26, x0
 648:	91004000 	add	x0, x0, #0x10
 64c:	8a07035a 	and	x26, x26, x7
 650:	8b00035a 	add	x26, x26, x0
 654:	92800260 	mov	x0, #0xffffffffffffffec    	// #-20
 658:	cb190000 	sub	x0, x0, x25
 65c:	8a070000 	and	x0, x0, x7
 660:	91005339 	add	x25, x25, #0x14
 664:	8b190000 	add	x0, x0, x25
 668:	910042e1 	add	x1, x23, #0x10
 66c:	eb01001f 	cmp	x0, x1
 670:	540001e3 	b.cc	6ac <alloc_slot+0x6ac>  // b.lo, b.ul, b.last
 674:	eb04081f 	cmp	x0, x4, lsl #2
 678:	54fff463 	b.cc	504 <alloc_slot+0x504>  // b.lo, b.ul, b.last
 67c:	531f7a61 	lsl	w1, w19, #1
 680:	93407c21 	sxtw	x1, w1
 684:	eb03003f 	cmp	x1, x3
 688:	9a80935a 	csel	x26, x26, x0, ls	// ls = plast
 68c:	1a9f9673 	csinc	w19, w19, wzr, ls	// ls = plast
 690:	17ffff9d 	b	504 <alloc_slot+0x504>
 694:	eb0408bf 	cmp	x5, x4, lsl #2
 698:	54fff1e9 	b.ls	4d4 <alloc_slot+0x4d4>  // b.plast
 69c:	d2800060 	mov	x0, #0x3                   	// #3
 6a0:	52800022 	mov	w2, #0x1                   	// #1
 6a4:	2a0003f3 	mov	w19, w0
 6a8:	17ffff8e 	b	4e0 <alloc_slot+0x4e0>
 6ac:	aa0003fa 	mov	x26, x0
 6b0:	52800033 	mov	w19, #0x1                   	// #1
 6b4:	17ffff94 	b	504 <alloc_slot+0x504>
 6b8:	a9005294 	stp	x20, x20, [x20]
 6bc:	f9000ad4 	str	x20, [x22, #16]
 6c0:	14000079 	b	8a4 <alloc_slot+0x8a4>
 6c4:	910030a1 	add	x1, x5, #0xc
 6c8:	d344fcb9 	lsr	x25, x5, #4
 6cc:	f10240bf 	cmp	x5, #0x90
 6d0:	540001c9 	b.ls	708 <alloc_slot+0x708>  // b.plast
 6d4:	91000720 	add	x0, x25, #0x1
 6d8:	528003d9 	mov	w25, #0x1e                  	// #30
 6dc:	5ac01002 	clz	w2, w0
 6e0:	4b020339 	sub	w25, w25, w2
 6e4:	531e7739 	lsl	w25, w25, #2
 6e8:	11000723 	add	w3, w25, #0x1
 6ec:	11000b22 	add	w2, w25, #0x2
 6f0:	7863db63 	ldrh	w3, [x27, w3, sxtw #1]
 6f4:	eb03001f 	cmp	x0, x3
 6f8:	1a998059 	csel	w25, w2, w25, hi	// hi = pmore
 6fc:	7879db62 	ldrh	w2, [x27, w25, sxtw #1]
 700:	eb02001f 	cmp	x0, x2
 704:	1a999739 	cinc	w25, w25, hi	// hi = pmore
 708:	2a1903e0 	mov	w0, w25
 70c:	97fffe3d 	bl	0 <alloc_slot>
 710:	2a0003e6 	mov	w6, w0
 714:	3100041f 	cmn	w0, #0x1
 718:	54000b00 	b.eq	878 <alloc_slot+0x878>  // b.none
 71c:	8b39cec0 	add	x0, x22, w25, sxtw #3
 720:	7879db67 	ldrh	w7, [x27, w25, sxtw #1]
 724:	f9402809 	ldr	x9, [x0, #80]
 728:	531c6ce7 	lsl	w7, w7, #4
 72c:	510010e7 	sub	w7, w7, #0x4
 730:	f9401121 	ldr	x1, [x9, #32]
 734:	93407ce3 	sxtw	x3, w7
 738:	f13ffc3f 	cmp	x1, #0xfff
 73c:	92401020 	and	x0, x1, #0x1f
 740:	fa408800 	ccmp	x0, #0x0, #0x0, hi	// hi = pmore
 744:	54000b80 	b.eq	8b4 <alloc_slot+0x8b4>  // b.none
 748:	53062c21 	ubfx	w1, w1, #6, #6
 74c:	7861db61 	ldrh	w1, [x27, w1, sxtw #1]
 750:	d37c3c21 	ubfiz	x1, x1, #4, #16
 754:	f9400922 	ldr	x2, [x9, #16]
 758:	93407cc0 	sxtw	x0, w6
 75c:	cb030023 	sub	x3, x1, x3
 760:	d1001025 	sub	x5, x1, #0x4
 764:	91004042 	add	x2, x2, #0x10
 768:	d1001063 	sub	x3, x3, #0x4
 76c:	9b010800 	madd	x0, x0, x1, x2
 770:	8b050005 	add	x5, x0, x5
 774:	385fc004 	ldurb	w4, [x0, #-4]
 778:	35ffd624 	cbnz	w4, 23c <alloc_slot+0x23c>
 77c:	f1003c7f 	cmp	x3, #0xf
 780:	54000389 	b.ls	7f0 <alloc_slot+0x7f0>  // b.plast
 784:	385fd001 	ldurb	w1, [x0, #-3]
 788:	340009c1 	cbz	w1, 8c0 <alloc_slot+0x8c0>
 78c:	785fe008 	ldurh	w8, [x0, #-2]
 790:	11000508 	add	w8, w8, #0x1
 794:	12001d08 	and	w8, w8, #0xff
 798:	d344fc6a 	lsr	x10, x3, #4
 79c:	eb28c15f 	cmp	x10, w8, sxtw
 7a0:	54000162 	b.cs	7cc <alloc_slot+0x7cc>  // b.hs, b.nlast
 7a4:	aa431541 	orr	x1, x10, x3, lsr #5
 7a8:	aa410821 	orr	x1, x1, x1, lsr #2
 7ac:	aa411021 	orr	x1, x1, x1, lsr #4
 7b0:	0a010108 	and	w8, w8, w1
 7b4:	eb28c15f 	cmp	x10, w8, sxtw
 7b8:	540000a2 	b.cs	7cc <alloc_slot+0x7cc>  // b.hs, b.nlast
 7bc:	4b0a0108 	sub	w8, w8, w10
 7c0:	51000508 	sub	w8, w8, #0x1
 7c4:	eb28c15f 	cmp	x10, w8, sxtw
 7c8:	54ffd3a3 	b.cc	23c <alloc_slot+0x23c>  // b.lo, b.ul, b.last
 7cc:	34000128 	cbz	w8, 7f0 <alloc_slot+0x7f0>
 7d0:	531c6d01 	lsl	w1, w8, #4
 7d4:	128003e2 	mov	w2, #0xffffffe0            	// #-32
 7d8:	381fd002 	sturb	w2, [x0, #-3]
 7dc:	781fe008 	sturh	w8, [x0, #-2]
 7e0:	8b21c000 	add	x0, x0, w1, sxtw
 7e4:	381fc01f 	sturb	wzr, [x0, #-4]
 7e8:	f9400922 	ldr	x2, [x9, #16]
 7ec:	91004042 	add	x2, x2, #0x10
 7f0:	cb020001 	sub	x1, x0, x2
 7f4:	cb0000a2 	sub	x2, x5, x0
 7f8:	6b070042 	subs	w2, w2, w7
 7fc:	d344fc21 	lsr	x1, x1, #4
 800:	781fe001 	sturh	w1, [x0, #-2]
 804:	54000120 	b.eq	828 <alloc_slot+0x828>  // b.none
 808:	4b0203e1 	neg	w1, w2
 80c:	531b0844 	ubfiz	w4, w2, #5, #3
 810:	3821c8bf 	strb	wzr, [x5, w1, sxtw]
 814:	7100105f 	cmp	w2, #0x4
 818:	5400008d 	b.le	828 <alloc_slot+0x828>
 81c:	52801404 	mov	w4, #0xa0                  	// #160
 820:	381fb0bf 	sturb	wzr, [x5, #-5]
 824:	b81fc0a2 	stur	w2, [x5, #-4]
 828:	0b060084 	add	w4, w4, w6
 82c:	381fd004 	sturb	w4, [x0, #-3]
 830:	91003002 	add	x2, x0, #0xc
 834:	11000663 	add	w3, w19, #0x1
 838:	f9401284 	ldr	x4, [x20, #32]
 83c:	52800001 	mov	w1, #0x0                   	// #0
 840:	92402c84 	and	x4, x4, #0xfff
 844:	f9001284 	str	x4, [x20, #32]
 848:	385fd004 	ldurb	w4, [x0, #-3]
 84c:	12001084 	and	w4, w4, #0x1f
 850:	321a6484 	orr	w4, w4, #0xffffffc0
 854:	381fd004 	sturb	w4, [x0, #-3]
 858:	11000421 	add	w1, w1, #0x1
 85c:	3900005f 	strb	wzr, [x2]
 860:	8b170042 	add	x2, x2, x23
 864:	6b03003f 	cmp	w1, w3
 868:	54ffff81 	b.ne	858 <alloc_slot+0x858>  // b.any
 86c:	51000663 	sub	w3, w19, #0x1
 870:	2a0303e2 	mov	w2, w3
 874:	17ffff3c 	b	564 <alloc_slot+0x564>
 878:	a9007e9f 	stp	xzr, xzr, [x20]
 87c:	a9017e9f 	stp	xzr, xzr, [x20, #16]
 880:	f9400ac0 	ldr	x0, [x22, #16]
 884:	f900129f 	str	xzr, [x20, #32]
 888:	b4fff180 	cbz	x0, 6b8 <alloc_slot+0x6b8>
 88c:	f9000680 	str	x0, [x20, #8]
 890:	f9400000 	ldr	x0, [x0]
 894:	f9000280 	str	x0, [x20]
 898:	f9000414 	str	x20, [x0, #8]
 89c:	f9400680 	ldr	x0, [x20, #8]
 8a0:	f9000014 	str	x20, [x0]
 8a4:	f9402bfc 	ldr	x28, [sp, #80]
 8a8:	12800000 	mov	w0, #0xffffffff            	// #-1
 8ac:	a9446ffa 	ldp	x26, x27, [sp, #64]
 8b0:	17fffe81 	b	2b4 <alloc_slot+0x2b4>
 8b4:	9274cc21 	and	x1, x1, #0xfffffffffffff000
 8b8:	d1004021 	sub	x1, x1, #0x10
 8bc:	17ffffa6 	b	754 <alloc_slot+0x754>
 8c0:	394032c8 	ldrb	w8, [x22, #12]
 8c4:	17ffffb5 	b	798 <alloc_slot+0x798>
 8c8:	a9005294 	stp	x20, x20, [x20]
 8cc:	f8387ad4 	str	x20, [x22, x24, lsl #3]
 8d0:	17ffff50 	b	610 <alloc_slot+0x610>

Disassembly of section .text.__libc_malloc_impl:

0000000000000000 <__libc_malloc_impl>:
   0:	92820021 	mov	x1, #0xffffffffffffeffe    	// #-4098
   4:	a9bb4ffe 	stp	x30, x19, [sp, #-80]!
   8:	f2efffe1 	movk	x1, #0x7fff, lsl #48
   c:	eb01001f 	cmp	x0, x1
  10:	540006a8 	b.hi	e4 <__libc_malloc_impl+0xe4>  // b.pmore
  14:	aa0003f3 	mov	x19, x0
  18:	d29ffd60 	mov	x0, #0xffeb                	// #65515
  1c:	a90157f4 	stp	x20, x21, [sp, #16]
  20:	f2a00020 	movk	x0, #0x1, lsl #16
  24:	a9025ff6 	stp	x22, x23, [sp, #32]
  28:	a90367f8 	stp	x24, x25, [sp, #48]
  2c:	a9046ffa 	stp	x26, x27, [sp, #64]
  30:	eb00027f 	cmp	x19, x0
  34:	54000628 	b.hi	f8 <__libc_malloc_impl+0xf8>  // b.pmore
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
  8c:	9000001a 	adrp	x26, 0 <__libc_malloc_impl>
			8c: R_AARCH64_ADR_PREL_PG_HI21	__malloc_lock
  90:	91000356 	add	x22, x26, #0x0
			90: R_AARCH64_ADD_ABS_LO12_NC	__malloc_lock
  94:	39400c00 	ldrb	w0, [x0, #3]
  98:	72001c1f 	tst	w0, #0xff
  9c:	54001be1 	b.ne	418 <__libc_malloc_impl+0x418>  // b.any
  a0:	93407e95 	sxtw	x21, w20
  a4:	90000001 	adrp	x1, 0 <__libc_malloc_impl>
			a4: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
  a8:	91002aa0 	add	x0, x21, #0xa
  ac:	91000039 	add	x25, x1, #0x0
			ac: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
  b0:	f8607b38 	ldr	x24, [x25, x0, lsl #3]
  b4:	b4001b98 	cbz	x24, 424 <__libc_malloc_impl+0x424>
  b8:	b9401b00 	ldr	w0, [x24, #24]
  bc:	4b0003e1 	neg	w1, w0
  c0:	6a000021 	ands	w1, w1, w0
  c4:	54001b00 	b.eq	424 <__libc_malloc_impl+0x424>  // b.none
  c8:	5ac00034 	rbit	w20, w1
  cc:	4b010000 	sub	w0, w0, w1
  d0:	5ac01294 	clz	w20, w20
  d4:	b9400f37 	ldr	w23, [x25, #12]
  d8:	b9001b00 	str	w0, [x24, #24]
  dc:	93407e9b 	sxtw	x27, w20
  e0:	1400004f 	b	21c <__libc_malloc_impl+0x21c>
  e4:	94000000 	bl	0 <___errno_location>
			e4: R_AARCH64_CALL26	___errno_location
  e8:	52800181 	mov	w1, #0xc                   	// #12
  ec:	b9000001 	str	w1, [x0]
  f0:	d2800000 	mov	x0, #0x0                   	// #0
  f4:	14000091 	b	338 <__libc_malloc_impl+0x338>
  f8:	d2820260 	mov	x0, #0x1013                	// #4115
  fc:	8b000275 	add	x21, x19, x0
 100:	91005277 	add	x23, x19, #0x14
 104:	d34cfeb5 	lsr	x21, x21, #12
 108:	d10082a0 	sub	x0, x21, #0x20
 10c:	f107801f 	cmp	x0, #0x1e0
 110:	54000368 	b.hi	17c <__libc_malloc_impl+0x17c>  // b.pmore
 114:	52800014 	mov	w20, #0x0                   	// #0
 118:	d2800401 	mov	x1, #0x20                  	// #32
 11c:	eb0102bf 	cmp	x21, x1
 120:	54000089 	b.ls	130 <__libc_malloc_impl+0x130>  // b.plast
 124:	11000694 	add	w20, w20, #0x1
 128:	d37ff821 	lsl	x1, x1, #1
 12c:	17fffffc 	b	11c <__libc_malloc_impl+0x11c>
 130:	90000000 	adrp	x0, 0 <__libc>
			130: R_AARCH64_ADR_PREL_PG_HI21	__libc
 134:	91000000 	add	x0, x0, #0x0
			134: R_AARCH64_ADD_ABS_LO12_NC	__libc
 138:	9000001a 	adrp	x26, 0 <__libc_malloc_impl>
			138: R_AARCH64_ADR_PREL_PG_HI21	__malloc_lock
 13c:	91000356 	add	x22, x26, #0x0
			13c: R_AARCH64_ADD_ABS_LO12_NC	__malloc_lock
 140:	39400c00 	ldrb	w0, [x0, #3]
 144:	72001c1f 	tst	w0, #0xff
 148:	54000fc1 	b.ne	340 <__libc_malloc_impl+0x340>  // b.any
 14c:	93407e94 	sxtw	x20, w20
 150:	90000001 	adrp	x1, 0 <__libc_malloc_impl>
			150: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
 154:	9100ea94 	add	x20, x20, #0x3a
 158:	91000039 	add	x25, x1, #0x0
			158: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 15c:	f8747b38 	ldr	x24, [x25, x20, lsl #3]
 160:	b40000b8 	cbz	x24, 174 <__libc_malloc_impl+0x174>
 164:	f9401300 	ldr	x0, [x24, #32]
 168:	9274cc00 	and	x0, x0, #0xfffffffffffff000
 16c:	eb17001f 	cmp	x0, x23
 170:	54000ee2 	b.cs	34c <__libc_malloc_impl+0x34c>  // b.hs, b.nlast
 174:	b9400340 	ldr	w0, [x26]
			174: R_AARCH64_LDST32_ABS_LO12_NC	__malloc_lock
 178:	37f81180 	tbnz	w0, #31, 3a8 <__libc_malloc_impl+0x3a8>
 17c:	aa1703e1 	mov	x1, x23
 180:	d2800005 	mov	x5, #0x0                   	// #0
 184:	12800004 	mov	w4, #0xffffffff            	// #-1
 188:	52800443 	mov	w3, #0x22                  	// #34
 18c:	52800062 	mov	w2, #0x3                   	// #3
 190:	d2800000 	mov	x0, #0x0                   	// #0
 194:	94000000 	bl	0 <__mmap>
			194: R_AARCH64_CALL26	__mmap
 198:	aa0003f4 	mov	x20, x0
 19c:	b100041f 	cmn	x0, #0x1
 1a0:	540015c0 	b.eq	458 <__libc_malloc_impl+0x458>  // b.none
 1a4:	90000000 	adrp	x0, 0 <__libc>
			1a4: R_AARCH64_ADR_PREL_PG_HI21	__libc
 1a8:	91000000 	add	x0, x0, #0x0
			1a8: R_AARCH64_ADD_ABS_LO12_NC	__libc
 1ac:	9000001a 	adrp	x26, 0 <__libc_malloc_impl>
			1ac: R_AARCH64_ADR_PREL_PG_HI21	__malloc_lock
 1b0:	91000356 	add	x22, x26, #0x0
			1b0: R_AARCH64_ADD_ABS_LO12_NC	__malloc_lock
 1b4:	39400c00 	ldrb	w0, [x0, #3]
 1b8:	72001c1f 	tst	w0, #0xff
 1bc:	54000fc1 	b.ne	3b4 <__libc_malloc_impl+0x3b4>  // b.any
 1c0:	90000001 	adrp	x1, 0 <__libc_malloc_impl>
			1c0: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
 1c4:	91000039 	add	x25, x1, #0x0
			1c4: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 1c8:	394ee321 	ldrb	w1, [x25, #952]
 1cc:	11000420 	add	w0, w1, #0x1
 1d0:	12001c00 	and	w0, w0, #0xff
 1d4:	7103fc3f 	cmp	w1, #0xff
 1d8:	54000f40 	b.eq	3c0 <__libc_malloc_impl+0x3c0>  // b.none
 1dc:	390ee320 	strb	w0, [x25, #952]
 1e0:	94000000 	bl	0 <__libc_malloc_impl>
			1e0: R_AARCH64_CALL26	__malloc_alloc_meta
 1e4:	aa0003f8 	mov	x24, x0
 1e8:	b4000fe0 	cbz	x0, 3e4 <__libc_malloc_impl+0x3e4>
 1ec:	f9000814 	str	x20, [x0, #16]
 1f0:	d374ceb5 	lsl	x21, x21, #12
 1f4:	f9000280 	str	x0, [x20]
 1f8:	b27b1ab5 	orr	x21, x21, #0xfe0
 1fc:	b9001c1f 	str	wzr, [x0, #28]
 200:	d280001b 	mov	x27, #0x0                   	// #0
 204:	b9400f21 	ldr	w1, [x25, #12]
 208:	52800014 	mov	w20, #0x0                   	// #0
 20c:	b900181f 	str	wzr, [x0, #24]
 210:	11000437 	add	w23, w1, #0x1
 214:	b9000f37 	str	w23, [x25, #12]
 218:	f9001015 	str	x21, [x0, #32]
 21c:	b9400340 	ldr	w0, [x26]
			21c: R_AARCH64_LDST32_ABS_LO12_NC	__malloc_lock
 220:	37f81340 	tbnz	w0, #31, 488 <__libc_malloc_impl+0x488>
 224:	f9401301 	ldr	x1, [x24, #32]
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
 24c:	f9400b02 	ldr	x2, [x24, #16]
 250:	d1001025 	sub	x5, x1, #0x4
 254:	cb130023 	sub	x3, x1, x19
 258:	91004042 	add	x2, x2, #0x10
 25c:	d1001063 	sub	x3, x3, #0x4
 260:	9b1b0820 	madd	x0, x1, x27, x2
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
 2e0:	f9400b02 	ldr	x2, [x24, #16]
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
 334:	a9446ffa 	ldp	x26, x27, [sp, #64]
 338:	a8c54ffe 	ldp	x30, x19, [sp], #80
 33c:	d65f03c0 	ret
 340:	aa1603e0 	mov	x0, x22
 344:	94000000 	bl	0 <__lock>
			344: R_AARCH64_CALL26	__lock
 348:	17ffff81 	b	14c <__libc_malloc_impl+0x14c>
 34c:	f8347b3f 	str	xzr, [x25, x20, lsl #3]
 350:	b9001f1f 	str	wzr, [x24, #28]
 354:	394ee321 	ldrb	w1, [x25, #952]
 358:	11000420 	add	w0, w1, #0x1
 35c:	12001c00 	and	w0, w0, #0xff
 360:	7103fc3f 	cmp	w1, #0xff
 364:	54000100 	b.eq	384 <__libc_malloc_impl+0x384>  // b.none
 368:	b9400f21 	ldr	w1, [x25, #12]
 36c:	d280001b 	mov	x27, #0x0                   	// #0
 370:	52800014 	mov	w20, #0x0                   	// #0
 374:	390ee320 	strb	w0, [x25, #952]
 378:	11000437 	add	w23, w1, #0x1
 37c:	b9000f37 	str	w23, [x25, #12]
 380:	17ffffa7 	b	21c <__libc_malloc_impl+0x21c>
 384:	90000000 	adrp	x0, 0 <__libc_malloc_impl>
			384: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context+0x378
 388:	910e6321 	add	x1, x25, #0x398
 38c:	91000000 	add	x0, x0, #0x0
			38c: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context+0x378
 390:	14000002 	b	398 <__libc_malloc_impl+0x398>
 394:	3800141f 	strb	wzr, [x0], #1
 398:	eb00003f 	cmp	x1, x0
 39c:	54ffffc1 	b.ne	394 <__libc_malloc_impl+0x394>  // b.any
 3a0:	52800020 	mov	w0, #0x1                   	// #1
 3a4:	17fffff1 	b	368 <__libc_malloc_impl+0x368>
 3a8:	aa1603e0 	mov	x0, x22
 3ac:	94000000 	bl	0 <__unlock>
			3ac: R_AARCH64_CALL26	__unlock
 3b0:	17ffff73 	b	17c <__libc_malloc_impl+0x17c>
 3b4:	aa1603e0 	mov	x0, x22
 3b8:	94000000 	bl	0 <__lock>
			3b8: R_AARCH64_CALL26	__lock
 3bc:	17ffff81 	b	1c0 <__libc_malloc_impl+0x1c0>
 3c0:	90000001 	adrp	x1, 0 <__libc_malloc_impl>
			3c0: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context+0x378
 3c4:	910e6322 	add	x2, x25, #0x398
 3c8:	91000021 	add	x1, x1, #0x0
			3c8: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context+0x378
 3cc:	14000002 	b	3d4 <__libc_malloc_impl+0x3d4>
 3d0:	3800143f 	strb	wzr, [x1], #1
 3d4:	eb01005f 	cmp	x2, x1
 3d8:	54ffffc1 	b.ne	3d0 <__libc_malloc_impl+0x3d0>  // b.any
 3dc:	52800020 	mov	w0, #0x1                   	// #1
 3e0:	17ffff7f 	b	1dc <__libc_malloc_impl+0x1dc>
 3e4:	b9400340 	ldr	w0, [x26]
			3e4: R_AARCH64_LDST32_ABS_LO12_NC	__malloc_lock
 3e8:	37f80120 	tbnz	w0, #31, 40c <__libc_malloc_impl+0x40c>
 3ec:	aa1703e1 	mov	x1, x23
 3f0:	aa1403e0 	mov	x0, x20
 3f4:	94000000 	bl	0 <munmap>
			3f4: R_AARCH64_CALL26	munmap
 3f8:	a94157f4 	ldp	x20, x21, [sp, #16]
 3fc:	a9425ff6 	ldp	x22, x23, [sp, #32]
 400:	a94367f8 	ldp	x24, x25, [sp, #48]
 404:	a9446ffa 	ldp	x26, x27, [sp, #64]
 408:	17ffff3a 	b	f0 <__libc_malloc_impl+0xf0>
 40c:	aa1603e0 	mov	x0, x22
 410:	94000000 	bl	0 <__unlock>
			410: R_AARCH64_CALL26	__unlock
 414:	17fffff6 	b	3ec <__libc_malloc_impl+0x3ec>
 418:	aa1603e0 	mov	x0, x22
 41c:	94000000 	bl	0 <__lock>
			41c: R_AARCH64_CALL26	__lock
 420:	17ffff20 	b	a0 <__libc_malloc_impl+0xa0>
 424:	2a1403e0 	mov	w0, w20
 428:	aa1303e1 	mov	x1, x19
 42c:	94000000 	bl	0 <__libc_malloc_impl>
			42c: R_AARCH64_CALL26	.text.alloc_slot
 430:	2a0003f4 	mov	w20, w0
 434:	3100041f 	cmn	w0, #0x1
 438:	540000c0 	b.eq	450 <__libc_malloc_impl+0x450>  // b.none
 43c:	91002ab5 	add	x21, x21, #0xa
 440:	b9400f37 	ldr	w23, [x25, #12]
 444:	93407c1b 	sxtw	x27, w0
 448:	f8757b38 	ldr	x24, [x25, x21, lsl #3]
 44c:	17ffff74 	b	21c <__libc_malloc_impl+0x21c>
 450:	b9400340 	ldr	w0, [x26]
			450: R_AARCH64_LDST32_ABS_LO12_NC	__malloc_lock
 454:	37f800c0 	tbnz	w0, #31, 46c <__libc_malloc_impl+0x46c>
 458:	a94157f4 	ldp	x20, x21, [sp, #16]
 45c:	a9425ff6 	ldp	x22, x23, [sp, #32]
 460:	a94367f8 	ldp	x24, x25, [sp, #48]
 464:	a9446ffa 	ldp	x26, x27, [sp, #64]
 468:	17ffff22 	b	f0 <__libc_malloc_impl+0xf0>
 46c:	aa1603e0 	mov	x0, x22
 470:	94000000 	bl	0 <__unlock>
			470: R_AARCH64_CALL26	__unlock
 474:	a94157f4 	ldp	x20, x21, [sp, #16]
 478:	a9425ff6 	ldp	x22, x23, [sp, #32]
 47c:	a94367f8 	ldp	x24, x25, [sp, #48]
 480:	a9446ffa 	ldp	x26, x27, [sp, #64]
 484:	17ffff1b 	b	f0 <__libc_malloc_impl+0xf0>
 488:	aa1603e0 	mov	x0, x22
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

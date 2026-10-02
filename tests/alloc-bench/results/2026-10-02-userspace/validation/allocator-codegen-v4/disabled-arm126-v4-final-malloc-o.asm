
/Users/alex/code/vinix/third_party/useralloc-libc/build/musl/aarch64/ff88d5a4ea1a8cd33bb50f215311de4767a7deaec49201e25be59abaed06a69c/objects/obj/src/malloc/mallocng/malloc.o:     file format elf64-littleaarch64


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
  9c:	b4003b60 	cbz	x0, 808 <alloc_slot+0x808>
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
  c4:	8b000022 	add	x2, x1, x0
  c8:	38606833 	ldrb	w19, [x1, x0]
  cc:	d37e1e60 	ubfiz	x0, x19, #2, #8
  d0:	eb00007f 	cmp	x3, x0
  d4:	540011a2 	b.cs	308 <alloc_slot+0x308>  // b.hs, b.nlast
  d8:	39400453 	ldrb	w19, [x2, #1]
  dc:	d37e1e60 	ubfiz	x0, x19, #2, #8
  e0:	eb03001f 	cmp	x0, x3
  e4:	54001129 	b.ls	308 <alloc_slot+0x308>  // b.plast
  e8:	39400853 	ldrb	w19, [x2, #2]
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
 2d4:	3861c813 	ldrb	w19, [x0, w1, sxtw]
 2d8:	14000002 	b	2e0 <alloc_slot+0x2e0>
 2dc:	13017e73 	asr	w19, w19, #1
 2e0:	37000093 	tbnz	w19, #0, 2f0 <alloc_slot+0x2f0>
 2e4:	531e7660 	lsl	w0, w19, #2
 2e8:	eb20c07f 	cmp	x3, w0, sxtw
 2ec:	54ffff83 	b.cc	2dc <alloc_slot+0x2dc>  // b.lo, b.ul, b.last
 2f0:	b2404fe1 	mov	x1, #0xfffff               	// #1048575
 2f4:	14000002 	b	2fc <alloc_slot+0x2fc>
 2f8:	13017e73 	asr	w19, w19, #1
 2fc:	9bb37ee0 	umull	x0, w23, w19
 300:	eb01001f 	cmp	x0, x1
 304:	54ffffa8 	b.hi	2f8 <alloc_slot+0x2f8>  // b.pmore
 308:	d341fc80 	lsr	x0, x4, #1
 30c:	93407e7a 	sxtw	x26, w19
 310:	7100067f 	cmp	w19, #0x1
 314:	54000260 	b.eq	360 <alloc_slot+0x360>  // b.none
 318:	9bba7f86 	umull	x6, w28, w26
 31c:	910040c1 	add	x1, x6, #0x10
 320:	eb00003f 	cmp	x1, x0
 324:	54001949 	b.ls	64c <alloc_slot+0x64c>  // b.plast
 328:	531e7665 	lsl	w5, w19, #2
 32c:	93407ca5 	sxtw	x5, w5
 330:	51001ea0 	sub	w0, w21, #0x7
 334:	394ee2c2 	ldrb	w2, [x22, #952]
 338:	71007c1f 	cmp	w0, #0x1f
 33c:	54000368 	b.hi	3a8 <alloc_slot+0x3a8>  // b.pmore
 340:	8b20c2c0 	add	x0, x22, w0, sxtw
 344:	394de001 	ldrb	w1, [x0, #888]
 348:	394e6007 	ldrb	w7, [x0, #920]
 34c:	350001c1 	cbnz	w1, 384 <alloc_slot+0x384>
 350:	71018cff 	cmp	w7, #0x63
 354:	1a9f97e1 	cset	w1, hi	// hi = pmore
 358:	1a9f87e7 	cset	w7, ls	// ls = plast
 35c:	14000015 	b	3b0 <alloc_slot+0x3b0>
 360:	910042e1 	add	x1, x23, #0x10
 364:	eb00003f 	cmp	x1, x0
 368:	54000088 	b.hi	378 <alloc_slot+0x378>  // b.pmore
 36c:	d280005a 	mov	x26, #0x2                   	// #2
 370:	2a1a03f3 	mov	w19, w26
 374:	17ffffe9 	b	318 <alloc_slot+0x318>
 378:	aa1703e6 	mov	x6, x23
 37c:	d2800085 	mov	x5, #0x4                   	// #4
 380:	17ffffec 	b	330 <alloc_slot+0x330>
 384:	4b010041 	sub	w1, w2, w1
 388:	7100243f 	cmp	w1, #0x9
 38c:	54fffe2c 	b.gt	350 <alloc_slot+0x350>
 390:	71018cff 	cmp	w7, #0x63
 394:	110004e8 	add	w8, w7, #0x1
 398:	12800d21 	mov	w1, #0xffffff96            	// #-106
 39c:	1a882021 	csel	w1, w1, w8, cs	// cs = hs, nlast
 3a0:	390e6001 	strb	w1, [x0, #920]
 3a4:	17ffffeb 	b	350 <alloc_slot+0x350>
 3a8:	52800001 	mov	w1, #0x0                   	// #0
 3ac:	52800027 	mov	w7, #0x1                   	// #1
 3b0:	11000440 	add	w0, w2, #0x1
 3b4:	12001c00 	and	w0, w0, #0xff
 3b8:	7103fc5f 	cmp	w2, #0xff
 3bc:	54000300 	b.eq	41c <alloc_slot+0x41c>  // b.none
 3c0:	390ee2c0 	strb	w0, [x22, #952]
 3c4:	d1000488 	sub	x8, x4, #0x1
 3c8:	37000455 	tbnz	w21, #0, 450 <alloc_slot+0x450>
 3cc:	71007ebf 	cmp	w21, #0x1f
 3d0:	5400038c 	b.gt	440 <alloc_slot+0x440>
 3d4:	110006a0 	add	w0, w21, #0x1
 3d8:	710000ff 	cmp	w7, #0x0
 3dc:	8b20cec0 	add	x0, x22, w0, sxtw #3
 3e0:	f940fc00 	ldr	x0, [x0, #504]
 3e4:	8b000063 	add	x3, x3, x0
 3e8:	fa451062 	ccmp	x3, x5, #0x2, ne	// ne = any
 3ec:	54000382 	b.cs	45c <alloc_slot+0x45c>  // b.hs, b.nlast
 3f0:	120006a0 	and	w0, w21, #0x3
 3f4:	7100081f 	cmp	w0, #0x2
 3f8:	54001120 	b.eq	61c <alloc_slot+0x61c>  // b.none
 3fc:	eb040cdf 	cmp	x6, x4, lsl #3
 400:	54001128 	b.hi	624 <alloc_slot+0x624>  // b.pmore
 404:	eb0404df 	cmp	x6, x4, lsl #1
 408:	540002a9 	b.ls	45c <alloc_slot+0x45c>  // b.plast
 40c:	d28000a0 	mov	x0, #0x5                   	// #5
 410:	52800022 	mov	w2, #0x1                   	// #1
 414:	2a0003f3 	mov	w19, w0
 418:	14000014 	b	468 <alloc_slot+0x468>
 41c:	90000002 	adrp	x2, 0 <alloc_slot>
			41c: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context+0x378
 420:	910e62c0 	add	x0, x22, #0x398
 424:	91000042 	add	x2, x2, #0x0
			424: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context+0x378
 428:	14000002 	b	430 <alloc_slot+0x430>
 42c:	3800145f 	strb	wzr, [x2], #1
 430:	eb00005f 	cmp	x2, x0
 434:	54ffffc1 	b.ne	42c <alloc_slot+0x42c>  // b.any
 438:	52800020 	mov	w0, #0x1                   	// #1
 43c:	17ffffe1 	b	3c0 <alloc_slot+0x3c0>
 440:	710000ff 	cmp	w7, #0x0
 444:	fa451062 	ccmp	x3, x5, #0x2, ne	// ne = any
 448:	540000a2 	b.cs	45c <alloc_slot+0x45c>  // b.hs, b.nlast
 44c:	17ffffe9 	b	3f0 <alloc_slot+0x3f0>
 450:	710000ff 	cmp	w7, #0x0
 454:	fa451062 	ccmp	x3, x5, #0x2, ne	// ne = any
 458:	54000a83 	b.cc	5a8 <alloc_slot+0x5a8>  // b.lo, b.ul, b.last
 45c:	71001e7f 	cmp	w19, #0x7
 460:	93407e60 	sxtw	x0, w19
 464:	1a9fc7e2 	cset	w2, le
 468:	9ba07f80 	umull	x0, w28, w0
 46c:	928001fa 	mov	x26, #0xfffffffffffffff0    	// #-16
 470:	52000021 	eor	w1, w1, #0x1
 474:	cb00035a 	sub	x26, x26, x0
 478:	91004000 	add	x0, x0, #0x10
 47c:	8a08035a 	and	x26, x26, x8
 480:	8b00035a 	add	x26, x26, x0
 484:	6a01005f 	tst	w2, w1
 488:	54000aa1 	b.ne	5dc <alloc_slot+0x5dc>  // b.any
 48c:	aa1a03e1 	mov	x1, x26
 490:	d2800005 	mov	x5, #0x0                   	// #0
 494:	12800004 	mov	w4, #0xffffffff            	// #-1
 498:	52800443 	mov	w3, #0x22                  	// #34
 49c:	52800062 	mov	w2, #0x3                   	// #3
 4a0:	d2800000 	mov	x0, #0x0                   	// #0
 4a4:	94000000 	bl	0 <__mmap>
			4a4: R_AARCH64_CALL26	__mmap
 4a8:	b100041f 	cmn	x0, #0x1
 4ac:	54001980 	b.eq	7dc <alloc_slot+0x7dc>  // b.none
 4b0:	d281fe02 	mov	x2, #0xff0                 	// #4080
 4b4:	d34cff45 	lsr	x5, x26, #12
 4b8:	f9401284 	ldr	x4, [x20, #32]
 4bc:	51000663 	sub	w3, w19, #0x1
 4c0:	9ad70841 	udiv	x1, x2, x23
 4c4:	93407e7a 	sxtw	x26, w19
 4c8:	b374cca4 	bfi	x4, x5, #12, #52
 4cc:	f9001284 	str	x4, [x20, #32]
 4d0:	51000421 	sub	w1, w1, #0x1
 4d4:	b9400ec2 	ldr	w2, [x22, #12]
 4d8:	6b13003f 	cmp	w1, w19
 4dc:	1a83b021 	csel	w1, w1, w3, lt	// lt = tstop
 4e0:	11000442 	add	w2, w2, #0x1
 4e4:	b9000ec2 	str	w2, [x22, #12]
 4e8:	0aa17c22 	bic	w2, w1, w1, asr #31
 4ec:	8b180ec4 	add	x4, x22, x24, lsl #3
 4f0:	52800041 	mov	w1, #0x2                   	// #2
 4f4:	1ac22025 	lsl	w5, w1, w2
 4f8:	510004a5 	sub	w5, w5, #0x1
 4fc:	1ac32021 	lsl	w1, w1, w3
 500:	120016b5 	and	w21, w21, #0x3f
 504:	f940fc86 	ldr	x6, [x4, #504]
 508:	12001063 	and	w3, w3, #0x1f
 50c:	321b0063 	orr	w3, w3, #0x20
 510:	8b1a00c6 	add	x6, x6, x26
 514:	f900fc86 	str	x6, [x4, #504]
 518:	b9001a85 	str	w5, [x20, #24]
 51c:	2a151863 	orr	w3, w3, w21, lsl #6
 520:	f9000a80 	str	x0, [x20, #16]
 524:	b9401a84 	ldr	w4, [x20, #24]
 528:	4b040021 	sub	w1, w1, w4
 52c:	51000421 	sub	w1, w1, #0x1
 530:	b9001e81 	str	w1, [x20, #28]
 534:	f9000014 	str	x20, [x0]
 538:	f9400a80 	ldr	x0, [x20, #16]
 53c:	39402001 	ldrb	w1, [x0, #8]
 540:	33001041 	bfxil	w1, w2, #0, #5
 544:	39002001 	strb	w1, [x0, #8]
 548:	79404280 	ldrh	w0, [x20, #32]
 54c:	f9400682 	ldr	x2, [x20, #8]
 550:	12144c00 	and	w0, w0, #0xfffff000
 554:	b9401a81 	ldr	w1, [x20, #24]
 558:	2a000060 	orr	w0, w3, w0
 55c:	79004280 	strh	w0, [x20, #32]
 560:	51000420 	sub	w0, w1, #0x1
 564:	b9001a80 	str	w0, [x20, #24]
 568:	b5ffe6a2 	cbnz	x2, 23c <alloc_slot+0x23c>
 56c:	f9400280 	ldr	x0, [x20]
 570:	b5ffe660 	cbnz	x0, 23c <alloc_slot+0x23c>
 574:	91002b18 	add	x24, x24, #0xa
 578:	f8787ac0 	ldr	x0, [x22, x24, lsl #3]
 57c:	b4001760 	cbz	x0, 868 <alloc_slot+0x868>
 580:	f9000680 	str	x0, [x20, #8]
 584:	f9400000 	ldr	x0, [x0]
 588:	f9000280 	str	x0, [x20]
 58c:	f9000414 	str	x20, [x0, #8]
 590:	f9400680 	ldr	x0, [x20, #8]
 594:	f9000014 	str	x20, [x0]
 598:	f9402bfc 	ldr	x28, [sp, #80]
 59c:	52800000 	mov	w0, #0x0                   	// #0
 5a0:	a9446ffa 	ldp	x26, x27, [sp, #64]
 5a4:	17ffff44 	b	2b4 <alloc_slot+0x2b4>
 5a8:	120006a0 	and	w0, w21, #0x3
 5ac:	7100041f 	cmp	w0, #0x1
 5b0:	54fff561 	b.ne	45c <alloc_slot+0x45c>  // b.any
 5b4:	eb040cdf 	cmp	x6, x4, lsl #3
 5b8:	54fff529 	b.ls	45c <alloc_slot+0x45c>  // b.plast
 5bc:	2a1c03e0 	mov	w0, w28
 5c0:	928001fa 	mov	x26, #0xfffffffffffffff0    	// #-16
 5c4:	52800053 	mov	w19, #0x2                   	// #2
 5c8:	d37ff800 	lsl	x0, x0, #1
 5cc:	cb00035a 	sub	x26, x26, x0
 5d0:	91004000 	add	x0, x0, #0x10
 5d4:	8a08035a 	and	x26, x26, x8
 5d8:	8b00035a 	add	x26, x26, x0
 5dc:	92800260 	mov	x0, #0xffffffffffffffec    	// #-20
 5e0:	cb190000 	sub	x0, x0, x25
 5e4:	8a080000 	and	x0, x0, x8
 5e8:	91005339 	add	x25, x25, #0x14
 5ec:	8b190000 	add	x0, x0, x25
 5f0:	910042e1 	add	x1, x23, #0x10
 5f4:	eb01001f 	cmp	x0, x1
 5f8:	540001e3 	b.cc	634 <alloc_slot+0x634>  // b.lo, b.ul, b.last
 5fc:	eb04081f 	cmp	x0, x4, lsl #2
 600:	54fff463 	b.cc	48c <alloc_slot+0x48c>  // b.lo, b.ul, b.last
 604:	531f7a61 	lsl	w1, w19, #1
 608:	93407c21 	sxtw	x1, w1
 60c:	eb03003f 	cmp	x1, x3
 610:	9a80935a 	csel	x26, x26, x0, ls	// ls = plast
 614:	1a9f9673 	csinc	w19, w19, wzr, ls	// ls = plast
 618:	17ffff9d 	b	48c <alloc_slot+0x48c>
 61c:	eb0408df 	cmp	x6, x4, lsl #2
 620:	54fff1e9 	b.ls	45c <alloc_slot+0x45c>  // b.plast
 624:	d2800060 	mov	x0, #0x3                   	// #3
 628:	52800022 	mov	w2, #0x1                   	// #1
 62c:	2a0003f3 	mov	w19, w0
 630:	17ffff8e 	b	468 <alloc_slot+0x468>
 634:	aa0003fa 	mov	x26, x0
 638:	52800033 	mov	w19, #0x1                   	// #1
 63c:	17ffff94 	b	48c <alloc_slot+0x48c>
 640:	a9005294 	stp	x20, x20, [x20]
 644:	f9000ad4 	str	x20, [x22, #16]
 648:	14000070 	b	808 <alloc_slot+0x808>
 64c:	910030c1 	add	x1, x6, #0xc
 650:	d344fcd9 	lsr	x25, x6, #4
 654:	f10240df 	cmp	x6, #0x90
 658:	540001c9 	b.ls	690 <alloc_slot+0x690>  // b.plast
 65c:	91000720 	add	x0, x25, #0x1
 660:	528003d9 	mov	w25, #0x1e                  	// #30
 664:	5ac01002 	clz	w2, w0
 668:	4b020339 	sub	w25, w25, w2
 66c:	531e7739 	lsl	w25, w25, #2
 670:	11000723 	add	w3, w25, #0x1
 674:	11000b22 	add	w2, w25, #0x2
 678:	7863db63 	ldrh	w3, [x27, w3, sxtw #1]
 67c:	eb03001f 	cmp	x0, x3
 680:	1a998059 	csel	w25, w2, w25, hi	// hi = pmore
 684:	7879db62 	ldrh	w2, [x27, w25, sxtw #1]
 688:	eb02001f 	cmp	x0, x2
 68c:	1a999739 	cinc	w25, w25, hi	// hi = pmore
 690:	2a1903e0 	mov	w0, w25
 694:	97fffe5b 	bl	0 <alloc_slot>
 698:	2a0003e6 	mov	w6, w0
 69c:	3100041f 	cmn	w0, #0x1
 6a0:	540009e0 	b.eq	7dc <alloc_slot+0x7dc>  // b.none
 6a4:	8b39cec0 	add	x0, x22, w25, sxtw #3
 6a8:	7879db65 	ldrh	w5, [x27, w25, sxtw #1]
 6ac:	f9402807 	ldr	x7, [x0, #80]
 6b0:	531c6ca5 	lsl	w5, w5, #4
 6b4:	510010a5 	sub	w5, w5, #0x4
 6b8:	f94010e1 	ldr	x1, [x7, #32]
 6bc:	93407ca3 	sxtw	x3, w5
 6c0:	f13ffc3f 	cmp	x1, #0xfff
 6c4:	92401020 	and	x0, x1, #0x1f
 6c8:	fa408800 	ccmp	x0, #0x0, #0x0, hi	// hi = pmore
 6cc:	54000a60 	b.eq	818 <alloc_slot+0x818>  // b.none
 6d0:	53062c21 	ubfx	w1, w1, #6, #6
 6d4:	7861db61 	ldrh	w1, [x27, w1, sxtw #1]
 6d8:	d37c3c21 	ubfiz	x1, x1, #4, #16
 6dc:	f94008e2 	ldr	x2, [x7, #16]
 6e0:	93407cc0 	sxtw	x0, w6
 6e4:	cb030023 	sub	x3, x1, x3
 6e8:	d1001029 	sub	x9, x1, #0x4
 6ec:	91004042 	add	x2, x2, #0x10
 6f0:	d1001063 	sub	x3, x3, #0x4
 6f4:	d344fc68 	lsr	x8, x3, #4
 6f8:	9b010800 	madd	x0, x0, x1, x2
 6fc:	8b090009 	add	x9, x0, x9
 700:	385fd001 	ldurb	w1, [x0, #-3]
 704:	34000901 	cbz	w1, 824 <alloc_slot+0x824>
 708:	785fe004 	ldurh	w4, [x0, #-2]
 70c:	11000484 	add	w4, w4, #0x1
 710:	12001c84 	and	w4, w4, #0xff
 714:	385fc001 	ldurb	w1, [x0, #-4]
 718:	35ffd921 	cbnz	w1, 23c <alloc_slot+0x23c>
 71c:	eb24c11f 	cmp	x8, w4, sxtw
 720:	54000162 	b.cs	74c <alloc_slot+0x74c>  // b.hs, b.nlast
 724:	aa431501 	orr	x1, x8, x3, lsr #5
 728:	aa410821 	orr	x1, x1, x1, lsr #2
 72c:	aa411021 	orr	x1, x1, x1, lsr #4
 730:	0a010084 	and	w4, w4, w1
 734:	eb24c11f 	cmp	x8, w4, sxtw
 738:	540000a2 	b.cs	74c <alloc_slot+0x74c>  // b.hs, b.nlast
 73c:	4b080084 	sub	w4, w4, w8
 740:	51000484 	sub	w4, w4, #0x1
 744:	eb24c11f 	cmp	x8, w4, sxtw
 748:	54ffd7a3 	b.cc	23c <alloc_slot+0x23c>  // b.lo, b.ul, b.last
 74c:	34000124 	cbz	w4, 770 <alloc_slot+0x770>
 750:	531c6c81 	lsl	w1, w4, #4
 754:	128003e2 	mov	w2, #0xffffffe0            	// #-32
 758:	381fd002 	sturb	w2, [x0, #-3]
 75c:	781fe004 	sturh	w4, [x0, #-2]
 760:	8b21c000 	add	x0, x0, w1, sxtw
 764:	381fc01f 	sturb	wzr, [x0, #-4]
 768:	f94008e2 	ldr	x2, [x7, #16]
 76c:	91004042 	add	x2, x2, #0x10
 770:	cb020001 	sub	x1, x0, x2
 774:	12001cc2 	and	w2, w6, #0xff
 778:	381fd002 	sturb	w2, [x0, #-3]
 77c:	cb000123 	sub	x3, x9, x0
 780:	d344fc21 	lsr	x1, x1, #4
 784:	781fe001 	sturh	w1, [x0, #-2]
 788:	6b050061 	subs	w1, w3, w5
 78c:	54000120 	b.eq	7b0 <alloc_slot+0x7b0>  // b.none
 790:	4b0103e2 	neg	w2, w1
 794:	3822c93f 	strb	wzr, [x9, w2, sxtw]
 798:	7100103f 	cmp	w1, #0x4
 79c:	5400048c 	b.gt	82c <alloc_slot+0x82c>
 7a0:	385fd002 	ldurb	w2, [x0, #-3]
 7a4:	12001042 	and	w2, w2, #0x1f
 7a8:	0b011441 	add	w1, w2, w1, lsl #5
 7ac:	12001c22 	and	w2, w1, #0xff
 7b0:	381fd002 	sturb	w2, [x0, #-3]
 7b4:	52800001 	mov	w1, #0x0                   	// #0
 7b8:	91003002 	add	x2, x0, #0xc
 7bc:	f9401283 	ldr	x3, [x20, #32]
 7c0:	92402c63 	and	x3, x3, #0xfff
 7c4:	f9001283 	str	x3, [x20, #32]
 7c8:	385fd003 	ldurb	w3, [x0, #-3]
 7cc:	12001063 	and	w3, w3, #0x1f
 7d0:	321a6463 	orr	w3, w3, #0xffffffc0
 7d4:	381fd003 	sturb	w3, [x0, #-3]
 7d8:	1400001f 	b	854 <alloc_slot+0x854>
 7dc:	a9007e9f 	stp	xzr, xzr, [x20]
 7e0:	a9017e9f 	stp	xzr, xzr, [x20, #16]
 7e4:	f9400ac0 	ldr	x0, [x22, #16]
 7e8:	f900129f 	str	xzr, [x20, #32]
 7ec:	b4fff2a0 	cbz	x0, 640 <alloc_slot+0x640>
 7f0:	f9000680 	str	x0, [x20, #8]
 7f4:	f9400000 	ldr	x0, [x0]
 7f8:	f9000280 	str	x0, [x20]
 7fc:	f9000414 	str	x20, [x0, #8]
 800:	f9400680 	ldr	x0, [x20, #8]
 804:	f9000014 	str	x20, [x0]
 808:	f9402bfc 	ldr	x28, [sp, #80]
 80c:	12800000 	mov	w0, #0xffffffff            	// #-1
 810:	a9446ffa 	ldp	x26, x27, [sp, #64]
 814:	17fffea8 	b	2b4 <alloc_slot+0x2b4>
 818:	9274cc21 	and	x1, x1, #0xfffffffffffff000
 81c:	d1004021 	sub	x1, x1, #0x10
 820:	17ffffaf 	b	6dc <alloc_slot+0x6dc>
 824:	394032c4 	ldrb	w4, [x22, #12]
 828:	17ffffbb 	b	714 <alloc_slot+0x714>
 82c:	381fb13f 	sturb	wzr, [x9, #-5]
 830:	b81fc121 	stur	w1, [x9, #-4]
 834:	385fd002 	ldurb	w2, [x0, #-3]
 838:	12001042 	and	w2, w2, #0x1f
 83c:	51018042 	sub	w2, w2, #0x60
 840:	12001c42 	and	w2, w2, #0xff
 844:	17ffffdb 	b	7b0 <alloc_slot+0x7b0>
 848:	11000421 	add	w1, w1, #0x1
 84c:	3900005f 	strb	wzr, [x2]
 850:	8b170042 	add	x2, x2, x23
 854:	6b01027f 	cmp	w19, w1
 858:	54ffff8a 	b.ge	848 <alloc_slot+0x848>  // b.tcont
 85c:	51000663 	sub	w3, w19, #0x1
 860:	2a0303e2 	mov	w2, w3
 864:	17ffff22 	b	4ec <alloc_slot+0x4ec>
 868:	a9005294 	stp	x20, x20, [x20]
 86c:	f8387ad4 	str	x20, [x22, x24, lsl #3]
 870:	17ffff4a 	b	598 <alloc_slot+0x598>

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
  90:	9000001a 	adrp	x26, 0 <__libc_malloc_impl>
			90: R_AARCH64_ADR_PREL_PG_HI21	__malloc_lock
  94:	91000357 	add	x23, x26, #0x0
			94: R_AARCH64_ADD_ABS_LO12_NC	__malloc_lock
  98:	39400c00 	ldrb	w0, [x0, #3]
  9c:	72001c1f 	tst	w0, #0xff
  a0:	54000e01 	b.ne	260 <__libc_malloc_impl+0x260>  // b.any
  a4:	93407e80 	sxtw	x0, w20
  a8:	90000001 	adrp	x1, 0 <__libc_malloc_impl>
			a8: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
  ac:	91002802 	add	x2, x0, #0xa
  b0:	91000039 	add	x25, x1, #0x0
			b0: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
  b4:	f8627b36 	ldr	x22, [x25, x2, lsl #3]
  b8:	f10002df 	cmp	x22, #0x0
  bc:	7a430a84 	ccmp	w20, #0x3, #0x4, eq	// eq = none
  c0:	54000e6d 	b.le	28c <__libc_malloc_impl+0x28c>
  c4:	71007e9f 	cmp	w20, #0x1f
  c8:	7a46da84 	ccmp	w20, #0x6, #0x4, le
  cc:	54000200 	b.eq	10c <__libc_malloc_impl+0x10c>  // b.none
  d0:	370001f4 	tbnz	w20, #0, 10c <__libc_malloc_impl+0x10c>
  d4:	8b000f20 	add	x0, x25, x0, lsl #3
  d8:	f940fc00 	ldr	x0, [x0, #504]
  dc:	b5000180 	cbnz	x0, 10c <__libc_malloc_impl+0x10c>
  e0:	32000281 	orr	w1, w20, #0x1
  e4:	93407c20 	sxtw	x0, w1
  e8:	91002802 	add	x2, x0, #0xa
  ec:	8b000f20 	add	x0, x25, x0, lsl #3
  f0:	f8627b36 	ldr	x22, [x25, x2, lsl #3]
  f4:	f940fc00 	ldr	x0, [x0, #504]
  f8:	b4000c36 	cbz	x22, 27c <__libc_malloc_impl+0x27c>
  fc:	b9401ac2 	ldr	w2, [x22, #24]
 100:	34000b62 	cbz	w2, 26c <__libc_malloc_impl+0x26c>
 104:	f100301f 	cmp	x0, #0xc
 108:	54001689 	b.ls	3d8 <__libc_malloc_impl+0x3d8>  // b.plast
 10c:	aa1303e1 	mov	x1, x19
 110:	2a1403e0 	mov	w0, w20
 114:	94000000 	bl	0 <__libc_malloc_impl>
			114: R_AARCH64_CALL26	.text.alloc_slot
 118:	2a0003f5 	mov	w21, w0
 11c:	3100041f 	cmn	w0, #0x1
 120:	54001600 	b.eq	3e0 <__libc_malloc_impl+0x3e0>  // b.none
 124:	8b34cf20 	add	x0, x25, w20, sxtw #3
 128:	93407eb8 	sxtw	x24, w21
 12c:	b9400f34 	ldr	w20, [x25, #12]
 130:	f9402816 	ldr	x22, [x0, #80]
 134:	14000061 	b	2b8 <__libc_malloc_impl+0x2b8>
 138:	94000000 	bl	0 <___errno_location>
			138: R_AARCH64_CALL26	___errno_location
 13c:	52800181 	mov	w1, #0xc                   	// #12
 140:	b9000001 	str	w1, [x0]
 144:	d2800000 	mov	x0, #0x0                   	// #0
 148:	140000a2 	b	3d0 <__libc_malloc_impl+0x3d0>
 14c:	d2820260 	mov	x0, #0x1013                	// #4115
 150:	91005278 	add	x24, x19, #0x14
 154:	8b000275 	add	x21, x19, x0
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
 17c:	54001360 	b.eq	3e8 <__libc_malloc_impl+0x3e8>  // b.none
 180:	90000000 	adrp	x0, 0 <__libc>
			180: R_AARCH64_ADR_PREL_PG_HI21	__libc
 184:	91000000 	add	x0, x0, #0x0
			184: R_AARCH64_ADD_ABS_LO12_NC	__libc
 188:	9000001a 	adrp	x26, 0 <__libc_malloc_impl>
			188: R_AARCH64_ADR_PREL_PG_HI21	__malloc_lock
 18c:	91000357 	add	x23, x26, #0x0
			18c: R_AARCH64_ADD_ABS_LO12_NC	__malloc_lock
 190:	39400c00 	ldrb	w0, [x0, #3]
 194:	72001c1f 	tst	w0, #0xff
 198:	54000321 	b.ne	1fc <__libc_malloc_impl+0x1fc>  // b.any
 19c:	90000001 	adrp	x1, 0 <__libc_malloc_impl>
			19c: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context
 1a0:	91000039 	add	x25, x1, #0x0
			1a0: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context
 1a4:	394ee321 	ldrb	w1, [x25, #952]
 1a8:	11000420 	add	w0, w1, #0x1
 1ac:	12001c00 	and	w0, w0, #0xff
 1b0:	7103fc3f 	cmp	w1, #0xff
 1b4:	540002a0 	b.eq	208 <__libc_malloc_impl+0x208>  // b.none
 1b8:	390ee320 	strb	w0, [x25, #952]
 1bc:	94000000 	bl	0 <__libc_malloc_impl>
			1bc: R_AARCH64_CALL26	__malloc_alloc_meta
 1c0:	aa0003f6 	mov	x22, x0
 1c4:	b4000340 	cbz	x0, 22c <__libc_malloc_impl+0x22c>
 1c8:	f9000ad4 	str	x20, [x22, #16]
 1cc:	9274ceb5 	and	x21, x21, #0xfffffffffffff000
 1d0:	f9000296 	str	x22, [x20]
 1d4:	b27b1aa0 	orr	x0, x21, #0xfe0
 1d8:	b9001edf 	str	wzr, [x22, #28]
 1dc:	d2800018 	mov	x24, #0x0                   	// #0
 1e0:	b9400f22 	ldr	w2, [x25, #12]
 1e4:	52800015 	mov	w21, #0x0                   	// #0
 1e8:	b9001adf 	str	wzr, [x22, #24]
 1ec:	11000454 	add	w20, w2, #0x1
 1f0:	b9000f34 	str	w20, [x25, #12]
 1f4:	f90012c0 	str	x0, [x22, #32]
 1f8:	14000030 	b	2b8 <__libc_malloc_impl+0x2b8>
 1fc:	aa1703e0 	mov	x0, x23
 200:	94000000 	bl	0 <__lock>
			200: R_AARCH64_CALL26	__lock
 204:	17ffffe6 	b	19c <__libc_malloc_impl+0x19c>
 208:	90000002 	adrp	x2, 0 <__libc_malloc_impl>
			208: R_AARCH64_ADR_PREL_PG_HI21	__malloc_context+0x378
 20c:	910e6321 	add	x1, x25, #0x398
 210:	91000042 	add	x2, x2, #0x0
			210: R_AARCH64_ADD_ABS_LO12_NC	__malloc_context+0x378
 214:	14000002 	b	21c <__libc_malloc_impl+0x21c>
 218:	3800145f 	strb	wzr, [x2], #1
 21c:	eb02003f 	cmp	x1, x2
 220:	54ffffc1 	b.ne	218 <__libc_malloc_impl+0x218>  // b.any
 224:	52800020 	mov	w0, #0x1                   	// #1
 228:	17ffffe4 	b	1b8 <__libc_malloc_impl+0x1b8>
 22c:	b9400340 	ldr	w0, [x26]
			22c: R_AARCH64_LDST32_ABS_LO12_NC	__malloc_lock
 230:	37f80120 	tbnz	w0, #31, 254 <__libc_malloc_impl+0x254>
 234:	aa1803e1 	mov	x1, x24
 238:	aa1403e0 	mov	x0, x20
 23c:	94000000 	bl	0 <munmap>
			23c: R_AARCH64_CALL26	munmap
 240:	f94023fa 	ldr	x26, [sp, #64]
 244:	a94157f4 	ldp	x20, x21, [sp, #16]
 248:	a9425ff6 	ldp	x22, x23, [sp, #32]
 24c:	a94367f8 	ldp	x24, x25, [sp, #48]
 250:	17ffffbd 	b	144 <__libc_malloc_impl+0x144>
 254:	aa1703e0 	mov	x0, x23
 258:	94000000 	bl	0 <__unlock>
			258: R_AARCH64_CALL26	__unlock
 25c:	17fffff6 	b	234 <__libc_malloc_impl+0x234>
 260:	aa1703e0 	mov	x0, x23
 264:	94000000 	bl	0 <__lock>
			264: R_AARCH64_CALL26	__lock
 268:	17ffff8f 	b	a4 <__libc_malloc_impl+0xa4>
 26c:	b9401ec2 	ldr	w2, [x22, #28]
 270:	35fff4a2 	cbnz	w2, 104 <__libc_malloc_impl+0x104>
 274:	91000c00 	add	x0, x0, #0x3
 278:	17ffffa3 	b	104 <__libc_malloc_impl+0x104>
 27c:	91000c00 	add	x0, x0, #0x3
 280:	f100301f 	cmp	x0, #0xc
 284:	1a818294 	csel	w20, w20, w1, hi	// hi = pmore
 288:	17ffffa1 	b	10c <__libc_malloc_impl+0x10c>
 28c:	b4fff416 	cbz	x22, 10c <__libc_malloc_impl+0x10c>
 290:	b9401ac0 	ldr	w0, [x22, #24]
 294:	4b0003e2 	neg	w2, w0
 298:	6a000042 	ands	w2, w2, w0
 29c:	54fff380 	b.eq	10c <__libc_malloc_impl+0x10c>  // b.none
 2a0:	5ac00055 	rbit	w21, w2
 2a4:	b9400f34 	ldr	w20, [x25, #12]
 2a8:	5ac012b5 	clz	w21, w21
 2ac:	4b020000 	sub	w0, w0, w2
 2b0:	b9001ac0 	str	w0, [x22, #24]
 2b4:	93407eb8 	sxtw	x24, w21
 2b8:	b9400340 	ldr	w0, [x26]
			2b8: R_AARCH64_LDST32_ABS_LO12_NC	__malloc_lock
 2bc:	37f80ae0 	tbnz	w0, #31, 418 <__libc_malloc_impl+0x418>
 2c0:	f94012c3 	ldr	x3, [x22, #32]
 2c4:	f13ffc7f 	cmp	x3, #0xfff
 2c8:	92401060 	and	x0, x3, #0x1f
 2cc:	fa408800 	ccmp	x0, #0x0, #0x0, hi	// hi = pmore
 2d0:	54000aa0 	b.eq	424 <__libc_malloc_impl+0x424>  // b.none
 2d4:	53062c63 	ubfx	w3, w3, #6, #6
 2d8:	90000000 	adrp	x0, 0 <__libc_malloc_impl>
			2d8: R_AARCH64_ADR_PREL_PG_HI21	__malloc_size_classes
 2dc:	91000000 	add	x0, x0, #0x0
			2dc: R_AARCH64_ADD_ABS_LO12_NC	__malloc_size_classes
 2e0:	7863d803 	ldrh	w3, [x0, w3, sxtw #1]
 2e4:	d37c3c63 	ubfiz	x3, x3, #4, #16
 2e8:	f9400ac1 	ldr	x1, [x22, #16]
 2ec:	cb130064 	sub	x4, x3, x19
 2f0:	d1001065 	sub	x5, x3, #0x4
 2f4:	d1001084 	sub	x4, x4, #0x4
 2f8:	91004021 	add	x1, x1, #0x10
 2fc:	12001e82 	and	w2, w20, #0xff
 300:	d344fc86 	lsr	x6, x4, #4
 304:	9b180460 	madd	x0, x3, x24, x1
 308:	8b050005 	add	x5, x0, x5
 30c:	385fd003 	ldurb	w3, [x0, #-3]
 310:	34000083 	cbz	w3, 320 <__libc_malloc_impl+0x320>
 314:	785fe002 	ldurh	w2, [x0, #-2]
 318:	11000442 	add	w2, w2, #0x1
 31c:	12001c42 	and	w2, w2, #0xff
 320:	385fc003 	ldurb	w3, [x0, #-4]
 324:	35000863 	cbnz	w3, 430 <__libc_malloc_impl+0x430>
 328:	eb22c0df 	cmp	x6, w2, sxtw
 32c:	54000162 	b.cs	358 <__libc_malloc_impl+0x358>  // b.hs, b.nlast
 330:	aa4414c4 	orr	x4, x6, x4, lsr #5
 334:	aa440884 	orr	x4, x4, x4, lsr #2
 338:	aa441084 	orr	x4, x4, x4, lsr #4
 33c:	0a040042 	and	w2, w2, w4
 340:	eb22c0df 	cmp	x6, w2, sxtw
 344:	540000a2 	b.cs	358 <__libc_malloc_impl+0x358>  // b.hs, b.nlast
 348:	4b060042 	sub	w2, w2, w6
 34c:	51000442 	sub	w2, w2, #0x1
 350:	eb22c0df 	cmp	x6, w2, sxtw
 354:	540006e3 	b.cc	430 <__libc_malloc_impl+0x430>  // b.lo, b.ul, b.last
 358:	34000122 	cbz	w2, 37c <__libc_malloc_impl+0x37c>
 35c:	531c6c41 	lsl	w1, w2, #4
 360:	128003e3 	mov	w3, #0xffffffe0            	// #-32
 364:	381fd003 	sturb	w3, [x0, #-3]
 368:	781fe002 	sturh	w2, [x0, #-2]
 36c:	8b21c000 	add	x0, x0, w1, sxtw
 370:	381fc01f 	sturb	wzr, [x0, #-4]
 374:	f9400ac1 	ldr	x1, [x22, #16]
 378:	91004021 	add	x1, x1, #0x10
 37c:	cb010001 	sub	x1, x0, x1
 380:	12001ea2 	and	w2, w21, #0xff
 384:	381fd002 	sturb	w2, [x0, #-3]
 388:	cb0000a3 	sub	x3, x5, x0
 38c:	d344fc21 	lsr	x1, x1, #4
 390:	781fe001 	sturh	w1, [x0, #-2]
 394:	6b130061 	subs	w1, w3, w19
 398:	54000120 	b.eq	3bc <__libc_malloc_impl+0x3bc>  // b.none
 39c:	4b0103e2 	neg	w2, w1
 3a0:	3822c8bf 	strb	wzr, [x5, w2, sxtw]
 3a4:	7100103f 	cmp	w1, #0x4
 3a8:	5400046c 	b.gt	434 <__libc_malloc_impl+0x434>
 3ac:	385fd002 	ldurb	w2, [x0, #-3]
 3b0:	12001042 	and	w2, w2, #0x1f
 3b4:	0b011441 	add	w1, w2, w1, lsl #5
 3b8:	12001c22 	and	w2, w1, #0xff
 3bc:	381fd002 	sturb	w2, [x0, #-3]
 3c0:	a94157f4 	ldp	x20, x21, [sp, #16]
 3c4:	a9425ff6 	ldp	x22, x23, [sp, #32]
 3c8:	a94367f8 	ldp	x24, x25, [sp, #48]
 3cc:	f94023fa 	ldr	x26, [sp, #64]
 3d0:	a8c54ffe 	ldp	x30, x19, [sp], #80
 3d4:	d65f03c0 	ret
 3d8:	2a0103f4 	mov	w20, w1
 3dc:	17ffffad 	b	290 <__libc_malloc_impl+0x290>
 3e0:	b9400340 	ldr	w0, [x26]
			3e0: R_AARCH64_LDST32_ABS_LO12_NC	__malloc_lock
 3e4:	37f800c0 	tbnz	w0, #31, 3fc <__libc_malloc_impl+0x3fc>
 3e8:	f94023fa 	ldr	x26, [sp, #64]
 3ec:	a94157f4 	ldp	x20, x21, [sp, #16]
 3f0:	a9425ff6 	ldp	x22, x23, [sp, #32]
 3f4:	a94367f8 	ldp	x24, x25, [sp, #48]
 3f8:	17ffff53 	b	144 <__libc_malloc_impl+0x144>
 3fc:	aa1703e0 	mov	x0, x23
 400:	94000000 	bl	0 <__unlock>
			400: R_AARCH64_CALL26	__unlock
 404:	f94023fa 	ldr	x26, [sp, #64]
 408:	a94157f4 	ldp	x20, x21, [sp, #16]
 40c:	a9425ff6 	ldp	x22, x23, [sp, #32]
 410:	a94367f8 	ldp	x24, x25, [sp, #48]
 414:	17ffff4c 	b	144 <__libc_malloc_impl+0x144>
 418:	aa1703e0 	mov	x0, x23
 41c:	94000000 	bl	0 <__unlock>
			41c: R_AARCH64_CALL26	__unlock
 420:	17ffffa8 	b	2c0 <__libc_malloc_impl+0x2c0>
 424:	9274cc63 	and	x3, x3, #0xfffffffffffff000
 428:	d1004063 	sub	x3, x3, #0x10
 42c:	17ffffaf 	b	2e8 <__libc_malloc_impl+0x2e8>
 430:	d4207d00 	brk	#0x3e8
 434:	381fb0bf 	sturb	wzr, [x5, #-5]
 438:	b81fc0a1 	stur	w1, [x5, #-4]
 43c:	385fd002 	ldurb	w2, [x0, #-3]
 440:	12001042 	and	w2, w2, #0x1f
 444:	51018042 	sub	w2, w2, #0x60
 448:	12001c42 	and	w2, w2, #0xff
 44c:	17ffffdc 	b	3bc <__libc_malloc_impl+0x3bc>

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


build/alloc-bench-validation/vinix-aarch64-selftest:	file format elf64-littleaarch64

Disassembly of section .text:

ffffffff8011249c <memory__Slab__sfree>:
ffffffff8011249c: d10443ff     	sub	sp, sp, #0x110
ffffffff801124a0: a90b7bfd     	stp	x29, x30, [sp, #0xb0]
ffffffff801124a4: a90c6ffc     	stp	x28, x27, [sp, #0xc0]
ffffffff801124a8: a90d67fa     	stp	x26, x25, [sp, #0xd0]
ffffffff801124ac: a90e5ff8     	stp	x24, x23, [sp, #0xe0]
ffffffff801124b0: a90f57f6     	stp	x22, x21, [sp, #0xf0]
ffffffff801124b4: a9104ff4     	stp	x20, x19, [sp, #0x100]
ffffffff801124b8: 9102c3fd     	add	x29, sp, #0xb0
ffffffff801124bc: d0000628     	adrp	x8, 0xffffffff801d8000 <halt_at_stage>
ffffffff801124c0: f9417908     	ldr	x8, [x8, #0x2f0]
ffffffff801124c4: f81f03a8     	stur	x8, [x29, #-0x10]
ffffffff801124c8: b40017e1     	cbz	x1, 0xffffffff801127c4 <memory__Slab__sfree+0x328>
ffffffff801124cc: aa0103f4     	mov	x20, x1
ffffffff801124d0: aa0003f3     	mov	x19, x0
ffffffff801124d4: 52800035     	mov	w21, #0x1       // =1
ffffffff801124d8: 14000003     	b	0xffffffff801124e4 <memory__Slab__sfree+0x48>
ffffffff801124dc: d5034fdf     	msr	DAIFSet, #0xf
ffffffff801124e0: d503205f     	wfe
ffffffff801124e4: d53b4236     	mrs	x22, DAIF
ffffffff801124e8: d5034fdf     	msr	DAIFSet, #0xf
ffffffff801124ec: 910023e0     	add	x0, sp, #0x8
ffffffff801124f0: 9100a3e1     	add	x1, sp, #0x28
ffffffff801124f4: 52800102     	mov	w2, #0x8        // =8
ffffffff801124f8: f90017ff     	str	xzr, [sp, #0x28]
ffffffff801124fc: a900d7ff     	stp	xzr, x21, [sp, #0x8]
ffffffff80112500: f90003ff     	str	xzr, [sp]
ffffffff80112504: 94025e06     	bl	0xffffffff801a9d1c <memcpy>
ffffffff80112508: 910003e0     	mov	x0, sp
ffffffff8011250c: 910043e1     	add	x1, sp, #0x10
ffffffff80112510: 52800102     	mov	w2, #0x8        // =8
ffffffff80112514: 94025e02     	bl	0xffffffff801a9d1c <memcpy>
ffffffff80112518: a94007e2     	ldp	x2, x1, [sp]
ffffffff8011251c: aa1303e0     	mov	x0, x19
ffffffff80112520: 94026d48     	bl	0xffffffff801ada40 <vinix_casa64>
ffffffff80112524: f94007e8     	ldr	x8, [sp, #0x8]
ffffffff80112528: eb08001f     	cmp	x0, x8
ffffffff8011252c: 540000c0     	b.eq	0xffffffff80112544 <memory__Slab__sfree+0xa8>
ffffffff80112530: d53b4228     	mrs	x8, DAIF
ffffffff80112534: 373ffd56     	tbnz	w22, #0x7, 0xffffffff801124dc <memory__Slab__sfree+0x40>
ffffffff80112538: d5034fff     	msr	DAIFClr, #0xf
ffffffff8011253c: d503205f     	wfe
ffffffff80112540: 17ffffe9     	b	0xffffffff801124e4 <memory__Slab__sfree+0x48>
ffffffff80112544: d0000628     	adrp	x8, 0xffffffff801d8000 <halt_at_stage>
ffffffff80112548: f27902df     	tst	x22, #0x80
ffffffff8011254c: f9401908     	ldr	x8, [x8, #0x30]
ffffffff80112550: 1a9f17e9     	cset	w9, eq
ffffffff80112554: 39002269     	strb	w9, [x19, #0x8]
ffffffff80112558: cb0803ea     	neg	x10, x8
ffffffff8011255c: 8a140159     	and	x25, x10, x20
ffffffff80112560: d289884a     	mov	x10, #0x4c42    // =19522
ffffffff80112564: f2ab0a6a     	movk	x10, #0x5853, lsl #16
ffffffff80112568: f9400729     	ldr	x9, [x25, #0x8]
ffffffff8011256c: f2c9c92a     	movk	x10, #0x4e49, lsl #32
ffffffff80112570: f2eac92a     	movk	x10, #0x5649, lsl #48
ffffffff80112574: eb0a013f     	cmp	x9, x10
ffffffff80112578: 54001401     	b.ne	0xffffffff801127f8 <memory__Slab__sfree+0x35c>
ffffffff8011257c: f9400329     	ldr	x9, [x25]
ffffffff80112580: eb13013f     	cmp	x9, x19
ffffffff80112584: 540013a1     	b.ne	0xffffffff801127f8 <memory__Slab__sfree+0x35c>
ffffffff80112588: d1000508     	sub	x8, x8, #0x1
ffffffff8011258c: 8a140108     	and	x8, x8, x20
ffffffff80112590: f102c108     	subs	x8, x8, #0xb0
ffffffff80112594: 54001323     	b.lo	0xffffffff801127f8 <memory__Slab__sfree+0x35c>
ffffffff80112598: f9400a6d     	ldr	x13, [x19, #0x10]
ffffffff8011259c: b40012ed     	cbz	x13, 0xffffffff801127f8 <memory__Slab__sfree+0x35c>
ffffffff801125a0: 9acd0909     	udiv	x9, x8, x13
ffffffff801125a4: 9b0da128     	msub	x8, x9, x13, x8
ffffffff801125a8: b5001348     	cbnz	x8, 0xffffffff80112810 <memory__Slab__sfree+0x374>
ffffffff801125ac: f9401328     	ldr	x8, [x25, #0x20]
ffffffff801125b0: eb08013f     	cmp	x9, x8
ffffffff801125b4: 540012e2     	b.hs	0xffffffff80112810 <memory__Slab__sfree+0x374>
ffffffff801125b8: d346fd20     	lsr	x0, x9, #6
ffffffff801125bc: f110013f     	cmp	x9, #0x400
ffffffff801125c0: 54001422     	b.hs	0xffffffff80112844 <memory__Slab__sfree+0x3a8>
ffffffff801125c4: 5280002b     	mov	w11, #0x1       // =1
ffffffff801125c8: 9100c32a     	add	x10, x25, #0x30
ffffffff801125cc: 9ac9216b     	lsl	x11, x11, x9
ffffffff801125d0: f860794c     	ldr	x12, [x10, x0, lsl #3]
ffffffff801125d4: ea0b019f     	tst	x12, x11
ffffffff801125d8: 54001280     	b.eq	0xffffffff80112828 <memory__Slab__sfree+0x38c>
ffffffff801125dc: f9401729     	ldr	x9, [x25, #0x28]
ffffffff801125e0: b4001249     	cbz	x9, 0xffffffff80112828 <memory__Slab__sfree+0x38c>
ffffffff801125e4: f10021bf     	cmp	x13, #0x8
ffffffff801125e8: 54000062     	b.hs	0xffffffff801125f4 <memory__Slab__sfree+0x158>
ffffffff801125ec: aa0903ed     	mov	x13, x9
ffffffff801125f0: 14000018     	b	0xffffffff80112650 <memory__Slab__sfree+0x1b4>
ffffffff801125f4: d343fdac     	lsr	x12, x13, #3
ffffffff801125f8: f10041bf     	cmp	x13, #0x10
ffffffff801125fc: 54000062     	b.hs	0xffffffff80112608 <memory__Slab__sfree+0x16c>
ffffffff80112600: aa1f03ed     	mov	x13, xzr
ffffffff80112604: 1400000b     	b	0xffffffff80112630 <memory__Slab__sfree+0x194>
ffffffff80112608: 927fed8d     	and	x13, x12, #0x1ffffffffffffffe
ffffffff8011260c: 9100228e     	add	x14, x20, #0x8
ffffffff80112610: b201f3ef     	mov	x15, #-0x5555555555555556 // =-6148914691236517206
ffffffff80112614: aa0d03f0     	mov	x16, x13
ffffffff80112618: f1000a10     	subs	x16, x16, #0x2
ffffffff8011261c: a93fbdcf     	stp	x15, x15, [x14, #-0x8]
ffffffff80112620: 910041ce     	add	x14, x14, #0x10
ffffffff80112624: 54ffffa1     	b.ne	0xffffffff80112618 <memory__Slab__sfree+0x17c>
ffffffff80112628: eb0d019f     	cmp	x12, x13
ffffffff8011262c: 540000e0     	b.eq	0xffffffff80112648 <memory__Slab__sfree+0x1ac>
ffffffff80112630: 8b0d0e8e     	add	x14, x20, x13, lsl #3
ffffffff80112634: cb0d018c     	sub	x12, x12, x13
ffffffff80112638: b201f3ed     	mov	x13, #-0x5555555555555556 // =-6148914691236517206
ffffffff8011263c: f100058c     	subs	x12, x12, #0x1
ffffffff80112640: f80085cd     	str	x13, [x14], #0x8
ffffffff80112644: 54ffffc1     	b.ne	0xffffffff8011263c <memory__Slab__sfree+0x1a0>
ffffffff80112648: f860794c     	ldr	x12, [x10, x0, lsl #3]
ffffffff8011264c: f940172d     	ldr	x13, [x25, #0x28]
ffffffff80112650: 8a2b018b     	bic	x11, x12, x11
ffffffff80112654: f820794b     	str	x11, [x10, x0, lsl #3]
ffffffff80112658: d10005aa     	sub	x10, x13, #0x1
ffffffff8011265c: f900172a     	str	x10, [x25, #0x28]
ffffffff80112660: f9401a6a     	ldr	x10, [x19, #0x30]
ffffffff80112664: d100054a     	sub	x10, x10, #0x1
ffffffff80112668: f9001a6a     	str	x10, [x19, #0x30]
ffffffff8011266c: f940172a     	ldr	x10, [x25, #0x28]
ffffffff80112670: b400014a     	cbz	x10, 0xffffffff80112698 <memory__Slab__sfree+0x1fc>
ffffffff80112674: eb08013f     	cmp	x9, x8
ffffffff80112678: 54000341     	b.ne	0xffffffff801126e0 <memory__Slab__sfree+0x244>
ffffffff8011267c: f9000b3f     	str	xzr, [x25, #0x10]
ffffffff80112680: f9400e68     	ldr	x8, [x19, #0x18]
ffffffff80112684: f9000f28     	str	x8, [x25, #0x18]
ffffffff80112688: b4000048     	cbz	x8, 0xffffffff80112690 <memory__Slab__sfree+0x1f4>
ffffffff8011268c: f9000919     	str	x25, [x8, #0x10]
ffffffff80112690: f9000e79     	str	x25, [x19, #0x18]
ffffffff80112694: 14000013     	b	0xffffffff801126e0 <memory__Slab__sfree+0x244>
ffffffff80112698: eb08013f     	cmp	x9, x8
ffffffff8011269c: 54000120     	b.eq	0xffffffff801126c0 <memory__Slab__sfree+0x224>
ffffffff801126a0: a9412329     	ldp	x9, x8, [x25, #0x10]
ffffffff801126a4: f100013f     	cmp	x9, #0x0
ffffffff801126a8: 9a890269     	csel	x9, x19, x9, eq
ffffffff801126ac: f9000d28     	str	x8, [x9, #0x18]
ffffffff801126b0: b4000068     	cbz	x8, 0xffffffff801126bc <memory__Slab__sfree+0x220>
ffffffff801126b4: f9400b29     	ldr	x9, [x25, #0x10]
ffffffff801126b8: f9000909     	str	x9, [x8, #0x10]
ffffffff801126bc: a9017f3f     	stp	xzr, xzr, [x25, #0x10]
ffffffff801126c0: f9401268     	ldr	x8, [x19, #0x20]
ffffffff801126c4: b40000c8     	cbz	x8, 0xffffffff801126dc <memory__Slab__sfree+0x240>
ffffffff801126c8: f900073f     	str	xzr, [x25, #0x8]
ffffffff801126cc: f9401e68     	ldr	x8, [x19, #0x38]
ffffffff801126d0: d1000508     	sub	x8, x8, #0x1
ffffffff801126d4: f9001e68     	str	x8, [x19, #0x38]
ffffffff801126d8: 14000003     	b	0xffffffff801126e4 <memory__Slab__sfree+0x248>
ffffffff801126dc: f9001279     	str	x25, [x19, #0x20]
ffffffff801126e0: aa1f03f9     	mov	x25, xzr
ffffffff801126e4: 39402274     	ldrb	w20, [x19, #0x8]
ffffffff801126e8: aa1303e0     	mov	x0, x19
ffffffff801126ec: aa1f03e1     	mov	x1, xzr
ffffffff801126f0: 94026cb5     	bl	0xffffffff801ad9c4 <vinix_stlr64>
ffffffff801126f4: d503209f     	sev
ffffffff801126f8: d53b4228     	mrs	x8, DAIF
ffffffff801126fc: 36000094     	tbz	w20, #0x0, 0xffffffff8011270c <memory__Slab__sfree+0x270>
ffffffff80112700: d5034fff     	msr	DAIFClr, #0xf
ffffffff80112704: b5000099     	cbnz	x25, 0xffffffff80112714 <memory__Slab__sfree+0x278>
ffffffff80112708: 1400002f     	b	0xffffffff801127c4 <memory__Slab__sfree+0x328>
ffffffff8011270c: d5034fdf     	msr	DAIFSet, #0xf
ffffffff80112710: b40005b9     	cbz	x25, 0xffffffff801127c4 <memory__Slab__sfree+0x328>
ffffffff80112714: f9401328     	ldr	x8, [x25, #0x20]
ffffffff80112718: b40004c8     	cbz	x8, 0xffffffff801127b0 <memory__Slab__sfree+0x314>
ffffffff8011271c: f9400a73     	ldr	x19, [x19, #0x10]
ffffffff80112720: aa1f03fa     	mov	x26, xzr
ffffffff80112724: 9102c33b     	add	x27, x25, #0xb0
ffffffff80112728: f00017b4     	adrp	x20, 0xffffffff80409000 <gpu__agx__event__gpu_event_mgr+0x3f8>
ffffffff8011272c: 9137a294     	add	x20, x20, #0xde8
ffffffff80112730: b201f3f5     	mov	x21, #-0x5555555555555556 // =-6148914691236517206
ffffffff80112734: d343fe7c     	lsr	x28, x19, #3
ffffffff80112738: 14000005     	b	0xffffffff8011274c <memory__Slab__sfree+0x2b0>
ffffffff8011273c: f9401328     	ldr	x8, [x25, #0x20]
ffffffff80112740: 9100075a     	add	x26, x26, #0x1
ffffffff80112744: eb08035f     	cmp	x26, x8
ffffffff80112748: 54000342     	b.hs	0xffffffff801127b0 <memory__Slab__sfree+0x314>
ffffffff8011274c: f100227f     	cmp	x19, #0x8
ffffffff80112750: 54ffff63     	b.lo	0xffffffff8011273c <memory__Slab__sfree+0x2a0>
ffffffff80112754: 9b136f57     	madd	x23, x26, x19, x27
ffffffff80112758: aa1f03f6     	mov	x22, xzr
ffffffff8011275c: aa1c03e8     	mov	x8, x28
ffffffff80112760: f8766af8     	ldr	x24, [x23, x22]
ffffffff80112764: eb15031f     	cmp	x24, x21
ffffffff80112768: 540000a1     	b.ne	0xffffffff8011277c <memory__Slab__sfree+0x2e0>
ffffffff8011276c: f1000508     	subs	x8, x8, #0x1
ffffffff80112770: 910022d6     	add	x22, x22, #0x8
ffffffff80112774: 54ffff61     	b.ne	0xffffffff80112760 <memory__Slab__sfree+0x2c4>
ffffffff80112778: 17fffff1     	b	0xffffffff8011273c <memory__Slab__sfree+0x2a0>
ffffffff8011277c: aa1403e0     	mov	x0, x20
ffffffff80112780: 52800021     	mov	w1, #0x1        // =1
ffffffff80112784: 94026c9c     	bl	0xffffffff801ad9f4 <vinix_ldadd64>
ffffffff80112788: f1007c1f     	cmp	x0, #0x1f
ffffffff8011278c: 54fffd88     	b.hi	0xffffffff8011273c <memory__Slab__sfree+0x2a0>
ffffffff80112790: d0000540     	adrp	x0, 0xffffffff801bc000 <_str_2114+0x65d0>
ffffffff80112794: 912f3000     	add	x0, x0, #0xbcc
ffffffff80112798: aa1303e1     	mov	x1, x19
ffffffff8011279c: aa1703e2     	mov	x2, x23
ffffffff801127a0: aa1803e3     	mov	x3, x24
ffffffff801127a4: aa1603e4     	mov	x4, x22
ffffffff801127a8: 940263ae     	bl	0xffffffff801ab660 <kprintf>
ffffffff801127ac: 17ffffe4     	b	0xffffffff8011273c <memory__Slab__sfree+0x2a0>
ffffffff801127b0: f00006c8     	adrp	x8, 0xffffffff801ed000 <memory__heap_test_objects+0x3880>
ffffffff801127b4: 52800021     	mov	w1, #0x1        // =1
ffffffff801127b8: f943f508     	ldr	x8, [x8, #0x7e8]
ffffffff801127bc: cb080320     	sub	x0, x25, x8
ffffffff801127c0: 97fc6a99     	bl	0xffffffff8002d224 <memory__pmm_free>
ffffffff801127c4: d0000628     	adrp	x8, 0xffffffff801d8000 <halt_at_stage>
ffffffff801127c8: f85f03a9     	ldur	x9, [x29, #-0x10]
ffffffff801127cc: f9417908     	ldr	x8, [x8, #0x2f0]
ffffffff801127d0: eb09011f     	cmp	x8, x9
ffffffff801127d4: 54000361     	b.ne	0xffffffff80112840 <memory__Slab__sfree+0x3a4>
ffffffff801127d8: a9504ff4     	ldp	x20, x19, [sp, #0x100]
ffffffff801127dc: a94f57f6     	ldp	x22, x21, [sp, #0xf0]
ffffffff801127e0: a94e5ff8     	ldp	x24, x23, [sp, #0xe0]
ffffffff801127e4: a94d67fa     	ldp	x26, x25, [sp, #0xd0]
ffffffff801127e8: a94c6ffc     	ldp	x28, x27, [sp, #0xc0]
ffffffff801127ec: a94b7bfd     	ldp	x29, x30, [sp, #0xb0]
ffffffff801127f0: 910443ff     	add	sp, sp, #0x110
ffffffff801127f4: d65f03c0     	ret
ffffffff801127f8: aa1303e0     	mov	x0, x19
ffffffff801127fc: 97fc5c0b     	bl	0xffffffff80029828 <klock__Lock__release>
ffffffff80112800: d0000541     	adrp	x1, 0xffffffff801bc000 <_str_2114+0x65d0>
ffffffff80112804: 910b4821     	add	x1, x1, #0x2d2
ffffffff80112808: aa1f03e0     	mov	x0, xzr
ffffffff8011280c: 97ffce2d     	bl	0xffffffff801060c0 <lib__kpanic>
ffffffff80112810: aa1303e0     	mov	x0, x19
ffffffff80112814: 97fc5c05     	bl	0xffffffff80029828 <klock__Lock__release>
ffffffff80112818: 90000581     	adrp	x1, 0xffffffff801c2000 <_str_2114+0xc5d0>
ffffffff8011281c: 91004c21     	add	x1, x1, #0x13
ffffffff80112820: aa1f03e0     	mov	x0, xzr
ffffffff80112824: 97ffce27     	bl	0xffffffff801060c0 <lib__kpanic>
ffffffff80112828: aa1303e0     	mov	x0, x19
ffffffff8011282c: 97fc5bff     	bl	0xffffffff80029828 <klock__Lock__release>
ffffffff80112830: d0000541     	adrp	x1, 0xffffffff801bc000 <_str_2114+0x65d0>
ffffffff80112834: 912ee821     	add	x1, x1, #0xbba
ffffffff80112838: aa1f03e0     	mov	x0, xzr
ffffffff8011283c: 97ffce21     	bl	0xffffffff801060c0 <lib__kpanic>
ffffffff80112840: 9402643d     	bl	0xffffffff801ab934 <__stack_chk_fail>
ffffffff80112844: d503201f     	nop
ffffffff80112848: 1060fc48     	adr	x8, 0xffffffff801d47d0 <_str_186>
ffffffff8011284c: 9100a3f3     	add	x19, sp, #0x28
ffffffff80112850: a9402909     	ldp	x9, x10, [x8]
ffffffff80112854: f9400908     	ldr	x8, [x8, #0x10]
ffffffff80112858: f9001fe8     	str	x8, [sp, #0x38]
ffffffff8011285c: 91006268     	add	x8, x19, #0x18
ffffffff80112860: a902abe9     	stp	x9, x10, [sp, #0x28]
ffffffff80112864: 97fc90b5     	bl	0xffffffff80036b38 <impl_i64_to_string>
ffffffff80112868: d503201f     	nop
ffffffff8011286c: 1060fbe8     	adr	x8, 0xffffffff801d47e8 <_str_187>
ffffffff80112870: 52800200     	mov	w0, #0x10       // =16
ffffffff80112874: a9402909     	ldp	x9, x10, [x8]
ffffffff80112878: f9400908     	ldr	x8, [x8, #0x10]
ffffffff8011287c: f90037e8     	str	x8, [sp, #0x68]
ffffffff80112880: 91012268     	add	x8, x19, #0x48
ffffffff80112884: a905abe9     	stp	x9, x10, [sp, #0x58]
ffffffff80112888: 97fc90ac     	bl	0xffffffff80036b38 <impl_i64_to_string>
ffffffff8011288c: d503201f     	nop
ffffffff80112890: 105c7948     	adr	x8, 0xffffffff801cb7b8 <_str_23>
ffffffff80112894: 9100a3e1     	add	x1, sp, #0x28
ffffffff80112898: a9402909     	ldp	x9, x10, [x8]
ffffffff8011289c: f9400908     	ldr	x8, [x8, #0x10]
ffffffff801128a0: 528000a0     	mov	w0, #0x5        // =5
ffffffff801128a4: f9004fe8     	str	x8, [sp, #0x98]
ffffffff801128a8: 910043e8     	add	x8, sp, #0x10
ffffffff801128ac: a908abe9     	stp	x9, x10, [sp, #0x88]
ffffffff801128b0: 97fc5123     	bl	0xffffffff80026d3c <string_plus_many>
ffffffff801128b4: 910043e0     	add	x0, sp, #0x10
ffffffff801128b8: 97fbb5d2     	bl	0xffffffff80000000 <v_panic>

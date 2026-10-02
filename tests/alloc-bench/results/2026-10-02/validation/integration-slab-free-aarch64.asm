
/Users/alex/code/vinix/build/alloc-bench-integration/vinix-aarch64:	file format elf64-littleaarch64

Disassembly of section .text:

ffffffff801198ac <memory__Slab__sfree>:
ffffffff801198ac: d10443ff     	sub	sp, sp, #0x110
ffffffff801198b0: a90b7bfd     	stp	x29, x30, [sp, #0xb0]
ffffffff801198b4: a90c6ffc     	stp	x28, x27, [sp, #0xc0]
ffffffff801198b8: a90d67fa     	stp	x26, x25, [sp, #0xd0]
ffffffff801198bc: a90e5ff8     	stp	x24, x23, [sp, #0xe0]
ffffffff801198c0: a90f57f6     	stp	x22, x21, [sp, #0xf0]
ffffffff801198c4: a9104ff4     	stp	x20, x19, [sp, #0x100]
ffffffff801198c8: 9102c3fd     	add	x29, sp, #0xb0
ffffffff801198cc: f0000688     	adrp	x8, 0xffffffff801ec000 <halt_at_stage>
ffffffff801198d0: f9417d08     	ldr	x8, [x8, #0x2f8]
ffffffff801198d4: f81f03a8     	stur	x8, [x29, #-0x10]
ffffffff801198d8: b40017e1     	cbz	x1, 0xffffffff80119bd4 <memory__Slab__sfree+0x328>
ffffffff801198dc: aa0103f4     	mov	x20, x1
ffffffff801198e0: aa0003f3     	mov	x19, x0
ffffffff801198e4: 52800035     	mov	w21, #0x1       // =1
ffffffff801198e8: 14000003     	b	0xffffffff801198f4 <memory__Slab__sfree+0x48>
ffffffff801198ec: d5034fdf     	msr	DAIFSet, #0xf
ffffffff801198f0: d503205f     	wfe
ffffffff801198f4: d53b4236     	mrs	x22, DAIF
ffffffff801198f8: d5034fdf     	msr	DAIFSet, #0xf
ffffffff801198fc: 910023e0     	add	x0, sp, #0x8
ffffffff80119900: 9100a3e1     	add	x1, sp, #0x28
ffffffff80119904: 52800102     	mov	w2, #0x8        // =8
ffffffff80119908: f90017ff     	str	xzr, [sp, #0x28]
ffffffff8011990c: a900d7ff     	stp	xzr, x21, [sp, #0x8]
ffffffff80119910: f90003ff     	str	xzr, [sp]
ffffffff80119914: 9402964c     	bl	0xffffffff801bf244 <memcpy>
ffffffff80119918: 910003e0     	mov	x0, sp
ffffffff8011991c: 910043e1     	add	x1, sp, #0x10
ffffffff80119920: 52800102     	mov	w2, #0x8        // =8
ffffffff80119924: 94029648     	bl	0xffffffff801bf244 <memcpy>
ffffffff80119928: a94007e2     	ldp	x2, x1, [sp]
ffffffff8011992c: aa1303e0     	mov	x0, x19
ffffffff80119930: 9402a981     	bl	0xffffffff801c3f34 <vinix_casa64>
ffffffff80119934: f94007e8     	ldr	x8, [sp, #0x8]
ffffffff80119938: eb08001f     	cmp	x0, x8
ffffffff8011993c: 540000c0     	b.eq	0xffffffff80119954 <memory__Slab__sfree+0xa8>
ffffffff80119940: d53b4228     	mrs	x8, DAIF
ffffffff80119944: 373ffd56     	tbnz	w22, #0x7, 0xffffffff801198ec <memory__Slab__sfree+0x40>
ffffffff80119948: d5034fff     	msr	DAIFClr, #0xf
ffffffff8011994c: d503205f     	wfe
ffffffff80119950: 17ffffe9     	b	0xffffffff801198f4 <memory__Slab__sfree+0x48>
ffffffff80119954: f0000688     	adrp	x8, 0xffffffff801ec000 <halt_at_stage>
ffffffff80119958: f27902df     	tst	x22, #0x80
ffffffff8011995c: f9401508     	ldr	x8, [x8, #0x28]
ffffffff80119960: 1a9f17e9     	cset	w9, eq
ffffffff80119964: 39002269     	strb	w9, [x19, #0x8]
ffffffff80119968: cb0803ea     	neg	x10, x8
ffffffff8011996c: 8a140159     	and	x25, x10, x20
ffffffff80119970: d289884a     	mov	x10, #0x4c42    // =19522
ffffffff80119974: f2ab0a6a     	movk	x10, #0x5853, lsl #16
ffffffff80119978: f9400729     	ldr	x9, [x25, #0x8]
ffffffff8011997c: f2c9c92a     	movk	x10, #0x4e49, lsl #32
ffffffff80119980: f2eac92a     	movk	x10, #0x5649, lsl #48
ffffffff80119984: eb0a013f     	cmp	x9, x10
ffffffff80119988: 54001401     	b.ne	0xffffffff80119c08 <memory__Slab__sfree+0x35c>
ffffffff8011998c: f9400329     	ldr	x9, [x25]
ffffffff80119990: eb13013f     	cmp	x9, x19
ffffffff80119994: 540013a1     	b.ne	0xffffffff80119c08 <memory__Slab__sfree+0x35c>
ffffffff80119998: d1000508     	sub	x8, x8, #0x1
ffffffff8011999c: 8a140108     	and	x8, x8, x20
ffffffff801199a0: f102c108     	subs	x8, x8, #0xb0
ffffffff801199a4: 54001323     	b.lo	0xffffffff80119c08 <memory__Slab__sfree+0x35c>
ffffffff801199a8: f9400a6d     	ldr	x13, [x19, #0x10]
ffffffff801199ac: b40012ed     	cbz	x13, 0xffffffff80119c08 <memory__Slab__sfree+0x35c>
ffffffff801199b0: 9acd0909     	udiv	x9, x8, x13
ffffffff801199b4: 9b0da128     	msub	x8, x9, x13, x8
ffffffff801199b8: b5001348     	cbnz	x8, 0xffffffff80119c20 <memory__Slab__sfree+0x374>
ffffffff801199bc: f9401328     	ldr	x8, [x25, #0x20]
ffffffff801199c0: eb08013f     	cmp	x9, x8
ffffffff801199c4: 540012e2     	b.hs	0xffffffff80119c20 <memory__Slab__sfree+0x374>
ffffffff801199c8: d346fd20     	lsr	x0, x9, #6
ffffffff801199cc: f110013f     	cmp	x9, #0x400
ffffffff801199d0: 54001422     	b.hs	0xffffffff80119c54 <memory__Slab__sfree+0x3a8>
ffffffff801199d4: 5280002b     	mov	w11, #0x1       // =1
ffffffff801199d8: 9100c32a     	add	x10, x25, #0x30
ffffffff801199dc: 9ac9216b     	lsl	x11, x11, x9
ffffffff801199e0: f860794c     	ldr	x12, [x10, x0, lsl #3]
ffffffff801199e4: ea0b019f     	tst	x12, x11
ffffffff801199e8: 54001280     	b.eq	0xffffffff80119c38 <memory__Slab__sfree+0x38c>
ffffffff801199ec: f9401729     	ldr	x9, [x25, #0x28]
ffffffff801199f0: b4001249     	cbz	x9, 0xffffffff80119c38 <memory__Slab__sfree+0x38c>
ffffffff801199f4: f10021bf     	cmp	x13, #0x8
ffffffff801199f8: 54000062     	b.hs	0xffffffff80119a04 <memory__Slab__sfree+0x158>
ffffffff801199fc: aa0903ed     	mov	x13, x9
ffffffff80119a00: 14000018     	b	0xffffffff80119a60 <memory__Slab__sfree+0x1b4>
ffffffff80119a04: d343fdac     	lsr	x12, x13, #3
ffffffff80119a08: f10041bf     	cmp	x13, #0x10
ffffffff80119a0c: 54000062     	b.hs	0xffffffff80119a18 <memory__Slab__sfree+0x16c>
ffffffff80119a10: aa1f03ed     	mov	x13, xzr
ffffffff80119a14: 1400000b     	b	0xffffffff80119a40 <memory__Slab__sfree+0x194>
ffffffff80119a18: 927fed8d     	and	x13, x12, #0x1ffffffffffffffe
ffffffff80119a1c: 9100228e     	add	x14, x20, #0x8
ffffffff80119a20: b201f3ef     	mov	x15, #-0x5555555555555556 // =-6148914691236517206
ffffffff80119a24: aa0d03f0     	mov	x16, x13
ffffffff80119a28: f1000a10     	subs	x16, x16, #0x2
ffffffff80119a2c: a93fbdcf     	stp	x15, x15, [x14, #-0x8]
ffffffff80119a30: 910041ce     	add	x14, x14, #0x10
ffffffff80119a34: 54ffffa1     	b.ne	0xffffffff80119a28 <memory__Slab__sfree+0x17c>
ffffffff80119a38: eb0d019f     	cmp	x12, x13
ffffffff80119a3c: 540000e0     	b.eq	0xffffffff80119a58 <memory__Slab__sfree+0x1ac>
ffffffff80119a40: 8b0d0e8e     	add	x14, x20, x13, lsl #3
ffffffff80119a44: cb0d018c     	sub	x12, x12, x13
ffffffff80119a48: b201f3ed     	mov	x13, #-0x5555555555555556 // =-6148914691236517206
ffffffff80119a4c: f100058c     	subs	x12, x12, #0x1
ffffffff80119a50: f80085cd     	str	x13, [x14], #0x8
ffffffff80119a54: 54ffffc1     	b.ne	0xffffffff80119a4c <memory__Slab__sfree+0x1a0>
ffffffff80119a58: f860794c     	ldr	x12, [x10, x0, lsl #3]
ffffffff80119a5c: f940172d     	ldr	x13, [x25, #0x28]
ffffffff80119a60: 8a2b018b     	bic	x11, x12, x11
ffffffff80119a64: f820794b     	str	x11, [x10, x0, lsl #3]
ffffffff80119a68: d10005aa     	sub	x10, x13, #0x1
ffffffff80119a6c: f900172a     	str	x10, [x25, #0x28]
ffffffff80119a70: f9401a6a     	ldr	x10, [x19, #0x30]
ffffffff80119a74: d100054a     	sub	x10, x10, #0x1
ffffffff80119a78: f9001a6a     	str	x10, [x19, #0x30]
ffffffff80119a7c: f940172a     	ldr	x10, [x25, #0x28]
ffffffff80119a80: b400014a     	cbz	x10, 0xffffffff80119aa8 <memory__Slab__sfree+0x1fc>
ffffffff80119a84: eb08013f     	cmp	x9, x8
ffffffff80119a88: 54000341     	b.ne	0xffffffff80119af0 <memory__Slab__sfree+0x244>
ffffffff80119a8c: f9000b3f     	str	xzr, [x25, #0x10]
ffffffff80119a90: f9400e68     	ldr	x8, [x19, #0x18]
ffffffff80119a94: f9000f28     	str	x8, [x25, #0x18]
ffffffff80119a98: b4000048     	cbz	x8, 0xffffffff80119aa0 <memory__Slab__sfree+0x1f4>
ffffffff80119a9c: f9000919     	str	x25, [x8, #0x10]
ffffffff80119aa0: f9000e79     	str	x25, [x19, #0x18]
ffffffff80119aa4: 14000013     	b	0xffffffff80119af0 <memory__Slab__sfree+0x244>
ffffffff80119aa8: eb08013f     	cmp	x9, x8
ffffffff80119aac: 54000120     	b.eq	0xffffffff80119ad0 <memory__Slab__sfree+0x224>
ffffffff80119ab0: a9412329     	ldp	x9, x8, [x25, #0x10]
ffffffff80119ab4: f100013f     	cmp	x9, #0x0
ffffffff80119ab8: 9a890269     	csel	x9, x19, x9, eq
ffffffff80119abc: f9000d28     	str	x8, [x9, #0x18]
ffffffff80119ac0: b4000068     	cbz	x8, 0xffffffff80119acc <memory__Slab__sfree+0x220>
ffffffff80119ac4: f9400b29     	ldr	x9, [x25, #0x10]
ffffffff80119ac8: f9000909     	str	x9, [x8, #0x10]
ffffffff80119acc: a9017f3f     	stp	xzr, xzr, [x25, #0x10]
ffffffff80119ad0: f9401268     	ldr	x8, [x19, #0x20]
ffffffff80119ad4: b40000c8     	cbz	x8, 0xffffffff80119aec <memory__Slab__sfree+0x240>
ffffffff80119ad8: f900073f     	str	xzr, [x25, #0x8]
ffffffff80119adc: f9401e68     	ldr	x8, [x19, #0x38]
ffffffff80119ae0: d1000508     	sub	x8, x8, #0x1
ffffffff80119ae4: f9001e68     	str	x8, [x19, #0x38]
ffffffff80119ae8: 14000003     	b	0xffffffff80119af4 <memory__Slab__sfree+0x248>
ffffffff80119aec: f9001279     	str	x25, [x19, #0x20]
ffffffff80119af0: aa1f03f9     	mov	x25, xzr
ffffffff80119af4: 39402274     	ldrb	w20, [x19, #0x8]
ffffffff80119af8: aa1303e0     	mov	x0, x19
ffffffff80119afc: aa1f03e1     	mov	x1, xzr
ffffffff80119b00: 9402a8ee     	bl	0xffffffff801c3eb8 <vinix_stlr64>
ffffffff80119b04: d503209f     	sev
ffffffff80119b08: d53b4228     	mrs	x8, DAIF
ffffffff80119b0c: 36000094     	tbz	w20, #0x0, 0xffffffff80119b1c <memory__Slab__sfree+0x270>
ffffffff80119b10: d5034fff     	msr	DAIFClr, #0xf
ffffffff80119b14: b5000099     	cbnz	x25, 0xffffffff80119b24 <memory__Slab__sfree+0x278>
ffffffff80119b18: 1400002f     	b	0xffffffff80119bd4 <memory__Slab__sfree+0x328>
ffffffff80119b1c: d5034fdf     	msr	DAIFSet, #0xf
ffffffff80119b20: b40005b9     	cbz	x25, 0xffffffff80119bd4 <memory__Slab__sfree+0x328>
ffffffff80119b24: f9401328     	ldr	x8, [x25, #0x20]
ffffffff80119b28: b40004c8     	cbz	x8, 0xffffffff80119bc0 <memory__Slab__sfree+0x314>
ffffffff80119b2c: f9400a73     	ldr	x19, [x19, #0x10]
ffffffff80119b30: aa1f03fa     	mov	x26, xzr
ffffffff80119b34: 9102c33b     	add	x27, x25, #0xb0
ffffffff80119b38: b00018d4     	adrp	x20, 0xffffffff80432000 <gpu__agx__event__gpu_event_mgr+0xae0>
ffffffff80119b3c: 911c6294     	add	x20, x20, #0x718
ffffffff80119b40: b201f3f5     	mov	x21, #-0x5555555555555556 // =-6148914691236517206
ffffffff80119b44: d343fe7c     	lsr	x28, x19, #3
ffffffff80119b48: 14000005     	b	0xffffffff80119b5c <memory__Slab__sfree+0x2b0>
ffffffff80119b4c: f9401328     	ldr	x8, [x25, #0x20]
ffffffff80119b50: 9100075a     	add	x26, x26, #0x1
ffffffff80119b54: eb08035f     	cmp	x26, x8
ffffffff80119b58: 54000342     	b.hs	0xffffffff80119bc0 <memory__Slab__sfree+0x314>
ffffffff80119b5c: f100227f     	cmp	x19, #0x8
ffffffff80119b60: 54ffff63     	b.lo	0xffffffff80119b4c <memory__Slab__sfree+0x2a0>
ffffffff80119b64: 9b136f57     	madd	x23, x26, x19, x27
ffffffff80119b68: aa1f03f6     	mov	x22, xzr
ffffffff80119b6c: aa1c03e8     	mov	x8, x28
ffffffff80119b70: f8766af8     	ldr	x24, [x23, x22]
ffffffff80119b74: eb15031f     	cmp	x24, x21
ffffffff80119b78: 540000a1     	b.ne	0xffffffff80119b8c <memory__Slab__sfree+0x2e0>
ffffffff80119b7c: f1000508     	subs	x8, x8, #0x1
ffffffff80119b80: 910022d6     	add	x22, x22, #0x8
ffffffff80119b84: 54ffff61     	b.ne	0xffffffff80119b70 <memory__Slab__sfree+0x2c4>
ffffffff80119b88: 17fffff1     	b	0xffffffff80119b4c <memory__Slab__sfree+0x2a0>
ffffffff80119b8c: aa1403e0     	mov	x0, x20
ffffffff80119b90: 52800021     	mov	w1, #0x1        // =1
ffffffff80119b94: 9402a8d5     	bl	0xffffffff801c3ee8 <vinix_ldadd64>
ffffffff80119b98: f1007c1f     	cmp	x0, #0x1f
ffffffff80119b9c: 54fffd88     	b.hi	0xffffffff80119b4c <memory__Slab__sfree+0x2a0>
ffffffff80119ba0: f00005a0     	adrp	x0, 0xffffffff801d0000 <_str_2136+0x6660>
ffffffff80119ba4: 9134c000     	add	x0, x0, #0xd30
ffffffff80119ba8: aa1303e1     	mov	x1, x19
ffffffff80119bac: aa1703e2     	mov	x2, x23
ffffffff80119bb0: aa1803e3     	mov	x3, x24
ffffffff80119bb4: aa1603e4     	mov	x4, x22
ffffffff80119bb8: 94029bef     	bl	0xffffffff801c0b74 <kprintf>
ffffffff80119bbc: 17ffffe4     	b	0xffffffff80119b4c <memory__Slab__sfree+0x2a0>
ffffffff80119bc0: f0000708     	adrp	x8, 0xffffffff801fc000 <krandom__jitter_pool+0xf280>
ffffffff80119bc4: 52800021     	mov	w1, #0x1        // =1
ffffffff80119bc8: f946f108     	ldr	x8, [x8, #0xde0]
ffffffff80119bcc: cb080320     	sub	x0, x25, x8
ffffffff80119bd0: 97fc533f     	bl	0xffffffff8002e8cc <memory__pmm_free>
ffffffff80119bd4: f0000688     	adrp	x8, 0xffffffff801ec000 <halt_at_stage>
ffffffff80119bd8: f85f03a9     	ldur	x9, [x29, #-0x10]
ffffffff80119bdc: f9417d08     	ldr	x8, [x8, #0x2f8]
ffffffff80119be0: eb09011f     	cmp	x8, x9
ffffffff80119be4: 54000361     	b.ne	0xffffffff80119c50 <memory__Slab__sfree+0x3a4>
ffffffff80119be8: a9504ff4     	ldp	x20, x19, [sp, #0x100]
ffffffff80119bec: a94f57f6     	ldp	x22, x21, [sp, #0xf0]
ffffffff80119bf0: a94e5ff8     	ldp	x24, x23, [sp, #0xe0]
ffffffff80119bf4: a94d67fa     	ldp	x26, x25, [sp, #0xd0]
ffffffff80119bf8: a94c6ffc     	ldp	x28, x27, [sp, #0xc0]
ffffffff80119bfc: a94b7bfd     	ldp	x29, x30, [sp, #0xb0]
ffffffff80119c00: 910443ff     	add	sp, sp, #0x110
ffffffff80119c04: d65f03c0     	ret
ffffffff80119c08: aa1303e0     	mov	x0, x19
ffffffff80119c0c: 97fc4494     	bl	0xffffffff8002ae5c <klock__Lock__release>
ffffffff80119c10: f00005a1     	adrp	x1, 0xffffffff801d0000 <_str_2136+0x6660>
ffffffff80119c14: 91104821     	add	x1, x1, #0x412
ffffffff80119c18: aa1f03e0     	mov	x0, xzr
ffffffff80119c1c: 97ffcd86     	bl	0xffffffff8010d234 <lib__kpanic>
ffffffff80119c20: aa1303e0     	mov	x0, x19
ffffffff80119c24: 97fc448e     	bl	0xffffffff8002ae5c <klock__Lock__release>
ffffffff80119c28: b00005e1     	adrp	x1, 0xffffffff801d6000 <_str_2136+0xc660>
ffffffff80119c2c: 910b1c21     	add	x1, x1, #0x2c7
ffffffff80119c30: aa1f03e0     	mov	x0, xzr
ffffffff80119c34: 97ffcd80     	bl	0xffffffff8010d234 <lib__kpanic>
ffffffff80119c38: aa1303e0     	mov	x0, x19
ffffffff80119c3c: 97fc4488     	bl	0xffffffff8002ae5c <klock__Lock__release>
ffffffff80119c40: f00005a1     	adrp	x1, 0xffffffff801d0000 <_str_2136+0x6660>
ffffffff80119c44: 91347821     	add	x1, x1, #0xd1e
ffffffff80119c48: aa1f03e0     	mov	x0, xzr
ffffffff80119c4c: 97ffcd7a     	bl	0xffffffff8010d234 <lib__kpanic>
ffffffff80119c50: 94029c7e     	bl	0xffffffff801c0e48 <__stack_chk_fail>
ffffffff80119c54: d503201f     	nop
ffffffff80119c58: 10677e08     	adr	x8, 0xffffffff801e8c18 <_str_186>
ffffffff80119c5c: 9100a3f3     	add	x19, sp, #0x28
ffffffff80119c60: a9402909     	ldp	x9, x10, [x8]
ffffffff80119c64: f9400908     	ldr	x8, [x8, #0x10]
ffffffff80119c68: f9001fe8     	str	x8, [sp, #0x38]
ffffffff80119c6c: 91006268     	add	x8, x19, #0x18
ffffffff80119c70: a902abe9     	stp	x9, x10, [sp, #0x28]
ffffffff80119c74: 97fc79ce     	bl	0xffffffff800383ac <impl_i64_to_string>
ffffffff80119c78: d503201f     	nop
ffffffff80119c7c: 10677da8     	adr	x8, 0xffffffff801e8c30 <_str_187>
ffffffff80119c80: 52800200     	mov	w0, #0x10       // =16
ffffffff80119c84: a9402909     	ldp	x9, x10, [x8]
ffffffff80119c88: f9400908     	ldr	x8, [x8, #0x10]
ffffffff80119c8c: f90037e8     	str	x8, [sp, #0x68]
ffffffff80119c90: 91012268     	add	x8, x19, #0x48
ffffffff80119c94: a905abe9     	stp	x9, x10, [sp, #0x58]
ffffffff80119c98: 97fc79c5     	bl	0xffffffff800383ac <impl_i64_to_string>
ffffffff80119c9c: d503201f     	nop
ffffffff80119ca0: 1062f688     	adr	x8, 0xffffffff801dfb70 <_str_23>
ffffffff80119ca4: 9100a3e1     	add	x1, sp, #0x28
ffffffff80119ca8: a9402909     	ldp	x9, x10, [x8]
ffffffff80119cac: f9400908     	ldr	x8, [x8, #0x10]
ffffffff80119cb0: 528000a0     	mov	w0, #0x5        // =5
ffffffff80119cb4: f9004fe8     	str	x8, [sp, #0x98]
ffffffff80119cb8: 910043e8     	add	x8, sp, #0x10
ffffffff80119cbc: a908abe9     	stp	x9, x10, [sp, #0x88]
ffffffff80119cc0: 97fc39ac     	bl	0xffffffff80028370 <string_plus_many>
ffffffff80119cc4: 910043e0     	add	x0, sp, #0x10
ffffffff80119cc8: 97fb98ce     	bl	0xffffffff80000000 <v_panic>

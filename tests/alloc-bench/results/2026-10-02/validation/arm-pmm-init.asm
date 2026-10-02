
build/alloc-bench-validation/vinix-aarch64-selftest:	file format elf64-littleaarch64

Disassembly of section .text:

ffffffff80108b60 <memory__pmm_init>:
ffffffff80108b60: d10203ff     	sub	sp, sp, #0x80
ffffffff80108b64: a9027bfd     	stp	x29, x30, [sp, #0x20]
ffffffff80108b68: f9001bfb     	str	x27, [sp, #0x30]
ffffffff80108b6c: a90467fa     	stp	x26, x25, [sp, #0x40]
ffffffff80108b70: a9055ff8     	stp	x24, x23, [sp, #0x50]
ffffffff80108b74: a90657f6     	stp	x22, x21, [sp, #0x60]
ffffffff80108b78: a9074ff4     	stp	x20, x19, [sp, #0x70]
ffffffff80108b7c: 910083fd     	add	x29, sp, #0x20
ffffffff80108b80: 90000688     	adrp	x8, 0xffffffff801d8000 <halt_at_stage>
ffffffff80108b84: f9417908     	ldr	x8, [x8, #0x2f0]
ffffffff80108b88: f81f83a8     	stur	x8, [x29, #-0x8]
ffffffff80108b8c: 90000688     	adrp	x8, 0xffffffff801d8000 <halt_at_stage>
ffffffff80108b90: f941fd09     	ldr	x9, [x8, #0x3f8]
ffffffff80108b94: b4002a49     	cbz	x9, 0xffffffff801090dc <memory__pmm_init+0x57c>
ffffffff80108b98: f941fd08     	ldr	x8, [x8, #0x3f8]
ffffffff80108b9c: b0000739     	adrp	x25, 0xffffffff801ed000 <memory__heap_test_objects+0x3880>
ffffffff80108ba0: f00005a0     	adrp	x0, 0xffffffff801bf000 <_str_2114+0x95d0>
ffffffff80108ba4: 91283000     	add	x0, x0, #0xa0c
ffffffff80108ba8: f9400501     	ldr	x1, [x8, #0x8]
ffffffff80108bac: f903f721     	str	x1, [x25, #0x7e8]
ffffffff80108bb0: 94028a74     	bl	0xffffffff801ab580 <printf>
ffffffff80108bb4: 90000688     	adrp	x8, 0xffffffff801d8000 <halt_at_stage>
ffffffff80108bb8: f9422d09     	ldr	x9, [x8, #0x458]
ffffffff80108bbc: b4002989     	cbz	x9, 0xffffffff801090ec <memory__pmm_init+0x58c>
ffffffff80108bc0: f9422d16     	ldr	x22, [x8, #0x458]
ffffffff80108bc4: f94006c8     	ldr	x8, [x22, #0x8]
ffffffff80108bc8: b40010a8     	cbz	x8, 0xffffffff80108ddc <memory__pmm_init+0x27c>
ffffffff80108bcc: f9400ad7     	ldr	x23, [x22, #0x10]
ffffffff80108bd0: aa1f03f8     	mov	x24, xzr
ffffffff80108bd4: aa1f03f3     	mov	x19, xzr
ffffffff80108bd8: b00005d4     	adrp	x20, 0xffffffff801c1000 <_str_2114+0xb5d0>
ffffffff80108bdc: 911c5e94     	add	x20, x20, #0x717
ffffffff80108be0: 14000005     	b	0xffffffff80108bf4 <memory__pmm_init+0x94>
ffffffff80108be4: f94006c8     	ldr	x8, [x22, #0x8]
ffffffff80108be8: 91000673     	add	x19, x19, #0x1
ffffffff80108bec: eb08027f     	cmp	x19, x8
ffffffff80108bf0: 540001e2     	b.hs	0xffffffff80108c2c <memory__pmm_init+0xcc>
ffffffff80108bf4: f8737ae8     	ldr	x8, [x23, x19, lsl #3]
ffffffff80108bf8: aa1403e0     	mov	x0, x20
ffffffff80108bfc: 2a1303e1     	mov	w1, w19
ffffffff80108c00: a9400d02     	ldp	x2, x3, [x8]
ffffffff80108c04: f9400904     	ldr	x4, [x8, #0x10]
ffffffff80108c08: 94028a5e     	bl	0xffffffff801ab580 <printf>
ffffffff80108c0c: f8737ae8     	ldr	x8, [x23, x19, lsl #3]
ffffffff80108c10: f9400909     	ldr	x9, [x8, #0x10]
ffffffff80108c14: b5fffe89     	cbnz	x9, 0xffffffff80108be4 <memory__pmm_init+0x84>
ffffffff80108c18: a9402109     	ldp	x9, x8, [x8]
ffffffff80108c1c: 8b090108     	add	x8, x8, x9
ffffffff80108c20: eb18011f     	cmp	x8, x24
ffffffff80108c24: 9a988118     	csel	x24, x8, x24, hi
ffffffff80108c28: 17ffffef     	b	0xffffffff80108be4 <memory__pmm_init+0x84>
ffffffff80108c2c: b4000d98     	cbz	x24, 0xffffffff80108ddc <memory__pmm_init+0x27c>
ffffffff80108c30: 90000695     	adrp	x21, 0xffffffff801d8000 <halt_at_stage>
ffffffff80108c34: f9401ab4     	ldr	x20, [x21, #0x30]
ffffffff80108c38: b4002334     	cbz	x20, 0xffffffff8010909c <memory__pmm_init+0x53c>
ffffffff80108c3c: d100069a     	sub	x26, x20, #0x1
ffffffff80108c40: d0000580     	adrp	x0, 0xffffffff801ba000 <_str_2114+0x45d0>
ffffffff80108c44: 910d4800     	add	x0, x0, #0x352
ffffffff80108c48: 8b180348     	add	x8, x26, x24
ffffffff80108c4c: 9ad4091b     	udiv	x27, x8, x20
ffffffff80108c50: 91001f68     	add	x8, x27, #0x7
ffffffff80108c54: 8b480f48     	add	x8, x26, x8, lsr #3
ffffffff80108c58: 9ad40908     	udiv	x8, x8, x20
ffffffff80108c5c: 9b147d13     	mul	x19, x8, x20
ffffffff80108c60: b0000728     	adrp	x8, 0xffffffff801ed000 <memory__heap_test_objects+0x3880>
ffffffff80108c64: f903e51b     	str	x27, [x8, #0x7c8]
ffffffff80108c68: aa1303e1     	mov	x1, x19
ffffffff80108c6c: 94028a45     	bl	0xffffffff801ab580 <printf>
ffffffff80108c70: f94006c8     	ldr	x8, [x22, #0x8]
ffffffff80108c74: b0000738     	adrp	x24, 0xffffffff801ed000 <memory__heap_test_objects+0x3880>
ffffffff80108c78: b40005a8     	cbz	x8, 0xffffffff80108d2c <memory__pmm_init+0x1cc>
ffffffff80108c7c: 8b1b0b49     	add	x9, x26, x27, lsl #2
ffffffff80108c80: aa1703ec     	mov	x12, x23
ffffffff80108c84: 9ad40929     	udiv	x9, x9, x20
ffffffff80108c88: 9b147d34     	mul	x20, x9, x20
ffffffff80108c8c: f9401aa9     	ldr	x9, [x21, #0x30]
ffffffff80108c90: d100052b     	sub	x11, x9, #0x1
ffffffff80108c94: 8b14026a     	add	x10, x19, x20
ffffffff80108c98: 14000003     	b	0xffffffff80108ca4 <memory__pmm_init+0x144>
ffffffff80108c9c: f1000508     	subs	x8, x8, #0x1
ffffffff80108ca0: 54000460     	b.eq	0xffffffff80108d2c <memory__pmm_init+0x1cc>
ffffffff80108ca4: f840858d     	ldr	x13, [x12], #0x8
ffffffff80108ca8: f94009ae     	ldr	x14, [x13, #0x10]
ffffffff80108cac: b5ffff8e     	cbnz	x14, 0xffffffff80108c9c <memory__pmm_init+0x13c>
ffffffff80108cb0: b4001f69     	cbz	x9, 0xffffffff8010909c <memory__pmm_init+0x53c>
ffffffff80108cb4: a9403dae     	ldp	x14, x15, [x13]
ffffffff80108cb8: 8b0e016d     	add	x13, x11, x14
ffffffff80108cbc: 8b0e01ee     	add	x14, x15, x14
ffffffff80108cc0: 9ac909ad     	udiv	x13, x13, x9
ffffffff80108cc4: 9b097dad     	mul	x13, x13, x9
ffffffff80108cc8: eb0d01ce     	subs	x14, x14, x13
ffffffff80108ccc: fa4a81c0     	ccmp	x14, x10, #0x0, hi
ffffffff80108cd0: 54fffe63     	b.lo	0xffffffff80108c9c <memory__pmm_init+0x13c>
ffffffff80108cd4: b0000728     	adrp	x8, 0xffffffff801ed000 <memory__heap_test_objects+0x3880>
ffffffff80108cd8: b0000729     	adrp	x9, 0xffffffff801ed000 <memory__heap_test_objects+0x3880>
ffffffff80108cdc: f943f72a     	ldr	x10, [x25, #0x7e8]
ffffffff80108ce0: f903d10d     	str	x13, [x8, #0x7a0]
ffffffff80108ce4: 8b1301a8     	add	x8, x13, x19
ffffffff80108ce8: b0000739     	adrp	x25, 0xffffffff801ed000 <memory__heap_test_objects+0x3880>
ffffffff80108cec: f903d533     	str	x19, [x9, #0x7a8]
ffffffff80108cf0: b0000729     	adrp	x9, 0xffffffff801ed000 <memory__heap_test_objects+0x3880>
ffffffff80108cf4: 8b0d0140     	add	x0, x10, x13
ffffffff80108cf8: f903dd28     	str	x8, [x9, #0x7b8]
ffffffff80108cfc: b0000729     	adrp	x9, 0xffffffff801ed000 <memory__heap_test_objects+0x3880>
ffffffff80108d00: 8b080148     	add	x8, x10, x8
ffffffff80108d04: 52801fe1     	mov	w1, #0xff       // =255
ffffffff80108d08: aa1303e2     	mov	x2, x19
ffffffff80108d0c: f903cf00     	str	x0, [x24, #0x798]
ffffffff80108d10: f903e134     	str	x20, [x9, #0x7c0]
ffffffff80108d14: f903db28     	str	x8, [x25, #0x7b0]
ffffffff80108d18: 9402841a     	bl	0xffffffff801a9d80 <memset>
ffffffff80108d1c: f943db20     	ldr	x0, [x25, #0x7b0]
ffffffff80108d20: 2a1f03e1     	mov	w1, wzr
ffffffff80108d24: aa1403e2     	mov	x2, x20
ffffffff80108d28: 94028416     	bl	0xffffffff801a9d80 <memset>
ffffffff80108d2c: f943cf08     	ldr	x8, [x24, #0x798]
ffffffff80108d30: b4000568     	cbz	x8, 0xffffffff80108ddc <memory__pmm_init+0x27c>
ffffffff80108d34: f94006cb     	ldr	x11, [x22, #0x8]
ffffffff80108d38: b0000728     	adrp	x8, 0xffffffff801ed000 <memory__heap_test_objects+0x3880>
ffffffff80108d3c: b40006ab     	cbz	x11, 0xffffffff80108e10 <memory__pmm_init+0x2b0>
ffffffff80108d40: aa1f03e9     	mov	x9, xzr
ffffffff80108d44: 5280002a     	mov	w10, #0x1       // =1
ffffffff80108d48: 14000005     	b	0xffffffff80108d5c <memory__pmm_init+0x1fc>
ffffffff80108d4c: f94006cb     	ldr	x11, [x22, #0x8]
ffffffff80108d50: 91000529     	add	x9, x9, #0x1
ffffffff80108d54: eb0b013f     	cmp	x9, x11
ffffffff80108d58: 540005c2     	b.hs	0xffffffff80108e10 <memory__pmm_init+0x2b0>
ffffffff80108d5c: f8697aed     	ldr	x13, [x23, x9, lsl #3]
ffffffff80108d60: f94009ac     	ldr	x12, [x13, #0x10]
ffffffff80108d64: b5ffff6c     	cbnz	x12, 0xffffffff80108d50 <memory__pmm_init+0x1f0>
ffffffff80108d68: f9401aac     	ldr	x12, [x21, #0x30]
ffffffff80108d6c: b400198c     	cbz	x12, 0xffffffff8010909c <memory__pmm_init+0x53c>
ffffffff80108d70: a94035ae     	ldp	x14, x13, [x13]
ffffffff80108d74: 8b0e018f     	add	x15, x12, x14
ffffffff80108d78: 8b0e01ad     	add	x13, x13, x14
ffffffff80108d7c: d10005ef     	sub	x15, x15, #0x1
ffffffff80108d80: 9acc09ae     	udiv	x14, x13, x12
ffffffff80108d84: 9acc09ef     	udiv	x15, x15, x12
ffffffff80108d88: 9b0c7dce     	mul	x14, x14, x12
ffffffff80108d8c: 9b0c7ded     	mul	x13, x15, x12
ffffffff80108d90: eb0e01bf     	cmp	x13, x14
ffffffff80108d94: 54fffde2     	b.hs	0xffffffff80108d50 <memory__pmm_init+0x1f0>
ffffffff80108d98: f943ed0b     	ldr	x11, [x8, #0x7d8]
ffffffff80108d9c: 9100056b     	add	x11, x11, #0x1
ffffffff80108da0: f903ed0b     	str	x11, [x8, #0x7d8]
ffffffff80108da4: b40017cc     	cbz	x12, 0xffffffff8010909c <memory__pmm_init+0x53c>
ffffffff80108da8: 9acc09ab     	udiv	x11, x13, x12
ffffffff80108dac: f943cf0f     	ldr	x15, [x24, #0x798]
ffffffff80108db0: d343fd6c     	lsr	x12, x11, #3
ffffffff80108db4: 9acb214b     	lsl	x11, x10, x11
ffffffff80108db8: 927de58c     	and	x12, x12, #0x1ffffffffffffff8
ffffffff80108dbc: f86c69f0     	ldr	x16, [x15, x12]
ffffffff80108dc0: 8a2b020b     	bic	x11, x16, x11
ffffffff80108dc4: f82c69eb     	str	x11, [x15, x12]
ffffffff80108dc8: f9401aac     	ldr	x12, [x21, #0x30]
ffffffff80108dcc: 8b0d018d     	add	x13, x12, x13
ffffffff80108dd0: eb0e01bf     	cmp	x13, x14
ffffffff80108dd4: 54fffe23     	b.lo	0xffffffff80108d98 <memory__pmm_init+0x238>
ffffffff80108dd8: 17ffffdd     	b	0xffffffff80108d4c <memory__pmm_init+0x1ec>
ffffffff80108ddc: 90000688     	adrp	x8, 0xffffffff801d8000 <halt_at_stage>
ffffffff80108de0: f85f83a9     	ldur	x9, [x29, #-0x8]
ffffffff80108de4: f9417908     	ldr	x8, [x8, #0x2f0]
ffffffff80108de8: eb09011f     	cmp	x8, x9
ffffffff80108dec: 54001881     	b.ne	0xffffffff801090fc <memory__pmm_init+0x59c>
ffffffff80108df0: a9474ff4     	ldp	x20, x19, [sp, #0x70]
ffffffff80108df4: f9401bfb     	ldr	x27, [sp, #0x30]
ffffffff80108df8: a94657f6     	ldp	x22, x21, [sp, #0x60]
ffffffff80108dfc: a9455ff8     	ldp	x24, x23, [sp, #0x50]
ffffffff80108e00: a94467fa     	ldp	x26, x25, [sp, #0x40]
ffffffff80108e04: a9427bfd     	ldp	x29, x30, [sp, #0x20]
ffffffff80108e08: 910203ff     	add	sp, sp, #0x80
ffffffff80108e0c: d65f03c0     	ret
ffffffff80108e10: b0000729     	adrp	x9, 0xffffffff801ed000 <memory__heap_test_objects+0x3880>
ffffffff80108e14: b000072a     	adrp	x10, 0xffffffff801ed000 <memory__heap_test_objects+0x3880>
ffffffff80108e18: f943ed0d     	ldr	x13, [x8, #0x7d8]
ffffffff80108e1c: f943d52b     	ldr	x11, [x9, #0x7a8]
ffffffff80108e20: f943e14c     	ldr	x12, [x10, #0x7c0]
ffffffff80108e24: b000072e     	adrp	x14, 0xffffffff801ed000 <memory__heap_test_objects+0x3880>
ffffffff80108e28: f903f1cd     	str	x13, [x14, #0x7e0]
ffffffff80108e2c: ab0b019f     	cmn	x12, x11
ffffffff80108e30: 540003a0     	b.eq	0xffffffff80108ea4 <memory__pmm_init+0x344>
ffffffff80108e34: f9401aaf     	ldr	x15, [x21, #0x30]
ffffffff80108e38: aa1f03eb     	mov	x11, xzr
ffffffff80108e3c: b000072c     	adrp	x12, 0xffffffff801ed000 <memory__heap_test_objects+0x3880>
ffffffff80108e40: 5280002d     	mov	w13, #0x1       // =1
ffffffff80108e44: b000072e     	adrp	x14, 0xffffffff801ed000 <memory__heap_test_objects+0x3880>
ffffffff80108e48: b40012af     	cbz	x15, 0xffffffff8010909c <memory__pmm_init+0x53c>
ffffffff80108e4c: f943d190     	ldr	x16, [x12, #0x7a0]
ffffffff80108e50: f943cf11     	ldr	x17, [x24, #0x798]
ffffffff80108e54: 8b0b0210     	add	x16, x16, x11
ffffffff80108e58: 9acf0a0f     	udiv	x15, x16, x15
ffffffff80108e5c: d343fdf0     	lsr	x16, x15, #3
ffffffff80108e60: 9acf21b2     	lsl	x18, x13, x15
ffffffff80108e64: 927de610     	and	x16, x16, #0x1ffffffffffffff8
ffffffff80108e68: f8706a20     	ldr	x0, [x17, x16]
ffffffff80108e6c: aa120012     	orr	x18, x0, x18
ffffffff80108e70: f8306a32     	str	x18, [x17, x16]
ffffffff80108e74: f943d9d0     	ldr	x16, [x14, #0x7b0]
ffffffff80108e78: b82f7a0d     	str	w13, [x16, x15, lsl #2]
ffffffff80108e7c: f9401aaf     	ldr	x15, [x21, #0x30]
ffffffff80108e80: f943d530     	ldr	x16, [x9, #0x7a8]
ffffffff80108e84: f943e151     	ldr	x17, [x10, #0x7c0]
ffffffff80108e88: f943ed12     	ldr	x18, [x8, #0x7d8]
ffffffff80108e8c: 8b0b01eb     	add	x11, x15, x11
ffffffff80108e90: 8b100230     	add	x16, x17, x16
ffffffff80108e94: d1000651     	sub	x17, x18, #0x1
ffffffff80108e98: eb10017f     	cmp	x11, x16
ffffffff80108e9c: f903ed11     	str	x17, [x8, #0x7d8]
ffffffff80108ea0: 54fffd43     	b.lo	0xffffffff80108e48 <memory__pmm_init+0x2e8>
ffffffff80108ea4: 940033c4     	bl	0xffffffff80115db4 <memory__print_free>
ffffffff80108ea8: f9401aa8     	ldr	x8, [x21, #0x30]
ffffffff80108eac: f100811f     	cmp	x8, #0x20
ffffffff80108eb0: 54001063     	b.lo	0xffffffff801090bc <memory__pmm_init+0x55c>
ffffffff80108eb4: b0000729     	adrp	x9, 0xffffffff801ed000 <memory__heap_test_objects+0x3880>
ffffffff80108eb8: f944312a     	ldr	x10, [x9, #0x860]
ffffffff80108ebc: b500100a     	cbnz	x10, 0xffffffff801090bc <memory__pmm_init+0x55c>
ffffffff80108ec0: 928817ea     	mov	x10, #-0x40c0   // =-16576
ffffffff80108ec4: 5280020b     	mov	w11, #0x10      // =16
ffffffff80108ec8: 8b0a010a     	add	x10, x8, x10
ffffffff80108ecc: f904312b     	str	x11, [x9, #0x860]
ffffffff80108ed0: b140115f     	cmn	x10, #0x4, lsl #12 // =0x4000
ffffffff80108ed4: 54000fc3     	b.lo	0xffffffff801090cc <memory__pmm_init+0x56c>
ffffffff80108ed8: b0000729     	adrp	x9, 0xffffffff801ed000 <memory__heap_test_objects+0x3880>
ffffffff80108edc: f944512a     	ldr	x10, [x9, #0x8a0]
ffffffff80108ee0: b5000eea     	cbnz	x10, 0xffffffff801090bc <memory__pmm_init+0x55c>
ffffffff80108ee4: 5280040a     	mov	w10, #0x20      // =32
ffffffff80108ee8: f1033d1f     	cmp	x8, #0xcf
ffffffff80108eec: f904512a     	str	x10, [x9, #0x8a0]
ffffffff80108ef0: 54000ee9     	b.ls	0xffffffff801090cc <memory__pmm_init+0x56c>
ffffffff80108ef4: b0000729     	adrp	x9, 0xffffffff801ed000 <memory__heap_test_objects+0x3880>
ffffffff80108ef8: f944712a     	ldr	x10, [x9, #0x8e0]
ffffffff80108efc: b5000e0a     	cbnz	x10, 0xffffffff801090bc <memory__pmm_init+0x55c>
ffffffff80108f00: 5280060a     	mov	w10, #0x30      // =48
ffffffff80108f04: f1037d1f     	cmp	x8, #0xdf
ffffffff80108f08: f904712a     	str	x10, [x9, #0x8e0]
ffffffff80108f0c: 54000e09     	b.ls	0xffffffff801090cc <memory__pmm_init+0x56c>
ffffffff80108f10: b0000729     	adrp	x9, 0xffffffff801ed000 <memory__heap_test_objects+0x3880>
ffffffff80108f14: f944912a     	ldr	x10, [x9, #0x920]
ffffffff80108f18: b5000d2a     	cbnz	x10, 0xffffffff801090bc <memory__pmm_init+0x55c>
ffffffff80108f1c: 5280080a     	mov	w10, #0x40      // =64
ffffffff80108f20: f103bd1f     	cmp	x8, #0xef
ffffffff80108f24: f904912a     	str	x10, [x9, #0x920]
ffffffff80108f28: 54000d29     	b.ls	0xffffffff801090cc <memory__pmm_init+0x56c>
ffffffff80108f2c: b0000729     	adrp	x9, 0xffffffff801ed000 <memory__heap_test_objects+0x3880>
ffffffff80108f30: f944b12a     	ldr	x10, [x9, #0x960]
ffffffff80108f34: b5000c4a     	cbnz	x10, 0xffffffff801090bc <memory__pmm_init+0x55c>
ffffffff80108f38: 52800c0a     	mov	w10, #0x60      // =96
ffffffff80108f3c: f1043d1f     	cmp	x8, #0x10f
ffffffff80108f40: f904b12a     	str	x10, [x9, #0x960]
ffffffff80108f44: 54000c49     	b.ls	0xffffffff801090cc <memory__pmm_init+0x56c>
ffffffff80108f48: b0000729     	adrp	x9, 0xffffffff801ed000 <memory__heap_test_objects+0x3880>
ffffffff80108f4c: f944d12a     	ldr	x10, [x9, #0x9a0]
ffffffff80108f50: b5000b6a     	cbnz	x10, 0xffffffff801090bc <memory__pmm_init+0x55c>
ffffffff80108f54: 5280100a     	mov	w10, #0x80      // =128
ffffffff80108f58: f104bd1f     	cmp	x8, #0x12f
ffffffff80108f5c: f904d12a     	str	x10, [x9, #0x9a0]
ffffffff80108f60: 54000b69     	b.ls	0xffffffff801090cc <memory__pmm_init+0x56c>
ffffffff80108f64: f106011f     	cmp	x8, #0x180
ffffffff80108f68: 54000aa3     	b.lo	0xffffffff801090bc <memory__pmm_init+0x55c>
ffffffff80108f6c: b0000729     	adrp	x9, 0xffffffff801ed000 <memory__heap_test_objects+0x3880>
ffffffff80108f70: f944f129     	ldr	x9, [x9, #0x9e0]
ffffffff80108f74: b5000a49     	cbnz	x9, 0xffffffff801090bc <memory__pmm_init+0x55c>
ffffffff80108f78: 5280180a     	mov	w10, #0xc0      // =192
ffffffff80108f7c: f108011f     	cmp	x8, #0x200
ffffffff80108f80: b0000729     	adrp	x9, 0xffffffff801ed000 <memory__heap_test_objects+0x3880>
ffffffff80108f84: 91278129     	add	x9, x9, #0x9e0
ffffffff80108f88: f900012a     	str	x10, [x9]
ffffffff80108f8c: 54000983     	b.lo	0xffffffff801090bc <memory__pmm_init+0x55c>
ffffffff80108f90: f9402129     	ldr	x9, [x9, #0x40]
ffffffff80108f94: b5000949     	cbnz	x9, 0xffffffff801090bc <memory__pmm_init+0x55c>
ffffffff80108f98: 5280200a     	mov	w10, #0x100     // =256
ffffffff80108f9c: f10c011f     	cmp	x8, #0x300
ffffffff80108fa0: b0000729     	adrp	x9, 0xffffffff801ed000 <memory__heap_test_objects+0x3880>
ffffffff80108fa4: 91288129     	add	x9, x9, #0xa20
ffffffff80108fa8: f900012a     	str	x10, [x9]
ffffffff80108fac: 54000883     	b.lo	0xffffffff801090bc <memory__pmm_init+0x55c>
ffffffff80108fb0: f9402129     	ldr	x9, [x9, #0x40]
ffffffff80108fb4: b5000849     	cbnz	x9, 0xffffffff801090bc <memory__pmm_init+0x55c>
ffffffff80108fb8: 5280300a     	mov	w10, #0x180     // =384
ffffffff80108fbc: f110011f     	cmp	x8, #0x400
ffffffff80108fc0: b0000729     	adrp	x9, 0xffffffff801ed000 <memory__heap_test_objects+0x3880>
ffffffff80108fc4: 91298129     	add	x9, x9, #0xa60
ffffffff80108fc8: f900012a     	str	x10, [x9]
ffffffff80108fcc: 54000783     	b.lo	0xffffffff801090bc <memory__pmm_init+0x55c>
ffffffff80108fd0: f9402129     	ldr	x9, [x9, #0x40]
ffffffff80108fd4: b5000749     	cbnz	x9, 0xffffffff801090bc <memory__pmm_init+0x55c>
ffffffff80108fd8: 5280400a     	mov	w10, #0x200     // =512
ffffffff80108fdc: f118011f     	cmp	x8, #0x600
ffffffff80108fe0: b0000729     	adrp	x9, 0xffffffff801ed000 <memory__heap_test_objects+0x3880>
ffffffff80108fe4: 912a8129     	add	x9, x9, #0xaa0
ffffffff80108fe8: f900012a     	str	x10, [x9]
ffffffff80108fec: 54000683     	b.lo	0xffffffff801090bc <memory__pmm_init+0x55c>
ffffffff80108ff0: f9402129     	ldr	x9, [x9, #0x40]
ffffffff80108ff4: b5000649     	cbnz	x9, 0xffffffff801090bc <memory__pmm_init+0x55c>
ffffffff80108ff8: 5280600a     	mov	w10, #0x300     // =768
ffffffff80108ffc: f120011f     	cmp	x8, #0x800
ffffffff80109000: 90000729     	adrp	x9, 0xffffffff801ed000 <memory__heap_test_objects+0x3880>
ffffffff80109004: 912b8129     	add	x9, x9, #0xae0
ffffffff80109008: f900012a     	str	x10, [x9]
ffffffff8010900c: 54000583     	b.lo	0xffffffff801090bc <memory__pmm_init+0x55c>
ffffffff80109010: f9402129     	ldr	x9, [x9, #0x40]
ffffffff80109014: b5000549     	cbnz	x9, 0xffffffff801090bc <memory__pmm_init+0x55c>
ffffffff80109018: 5280800a     	mov	w10, #0x400     // =1024
ffffffff8010901c: f130011f     	cmp	x8, #0xc00
ffffffff80109020: 90000729     	adrp	x9, 0xffffffff801ed000 <memory__heap_test_objects+0x3880>
ffffffff80109024: 912c8129     	add	x9, x9, #0xb20
ffffffff80109028: f900012a     	str	x10, [x9]
ffffffff8010902c: 54000483     	b.lo	0xffffffff801090bc <memory__pmm_init+0x55c>
ffffffff80109030: f9402129     	ldr	x9, [x9, #0x40]
ffffffff80109034: b5000449     	cbnz	x9, 0xffffffff801090bc <memory__pmm_init+0x55c>
ffffffff80109038: 5280c009     	mov	w9, #0x600      // =1536
ffffffff8010903c: f140051f     	cmp	x8, #0x1, lsl #12 // =0x1000
ffffffff80109040: 90000728     	adrp	x8, 0xffffffff801ed000 <memory__heap_test_objects+0x3880>
ffffffff80109044: 912d8108     	add	x8, x8, #0xb60
ffffffff80109048: f9000109     	str	x9, [x8]
ffffffff8010904c: 54000383     	b.lo	0xffffffff801090bc <memory__pmm_init+0x55c>
ffffffff80109050: f9402108     	ldr	x8, [x8, #0x40]
ffffffff80109054: b5000348     	cbnz	x8, 0xffffffff801090bc <memory__pmm_init+0x55c>
ffffffff80109058: 90000728     	adrp	x8, 0xffffffff801ed000 <memory__heap_test_objects+0x3880>
ffffffff8010905c: 52810009     	mov	w9, #0x800      // =2048
ffffffff80109060: f905d109     	str	x9, [x8, #0xba0]
ffffffff80109064: 94002e5e     	bl	0xffffffff801149dc <memory__init_medium_slabs>
ffffffff80109068: f0000668     	adrp	x8, 0xffffffff801d8000 <halt_at_stage>
ffffffff8010906c: f85f83a9     	ldur	x9, [x29, #-0x8]
ffffffff80109070: f9417908     	ldr	x8, [x8, #0x2f0]
ffffffff80109074: eb09011f     	cmp	x8, x9
ffffffff80109078: 54000421     	b.ne	0xffffffff801090fc <memory__pmm_init+0x59c>
ffffffff8010907c: a9474ff4     	ldp	x20, x19, [sp, #0x70]
ffffffff80109080: f9401bfb     	ldr	x27, [sp, #0x30]
ffffffff80109084: a94657f6     	ldp	x22, x21, [sp, #0x60]
ffffffff80109088: a9455ff8     	ldp	x24, x23, [sp, #0x50]
ffffffff8010908c: a94467fa     	ldp	x26, x25, [sp, #0x40]
ffffffff80109090: a9427bfd     	ldp	x29, x30, [sp, #0x20]
ffffffff80109094: 910203ff     	add	sp, sp, #0x80
ffffffff80109098: 14002ae2     	b	0xffffffff80113c20 <memory__heap_selftest>
ffffffff8010909c: b00005e8     	adrp	x8, 0xffffffff801c6000 <a_guid_format.hex+0xeb5>
ffffffff801090a0: 9137b508     	add	x8, x8, #0xded
ffffffff801090a4: 52800209     	mov	w9, #0x10       // =16
ffffffff801090a8: a90027e8     	stp	x8, x9, [sp]
ffffffff801090ac: 52800028     	mov	w8, #0x1        // =1
ffffffff801090b0: 910003e0     	mov	x0, sp
ffffffff801090b4: f9000be8     	str	x8, [sp, #0x10]
ffffffff801090b8: 97fbdbd2     	bl	0xffffffff80000000 <v_panic>
ffffffff801090bc: d0000581     	adrp	x1, 0xffffffff801bb000 <_str_2114+0x55d0>
ffffffff801090c0: 9108ec21     	add	x1, x1, #0x23b
ffffffff801090c4: aa1f03e0     	mov	x0, xzr
ffffffff801090c8: 97fff3fe     	bl	0xffffffff801060c0 <lib__kpanic>
ffffffff801090cc: f00005a1     	adrp	x1, 0xffffffff801c0000 <_str_2114+0xa5d0>
ffffffff801090d0: 91347821     	add	x1, x1, #0xd1e
ffffffff801090d4: aa1f03e0     	mov	x0, xzr
ffffffff801090d8: 97fff3fa     	bl	0xffffffff801060c0 <lib__kpanic>
ffffffff801090dc: 900005a1     	adrp	x1, 0xffffffff801bd000 <_str_2114+0x75d0>
ffffffff801090e0: 9132b421     	add	x1, x1, #0xcad
ffffffff801090e4: aa1f03e0     	mov	x0, xzr
ffffffff801090e8: 97fff3f6     	bl	0xffffffff801060c0 <lib__kpanic>
ffffffff801090ec: d0000561     	adrp	x1, 0xffffffff801b7000 <_str_2114+0x15d0>
ffffffff801090f0: 91181821     	add	x1, x1, #0x606
ffffffff801090f4: aa1f03e0     	mov	x0, xzr
ffffffff801090f8: 97fff3f2     	bl	0xffffffff801060c0 <lib__kpanic>
ffffffff801090fc: 94028a0e     	bl	0xffffffff801ab934 <__stack_chk_fail>

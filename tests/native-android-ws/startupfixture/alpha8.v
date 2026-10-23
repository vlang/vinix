// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn alpha8_pixel(bitmap string, x int, y int, color string) string {
	return 'const/16 v0, ${x}\nconst/16 v1, ${y}\nconst v2, ${color}\n' +
		'invoke-static {${bitmap}, v0, v1, v2}, Lorg/vinix/bootstrap/Alpha8Probe;->pixel(Landroid/graphics/Bitmap;III)V\n'
}

fn install_alpha8_probe(dir string) ! {
	mut check := '
const/4 v0, 3
const/4 v1, 2
invoke-static {v0, v1}, Lorg/vinix/bootstrap/Alpha8Probe;->alpha(II)Landroid/graphics/Bitmap;
move-result-object v8
# Maps immediately wraps its ALPHA_8 mask in a Canvas.
new-instance v9, Landroid/graphics/Canvas;
invoke-direct {v9, v8}, Landroid/graphics/Canvas;-><init>(Landroid/graphics/Bitmap;)V
invoke-virtual {v8}, Landroid/graphics/Bitmap;->getRowBytes()I
move-result v0
const/4 v1, 4
if-ne v0, v1, :bad
invoke-virtual {v8}, Landroid/graphics/Bitmap;->getByteCount()I
move-result v0
const/16 v1, 8
if-ne v0, v1, :bad
const v0, 0x40123456
invoke-virtual {v8, v0}, Landroid/graphics/Bitmap;->eraseColor(I)V
'
	check += alpha8_pixel('v8', 0, 0, '0x40000000') + alpha8_pixel('v8', 2, 1, '0x40000000')
	check += '
const/4 v0, 3
new-array v1, v0, [I
fill-array-data v1, :source_colors
invoke-static {v8, v1}, Lorg/vinix/bootstrap/Alpha8Probe;->putRow(Landroid/graphics/Bitmap;[I)V
'
	check += alpha8_pixel('v8', 0, 0, '0x10000000') + alpha8_pixel('v8', 1, 0, '0x80000000') +
		alpha8_pixel('v8', 2, 0, '0xff000000') + alpha8_pixel('v8', 2, 1, '0x40000000')
	check += '
const v0, 0x40ffffff
invoke-virtual {v8, v0}, Landroid/graphics/Bitmap;->eraseColor(I)V
const/4 v0, 1
const/4 v1, 0
const/4 v2, 2
const/4 v3, 1
invoke-virtual {v9, v0, v1, v2, v3}, Landroid/graphics/Canvas;->clipRect(IIII)Z
new-instance v7, Landroid/graphics/Paint;
invoke-direct {v7}, Landroid/graphics/Paint;-><init>()V
const v0, 0x80123456
invoke-virtual {v7, v0}, Landroid/graphics/Paint;->setColor(I)V
move-object v0, v9
const/4 v1, 0
const/4 v2, 0
const/high16 v3, 0x40400000
const/high16 v4, 0x40000000
move-object v5, v7
invoke-virtual/range {v0 .. v5}, Landroid/graphics/Canvas;->drawRect(FFFFLandroid/graphics/Paint;)V
'
	check += alpha8_pixel('v8', 1, 0, '0x9f000000') + alpha8_pixel('v8', 0, 0, '0x40000000') +
		alpha8_pixel('v8', 2, 1, '0x40000000')
	check += '
const/4 v0, 3
const/4 v1, 2
sget-object v2, Landroid/graphics/Bitmap$Config;->ARGB_8888:Landroid/graphics/Bitmap$Config;
invoke-static {v0, v1, v2}, Landroid/graphics/Bitmap;->createBitmap(IILandroid/graphics/Bitmap$Config;)Landroid/graphics/Bitmap;
move-result-object v9
const/4 v0, 0
invoke-virtual {v9, v0}, Landroid/graphics/Bitmap;->eraseColor(I)V
new-instance v0, Landroid/graphics/Canvas;
invoke-direct {v0, v9}, Landroid/graphics/Canvas;-><init>(Landroid/graphics/Bitmap;)V
move-object v1, v8
const/4 v2, 0
const/4 v3, 0
move-object v4, v7
const v5, 0x80336699
invoke-virtual {v7, v5}, Landroid/graphics/Paint;->setColor(I)V
invoke-virtual {v0, v1, v2, v3, v4}, Landroid/graphics/Canvas;->drawBitmap(Landroid/graphics/Bitmap;FFLandroid/graphics/Paint;)V
'
	check += alpha8_pixel('v9', 1, 0, '0x4f336699') + alpha8_pixel('v9', 0, 0, '0x20336699') +
		alpha8_pixel('v9', 2, 1, '0x20336699')
	check += '
invoke-virtual {v9}, Landroid/graphics/Bitmap;->getRowBytes()I
move-result v0
const/16 v1, 12
if-ne v0, v1, :bad
invoke-virtual {v9}, Landroid/graphics/Bitmap;->recycle()V
invoke-virtual {v8}, Landroid/graphics/Bitmap;->recycle()V
# Overlapping self-copy must read an unchanged source mask.
const/4 v0, 3
const/4 v1, 1
invoke-static {v0, v1}, Lorg/vinix/bootstrap/Alpha8Probe;->alpha(II)Landroid/graphics/Bitmap;
move-result-object v8
const/4 v0, 3
new-array v1, v0, [I
fill-array-data v1, :self_colors
invoke-static {v8, v1}, Lorg/vinix/bootstrap/Alpha8Probe;->putRow(Landroid/graphics/Bitmap;[I)V
new-instance v0, Landroid/graphics/Canvas;
invoke-direct {v0, v8}, Landroid/graphics/Canvas;-><init>(Landroid/graphics/Bitmap;)V
const/high16 v2, 0x3f800000
const/4 v3, 0
const/4 v4, 0
invoke-virtual {v0, v8, v2, v3, v4}, Landroid/graphics/Canvas;->drawBitmap(Landroid/graphics/Bitmap;FFLandroid/graphics/Paint;)V
'
	check += alpha8_pixel('v8', 0, 0, '0x80000000') + alpha8_pixel('v8', 1, 0, '0x80000000') +
		alpha8_pixel('v8', 2, 0, '0')
	check += '
invoke-virtual {v8}, Landroid/graphics/Bitmap;->recycle()V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-ALPHA8-PASS padded-stride byte-count erase get-set-pixels source-over clip paint-tinted-mask ARGB-preserved self-copy"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "ALPHA_8 storage, mask rendering or overlapping copy"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:source_colors
.array-data 4
0x10010203
0x80abcdef
0xff336699
.end array-data
:self_colors
.array-data 4
0x80010203
0
0
.end array-data
'
	text := '.class public Lorg/vinix/bootstrap/Alpha8Probe;\n.super Ljava/lang/Object;\n' +
		method('public static check()V', check) +
		method('private static alpha(II)Landroid/graphics/Bitmap;', '
sget-object v0, Landroid/graphics/Bitmap$Config;->ALPHA_8:Landroid/graphics/Bitmap$Config;
invoke-static {p0, p1, v0}, Landroid/graphics/Bitmap;->createBitmap(IILandroid/graphics/Bitmap$Config;)Landroid/graphics/Bitmap;
move-result-object v0
return-object v0') + method('private static putRow(Landroid/graphics/Bitmap;[I)V', '
move-object v0, p0
move-object v1, p1
const/4 v2, 0
invoke-virtual {p0}, Landroid/graphics/Bitmap;->getWidth()I
move-result v3
const/4 v4, 0
const/4 v5, 0
move v6, v3
const/4 v7, 1
invoke-virtual/range {v0 .. v7}, Landroid/graphics/Bitmap;->setPixels([IIIIIII)V
return-void') + method('private static pixel(Landroid/graphics/Bitmap;III)V', '
const/4 v0, 1
new-array v1, v0, [I
move-object v0, p0
const/4 v2, 0
const/4 v3, 1
move v4, p1
move v5, p2
const/4 v6, 1
const/4 v7, 1
invoke-virtual/range {v0 .. v7}, Landroid/graphics/Bitmap;->getPixels([IIIIIII)V
aget v0, v1, v2
if-ne v0, p3, :bad
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "ALPHA_8 expected pixel"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0') + alpha8_gl_methods()
	os.write_file(dir + '/Alpha8Probe.smali', text)!
}

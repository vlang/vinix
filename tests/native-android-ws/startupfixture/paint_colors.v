// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_paint_color_probe(dir string) ! {
 mut check := 'new-instance v0, Landroid/graphics/Paint;\ninvoke-direct {v0}, Landroid/graphics/Paint;-><init>()V\n'
 for color in ['0', '0xff17395b', '0x7fabcdef', '0xffffffff'] {
  check += 'const v1, ${color}\nint-to-long v2, v1\nconst/16 v4, 32\nshl-long/2addr v2, v4\n' +
   'invoke-virtual {v0, v2, v3}, Landroid/graphics/Paint;->setColor(J)V\n' +
   'invoke-static {v0, v1}, Lorg/vinix/bootstrap/PaintColorProbe;->expect(Landroid/graphics/Paint;I)V\n'
 }
 check += '
const/16 v1, 64
invoke-virtual {v0, v1}, Landroid/graphics/Paint;->setAlpha(I)V
const v1, 0x40ffffff
invoke-static {v0, v1}, Lorg/vinix/bootstrap/PaintColorProbe;->expect(Landroid/graphics/Paint;I)V
new-instance v2, Landroid/graphics/Paint;
invoke-direct {v2, v0}, Landroid/graphics/Paint;-><init>(Landroid/graphics/Paint;)V
invoke-static {v2, v1}, Lorg/vinix/bootstrap/PaintColorProbe;->expect(Landroid/graphics/Paint;I)V
invoke-virtual {v2}, Landroid/graphics/Paint;->reset()V
const v1, 0xff000000
invoke-static {v2, v1}, Lorg/vinix/bootstrap/PaintColorProbe;->expect(Landroid/graphics/Paint;I)V
const-wide/16 v2, 1
:unsupported_begin
invoke-virtual {v0, v2, v3}, Landroid/graphics/Paint;->setColor(J)V
:unsupported_end
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "Non-sRGB half floats must not be misinterpreted as ARGB"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:unsupported
move-exception v1
const v1, 0x40ffffff
invoke-static {v0, v1}, Lorg/vinix/bootstrap/PaintColorProbe;->expect(Landroid/graphics/Paint;I)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-PAINT-COLOR-LONG-PASS sRGB alpha copy reset pixels unsupported-space"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
.catch Ljava/lang/UnsupportedOperationException; {:unsupported_begin .. :unsupported_end} :unsupported
'
 os.write_file(dir + '/PaintColorProbe.smali', '.class public Lorg/vinix/bootstrap/PaintColorProbe;\n.super Ljava/lang/Object;\n' +
  method('public static check()V', check) + method('private static expect(Landroid/graphics/Paint;I)V', '
invoke-virtual {p0}, Landroid/graphics/Paint;->getColor()I
move-result v0
if-ne v0, p1, :bad
invoke-virtual {p0}, Landroid/graphics/Paint;->getColorLong()J
move-result-wide v0
int-to-long v2, p1
const/16 v4, 32
shl-long/2addr v2, v4
cmp-long v0, v0, v2
if-nez v0, :bad
const/4 v0, 2
sget-object v1, Landroid/graphics/Bitmap$Config;->ARGB_8888:Landroid/graphics/Bitmap$Config;
invoke-static {v0, v0, v1}, Landroid/graphics/Bitmap;->createBitmap(IILandroid/graphics/Bitmap$Config;)Landroid/graphics/Bitmap;
move-result-object v0
new-instance v1, Landroid/graphics/Canvas;
invoke-direct {v1, v0}, Landroid/graphics/Canvas;-><init>(Landroid/graphics/Bitmap;)V
move-object v2, v1
const/4 v3, 0
const/4 v4, 0
const/high16 v5, 0x40000000
const/high16 v6, 0x40000000
move-object v7, p0
invoke-virtual/range {v2 .. v7}, Landroid/graphics/Canvas;->drawRect(FFFFLandroid/graphics/Paint;)V
const/4 v1, 1
new-array v1, v1, [I
move-object v2, v0
move-object v3, v1
const/4 v4, 0
const/4 v5, 1
const/4 v6, 0
const/4 v7, 0
const/4 v8, 1
const/4 v9, 1
invoke-virtual/range {v2 .. v9}, Landroid/graphics/Bitmap;->getPixels([IIIIIII)V
const/4 v2, 0
aget v0, v1, v2
if-ne v0, p1, :bad
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "Paint color-long storage or rendered pixel"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'))!
}

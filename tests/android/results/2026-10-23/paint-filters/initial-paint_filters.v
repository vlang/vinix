// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_paint_filters_probe(dir string) ! {
	probe := 'Lorg/vinix/bootstrap/PaintFiltersProbe;'
	os.write_file(dir + '/PaintFiltersProbe.smali', '.class public ${probe}\n.super Ljava/lang/Object;\n' +
		method('public static check()V', '
const/4 v0, 2
const/4 v1, 1
sget-object v2, Landroid/graphics/Bitmap$Config;->ARGB_8888:Landroid/graphics/Bitmap$Config;
invoke-static {v0, v1, v2}, Landroid/graphics/Bitmap;->createBitmap(IILandroid/graphics/Bitmap$Config;)Landroid/graphics/Bitmap;
move-result-object v8
const/4 v0, 2
new-array v1, v0, [I
fill-array-data v1, :source_colors
move-object v0, v8
const/4 v2, 0
const/4 v3, 2
const/4 v4, 0
const/4 v5, 0
const/4 v6, 2
const/4 v7, 1
invoke-virtual/range {v0 .. v7}, Landroid/graphics/Bitmap;->setPixels([IIIIIII)V
new-instance v9, Landroid/graphics/Paint;
invoke-direct {v9}, Landroid/graphics/Paint;-><init>()V
# The legacy filter is the reference for the Compose BlendMode filter.
new-instance v0, Landroid/graphics/PorterDuffColorFilter;
const v1, 0xff336699
sget-object v2, Landroid/graphics/PorterDuff$Mode;->SRC_IN:Landroid/graphics/PorterDuff$Mode;
invoke-direct {v0, v1, v2}, Landroid/graphics/PorterDuffColorFilter;-><init>(ILandroid/graphics/PorterDuff$Mode;)V
invoke-virtual {v9, v0}, Landroid/graphics/Paint;->setColorFilter(Landroid/graphics/ColorFilter;)Landroid/graphics/ColorFilter;
invoke-static {v8, v9}, ${probe}->render(Landroid/graphics/Bitmap;Landroid/graphics/Paint;)Landroid/graphics/Bitmap;
move-result-object v6
const v0, 0xff336699
const v1, 0x80336699
invoke-static {v6, v0, v1}, ${probe}->pixels(Landroid/graphics/Bitmap;II)V
invoke-virtual {v6}, Landroid/graphics/Bitmap;->recycle()V
new-instance v0, Landroid/graphics/BlendModeColorFilter;
const v1, 0xff336699
sget-object v2, Landroid/graphics/BlendMode;->SRC_IN:Landroid/graphics/BlendMode;
invoke-direct {v0, v1, v2}, Landroid/graphics/BlendModeColorFilter;-><init>(ILandroid/graphics/BlendMode;)V
invoke-virtual {v9, v0}, Landroid/graphics/Paint;->setColorFilter(Landroid/graphics/ColorFilter;)Landroid/graphics/ColorFilter;
invoke-virtual {v9}, Landroid/graphics/Paint;->getColorFilter()Landroid/graphics/ColorFilter;
move-result-object v1
if-ne v0, v1, :bad
invoke-static {v8, v9}, ${probe}->render(Landroid/graphics/Bitmap;Landroid/graphics/Paint;)Landroid/graphics/Bitmap;
move-result-object v6
const v0, 0xff336699
const v1, 0x80336699
invoke-static {v6, v0, v1}, ${probe}->pixels(Landroid/graphics/Bitmap;II)V
invoke-virtual {v6}, Landroid/graphics/Bitmap;->recycle()V
# Clearing the filter restores both source color and source alpha.
const/4 v0, 0
invoke-virtual {v9, v0}, Landroid/graphics/Paint;->setColorFilter(Landroid/graphics/ColorFilter;)Landroid/graphics/ColorFilter;
invoke-virtual {v9}, Landroid/graphics/Paint;->getColorFilter()Landroid/graphics/ColorFilter;
move-result-object v0
if-nez v0, :bad
invoke-static {v8, v9}, ${probe}->render(Landroid/graphics/Bitmap;Landroid/graphics/Paint;)Landroid/graphics/Bitmap;
move-result-object v6
const v0, 0xff123456
const v1, 0x80123456
invoke-static {v6, v0, v1}, ${probe}->pixels(Landroid/graphics/Bitmap;II)V
invoke-virtual {v6}, Landroid/graphics/Bitmap;->recycle()V
# A translucent replacement multiplies the filter and source alpha.
new-instance v0, Landroid/graphics/BlendModeColorFilter;
const v1, 0x80cc5522
sget-object v2, Landroid/graphics/BlendMode;->SRC_IN:Landroid/graphics/BlendMode;
invoke-direct {v0, v1, v2}, Landroid/graphics/BlendModeColorFilter;-><init>(ILandroid/graphics/BlendMode;)V
invoke-virtual {v9, v0}, Landroid/graphics/Paint;->setColorFilter(Landroid/graphics/ColorFilter;)Landroid/graphics/ColorFilter;
invoke-static {v8, v9}, ${probe}->render(Landroid/graphics/Bitmap;Landroid/graphics/Paint;)Landroid/graphics/Bitmap;
move-result-object v6
const v0, 0x80cc5522
const v1, 0x40cc5522
invoke-static {v6, v0, v1}, ${probe}->pixels(Landroid/graphics/Bitmap;II)V
invoke-virtual {v6}, Landroid/graphics/Bitmap;->recycle()V
# Reassigning a legacy filter must replace the modern filter too.
new-instance v0, Landroid/graphics/PorterDuffColorFilter;
const v1, 0xff22cc77
sget-object v2, Landroid/graphics/PorterDuff$Mode;->SRC_IN:Landroid/graphics/PorterDuff$Mode;
invoke-direct {v0, v1, v2}, Landroid/graphics/PorterDuffColorFilter;-><init>(ILandroid/graphics/PorterDuff$Mode;)V
invoke-virtual {v9, v0}, Landroid/graphics/Paint;->setColorFilter(Landroid/graphics/ColorFilter;)Landroid/graphics/ColorFilter;
invoke-static {v8, v9}, ${probe}->render(Landroid/graphics/Bitmap;Landroid/graphics/Paint;)Landroid/graphics/Bitmap;
move-result-object v6
const v0, 0xff22cc77
const v1, 0x8022cc77
invoke-static {v6, v0, v1}, ${probe}->pixels(Landroid/graphics/Bitmap;II)V
invoke-virtual {v6}, Landroid/graphics/Bitmap;->recycle()V
invoke-virtual {v8}, Landroid/graphics/Bitmap;->recycle()V
# Compose tints an ALPHA_8 cached vector mask with the same filter.
const/4 v0, 2
const/4 v1, 1
sget-object v2, Landroid/graphics/Bitmap$Config;->ALPHA_8:Landroid/graphics/Bitmap$Config;
invoke-static {v0, v1, v2}, Landroid/graphics/Bitmap;->createBitmap(IILandroid/graphics/Bitmap$Config;)Landroid/graphics/Bitmap;
move-result-object v8
const v0, 0x80123456
invoke-virtual {v8, v0}, Landroid/graphics/Bitmap;->eraseColor(I)V
new-instance v0, Landroid/graphics/BlendModeColorFilter;
const v1, 0xff336699
sget-object v2, Landroid/graphics/BlendMode;->SRC_IN:Landroid/graphics/BlendMode;
invoke-direct {v0, v1, v2}, Landroid/graphics/BlendModeColorFilter;-><init>(ILandroid/graphics/BlendMode;)V
invoke-virtual {v9, v0}, Landroid/graphics/Paint;->setColorFilter(Landroid/graphics/ColorFilter;)Landroid/graphics/ColorFilter;
invoke-static {v8, v9}, ${probe}->render(Landroid/graphics/Bitmap;Landroid/graphics/Paint;)Landroid/graphics/Bitmap;
move-result-object v6
const v0, 0x80336699
invoke-static {v6, v0, v0}, ${probe}->pixels(Landroid/graphics/Bitmap;II)V
invoke-virtual {v6}, Landroid/graphics/Bitmap;->recycle()V
invoke-virtual {v8}, Landroid/graphics/Bitmap;->recycle()V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-PAINT-FILTERS-PASS SRC_IN porter-duff-equivalence opaque partial-alpha getter clear translucent-reassign legacy-reassign ALPHA_8-mask"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "Paint color filter identity"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:source_colors
.array-data 4
0xff123456
0x80123456
.end array-data') + method('private static render(Landroid/graphics/Bitmap;Landroid/graphics/Paint;)Landroid/graphics/Bitmap;', '
const/4 v0, 2
const/4 v1, 1
sget-object v2, Landroid/graphics/Bitmap$Config;->ARGB_8888:Landroid/graphics/Bitmap$Config;
invoke-static {v0, v1, v2}, Landroid/graphics/Bitmap;->createBitmap(IILandroid/graphics/Bitmap$Config;)Landroid/graphics/Bitmap;
move-result-object v6
const/4 v0, 0
invoke-virtual {v6, v0}, Landroid/graphics/Bitmap;->eraseColor(I)V
new-instance v0, Landroid/graphics/Canvas;
invoke-direct {v0, v6}, Landroid/graphics/Canvas;-><init>(Landroid/graphics/Bitmap;)V
const/4 v1, 0
invoke-virtual {v0, p0, v1, v1, p1}, Landroid/graphics/Canvas;->drawBitmap(Landroid/graphics/Bitmap;FFLandroid/graphics/Paint;)V
return-object v6') + method('private static pixels(Landroid/graphics/Bitmap;II)V', '
const/4 v0, 2
new-array v1, v0, [I
move-object v0, p0
const/4 v2, 0
const/4 v3, 2
const/4 v4, 0
const/4 v5, 0
const/4 v6, 2
const/4 v7, 1
invoke-virtual/range {v0 .. v7}, Landroid/graphics/Bitmap;->getPixels([IIIIIII)V
aget v0, v1, v2
if-ne v0, p1, :bad
const/4 v2, 1
aget v0, v1, v2
if-ne v0, p2, :bad
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "SRC_IN filtered bitmap pixel"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'))!
}

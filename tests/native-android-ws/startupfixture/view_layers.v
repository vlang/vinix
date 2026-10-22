// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_view_layer_probe(dir string) ! {
	os.write_file(dir + '/LayerLeaf.smali', '.class public Lorg/vinix/bootstrap/LayerLeaf;\n.super Landroid/view/View;\n.field public failure:Ljava/lang/RuntimeException;\n' +
		method('public constructor <init>(Landroid/content/Context;)V', 'invoke-direct {p0, p1}, Landroid/view/View;-><init>(Landroid/content/Context;)V\nreturn-void') +
		method('public draw(Landroid/graphics/Canvas;)V', '
iget-object v0, p0, Lorg/vinix/bootstrap/LayerLeaf;->failure:Ljava/lang/RuntimeException;
if-eqz v0, :paint
const/high16 v1, 0x3f800000
invoke-virtual {p1, v1, v1}, Landroid/graphics/Canvas;->translate(FF)V
throw v0
:paint
new-instance v5, Landroid/graphics/Paint;
invoke-direct {v5}, Landroid/graphics/Paint;-><init>()V
const v0, 0xffff0000
invoke-virtual {v5, v0}, Landroid/graphics/Paint;->setColor(I)V
move-object v0, p1
const/4 v1, 0
const/4 v2, 0
const/high16 v3, 0x40400000
const/high16 v4, 0x40800000
invoke-virtual/range {v0 .. v5}, Landroid/graphics/Canvas;->drawRect(FFFFLandroid/graphics/Paint;)V
const v0, 0xff0000ff
invoke-virtual {v5, v0}, Landroid/graphics/Paint;->setColor(I)V
move-object v0, p1
const/high16 v1, 0x40000000
const/high16 v3, 0x40800000
invoke-virtual/range {v0 .. v5}, Landroid/graphics/Canvas;->drawRect(FFFFLandroid/graphics/Paint;)V
return-void'))!
	mut check := '
new-instance v0, Landroid/widget/FrameLayout;
invoke-direct {v0, p0}, Landroid/widget/FrameLayout;-><init>(Landroid/content/Context;)V
new-instance v1, Lorg/vinix/bootstrap/LayerLeaf;
invoke-direct {v1, p0}, Lorg/vinix/bootstrap/LayerLeaf;-><init>(Landroid/content/Context;)V
invoke-virtual {v1}, Landroid/view/View;->getLayerType()I
move-result v2
if-nez v2, :bad
invoke-virtual {v0, v1}, Landroid/view/ViewGroup;->addView(Landroid/view/View;)V
const/4 v2, 0
const/4 v3, 4
invoke-virtual {v0, v2, v2, v3, v3}, Landroid/view/View;->layout(IIII)V
invoke-virtual {v1, v2, v2, v3, v3}, Landroid/view/View;->layout(IIII)V
new-instance v2, Landroid/graphics/Paint;
invoke-direct {v2}, Landroid/graphics/Paint;-><init>()V
const/16 v3, 128
invoke-virtual {v2, v3}, Landroid/graphics/Paint;->setAlpha(I)V
'
	// Identical overlapping content must be composited once for both requested
	// layer types. NONE ignores the layer paint. Every iteration checks pixels.
	for index, kind in [1, 2, 0, 1] {
		check += '
const/4 v3, ${kind}
invoke-virtual {v1, v3, v2}, Landroid/view/View;->setLayerType(ILandroid/graphics/Paint;)V
invoke-virtual {v1}, Landroid/view/View;->getLayerType()I
move-result v4
if-ne v3, v4, :bad
invoke-virtual {v0}, Landroid/view/View;->getLayerType()I
move-result v4
if-nez v4, :bad
const v3, ${if kind == 0 { '0xffff0000' } else { '0x80ff0000' }}
const v4, ${if kind == 0 { '0xff0000ff' } else { '0x800000ff' }}
invoke-static {v0, v3, v4}, Lorg/vinix/bootstrap/ViewLayerProbe;->pixels(Landroid/view/View;II)V
'
		if index == 0 {
			check += '
# Paint replacement changes composition on an already allocated layer.
const/4 v3, 0
invoke-virtual {v1, v3}, Landroid/view/View;->setLayerPaint(Landroid/graphics/Paint;)V
const v3, 0xffff0000
const v4, 0xff0000ff
invoke-static {v0, v3, v4}, Lorg/vinix/bootstrap/ViewLayerProbe;->pixels(Landroid/view/View;II)V
invoke-virtual {v1, v2}, Landroid/view/View;->setLayerPaint(Landroid/graphics/Paint;)V
'
		}
	}
	for index, kind in [-1, 3] {
		check += '
const/4 v3, ${kind}
:invalid_start${index}
invoke-virtual {v1, v3, v2}, Landroid/view/View;->setLayerType(ILandroid/graphics/Paint;)V
:invalid_end${index}
.catch Ljava/lang/IllegalArgumentException; {:invalid_start${index} .. :invalid_end${index}} :invalid_caught${index}
goto :bad
:invalid_caught${index}
move-exception v3
invoke-virtual {v1}, Landroid/view/View;->getLayerType()I
move-result v3
const/4 v4, 1
if-ne v3, v4, :bad
'
	}
	check += '
# An exception after changing the layer canvas must preserve the throwable and
# leave the cached canvas usable for the following frame.
new-instance v3, Ljava/lang/IllegalStateException;
const-string v4, "expected layered draw failure"
invoke-direct {v3, v4}, Ljava/lang/IllegalStateException;-><init>(Ljava/lang/String;)V
iput-object v3, v1, Lorg/vinix/bootstrap/LayerLeaf;->failure:Ljava/lang/RuntimeException;
:draw_start
const v4, 0x80ff0000
const v5, 0x800000ff
invoke-static {v0, v4, v5}, Lorg/vinix/bootstrap/ViewLayerProbe;->pixels(Landroid/view/View;II)V
:draw_end
.catch Ljava/lang/RuntimeException; {:draw_start .. :draw_end} :draw_caught
goto :bad
:draw_caught
move-exception v4
if-ne v3, v4, :bad
const/4 v3, 0
iput-object v3, v1, Lorg/vinix/bootstrap/LayerLeaf;->failure:Ljava/lang/RuntimeException;
const v4, 0x80ff0000
const v5, 0x800000ff
invoke-static {v0, v4, v5}, Lorg/vinix/bootstrap/ViewLayerProbe;->pixels(Landroid/view/View;II)V
# Resize the same view; old pixels and storage dimensions must not survive.
const/4 v4, 2
invoke-virtual {v1, v3, v3, v4, v4}, Landroid/view/View;->layout(IIII)V
const v4, 0x80ff0000
const/4 v5, 0
invoke-static {v0, v4, v5}, Lorg/vinix/bootstrap/ViewLayerProbe;->pixels(Landroid/view/View;II)V
const/4 v4, 4
invoke-virtual {v1, v3, v3, v4, v4}, Landroid/view/View;->layout(IIII)V
const v4, 0x80ff0000
const v5, 0x800000ff
invoke-static {v0, v4, v5}, Lorg/vinix/bootstrap/ViewLayerProbe;->pixels(Landroid/view/View;II)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-VIEW-LAYERS-PASS state validation virtual-draw alpha overlap paint fallback reuse resize exception-recovery"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "View layer state or exception identity"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'
	os.write_file(dir + '/ViewLayerProbe.smali', '.class public Lorg/vinix/bootstrap/ViewLayerProbe;\n.super Ljava/lang/Object;\n' +
		method('public static check(Landroid/content/Context;)V', check) +
		method('private static pixels(Landroid/view/View;II)V', '
const/4 v0, 4
sget-object v1, Landroid/graphics/Bitmap$Config;->ARGB_8888:Landroid/graphics/Bitmap$Config;
invoke-static {v0, v0, v1}, Landroid/graphics/Bitmap;->createBitmap(IILandroid/graphics/Bitmap$Config;)Landroid/graphics/Bitmap;
move-result-object v8
new-instance v9, Landroid/graphics/Canvas;
invoke-direct {v9, v8}, Landroid/graphics/Canvas;-><init>(Landroid/graphics/Bitmap;)V
:start
invoke-virtual {p0, v9}, Landroid/view/View;->draw(Landroid/graphics/Canvas;)V
const/16 v0, 16
new-array v1, v0, [I
move-object v0, v8
const/4 v2, 0
const/4 v3, 4
const/4 v4, 0
const/4 v5, 0
const/4 v6, 4
const/4 v7, 4
invoke-virtual/range {v0 .. v7}, Landroid/graphics/Bitmap;->getPixels([IIIIIII)V
const/4 v0, 0
aget v2, v1, v0
if-ne v2, p1, :bad
const/4 v0, 2
aget v2, v1, v0
if-ne v2, p2, :bad
:end
.catchall {:start .. :end} :failed
invoke-virtual {v8}, Landroid/graphics/Bitmap;->recycle()V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "View layer pixel composition"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:failed
move-exception v0
invoke-virtual {v8}, Landroid/graphics/Bitmap;->recycle()V
throw v0'))!
}
